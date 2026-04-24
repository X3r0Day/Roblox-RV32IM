local Parser = require(game.ReplicatedStorage.RiscV.Parser)
local CPU = require(game.ReplicatedStorage.RiscV.CPU)
local Programs = require(game.ReplicatedStorage.RiscV.Programs)
local UserPrograms = require(game.ReplicatedStorage.RiscV.UserPrograms)

local PROGRAM_TO_RUN = "SierpinskiTriangle"
local USE_USER_PROGRAMS = true

local function runProgram(programName, source)
	local output = ""

	print(string.rep("=", 48))
	print("  RISC-V Emulator - By X3r0Day (RV32IM)")
	print(string.rep("=", 48))
	print("  Running: " .. programName)
	print(string.rep("-", 48))

	-- catch syntax/label errors early before we even spin up the CPU state
	local ok, prog = pcall(function()
		return Parser.assemble(source, {textBase = 0x00000000, dataBase = 0x10000000})
	end)
	
	if not ok then
		print("  ASSEMBLY ERROR: " .. tostring(prog))
		print(string.rep("=", 48))
		return
	end

	local exitCode = 0
	local cpu = CPU.new(prog, {
		debug = false,
		-- wire up the syscall interceptor
		-- this catches 'ecall' instructions and routes them to our lua host instead of crashing
		onEcall = function(self)
			local syscall = self:getReg(17)

			if syscall == 64 then
				-- technically this assumes fd=1 is always stdout, but it's good enough for testing programs
				local fd  = self:getReg(10)
				local buf = self:getReg(11)
				local len = self:getReg(12)
				
				if fd == 1 then
					local str = ""
					for i = 0, len - 1 do
						local byte = self:load8(buf + i)
						if byte == 0 then break end
						str = str .. string.char(byte)
					end
					output = output .. str
					self:setReg(10, len)
				end

			elseif syscall == 63 then
				-- todo: implement fd reads (blocked until we mock the VFS)
				self:setReg(10, 0)

			elseif syscall == 93 then
				exitCode = self:getReg(10)
				self.running = false

			else
				print(string.format("  [WARN] Unknown syscall: %d", syscall))
			end
		end
	})

	-- hard cap at 1M steps so studio doesn't hang on an infinite loop
	local startTime = tick()
	local steps = cpu:run(1000000)
	local elapsed = (tick() - startTime) * 1000

	if #output > 0 then
		for line in (output):gmatch("([^\n]*)\n?") do
			if #line > 0 then
				print("  " .. line)
			end
		end
	end

	print(string.rep("-", 48))
	print(string.format("  Steps: %d | Time: %.3fms | Exit: %d", steps, elapsed, exitCode))
	print(string.rep("=", 48))
end

-- fallback to standard programs if they typo'd the name or it doesn't exist in UserPrograms
-- basically UserPrograms.lua is considered first and then Programs.lua
-- the emulator is now driven by the client UI in src/Client/EmulatorUI.client.lua
-- uncomment the lines below if you want to run headlessly on the server

--[[
local source
if USE_USER_PROGRAMS then
	source = UserPrograms[PROGRAM_TO_RUN]
else
	source = Programs[PROGRAM_TO_RUN]
end

if source then
	runProgram(PROGRAM_TO_RUN, source)
else
	local pool = USE_USER_PROGRAMS and UserPrograms or Programs
	print("Program '" .. PROGRAM_TO_RUN .. "' not found!")
	
	local names = {}
	for k in pairs(pool) do table.insert(names, k) end
	print("Available: " .. table.concat(names, ", "))
end
]]
