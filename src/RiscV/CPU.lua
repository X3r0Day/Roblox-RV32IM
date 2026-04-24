-- ModuleScript: RiscV/CPU.lua
local CPU = {}

-- helpers for 32-bit math since lua uses 64-bit floats

-- Sign-extend a value from 'bits' width to Lua signed integer
local function sext(value, bits)
	local shift = 32 - bits
	return bit32.arshift(bit32.lshift(value, shift), shift)
end

-- Ensure value is treated as unsigned 32-bit
local function toUnsigned32(value)
	return bit32.band(value, 0xFFFFFFFF)
end

-- Convert an unsigned 32-bit value to a signed Lua number (two's complement)
local function toSigned32(value)
	value = bit32.band(value, 0xFFFFFFFF)
	if bit32.btest(value, 0x80000000) then
		-- Negative: value - 2^32
		return value - 4294967296
	end
	return value
end

-- Unsigned less-than comparison for 32-bit values
local function unsignedLT(a, b)
	-- bit32 functions return values in [0, 2^32-1] in Luau, so direct compare works
	return toUnsigned32(a) < toUnsigned32(b)
end

-- manual 64-bit math via 16-bit chunks since luau doesn't support int64 natively
-- decomposes 32-bit values into 16-bit halves to avoid 53-bit float precision loss
-- tracks lower 32 bits and upper 32 bits separately with manual carry logic
local function umul64(a, b)
	a = toUnsigned32(a)
	b = toUnsigned32(b)

	local aL = bit32.band(a, 0xFFFF)
	local aH = bit32.rshift(a, 16)
	local bL = bit32.band(b, 0xFFFF)
	local bH = bit32.rshift(b, 16)

	local ll = aL * bL           -- partial products
	local lh = aL * bH
	local hl = aH * bL
	local hh = aH * bH

	local lo = ll                -- accumulate lower
	local mid = lh + hl
	local midLo = mid % 65536
	local midHi = math.floor(mid / 65536)
	lo = lo + midLo * 65536

	local hi = hh + midHi        -- accumulate upper

	if lo >= 4294967296 then
		hi = hi + math.floor(lo / 4294967296) -- handle carry
	end
	lo = lo % 4294967296 -- keep 32 bits

	return toUnsigned32(lo), toUnsigned32(hi)
end

-- computes absolute values as unsigned, delegates to umul64, then negates if signs differed
local function mulh_signed(a, b)
	local aSigned = toSigned32(a)
	local bSigned = toSigned32(b)
	local negative = (aSigned < 0) ~= (bSigned < 0)

	local aAbs = (aSigned < 0) and toUnsigned32(-aSigned) or toUnsigned32(aSigned)
	local bAbs = (bSigned < 0) and toUnsigned32(-bSigned) or toUnsigned32(bSigned)

	local lo, hi = umul64(aAbs, bAbs)

	if negative then
		lo = bit32.bnot(lo)
		hi = bit32.bnot(hi)
		lo = toUnsigned32(lo + 1)
		if lo == 0 then
			hi = toUnsigned32(hi + 1) -- propagate carry
		end
	end

	return hi
end

-- computes absolute values as unsigned, delegates to umul64, then negates if negative
local function mulhsu(a, b)
	local aSigned = toSigned32(a)
	local bUnsigned = toUnsigned32(b)
	local negative = aSigned < 0

	local aAbs = negative and toUnsigned32(-aSigned) or toUnsigned32(aSigned)

	local lo, hi = umul64(aAbs, bUnsigned)

	if negative then
		lo = bit32.bnot(lo)
		hi = bit32.bnot(hi)
		lo = toUnsigned32(lo + 1)
		if lo == 0 then
			hi = toUnsigned32(hi + 1) -- propagate carry
		end
	end

	return hi
end

-- C99/RISC-V style truncated division (round towards zero)

-- Signed truncated division: rounds toward zero
local function truncDiv(a, b)
	-- a / b truncated toward zero
	local result = a / b
	if result >= 0 then
		return math.floor(result)
	else
		return math.ceil(result)
	end
end

-- Signed truncated remainder: sign matches dividend
local function truncRem(a, b)
	local q = truncDiv(a, b)
	return a - q * b
end

-- Constants for overflow detection
local INT32_MIN = -2147483648 -- -2^31
local INT32_MAX = 2147483647  -- 2^31 - 1

-- core cpu state

function CPU.new(program, options)
	options = options or {}

	local cpu = {
		-- Core state
		pc = program.textBase,
		regs = {},
		memory = {},
		csrs = {},

		-- Program data
		prog = program,
		program = program,

		-- Control
		running = true,

		-- Callbacks
		onEcall = options.onEcall,

		-- Debug
		debug = options.debug or false
	}

	-- Initialize registers (x0..x31, stored at indices 1..32)
	for i = 1, 32 do
		cpu.regs[i] = 0
	end

	-- Initialize memory with program data
	for addr, byte in pairs(program.data or {}) do
		cpu.memory[addr] = bit32.band(byte, 0xFF)
	end

	return setmetatable(cpu, {__index = CPU})
end

-- x0 is hardwired to zero

function CPU:getReg(regNum)
	if regNum == 0 then return 0 end
	return self.regs[regNum + 1] or 0
end

function CPU:setReg(regNum, value)
	if regNum == 0 then return end
	self.regs[regNum + 1] = toUnsigned32(value)
end

-- control and status registers

function CPU:getCSR(csrAddr)
	return self.csrs[csrAddr] or 0
end

function CPU:setCSR(csrAddr, value)
	self.csrs[csrAddr] = toUnsigned32(value)
end

-- memory is just a flat sparse table right now. todo: hook up real mmu/page tables

function CPU:load8(addr)
	return self.memory[addr] or 0
end

function CPU:store8(addr, value)
	self.memory[addr] = bit32.band(value, 0xFF)
end

function CPU:load16(addr)
	local b0 = self:load8(addr)
	local b1 = self:load8(addr + 1)
	return bit32.bor(b0, bit32.lshift(b1, 8))
end

function CPU:store16(addr, value)
	self:store8(addr, value)
	self:store8(addr + 1, bit32.rshift(value, 8))
end

function CPU:load32(addr)
	local b0 = self:load8(addr)
	local b1 = self:load8(addr + 1)
	local b2 = self:load8(addr + 2)
	local b3 = self:load8(addr + 3)
	return bit32.bor(b0, bit32.lshift(b1, 8), bit32.lshift(b2, 16), bit32.lshift(b3, 24))
end

function CPU:store32(addr, value)
	self:store8(addr, value)
	self:store8(addr + 1, bit32.rshift(value, 8))
	self:store8(addr + 2, bit32.rshift(value, 16))
	self:store8(addr + 3, bit32.rshift(value, 24))
end

-- main execution pipeline

function CPU:step()
	local instIndex = self.program.pcToIndex[self.pc]
	if not instIndex then
		if self.debug then
			print("No instruction at PC:", string.format("0x%08X", self.pc))
		end
		self.running = false
		return
	end

	local inst = self.program.code[instIndex]
	local nextPC = self.pc + 4

	if self.debug then
		print(string.format("PC: 0x%08X, Op: %s", self.pc, inst.op))
	end

	local op = inst.op

	-- rv32i base integer instructions

	-- R-type arithmetic
	if op == "add" then
		self:setReg(inst.rd, self:getReg(inst.rs1) + self:getReg(inst.rs2))
	elseif op == "sub" then
		self:setReg(inst.rd, self:getReg(inst.rs1) - self:getReg(inst.rs2))
	elseif op == "and" then
		self:setReg(inst.rd, bit32.band(self:getReg(inst.rs1), self:getReg(inst.rs2)))
	elseif op == "or" then
		self:setReg(inst.rd, bit32.bor(self:getReg(inst.rs1), self:getReg(inst.rs2)))
	elseif op == "xor" then
		self:setReg(inst.rd, bit32.bxor(self:getReg(inst.rs1), self:getReg(inst.rs2)))
	elseif op == "sll" then
		self:setReg(inst.rd, bit32.lshift(self:getReg(inst.rs1), bit32.band(self:getReg(inst.rs2), 31)))
	elseif op == "srl" then
		self:setReg(inst.rd, bit32.rshift(self:getReg(inst.rs1), bit32.band(self:getReg(inst.rs2), 31)))
	elseif op == "sra" then
		self:setReg(inst.rd, bit32.arshift(self:getReg(inst.rs1), bit32.band(self:getReg(inst.rs2), 31)))
	elseif op == "slt" then
		local a = toSigned32(self:getReg(inst.rs1))
		local b = toSigned32(self:getReg(inst.rs2))
		self:setReg(inst.rd, (a < b) and 1 or 0)
	elseif op == "sltu" then
		self:setReg(inst.rd, unsignedLT(self:getReg(inst.rs1), self:getReg(inst.rs2)) and 1 or 0)

	-- I-type arithmetic
	elseif op == "addi" then
		self:setReg(inst.rd, self:getReg(inst.rs1) + (inst.imm or 0))
	elseif op == "andi" then
		self:setReg(inst.rd, bit32.band(self:getReg(inst.rs1), inst.imm or 0))
	elseif op == "ori" then
		self:setReg(inst.rd, bit32.bor(self:getReg(inst.rs1), inst.imm or 0))
	elseif op == "xori" then
		self:setReg(inst.rd, bit32.bxor(self:getReg(inst.rs1), inst.imm or 0))
	elseif op == "slti" then
		local a = toSigned32(self:getReg(inst.rs1))
		local b = toSigned32(sext(inst.imm or 0, 12))
		self:setReg(inst.rd, (a < b) and 1 or 0)
	elseif op == "sltiu" then
		self:setReg(inst.rd, unsignedLT(self:getReg(inst.rs1), inst.imm or 0) and 1 or 0)
	elseif op == "slli" then
		self:setReg(inst.rd, bit32.lshift(self:getReg(inst.rs1), bit32.band(inst.imm or 0, 31)))
	elseif op == "srli" then
		self:setReg(inst.rd, bit32.rshift(self:getReg(inst.rs1), bit32.band(inst.imm or 0, 31)))
	elseif op == "srai" then
		self:setReg(inst.rd, bit32.arshift(self:getReg(inst.rs1), bit32.band(inst.imm or 0, 31)))

	-- U-type instructions
	elseif op == "lui" then
		self:setReg(inst.rd, bit32.lshift(bit32.band(inst.imm or 0, 0xFFFFF), 12))
	elseif op == "auipc" then
		self:setReg(inst.rd, self.pc + bit32.lshift(bit32.band(inst.imm or 0, 0xFFFFF), 12))

	-- Load instructions
	elseif op == "lb" then
		local addr = self:getReg(inst.rs1) + (inst.imm or 0)
		self:setReg(inst.rd, sext(self:load8(addr), 8))
	elseif op == "lh" then
		local addr = self:getReg(inst.rs1) + (inst.imm or 0)
		self:setReg(inst.rd, sext(self:load16(addr), 16))
	elseif op == "lw" then
		local addr = self:getReg(inst.rs1) + (inst.imm or 0)
		self:setReg(inst.rd, self:load32(addr))
	elseif op == "lbu" then
		local addr = self:getReg(inst.rs1) + (inst.imm or 0)
		self:setReg(inst.rd, self:load8(addr))
	elseif op == "lhu" then
		local addr = self:getReg(inst.rs1) + (inst.imm or 0)
		self:setReg(inst.rd, self:load16(addr))

	-- Store instructions
	elseif op == "sb" then
		local addr = self:getReg(inst.rs1) + (inst.imm or 0)
		self:store8(addr, self:getReg(inst.rs2))
	elseif op == "sh" then
		local addr = self:getReg(inst.rs1) + (inst.imm or 0)
		self:store16(addr, self:getReg(inst.rs2))
	elseif op == "sw" then
		local addr = self:getReg(inst.rs1) + (inst.imm or 0)
		self:store32(addr, self:getReg(inst.rs2))

	-- Branch instructions
	elseif op == "beq" then
		if self:getReg(inst.rs1) == self:getReg(inst.rs2) then
			nextPC = inst.targetAddr
		end
	elseif op == "bne" then
		if self:getReg(inst.rs1) ~= self:getReg(inst.rs2) then
			nextPC = inst.targetAddr
		end
	elseif op == "blt" then
		local a = toSigned32(self:getReg(inst.rs1))
		local b = toSigned32(self:getReg(inst.rs2))
		if a < b then nextPC = inst.targetAddr end
	elseif op == "bge" then
		local a = toSigned32(self:getReg(inst.rs1))
		local b = toSigned32(self:getReg(inst.rs2))
		if a >= b then nextPC = inst.targetAddr end
	elseif op == "bgt" then
		-- Pseudo-branch (bgt rs, rt, label) = blt rt, rs, label
		local a = toSigned32(self:getReg(inst.rs1))
		local b = toSigned32(self:getReg(inst.rs2))
		if a > b then nextPC = inst.targetAddr end
	elseif op == "ble" then
		-- Pseudo-branch (ble rs, rt, label) = bge rt, rs, label
		local a = toSigned32(self:getReg(inst.rs1))
		local b = toSigned32(self:getReg(inst.rs2))
		if a <= b then nextPC = inst.targetAddr end
	elseif op == "bltu" then
		if unsignedLT(self:getReg(inst.rs1), self:getReg(inst.rs2)) then
			nextPC = inst.targetAddr
		end
	elseif op == "bgeu" then
		if not unsignedLT(self:getReg(inst.rs1), self:getReg(inst.rs2)) then
			nextPC = inst.targetAddr
		end
	elseif op == "bgtu" then
		local a = self:getReg(inst.rs1)
		local b = self:getReg(inst.rs2)
		if (not unsignedLT(a, b)) and (a ~= b) then
			nextPC = inst.targetAddr
		end
	elseif op == "bleu" then
		local a = self:getReg(inst.rs1)
		local b = self:getReg(inst.rs2)
		if unsignedLT(a, b) or (a == b) then
			nextPC = inst.targetAddr
		end

	-- Jump instructions
	elseif op == "jal" then
		self:setReg(inst.rd or 1, nextPC)
		nextPC = inst.targetAddr
	elseif op == "jalr" then
		local target = bit32.band(self:getReg(inst.rs1) + (inst.imm or 0), 0xFFFFFFFE)
		self:setReg(inst.rd or 1, nextPC)
		nextPC = target

	-- rv32m multiply/divide

	-- MUL: Multiply, return lower 32 bits of product
	elseif op == "mul" then
		local a = toUnsigned32(self:getReg(inst.rs1))
		local b = toUnsigned32(self:getReg(inst.rs2))
		local lo, _ = umul64(a, b)
		self:setReg(inst.rd, lo)

	-- MULH: Multiply High (signed × signed), return upper 32 bits
	elseif op == "mulh" then
		local hi = mulh_signed(self:getReg(inst.rs1), self:getReg(inst.rs2))
		self:setReg(inst.rd, hi)

	-- MULHSU: Multiply High (signed × unsigned), return upper 32 bits
	elseif op == "mulhsu" then
		local hi = mulhsu(self:getReg(inst.rs1), self:getReg(inst.rs2))
		self:setReg(inst.rd, hi)

	-- MULHU: Multiply High (unsigned × unsigned), return upper 32 bits
	elseif op == "mulhu" then
		local a = toUnsigned32(self:getReg(inst.rs1))
		local b = toUnsigned32(self:getReg(inst.rs2))
		local _, hi = umul64(a, b)
		self:setReg(inst.rd, hi)

	-- DIV: Signed division (truncated toward zero)
	elseif op == "div" then
		local a = toSigned32(self:getReg(inst.rs1))
		local b = toSigned32(self:getReg(inst.rs2))
		if b == 0 then
			-- Division by zero: result is all 1s per spec
			self:setReg(inst.rd, 0xFFFFFFFF)
		elseif a == INT32_MIN and b == -1 then
			-- Signed overflow: INT_MIN / -1 = INT_MIN per spec
			self:setReg(inst.rd, INT32_MIN)
		else
			self:setReg(inst.rd, truncDiv(a, b))
		end

	-- DIVU: Unsigned division
	elseif op == "divu" then
		local a = toUnsigned32(self:getReg(inst.rs1))
		local b = toUnsigned32(self:getReg(inst.rs2))
		if b == 0 then
			-- Division by zero: result is all 1s per spec
			self:setReg(inst.rd, 0xFFFFFFFF)
		else
			self:setReg(inst.rd, math.floor(a / b))
		end

	-- REM: Signed remainder (sign matches dividend, truncated division)
	elseif op == "rem" then
		local a = toSigned32(self:getReg(inst.rs1))
		local b = toSigned32(self:getReg(inst.rs2))
		if b == 0 then
			-- Remainder by zero: result is the dividend per spec
			self:setReg(inst.rd, a)
		elseif a == INT32_MIN and b == -1 then
			-- Signed overflow: remainder is 0 per spec
			self:setReg(inst.rd, 0)
		else
			self:setReg(inst.rd, truncRem(a, b))
		end

	-- REMU: Unsigned remainder
	elseif op == "remu" then
		local a = toUnsigned32(self:getReg(inst.rs1))
		local b = toUnsigned32(self:getReg(inst.rs2))
		if b == 0 then
			-- Remainder by zero: result is the dividend per spec
			self:setReg(inst.rd, a)
		else
			self:setReg(inst.rd, a % b)
		end

	-- zicsr instructions

	elseif op == "csrrw" then
		local old = self:getCSR(inst.csr)
		self:setCSR(inst.csr, self:getReg(inst.rs1))
		self:setReg(inst.rd, old)
	elseif op == "csrrs" then
		local old = self:getCSR(inst.csr)
		if inst.rs1 ~= 0 then
			self:setCSR(inst.csr, bit32.bor(old, self:getReg(inst.rs1)))
		end
		self:setReg(inst.rd, old)
	elseif op == "csrrc" then
		local old = self:getCSR(inst.csr)
		if inst.rs1 ~= 0 then
			self:setCSR(inst.csr, bit32.band(old, bit32.bnot(self:getReg(inst.rs1))))
		end
		self:setReg(inst.rd, old)

	-- system instructions

	elseif op == "ecall" then
		if self.onEcall then
			self.onEcall(self)
		end
	elseif op == "ebreak" then
		self.running = false
	elseif op == "fence" or op == "fence.i" then
		-- Memory ordering fence — no-op in single-core emulator

	else
		error("Unknown instruction: " .. op .. " at PC " .. string.format("0x%08X", self.pc))
	end

	-- Ensure x0 is always zero
	self.regs[1] = 0

	self.pc = nextPC
end

-- run loop

function CPU:run(maxSteps)
	maxSteps = maxSteps or 100000
	local steps = 0

	while self.running and steps < maxSteps do
		self:step()
		steps = steps + 1
	end

	return steps
end

return CPU