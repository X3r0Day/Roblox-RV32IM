-- ModuleScript: RiscV/UserPrograms.lua
-- ============================================================================
-- USER PROGRAMS: Paste any standard RISC-V assembly here.
--
-- Write COMPLETE programs with _start, just like you would for QEMU.
-- Use Linux RISC-V syscalls to print output:
--
--   write(fd, buf, len):  a7=64,  a0=1(stdout), a1=buf_addr, a2=len  → ecall
--   exit(code):           a7=93,  a0=exit_code                       → ecall
-- ============================================================================

local UserPrograms = {}

UserPrograms.Divide = [[
.text
.globl _start

_start:
    lui     sp, 0x10002         # setup stack

    # Print header
    la      a0, msg_header
    call    print_string

    # Perform division: 42 / 5
    li      a0, 42
    li      a1, 5
    call    divide
    # a0 = quotient (8), a1 = remainder (2)

    # Save results
    mv      s0, a0              # quotient
    mv      s1, a1              # remainder

    # Print "Quotient: "
    la      a0, msg_quot
    call    print_string
    mv      a0, s0
    call    print_number
    la      a0, newline
    call    print_string

    # Print "Remainder: "
    la      a0, msg_rem
    call    print_string
    mv      a0, s1
    call    print_number
    la      a0, newline
    call    print_string

    # Exit
    li      a7, 93
    li      a0, 0
    ecall

# -----------------------------------------
# int divide(int dividend, int divisor)
# Input:  a0 = dividend, a1 = divisor
# Output: a0 = quotient, a1 = remainder
# -----------------------------------------
divide:
    beq     a1, x0, div_by_zero
    div     a2, a0, a1
    rem     a3, a0, a1
    mv      a0, a2
    mv      a1, a3
    ret

div_by_zero:
    li      a0, 0
    li      a1, 0
    ret

# -----------------------------------------
# void print_string(char* a0)
# Print null-terminated string to stdout
# -----------------------------------------
print_string:
    addi    sp, sp, -12
    sw      ra, 8(sp)
    sw      s0, 4(sp)
    sw      s1, 0(sp)
    mv      s0, a0
    li      s1, 0
    mv      t0, s0
ps_len:
    lb      t1, 0(t0)
    beqz    t1, ps_print
    addi    t0, t0, 1
    addi    s1, s1, 1
    j       ps_len
ps_print:
    li      a7, 64
    li      a0, 1
    mv      a1, s0
    mv      a2, s1
    ecall
    lw      s1, 0(sp)
    lw      s0, 4(sp)
    lw      ra, 8(sp)
    addi    sp, sp, 12
    ret

# -----------------------------------------
# void print_number(int a0)
# Print integer to stdout (handles multi-digit)
# -----------------------------------------
print_number:
    addi    sp, sp, -20
    sw      ra, 16(sp)
    sw      s0, 12(sp)
    sw      s1, 8(sp)
    sw      s2, 4(sp)
    sw      s3, 0(sp)
    mv      s0, a0
    li      s1, 0
    la      s2, num_buf
    addi    s2, s2, 9
    bnez    s0, pn_loop
    li      t0, 48
    sb      t0, 0(s2)
    li      s1, 1
    j       pn_print
pn_loop:
    beqz    s0, pn_done
    li      t0, 10
    remu    t1, s0, t0
    divu    s0, s0, t0
    addi    t1, t1, 48
    sb      t1, 0(s2)
    addi    s2, s2, -1
    addi    s1, s1, 1
    j       pn_loop
pn_done:
    addi    s2, s2, 1
pn_print:
    li      a7, 64
    li      a0, 1
    mv      a1, s2
    mv      a2, s1
    ecall
    lw      s3, 0(sp)
    lw      s2, 4(sp)
    lw      s1, 8(sp)
    lw      s0, 12(sp)
    lw      ra, 16(sp)
    addi    sp, sp, 20
    ret

.data
msg_header: .asciz "=== Division: 42 / 5 ===\n"
msg_quot:   .asciz "Quotient:  "
msg_rem:    .asciz "Remainder: "
newline:    .asciz "\n"
num_buf:    .space 10
]]


UserPrograms.Fib2 = [[
    .section .data
space:  .ascii " "
newline:.ascii "\n"

    # Change N here (number of Fibonacci terms)
    .equ N, 10

    .section .bss
    .lcomm buffer, 12   # buffer for integer to ASCII

    .section .text
    .globl _start

_start:
    li s0, N          # loop counter
    li s1, 0          # a = 0
    li s2, 1          # b = 1

fib_loop:
    beqz s0, done

    # print a
    mv a0, s1
    call print_int

    # print space
    li a0, 1
    la a1, space
    li a2, 1
    li a7, 64
    ecall

    # next fib: (a, b) = (b, a+b)
    add t3, s1, s2
    mv s1, s2
    mv s2, t3

    addi s0, s0, -1
    j fib_loop

done:
    # print newline
    li a0, 1
    la a1, newline
    li a2, 1
    li a7, 64
    ecall

    # exit(0)
    li a0, 0
    li a7, 93
    ecall


# -----------------------------------------
# print_int: prints integer in a0 (RV32I)
# uses syscall write
# -----------------------------------------
print_int:
    la t0, buffer+11
    li t1, 10
    sb zero, 0(t0)

    mv t2, a0
    li t3, 0          # digit count

    # handle 0 explicitly
    bnez t2, conv_loop
    li t4, '0'
    addi t0, t0, -1
    sb t4, 0(t0)
    j print_write

conv_loop:
    beqz t2, conv_done
    rem t4, t2, t1
    addi t4, t4, '0'
    addi t0, t0, -1
    sb t4, 0(t0)
    div t2, t2, t1
    j conv_loop

conv_done:

print_write:
    # compute length
    la t5, buffer+11
    sub a2, t5, t0

    mv a1, t0
    li a0, 1
    li a7, 64
    ecall

    ret
]]

UserPrograms.HelloWorld = [[
.section .data
msg:
    .ascii "Hello World\n"
msg_len = . - msg

.section .text
.globl _start

_start:
    # write(1, msg, msg_len)
    li a7, 64          # syscall: write
    li a0, 1           # fd = stdout
    la a1, msg         # buffer address
    li a2, msg_len     # length
    ecall

    # exit(0)
    li a7, 93          # syscall: exit
    li a0, 0           # status = 0
    ecall
]]


UserPrograms.SierpinskiTriangle = [[
.data
buffer:     .space 128      # Line buffer to hold output before printing

.text
.globl _start

_start:
    li s0, 0                # s0 = y = 0
    li s1, 32               # s1 = SIZE = 32

loop_y:
    beq s0, s1, exit        # if y == SIZE, exit
    la s2, buffer           # s2 = pointer to current position in buffer

    # Loop to print leading spaces for a centered triangle
    sub s3, s1, s0          # s3 = SIZE - y
    li t0, 0                # t0 = space counter = 0
loop_spaces:
    beq t0, s3, init_x
    li t1, 32               # ASCII ' '
    sb t1, 0(s2)
    addi s2, s2, 1
    addi t0, t0, 1
    j loop_spaces

init_x:
    li s4, 0                # s4 = x = 0

loop_x:
    bgt s4, s0, print_line  # if x > y, we are done with this line

    # The Fractal Magic: check if (x & y) == x
    and t0, s4, s0
    beq t0, s4, print_star

print_empty:
    li t1, 32               # ASCII ' '
    sb t1, 0(s2)
    sb t1, 1(s2)            # Add two spaces
    addi s2, s2, 2
    j next_x

print_star:
    li t1, 42               # ASCII '*'
    sb t1, 0(s2)
    li t1, 32               # ASCII ' '
    sb t1, 1(s2)            # Add "* "
    addi s2, s2, 2

next_x:
    addi s4, s4, 1          # x++
    j loop_x

print_line:
    li t1, 10               # ASCII '\n'
    sb t1, 0(s2)            # Add newline at the end of the buffer
    addi s2, s2, 1

    # Linux Syscall: write(fd=1, buffer, length)
    li a0, 1                # a0 = file descriptor 1 (stdout)
    la a1, buffer           # a1 = address of buffer
    la t0, buffer
    sub a2, s2, t0          # a2 = length to print (current pointer - start)
    li a7, 64               # a7 = syscall number for 'write' (64)
    ecall

    addi s0, s0, 1          # y++
    j loop_y

exit:
    # Linux Syscall: exit(status=0)
    li a0, 0                # a0 = exit status 0
    li a7, 93               # a7 = syscall number for 'exit' (93)
    ecall
]]


UserPrograms.BubbleSort = [[
.section .data

array:
    .word 5, 1, 4, 2, 8
len = 5

space:
    .ascii " "

newline:
    .ascii "\n"

before_msg:
    .ascii "Before sort:\n"
before_len = . - before_msg

after_msg:
    .ascii "After sort:\n"
after_len = . - after_msg


.section .bss
    .lcomm buffer, 16   # buffer for integer conversion


.section .text
.globl _start


# -----------------------------
# _start
# -----------------------------
_start:
    # print "Before sort"
    li a7, 64
    li a0, 1
    la a1, before_msg
    li a2, before_len
    ecall

    la a0, array
    li a1, len
    call print_array

    # newline
    call print_newline

    # bubble sort
    la a0, array
    li a1, len
    call bubble_sort

    # print "After sort"
    li a7, 64
    li a0, 1
    la a1, after_msg
    li a2, after_len
    ecall

    la a0, array
    li a1, len
    call print_array

    call print_newline

    # exit(0)
    li a7, 93
    li a0, 0
    ecall


# -----------------------------
# bubble_sort(a0=array, a1=len)
# -----------------------------
bubble_sort:
    addi sp, sp, -16
    sw ra, 12(sp)

    mv t0, a1          # n

outer_loop:
    li t1, 0           # i = 0
    addi t0, t0, -1    # n-1 passes

    blez t0, done_sort

inner_loop:
    bge t1, t0, outer_loop_end

    # load arr[i]
    slli t2, t1, 2
    add t3, a0, t2
    lw t4, 0(t3)

    lw t5, 4(t3)

    # if arr[i] > arr[i+1], swap
    ble t4, t5, no_swap

    sw t5, 0(t3)
    sw t4, 4(t3)

no_swap:
    addi t1, t1, 1
    j inner_loop

outer_loop_end:
    j outer_loop

done_sort:
    lw ra, 12(sp)
    addi sp, sp, 16
    ret


# -----------------------------
# print_array(a0=array, a1=len)
# -----------------------------
print_array:
    addi sp, sp, -32
    sw ra, 28(sp)
    sw s0, 24(sp)
    sw s1, 20(sp)
    sw s2, 16(sp)

    mv s0, a0          # array address
    mv s1, a1          # array length
    li s2, 0           # loop counter

print_loop:
    bge s2, s1, print_done

    slli t3, s2, 2
    add t4, s0, t3
    lw a0, 0(t4)

    call print_int

    # print space
    li a7, 64
    li a0, 1
    la a1, space
    li a2, 1
    ecall

    addi s2, s2, 1
    j print_loop

print_done:
    lw ra, 28(sp)
    lw s0, 24(sp)
    lw s1, 20(sp)
    lw s2, 16(sp)
    addi sp, sp, 32
    ret


# -----------------------------
# print_int(a0 = integer)
# -----------------------------
print_int:
    addi sp, sp, -16
    sw ra, 12(sp)

    la t0, buffer
    addi t1, t0, 15
    sb zero, 0(t1)

    li t2, 10

    # handle zero
    bnez a0, convert_loop
    addi t1, t1, -1
    li t3, '0'
    sb t3, 0(t1)
    j print_number

convert_loop:
    beqz a0, print_number

    rem t3, a0, t2
    addi t3, t3, '0'
    addi t1, t1, -1
    sb t3, 0(t1)

    div a0, a0, t2
    j convert_loop

print_number:
    li a7, 64
    li a0, 1
    mv a1, t1
    la t0, buffer
    addi a2, t0, 15
    sub a2, a2, t1
    ecall

    lw ra, 12(sp)
    addi sp, sp, 16
    ret


# -----------------------------
# print newline
# -----------------------------
print_newline:
    li a7, 64
    li a0, 1
    la a1, newline
    li a2, 1
    ecall
    ret
]]

UserPrograms.Mul2 = [[
.section .data
buffer: .space 16

.section .text
.globl _start

_start:
    # -------------------------
    # Load numbers
    # -------------------------
    li t0, 6
    li t1, 7

    # -------------------------
    # Multiply (RV32M)
    # -------------------------
    mul t2, t0, t1     # t2 = 42

    # -------------------------
    # Convert to ASCII (0–99)
    # -------------------------
    la t3, buffer

    li t4, 10
    div t5, t2, t4     # tens digit
    rem t6, t2, t4     # ones digit

    addi t5, t5, 48    # ASCII '0'
    addi t6, t6, 48

    sb t5, 0(t3)
    sb t6, 1(t3)

    li t0, '\n'        # newline (valid register reuse)
    sb t0, 2(t3)

    # -------------------------
    # write(1, buffer, 3)
    # -------------------------
    li a0, 1           # stdout
    la a1, buffer      # pointer
    li a2, 3           # length
    li a7, 64          # sys_write
    ecall

    # -------------------------
    # exit(0)
    # -------------------------
    li a0, 0
    li a7, 93
    ecall
]]


UserPrograms.Factorial = [[
.text
.globl _start

_start:
    lui     sp, 0x10002

    la      a0, msg_header
    call    print_string

    li      a0, 7
    call    factorial
    mv      s0, a0

    la      a0, msg_result
    call    print_string
    mv      a0, s0
    call    print_number
    la      a0, newline
    call    print_string

    li      a7, 93
    li      a0, 0
    ecall

# -----------------------------------------
# int factorial(int n)
# -----------------------------------------
factorial:
    addi    sp, sp, -8
    sw      ra, 4(sp)
    sw      s0, 0(sp)
    mv      s0, a0
    li      t0, 1
    ble     s0, t0, fact_base
    addi    a0, s0, -1
    call    factorial
    mul     a0, s0, a0
    j       fact_done
fact_base:
    li      a0, 1
fact_done:
    lw      s0, 0(sp)
    lw      ra, 4(sp)
    addi    sp, sp, 8
    ret

# -----------------------------------------
# void print_string(char* a0)
# -----------------------------------------
print_string:
    addi    sp, sp, -12
    sw      ra, 8(sp)
    sw      s0, 4(sp)
    sw      s1, 0(sp)
    mv      s0, a0
    li      s1, 0
    mv      t0, s0
ps_len:
    lb      t1, 0(t0)
    beqz    t1, ps_print
    addi    t0, t0, 1
    addi    s1, s1, 1
    j       ps_len
ps_print:
    li      a7, 64
    li      a0, 1
    mv      a1, s0
    mv      a2, s1
    ecall
    lw      s1, 0(sp)
    lw      s0, 4(sp)
    lw      ra, 8(sp)
    addi    sp, sp, 12
    ret

# -----------------------------------------
# void print_number(int a0)
# -----------------------------------------
print_number:
    addi    sp, sp, -20
    sw      ra, 16(sp)
    sw      s0, 12(sp)
    sw      s1, 8(sp)
    sw      s2, 4(sp)
    sw      s3, 0(sp)
    mv      s0, a0
    li      s1, 0
    la      s2, num_buf
    addi    s2, s2, 9
    bnez    s0, pn_loop
    li      t0, 48
    sb      t0, 0(s2)
    li      s1, 1
    j       pn_print
pn_loop:
    beqz    s0, pn_done
    li      t0, 10
    remu    t1, s0, t0
    divu    s0, s0, t0
    addi    t1, t1, 48
    sb      t1, 0(s2)
    addi    s2, s2, -1
    addi    s1, s1, 1
    j       pn_loop
pn_done:
    addi    s2, s2, 1
pn_print:
    li      a7, 64
    li      a0, 1
    mv      a1, s2
    mv      a2, s1
    ecall
    lw      s3, 0(sp)
    lw      s2, 4(sp)
    lw      s1, 8(sp)
    lw      s0, 12(sp)
    lw      ra, 16(sp)
    addi    sp, sp, 20
    ret

.data
msg_header: .asciz "=== Factorial: 7! ===\n"
msg_result: .asciz "Result: "
newline:    .asciz "\n"
num_buf:    .space 10
]]


UserPrograms.GCD = [[
.text
.globl _start

_start:
    lui     sp, 0x10002

    la      a0, msg_header
    call    print_string

    li      a0, 48
    li      a1, 18
    call    gcd
    mv      s0, a0

    la      a0, msg_result
    call    print_string
    mv      a0, s0
    call    print_number
    la      a0, newline
    call    print_string

    li      a7, 93
    li      a0, 0
    ecall

# -----------------------------------------
# int gcd(int a, int b)
# -----------------------------------------
gcd:
    beqz    a1, gcd_done
gcd_loop:
    rem     t0, a0, a1
    mv      a0, a1
    mv      a1, t0
    bnez    a1, gcd_loop
gcd_done:
    ret

# --- print_string and print_number (same as above) ---
print_string:
    addi    sp, sp, -12
    sw      ra, 8(sp)
    sw      s0, 4(sp)
    sw      s1, 0(sp)
    mv      s0, a0
    li      s1, 0
    mv      t0, s0
ps_len:
    lb      t1, 0(t0)
    beqz    t1, ps_print
    addi    t0, t0, 1
    addi    s1, s1, 1
    j       ps_len
ps_print:
    li      a7, 64
    li      a0, 1
    mv      a1, s0
    mv      a2, s1
    ecall
    lw      s1, 0(sp)
    lw      s0, 4(sp)
    lw      ra, 8(sp)
    addi    sp, sp, 12
    ret

print_number:
    addi    sp, sp, -20
    sw      ra, 16(sp)
    sw      s0, 12(sp)
    sw      s1, 8(sp)
    sw      s2, 4(sp)
    sw      s3, 0(sp)
    mv      s0, a0
    li      s1, 0
    la      s2, num_buf
    addi    s2, s2, 9
    bnez    s0, pn_loop
    li      t0, 48
    sb      t0, 0(s2)
    li      s1, 1
    j       pn_print
pn_loop:
    beqz    s0, pn_done
    li      t0, 10
    remu    t1, s0, t0
    divu    s0, s0, t0
    addi    t1, t1, 48
    sb      t1, 0(s2)
    addi    s2, s2, -1
    addi    s1, s1, 1
    j       pn_loop
pn_done:
    addi    s2, s2, 1
pn_print:
    li      a7, 64
    li      a0, 1
    mv      a1, s2
    mv      a2, s1
    ecall
    lw      s3, 0(sp)
    lw      s2, 4(sp)
    lw      s1, 8(sp)
    lw      s0, 12(sp)
    lw      ra, 16(sp)
    addi    sp, sp, 20
    ret

.data
msg_header: .asciz "=== GCD(48, 18) ===\n"
msg_result: .asciz "GCD: "
newline:    .asciz "\n"
num_buf:    .space 10
]]

return UserPrograms
