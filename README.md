# Roblox RV32IM Emulator

RISC-V emulator that runs entirely inside Roblox. Written in Luau. No external servers, no HTTP, nothing leaves the client.

Implements the full RV32IM instruction set (base integer + multiply/divide). Comes with a built-in assembler and a fullscreen IDE so you can write and run assembly right in-game.

## What this is

When you join the game there's no character, no world, just the code editor. You write RISC-V assembly, click Run, and it assembles + executes your code right there. Output shows up in the terminal below.

There are tabs for switching between different programs, and after your code runs you can check the register and memory state.

## The Assembler

`Parser.lua` handles turning your text into something the CPU can run. It does two passes over the source.

First pass goes through every line and figures out where things live in memory. It builds a table of all your labels and their addresses, handles `.text` and `.data` sections, processes directives like `.ascii`, `.word`, `.space`, `.byte`. Pseudo-instructions get expanded here too so the address math stays correct. Something like `li` with a big value turns into a `lui` + `addi` pair, which takes up two instruction slots instead of one.

Second pass takes the expanded instructions and actually encodes them. Label references get resolved into real offsets or addresses depending on what kind of instruction it is. Branches use PC-relative offsets, `lui`/`auipc` sequences use absolute addresses.

### RV32I Instructions

| Category | Instructions | Format |
|----------|-------------|--------|
| Arithmetic | `add`, `sub` | R-type: op rd, rs1, rs2 |
| Arithmetic Immediate | `addi`, `slti`, `sltiu` | I-type: op rd, rs1, imm |
| Logical | `and`, `or`, `xor` | R-type: op rd, rs1, rs2 |
| Logical Immediate | `andi`, `ori`, `xori` | I-type: op rd, rs1, imm |
| Shifts | `sll`, `srl`, `sra` | R-type: op rd, rs1, rs2 |
| Shift Immediate | `slli`, `srli`, `srai` | I-type: op rd, rs1, imm |
| Compare | `slt`, `sltu` | R-type: op rd, rs1, rs2 |
| Load | `lb`, `lh`, `lw`, `lbu`, `lhu` | I-type: op rd, offset(rs1) |
| Store | `sb`, `sh`, `sw` | S-type: op rs2, offset(rs1) |
| Branch | `beq`, `bne`, `blt`, `bge`, `bltu`, `bgeu` | B-type: op rs1, rs2, label |
| Upper Immediate | `lui`, `auipc` | U-type: op rd, imm |
| Jump | `jal`, `jalr` | J/I-type: op rd, label/offset |
| System | `ecall`, `ebreak`, `fence` | |

### RV32M Extension (Multiply/Divide)

| Instruction | What it does |
|-------------|-------------|
| `mul` | rd = (rs1 * rs2)[31:0], lower 32 bits |
| `mulh` | rd = (rs1 * rs2)[63:32], signed x signed upper bits |
| `mulhsu` | rd = (rs1 * rs2)[63:32], signed x unsigned |
| `mulhu` | rd = (rs1 * rs2)[63:32], unsigned x unsigned |
| `div` | signed division, truncates toward zero |
| `divu` | unsigned division |
| `rem` | signed remainder, sign matches dividend |
| `remu` | unsigned remainder |

### Pseudo-instructions

These get expanded by the assembler into real instructions.

| Pseudo | Expands to |
|--------|-----------|
| `li rd, imm` | `addi` if small, `lui` + `addi` if large |
| `la rd, label` | `auipc` + `addi` |
| `mv rd, rs` | `addi rd, rs, 0` |
| `j label` | `jal x0, label` |
| `jr rs` | `jalr x0, rs, 0` |
| `call label` | `auipc ra` + `jalr ra` |
| `ret` | `jalr x0, ra, 0` |
| `nop` | `addi x0, x0, 0` |
| `not rd, rs` | `xori rd, rs, -1` |
| `neg rd, rs` | `sub rd, x0, rs` |
| `beqz rs, label` | `beq rs, x0, label` |
| `bnez rs, label` | `bne rs, x0, label` |
| `bgt`, `ble`, `bgtu`, `bleu` | swapped-operand branches |
| `tail label` | `auipc t1` + `jalr x0, t1` |

### Data Directives

| Directive | What it does |
|-----------|-------------|
| `.text` | Switch to code section |
| `.data` / `.section .data` | Switch to data section |
| `.globl label` | Mark a label as global (parsed but no effect in this emulator) |
| `.ascii "str"` | Store raw string bytes |
| `.asciz "str"` / `.string "str"` | Store string with null terminator |
| `.byte val, ...` | Store individual bytes |
| `.half val, ...` | Store 16-bit values |
| `.word val, ...` | Store 32-bit values |
| `.space n` | Reserve n zero bytes |
| `.align n` | Align to 2^n byte boundary |
| `.equ name, val` | Define a constant |

### Registers

All 32 registers, both by number and ABI name.

| Register | ABI Name | Usage |
|----------|----------|-------|
| x0 | zero | always 0 |
| x1 | ra | return address |
| x2 | sp | stack pointer |
| x3 | gp | global pointer |
| x4 | tp | thread pointer |
| x5-x7 | t0-t2 | temporaries |
| x8 | s0/fp | saved register / frame pointer |
| x9 | s1 | saved register |
| x10-x11 | a0-a1 | function args / return values |
| x12-x17 | a2-a7 | function args |
| x18-x27 | s2-s11 | saved registers |
| x28-x31 | t3-t6 | temporaries |

## The CPU

`CPU.lua` is the execution engine. Pretty standard fetch-decode-execute loop.

It has 32 integer registers (x0 is hardwired to zero), a program counter, and byte-addressable memory stored as a Lua table keyed by address.

Each cycle: read the instruction at PC, figure out what it does, do it, write back the result, bump PC forward. Branches and jumps just set PC directly.

One thing worth knowing: Luau uses 64-bit floats internally, not integers. So the CPU has to be careful about keeping everything in 32-bit range. It uses `bit32` for unsigned operations and manual sign extension for signed ones.

The multiply instructions are the trickiest part. `mulh`, `mulhsu`, `mulhu` need the upper 32 bits of a 64-bit product. Can't just multiply two numbers and grab the top half because float precision will eat some bits. Instead it splits operands into 16-bit halves and does partial products by hand to keep everything exact.

Division follows the RISC-V spec (C99 semantics). Truncation toward zero. Division by zero returns -1 or max unsigned. Overflow case (-2^31 / -1) returns -2^31.

Execution caps out at 1,000,000 instructions so infinite loops don't lock up the client.

## Syscalls

Programs talk to the host using `ecall`. Two syscalls are supported:

| Syscall | Number | Registers | What it does |
|---------|--------|-----------|-------------|
| write | 64 | a0=fd, a1=buf, a2=len | Writes bytes from memory to the terminal. fd=1 for stdout |
| exit | 93 | a0=exit_code | Stops execution |

Same ABI as Linux RISC-V. If you have a simple program that runs on QEMU with just these two syscalls, it'll run here too.

## Project structure

```
src/
  Client/
    EmulatorUI.client.lua   - the IDE, runs on client
  Main.server.lua           - optional server-side runner for headless testing
  RiscV/
    CPU.lua                 - execution engine
    Parser.lua              - assembler
    Spec.lua                - instruction encoding tables, register maps
    Programs.lua            - built-in test programs
    UserPrograms.lua        - example programs that show up as tabs in the IDE
```

## Example programs included

- HelloWorld: basic write syscall
- Fib2: iterative fibonacci
- Factorial: recursive, computes 7!
- BubbleSort: sorts an array, prints it
- SierpinskiTriangle: renders the triangle with bitwise ops
- GCD: euclidean algorithm
- Divide: integer division, prints quotient and remainder
- Mul2: multiplication test

## What's not here

- No floating point (no RV32F/D)
- No real CSR support
- No interrupts or exceptions beyond ecall
- No MMU
- No persistance
