--[=[
	UH  -  Menu  (Roblox / Luau  |  CoreGui)
	-------------------------------------------------------------------
	1:1 recreation of the "Settings" window:
	  * Sidebar with tabs  (Combat / Visuals / Player / Automation / World / Cosmetics / Settings)
	  * Settings  ->  General | Config Profiles | Theme
	  * Whole-menu config system (create / load / save / delete / export / import / auto save / auto load)
	  * Global search (Ctrl+F), confirm dialogs, notifications, watermark + keybind list HUD, draggable + resizable window

	Run it in an executor.  It mounts to CoreGui (falls back to gethui / PlayerGui).
	Config files live in  <workspace>/UH/configs/*.json   (falls back to memory if the executor has no file API).
]=]

----------------------------------------------------------------------
-- Boot
----------------------------------------------------------------------
local env = (getgenv and getgenv()) or _G

if type(env.UH) == "table" and type(env.UH.Unload) == "function" then
	pcall(env.UH.Unload)
end
if not game:IsLoaded() then
	game.Loaded:Wait()
end

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")
local LocalPlayer = Players.LocalPlayer

local UH = {
	Version = "1.0.0",
	Flags = {},
	Tabs = {},
	TabsByName = {},
	Connections = {},
	Visible = true,
	Unloaded = false,
	MenuKey = Enum.KeyCode.RightShift,
	NotificationsEnabled = true,
	UserScale = 1,
	_index = {},
	_currentDropdown = nil,
	_keybinds = {},
}
env.UH = UH

local ASSETS = {
	Combat = "rbxassetid://99199363807265",
	Visuals = "rbxassetid://127234874352422",
	Player = "rbxassetid://114567720540659",
	Automation = "rbxassetid://70979486241131",
	World = "rbxassetid://125685532120024",
	Cosmetics = "rbxassetid://128162112866809",
	Settings = "rbxassetid://106205298246017",
	Gear = "rbxassetid://106205298246017",
	Search = "rbxassetid://72296609649861",
	Clear = "rbxassetid://116396312853810",
	Chevron = "rbxassetid://84796267467531",
}

----------------------------------------------------------------------
-- Theme
----------------------------------------------------------------------
local Theme = {}

-- Fixed colors (not editable in the Theme tab)
local ThemeBase = {
	InputBackground = Color3.fromRGB(13, 13, 13),
	Title = Color3.fromRGB(235, 235, 235),
	Muted = Color3.fromRGB(140, 140, 140),
	SubText = Color3.fromRGB(105, 105, 105),
}

-- Editable colors (Settings > Theme)
local ThemeDefaults = {
	Accent = Color3.fromRGB(255, 255, 255),
	Background = Color3.fromRGB(0, 0, 0),
	ElementBackground = Color3.fromRGB(6, 6, 6),
	Outline = Color3.fromRGB(24, 24, 24),
	TabButtonSelected = Color3.fromRGB(66, 66, 66),
	TextColor = Color3.fromRGB(197, 197, 197),
	Unselected = Color3.fromRGB(85, 85, 85),
	ToggleCircleUnselected = Color3.fromRGB(85, 85, 85),
	ToggleBackgroundUnselected = Color3.fromRGB(12, 12, 12),
}
local ThemeKeys = {
	{ Key = "Accent", Label = "Accent" },
	{ Key = "Background", Label = "Background" },
	{ Key = "ElementBackground", Label = "Element Background" },
	{ Key = "Outline", Label = "Outline" },
	{ Key = "TabButtonSelected", Label = "Selected Tab" },
	{ Key = "TextColor", Label = "Text" },
	{ Key = "Unselected", Label = "Unselected Text" },
	{ Key = "ToggleCircleUnselected", Label = "Toggle Circle" },
	{ Key = "ToggleBackgroundUnselected", Label = "Toggle Background" },
}
local ThemeValues = {}
for k, v in pairs(ThemeDefaults) do
	ThemeValues[k] = v
end
local TabSelectedCustom = false -- while false, "Selected Tab" follows the accent color

local function darken(c, f)
	return Color3.new(c.R * f, c.G * f, c.B * f)
end

local function recomputeTheme()
	for k, v in pairs(ThemeBase) do
		Theme[k] = v
	end
	for k, v in pairs(ThemeValues) do
		Theme[k] = v
	end
	if not TabSelectedCustom then
		Theme.TabButtonSelected = darken(Theme.Accent, 0.26)
	end
	local base = Theme.TabButtonSelected
	Theme.TabHighlight = Color3.new(math.min(base.R * 1.154, 1), math.min(base.G * 1.154, 1), math.min(base.B * 1.154, 1))
	Theme.TabShadow = darken(base, 0.615)
end
recomputeTheme()

----------------------------------------------------------------------
-- Fonts
----------------------------------------------------------------------
local FONT_FAMILY = "rbxassetid://12187365364"
local function mkFont(weight)
	return Font.new(FONT_FAMILY, weight, Enum.FontStyle.Normal)
end
local Fonts = {
	Regular = mkFont(Enum.FontWeight.Regular),
	Medium = mkFont(Enum.FontWeight.Medium),
	SemiBold = mkFont(Enum.FontWeight.SemiBold),
	Bold = mkFont(Enum.FontWeight.Bold),
	Heavy = mkFont(Enum.FontWeight.Heavy),
}

----------------------------------------------------------------------
-- Utilities
----------------------------------------------------------------------
local function connect(signal, fn)
	local c = signal:Connect(fn)
	UH.Connections[#UH.Connections + 1] = c
	return c
end

local function new(class, props, children)
	local inst = Instance.new(class)
	local parent
	for k, v in pairs(props or {}) do
		if k == "Parent" then
			parent = v
		else
			inst[k] = v
		end
	end
	for _, child in ipairs(children or {}) do
		child.Parent = inst
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function newSignal()
	local handlers = {}
	local signal = {}
	function signal:Connect(fn)
		handlers[#handlers + 1] = fn
		return {
			Disconnect = function()
				local i = table.find(handlers, fn)
				if i then
					table.remove(handlers, i)
				end
			end,
		}
	end
	function signal:Fire(...)
		for _, fn in ipairs(table.clone(handlers)) do
			task.spawn(fn, ...)
		end
	end
	return signal
end

local function safeCall(fn, ...)
	if type(fn) ~= "function" then
		return
	end
	local ok, err = pcall(fn, ...)
	if not ok then
		warn("[UH] callback error: " .. tostring(err))
	end
end

local function tween(inst, props, t)
	local tw = TweenService:Create(inst, TweenInfo.new(t or 0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

-- Theme bindings
local bindings = setmetatable({}, { __mode = "k" })
local themeListeners = {}

local function bind(inst, map)
	local b = bindings[inst]
	if not b then
		b = {}
		bindings[inst] = b
	end
	for prop, key in pairs(map) do
		b[prop] = key
		inst[prop] = Theme[key]
	end
	return inst
end

local function onTheme(fn)
	themeListeners[#themeListeners + 1] = fn
	fn()
end

local function applyTheme()
	for inst, map in pairs(bindings) do
		for prop, key in pairs(map) do
			pcall(function()
				inst[prop] = Theme[key]
			end)
		end
	end
	for _, fn in ipairs(themeListeners) do
		pcall(fn)
	end
end

function UH:SetThemeColor(key, color)
	if ThemeDefaults[key] == nil or typeof(color) ~= "Color3" then
		return
	end
	ThemeValues[key] = color
	if key == "TabButtonSelected" then
		TabSelectedCustom = true
	end
	recomputeTheme()
	applyTheme()
end

function UH:GetThemeColor(key)
	return Theme[key]
end

function UH:SetAccent(color)
	UH:SetThemeColor("Accent", color)
end

function UH:ResetTheme()
	for k, v in pairs(ThemeDefaults) do
		ThemeValues[k] = v
	end
	TabSelectedCustom = false
	recomputeTheme()
	applyTheme()
end
UH.ThemeKeys = ThemeKeys
UH.ThemeDefaults = ThemeDefaults

-- Small builders
local function addCorner(inst, radius)
	return new("UICorner", { CornerRadius = UDim.new(0, radius), Parent = inst })
end

local function addStroke(inst, key, thickness)
	local stroke = new("UIStroke", {
		Color = Theme[key or "Outline"],
		Thickness = thickness or 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = inst,
	})
	bind(stroke, { Color = key or "Outline" })
	return stroke
end

local function addPadding(inst, l, r, t, b)
	return new("UIPadding", {
		PaddingLeft = UDim.new(0, l or 0),
		PaddingRight = UDim.new(0, r or 0),
		PaddingTop = UDim.new(0, t or 0),
		PaddingBottom = UDim.new(0, b or 0),
		Parent = inst,
	})
end

local function newText(props, colorKey)
	local key = colorKey
	if key == nil and props and props.TextColor3 ~= nil then
		key = false
	elseif key == nil then
		key = "TextColor"
	end
	local t = {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		FontFace = Fonts.Medium,
		TextSize = 14,
		TextColor3 = key and Theme[key] or (props and props.TextColor3 or Color3.new(1, 1, 1)),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		Text = "",
	}
	for k, v in pairs(props or {}) do
		t[k] = v
	end
	local inst = new("TextLabel", t)
	if key then
		bind(inst, { TextColor3 = key })
	end
	return inst
end

local function makeIcon(parent, id, px)
	return new("ImageLabel", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Image = id,
		Size = UDim2.fromOffset(px, px),
		ScaleType = Enum.ScaleType.Fit,
		ImageColor3 = Theme.Unselected,
		Parent = parent,
	})
end

-- Shared drag handler
local activeDrag = nil

local Section, Page, Tab = {}, {}, {}
Section.__index = Section
Page.__index = Page
Tab.__index = Tab

----------------------------------------------------------------------
-- Storage + config manager
----------------------------------------------------------------------
local ROOT = "UH"
local CONFIG_DIR = ROOT .. "/configs"
local STATE_PATH = ROOT .. "/state.json"

local FS = { memory = {}, native = false }
do
	FS.native = (env.writefile and env.readfile and env.isfile and env.isfolder and env.makefolder and env.listfiles and env.delfile) and true or false
end

function FS.init()
	if FS.native then
		pcall(function()
			if not env.isfolder(ROOT) then
				env.makefolder(ROOT)
			end
			if not env.isfolder(CONFIG_DIR) then
				env.makefolder(CONFIG_DIR)
			end
		end)
	end
end

function FS.write(path, data)
	if FS.native then
		local ok, err = pcall(env.writefile, path, data)
		if not ok then
			return false, tostring(err)
		end
		return true
	end
	FS.memory[path] = data
	return true
end

function FS.read(path)
	if FS.native then
		local ok, res = pcall(env.readfile, path)
		if ok then
			return res
		end
		return nil, tostring(res)
	end
	local data = FS.memory[path]
	if data == nil then
		return nil, "File not found"
	end
	return data
end

function FS.exists(path)
	if FS.native then
		local ok, res = pcall(env.isfile, path)
		return ok and res == true
	end
	return FS.memory[path] ~= nil
end

function FS.delete(path)
	if FS.native then
		local ok, err = pcall(env.delfile, path)
		if not ok then
			return false, tostring(err)
		end
		return true
	end
	FS.memory[path] = nil
	return true
end

function FS.list(dir)
	local out = {}
	if FS.native then
		local ok, files = pcall(env.listfiles, dir)
		if ok and type(files) == "table" then
			for _, f in ipairs(files) do
				out[#out + 1] = tostring(f)
			end
		end
	else
		for path in pairs(FS.memory) do
			if path:sub(1, #dir + 1) == dir .. "/" then
				out[#out + 1] = path
			end
		end
	end
	return out
end

FS.init()

local Config = {
	Applying = false,
	State = { AutoSave = false, AutoSaveName = nil, AutoLoad = false, AutoLoadName = nil, Positions = {} },
}

local function sanitize(name)
	name = tostring(name or "")
	name = name:gsub("%s+", "")
	name = name:gsub('[\\/:*?"<>|%.]', "")
	return name:sub(1, 32)
end

local function configPath(name)
	return CONFIG_DIR .. "/" .. name .. ".json"
end

function Config.All()
	local names = {}
	for _, file in ipairs(FS.list(CONFIG_DIR)) do
		local n = file:match("([^/\\]+)%.json$")
		if n then
			names[#names + 1] = n
		end
	end
	table.sort(names, function(a, b)
		return a:lower() < b:lower()
	end)
	return names
end

function Config.Snapshot(useDefaults)
	local flags = {}
	for flag, el in pairs(UH.Flags) do
		local value
		if useDefaults then
			value = el.DefaultSerialized
		else
			value = el:Serialize()
		end
		if value ~= nil then
			flags[flag] = value
		end
	end
	return { Version = 1, Menu = "UH", Flags = flags }
end

function Config.Encode(useDefaults)
	local ok, enc = pcall(function()
		return HttpService:JSONEncode(Config.Snapshot(useDefaults))
	end)
	if not ok then
		return nil, tostring(enc)
	end
	return enc
end

function Config.Apply(data)
	if type(data) ~= "table" or type(data.Flags) ~= "table" then
		return false, "Not a valid UH config"
	end
	local count = 0
	Config.Applying = true
	for flag, value in pairs(data.Flags) do
		local el = UH.Flags[flag]
		if el then
			local ok, err = pcall(el.Deserialize, el, value)
			if ok then
				count = count + 1
			else
				warn("[UH] could not apply '" .. tostring(flag) .. "': " .. tostring(err))
			end
		end
	end
	Config.Applying = false
	return true, count
end

function Config.LoadJson(raw)
	local ok, data = pcall(function()
		return HttpService:JSONDecode(raw)
	end)
	if not ok then
		return false, "Invalid JSON"
	end
	return Config.Apply(data)
end

function Config.Create(name)
	name = sanitize(name)
	if name == "" then
		return false, "Enter a config name first"
	end
	if FS.exists(configPath(name)) then
		return false, "A config named '" .. name .. "' already exists"
	end
	local enc, err = Config.Encode(false)
	if not enc then
		return false, err
	end
	local ok, werr = FS.write(configPath(name), enc)
	if not ok then
		return false, werr
	end
	return true, name
end

function Config.Save(name)
	if type(name) ~= "string" or name == "" then
		return false, "Select a config first"
	end
	local enc, err = Config.Encode(false)
	if not enc then
		return false, err
	end
	return FS.write(configPath(name), enc)
end

function Config.Load(name)
	if type(name) ~= "string" or name == "" then
		return false, "Select a config first"
	end
	local raw, err = FS.read(configPath(name))
	if not raw then
		return false, err or "Config file not found"
	end
	return Config.LoadJson(raw)
end

function Config.Delete(name)
	if type(name) ~= "string" or name == "" then
		return false, "Select a config first"
	end
	if not FS.exists(configPath(name)) then
		return false, "Config file not found"
	end
	return FS.delete(configPath(name))
end

function Config.SaveState()
	local s = Config.State
	pcall(function()
		FS.write(
			STATE_PATH,
			HttpService:JSONEncode({
				AutoSave = s.AutoSave,
				AutoSaveName = s.AutoSaveName,
				AutoLoad = s.AutoLoad,
				AutoLoadName = s.AutoLoadName,
				Positions = s.Positions,
			})
		)
	end)
end

function Config.LoadState()
	pcall(function()
		if not FS.exists(STATE_PATH) then
			return
		end
		local raw = FS.read(STATE_PATH)
		local data = HttpService:JSONDecode(raw)
		if type(data) == "table" then
			Config.State.AutoSave = data.AutoSave == true
			Config.State.AutoLoad = data.AutoLoad == true
			if type(data.AutoSaveName) == "string" then
				Config.State.AutoSaveName = data.AutoSaveName
			end
			if type(data.AutoLoadName) == "string" then
				Config.State.AutoLoadName = data.AutoLoadName
			end
			if type(data.Positions) == "table" then
				for key, p in pairs(data.Positions) do
					if type(key) == "string" and type(p) == "table" and type(p[1]) == "number" and type(p[2]) == "number" then
						Config.State.Positions[key] = { p[1], p[2] }
					end
				end
			end
		end
	end)
end

UH.Config = Config

local autoSaveToken = 0
function UH:_changed()
	if Config.Applying or UH.Unloaded then
		return
	end
	local s = Config.State
	local name = s.AutoSaveName
	if s.AutoSave and type(name) == "string" and name ~= "" then
		autoSaveToken = autoSaveToken + 1
		local token = autoSaveToken
		task.delay(1, function()
			if token == autoSaveToken and not UH.Unloaded then
				Config.Save(name)
			end
		end)
	end
end

----------------------------------------------------------------------
-- GUI root
----------------------------------------------------------------------
local Gui = new("ScreenGui", {
	Name = "UH",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 9999,
})
pcall(function()
	if env.syn and env.syn.protect_gui then
		env.syn.protect_gui(Gui)
	end
end)

local function mountGui(gui)
	if pcall(function()
		gui.Parent = CoreGui
	end) and gui.Parent == CoreGui then
		return "CoreGui"
	end
	local ok, hui = pcall(function()
		return env.gethui and env.gethui()
	end)
	if ok and hui then
		local ok2 = pcall(function()
			gui.Parent = hui
		end)
		if ok2 and gui.Parent == hui then
			return "gethui"
		end
	end
	gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
	return "PlayerGui"
end
UH.Gui = Gui
UH.MountedIn = mountGui(Gui)

----------------------------------------------------------------------
-- Window
----------------------------------------------------------------------
local WIN_W, WIN_H = 920, 644
local MIN_W, MIN_H = 800, 520
local MAX_W, MAX_H = 1600, 1000

local Main = new("Frame", {
	Name = "Window",
	Size = UDim2.fromOffset(WIN_W, WIN_H),
	Position = UDim2.fromOffset(100, 100),
	BorderSizePixel = 0,
	Parent = Gui,
})
bind(Main, { BackgroundColor3 = "Background" })
addCorner(Main, 4)
addStroke(Main, "Outline")
local Scale = new("UIScale", { Parent = Main })

local function viewport()
	local cam = workspace.CurrentCamera
	return cam and cam.ViewportSize or Vector2.new(1280, 720)
end

local function updateScale()
	local vp = viewport()
	local w, h = Main.Size.X.Offset, Main.Size.Y.Offset
	local fit = math.min((vp.X - 24) / w, (vp.Y - 24) / h, 1)
	Scale.Scale = math.max(0.35, fit) * UH.UserScale
end

do
	updateScale()
	local vp = viewport()
	Main.Position = UDim2.fromOffset(
		math.floor((vp.X - WIN_W * Scale.Scale) / 2),
		math.floor((vp.Y - WIN_H * Scale.Scale) / 2)
	)
	local cam = workspace.CurrentCamera
	if cam then
		connect(cam:GetPropertyChangedSignal("ViewportSize"), updateScale)
	end
end

-- Drag area
local DragBar = new("Frame", {
	Name = "DragBar",
	BackgroundTransparency = 1,
	Size = UDim2.new(1, 0, 0, 84),
	Parent = Main,
})
DragBar.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		local startMouse = input.Position
		local startPos = Main.Position
		activeDrag = function(pos)
			local d = pos - startMouse
			local vp = viewport()
			local w = Main.AbsoluteSize.X
			local x = math.clamp(startPos.X.Offset + d.X, -w + 90, vp.X - 90)
			local y = math.clamp(startPos.Y.Offset + d.Y, 0, vp.Y - 40)
			Main.Position = UDim2.fromOffset(x, y)
		end
	end
end)

-- Sidebar
local Sidebar = new("Frame", {
	Name = "Sidebar",
	BackgroundTransparency = 1,
	Size = UDim2.new(0, 100, 1, 0),
	Parent = Main,
})

local Logo = newText({
	Name = "Logo",
	Text = "UH",
	FontFace = Fonts.Heavy,
	TextSize = 34,
	TextXAlignment = Enum.TextXAlignment.Center,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromOffset(50, 42),
	Size = UDim2.fromOffset(80, 44),
	Parent = Sidebar,
}, "Accent")
new("UIGradient", {
	Rotation = 90,
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 150, 150)),
	}),
	Parent = Logo,
})

local LogoLine = new("Frame", {
	Name = "LogoLine",
	BorderSizePixel = 0,
	Position = UDim2.fromOffset(5, 84),
	Size = UDim2.fromOffset(92, 1),
	Parent = Sidebar,
})
bind(LogoLine, { BackgroundColor3 = "Outline" })

local SidebarLine = new("Frame", {
	Name = "SidebarLine",
	BorderSizePixel = 0,
	Position = UDim2.fromOffset(99, 7),
	Size = UDim2.new(0, 1, 1, -14),
	Parent = Main,
})
bind(SidebarLine, { BackgroundColor3 = "Outline" })

local TabList = new("ScrollingFrame", {
	Name = "Tabs",
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Position = UDim2.fromOffset(0, 85),
	Size = UDim2.new(0, 99, 1, -85),
	ScrollBarThickness = 0,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	ElasticBehavior = Enum.ElasticBehavior.Never,
	Parent = Sidebar,
}, {
	new("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 4),
	}),
	new("UIPadding", { PaddingTop = UDim.new(0, 17), PaddingBottom = UDim.new(0, 12) }),
})

-- Header
local HeaderLine = new("Frame", {
	Name = "HeaderLine",
	BorderSizePixel = 0,
	Position = UDim2.fromOffset(100, 84),
	Size = UDim2.new(1, -100, 0, 1),
	Parent = Main,
})
bind(HeaderLine, { BackgroundColor3 = "Outline" })

local TitleLabel = newText({
	Name = "Title",
	FontFace = Fonts.Bold,
	TextSize = 17,
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.fromOffset(117, 35),
	Size = UDim2.new(1, -420, 0, 24),
	TextTruncate = Enum.TextTruncate.AtEnd,
	Parent = Main,
}, "Title")

local SubtitleLabel = newText({
	Name = "Subtitle",
	FontFace = Fonts.Medium,
	TextSize = 12,
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.fromOffset(117, 53),
	Size = UDim2.new(1, -420, 0, 16),
	TextTruncate = Enum.TextTruncate.AtEnd,
	Parent = Main,
}, "SubText")

-- Content
local Content = new("Frame", {
	Name = "Content",
	BackgroundTransparency = 1,
	ClipsDescendants = true,
	Position = UDim2.fromOffset(100, 85),
	Size = UDim2.new(1, -100, 1, -85),
	Parent = Main,
})

-- Resize grip
local Grip = new("TextButton", {
	Name = "Grip",
	Text = "",
	AutoButtonColor = false,
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -2, 1, -2),
	Size = UDim2.fromOffset(16, 16),
	Parent = Main,
})
for _, spec in ipairs({ { 10, 10 }, { 5, 14 } }) do
	local line = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(spec[2], spec[2]),
		Size = UDim2.fromOffset(spec[1], 1),
		Rotation = -45,
		BorderSizePixel = 0,
		Parent = Grip,
	})
	bind(line, { BackgroundColor3 = "Unselected" })
end
Grip.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		local startMouse = input.Position
		local startW, startH = Main.Size.X.Offset, Main.Size.Y.Offset
		activeDrag = function(pos)
			local d = (pos - startMouse) / Scale.Scale
			Main.Size = UDim2.fromOffset(
				math.clamp(startW + d.X, MIN_W, MAX_W),
				math.clamp(startH + d.Y, MIN_H, MAX_H)
			)
		end
	end
end)

-- Modal button frees the mouse in first person
new("TextButton", {
	Name = "Modal",
	Text = "",
	Modal = true,
	BackgroundTransparency = 1,
	Size = UDim2.fromOffset(0, 0),
	Parent = Main,
})

-- Overlay (popups, dialogs, search results)
local Overlay = new("Frame", {
	Name = "Overlay",
	BackgroundTransparency = 1,
	Size = UDim2.new(1, 0, 1, 0),
	ZIndex = 100,
	Parent = Main,
})

local function localRect(obj)
	local s = Scale.Scale
	return (obj.AbsolutePosition - Main.AbsolutePosition) / s, obj.AbsoluteSize / s
end

local function closePopup()
	local close = UH._popup
	UH._popup = nil
	UH._currentDropdown = nil
	if close then
		pcall(close)
	end
end

----------------------------------------------------------------------
-- Notifications + watermark
----------------------------------------------------------------------
local GuiService = game:GetService("GuiService")

-- Notifications (KiciaHook style: small dark pill, accent outline, mono text, slides in)
local NotifyState = { Enabled = true, Side = "TopLeft", Size = 15, Font = "Inconsolata", Offset = 0 }
UH.Notif = NotifyState

local NOTIFY_FONTS = {
	Inconsolata = Font.fromEnum(Enum.Font.Code),
	Arial = Font.fromEnum(Enum.Font.Arial),
	Roboto = Font.fromEnum(Enum.Font.Roboto),
	Ubuntu = Font.fromEnum(Enum.Font.Ubuntu),
	["Source Sans"] = Font.fromEnum(Enum.Font.SourceSans),
	Gotham = Font.fromEnum(Enum.Font.Gotham),
}
UH.NotifyFonts = { "Inconsolata", "Arial", "Roboto", "Ubuntu", "Source Sans", "Gotham" }

local NOTIFY_SIDES = {
	TopLeft = { AlignX = 0, Valign = Enum.VerticalAlignment.Top },
	TopRight = { AlignX = 1, Valign = Enum.VerticalAlignment.Top },
	BottomLeft = { AlignX = 0, Valign = Enum.VerticalAlignment.Bottom },
	BottomRight = { AlignX = 1, Valign = Enum.VerticalAlignment.Bottom },
	Center = { AlignX = 0.5, Valign = Enum.VerticalAlignment.Top },
	Crosshair = { AlignX = 0.5, Valign = Enum.VerticalAlignment.Center, Crosshair = true },
}
UH.NotifySides = { "TopLeft", "TopRight", "BottomLeft", "BottomRight", "Center", "Crosshair" }

local NOTIFY_INTENTS = {
	success = Color3.fromRGB(72, 199, 120),
	warning = Color3.fromRGB(255, 183, 77),
	error = Color3.fromRGB(255, 80, 82),
}

local NotifyHolder = new("Frame", {
	Name = "Notifications",
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Size = UDim2.fromScale(1, 1),
	Parent = Gui,
})
local NotifyMargin = new("UIPadding", { Parent = NotifyHolder })
local NotifyList = new("UIListLayout", {
	Padding = UDim.new(0, 6),
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = NotifyHolder,
})
local notifyStack = {}
local notifyCounter = 0

local TW_IN = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TW_SETTLE = TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TW_OUT = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local function notifyPos(alignX, y)
	return UDim2.new(alignX, 0, 0.5, y)
end

local function escapeRich(s)
	return (tostring(s):gsub("[&<>]", { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;" }))
end

local function richText(segments, textColor, accent)
	if type(segments) ~= "table" then
		return escapeRich(segments)
	end
	local out = table.create(#segments)
	for i, seg in ipairs(segments) do
		local c = (seg.Accent and accent) or seg.Color or textColor
		out[i] = string.format('<font color="#%s">%s</font>', c:ToHex(), escapeRich(seg.Text))
	end
	return table.concat(out, "")
end

local function notifyMargins()
	local cam = workspace.CurrentCamera
	if not cam then
		return 16, 16, 16, 16
	end
	local ok, area = pcall(function()
		return GuiService:GetInsetArea(Enum.ScreenInsets.CoreUISafeInsets)
	end)
	if not ok or not area then
		return 14, 14, 14, 16
	end
	local vp = cam.ViewportSize
	local barH = 0
	pcall(function()
		barH = GuiService:GetGuiInset().Y
	end)
	local left = 14 + math.max(0, area.Min.X)
	local top = 14 + math.max(0, area.Min.Y, barH)
	local right = 16 + math.max(0, vp.X - area.Max.X)
	local bottom = 14 + math.max(0, vp.Y - area.Max.Y)
	return top, bottom, left, right
end

local function createNotification(layout, text, theme, lifetime, onDestroyed)
	local alignX = layout.AlignX
	local n = { _dismissing = false, _destroyed = false, _alignX = alignX }

	n.Ghost = new("Frame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, math.ceil(theme.Size * 1.25) + 10),
		LayoutOrder = layout.Order,
	})
	n.Bar = new("Frame", {
		BackgroundColor3 = theme.Background,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(alignX, 0.5),
		Position = notifyPos(alignX, -20),
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		Parent = n.Ghost,
	})
	new("UICorner", { CornerRadius = UDim.new(0, 4), Parent = n.Bar })
	n.Stroke = new("UIStroke", {
		Color = theme.Accent,
		Transparency = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = n.Bar,
	})
	new("UIPadding", {
		PaddingTop = UDim.new(0, 5),
		PaddingBottom = UDim.new(0, 5),
		PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 10),
		Parent = n.Bar,
	})
	n.Label = new("TextLabel", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		FontFace = theme.Font,
		RichText = true,
		Text = richText(text, theme.TextColor, theme.Accent),
		TextColor3 = theme.TextColor,
		TextSize = theme.Size,
		TextTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		Parent = n.Bar,
	})
	n.Ghost.Parent = layout.Parent

	local function play(inst, info, props)
		local t = TweenService:Create(inst, info, props)
		t:Play()
		return t
	end

	function n:Destroy()
		if self._destroyed then
			return
		end
		self._destroyed = true
		pcall(function()
			self.Ghost:Destroy()
		end)
		onDestroyed(self)
	end

	function n:_animateOut()
		local t = play(self.Bar, TW_OUT, { Position = notifyPos(self._alignX, -20), BackgroundTransparency = 1 })
		t.Completed:Connect(function()
			self:Destroy()
		end)
	end

	function n:Dismiss()
		if self._dismissing or self._destroyed then
			return
		end
		self._dismissing = true
		play(self.Stroke, TW_OUT, { Transparency = 1 })
		play(self.Label, TW_OUT, { TextTransparency = 1 })
		self:_animateOut()
	end

	function n:SetLayout(l)
		if self._destroyed then
			return
		end
		self._alignX = l.AlignX
		self.Ghost.LayoutOrder = l.Order
		self.Bar.AnchorPoint = Vector2.new(l.AlignX, 0.5)
		if self._dismissing then
			self:_animateOut()
		else
			self.Bar.Position = notifyPos(l.AlignX, 0)
		end
	end

	-- slide in (overshoots by 4px then settles)
	play(n.Bar, TW_IN, { BackgroundTransparency = 0.4 })
	play(n.Stroke, TW_IN, { Transparency = 0.4 })
	play(n.Label, TW_IN, { TextTransparency = 0 })
	local slide = play(n.Bar, TW_IN, { Position = notifyPos(alignX, 4) })
	slide.Completed:Connect(function()
		if not n._dismissing and not n._destroyed then
			play(n.Bar, TW_SETTLE, { Position = notifyPos(alignX, 0) })
		end
	end)

	if lifetime > 0 then
		task.delay(lifetime, function()
			n:Dismiss()
		end)
	end
	return n
end

local function notifySpec()
	return NOTIFY_SIDES[NotifyState.Side] or NOTIFY_SIDES.TopLeft
end

function UH:_applyNotifyLayout()
	local spec = notifySpec()
	local top, bottom, left, right = notifyMargins()
	if spec.Crosshair then
		top, bottom = 16, 16
	end
	-- keep the stack clear of the watermark
	local wm = UH._watermark
	if wm and wm.Visible and not spec.Crosshair then
		local vp = viewport()
		local colW = 340
		local colL, colR
		if spec.AlignX == 0 then
			colL, colR = left, left + colW
		elseif spec.AlignX == 1 then
			colR = vp.X - right
			colL = colR - colW
		else
			colL = vp.X / 2 - colW / 2
			colR = colL + colW
		end
		local p, s = wm.AbsolutePosition, wm.AbsoluteSize
		if p.X < colR and p.X + s.X > colL then
			if spec.Valign == Enum.VerticalAlignment.Top and p.Y < top + 40 then
				top = math.max(top, p.Y + s.Y + 8)
			elseif spec.Valign == Enum.VerticalAlignment.Bottom and p.Y + s.Y > vp.Y - bottom - 40 then
				bottom = math.max(bottom, vp.Y - p.Y + 8)
			end
		end
	end
	local sig = table.concat({ NotifyState.Side, top, bottom, left, right, NotifyState.Offset or 0, tostring(NotifyState.Enabled) }, "|")
	if sig == UH._notifySig then
		return
	end
	UH._notifySig = sig
	NotifyMargin.PaddingTop = UDim.new(0, top)
	NotifyMargin.PaddingBottom = UDim.new(0, bottom)
	NotifyMargin.PaddingLeft = UDim.new(0, left)
	NotifyMargin.PaddingRight = UDim.new(0, right)
	NotifyHolder.Visible = NotifyState.Enabled

	if spec.Crosshair then
		local offset = NotifyState.Offset or 0
		if offset >= 0 then
			NotifyList.VerticalAlignment = Enum.VerticalAlignment.Top
			NotifyHolder.Position = UDim2.new(0, 0, 0.5, offset)
			NotifyHolder.Size = UDim2.new(1, 0, 0.5, -offset)
		else
			NotifyList.VerticalAlignment = Enum.VerticalAlignment.Bottom
			NotifyHolder.Position = UDim2.fromScale(0, 0)
			NotifyHolder.Size = UDim2.new(1, 0, 0.5, offset)
		end
	else
		NotifyList.VerticalAlignment = spec.Valign
		NotifyHolder.Position = UDim2.fromScale(0, 0)
		NotifyHolder.Size = UDim2.fromScale(1, 1)
	end

	local bottomUp = NotifyList.VerticalAlignment == Enum.VerticalAlignment.Bottom
	for k, n in ipairs(notifyStack) do
		n:SetLayout({ Parent = NotifyHolder, Order = bottomUp and k or -k, AlignX = spec.AlignX })
	end
	if not NotifyState.Enabled then
		for _, n in ipairs(table.clone(notifyStack)) do
			n:Destroy()
		end
	end
end

do
	local cam = workspace.CurrentCamera
	if cam then
		connect(cam:GetPropertyChangedSignal("ViewportSize"), function()
			UH:_applyNotifyLayout()
		end)
	end
	UH:_applyNotifyLayout()
end

-- UH:Notify("text")
-- UH:Notify({ { Text = "Name", Accent = true }, { Text = " did a thing" } }, 4)
-- UH:Notify("text", 4, { Intent = "success" | "warning" | "error", Color = Color3, Force = true })
-- (a third argument of `true` forces the notification even when notifications are disabled)
function UH:Notify(text, duration, opts)
	if UH.Unloaded then
		return
	end
	if type(duration) == "table" then
		opts, duration = duration, nil
	end
	local force = false
	if opts == true then
		force, opts = true, {}
	elseif type(opts) ~= "table" then
		opts = {}
	else
		force = opts.Force == true
	end
	if not NotifyState.Enabled and not force then
		return
	end
	if not NotifyHolder.Visible then
		NotifyHolder.Visible = true
	end

	local spec = notifySpec()
	local bottomUp = NotifyList.VerticalAlignment == Enum.VerticalAlignment.Bottom
	notifyCounter = notifyCounter + 1
	local theme = {
		Accent = opts.Color or NOTIFY_INTENTS[opts.Intent] or Theme.Accent,
		Background = Theme.Background,
		TextColor = Theme.TextColor,
		Font = NOTIFY_FONTS[NotifyState.Font] or NOTIFY_FONTS.Inconsolata,
		Size = NotifyState.Size,
	}
	local layout = {
		Parent = NotifyHolder,
		Order = bottomUp and notifyCounter or -notifyCounter,
		AlignX = spec.AlignX,
	}
	local created
	created = createNotification(layout, text, theme, opts.Lifetime or duration or 6, function(n)
		local i = table.find(notifyStack, n)
		if i then
			table.remove(notifyStack, i)
		end
	end)
	notifyStack[#notifyStack + 1] = created
	while #notifyStack > 50 do
		notifyStack[1]:Destroy()
	end
end

-- UH.Template("Hit %NAME% for %DMG%", { NAME = "x", DMG = 30 })  ->  segments with the values highlighted
function UH.Template(str, values)
	local out, n = {}, 1
	while true do
		local s, e, key = str:find("%%(%w+)%%", n)
		if not s then
			break
		end
		if n < s then
			out[#out + 1] = { Text = str:sub(n, s - 1) }
		end
		local v = values[key]
		if v ~= nil then
			out[#out + 1] = { Text = tostring(v), Accent = true }
		else
			out[#out + 1] = { Text = str:sub(s, e) }
		end
		n = e + 1
	end
	if n <= #str then
		out[#out + 1] = { Text = str:sub(n) }
	end
	return out
end

function UH:ClearNotifications()
	for _, n in ipairs(table.clone(notifyStack)) do
		n:Dismiss()
	end
end

-- HUD helpers (draggable overlays that persist their position)
local draggables = {}

local function clampToViewport(frame)
	local vp = viewport()
	local sz, p = frame.AbsoluteSize, frame.AbsolutePosition
	frame.Position = UDim2.fromOffset(
		math.clamp(p.X, 0, math.max(vp.X - sz.X, 0)),
		math.clamp(p.Y, 0, math.max(vp.Y - sz.Y, 0))
	)
end

local function makeDraggable(frame, key, handle)
	handle = handle or frame
	draggables[key] = frame
	handle.Active = true
	handle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			local startMouse = input.Position
			local startPos = frame.Position
			activeDrag = function(pos)
				local d = pos - startMouse
				local vp = viewport()
				local sz = frame.AbsoluteSize
				local x = math.clamp(startPos.X.Offset + d.X, 0, math.max(vp.X - sz.X, 0))
				local y = math.clamp(startPos.Y.Offset + d.Y, 0, math.max(vp.Y - sz.Y, 0))
				frame.Position = UDim2.fromOffset(x, y)
				Config.State.Positions[key] = { x, y }
				UH._dragDirty = true
			end
		end
	end)
end

function UH:_restorePositions()
	for key, frame in pairs(draggables) do
		local p = Config.State.Positions[key]
		if type(p) == "table" and type(p[1]) == "number" and type(p[2]) == "number" then
			frame.Position = UDim2.fromOffset(p[1], p[2])
			task.delay(0.2, function()
				if frame.Parent then
					clampToViewport(frame)
				end
			end)
		end
	end
end

-- Watermark  (logo | title | user | fps)
local WATERMARK_TITLE = "UniversalHub | Rivals | Free Build"
local ICON_USER = "rbxassetid://83187029320661"
local ICON_FPS = "rbxassetid://113103422688495"

local Watermark = new("Frame", {
	Name = "Watermark",
	BackgroundTransparency = 0.04,
	Position = UDim2.fromOffset(28, 35),
	Size = UDim2.fromOffset(0, 0),
	AutomaticSize = Enum.AutomaticSize.XY,
	BorderSizePixel = 0,
	Parent = Gui,
}, {
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 10),
	}),
})
bind(Watermark, { BackgroundColor3 = "ElementBackground" })
addCorner(Watermark, 6)
addStroke(Watermark, "Outline")
addPadding(Watermark, 13, 11, 8, 8)

local function wmIcon(order, image)
	local icon = new("ImageLabel", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Image = image,
		Size = UDim2.fromOffset(20, 20),
		ScaleType = Enum.ScaleType.Fit,
		LayoutOrder = order,
		Parent = Watermark,
	})
	bind(icon, { ImageColor3 = "Accent" })
	return icon
end
local function wmText(text, order, key, extra)
	local props = {
		Text = text,
		TextSize = 16,
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		LayoutOrder = order,
		Parent = Watermark,
	}
	for k, v in pairs(extra or {}) do
		props[k] = v
	end
	return newText(props, key)
end
local function wmSep(order)
	return wmText("|", order, "Unselected")
end

wmText("UH", 1, "Accent", { FontFace = Fonts.Heavy })
local WmTitle = wmText(WATERMARK_TITLE, 2)
wmSep(3)
wmIcon(4, ICON_USER)
local WmUser = wmText(LocalPlayer and LocalPlayer.Name or "player", 5)
wmSep(6)
wmIcon(7, ICON_FPS)
local FpsLabel = wmText("60 FPS", 8, nil, { AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.fromOffset(60, 0) })

do
	local frames, last = 0, os.clock()
	connect(RunService.RenderStepped, function()
		if not Watermark.Visible then
			return
		end
		frames = frames + 1
		local now = os.clock()
		if now - last >= 0.5 then
			FpsLabel.Text = string.format("%d FPS", math.floor(frames / (now - last) + 0.5))
			frames, last = 0, now
		end
	end)
end
makeDraggable(Watermark, "Watermark")
UH._watermark = Watermark
for _, prop in ipairs({ "AbsolutePosition", "AbsoluteSize", "Visible" }) do
	Watermark:GetPropertyChangedSignal(prop):Connect(function()
		UH:_applyNotifyLayout()
	end)
end

function UH:SetWatermark(v)
	Watermark.Visible = v == true
end
function UH:SetWatermarkTitle(text)
	WmTitle.Text = tostring(text)
end
function UH:SetWatermarkUsername(text)
	WmUser.Text = tostring(text)
end

-- Keybind list  (shows every keybind that has a key assigned)
local KEY_SHORT = {
	RightShift = "RSHIFT", LeftShift = "LSHIFT", RightControl = "RCTRL", LeftControl = "LCTRL",
	RightAlt = "RALT", LeftAlt = "LALT", Return = "ENTER", Backspace = "BKSP", Escape = "ESC",
	Zero = "0", One = "1", Two = "2", Three = "3", Four = "4", Five = "5", Six = "6", Seven = "7", Eight = "8", Nine = "9",
	MouseButton1 = "MB1", MouseButton2 = "MB2", MouseButton3 = "MB3",
}
local function shortKey(name)
	return KEY_SHORT[name] or tostring(name)
end

UH.KeybindListEnabled = true
local KbEntries = {}

local KbFrame = new("Frame", {
	Name = "Keybinds",
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Position = UDim2.fromOffset(50, math.min(400, math.floor(viewport().Y * 0.5))),
	Size = UDim2.fromOffset(0, 0),
	AutomaticSize = Enum.AutomaticSize.XY,
	Visible = false,
	Parent = Gui,
})
local KbCard = new("CanvasGroup", {
	Name = "Card",
	BackgroundTransparency = 0.06,
	BorderSizePixel = 0,
	Size = UDim2.fromOffset(260, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	Parent = KbFrame,
})
bind(KbCard, { BackgroundColor3 = "ElementBackground" })
addCorner(KbCard, 6)
local kbStroke = addStroke(KbCard, "Outline")
kbStroke.Transparency = 0.8
local KbBar = new("Frame", {
	Name = "Bar",
	BorderSizePixel = 0,
	Size = UDim2.new(0, 2, 1, 0),
	Parent = KbCard,
})
bind(KbBar, { BackgroundColor3 = "Accent" })
local KbInner = new("Frame", {
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Position = UDim2.fromOffset(2, 0),
	Size = UDim2.new(1, -2, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	Parent = KbCard,
}, {
	new("UIPadding", {
		PaddingTop = UDim.new(0, 8),
		PaddingBottom = UDim.new(0, 9),
		PaddingLeft = UDim.new(0, 12),
		PaddingRight = UDim.new(0, 12),
	}),
	new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }),
})
newText({
	Text = "KEYBINDS",
	FontFace = Fonts.SemiBold,
	TextSize = 10,
	Size = UDim2.new(1, 0, 0, 12),
	LayoutOrder = 0,
	Parent = KbInner,
}, "Unselected")
local KbRows = new("Frame", {
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Size = UDim2.new(1, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	LayoutOrder = 1,
	Parent = KbInner,
}, {
	new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 1) }),
})
makeDraggable(KbFrame, "Keybinds", KbCard)

local function refreshKeybindList()
	local any = false
	for _, e in ipairs(KbEntries) do
		local show = e.Shown and e.KeyName ~= "None"
		e.Row.Visible = show
		if show then
			any = true
		end
	end
	KbFrame.Visible = UH.KeybindListEnabled and any
end

local function paintEntry(e)
	if e.Active then
		e.LabelObj.TextColor3 = Theme.TextColor
		e.LabelObj.TextTransparency = 0
		e.ModeObj.TextColor3 = Theme.Accent
		e.ModeObj.TextTransparency = 0
	else
		e.LabelObj.TextColor3 = Theme.Unselected
		e.LabelObj.TextTransparency = 0.15
		e.ModeObj.TextColor3 = Theme.Unselected
		e.ModeObj.TextTransparency = 0.25
	end
end
onTheme(function()
	for _, e in ipairs(KbEntries) do
		paintEntry(e)
	end
end)

function UH:AddKeybindEntry(opts)
	opts = opts or {}
	local e = {
		KeyName = tostring(opts.Key or "None"),
		Mode = tostring(opts.Mode or "Toggle"),
		Active = false,
		Shown = opts.Visible ~= false,
	}
	e.Row = new("Frame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 20),
		LayoutOrder = #KbEntries + 1,
		Visible = false,
		Parent = KbRows,
	}, {
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 10),
		}),
	})
	e.KeyObj = newText({
		Text = shortKey(e.KeyName):upper(),
		TextSize = 12,
		Size = UDim2.fromOffset(60, 20),
		LayoutOrder = 1,
		Parent = e.Row,
	}, "Accent")
	e.LabelObj = newText({
		Text = tostring(opts.Label or "Keybind"),
		TextSize = 12,
		Size = UDim2.fromOffset(104, 20),
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextColor3 = Theme.TextColor,
		LayoutOrder = 2,
		Parent = e.Row,
	}, false)
	e.ModeObj = newText({
		Text = e.Mode:upper(),
		TextSize = 12,
		Size = UDim2.fromOffset(50, 20),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Theme.TextColor,
		LayoutOrder = 3,
		Parent = e.Row,
	}, false)

	function e:SetLabel(text)
		self.LabelObj.Text = tostring(text)
	end
	function e:SetKey(name)
		self.KeyName = tostring(name or "None")
		self.KeyObj.Text = shortKey(self.KeyName):upper()
		refreshKeybindList()
	end
	function e:SetMode(mode)
		self.Mode = tostring(mode)
		self.ModeObj.Text = self.Mode:upper()
	end
	function e:SetActive(active)
		self.Active = active == true
		paintEntry(self)
	end
	function e:SetShown(v)
		self.Shown = v ~= false
		refreshKeybindList()
	end
	function e:Destroy()
		local i = table.find(KbEntries, self)
		if i then
			table.remove(KbEntries, i)
		end
		self.Row:Destroy()
		refreshKeybindList()
	end

	KbEntries[#KbEntries + 1] = e
	paintEntry(e)
	refreshKeybindList()
	return e
end

function UH:SetKeybindList(v)
	UH.KeybindListEnabled = v == true
	refreshKeybindList()
end
function UH:IsKeybindListEnabled()
	return UH.KeybindListEnabled
end

----------------------------------------------------------------------
-- Confirm dialog
----------------------------------------------------------------------
function UH:Confirm(opts)
	closePopup()
	local backdrop = new("TextButton", {
		Name = "Confirm",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, 0),
		Parent = Overlay,
	})
	tween(backdrop, { BackgroundTransparency = 0.45 }, 0.15)

	local dialog = new("Frame", {
		Active = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.fromOffset(330, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BorderSizePixel = 0,
		Parent = backdrop,
	}, {
		new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 10) }),
	})
	bind(dialog, { BackgroundColor3 = "Background" })
	addCorner(dialog, 6)
	addStroke(dialog, "Outline")
	addPadding(dialog, 16, 16, 16, 16)

	newText({
		Text = opts.Title or "Confirm",
		FontFace = Fonts.Bold,
		TextSize = 15,
		Size = UDim2.new(1, 0, 0, 20),
		LayoutOrder = 1,
		Parent = dialog,
	}, "Title")
	newText({
		Text = opts.Message or "Are you sure?",
		TextSize = 13,
		TextWrapped = true,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 0),
		LayoutOrder = 2,
		Parent = dialog,
	}, "Muted")

	local buttons = new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 28),
		LayoutOrder = 3,
		Parent = dialog,
	}, {
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 8),
		}),
	})

	local function close()
		if UH._popup == close then
			UH._popup = nil
		end
		backdrop:Destroy()
	end
	UH._popup = close

	local function dialogButton(text, order, primary)
		local b = new("TextButton", {
			Text = "",
			AutoButtonColor = false,
			Size = UDim2.fromOffset(88, 28),
			BorderSizePixel = 0,
			LayoutOrder = order,
			Parent = buttons,
		})
		if primary then
			bind(b, { BackgroundColor3 = "Accent" })
		else
			bind(b, { BackgroundColor3 = "ElementBackground" })
			addStroke(b, "Outline")
		end
		addCorner(b, 5)
		newText({
			Text = text,
			FontFace = Fonts.SemiBold,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = primary and Color3.new(0, 0, 0) or Theme.TextColor,
			Size = UDim2.new(1, 0, 1, 0),
			Parent = b,
		}, false)
		return b
	end

	local cancel = dialogButton("Cancel", 1, false)
	local confirm = dialogButton(opts.ConfirmText or "Confirm", 2, true)
	cancel.Activated:Connect(close)
	backdrop.Activated:Connect(close)
	confirm.Activated:Connect(function()
		close()
		safeCall(opts.OnConfirm)
	end)
end

----------------------------------------------------------------------
-- Section / elements
----------------------------------------------------------------------
function Section:_row(height, label)
	self._count = self._count + 1
	local order = self._count * 2
	local divider
	if self._count > 1 then
		divider = new("Frame", {
			Name = "Divider",
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 1),
			LayoutOrder = order - 1,
			Parent = self.Box,
		})
		bind(divider, { BackgroundColor3 = "Outline" })
	end
	local row = new("Frame", {
		Name = "Row",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, height),
		LayoutOrder = order,
		Parent = self.Box,
	})
	if label then
		UH._index[#UH._index + 1] = {
			Label = label,
			Tab = self.Page.Tab,
			Page = self.Page,
			Section = self.Title,
			Row = row,
		}
	end
	return row, divider
end

function Section:_register(opts, el, label)
	el.Section = self
	if opts.Persist == false then
		return
	end
	local flag = opts.Flag
	if not flag then
		flag = table.concat({
			self.Page.Tab.Label,
			self.Page.Label or "Main",
			self.Title or "Section",
			label or "Element",
		}, "/")
	end
	if UH.Flags[flag] then
		local n = 2
		while UH.Flags[flag .. "#" .. n] do
			n = n + 1
		end
		flag = flag .. "#" .. n
	end
	el.Flag = flag
	el.DefaultSerialized = el:Serialize()
	UH.Flags[flag] = el
end

local function attachVisibility(el, row, divider)
	el.Row = row
	function el:SetVisible(v)
		row.Visible = v
		if divider then
			divider.Visible = v
		end
	end
end

local function rowLabel(row, text, width)
	return newText({
		Name = "Label",
		Text = text or "",
		Position = UDim2.fromOffset(12, 0),
		Size = width or UDim2.new(1, -24, 1, 0),
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = row,
	})
end

-- Label
function Section:AddLabel(opts)
	local row, divider = self:_row(36, nil)
	local lbl = rowLabel(row, opts.Label)
	if opts.TextColor then
		lbl.TextColor3 = opts.TextColor
	end
	local el = { Type = "Label", Instance = lbl }
	function el:Set(text)
		lbl.Text = tostring(text)
	end
	attachVisibility(el, row, divider)
	return el
end

-- Button
function Section:AddButton(opts)
	local row, divider = self:_row(48, opts.Label)
	local button = new("TextButton", {
		Name = "Button",
		Text = "",
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(1, -24, 0, 25),
		BorderSizePixel = 0,
		Parent = row,
	})
	bind(button, { BackgroundColor3 = "ElementBackground" })
	addCorner(button, 5)
	local stroke = addStroke(button, "Outline")
	local text = newText({
		Text = opts.Label,
		FontFace = Fonts.SemiBold,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 1, 0),
		Parent = button,
	})

	local el = { Type = "Button", Instance = button, Clicked = newSignal() }
	local function fire()
		safeCall(opts.OnClick)
		el.Clicked:Fire()
	end
	function el:Click()
		if opts.Confirm then
			UH:Confirm({
				Title = opts.Label,
				Message = opts.ConfirmMessage or ("Are you sure you want to " .. string.lower(opts.Label) .. "?"),
				OnConfirm = fire,
			})
		else
			fire()
		end
	end
	function el:SetLabel(t)
		text.Text = t
	end

	button.MouseEnter:Connect(function()
		tween(stroke, { Color = Theme.Unselected }, 0.12)
		tween(button, { BackgroundColor3 = Theme.InputBackground }, 0.12)
	end)
	button.MouseLeave:Connect(function()
		tween(stroke, { Color = Theme.Outline }, 0.12)
		tween(button, { BackgroundColor3 = Theme.ElementBackground }, 0.12)
	end)
	button.MouseButton1Down:Connect(function()
		tween(button, { BackgroundColor3 = Theme.TabButtonSelected }, 0.06)
	end)
	button.MouseButton1Up:Connect(function()
		tween(button, { BackgroundColor3 = Theme.InputBackground }, 0.1)
	end)
	button.Activated:Connect(function()
		el:Click()
	end)

	attachVisibility(el, row, divider)
	return el
end

-- TextBox
function Section:AddTextBox(opts)
	local row, divider = self:_row(48, opts.Label)
	rowLabel(row, opts.Label, UDim2.new(1, -112, 1, 0))
	local box = new("TextBox", {
		Name = "Input",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -13, 0.5, 0),
		Size = UDim2.fromOffset(82, 24),
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
		ClipsDescendants = true,
		Text = opts.Default or "",
		PlaceholderText = opts.Placeholder or "",
		FontFace = Fonts.Medium,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})
	bind(box, { BackgroundColor3 = "InputBackground", TextColor3 = "TextColor", PlaceholderColor3 = "SubText" })
	addCorner(box, 5)
	addPadding(box, 8, 8, 0, 0)
	local stroke = addStroke(box, "Outline")

	local el = { Type = "TextBox", Instance = box, Value = opts.Default or "", Default = opts.Default or "", Changed = newSignal() }
	local isSetting = false

	local function fire()
		safeCall(opts.OnChanged, el.Value)
		el.Changed:Fire(el.Value)
		UH:_changed()
	end
	box.Focused:Connect(function()
		tween(stroke, { Color = Theme.Accent }, 0.12)
	end)
	box.FocusLost:Connect(function()
		tween(stroke, { Color = Theme.Outline }, 0.12)
		el.Value = box.Text
		if opts.FocusLostOnly then
			fire()
		end
	end)
	box:GetPropertyChangedSignal("Text"):Connect(function()
		if isSetting then
			return
		end
		el.Value = box.Text
		if not opts.FocusLostOnly then
			fire()
		end
	end)
	function el:Get()
		return box.Text
	end
	function el:Set(value, silent)
		isSetting = true
		box.Text = tostring(value or "")
		self.Value = box.Text
		isSetting = false
		if not silent then
			fire()
		end
	end
	function el:Serialize()
		return self.Value
	end
	function el:Deserialize(v)
		if type(v) == "string" then
			self:Set(v)
		end
	end

	attachVisibility(el, row, divider)
	self:_register(opts, el, opts.Label)
	return el
end

-- Toggle
function Section:AddToggle(opts)
	local row, divider = self:_row(46, opts.Label)
	local hit = new("TextButton", {
		Name = "Hit",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		Parent = row,
	})
	local lbl = rowLabel(row, opts.Label, UDim2.new(1, -70, 1, 0))
	local track = new("Frame", {
		Name = "Track",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -13, 0.5, 0),
		Size = UDim2.fromOffset(30, 18),
		BorderSizePixel = 0,
		Parent = row,
	})
	addCorner(track, 9)
	addStroke(track, "Outline")
	local knob = new("Frame", {
		Name = "Knob",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 3, 0.5, 0),
		Size = UDim2.fromOffset(12, 12),
		BorderSizePixel = 0,
		Parent = track,
	})
	addCorner(knob, 6)

	local default = opts.Default == true
	local el = { Type = "Toggle", Instance = row, Value = default, Default = default, Changed = newSignal() }

	local function paint(animate)
		local on = el.Value
		local trackGoal = { BackgroundColor3 = on and Theme.Accent or Theme.ToggleBackgroundUnselected }
		local knobGoal = {
			Position = on and UDim2.new(0, 15, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
			BackgroundColor3 = on and Theme.Background or Theme.ToggleCircleUnselected,
		}
		if animate then
			tween(track, trackGoal, 0.15)
			tween(knob, knobGoal, 0.15)
		else
			for k, v in pairs(trackGoal) do
				track[k] = v
			end
			for k, v in pairs(knobGoal) do
				knob[k] = v
			end
		end
	end
	onTheme(function()
		paint(false)
	end)

	function el:Set(value, silent)
		value = value == true
		if self.Value == value then
			return
		end
		self.Value = value
		paint(true)
		if not silent then
			safeCall(opts.OnChanged, value)
			self.Changed:Fire(value)
			UH:_changed()
		end
	end
	function el:Get()
		return self.Value
	end
	function el:Serialize()
		return self.Value
	end
	function el:Deserialize(v)
		if type(v) == "boolean" then
			self:Set(v)
		end
	end

	hit.MouseEnter:Connect(function()
		tween(lbl, { TextColor3 = Theme.Accent }, 0.12)
	end)
	hit.MouseLeave:Connect(function()
		tween(lbl, { TextColor3 = Theme.TextColor }, 0.12)
	end)
	hit.Activated:Connect(function()
		el:Set(not el.Value)
	end)

	attachVisibility(el, row, divider)
	self:_register(opts, el, opts.Label)
	return el
end

-- Dropdown
function Section:AddDropdown(opts)
	local row, divider = self:_row(46, opts.Label)
	rowLabel(row, opts.Label, UDim2.new(1, -170, 1, 0))
	local button = new("TextButton", {
		Name = "Dropdown",
		Text = "",
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -13, 0.5, 0),
		Size = UDim2.fromOffset(137, 23),
		BorderSizePixel = 0,
		Parent = row,
	})
	bind(button, { BackgroundColor3 = "ElementBackground" })
	addCorner(button, 5)
	local stroke = addStroke(button, "Outline")
	local valueLabel = newText({
		Text = "Select",
		TextSize = 12,
		Position = UDim2.fromOffset(9, 0),
		Size = UDim2.new(1, -28, 1, 0),
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = button,
	})
	local chevron = new("ImageLabel", {
		BackgroundTransparency = 1,
		Image = ASSETS.Chevron,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -9, 0.5, 0),
		Size = UDim2.fromOffset(9, 5),
		Parent = button,
	})
	bind(chevron, { ImageColor3 = "Muted" })

	local options = {}
	for _, o in ipairs(opts.Options or {}) do
		options[#options + 1] = tostring(o)
	end
	local el = { Type = "Dropdown", Instance = row, Value = opts.Default, Default = opts.Default, Changed = newSignal() }

	local function refreshText()
		valueLabel.Text = el.Value ~= nil and tostring(el.Value) or "Select"
	end
	refreshText()

	function el:SetOptions(list)
		options = {}
		for _, o in ipairs(list or {}) do
			options[#options + 1] = tostring(o)
		end
	end
	function el:Set(value, silent)
		if value ~= nil then
			value = tostring(value)
		end
		self.Value = value
		refreshText()
		if not silent then
			safeCall(opts.OnChanged, value)
			self.Changed:Fire(value)
			UH:_changed()
		end
	end
	function el:Get()
		return self.Value
	end
	function el:Serialize()
		return self.Value
	end
	function el:Deserialize(v)
		if type(v) == "string" then
			self:Set(v)
		end
	end

	local function open()
		if UH._currentDropdown == el then
			closePopup()
			return
		end
		closePopup()
		UH._currentDropdown = el
		if opts.GetOptions then
			local ok, list = pcall(opts.GetOptions)
			if ok and type(list) == "table" then
				el:SetOptions(list)
			end
		end
		local pos, size = localRect(button)
		local itemH, maxVisible = 24, 6
		local count = math.max(#options, 1)
		local h = math.min(count, maxVisible) * itemH + 8
		local y = pos.Y + size.Y + 4
		local mainH = Main.AbsoluteSize.Y / Scale.Scale
		if y + h > mainH - 6 then
			y = pos.Y - h - 4
		end

		local blocker = new("TextButton", {
			Name = "Blocker",
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 1, 0),
			Parent = Overlay,
		})
		local popup = new("Frame", {
			Name = "DropdownPopup",
			Active = true,
			Position = UDim2.fromOffset(pos.X, y),
			Size = UDim2.fromOffset(size.X, h),
			BackgroundColor3 = Theme.ElementBackground,
			BorderSizePixel = 0,
			Parent = Overlay,
		})
		addCorner(popup, 5)
		new("UIStroke", { Color = Theme.Unselected, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = popup })
		local scroll = new("ScrollingFrame", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(4, 4),
			Size = UDim2.new(1, -8, 1, -8),
			ScrollBarThickness = 2,
			ScrollBarImageColor3 = Theme.TabButtonSelected,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ElasticBehavior = Enum.ElasticBehavior.Never,
			Parent = popup,
		}, {
			new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }),
		})

		if #options == 0 then
			newText({
				Text = "No options",
				TextSize = 12,
				Size = UDim2.new(1, 0, 0, itemH),
				Parent = scroll,
			}, "SubText")
		end
		for i, opt in ipairs(options) do
			local selected = el.Value == opt
			local item = new("TextButton", {
				Text = "",
				AutoButtonColor = false,
				Size = UDim2.new(1, 0, 0, itemH),
				BackgroundColor3 = Theme.TabButtonSelected,
				BackgroundTransparency = selected and 0 or 1,
				BorderSizePixel = 0,
				LayoutOrder = i,
				Parent = scroll,
			})
			addCorner(item, 4)
			newText({
				Text = opt,
				TextSize = 12,
				Position = UDim2.fromOffset(8, 0),
				Size = UDim2.new(1, -12, 1, 0),
				TextColor3 = selected and Theme.Accent or Theme.TextColor,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Parent = item,
			}, false)
			item.MouseEnter:Connect(function()
				if not selected then
					tween(item, { BackgroundTransparency = 0.6 }, 0.1)
				end
			end)
			item.MouseLeave:Connect(function()
				if not selected then
					tween(item, { BackgroundTransparency = 1 }, 0.1)
				end
			end)
			item.Activated:Connect(function()
				closePopup()
				el:Set(opt)
			end)
		end

		chevron.Rotation = 180
		tween(stroke, { Color = Theme.Unselected }, 0.12)
		local function close()
			if UH._popup == close then
				UH._popup = nil
				UH._currentDropdown = nil
			end
			chevron.Rotation = 0
			tween(stroke, { Color = Theme.Outline }, 0.12)
			blocker:Destroy()
			popup:Destroy()
		end
		UH._popup = close
		blocker.MouseButton1Down:Connect(closePopup)
	end
	button.Activated:Connect(open)

	attachVisibility(el, row, divider)
	self:_register(opts, el, opts.Label)
	return el
end

-- List
function Section:AddList(opts)
	local height = opts.Height or 140
	local hasSearch = opts.Search == true
	local row, divider = self:_row(12 + (hasSearch and 34 or 0) + height + 12, opts.Label)

	local listY = 12
	local searchBox
	if hasSearch then
		searchBox = new("TextBox", {
			Name = "Search",
			Position = UDim2.fromOffset(12, 12),
			Size = UDim2.new(1, -24, 0, 22),
			BorderSizePixel = 0,
			ClearTextOnFocus = false,
			ClipsDescendants = true,
			Text = "",
			PlaceholderText = "Search...",
			FontFace = Fonts.Medium,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = row,
		})
		bind(searchBox, { BackgroundColor3 = "InputBackground", TextColor3 = "TextColor", PlaceholderColor3 = "SubText" })
		addCorner(searchBox, 5)
		addPadding(searchBox, 8, 8, 0, 0)
		local sStroke = addStroke(searchBox, "Outline")
		searchBox.Focused:Connect(function()
			tween(sStroke, { Color = Theme.Accent }, 0.12)
		end)
		searchBox.FocusLost:Connect(function()
			tween(sStroke, { Color = Theme.Outline }, 0.12)
		end)
		listY = 12 + 22 + 12
	end

	local listFrame = new("ScrollingFrame", {
		Name = "List",
		Position = UDim2.fromOffset(12, listY),
		Size = UDim2.new(1, -24, 0, height),
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ElasticBehavior = Enum.ElasticBehavior.Never,
		Parent = row,
	}, {
		new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2) }),
	})
	bind(listFrame, { BackgroundColor3 = "Background", ScrollBarImageColor3 = "TabButtonSelected" })
	addCorner(listFrame, 5)
	addStroke(listFrame, "Outline")
	addPadding(listFrame, 4, 4, 4, 4)

	local options = {}
	for _, o in ipairs(opts.Options or {}) do
		options[#options + 1] = tostring(o)
	end
	local el = { Type = "List", Instance = row, Value = opts.Default, Default = opts.Default, Changed = newSignal() }

	local function rebuild()
		for _, child in ipairs(listFrame:GetChildren()) do
			if child:IsA("TextButton") then
				child:Destroy()
			end
		end
		local filter = searchBox and searchBox.Text:lower() or ""
		local order = 0
		for _, opt in ipairs(options) do
			if filter == "" or string.find(opt:lower(), filter, 1, true) then
				order = order + 1
				local selected = el.Value == opt
				local item = new("TextButton", {
					Text = "",
					AutoButtonColor = false,
					Size = UDim2.new(1, 0, 0, 26),
					BackgroundColor3 = Theme.TabButtonSelected,
					BackgroundTransparency = selected and 0 or 1,
					BorderSizePixel = 0,
					LayoutOrder = order,
					Parent = listFrame,
				})
				addCorner(item, 4)
				newText({
					Text = opt,
					TextSize = 13,
					Position = UDim2.fromOffset(9, 0),
					Size = UDim2.new(1, -14, 1, 0),
					TextColor3 = selected and Theme.Accent or Theme.TextColor,
					TextTruncate = Enum.TextTruncate.AtEnd,
					Parent = item,
				}, false)
				item.MouseEnter:Connect(function()
					if el.Value ~= opt then
						tween(item, { BackgroundTransparency = 0.6 }, 0.1)
					end
				end)
				item.MouseLeave:Connect(function()
					if el.Value ~= opt then
						tween(item, { BackgroundTransparency = 1 }, 0.1)
					end
				end)
				item.Activated:Connect(function()
					el:Set(opt)
				end)
			end
		end
	end
	if searchBox then
		searchBox:GetPropertyChangedSignal("Text"):Connect(rebuild)
	end
	onTheme(rebuild)

	function el:SetOptions(list)
		options = {}
		for _, o in ipairs(list or {}) do
			options[#options + 1] = tostring(o)
		end
		if self.Value ~= nil and not table.find(options, self.Value) then
			self.Value = nil
		end
		rebuild()
	end
	function el:Set(value, silent)
		if value ~= nil then
			value = tostring(value)
		end
		self.Value = value
		rebuild()
		if not silent then
			safeCall(opts.OnChanged, value)
			self.Changed:Fire(value)
			UH:_changed()
		end
	end
	function el:Get()
		return self.Value
	end
	function el:Serialize()
		return self.Value
	end
	function el:Deserialize(v)
		if type(v) == "string" then
			self:Set(v)
		end
	end

	attachVisibility(el, row, divider)
	self:_register(opts, el, opts.Label)
	return el
end

-- Slider
function Section:AddSlider(opts)
	local min, max = opts.Min or 0, opts.Max or 100
	local inc = opts.Increment or 1
	local suffix = opts.Suffix or ""
	local default = math.clamp(opts.Default or min, min, max)
	local row, divider = self:_row(54, opts.Label)
	rowLabel(row, opts.Label, UDim2.new(1, -100, 0, 20)).Position = UDim2.fromOffset(12, 6)
	local valueLabel = newText({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 6),
		Size = UDim2.fromOffset(80, 20),
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = row,
	}, "Muted")
	local track = new("Frame", {
		Name = "Track",
		Position = UDim2.new(0, 12, 0, 34),
		Size = UDim2.new(1, -24, 0, 6),
		BorderSizePixel = 0,
		Parent = row,
	})
	bind(track, { BackgroundColor3 = "InputBackground" })
	addCorner(track, 3)
	addStroke(track, "Outline")
	local fill = new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BorderSizePixel = 0,
		Parent = track,
	})
	bind(fill, { BackgroundColor3 = "Accent" })
	addCorner(fill, 3)
	local hit = new("TextButton", {
		Name = "Hit",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 12, 0, 24),
		Size = UDim2.new(1, -24, 0, 26),
		Parent = row,
	})

	local el = { Type = "Slider", Instance = row, Value = default, Default = default, Changed = newSignal() }
	local decimals = 0
	if inc < 1 then
		decimals = math.min(4, math.ceil(-math.log10(inc)))
	end
	local function render()
		valueLabel.Text = string.format("%." .. decimals .. "f", el.Value) .. suffix
		local rel = (max > min) and (el.Value - min) / (max - min) or 0
		fill.Size = UDim2.fromScale(rel, 1)
	end
	render()

	function el:Set(value, silent)
		value = tonumber(value)
		if not value then
			return
		end
		value = math.clamp(value, min, max)
		value = math.floor((value - min) / inc + 0.5) * inc + min
		value = tonumber(string.format("%.4f", math.clamp(value, min, max)))
		local changed = value ~= self.Value
		self.Value = value
		render()
		if changed and not silent then
			safeCall(opts.OnChanged, value)
			self.Changed:Fire(value)
			UH:_changed()
		end
	end
	function el:Get()
		return self.Value
	end
	function el:Serialize()
		return self.Value
	end
	function el:Deserialize(v)
		if type(v) == "number" then
			self:Set(v)
		end
	end

	local function setFromX(x)
		local rel = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
		el:Set(min + (max - min) * rel)
	end
	hit.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			setFromX(input.Position.X)
			activeDrag = function(pos)
				setFromX(pos.X)
			end
		end
	end)

	attachVisibility(el, row, divider)
	self:_register(opts, el, opts.Label)
	return el
end

-- Keybind
function Section:AddKeybind(opts)
	local row, divider = self:_row(46, opts.Label)
	rowLabel(row, opts.Label, UDim2.new(1, -130, 1, 0))
	local button = new("TextButton", {
		Name = "Keybind",
		Text = "",
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -13, 0.5, 0),
		Size = UDim2.fromOffset(92, 23),
		BorderSizePixel = 0,
		Parent = row,
	})
	bind(button, { BackgroundColor3 = "ElementBackground" })
	addCorner(button, 5)
	local stroke = addStroke(button, "Outline")
	local keyLabel = newText({
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 1, 0),
		Parent = button,
	})

	local default = opts.Default or "None"
	if typeof(default) == "EnumItem" then
		default = default.Name
	end
	local mode = tostring(opts.Mode or "Toggle"):lower() == "hold" and "Hold" or "Toggle"
	local el = {
		Type = "Keybind",
		Instance = row,
		Value = default,
		Default = default,
		Changed = newSignal(),
		Triggered = newSignal(),
		Mode = mode,
		Active = false,
		AutoTrigger = opts.AutoTrigger ~= false,
	}
	local function render()
		keyLabel.Text = el.Value
		if el.Entry then
			el.Entry:SetKey(el.Value)
		end
	end
	-- every keybind is listed in the on-screen keybind list (InKeybindList = false hides it)
	el.Entry = UH:AddKeybindEntry({
		Label = opts.ListLabel or opts.Label or "Keybind",
		Key = el.Value,
		Mode = mode,
		Visible = opts.InKeybindList ~= false,
	})
	render()

	function el:Set(value, silent)
		value = tostring(value or "None")
		if value ~= "None" and not Enum.KeyCode[value] then
			return
		end
		self.Value = value
		render()
		if not silent then
			safeCall(opts.OnChanged, value)
			self.Changed:Fire(value)
			UH:_changed()
		end
	end
	function el:Get()
		return self.Value
	end
	function el:Serialize()
		return self.Value
	end
	function el:Deserialize(v)
		if type(v) == "string" then
			self:Set(v)
		end
	end
	-- list helpers
	function el:SetActive(active)
		self.Active = active == true
		self.Entry:SetActive(self.Active)
	end
	function el:SetShowInList(v)
		self.Entry:SetShown(v)
	end
	function el:_capture(input)
		if input.KeyCode == Enum.KeyCode.Escape then
			-- Cancel capture
		elseif input.KeyCode == Enum.KeyCode.Backspace and opts.AllowNone ~= false then
			self:Set("None")
		elseif input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode ~= Enum.KeyCode.Unknown then
			self:Set(input.KeyCode.Name)
		end
		UH._capturing = nil
		render()
		tween(stroke, { Color = Theme.Outline }, 0.12)
	end

	button.Activated:Connect(function()
		if UH._capturing == el then
			return
		end
		UH._capturing = el
		keyLabel.Text = "..."
		tween(stroke, { Color = Theme.Accent }, 0.12)
	end)

	UH._keybinds[#UH._keybinds + 1] = { El = el, OnTriggered = opts.OnTriggered }
	attachVisibility(el, row, divider)
	self:_register(opts, el, opts.Label)
	return el
end

-- keybind triggering (drives the "active" look in the keybind list)
function UH:_keyDown(name)
	for _, k in ipairs(UH._keybinds) do
		local el = k.El
		if el.AutoTrigger and el.Value == name then
			if el.Mode == "Hold" then
				el:SetActive(true)
			else
				el:SetActive(not el.Active)
			end
			safeCall(k.OnTriggered, el.Active)
			el.Triggered:Fire(el.Active)
		end
	end
end

function UH:_keyUp(name)
	for _, k in ipairs(UH._keybinds) do
		local el = k.El
		if el.AutoTrigger and el.Mode == "Hold" and el.Value == name and el.Active then
			el:SetActive(false)
			safeCall(k.OnTriggered, false)
			el.Triggered:Fire(false)
		end
	end
end

-- Color  (swatch + popup picker: saturation/value square, hue bar, hex input)
local function colorToHex(c)
	return string.format("%02X%02X%02X", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

local function hexToColor(s)
	s = tostring(s or ""):gsub("[#%s]", "")
	if #s == 3 then
		s = s:sub(1, 1):rep(2) .. s:sub(2, 2):rep(2) .. s:sub(3, 3):rep(2)
	end
	if not s:match("^%x%x%x%x%x%x$") then
		return nil
	end
	return Color3.fromRGB(tonumber(s:sub(1, 2), 16), tonumber(s:sub(3, 4), 16), tonumber(s:sub(5, 6), 16))
end

local function isPress(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

function Section:AddColor(opts)
	local row, divider = self:_row(47, opts.Label)
	local hit = new("TextButton", {
		Name = "Hit",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		Parent = row,
	})
	local lbl = rowLabel(row, opts.Label, UDim2.new(1, -70, 1, 0))
	local swatch = new("Frame", {
		Name = "Swatch",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -13, 0.5, 0),
		Size = UDim2.fromOffset(24, 24),
		BorderSizePixel = 0,
		Parent = row,
	})
	addCorner(swatch, 5)
	local stroke = addStroke(swatch, "Outline")

	local default = typeof(opts.Default) == "Color3" and opts.Default or Color3.new(1, 1, 1)
	local el = { Type = "Color", Instance = row, Value = default, Default = default, Changed = newSignal() }
	local function render()
		swatch.BackgroundColor3 = el.Value
	end
	render()

	function el:Set(value, silent)
		if typeof(value) ~= "Color3" then
			return
		end
		self.Value = value
		render()
		if self._refreshPicker then
			self._refreshPicker()
		end
		if not silent then
			safeCall(opts.OnChanged, value)
			self.Changed:Fire(value)
			UH:_changed()
		end
	end
	function el:Get()
		return self.Value
	end
	function el:Serialize()
		return colorToHex(self.Value)
	end
	function el:Deserialize(v)
		if type(v) == "string" then
			local c = hexToColor(v)
			if c then
				self:Set(c)
			end
		end
	end

	local function open()
		if UH._currentDropdown == el then
			closePopup()
			return
		end
		closePopup()
		UH._currentDropdown = el

		local W, H = 252, 262
		local SV_W, SV_H = 206, 188
		local pos, size = localRect(swatch)
		local mainW, mainH = Main.AbsoluteSize.X / Scale.Scale, Main.AbsoluteSize.Y / Scale.Scale
		local x = math.clamp(pos.X + size.X - W, 6, math.max(mainW - W - 6, 6))
		local y = pos.Y + size.Y + 6
		if y + H > mainH - 6 then
			y = math.max(pos.Y - H - 6, 6)
		end

		local blocker = new("TextButton", {
			Name = "Blocker",
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 1, 0),
			Parent = Overlay,
		})
		local popup = new("Frame", {
			Name = "ColorPopup",
			Active = true,
			Position = UDim2.fromOffset(x, y),
			Size = UDim2.fromOffset(W, H),
			BorderSizePixel = 0,
			Parent = Overlay,
		})
		bind(popup, { BackgroundColor3 = "ElementBackground" })
		addCorner(popup, 6)
		addStroke(popup, "Unselected")
		newText({
			Text = "Color",
			TextSize = 12,
			Position = UDim2.fromOffset(12, 8),
			Size = UDim2.fromOffset(120, 14),
			Parent = popup,
		}, "Muted")

		local h, s, v = Color3.toHSV(el.Value)

		-- saturation / value square
		local svBox = new("Frame", {
			Name = "SV",
			Position = UDim2.fromOffset(12, 28),
			Size = UDim2.fromOffset(SV_W, SV_H),
			BorderSizePixel = 0,
			Parent = popup,
		})
		addCorner(svBox, 4)
		local whiteLayer = new("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			ZIndex = 2,
			Parent = svBox,
		}, {
			new("UICorner", { CornerRadius = UDim.new(0, 4) }),
			new("UIGradient", { Transparency = NumberSequence.new(0, 1) }),
		})
		local blackLayer = new("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BorderSizePixel = 0,
			ZIndex = 3,
			Parent = svBox,
		}, {
			new("UICorner", { CornerRadius = UDim.new(0, 4) }),
			new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(1, 0) }),
		})
		local svCursor = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(12, 12),
			ZIndex = 5,
			Parent = svBox,
		}, {
			new("UICorner", { CornerRadius = UDim.new(1, 0) }),
			new("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
		})
		local svHit = new("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 6,
			Parent = svBox,
		})

		-- hue bar
		local hueBar = new("Frame", {
			Name = "Hue",
			Position = UDim2.fromOffset(12 + SV_W + 10, 28),
			Size = UDim2.fromOffset(14, SV_H),
			BorderSizePixel = 0,
			BackgroundColor3 = Color3.new(1, 1, 1),
			Parent = popup,
		}, {
			new("UICorner", { CornerRadius = UDim.new(0, 4) }),
			new("UIGradient", {
				Rotation = 90,
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.fromHSV(0, 1, 1)),
					ColorSequenceKeypoint.new(1 / 6, Color3.fromHSV(1 / 6, 1, 1)),
					ColorSequenceKeypoint.new(2 / 6, Color3.fromHSV(2 / 6, 1, 1)),
					ColorSequenceKeypoint.new(3 / 6, Color3.fromHSV(3 / 6, 1, 1)),
					ColorSequenceKeypoint.new(4 / 6, Color3.fromHSV(4 / 6, 1, 1)),
					ColorSequenceKeypoint.new(5 / 6, Color3.fromHSV(5 / 6, 1, 1)),
					ColorSequenceKeypoint.new(1, Color3.fromHSV(0, 1, 1)),
				}),
			}),
		})
		local hueHandle = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(20, 6),
			ZIndex = 3,
			Parent = hueBar,
		}, {
			new("UICorner", { CornerRadius = UDim.new(0, 3) }),
			new("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 1, Transparency = 0.5 }),
		})
		local hueHit = new("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 4,
			Parent = hueBar,
		})

		-- hex input
		newText({
			Text = "Input",
			TextSize = 12,
			Position = UDim2.fromOffset(12, 230),
			Size = UDim2.fromOffset(60, 20),
			Parent = popup,
		}, "Muted")
		local hexBox = new("TextBox", {
			Name = "Hex",
			Position = UDim2.fromOffset(W - 12 - 104, 228),
			Size = UDim2.fromOffset(104, 24),
			BorderSizePixel = 0,
			ClearTextOnFocus = false,
			Text = "",
			PlaceholderText = "RRGGBB",
			TextSize = 12,
			FontFace = Fonts.Medium,
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = popup,
		})
		bind(hexBox, { BackgroundColor3 = "InputBackground", TextColor3 = "TextColor" })
		addCorner(hexBox, 5)
		addStroke(hexBox, "Outline")

		local internal = false
		local function redraw()
			svBox.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
			svCursor.Position = UDim2.fromScale(s, 1 - v)
			hueHandle.Position = UDim2.fromScale(0.5, h)
			if not hexBox:IsFocused() then
				hexBox.Text = colorToHex(el.Value)
			end
		end
		local function push()
			internal = true
			el:Set(Color3.fromHSV(h, s, v))
			internal = false
			redraw()
		end
		el._refreshPicker = function()
			if internal then
				return
			end
			h, s, v = Color3.toHSV(el.Value)
			redraw()
		end
		redraw()

		local function setSV(p)
			s = math.clamp((p.X - svBox.AbsolutePosition.X) / math.max(svBox.AbsoluteSize.X, 1), 0, 1)
			v = 1 - math.clamp((p.Y - svBox.AbsolutePosition.Y) / math.max(svBox.AbsoluteSize.Y, 1), 0, 1)
			push()
		end
		local function setHue(p)
			h = math.clamp((p.Y - hueBar.AbsolutePosition.Y) / math.max(hueBar.AbsoluteSize.Y, 1), 0, 0.999)
			push()
		end
		svHit.InputBegan:Connect(function(input)
			if isPress(input) then
				setSV(input.Position)
				activeDrag = setSV
			end
		end)
		hueHit.InputBegan:Connect(function(input)
			if isPress(input) then
				setHue(input.Position)
				activeDrag = setHue
			end
		end)
		hexBox.FocusLost:Connect(function()
			local c = hexToColor(hexBox.Text)
			if c then
				internal = true
				el:Set(c)
				internal = false
				h, s, v = Color3.toHSV(c)
			end
			redraw()
		end)

		tween(stroke, { Color = Theme.Accent }, 0.12)
		local function close()
			if UH._popup == close then
				UH._popup = nil
				UH._currentDropdown = nil
			end
			el._refreshPicker = nil
			tween(stroke, { Color = Theme.Outline }, 0.12)
			blocker:Destroy()
			popup:Destroy()
		end
		UH._popup = close
		blocker.MouseButton1Down:Connect(closePopup)
	end

	hit.MouseEnter:Connect(function()
		tween(lbl, { TextColor3 = Theme.Accent }, 0.12)
	end)
	hit.MouseLeave:Connect(function()
		tween(lbl, { TextColor3 = Theme.TextColor }, 0.12)
	end)
	hit.Activated:Connect(open)

	attachVisibility(el, row, divider)
	self:_register(opts, el, opts.Label)
	return el
end

----------------------------------------------------------------------
-- Pages + tabs
----------------------------------------------------------------------
function Page:AddSection(opts)
	opts = opts or {}
	local side = (opts.Side == "right") and self.Right or self.Left
	if opts.Side == "full" then
		side = self.Left
		self.Left.Size = UDim2.new(1, 0, 0, 0)
		self.Right.Visible = false
	end
	self._order = self._order + 1
	if self.Empty then
		self.Empty.Visible = false
	end
	local holder = new("Frame", {
		Name = "Section",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = self._order,
		Parent = side,
	}, {
		new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 12) }),
	})
	if opts.Title and opts.Title ~= "" then
		newText({
			Name = "Title",
			Text = opts.Title,
			FontFace = Fonts.Bold,
			TextSize = 14,
			Size = UDim2.new(1, 0, 0, 20),
			LayoutOrder = 1,
			Parent = holder,
		})
	end
	local box = new("Frame", {
		Name = "Box",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BorderSizePixel = 0,
		LayoutOrder = 2,
		Parent = holder,
	}, {
		new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	bind(box, { BackgroundColor3 = "Background" })
	addCorner(box, 5)
	addStroke(box, "Outline")
	return setmetatable({ Page = self, Title = opts.Title, Box = box, Holder = holder, _count = 0 }, Section)
end

function Page:Select()
	local tab = self.Tab
	tab.CurrentPage = self
	for _, p in ipairs(tab.Pages) do
		p.Active = (p == self)
		p.Scroll.Visible = p.Active and tab.Active
		if p.Paint then
			p:Paint(true)
		end
	end
end

function Page:_buildPill()
	local tab = self.Tab
	local pill = new("TextButton", {
		Name = self.Label,
		Text = "",
		AutoButtonColor = false,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = #tab.Pages,
		Parent = tab.SubBar,
	}, {
		new("UICorner", { CornerRadius = UDim.new(0, 5) }),
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 16),
		}),
		new("UIPadding", {
			PaddingLeft = UDim.new(0, self.Icon and 13 or 33),
			PaddingRight = UDim.new(0, self.Icon and 15 or 33),
		}),
	})
	local icon
	if self.Icon then
		icon = makeIcon(pill, self.Icon, 22)
		icon.LayoutOrder = 1
	end
	local text = newText({
		Text = self.Label,
		TextSize = 15,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 0, 20),
		LayoutOrder = 2,
		Parent = pill,
	}, false)

	local hover = false
	function self:Paint(animate)
		local active = self.Active
		local bg = active and 0 or 1
		local col = (active or hover) and Theme.Accent or Theme.Muted
		pill.BackgroundColor3 = Theme.TabButtonSelected
		if animate then
			tween(pill, { BackgroundTransparency = bg }, 0.15)
			tween(text, { TextColor3 = col }, 0.15)
			if icon then
				tween(icon, { ImageColor3 = col }, 0.15)
			end
		else
			pill.BackgroundTransparency = bg
			text.TextColor3 = col
			if icon then
				icon.ImageColor3 = col
			end
		end
	end
	pill.MouseEnter:Connect(function()
		hover = true
		self:Paint(true)
	end)
	pill.MouseLeave:Connect(function()
		hover = false
		self:Paint(true)
	end)
	pill.Activated:Connect(function()
		self:Select()
	end)
	onTheme(function()
		self:Paint(false)
	end)
end

function Tab:_layoutPages()
	local top = self.Named > 0 and 73 or 12
	for _, p in ipairs(self.Pages) do
		p.Scroll.Position = UDim2.fromOffset(0, top)
		p.Scroll.Size = UDim2.new(1, 0, 1, -top)
	end
end

function Tab:AddPage(opts)
	opts = opts or {}
	local page = setmetatable({ Tab = self, Label = opts.Label, Icon = opts.Icon, _order = 0, Active = false }, Page)
	self.Pages[#self.Pages + 1] = page

	local scroll = new("ScrollingFrame", {
		Name = "Page",
		Visible = false,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		VerticalScrollBarInset = Enum.ScrollBarInset.Always,
		HorizontalScrollBarInset = Enum.ScrollBarInset.None,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ElasticBehavior = Enum.ElasticBehavior.Never,
		ClipsDescendants = true,
		Parent = Content,
	})
	bind(scroll, { ScrollBarImageColor3 = "TabButtonSelected" })
	-- no UIPadding on the scroller (it caused right/bottom cut-off); margins are applied on the grid instead
	page.Scroll = scroll

	local grid = new("Frame", {
		Name = "Grid",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(18, 12),
		Size = UDim2.new(1, -36, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = scroll,
	}, {
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Top,
			Padding = UDim.new(0, 18),
		}),
		-- bottom breathing room so the last row is never hidden behind the window edge / resize grip
		new("UIPadding", { PaddingBottom = UDim.new(0, 36) }),
	})
	local function column(order)
		return new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(0.5, -9, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = order,
			Parent = grid,
		}, {
			new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 16) }),
		})
	end
	page.Left = column(1)
	page.Right = column(2)

	page.Empty = newText({
		Text = "Nothing here yet",
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 120),
		Size = UDim2.fromOffset(300, 20),
		Parent = scroll,
	}, "SubText")

	if opts.Label then
		self.Named = self.Named + 1
		self.SubBar.Visible = self.Active
		page:_buildPill()
		UH._index[#UH._index + 1] = { Label = opts.Label, Tab = self, Page = page }
	end
	self:_layoutPages()
	return page
end

function Tab:AddSection(opts)
	if not self.DefaultPage then
		self.DefaultPage = self:AddPage({})
	end
	return self.DefaultPage:AddSection(opts)
end

function Tab:_paint(animate)
	local active, hover = self.Active, self.Hover
	local iconCol = (active and Theme.Accent) or (hover and Theme.Muted) or Theme.Unselected
	local textCol = (active and Theme.Accent) or (hover and Theme.TextColor) or Theme.Muted
	self.Gradient.Color = ColorSequence.new(Theme.TabHighlight, Theme.TabShadow)
	if animate then
		tween(self.Button, { BackgroundTransparency = active and 0 or 1 }, 0.15)
		tween(self.Icon, { ImageColor3 = iconCol }, 0.15)
		tween(self.Text, { TextColor3 = textCol }, 0.15)
	else
		self.Button.BackgroundTransparency = active and 0 or 1
		self.Icon.ImageColor3 = iconCol
		self.Text.TextColor3 = textCol
	end
end

function Tab:Select()
	closePopup()
	for _, t in ipairs(UH.Tabs) do
		t.Active = (t == self)
		t:_paint(true)
		t.SubBar.Visible = t.Active and t.Named > 0
		if not t.Active then
			for _, p in ipairs(t.Pages) do
				p.Scroll.Visible = false
			end
		end
	end
	UH.CurrentTab = self
	TitleLabel.Text = self.Label
	SubtitleLabel.Text = self.Description
	if not self.DefaultPage and #self.Pages == 0 then
		self.DefaultPage = self:AddPage({})
	end
	local page = self.CurrentPage or self.Pages[1]
	if page then
		page:Select()
	end
end

function UH:AddTab(opts)
	local tab = setmetatable({
		Label = opts.Label,
		Description = opts.Description or "",
		Pages = {},
		Named = 0,
		Active = false,
		Hover = false,
	}, Tab)

	local button = new("TextButton", {
		Name = opts.Label,
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(66, 66),
		LayoutOrder = #UH.Tabs + 1,
		Parent = TabList,
	})
	addCorner(button, 6)
	tab.Gradient = new("UIGradient", { Rotation = 90, Parent = button })
	tab.Button = button
	tab.Icon = makeIcon(button, opts.Icon or ASSETS[opts.Label] or "", 24)
	tab.Icon.AnchorPoint = Vector2.new(0.5, 0.5)
	tab.Icon.Position = UDim2.fromOffset(33, 23)
	tab.Text = newText({
		Text = opts.Label,
		FontFace = Fonts.Medium,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(33, 53),
		Size = UDim2.new(1, 0, 0, 14),
		Parent = button,
	}, false)

	tab.SubBar = new("Frame", {
		Name = opts.Label .. "_SubTabs",
		Visible = false,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(18, 17),
		Size = UDim2.new(1, -36, 0, 50),
		Parent = Content,
	}, {
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 4),
		}),
	})

	button.MouseEnter:Connect(function()
		tab.Hover = true
		tab:_paint(true)
	end)
	button.MouseLeave:Connect(function()
		tab.Hover = false
		tab:_paint(true)
	end)
	button.Activated:Connect(function()
		tab:Select()
	end)
	onTheme(function()
		tab:_paint(false)
	end)

	UH.Tabs[#UH.Tabs + 1] = tab
	UH.TabsByName[opts.Label] = tab
	UH._index[#UH._index + 1] = { Label = opts.Label, Tab = tab }
	return tab
end

----------------------------------------------------------------------
-- Global search  (Ctrl+F)
----------------------------------------------------------------------
local SEARCH_W_IDLE, SEARCH_W_OPEN = 91, 260

local SearchFrame = new("Frame", {
	Name = "Search",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -14, 0, 25),
	Size = UDim2.fromOffset(SEARCH_W_IDLE, 34),
	BorderSizePixel = 0,
	Parent = Main,
})
bind(SearchFrame, { BackgroundColor3 = "Background" })
addCorner(SearchFrame, 6)
local SearchStroke = addStroke(SearchFrame, "Outline")

local SearchIcon = makeIcon(SearchFrame, ASSETS.Search, 16)
SearchIcon.AnchorPoint = Vector2.new(0, 0.5)
SearchIcon.Position = UDim2.new(0, 11, 0.5, 0)
bind(SearchIcon, { ImageColor3 = "Muted" })

local SearchBox = new("TextBox", {
	Name = "Input",
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ClearTextOnFocus = false,
	ClipsDescendants = true,
	Text = "",
	PlaceholderText = "",
	FontFace = Fonts.Medium,
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Left,
	Position = UDim2.fromOffset(34, 0),
	Size = UDim2.new(1, -56, 1, 0),
	Parent = SearchFrame,
})
bind(SearchBox, { TextColor3 = "TextColor", PlaceholderColor3 = "SubText" })

local SearchHint = newText({
	Text = "Ctrl+F",
	TextSize = 11,
	Position = UDim2.fromOffset(34, 0),
	Size = UDim2.new(1, -40, 1, 0),
	Active = false,
	Parent = SearchFrame,
}, "Muted")

local SearchClear = new("ImageButton", {
	Name = "Clear",
	Visible = false,
	BackgroundTransparency = 1,
	Image = ASSETS.Clear,
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -9, 0.5, 0),
	Size = UDim2.fromOffset(14, 14),
	AutoButtonColor = false,
	Parent = SearchFrame,
})
bind(SearchClear, { ImageColor3 = "Muted" })

local Results = new("Frame", {
	Name = "SearchResults",
	Visible = false,
	Size = UDim2.fromOffset(SEARCH_W_OPEN, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BorderSizePixel = 0,
	Parent = Overlay,
}, {
	new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2) }),
})
bind(Results, { BackgroundColor3 = "ElementBackground" })
addCorner(Results, 6)
addStroke(Results, "Unselected")
addPadding(Results, 4, 4, 4, 4)

local function flashRow(row)
	local flash = new("Frame", {
		BackgroundColor3 = Theme.Accent,
		BackgroundTransparency = 0.82,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, 0),
		Parent = row,
	})
	addCorner(flash, 4)
	local tw = tween(flash, { BackgroundTransparency = 1 }, 1.4)
	tw.Completed:Connect(function()
		flash:Destroy()
	end)
end

local function gotoEntry(entry)
	entry.Tab:Select()
	local page = entry.Page or entry.Tab.CurrentPage
	if page then
		page:Select()
	end
	if entry.Row and page then
		task.spawn(function()
			RunService.Heartbeat:Wait()
			RunService.Heartbeat:Wait()
			local scroll = page.Scroll
			local y = (entry.Row.AbsolutePosition.Y - scroll.AbsolutePosition.Y) / Scale.Scale + scroll.CanvasPosition.Y
			scroll.CanvasPosition = Vector2.new(0, math.max(0, y - 40))
			flashRow(entry.Row)
		end)
	end
end

local function hideResults()
	Results.Visible = false
end

local function runSearch(query)
	query = (query or ""):lower():match("^%s*(.-)%s*$")
	for _, child in ipairs(Results:GetChildren()) do
		if child:IsA("TextButton") or child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	if query == "" then
		hideResults()
		return
	end
	local found = {}
	for _, e in ipairs(UH._index) do
		local hay = (e.Label .. " " .. (e.Section or "") .. " " .. e.Tab.Label .. " " .. (e.Page and e.Page.Label or "")):lower()
		if string.find(hay, query, 1, true) then
			local score = string.find(e.Label:lower(), query, 1, true) or (100 + string.find(hay, query, 1, true))
			found[#found + 1] = { entry = e, score = score }
		end
	end
	table.sort(found, function(a, b)
		if a.score ~= b.score then
			return a.score < b.score
		end
		return a.entry.Label < b.entry.Label
	end)

	local w = Main.AbsoluteSize.X / Scale.Scale
	Results.Position = UDim2.fromOffset(w - 14 - SEARCH_W_OPEN, 65)
	Results.Visible = true

	if #found == 0 then
		newText({
			Text = "No results",
			TextSize = 12,
			Size = UDim2.new(1, 0, 0, 28),
			Parent = Results,
		}, "SubText")
		return
	end
	for i = 1, math.min(#found, 8) do
		local e = found[i].entry
		local item = new("TextButton", {
			Text = "",
			AutoButtonColor = false,
			Size = UDim2.new(1, 0, 0, 30),
			BackgroundColor3 = Theme.TabButtonSelected,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			LayoutOrder = i,
			Parent = Results,
		})
		addCorner(item, 4)
		newText({
			Text = e.Label,
			TextSize = 13,
			Position = UDim2.fromOffset(9, 0),
			Size = UDim2.new(0.55, -9, 1, 0),
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = item,
		})
		local where = e.Tab.Label
		if e.Page and e.Page.Label then
			where = where .. " / " .. e.Page.Label
		end
		newText({
			Text = where,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -9, 0, 0),
			Size = UDim2.new(0.45, -9, 1, 0),
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = item,
		}, "Muted")
		item.MouseEnter:Connect(function()
			tween(item, { BackgroundTransparency = 0.5 }, 0.1)
		end)
		item.MouseLeave:Connect(function()
			tween(item, { BackgroundTransparency = 1 }, 0.1)
		end)
		item.Activated:Connect(function()
			hideResults()
			gotoEntry(e)
		end)
	end
end

local lastHotkeyFocus = 0
SearchBox.Focused:Connect(function()
	SearchHint.Visible = false
	SearchBox.PlaceholderText = "Search settings..."
	tween(SearchFrame, { Size = UDim2.fromOffset(SEARCH_W_OPEN, 34) }, 0.15)
	tween(SearchStroke, { Color = Theme.Accent }, 0.15)
	runSearch(SearchBox.Text)
end)
SearchBox.FocusLost:Connect(function()
	SearchBox.PlaceholderText = ""
	SearchHint.Visible = SearchBox.Text == ""
	tween(SearchFrame, { Size = UDim2.fromOffset(SEARCH_W_IDLE, 34) }, 0.15)
	tween(SearchStroke, { Color = Theme.Outline }, 0.15)
	task.delay(0.2, hideResults)
end)
SearchBox:GetPropertyChangedSignal("Text"):Connect(function()
	if os.clock() - lastHotkeyFocus < 0.2 and SearchBox.Text:lower() == "f" then
		SearchBox.Text = ""
		return
	end
	SearchClear.Visible = SearchBox.Text ~= ""
	if SearchBox:IsFocused() then
		runSearch(SearchBox.Text)
	end
end)
SearchClear.Activated:Connect(function()
	SearchBox.Text = ""
	SearchBox:CaptureFocus()
end)

function UH:FocusSearch()
	if not UH.Visible then
		return
	end
	lastHotkeyFocus = os.clock()
	SearchBox:CaptureFocus()
end

----------------------------------------------------------------------
-- Visibility / unload
----------------------------------------------------------------------
function UH:SetVisible(v)
	UH.Visible = v
	Main.Visible = v
	if UH.MenuKeybind then
		UH.MenuKeybind:SetActive(v)
	end
	closePopup()
	hideResults()
end

function UH:Toggle()
	UH:SetVisible(not UH.Visible)
end

function UH.Unload()
	if UH.Unloaded then
		return
	end
	UH.Unloaded = true
	pcall(function()
		local s = Config.State
		if s.AutoSave and type(s.AutoSaveName) == "string" and s.AutoSaveName ~= "" then
			Config.Save(s.AutoSaveName)
		end
	end)
	for _, c in ipairs(UH.Connections) do
		pcall(function()
			c:Disconnect()
		end)
	end
	table.clear(UH.Connections)
	pcall(function()
		Gui:Destroy()
	end)
	if env.UH == UH then
		env.UH = nil
	end
end

----------------------------------------------------------------------
-- Tabs
----------------------------------------------------------------------
local tCombat = UH:AddTab({ Label = "Combat", Icon = ASSETS.Combat, Description = "Combat options and modules." })
local tVisuals = UH:AddTab({ Label = "Visuals", Icon = ASSETS.Visuals, Description = "Visual options and overlays." })
local tPlayer = UH:AddTab({ Label = "Player", Icon = ASSETS.Player, Description = "Player and character options." })
local tAutomation = UH:AddTab({ Label = "Automation", Icon = ASSETS.Automation, Description = "Automation and scripted behaviors." })
local tWorld = UH:AddTab({ Label = "World", Icon = ASSETS.World, Description = "Lighting, post-processing, sky, and ambient sound." })
local tCosmetics = UH:AddTab({ Label = "Cosmetics", Icon = ASSETS.Cosmetics, Description = "Cosmetic options and presets." })
local tSettings = UH:AddTab({
	Label = "Settings",
	Icon = ASSETS.Settings,
	Description = "Menu preferences, config management, and theme customization.",
})

Config.LoadState()
UH:_restorePositions()

----------------------------------------------------------------------
-- Settings  >  General
----------------------------------------------------------------------
local pGeneral = tSettings:AddPage({ Label = "General", Icon = ASSETS.Gear })
local pConfig = tSettings:AddPage({ Label = "Config Profiles" })
local pTheme = tSettings:AddPage({ Label = "Theme" })

do
	local menu = pGeneral:AddSection({ Title = "Menu", Side = "left" })
	local menuKey = menu:AddKeybind({
		Label = "Menu Keybind",
		Default = "RightShift",
		ListLabel = "Menu",
		Mode = "Toggle",
		AutoTrigger = false, -- the menu toggles itself; the list entry follows UH.Visible
		OnChanged = function(name)
			local key = Enum.KeyCode[name]
			if key then
				UH.MenuKey = key
			end
		end,
	})
	UH.MenuKeybind = menuKey
	menuKey:SetActive(UH.Visible)
	menu:AddToggle({
		Label = "Show Keybinds",
		Default = true,
		OnChanged = function(v)
			UH:SetKeybindList(v)
		end,
	})
	menu:AddToggle({
		Label = "Show Menu Keybind in List",
		Default = true,
		OnChanged = function(v)
			menuKey:SetShowInList(v)
		end,
	})
	menu:AddToggle({
		Label = "Show Watermark",
		Default = true,
		OnChanged = function(v)
			UH:SetWatermark(v)
		end,
	})

	local notif = pGeneral:AddSection({ Title = "Notifications", Side = "right" })
	notif:AddToggle({
		Label = "Enable Notifications",
		Default = true,
		OnChanged = function(v)
			UH.Notif.Enabled = v
			UH.NotificationsEnabled = v
			UH:_applyNotifyLayout()
		end,
	})
	notif:AddDropdown({
		Label = "Position",
		Options = UH.NotifySides,
		Default = "TopLeft",
		OnChanged = function(v)
			UH.Notif.Side = v
			UH:_applyNotifyLayout()
		end,
	})
	notif:AddSlider({
		Label = "Crosshair Offset",
		Min = -500,
		Max = 500,
		Default = 0,
		Suffix = "px",
		OnChanged = function(v)
			UH.Notif.Offset = v
			UH:_applyNotifyLayout()
		end,
	})
	notif:AddSlider({
		Label = "Text Size",
		Min = 10,
		Max = 28,
		Default = 15,
		OnChanged = function(v)
			UH.Notif.Size = v
		end,
	})
	notif:AddDropdown({
		Label = "Font",
		Options = UH.NotifyFonts,
		Default = "Inconsolata",
		OnChanged = function(v)
			UH.Notif.Font = v
		end,
	})
	notif:AddButton({
		Label = "Test Notification",
		OnClick = function()
			UH:Notify("This is a test notification.", 6)
			UH:Notify({ { Text = "Hit " }, { Text = "Player", Accent = true }, { Text = " for " }, { Text = "34", Accent = true }, { Text = " in Head" } }, 6)
			UH:Notify("Success notification", 6, { Intent = "success" })
			UH:Notify("Warning notification", 6, { Intent = "warning" })
			UH:Notify("Error notification", 6, { Intent = "error" })
		end,
	})

	local session = pGeneral:AddSection({ Title = "Session", Side = "right" })
	session:AddButton({
		Label = "Unload UH",
		Confirm = true,
		ConfirmMessage = "This closes the menu and removes it from the game.",
		OnClick = function()
			UH.Unload()
		end,
	})
end

----------------------------------------------------------------------
-- Settings  >  Config Profiles
----------------------------------------------------------------------
do
	local profiles = pConfig:AddSection({ Title = "Whole-Menu Profiles", Side = "left" })
	local transfer = pConfig:AddSection({ Title = "Transfer", Side = "right" })
	local automation = pConfig:AddSection({ Title = "Automation", Side = "right" })

	local function report(ok, err, action)
		if ok then
			return true
		end
		UH:Notify(action .. " failed: " .. tostring(err), 4, true)
		return false
	end

	local nameBox = profiles:AddTextBox({ Label = "Config Name", Persist = false })
	local createBtn = profiles:AddButton({ Label = "Create Config" })
	local list = profiles:AddList({ Label = "Configs", Options = Config.All(), Height = 140, Search = true, Persist = false })
	local refreshBtn = profiles:AddButton({ Label = "Refresh List" })
	local loadBtn, saveBtn, deleteBtn
	local autoSaveToggle, autoSaveDrop, autoLoadToggle, autoLoadDrop

	local function refreshLists()
		local all = Config.All()
		list:SetOptions(all)
		if autoSaveDrop then
			autoSaveDrop:SetOptions(all)
		end
		if autoLoadDrop then
			autoLoadDrop:SetOptions(all)
		end
	end

	createBtn.Clicked:Connect(function()
		local ok, res = Config.Create(nameBox:Get())
		if not report(ok, res, "Creating config") then
			return
		end
		refreshLists()
		list:Set(res, true)
		UH:Notify("Created config '" .. res .. "'")
	end)

	refreshBtn.Clicked:Connect(function()
		refreshLists()
		local s = Config.State
		local pick = s.AutoSaveName or s.AutoLoadName
		if pick and table.find(Config.All(), pick) then
			list:Set(pick, true)
		end
	end)

	loadBtn = profiles:AddButton({
		Label = "Load Selected Config",
		Confirm = true,
		OnClick = function()
			local name = list.Value
			if type(name) ~= "string" then
				UH:Notify("Select a config first", 3, true)
				return
			end
			local ok, res = Config.Load(name)
			if report(ok, res, "Loading config") then
				UH:Notify("Loaded '" .. name .. "' (" .. tostring(res) .. " settings)")
			end
		end,
	})

	saveBtn = profiles:AddButton({
		Label = "Save to Selected Config",
		Confirm = true,
		OnClick = function()
			local name = list.Value
			if type(name) ~= "string" or name == "" then
				UH:Notify("Select a config first", 3, true)
				return
			end
			local ok, err = Config.Save(name)
			if report(ok, err, "Saving config") then
				UH:Notify("Saved to '" .. name .. "'")
			end
		end,
	})

	deleteBtn = profiles:AddButton({ Label = "Delete Selected Config", Confirm = true })
	deleteBtn.Clicked:Connect(function()
		local name = list.Value
		if type(name) ~= "string" then
			UH:Notify("Select a config first", 3, true)
			return
		end
		local ok, err = Config.Delete(name)
		if not report(ok, err, "Deleting config") then
			return
		end
		local s = Config.State
		if s.AutoSaveName == name then
			s.AutoSaveName = nil
			if autoSaveDrop then
				autoSaveDrop:Set(nil, true)
			end
		end
		if s.AutoLoadName == name then
			s.AutoLoadName = nil
			if autoLoadDrop then
				autoLoadDrop:Set(nil, true)
			end
		end
		Config.SaveState()
		list:Set(nil, true)
		refreshLists()
		UH:Notify("Deleted '" .. name .. "'")
	end)

	-- Transfer
	transfer:AddButton({
		Label = "Export to Clipboard",
		OnClick = function()
			local enc, err = Config.Encode(false)
			if not enc then
				report(false, err, "Exporting config")
				return
			end
			local clip = env.setclipboard or env.toclipboard or env.set_clipboard or (env.syn and env.syn.write_clipboard)
			if clip then
				local ok, cerr = pcall(clip, enc)
				if ok then
					UH:Notify("Copied your current config to the clipboard")
					return
				end
				err = cerr
			end
			UH.ImportBox:Set(enc)
			UH:Notify("Clipboard not available. Config placed in the import box.", 4, true)
		end,
	})
	UH.ImportBox = transfer:AddTextBox({ Label = "Import (paste config)", FocusLostOnly = true, Persist = false })
	transfer:AddButton({
		Label = "Import Config",
		Confirm = true,
		OnClick = function()
			local raw = UH.ImportBox:Get()
			if raw == "" then
				UH:Notify("Paste a config into the import box first", 3, true)
				return
			end
			local ok, res = Config.LoadJson(raw)
			if report(ok, res, "Importing config") then
				UH:Notify("Imported config (" .. tostring(res) .. " settings)")
			end
		end,
	})

	-- Automation
	local s = Config.State
	autoSaveToggle = automation:AddToggle({
		Label = "Auto Save",
		Persist = false,
		Default = s.AutoSave,
		OnChanged = function(v)
			Config.State.AutoSave = v
			Config.SaveState()
			if v and not Config.State.AutoSaveName then
				UH:Notify("Pick a profile under 'Profile to Auto Save'", 3.5, true)
			end
		end,
	})
	autoSaveDrop = automation:AddDropdown({
		Label = "Profile to Auto Save",
		Persist = false,
		Options = Config.All(),
		GetOptions = Config.All,
		Default = s.AutoSaveName,
		OnChanged = function(v)
			Config.State.AutoSaveName = v
			Config.SaveState()
		end,
	})
	autoLoadToggle = automation:AddToggle({
		Label = "Auto Load",
		Persist = false,
		Default = s.AutoLoad,
		OnChanged = function(v)
			Config.State.AutoLoad = v
			Config.SaveState()
			if v and not Config.State.AutoLoadName then
				UH:Notify("Pick a profile under 'Profile to Auto Load'", 3.5, true)
			end
		end,
	})
	autoLoadDrop = automation:AddDropdown({
		Label = "Profile to Auto Load",
		Persist = false,
		Options = Config.All(),
		GetOptions = Config.All,
		Default = s.AutoLoadName,
		OnChanged = function(v)
			Config.State.AutoLoadName = v
			Config.SaveState()
		end,
	})

	local initial = s.AutoSaveName or s.AutoLoadName
	if initial and table.find(Config.All(), initial) then
		list:Set(initial, true)
	end
end

----------------------------------------------------------------------
-- Settings  >  Theme
----------------------------------------------------------------------
do
	local colors = pTheme:AddSection({ Title = "Theme Colors", Side = "full" })
	local pickers = {}

	for _, entry in ipairs(UH.ThemeKeys) do
		local key = entry.Key
		pickers[key] = colors:AddColor({
			Label = entry.Label,
			Default = UH.ThemeDefaults[key],
			Flag = "Theme/" .. key,
			OnChanged = function(color)
				UH:SetThemeColor(key, color)
			end,
		})
	end

	-- keep the swatches in sync when a color changes indirectly
	-- (e.g. "Selected Tab" follows the accent until you pick it yourself, or Reset Theme)
	onTheme(function()
		for key, el in pairs(pickers) do
			local current = Theme[key]
			if current ~= nil and el.Value ~= current then
				el:Set(current, true)
			end
		end
	end)

	local iface = pTheme:AddSection({ Title = "Interface", Side = "full" })
	iface:AddSlider({
		Label = "Menu Scale",
		Min = 70,
		Max = 130,
		Default = 100,
		Suffix = "%",
		Flag = "Theme/MenuScale",
		OnChanged = function(v)
			UH.UserScale = v / 100
			updateScale()
		end,
	})
	iface:AddButton({
		Label = "Reset Theme",
		Confirm = true,
		ConfirmMessage = "This resets every theme color back to its default.",
		OnClick = function()
			UH:ResetTheme()
			UH:_changed()
		end,
	})
end

----------------------------------------------------------------------
-- Example section
----------------------------------------------------------------------
do
	local ex = tPlayer:AddSection({ Title = "Example", Side = "left" })
	ex:AddToggle({ Label = "Example Toggle", Default = false })
	ex:AddSlider({ Label = "Example Slider", Min = 0, Max = 100, Default = 50, Suffix = "%" })
	ex:AddDropdown({ Label = "Example Dropdown", Options = { "One", "Two", "Three" }, Default = "One" })
	ex:AddKeybind({ Label = "Example Keybind", Default = "E" })
	ex:AddTextBox({ Label = "Example Text", Placeholder = "type..." })
end

----------------------------------------------------------------------
-- Global input
----------------------------------------------------------------------
connect(UserInputService.InputBegan, function(input)
	if UH.Unloaded then
		return
	end
	if UH._capturing then
		UH._capturing:_capture(input)
		return
	end
	if input.UserInputType ~= Enum.UserInputType.Keyboard then
		return
	end
	if UserInputService:GetFocusedTextBox() then
		return
	end
	if input.KeyCode == UH.MenuKey then
		UH:Toggle()
	elseif
		input.KeyCode == Enum.KeyCode.F
		and (UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl))
	then
		UH:FocusSearch()
	else
		UH:_keyDown(input.KeyCode.Name)
	end
end)

connect(UserInputService.InputChanged, function(input)
	if
		activeDrag
		and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch)
	then
		activeDrag(input.Position)
	end
end)

connect(UserInputService.InputEnded, function(input)
	if
		activeDrag
		and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch)
	then
		activeDrag = nil
		if UH._dragDirty then
			UH._dragDirty = false
			Config.SaveState()
		end
	end
	if input.UserInputType == Enum.UserInputType.Keyboard and not UH._capturing then
		UH:_keyUp(input.KeyCode.Name)
	end
end)

----------------------------------------------------------------------
-- Start
----------------------------------------------------------------------
tSettings:Select()
pConfig:Select()

task.defer(function()
	local s = Config.State
	if s.AutoLoad and type(s.AutoLoadName) == "string" and FS.exists(configPath(s.AutoLoadName)) then
		local ok, res = Config.Load(s.AutoLoadName)
		if ok then
			UH:Notify("Auto loaded '" .. s.AutoLoadName .. "' (" .. tostring(res) .. " settings)")
		else
			UH:Notify("Auto load failed: " .. tostring(res), 4, true)
		end
	end
end)

return UH
