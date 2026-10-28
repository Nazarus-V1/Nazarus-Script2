local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RS = game:GetService("ReplicatedStorage")

local Remotes = RS:WaitForChild("Remotes")
local BuyEgg = Remotes:WaitForChild("BuyEgg")
local BuyTool = Remotes:WaitForChild("BuyTool")
local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui")

-- ===== SETTINGS =====
local KEY_EGGS = Enum.KeyCode.R
local KEY_GEAR = Enum.KeyCode.T

local EGG_INTERVAL = 0.15
local EGG_RETRY_AFTER = 1.5

local GEAR_POLL = 1.0 
-- Use the exact names shown in the shop (e.g. "Invisibility Cloak" would work too)
local GEAR_ITEMS = {
	"Giant Luck Spray", 
	"Giant Size Spray", 
	"Luck Spray", 
	"Size Spray", 
	"Volcanic Spray", 
	"Shock Spray"
}

local DEBUG = false
-- ========================

local GREEN = Color3.fromRGB(70, 220, 110)
local RED = Color3.fromRGB(220, 60, 60)

local alive = true
local eggEnabled, gearEnabled = false, false
local conns = {}

local eggSelected = {}
local gearSelected = {}
local gearState = {}
for _, n in ipairs(GEAR_ITEMS) do
	gearSelected[n] = false
	gearState[n] = {label = nil, stock = nil, lockedAt = nil, nextFind = 0, pending = nil}
end

-- PURCHASE COUNTERS
local eggCounts = {}
local gearCounts = {}
for _, n in ipairs(GEAR_ITEMS) do gearCounts[n] = 0 end

local prompts = {}
local eggSent, gearSent = 0, 0
local gearHint = false -- text shown while some spray stock can't be read
local gearNote, gearNoteUntil = nil, 0 -- temporary note (e.g. stock didn't change)

local ID_KEYS = {"Id", "ID", "id", "EggId", "EggID", "Guid", "GUID", "UUID", "Uid", "UID"}
local GUID = "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"

local function findId(prompt)
	local inst = prompt.Parent
	while inst and inst ~= workspace do
		for _, k in ipairs(ID_KEYS) do
			local a = inst:GetAttribute(k)
			if typeof(a) == "string" and a ~= "" then return a end
			local v = inst:FindFirstChild(k)
			if v and v:IsA("StringValue") and v.Value ~= "" then return v.Value end
		end
		if inst.Name:match(GUID) then return inst.Name end
		inst = inst.Parent
	end
	return nil
end

local function eggName(prompt)
	if prompt.ObjectText ~= "" then return prompt.ObjectText end
	local m = prompt:FindFirstAncestorOfClass("Model")
	return m and m.Name or (prompt.Parent and prompt.Parent.Name) or "?"
end

-- ===== UI =====
for _, n in ipairs({"AutoBuyUI"}) do
	local old = pg:FindFirstChild(n)
	if old then old:Destroy() end
end

local gui = Instance.new("ScreenGui")
gui.Name = "AutoBuyUI"
gui.ResetOnSpawn = false
gui.Parent = pg

-- ===== STYLE =====
local WIN_W, WIN_H = 460, 360
local C = {
	window = Color3.fromRGB(8, 8, 10),
	panel = Color3.fromRGB(18, 18, 22),
	card = Color3.fromRGB(28, 28, 33),
	text = Color3.fromRGB(240, 240, 245),
	sub = Color3.fromRGB(150, 150, 160),
	line = Color3.fromRGB(255, 255, 255),
	off = Color3.fromRGB(70, 70, 78),
	on = GREEN,
}

local function corner(inst, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = inst
	return c
end

local function addStroke(inst, color, transparency, thickness)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Transparency = transparency
	s.Thickness = thickness
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = inst
	return s
end

local function makeLabel(parent, text, size, font, color, pos, sz)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextSize = size
	l.Font = font
	l.TextColor3 = color
	l.Position = pos
	l.Size = sz
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.Parent = parent
	return l
end

local function onPress(obj, callback)
	obj.Active = true
	local down, startPos = false, nil
	obj.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			down = true
			startPos = input.Position
		end
	end)
	obj.InputEnded:Connect(function(input)
		if down and (input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch) then
			down = false
			if (input.Position - startPos).Magnitude < 10 then
				callback()
			end
		end
	end)
end

local function makeToggle(parent)
	local track = Instance.new("Frame")
	track.Size = UDim2.fromOffset(44, 22)
	track.AnchorPoint = Vector2.new(1, 0.5)
	track.Position = UDim2.new(1, -12, 0.5, 0)
	track.BackgroundColor3 = C.off
	track.BorderSizePixel = 0
	track.Parent = parent
	corner(track, 11)

	local knob = Instance.new("Frame")
	knob.Size = UDim2.fromOffset(16, 16)
	knob.Position = UDim2.new(0, 3, 0.5, -8)
	knob.BackgroundColor3 = Color3.new(1, 1, 1)
	knob.BorderSizePixel = 0
	knob.Parent = track
	corner(knob, 8)

	local function set(on, animate)
		local info = TweenInfo.new(animate == false and 0 or 0.15)
		TweenService:Create(track, info, {BackgroundColor3 = on and C.on or C.off}):Play()
		TweenService:Create(knob, info, {
			Position = on and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)
		}):Play()
	end
	set(false, false)
	return set
end

local function makeCard(parent, height, titleText, descText)
	local card = Instance.new("Frame")
	card.Size = UDim2.new(1, 0, 0, height)
	card.BackgroundColor3 = C.card
	card.BackgroundTransparency = 0.35
	card.BorderSizePixel = 0
	card.Parent = parent
	corner(card, 8)
	local cardStroke = addStroke(card, C.line, 0.9, 1)

	local ty = math.floor((height - 32) / 2)
	local t = makeLabel(card, titleText, 13, Enum.Font.GothamBold, C.text,
		UDim2.fromOffset(12, ty), UDim2.new(1, -70, 0, 16))
	local d = makeLabel(card, descText, 11, Enum.Font.Gotham, C.sub,
		UDim2.fromOffset(12, ty + 17), UDim2.new(1, -70, 0, 14))
	local setToggle = makeToggle(card)

	card.MouseEnter:Connect(function()
		TweenService:Create(card, TweenInfo.new(0.12), {BackgroundTransparency = 0.2}):Play()
	end)
	card.MouseLeave:Connect(function()
		TweenService:Create(card, TweenInfo.new(0.12), {BackgroundTransparency = 0.35}):Play()
	end)

	local function click(fn)
		onPress(card, fn)
	end

	return card, t, d, setToggle, cardStroke, click
end

-- ===== WINDOW =====
local container = Instance.new("Frame")
container.Size = UDim2.fromOffset(WIN_W, WIN_H)
container.Position = UDim2.new(0, 16, 0.5, 0)
container.AnchorPoint = Vector2.new(0, 0.5)
container.BackgroundColor3 = C.window
container.BackgroundTransparency = 0.25
container.BorderSizePixel = 0
container.Parent = gui
corner(container, 12)
addStroke(container, C.line, 0.85, 1)

local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 38)
titleBar.BackgroundTransparency = 1
titleBar.Active = true
titleBar.Parent = container

local brand = makeLabel(titleBar, "", 13, Enum.Font.GothamBlack, C.text,
	UDim2.new(0.5, 0, 0, 0), UDim2.new(0.5, -16, 1, 0))
brand.RichText = true
brand.Text = 'NAZARUS <font color="rgb(70,220,110)">V1</font>'
brand.TextXAlignment = Enum.TextXAlignment.Right

local divider = Instance.new("Frame")
divider.Size = UDim2.new(1, -16, 0, 1)
divider.Position = UDim2.fromOffset(8, 38)
divider.BackgroundColor3 = C.line
divider.BackgroundTransparency = 0.9
divider.BorderSizePixel = 0
divider.Parent = container

local dragging = false
local dragStart, startPos

titleBar.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		dragStart = input.Position
		startPos = container.Position
		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				dragging = false
			end
		end)
	end
end)

conns[#conns + 1] = UIS.InputChanged:Connect(function(input)
	if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch) then
		local delta = input.Position - dragStart
		local vs = gui.AbsoluteSize
		local currentHeight = container.AbsoluteSize.Y
		local x = math.clamp(startPos.X.Offset + delta.X, -(WIN_W - 80), vs.X - 80)
		-- AnchorPoint.Y is 0.5, so clamp the window center using its current height.
		local minY = currentHeight / 2 - vs.Y / 2
		local maxY = vs.Y / 2 - currentHeight / 2
		local y = math.clamp(startPos.Y.Offset + delta.Y, minY, maxY)
		container.Position = UDim2.new(startPos.X.Scale, x, startPos.Y.Scale, y)
	end
end)

-- ===== LEFT TAB SIDEBAR =====
local sidebar = Instance.new("Frame")
sidebar.Position = UDim2.fromOffset(8, 46)
sidebar.Size = UDim2.new(0, 110, 1, -54)
sidebar.BackgroundTransparency = 1
sidebar.Parent = container

local sidebarLayout = Instance.new("UIListLayout")
sidebarLayout.Padding = UDim.new(0, 4)
sidebarLayout.SortOrder = Enum.SortOrder.LayoutOrder
sidebarLayout.Parent = sidebar

local showTab

-- returns setActive(active) and setOn(on)
-- setActive: selected tab (highlight + accent bar)
-- setOn: animated green outline while that tab's auto-buy is ON
local function makeSideTab(text, order, onClick)
	local b = Instance.new("Frame")
	b.LayoutOrder = order
	b.Size = UDim2.new(1, 0, 0, 34)
	b.BackgroundColor3 = Color3.new(1, 1, 1)
	b.BackgroundTransparency = 1
	b.BorderSizePixel = 0
	b.Parent = sidebar
	corner(b, 8)

	local tabStroke = Instance.new("UIStroke")
	tabStroke.Color = GREEN
	tabStroke.Thickness = 1.5
	tabStroke.Transparency = 1
	tabStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	tabStroke.Parent = b

	local bar = Instance.new("Frame")
	bar.AnchorPoint = Vector2.new(0, 0.5)
	bar.Size = UDim2.fromOffset(3, 6)
	bar.Position = UDim2.new(0, 2, 0.5, 0)
	bar.BackgroundColor3 = C.on
	bar.BackgroundTransparency = 1
	bar.BorderSizePixel = 0
	bar.Parent = b
	corner(bar, 2)

	local l = makeLabel(b, text, 13, Enum.Font.GothamMedium, C.sub,
		UDim2.fromOffset(16, 0), UDim2.new(1, -16, 1, 0))

	local function setActive(active)
		local info = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(b, info, {BackgroundTransparency = active and 0.88 or 1}):Play()
		TweenService:Create(bar, info, {
			BackgroundTransparency = active and 0 or 1,
			Size = UDim2.fromOffset(3, active and 16 or 6),
		}):Play()
		TweenService:Create(l, info, {TextColor3 = active and C.text or C.sub}):Play()
	end

	local pulseToken = 0
	local pulseTween
	local function setOn(on)
		pulseToken += 1
		local token = pulseToken
		if pulseTween then
			pulseTween:Cancel()
			pulseTween = nil
		end
		if on then
			local fadeIn = TweenService:Create(tabStroke,
				TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{Transparency = 0.1})
			fadeIn.Completed:Connect(function()
				if token ~= pulseToken then return end
				pulseTween = TweenService:Create(tabStroke,
					TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
					{Transparency = 0.55})
				pulseTween:Play()
			end)
			fadeIn:Play()
		else
			TweenService:Create(tabStroke,
				TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{Transparency = 1}):Play()
		end
	end

	setActive(false)
	onPress(b, onClick)
	return setActive, setOn
end

-- ===== RIGHT CONTENT PANEL =====
local content = Instance.new("Frame")
content.Position = UDim2.new(0, 126, 0, 46)
content.Size = UDim2.new(1, -134, 1, -54)
content.BackgroundColor3 = C.panel
content.BackgroundTransparency = 0.45
content.BorderSizePixel = 0
content.ClipsDescendants = true
content.Parent = container
corner(content, 10)
addStroke(content, C.line, 0.92, 1)

local setEggTab, setEggOn = makeSideTab("Eggs", 1, function() showTab("eggs") end)
local setGearTab, setGearOn = makeSideTab("Shop", 2, function() showTab("gear") end)
local setCollectTab, setCollectOn = makeSideTab("Collect", 3, function() showTab("collect") end)
local setSettingsTab = makeSideTab("Settings", 4, function() showTab("settings") end)

local function makePage(pageTitle, masterTitle, masterDesc, listTitle)
	local page = Instance.new("Frame")
	page.BackgroundTransparency = 1
	page.Size = UDim2.new(1, 0, 1, 0)
	page.Visible = false
	page.Parent = content

	makeLabel(page, pageTitle, 18, Enum.Font.GothamBold, C.text,
		UDim2.fromOffset(12, 8), UDim2.new(1, -24, 0, 24))

	local header, _, _, setMaster, masterStroke, headerClick = makeCard(page, 54, masterTitle, masterDesc)
	header.Position = UDim2.fromOffset(10, 38)
	header.Size = UDim2.new(1, -20, 0, 54)

	makeLabel(page, listTitle, 11, Enum.Font.GothamMedium, C.sub,
		UDim2.fromOffset(12, 100), UDim2.new(1, -24, 0, 16))

	local scroll = Instance.new("ScrollingFrame")
	scroll.Position = UDim2.fromOffset(10, 122)
	scroll.Size = UDim2.new(1, -20, 1, -148)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 3
	scroll.ScrollBarImageTransparency = 0.5
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = page

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.Name
	layout.Parent = scroll

	local stats = makeLabel(page, "", 11, Enum.Font.Gotham, C.sub,
		UDim2.new(0, 12, 1, -6), UDim2.new(1, -24, 0, 18))
	stats.AnchorPoint = Vector2.new(0, 1)

	local P = {frame = page, header = header, onToggle = headerClick, scroll = scroll, stats = stats}

	function P.setVisual(on)
		setMaster(on)
		TweenService:Create(masterStroke, TweenInfo.new(0.15), {
			Color = on and GREEN or C.line,
			Transparency = on and 0.35 or 0.9,
		}):Play()
	end
	P.setVisual(false)
	return P
end

local eggPage = makePage("Eggs", "Auto buy", "Auto-buys the selected eggs · hotkey R", "EGGS (choose which to buy)")
local gearPage = makePage("Shop", "Auto buy", "Auto-buys the selected sprays · hotkey T", "SPRAYS (choose which to buy)")

local eggRows, gearRows = {}, {}

local function makeRow(scroll, name)
	local card, _, desc, setToggle, _, click = makeCard(scroll, 42, name, "")
	card.Name = name
	card.Size = UDim2.new(1, -6, 0, 42)
	return card, desc, setToggle, click
end

local function paintEgg(name)
	local r = eggRows[name]
	if not r then return end
	local on = eggSelected[name] == true
	r.setToggle(on)
	local count = eggCounts[name] or 0
	r.mark.Text = "Purchased: " .. count
end

local function paintGear(name)
	local r = gearRows[name]
	if not r then return end
	local on = gearSelected[name] == true
	if r.lastOn ~= on then
		r.lastOn = on
		r.setToggle(on)
	end
	local s = gearState[name].stock
	local count = gearCounts[name] or 0
	r.mark.Text = "Stock: " .. (s ~= nil and ("x" .. s) or "?") .. "  ·  Purchased: " .. count
end

local function addEggRow(name)
	if eggRows[name] then return end
	local b, m, setToggle, click = makeRow(eggPage.scroll, name)
	eggRows[name] = {button = b, mark = m, setToggle = setToggle}
	eggCounts[name] = 0 -- Initialize the counter.
	click(function()
		eggSelected[name] = not eggSelected[name] or nil
		paintEgg(name)
	end)
	paintEgg(name)
end

for i, name in ipairs(GEAR_ITEMS) do
	local b, m, setToggle, click = makeRow(gearPage.scroll, name)
	gearRows[name] = {button = b, mark = m, setToggle = setToggle, lastOn = nil}
	click(function()
		gearSelected[name] = not gearSelected[name] or nil
		gearState[name].lockedAt = nil -- allow a fresh attempt after toggling
		paintGear(name)
	end)
	paintGear(name)
end

local function updateEggStats()
	eggPage.stats.Text = "Requests sent: " .. eggSent
end
local function updateGearStats()
	local extra = ""
	if gearHint then
		extra = "  ·  " .. gearHint
	elseif gearNote and os.clock() < gearNoteUntil then
		extra = "  ·  " .. gearNote
	end
	gearPage.stats.Text = "Requests sent: " .. gearSent .. extra
end
updateEggStats()
updateGearStats()

local function kill()
	if not alive then return end
	alive = false
	eggEnabled, gearEnabled = false, false
	for _, c in ipairs(conns) do
		pcall(function() c:Disconnect() end)
	end
	table.clear(conns)
	table.clear(prompts)
	gui:Destroy()
end

-- ===== COLLECT PAGE LOGIC (INTEGRATED) =====
local collectPage = Instance.new("Frame")
collectPage.BackgroundTransparency = 1
collectPage.Size = UDim2.new(1, 0, 1, 0)
collectPage.Visible = false
collectPage.Parent = content

makeLabel(collectPage, "Collect", 18, Enum.Font.GothamBold, C.text,
	UDim2.fromOffset(12, 8), UDim2.new(1, -24, 0, 24))
	
-- UI Card for Auto Collect
local collectCard, _, _, setCollectToggle, collectCardStroke, collectClick = makeCard(collectPage, 54, "Auto Collect", "Teleports to spawn and walks route")
collectCard.Position = UDim2.fromOffset(10, 38)
collectCard.Size = UDim2.new(1, -20, 0, 54)

local collectEnabled = false

-- Movement function for Collect Route
local function moveCharacter(direction, duration)
    local character = player.Character
    if not character then return end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    
    if humanoid and rootPart then
        local targetPosition = rootPart.Position + (direction * 100)
        humanoid:MoveTo(targetPosition)
        task.wait(duration)
        humanoid:MoveTo(rootPart.Position)
    end
end

-- Update visually toggle state
local function updateCollectVisual(on)
	setCollectToggle(on)
	setCollectOn(on) -- Tab Outline Pulse
	TweenService:Create(collectCardStroke, TweenInfo.new(0.15), {
		Color = on and GREEN or C.line,
		Transparency = on and 0.35 or 0.9,
	}):Play()
end

-- UI Card for Frequency Slider
local sliderCard = Instance.new("Frame")
sliderCard.Position = UDim2.fromOffset(10, 100) -- Зміщено під основну кнопку
sliderCard.Size = UDim2.new(1, -20, 0, 54)
sliderCard.BackgroundColor3 = C.card
sliderCard.BackgroundTransparency = 0.35
sliderCard.BorderSizePixel = 0
sliderCard.Parent = collectPage
corner(sliderCard, 8)
addStroke(sliderCard, C.line, 0.9, 1)

local sTitle = makeLabel(sliderCard, "Frequency", 13, Enum.Font.GothamBold, C.text,
	UDim2.fromOffset(12, 11), UDim2.new(1, -120, 0, 16))
local sDesc = makeLabel(sliderCard, "Every 30s", 11, Enum.Font.Gotham, C.sub,
	UDim2.fromOffset(12, 28), UDim2.new(1, -120, 0, 14))

local trackBg = Instance.new("Frame")
trackBg.Size = UDim2.new(0, 120, 0, 4)
trackBg.AnchorPoint = Vector2.new(1, 0.5)
trackBg.Position = UDim2.new(1, -16, 0.5, 0)
trackBg.BackgroundColor3 = C.off
trackBg.BorderSizePixel = 0
trackBg.Parent = sliderCard
corner(trackBg, 2)

local trackFill = Instance.new("Frame")
trackFill.Size = UDim2.new(0, 0, 1, 0)
trackFill.BackgroundColor3 = C.line
trackFill.BorderSizePixel = 0
trackFill.Parent = trackBg
corner(trackFill, 2)

local knob = Instance.new("Frame")
knob.Size = UDim2.fromOffset(14, 14)
knob.AnchorPoint = Vector2.new(0.5, 0.5)
knob.Position = UDim2.new(0, 0, 0.5, 0)
knob.BackgroundColor3 = Color3.new(1, 1, 1)
knob.BorderSizePixel = 0
knob.Parent = trackBg
corner(knob, 7)

local sliderBtn = Instance.new("TextButton")
sliderBtn.Size = UDim2.new(1, 20, 1, 20)
sliderBtn.AnchorPoint = Vector2.new(0.5, 0.5)
sliderBtn.Position = UDim2.new(0.5, 0, 0.5, 0)
sliderBtn.BackgroundTransparency = 1
sliderBtn.Text = ""
sliderBtn.Parent = trackBg

local collectInterval = 30
local minTime = 30
local maxTime = 600
local step = 30

local function formatTime(seconds)
	if seconds < 60 then return seconds .. "s" end
	local m = math.floor(seconds / 60)
	local s = seconds % 60
	if s == 0 then return m .. "m" end
	return m .. "m " .. s .. "s"
end

local function updateSlider(pct)
	pct = math.clamp(pct, 0, 1)
	local rawValue = minTime + (maxTime - minTime) * pct
	local steps = math.floor((rawValue - minTime) / step + 0.5)
	collectInterval = minTime + (steps * step)
	
	local snappedPct = (collectInterval - minTime) / (maxTime - minTime)
	
	TweenService:Create(trackFill, TweenInfo.new(0.1), {Size = UDim2.new(snappedPct, 0, 1, 0)}):Play()
	TweenService:Create(knob, TweenInfo.new(0.1), {Position = UDim2.new(snappedPct, 0, 0.5, 0)}):Play()
	sDesc.Text = "Every " .. formatTime(collectInterval)
end

local sliderDragging = false
sliderBtn.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		sliderDragging = true
		local pct = (input.Position.X - trackBg.AbsolutePosition.X) / trackBg.AbsoluteSize.X
		updateSlider(pct)
	end
end)

UIS.InputChanged:Connect(function(input)
	if sliderDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
		local pct = (input.Position.X - trackBg.AbsolutePosition.X) / trackBg.AbsoluteSize.X
		updateSlider(pct)
	end
end)

UIS.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		sliderDragging = false
	end
end)

updateSlider(0) -- Ініціалізація на 30 секунд

-- Collect Card Logic
collectClick(function()
    collectEnabled = not collectEnabled
    updateCollectVisual(collectEnabled)
    
    if collectEnabled then
        task.spawn(function()
            while collectEnabled do
                -- ==========================================
                -- ЧАСТИНА 1: ТЕЛЕПОРТ
                -- ==========================================
                local success, err = pcall(function()
                    local Packages = RS:FindFirstChild("Packages")
                    if Packages then
                        local Knit = Packages:FindFirstChild("_Index")
                        if Knit then
                            local PlotService = Knit:FindFirstChild("sleitnick_knit@1.7.0")
                            if PlotService then
                                local RF = PlotService:FindFirstChild("knit"):FindFirstChild("Services"):FindFirstChild("PlotService"):FindFirstChild("RF"):FindFirstChild("TeleportSpawn")
                                if RF then
                                    RF:InvokeServer()
                                else
                                    warn("Не знайдено RemoteFunction TeleportSpawn")
                                end
                            end
                        end
                    end
                end)

                local character = player.Character
                while collectEnabled and (not character or not character:FindFirstChild("HumanoidRootPart")) do
                    task.wait(0.05)
                    character = player.Character
                end
                
                if not collectEnabled then break end
                task.wait(0.2) -- Фізика заспокоюється

                -- ==========================================
                -- ЧАСТИНА 2: РУХ ЗА МАРШРУТОМ
                -- ==========================================
                local root = character:FindFirstChild("HumanoidRootPart")
                if root and collectEnabled then 
                    local timeForward = 0.7
                    local timeLeft = 3.0
                    local forwardDir = root.CFrame.LookVector
                    local leftDir = -root.CFrame.RightVector

                    moveCharacter(forwardDir, timeForward)
                    if collectEnabled then 
                        moveCharacter(leftDir, timeLeft)
                    end
                end
                
                -- Чекаємо вибраний на повзунку інтервал
                local waited = 0
                while collectEnabled and waited < collectInterval do
                    task.wait(0.5)
                    waited += 0.5
                end
            end
        end)
    end
end)

-- ===== SETTINGS PAGE =====
local settingsPage = Instance.new("Frame")
settingsPage.BackgroundTransparency = 1
settingsPage.Size = UDim2.new(1, 0, 1, 0)
settingsPage.Visible = false
settingsPage.Parent = content

makeLabel(settingsPage, "Settings", 18, Enum.Font.GothamBold, C.text,
	UDim2.fromOffset(12, 8), UDim2.new(1, -24, 0, 24))
makeLabel(settingsPage, "GENERAL", 11, Enum.Font.GothamMedium, C.sub,
	UDim2.fromOffset(12, 40), UDim2.new(1, -24, 0, 16))

local stopCard = Instance.new("Frame")
stopCard.Position = UDim2.fromOffset(10, 62)
stopCard.Size = UDim2.new(1, -20, 0, 54)
stopCard.BackgroundColor3 = C.card
stopCard.BackgroundTransparency = 0.35
stopCard.BorderSizePixel = 0
stopCard.Parent = settingsPage
corner(stopCard, 8)
addStroke(stopCard, C.line, 0.9, 1)

makeLabel(stopCard, "Stop script", 13, Enum.Font.GothamBold, C.text,
	UDim2.fromOffset(12, 11), UDim2.new(1, -120, 0, 16))
makeLabel(stopCard, "Fully shuts down the script", 11, Enum.Font.Gotham, C.sub,
	UDim2.fromOffset(12, 28), UDim2.new(1, -120, 0, 14))

local stopBtn = Instance.new("Frame")
stopBtn.Size = UDim2.fromOffset(84, 28)
stopBtn.AnchorPoint = Vector2.new(1, 0.5)
stopBtn.Position = UDim2.new(1, -12, 0.5, 0)
stopBtn.BackgroundColor3 = Color3.fromRGB(120, 40, 40)
stopBtn.BorderSizePixel = 0
stopBtn.Parent = stopCard
corner(stopBtn, 8)

local stopText = Instance.new("TextLabel")
stopText.BackgroundTransparency = 1
stopText.Size = UDim2.fromScale(1, 1)
stopText.Text = "STOP"
stopText.Font = Enum.Font.GothamBold
stopText.TextSize = 12
stopText.TextColor3 = Color3.fromRGB(255, 200, 200)
stopText.Parent = stopBtn

local armed = false
onPress(stopBtn, function()
	if not armed then
		armed = true
		stopText.Text = "SURE?"
		task.delay(2.5, function()
			if alive and armed then
				armed = false
				stopText.Text = "STOP"
			end
		end)
	else
		kill()
	end
end)

local tabs = {
	eggs = {page = eggPage, setActive = setEggTab},
	gear = {page = gearPage, setActive = setGearTab},
	collect = {page = {frame = collectPage}, setActive = setCollectTab},
	settings = {page = {frame = settingsPage}, setActive = setSettingsTab},
}

showTab = function(which)
	for name, t in pairs(tabs) do
		t.page.frame.Visible = name == which
		t.setActive(name == which)
	end
end
showTab("eggs")

local function setEgg(v)
	eggEnabled = v
	eggPage.setVisual(v)
	setEggOn(v)
end
local function setGear(v)
	gearEnabled = v
	gearPage.setVisual(v)
	setGearOn(v)
	if v then
		-- fresh start: allow a new purchase attempt for every spray
		for _, s in pairs(gearState) do s.lockedAt = nil end
	end
end

eggPage.onToggle(function() setEgg(not eggEnabled) end)
gearPage.onToggle(function() setGear(not gearEnabled) end)

conns[#conns + 1] = UIS.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == KEY_EGGS then setEgg(not eggEnabled) 
	elseif input.KeyCode == KEY_GEAR then setGear(not gearEnabled) end
end)

-- ===== EGG LOGIC =====
local function track(obj)
	if not obj:IsA("ProximityPrompt") then return end
	local act = obj.ActionText:lower()
	if not (act:find("purchase") or act:find("buy")) then return end
	
	prompts[obj] = 0
	addEggRow(eggName(obj))
	
	obj.AncestryChanged:Connect(function(_, parent)
		if not parent then prompts[obj] = nil end
	end)
end

for _, d in ipairs(workspace:GetDescendants()) do track(d) end
conns[#conns + 1] = workspace.DescendantAdded:Connect(track)

task.spawn(function()
	while gui.Parent do
		if eggEnabled then
			local now = os.clock()
			for prompt, last in pairs(prompts) do
				if not eggEnabled then break end
				if prompt.Parent and prompt.Enabled and now - last >= EGG_RETRY_AFTER
					and eggSelected[eggName(prompt)] then
					
					if not pg:FindFirstChild("PurchasePrompt") then
						prompts[prompt] = os.clock()
						local id = findId(prompt)
						if id then
							pcall(function() BuyEgg:FireServer(id) end)
							eggSent += 1
							local name = eggName(prompt)
							eggCounts[name] = (eggCounts[name] or 0) + 1
							paintEgg(name)
							updateEggStats()
						elseif typeof(fireproximityprompt) == "function" then
							pcall(fireproximityprompt, prompt)
							eggSent += 1
							local name = eggName(prompt)
							eggCounts[name] = (eggCounts[name] or 0) + 1
							paintEgg(name)
							updateEggStats()
						end
						task.wait(EGG_INTERVAL)
					end
				end
			end
		end
		task.wait(0.05)
	end
end)

-- ===== SHOP LOGIC =====
-- Stock is read from the shop's own "xN Stock" labels, so we only buy
-- while the shop shows stock above zero (no Robux prompt can appear).
local function parseStock(text)
	local t = tostring(text)
	t = t:gsub("<[^>]->", "")
	t = t:lower()
	local n = t:match("x%s*(%d+)%s*stock")
		or t:match("(%d+)%s*stock")
		or t:match("stock%s*[:x]%s*(%d+)")
	return n and tonumber(n) or nil
end

local function isText(x)
	return x:IsA("TextLabel") or x:IsA("TextButton")
end

local function norm(s)
	s = tostring(s)
	s = s:gsub("<[^>]->", "")
	s = s:lower():gsub("[^%a]", "")
	return s
end

-- the game's shop: PlayerGui.MainUI.Frames.GearShop.ScrollingFrame
-- every row has a "ToolName" label and a "Stock" label
local function shopScrollFrame()
	local mainUI = pg:FindFirstChild("MainUI")
	local frames = mainUI and mainUI:FindFirstChild("Frames")
	local shop = frames and frames:FindFirstChild("GearShop")
	return shop and shop:FindFirstChild("ScrollingFrame")
end

local function findStockDirect(scroll, itemName)
	local want = norm(itemName)
	for _, row in ipairs(scroll:GetChildren()) do
		local tn = row:FindFirstChild("ToolName")
		local st = row:FindFirstChild("Stock")
		if tn and st and tn:IsA("TextLabel") and st:IsA("TextLabel")
			and norm(tn.Text) == want then
			return st
		end
	end
	return nil
end

-- ---- generic fallback (only used if the shop structure above is not found) ----
local cachedDesc, cachedAt = nil, 0
local function guiDescendants()
	if cachedDesc and os.clock() - cachedAt < 0.5 then return cachedDesc end
	cachedDesc = pg:GetDescendants()
	cachedAt = os.clock()
	return cachedDesc
end

local function sameCluster(a, b)
	return a.Parent == b.Parent or a:IsDescendantOf(b) or b:IsDescendantOf(a)
end

local function pickUnique(found)
	if #found == 0 then return nil end
	local first = found[1]
	local v = parseStock(first.Text)
	for i = 2, #found do
		local x = found[i]
		if parseStock(x.Text) ~= v or not sameCluster(first, x) then
			return nil
		end
	end
	return first
end

local function stockLabelsIn(root)
	local found = {}
	for _, x in ipairs(root:GetDescendants()) do
		if isText(x) and parseStock(x.Text) ~= nil and not x:IsDescendantOf(gui) then
			found[#found + 1] = x
		end
	end
	return found
end

local function findStockGeneric(itemName)
	local want = norm(itemName)
	for _, d in ipairs(guiDescendants()) do
		if isText(d) then
			local t = d.Text
			if #t >= #want and #t <= #itemName + 40 and norm(t) == want
				and not d:IsDescendantOf(gui) then
				local inst = d.Parent
				for _ = 1, 6 do
					if not inst or inst == pg then break end
					local found = stockLabelsIn(inst)
					if #found > 0 then
						local label = pickUnique(found)
						if label then return label end
						break
					end
					inst = inst.Parent
				end
			end
		end
	end
	return nil
end

local function findStockLabel(itemName)
	local scroll = shopScrollFrame()
	if scroll then
		return findStockDirect(scroll, itemName)
	end
	return findStockGeneric(itemName)
end

task.spawn(function()
	while gui.Parent do
		local ok, err = pcall(function()
			local anyUnknown = false

			for _, name in ipairs(GEAR_ITEMS) do
				local s = gearState[name]
				local label = s.label

				if not (label and label.Parent and label:IsDescendantOf(pg)) then
					s.label = nil
					label = nil
					if os.clock() >= s.nextFind then
						s.nextFind = os.clock() + 3
						s.label = findStockLabel(name)
						label = s.label
					end
				end

				local cur = label and parseStock(label.Text) or nil
				s.stock = cur

				if cur == nil then
					anyUnknown = true
				else
					-- count a purchase only when the stock really dropped after our request
					if s.pending then
						if cur < s.pending.from then
							gearCounts[name] = (gearCounts[name] or 0) + (s.pending.from - cur)
							s.pending = nil
						elseif os.clock() - s.pending.at > 3 then
							s.pending = nil -- the stock did not change
							gearNote = name .. ": stock didn't change (not enough $?)"
							gearNoteUntil = os.clock() + 10
						end
					end

					if cur == 0 or (s.lockedAt and cur ~= s.lockedAt) then
						s.lockedAt = nil
					end

					-- buy ONLY while the shop shows stock above zero
					if gearEnabled and gearSelected[name] and cur > 0 and not s.lockedAt then
						s.lockedAt = cur
						s.pending = {from = cur, at = os.clock()}
						pcall(function() BuyTool:FireServer(name) end)
						gearSent += 1
					end
				end

				paintGear(name)
			end

			gearHint = anyUnknown and "some items not found: check the names" or false
			updateGearStats()
		end)
		if not ok and DEBUG then warn("[AutoBuy] shop error:", err) end
		task.wait(GEAR_POLL)
	end
end)


-- ===== COLLAPSE BUTTON (ADDED; EXISTING SCRIPT LOGIC UNCHANGED) =====
-- Keeps the top bar visible and smoothly folds the window upward.
container.ClipsDescendants = true

local collapseButton = Instance.new("TextButton")
collapseButton.Name = "CollapseButton"
collapseButton.Size = UDim2.fromOffset(28, 26)
collapseButton.AnchorPoint = Vector2.new(1, 0)
collapseButton.Position = UDim2.new(1, -7, 0, 6)
collapseButton.BackgroundColor3 = Color3.fromRGB(28, 28, 33)
collapseButton.BackgroundTransparency = 0.1
collapseButton.BorderSizePixel = 0
collapseButton.Text = "−"
collapseButton.TextColor3 = C.text
collapseButton.TextSize = 20
collapseButton.Font = Enum.Font.GothamMedium
collapseButton.AutoButtonColor = true
collapseButton.ZIndex = 10
collapseButton.Parent = titleBar
corner(collapseButton, 6)
addStroke(collapseButton, C.line, 0.82, 1)

-- Leave room for the button so the title doesn't overlap it.
brand.Size = UDim2.new(0.5, -48, 1, 0)

local isCollapsed = false
local collapseTween
local expandedSize = UDim2.fromOffset(WIN_W, WIN_H)
local collapsedSize = UDim2.fromOffset(WIN_W, 38)
local expandedPosition = container.Position
local collapsedPosition = container.Position
local collapseInfo = TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)

collapseButton.Activated:Connect(function()
    isCollapsed = not isCollapsed

    if collapseTween then
        collapseTween:Cancel()
    end

    collapseButton.Text = isCollapsed and "+" or "−"

    -- Preserve the current top edge when folding and unfolding.
    local viewportHeight = gui.AbsoluteSize.Y
    local currentCenterY = container.Position.Y.Offset
    if isCollapsed then
        expandedPosition = container.Position
        collapsedPosition = UDim2.new(
            container.Position.X.Scale,
            container.Position.X.Offset,
            container.Position.Y.Scale,
            currentCenterY - (container.AbsoluteSize.Y - 38) / 2
        )
        sidebar.Visible = false
        content.Visible = false
        divider.Visible = false
    else
        sidebar.Visible = true
        content.Visible = true
        divider.Visible = true
    end

    local targetSize = isCollapsed and collapsedSize or expandedSize
    local targetPosition

    if isCollapsed then
        targetPosition = collapsedPosition
    else
        -- Expand from the current collapsed position, including any movement made while collapsed.
        targetPosition = UDim2.new(
            container.Position.X.Scale,
            container.Position.X.Offset,
            container.Position.Y.Scale,
            container.Position.Y.Offset + (WIN_H - 38) / 2
        )
        expandedPosition = targetPosition
    end

    collapseTween = TweenService:Create(container, collapseInfo, {
        Size = targetSize,
        Position = targetPosition
    })
    collapseTween:Play()
end)
-- ===== END COLLAPSE BUTTON =====

-- ===== OPENING ANIMATION AND BRAND LABEL =====
local brandFooter = Instance.new("TextLabel")
brandFooter.Name = "BrandFooter"
brandFooter.BackgroundTransparency = 1
brandFooter.Position = UDim2.new(0, 12, 1, -20)
brandFooter.Size = UDim2.fromOffset(110, 14)
brandFooter.Font = Enum.Font.GothamBold
brandFooter.Text = "NAZARUS V1"
brandFooter.TextSize = 10
brandFooter.TextColor3 = C.sub
brandFooter.TextTransparency = 0.12
brandFooter.TextXAlignment = Enum.TextXAlignment.Left
brandFooter.ZIndex = 10
brandFooter.Parent = container

local openingScale = Instance.new("UIScale")
openingScale.Scale = 0.92
openingScale.Parent = container

local openingTargetPosition = container.Position
container.Position = UDim2.new(
    openingTargetPosition.X.Scale,
    openingTargetPosition.X.Offset,
    openingTargetPosition.Y.Scale,
    openingTargetPosition.Y.Offset + 22
)
container.BackgroundTransparency = 1

local openingInfo = TweenInfo.new(0.38, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
TweenService:Create(openingScale, openingInfo, {Scale = 1}):Play()
TweenService:Create(container, openingInfo, {
    Position = openingTargetPosition,
    BackgroundTransparency = 0.25
}):Play()
-- ===== END OPENING ANIMATION =====
