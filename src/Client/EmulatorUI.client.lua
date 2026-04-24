print("Emulator UI starting...")

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local RiscV = ReplicatedStorage:WaitForChild("RiscV")
local Parser = require(RiscV:WaitForChild("Parser"))
local CPU = require(RiscV:WaitForChild("CPU"))
local UserPrograms = require(RiscV:WaitForChild("UserPrograms"))
local Programs = require(RiscV:WaitForChild("Programs"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local editorCache = {}
local firstProgram = nil
for name, code in pairs(UserPrograms) do
	editorCache[name] = code
	if not firstProgram then firstProgram = name end
end
local currentProgram = nil


local screenGui = Instance.new("ScreenGui")
screenGui.Name = "RiscVEmulator"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.new(1, 0, 1, 0)
mainFrame.Position = UDim2.new(0, 0, 0, 0)
mainFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
mainFrame.BorderSizePixel = 0
mainFrame.Parent = screenGui

local topBar = Instance.new("Frame")
topBar.Name = "TopBar"
topBar.Size = UDim2.new(1, 0, 0, 40)
topBar.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
topBar.BorderSizePixel = 0
topBar.Parent = mainFrame

local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "Title"
titleLabel.Size = UDim2.new(0, 200, 1, 0)
titleLabel.Position = UDim2.new(0.5, -100, 0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "RISC-V IDE"
titleLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
titleLabel.TextXAlignment = Enum.TextXAlignment.Center
titleLabel.Font = Enum.Font.GothamMedium
titleLabel.TextSize = 16
titleLabel.Parent = topBar

local runButton = Instance.new("TextButton")
runButton.Name = "RunButton"
runButton.Size = UDim2.new(0, 80, 0, 26)
runButton.Position = UDim2.new(1, -95, 0, 7)
runButton.BackgroundColor3 = Color3.fromRGB(46, 204, 113)
runButton.Text = "▶ Run"
runButton.TextColor3 = Color3.fromRGB(255, 255, 255)
runButton.Font = Enum.Font.GothamBold
runButton.TextSize = 12
runButton.Parent = topBar

local runCorner = Instance.new("UICorner")
runCorner.CornerRadius = UDim.new(0, 4)
runCorner.Parent = runButton

local terminalButton = Instance.new("TextButton")
terminalButton.Name = "TerminalButton"
terminalButton.Size = UDim2.new(0, 120, 0, 26)
terminalButton.Position = UDim2.new(1, -225, 0, 7)
terminalButton.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
terminalButton.Text = "Toggle Terminal"
terminalButton.TextColor3 = Color3.fromRGB(200, 200, 200)
terminalButton.Font = Enum.Font.Gotham
terminalButton.TextSize = 12
terminalButton.Parent = topBar

local terminalCorner = Instance.new("UICorner")
terminalCorner.CornerRadius = UDim.new(0, 4)
terminalCorner.Parent = terminalButton

local clearButton = Instance.new("TextButton")
clearButton.Name = "ClearButton"
clearButton.Size = UDim2.new(0, 90, 0, 26)
clearButton.Position = UDim2.new(1, -325, 0, 7)
clearButton.BackgroundColor3 = Color3.fromRGB(231, 76, 60)
clearButton.Text = "Clear Output"
clearButton.TextColor3 = Color3.fromRGB(255, 255, 255)
clearButton.Font = Enum.Font.Gotham
clearButton.TextSize = 12
clearButton.Parent = topBar

local clearCorner = Instance.new("UICorner")
clearCorner.CornerRadius = UDim.new(0, 4)
clearCorner.Parent = clearButton


local contentFrame = Instance.new("Frame")
contentFrame.Name = "Content"
contentFrame.Size = UDim2.new(1, 0, 1, -40)
contentFrame.Position = UDim2.new(0, 0, 0, 40)
contentFrame.BackgroundTransparency = 1
contentFrame.Parent = mainFrame


local editorFrame = Instance.new("Frame")
editorFrame.Name = "EditorFrame"
editorFrame.Size = UDim2.new(1, 0, 0.65, 0)
editorFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
editorFrame.BorderSizePixel = 0
editorFrame.Parent = contentFrame


local editorTabBar = Instance.new("ScrollingFrame")
editorTabBar.Name = "EditorTabs"
editorTabBar.Size = UDim2.new(1, 0, 0, 30)
editorTabBar.BackgroundColor3 = Color3.fromRGB(37, 37, 38)
editorTabBar.BorderSizePixel = 0
editorTabBar.CanvasSize = UDim2.new(0, 0, 0, 0)
editorTabBar.AutomaticCanvasSize = Enum.AutomaticSize.X
editorTabBar.ScrollBarThickness = 0
editorTabBar.Parent = editorFrame

local editorTabLayout = Instance.new("UIListLayout")
editorTabLayout.FillDirection = Enum.FillDirection.Horizontal
editorTabLayout.SortOrder = Enum.SortOrder.LayoutOrder
editorTabLayout.Parent = editorTabBar

local inputBox = Instance.new("TextBox")

local function switchEditorTab(name)
	if currentProgram then
		editorCache[currentProgram] = inputBox.Text
	end
	currentProgram = name
	inputBox.Text = editorCache[name] or ""
	

	for _, child in pairs(editorTabBar:GetChildren()) do
		if child:IsA("TextButton") then
			if child.Name == name then
				child.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
				child.TextColor3 = Color3.fromRGB(255, 255, 255)
			else
				child.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
				child.TextColor3 = Color3.fromRGB(150, 150, 150)
			end
		end
	end
end

for name, _ in pairs(editorCache) do
	local tabBtn = Instance.new("TextButton")
	tabBtn.Name = name
	tabBtn.Size = UDim2.new(0, 150, 1, 0)
	tabBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
	tabBtn.BorderSizePixel = 0
	tabBtn.Text = " " .. name .. ".s"
	tabBtn.TextColor3 = Color3.fromRGB(150, 150, 150)
	tabBtn.Font = Enum.Font.Gotham
	tabBtn.TextSize = 12
	tabBtn.TextXAlignment = Enum.TextXAlignment.Left
	tabBtn.Parent = editorTabBar
	
	tabBtn.MouseButton1Click:Connect(function()
		switchEditorTab(name)
	end)
end


local inputScroll = Instance.new("ScrollingFrame")
inputScroll.Name = "InputScroll"
inputScroll.Size = UDim2.new(1, -20, 1, -40)
inputScroll.Position = UDim2.new(0, 10, 0, 40)
inputScroll.BackgroundTransparency = 1
inputScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
inputScroll.AutomaticCanvasSize = Enum.AutomaticSize.XY
inputScroll.ScrollBarThickness = 8
inputScroll.ClipsDescendants = true
inputScroll.Parent = editorFrame

inputBox.Name = "InputBox"
inputBox.Size = UDim2.new(1, 0, 1, 0)
inputBox.AutomaticSize = Enum.AutomaticSize.XY
inputBox.BackgroundTransparency = 1
inputBox.TextColor3 = Color3.fromRGB(212, 212, 212)
inputBox.Font = Enum.Font.Code
inputBox.TextSize = 15
inputBox.TextXAlignment = Enum.TextXAlignment.Left
inputBox.TextYAlignment = Enum.TextYAlignment.Top
inputBox.ClearTextOnFocus = false
inputBox.MultiLine = true
inputBox.TextWrapped = false
inputBox.Parent = inputScroll

if firstProgram then switchEditorTab(firstProgram) end


local divider = Instance.new("TextButton")
divider.Name = "Divider"
divider.Size = UDim2.new(1, 0, 0, 5)
divider.Position = UDim2.new(0, 0, 0.65, 0)
divider.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
divider.BorderSizePixel = 0
divider.Text = ""
divider.Parent = contentFrame


local terminalFrame = Instance.new("Frame")
terminalFrame.Name = "TerminalFrame"
terminalFrame.Size = UDim2.new(1, 0, 0.35, -5)
terminalFrame.Position = UDim2.new(0, 0, 0.65, 5)
terminalFrame.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
terminalFrame.BorderSizePixel = 0
terminalFrame.Parent = contentFrame


local termTabBar = Instance.new("Frame")
termTabBar.Name = "TermTabs"
termTabBar.Size = UDim2.new(1, 0, 0, 30)
termTabBar.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
termTabBar.BorderSizePixel = 0
termTabBar.Parent = terminalFrame

local termTabLayout = Instance.new("UIListLayout")
termTabLayout.FillDirection = Enum.FillDirection.Horizontal
termTabLayout.SortOrder = Enum.SortOrder.LayoutOrder
termTabLayout.Parent = termTabBar

local termViews = {}
local currentTermTab = "Output"

local function switchTermTab(name)
	for tName, v in pairs(termViews) do
		if tName == name then
			v.btn.TextColor3 = Color3.fromRGB(255, 255, 255)
			v.ind.Visible = true
			v.scroll.Visible = true
		else
			v.btn.TextColor3 = Color3.fromRGB(150, 150, 150)
			v.ind.Visible = false
			v.scroll.Visible = false
		end
	end
	currentTermTab = name
end

local function createTermTab(name)
	local tabBtn = Instance.new("TextButton")
	tabBtn.Name = name
	tabBtn.Size = UDim2.new(0, 100, 1, 0)
	tabBtn.BackgroundTransparency = 1
	tabBtn.Text = string.upper(name)
	tabBtn.TextColor3 = Color3.fromRGB(150, 150, 150)
	tabBtn.Font = Enum.Font.GothamMedium
	tabBtn.TextSize = 11
	tabBtn.Parent = termTabBar
	
	local indicator = Instance.new("Frame")
	indicator.Name = "Indicator"
	indicator.Size = UDim2.new(1, 0, 0, 1)
	indicator.Position = UDim2.new(0, 0, 1, -1)
	indicator.BackgroundColor3 = Color3.fromRGB(46, 204, 113)
	indicator.BorderSizePixel = 0
	indicator.Visible = false
	indicator.Parent = tabBtn

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = name.."Scroll"
	scroll.Size = UDim2.new(1, -20, 1, -40)
	scroll.Position = UDim2.new(0, 10, 0, 40)
	scroll.BackgroundTransparency = 1
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.XY
	scroll.ScrollBarThickness = 8
	scroll.ClipsDescendants = true
	scroll.Visible = false
	scroll.Parent = terminalFrame

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.new(1, 0, 1, 0)
	label.AutomaticSize = Enum.AutomaticSize.XY
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(204, 204, 204)
	label.Font = Enum.Font.Code
	label.TextSize = 14
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.Text = ""
	label.Parent = scroll
	
	termViews[name] = {btn = tabBtn, ind = indicator, scroll = scroll, label = label}
	
	tabBtn.MouseButton1Click:Connect(function()
		switchTermTab(name)
	end)
end

createTermTab("Output")
createTermTab("Registers")
createTermTab("Memory")


switchTermTab("Output")
termViews["Output"].label.Text = "Terminal ready.\n"


local dragging = false
local dragStartPos = nil
local dragStartYScale = nil

divider.MouseButton1Down:Connect(function(x, y)
	dragging = true
	dragStartPos = y
	dragStartYScale = editorFrame.Size.Y.Scale
end)

UserInputService.InputChanged:Connect(function(input)
	if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
		local delta = input.Position.Y - dragStartPos
		local deltaScale = delta / contentFrame.AbsoluteSize.Y
		local newScale = math.clamp(dragStartYScale + deltaScale, 0.1, 0.9)
		
		editorFrame.Size = UDim2.new(1, 0, newScale, 0)
		divider.Position = UDim2.new(0, 0, newScale, 0)
		terminalFrame.Position = UDim2.new(0, 0, newScale, 5)
		terminalFrame.Size = UDim2.new(1, 0, 1 - newScale, -5)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		dragging = false
	end
end)


local terminalOpen = true
local savedScale = 0.65

local function updateLayout()
	if terminalOpen then
		editorFrame.Size = UDim2.new(1, 0, savedScale, 0)
		divider.Visible = true
		divider.Position = UDim2.new(0, 0, savedScale, 0)
		terminalFrame.Visible = true
		terminalFrame.Position = UDim2.new(0, 0, savedScale, 5)
		terminalFrame.Size = UDim2.new(1, 0, 1 - savedScale, -5)
	else
		savedScale = editorFrame.Size.Y.Scale
		editorFrame.Size = UDim2.new(1, 0, 1, 0)
		divider.Visible = false
		terminalFrame.Visible = false
	end
end

terminalButton.MouseButton1Click:Connect(function()
	terminalOpen = not terminalOpen
	updateLayout()
end)

local function logOutput(text)
	termViews["Output"].label.Text = termViews["Output"].label.Text .. text
	task.defer(function()
		termViews["Output"].scroll.CanvasPosition = Vector2.new(0, 999999)
	end)
end

clearButton.MouseButton1Click:Connect(function()
	termViews["Output"].label.Text = ""
	termViews["Registers"].label.Text = ""
	termViews["Memory"].label.Text = ""
end)

local isRunning = false
local regNames = {"zero", "ra", "sp", "gp", "tp", "t0", "t1", "t2", "s0/fp", "s1", "a0", "a1", "a2", "a3", "a4", "a5", "a6", "a7", "s2", "s3", "s4", "s5", "s6", "s7", "s8", "s9", "s10", "s11", "t3", "t4", "t5", "t6"}

runButton.MouseButton1Click:Connect(function()
	if isRunning then return end
	isRunning = true
	runButton.Text = "Running..."
	runButton.BackgroundColor3 = Color3.fromRGB(127, 140, 141)
	
	if not terminalOpen then
		terminalOpen = true
		updateLayout()
	end
	

	switchTermTab("Output")
	
	termViews["Output"].label.Text = ""
	local source = inputBox.Text
	
	task.spawn(function()
		logOutput("Assembling...\n")
		
		local ok, prog = pcall(function()
			return Parser.assemble(source, {textBase = 0x00000000, dataBase = 0x10000000})
		end)
		
		if not ok then
			logOutput("\nASSEMBLY ERROR:\n" .. tostring(prog) .. "\n")
			isRunning = false
			runButton.Text = "▶ Run"
			runButton.BackgroundColor3 = Color3.fromRGB(46, 204, 113)
			return
		end
		
		logOutput("Executing...\n\n")
		
		local exitCode = 0
		local rawOutput = ""
		
		local cpu = CPU.new(prog, {
			debug = false,
			onEcall = function(self)
				local syscall = self:getReg(17)

				if syscall == 64 then
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
						rawOutput = rawOutput .. str
						self:setReg(10, len)
					end
				elseif syscall == 63 then
					self:setReg(10, 0)
				elseif syscall == 93 then
					exitCode = self:getReg(10)
					self.running = false
				else
					rawOutput = rawOutput .. string.format("[WARN] Unknown syscall: %d\n", syscall)
				end
			end
		})
		
		local startTime = tick()
		local steps = cpu:run(1000000)
		local elapsed = (tick() - startTime) * 1000
		
		if #rawOutput > 0 then
			logOutput(rawOutput)
			if rawOutput:sub(-1) ~= "\n" then logOutput("\n") end
		end
		
		logOutput(string.format("\n--- Finished ---\nSteps: %d\nTime: %.3fms\nExit Code: %d\n", steps, elapsed, exitCode))
		

		local regStr = "--- Registers at Exit ---\n"
		regStr = regStr .. string.format("PC: 0x%08X\n\n", cpu.pc)
		for i=0, 31 do
			regStr = regStr .. string.format("x%-2d (%-5s): 0x%08X\n", i, regNames[i+1], cpu:getReg(i))
		end
		termViews["Registers"].label.Text = regStr
		

		local memStr = "--- Memory (Non-Zero) ---\n"
		local addrs = {}
		for addr in pairs(cpu.memory) do table.insert(addrs, addr) end
		table.sort(addrs)
		local count = 0
		for _, addr in ipairs(addrs) do
			local val = cpu.memory[addr]
			if val ~= 0 then
				memStr = memStr .. string.format("0x%08X: 0x%02X\n", addr, val)
				count = count + 1
				if count > 1000 then
					memStr = memStr .. "\n... (truncated for performance)\n"
					break
				end
			end
		end
		if count == 0 then memStr = memStr .. "Memory is empty or all zero.\n" end
		termViews["Memory"].label.Text = memStr
		
		isRunning = false
		runButton.Text = "▶ Run"
		runButton.BackgroundColor3 = Color3.fromRGB(46, 204, 113)
	end)
end)
