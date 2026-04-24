-- ModuleScript: RiscV/Parser.lua
local Spec = require(script.Parent.Spec)

local Parser = {}


local function trim(s)
	return s:match("^%s*(.-)%s*$")
end

local function stripComments(line)
	line = line:gsub("#.*$", "")
	line = line:gsub("//.*$", "")  
	line = line:gsub(";.*$", "")
	return trim(line)
end

local function parseNumber(str)
	if not str then return nil end
	str = trim(str)
	if str:match("^0[xX]") then
		return tonumber(str, 16)
	elseif str:match("^0[bB]") then
		return tonumber(str:sub(3), 2)
	elseif str:match("^'(.)'$") then
		return string.byte(str:match("^'(.)'$"))
	elseif str:match("^%-?%d+$") then
		return tonumber(str, 10)
	end
	return nil
end

local function evaluateExpression(expr, labels, currentAddr)
	if not expr then return nil end
	expr = expr:gsub("%s+", "")
	
	-- Simple number or single symbol
	local num = parseNumber(expr)
	if num then return num end
	if expr == "." then return currentAddr end
	if labels[expr] then return labels[expr] end
	
	-- Simple A +/- B (enough for . - msg)
	local a, op, b = expr:match("^([%w_%.]+)([%+%-])([%w_%.]+)$")
	if a and op and b then
		local valA = (a == ".") and currentAddr or parseNumber(a) or labels[a]
		local valB = (b == ".") and currentAddr or parseNumber(b) or labels[b]
		if valA and valB then
			if op == "+" then return valA + valB end
			if op == "-" then return valA - valB end
		end
	end
	
	return nil
end

local function splitOperands(str)
	local ops = {}
	for op in str:gmatch("([^,]+)") do
		table.insert(ops, trim(op))
	end
	return ops
end

local function parseOffsetRegister(operand)
	local offset, reg = operand:match("^([%-+]?%d+)%(([%w%d]+)%)$")
	if offset and reg then
		local offsetNum = parseNumber(offset)
		if offsetNum and Spec.isReg(reg) then
			return offsetNum, Spec.regId(reg)
		end
	end
	return nil, nil
end

-- basic instruction map
local RV32I_R = {
	add=true, sub=true, sll=true, slt=true, sltu=true, xor=true, 
	srl=true, sra=true, ["or"]=true, ["and"]=true
}

local RV32I_I = {
	addi=true, slti=true, sltiu=true, xori=true, ori=true, andi=true, 
	slli=true, srli=true, srai=true
}

local RV32I_LOAD = {
	lb=true, lh=true, lw=true, lbu=true, lhu=true
}

local RV32I_STORE = {
	sb=true, sh=true, sw=true
}

local RV32I_BRANCH = {
	beq=true, bne=true, blt=true, bge=true, bltu=true, bgeu=true,
	bgt=true, ble=true, bgtu=true, bleu=true
}

local RV32I_U = {
	lui=true, auipc=true
}

local RV32I_J = {
	jal=true, jalr=true
}

local RV32I_SYSTEM = {
	ecall=true, ebreak=true, fence=true
}

local RV32M = {
	mul=true, mulh=true, mulhsu=true, mulhu=true,
	div=true, divu=true, rem=true, remu=true
}

local RV32_CSR = {
	csrrw=true, csrrs=true, csrrc=true,
	csrrwi=true, csrrsi=true, csrrci=true
}

-- Helper: sign-extend a 12-bit value to a signed Lua number
local function sext12(value)
	value = bit32.band(value, 0xFFF)
	if bit32.btest(value, 0x800) then
		return value - 0x1000
	end
	return value
end

-- pseudo-instructions into base rv32i instructions
-- 'li' evaluates size early to decide if it needs 1 or 2 instructions for accurate PC tracking
-- larger immediates use lui+addi, compensating for addi's sign-extension behavior
-- 'la' always resolves to lui+addi (2 instructions), so we defer its calculation to pass 2
local function expandPseudo(op, operands)
	op = op:lower()

	if op == "li" then
		assert(#operands == 2, "li expects rd, imm")
		local rd = operands[1]
		local immStr = operands[2]
		
		local immVal = nil
		immStr = immStr:match("^%s*(.-)%s*$")
		if immStr:match("^0[xX]") then
			immVal = tonumber(immStr, 16)
		elseif immStr:match("^%-?%d+$") then
			immVal = tonumber(immStr, 10)
		end

		if immVal and immVal >= -2048 and immVal <= 2047 then
			return {{op="addi", operands={rd, "x0", immStr}}} -- fits in single addi
		elseif immVal then
			local val32 = bit32.band(immVal, 0xFFFFFFFF) -- 32-bit unsigned
			local lower = bit32.band(val32, 0xFFF)
			local upper = bit32.rshift(val32, 12)
			
			if bit32.btest(lower, 0x800) then
				upper = bit32.band(upper + 1, 0xFFFFF) -- compensate for sign-extension
			end
			
			local lowerSigned = sext12(lower)
			return {
				{op="lui", operands={rd, tostring(upper)}},
				{op="addi", operands={rd, rd, tostring(lowerSigned)}}
			}
		else
			return {{op="li_pseudo", rd=rd, imm=immStr}} -- defer to pass 2
		end

	elseif op == "la" then
		assert(#operands == 2, "la expects rd, symbol")
		return {{op="la_pseudo", rd=operands[1], symbol=operands[2]}} -- defer to pass 2

	elseif op == "mv" then
		assert(#operands == 2, "mv expects rd, rs")
		return {{op="addi", operands={operands[1], operands[2], "0"}}}

	elseif op == "nop" then
		return {{op="addi", operands={"x0", "x0", "0"}}}

	elseif op == "ret" then
		return {{op="jalr", operands={"x0", "ra", "0"}}}

	elseif op == "j" then
		assert(#operands == 1, "j expects label")
		return {{op="jal", operands={"x0", operands[1]}}}

	elseif op == "call" then
		assert(#operands == 1, "call expects label") 
		return {{op="jal", operands={"ra", operands[1]}}}

	elseif op == "beqz" then
		assert(#operands == 2, "beqz expects rs, label")
		return {{op="beq", operands={operands[1], "x0", operands[2]}}}

	elseif op == "bnez" then
		assert(#operands == 2, "bnez expects rs, label")
		return {{op="bne", operands={operands[1], "x0", operands[2]}}}

	elseif op == "seqz" then
		assert(#operands == 2, "seqz expects rd, rs")
		return {{op="sltiu", operands={operands[1], operands[2], "1"}}}

	elseif op == "snez" then
		assert(#operands == 2, "snez expects rd, rs")
		return {{op="sltu", operands={operands[1], "x0", operands[2]}}}

	elseif op == "not" then
		assert(#operands == 2, "not expects rd, rs")
		return {{op="xori", operands={operands[1], operands[2], "-1"}}}

	elseif op == "neg" then
		assert(#operands == 2, "neg expects rd, rs")
		return {{op="sub", operands={operands[1], "x0", operands[2]}}}

	elseif op == "jr" then
		assert(#operands == 1, "jr expects rs")
		return {{op="jalr", operands={"x0", operands[1], "0"}}}

	elseif op == "tail" then
		assert(#operands == 1, "tail expects label")
		return {{op="jal", operands={"x0", operands[1]}}}

	elseif op == "sgtz" then
		assert(#operands == 2, "sgtz expects rd, rs")
		return {{op="slt", operands={operands[1], "x0", operands[2]}}}

	elseif op == "sltz" then
		assert(#operands == 2, "sltz expects rd, rs")
		return {{op="slt", operands={operands[1], operands[2], "x0"}}}

	elseif op == "blez" then
		assert(#operands == 2, "blez expects rs, label")
		return {{op="bge", operands={"x0", operands[1], operands[2]}}}

	elseif op == "bgtz" then
		assert(#operands == 2, "bgtz expects rs, label")
		return {{op="blt", operands={"x0", operands[1], operands[2]}}}

	elseif op == "bltz" then
		assert(#operands == 2, "bltz expects rs, label")
		return {{op="blt", operands={operands[1], "x0", operands[2]}}}

	elseif op == "bgez" then
		assert(#operands == 2, "bgez expects rs, label")
		return {{op="bge", operands={operands[1], "x0", operands[2]}}}

	elseif op == "bgt" then
		assert(#operands == 3, "bgt expects rs1, rs2, label")
		return {{op="blt", operands={operands[2], operands[1], operands[3]}}}

	elseif op == "ble" then
		assert(#operands == 3, "ble expects rs1, rs2, label")
		return {{op="bge", operands={operands[2], operands[1], operands[3]}}}

	elseif op == "bgtu" then
		assert(#operands == 3, "bgtu expects rs1, rs2, label")
		return {{op="bltu", operands={operands[2], operands[1], operands[3]}}}

	elseif op == "bleu" then
		assert(#operands == 3, "bleu expects rs1, rs2, label")
		return {{op="bgeu", operands={operands[2], operands[1], operands[3]}}}

	elseif op == "zext.b" then
		assert(#operands == 2, "zext.b expects rd, rs")
		return {{op="andi", operands={operands[1], operands[2], "255"}}}

	elseif op == "sext.w" then
		assert(#operands == 2, "sext.w expects rd, rs")
		return {{op="addi", operands={operands[1], operands[2], "0"}}}

	-- CSR pseudo-instructions
	elseif op == "csrr" then
		assert(#operands == 2, "csrr expects rd, csr")
		return {{op="csrrs", operands={operands[1], operands[2], "x0"}}}

	elseif op == "csrw" then
		assert(#operands == 2, "csrw expects csr, rs")
		return {{op="csrrw", operands={"x0", operands[1], operands[2]}}}

	elseif op == "csrs" then
		assert(#operands == 2, "csrs expects csr, rs")
		return {{op="csrrs", operands={"x0", operands[1], operands[2]}}}

	elseif op == "csrc" then
		assert(#operands == 2, "csrc expects csr, rs")
		return {{op="csrrc", operands={"x0", operands[1], operands[2]}}}

	elseif op == "csrwi" then
		assert(#operands == 2, "csrwi expects csr, imm")
		return {{op="csrrwi", operands={"x0", operands[1], operands[2]}}}

	elseif op == "csrsi" then
		assert(#operands == 2, "csrsi expects csr, imm")
		return {{op="csrrsi", operands={"x0", operands[1], operands[2]}}}

	elseif op == "csrci" then
		assert(#operands == 2, "csrci expects csr, imm")
		return {{op="csrrci", operands={"x0", operands[1], operands[2]}}}

	elseif op == "rdcycle" then
		assert(#operands == 1, "rdcycle expects rd")
		return {{op="csrrs", operands={operands[1], "0xC00", "x0"}}}

	elseif op == "rdtime" then
		assert(#operands == 1, "rdtime expects rd")
		return {{op="csrrs", operands={operands[1], "0xC01", "x0"}}}

	elseif op == "rdinstret" then
		assert(#operands == 1, "rdinstret expects rd")
		return {{op="csrrs", operands={operands[1], "0xC02", "x0"}}}

	elseif op == "fence.tso" then
		return {{op="fence", operands={}}}

	end

	return nil
end

function Parser.assemble(source, options)
	options = options or {}
	local textBase = options.textBase or 0
	local dataBase = options.dataBase or 0x10000000

	local lines = {}
	for line in source:gmatch("[^\r\n]+") do
		local cleaned = stripComments(line)
		if cleaned ~= "" then
			table.insert(lines, cleaned)
		end
	end

	local labels = {}
	local instructions = {}
	local dataItems = {}
	local pc = textBase
	local dc = dataBase
	local section = ".text"

	local symbolExprs = {}

	-- pass 1: symbol resolution and address measurement
	for _, line in ipairs(lines) do
		-- Symbol assignment: sym = expr or .equ sym, expr or .set sym, expr
		local symAssign, exprStr = line:match("^([%w_][%w%d_]*)%s*=%s*(.*)$")
		if not symAssign then
			symAssign, exprStr = line:match("^%.equ%s+([%w_][%w%d_]*),%s*(.*)$")
			if not symAssign then 
				symAssign, exprStr = line:match("^%.set%s+([%w_][%w%d_]*),%s*(.*)$") 
			end
		end
		
		if symAssign and exprStr then
			-- Evaluate it right away (assumes dependencies are already defined)
			local val = evaluateExpression(exprStr, labels, section == ".text" and pc or dc)
			if val then
				labels[symAssign] = val
			else
				symbolExprs[symAssign] = {expr = exprStr, addr = section == ".text" and pc or dc}
			end
			line = ""
		end

		local label, rest = line:match("^([%w_][%w%d_]*):(.*)$")
		if label then
			if section == ".text" then
				labels[label] = pc
			else
				labels[label] = dc  
			end
			line = trim(rest)
		end

		if line == "" then
			-- Empty line
		elseif line:match("^%.") then
			-- Directive processing
			if line == ".text" or line == ".section .text" then
				section = ".text"
			elseif line == ".data" or line == ".section .data" then
				section = ".data"
			elseif line == ".bss" or line == ".section .bss" then
				section = ".bss"
			elseif line == ".rodata" or line == ".section .rodata" then
				section = ".data" -- map rodata to data for now
			elseif line:match("^%.globl") or line:match("^%.global") or line:match("^%.local") or line:match("^%.type") or line:match("^%.size") then
				-- Ignored metadata directives
			elseif line:match("^%.align") or line:match("^%.p2align") then
				local n = parseNumber(line:match("^%.%w+%s+(%d+)") or "0")
				local align = bit32.lshift(1, n) -- 2^n alignment
				if section == ".text" then
					pc = math.ceil(pc / align) * align
				else
					dc = math.ceil(dc / align) * align
				end
			elseif line:match("^%.balign") then
				local align = parseNumber(line:match("^%.balign%s+(%d+)") or "1")
				if section == ".text" then
					pc = math.ceil(pc / align) * align
				else
					dc = math.ceil(dc / align) * align
				end
			elseif line:match("^%.ascii") then
				local str = line:match('%.ascii%s+"(.*)"') or ""
				str = str:gsub("\\n", "\n"):gsub("\\t", "\t"):gsub("\\r", "\r"):gsub("\\\\", "\\"):gsub('\\"', '"')
				table.insert(dataItems, {type="ascii", text=str, addr=dc, nullTerm=false})
				dc = dc + #str
			elseif line:match("^%.asciz") or line:match("^%.string") then
				local str = line:match('%.%w+%s+"(.*)"') or ""
				str = str:gsub("\\n", "\n"):gsub("\\t", "\t"):gsub("\\r", "\r"):gsub("\\\\", "\\"):gsub('\\"', '"')
				table.insert(dataItems, {type="ascii", text=str, addr=dc, nullTerm=true})
				dc = dc + #str + 1
			elseif line:match("^%.word") or line:match("^%.long") or line:match("^%.4byte") then
				local values = line:match("%.%w+%s+(.+)")
				local count = 0
				if values then
					for _ in values:gmatch("[^,%s]+") do count = count + 1 end
				end
				table.insert(dataItems, {type="data", size=4, text=values or "", addr=dc})
				dc = dc + count * 4
			elseif line:match("^%.half") or line:match("^%.short") or line:match("^%.2byte") then
				local values = line:match("%.%w+%s+(.+)")
				local count = 0
				if values then
					for _ in values:gmatch("[^,%s]+") do count = count + 1 end
				end
				table.insert(dataItems, {type="data", size=2, text=values or "", addr=dc})
				dc = dc + count * 2
			elseif line:match("^%.byte") then
				local values = line:match("%.byte%s+(.+)")
				local count = 0
				if values then
					for _ in values:gmatch("[^,%s]+") do count = count + 1 end
				end
				table.insert(dataItems, {type="data", size=1, text=values or "", addr=dc})
				dc = dc + count * 1
			elseif line:match("^%.space") or line:match("^%.skip") or line:match("^%.zero") then
				local size = parseNumber(line:match("%.%w+%s+(%d+)") or "0")
				table.insert(dataItems, {type="space", size=size, addr=dc})
				dc = dc + size
			elseif line:match("^%.comm") or line:match("^%.lcomm") then
				local sym, sizeStr = line:match("^%.%w+%s+([%w_][%w%d_]*),%s*(%d+)")
				if sym and sizeStr then
					local size = parseNumber(sizeStr) or 0
					labels[sym] = dc
					table.insert(dataItems, {type="space", size=size, addr=dc})
					dc = dc + size
				end
			end
		else
			-- Instruction processing
			if section == ".text" then
				local opMatch = line:match("^([%w%.]+)")
				if opMatch then
					local op = opMatch:lower()
					local rest = line:match("^[%w%.]+%s*(.*)") or ""
					local operands = splitOperands(rest)

					local expanded = expandPseudo(op, operands)
					if expanded then
						for _, inst in ipairs(expanded) do
							inst.pc = pc
							table.insert(instructions, inst)
							pc = pc + 4
						end
					else
						local inst = {op=op, operands=operands, pc=pc}
						table.insert(instructions, inst)
						pc = pc + 4
					end
				end
			end
		end
	end

	-- flush out any unresolved expressions now that all labels are known
	for sym, data in pairs(symbolExprs) do
		local val = evaluateExpression(data.expr, labels, data.addr)
		if val then labels[sym] = val end
	end

	-- populate .data and .bss memory map
	local dataBytes = {}
	for _, item in ipairs(dataItems) do
		if item.type == "ascii" then
			for i = 1, #item.text do
				dataBytes[item.addr + i - 1] = string.byte(item.text, i)
			end
			if item.nullTerm then
				dataBytes[item.addr + #item.text] = 0
			end
		elseif item.type == "data" then
			local idx = 0
			for value in item.text:gmatch("[^,%s]+") do
				local num = evaluateExpression(value, labels, item.addr) or 0
				local addr = item.addr + idx * item.size
				
				dataBytes[addr] = bit32.band(num, 0xFF)
				if item.size >= 2 then
					dataBytes[addr + 1] = bit32.band(bit32.rshift(num, 8), 0xFF)
				end
				if item.size >= 4 then
					dataBytes[addr + 2] = bit32.band(bit32.rshift(num, 16), 0xFF)
					dataBytes[addr + 3] = bit32.band(bit32.rshift(num, 24), 0xFF)
				end
				idx = idx + 1
			end
		elseif item.type == "space" then
			for i = 0, item.size - 1 do
				dataBytes[item.addr + i] = 0
			end
		end
	end

	-- pass 2: final instruction generation
	-- here we resolve deferred pseudo-instructions like li and la now that all labels are known
	-- since they were allocated specific sizes in pass 1, we stuff their full 32-bit values 
	-- into a single addi 'imm' field to keep the instruction count consistent for the VM
	local program = {
		textBase = textBase,
		dataBase = dataBase,
		labels = labels,
		code = {},
		data = dataBytes,
		pcToIndex = {}
	}

	for i, inst in ipairs(instructions) do
		program.pcToIndex[inst.pc] = i

		local parsedInst = {op = inst.op, pc = inst.pc}

		-- Handle special pseudo-instructions
		if inst.op == "li_pseudo" then
			local rd = assert(Spec.regId(inst.rd), "Invalid register: " .. inst.rd)
			local imm = evaluateExpression(inst.imm, labels, inst.pc) or 0

			parsedInst.op = "addi"
			parsedInst.rd = rd
			parsedInst.rs1 = 0
			parsedInst.imm = imm -- encode full value

		elseif inst.op == "la_pseudo" then
			local rd = assert(Spec.regId(inst.rd), "Invalid register: " .. inst.rd)
			local addr = assert(evaluateExpression(inst.symbol, labels, inst.pc), "Unknown symbol/expression: " .. inst.symbol)

			parsedInst.op = "addi"
			parsedInst.rd = rd
			parsedInst.rs1 = 0
			parsedInst.imm = addr -- encode full address

		else
			-- Parse regular instruction
			local ops = inst.operands or {}

			-- R-type instructions
			if RV32I_R[inst.op] or RV32M[inst.op] then
				assert(#ops == 3, inst.op .. " expects 3 operands")
				parsedInst.rd = assert(Spec.regId(ops[1]), "Invalid register: " .. ops[1])
				parsedInst.rs1 = assert(Spec.regId(ops[2]), "Invalid register: " .. ops[2])
				parsedInst.rs2 = assert(Spec.regId(ops[3]), "Invalid register: " .. ops[3])

				-- I-type instructions
			elseif RV32I_I[inst.op] then
				assert(#ops == 3, inst.op .. " expects 3 operands")
				parsedInst.rd = assert(Spec.regId(ops[1]), "Invalid register: " .. ops[1])
				parsedInst.rs1 = assert(Spec.regId(ops[2]), "Invalid register: " .. ops[2])
				parsedInst.imm = evaluateExpression(ops[3], labels, inst.pc) or 0

				-- Load instructions
			elseif RV32I_LOAD[inst.op] then
				assert(#ops == 2, inst.op .. " expects 2 operands")
				parsedInst.rd = assert(Spec.regId(ops[1]), "Invalid register: " .. ops[1])
				local offset, base = parseOffsetRegister(ops[2])
				assert(offset and base, "Invalid addressing mode: " .. ops[2])
				parsedInst.rs1 = base
				parsedInst.imm = offset

				-- Store instructions  
			elseif RV32I_STORE[inst.op] then
				assert(#ops == 2, inst.op .. " expects 2 operands")
				parsedInst.rs2 = assert(Spec.regId(ops[1]), "Invalid register: " .. ops[1])
				local offset, base = parseOffsetRegister(ops[2])
				assert(offset and base, "Invalid addressing mode: " .. ops[2])
				parsedInst.rs1 = base
				parsedInst.imm = offset

				-- Branch instructions
			elseif RV32I_BRANCH[inst.op] then
				assert(#ops == 3, inst.op .. " expects 3 operands")
				parsedInst.rs1 = assert(Spec.regId(ops[1]), "Invalid register: " .. ops[1])
				parsedInst.rs2 = assert(Spec.regId(ops[2]), "Invalid register: " .. ops[2])
				parsedInst.target = ops[3]
				parsedInst.targetAddr = assert(labels[ops[3]], "Unknown label: " .. ops[3])

				-- FIXED: Jump instructions with proper operand handling
			elseif RV32I_J[inst.op] then
				if inst.op == "jal" then
					assert(#ops >= 1 and #ops <= 2, "jal expects 1 or 2 operands")
					if #ops == 1 then
						parsedInst.rd = 1 -- ra (default)
						parsedInst.target = ops[1]
					else
						parsedInst.rd = assert(Spec.regId(ops[1]), "Invalid register: " .. ops[1])
						parsedInst.target = ops[2]
					end
					parsedInst.targetAddr = assert(labels[parsedInst.target], "Unknown label: " .. parsedInst.target)

				elseif inst.op == "jalr" then
					assert(#ops >= 1 and #ops <= 3, "jalr expects 1-3 operands")
					if #ops == 1 then
						parsedInst.rd = 1 -- ra (default)
						parsedInst.rs1 = assert(Spec.regId(ops[1]), "Invalid register: " .. ops[1])
						parsedInst.imm = 0
					elseif #ops == 2 then
						parsedInst.rd = assert(Spec.regId(ops[1]), "Invalid register: " .. ops[1])
						local offset, base = parseOffsetRegister(ops[2])
						if offset and base then
							parsedInst.rs1 = base
							parsedInst.imm = offset
						else
							parsedInst.rs1 = assert(Spec.regId(ops[2]), "Invalid register: " .. ops[2])
							parsedInst.imm = 0
						end
					else -- #ops == 3
						parsedInst.rd = assert(Spec.regId(ops[1]), "Invalid register: " .. ops[1])
						parsedInst.rs1 = assert(Spec.regId(ops[2]), "Invalid register: " .. ops[2])
						parsedInst.imm = evaluateExpression(ops[3], labels, inst.pc) or 0
					end
				end

				-- U-type instructions  
			elseif RV32I_U[inst.op] then
				assert(#ops == 2, inst.op .. " expects 2 operands")
				parsedInst.rd = assert(Spec.regId(ops[1]), "Invalid register: " .. ops[1])
				parsedInst.imm = evaluateExpression(ops[2], labels, inst.pc) or 0

				-- CSR instructions
			elseif RV32_CSR[inst.op] then
				assert(#ops == 3, inst.op .. " expects 3 operands")
				parsedInst.rd = assert(Spec.regId(ops[1]), "Invalid register: " .. ops[1])
				parsedInst.csr = parseNumber(ops[2]) or 0
				if inst.op:sub(-1) == "i" then
					parsedInst.imm = parseNumber(ops[3]) or 0
				else
					parsedInst.rs1 = assert(Spec.regId(ops[3]), "Invalid register: " .. ops[3])
				end

				-- System instructions
			elseif RV32I_SYSTEM[inst.op] or inst.op == "fence.i" then
				-- No operands needed

			else
				error("Unknown instruction: " .. inst.op)
			end
		end

		table.insert(program.code, parsedInst)
	end

	return program
end

return Parser
