-- SGVA BLADE BALL HUB v2
-- BLADE BALL VERSION
-- DEVELOPER: SAGA
-- MODE: Stealth + Fast Loading

print("[SGVA-BB] SCRIPT START v2 Stealth")

-- ============================================================
-- SAFE ENVIRONMENT (MINIMAL API SURFACE)
-- ============================================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
    LocalPlayer = Players.LocalPlayer
end

-- STEALTH: Refresh service dengan pcall
local function RefreshBackendServices()
    local vim, vu = nil, nil
    pcall(function() vim = game:GetService("VirtualInputManager") end)
    pcall(function() vu = game:GetService("VirtualUser") end)
    return vim, vu
end

local VirtualInputManager, VirtualUser = RefreshBackendServices()

local GlobalEnv
if getgenv then
    local ok, env = pcall(getgenv)
    GlobalEnv = (ok and env) or _G
else
    GlobalEnv = _G
end

if GlobalEnv.SGVA_BB_Cleanup then
    pcall(GlobalEnv.SGVA_BB_Cleanup)
end

-- ============================================================
-- UI PARENT (STEALTH: coba gethui dulu)
-- ============================================================
local function GetUIParent()
    if gethui then
        local ok, hui = pcall(gethui)
        if ok and hui and typeof(hui) == "Instance" then return hui, "gethui" end
    end
    if get_hidden_gui then
        local ok, hgui = pcall(get_hidden_gui)
        if ok and hgui and typeof(hgui) == "Instance" then return hgui, "get_hidden_gui" end
    end
    local CoreGui = game:GetService("CoreGui")
    if CoreGui then
        local ok = pcall(function()
            local t = Instance.new("Folder")
            t.Parent = CoreGui
            t:Destroy()
        end)
        if ok then return CoreGui, "CoreGui" end
    end
    local PlayerGui = LocalPlayer:WaitForChild("PlayerGui", 10)
    if PlayerGui then return PlayerGui, "PlayerGui" end
    return nil, nil
end

local UIParent, parentName = GetUIParent()
if not UIParent then
    warn("[SGVA-BB] No UI parent available.")
    return
end
print("[SGVA-BB] UI parent:", parentName)

for _, parent in ipairs({
    game:GetService("CoreGui"),
    LocalPlayer:FindFirstChild("PlayerGui"),
    UIParent
}) do
    if parent then
        local old = parent:FindFirstChild("SGVA_BLADE_BALL")
        if old then old:Destroy() end
    end
end

-- ============================================================
-- THEME
-- ============================================================
local Theme = {
    Background = Color3.fromRGB(4, 8, 18),
    Panel = Color3.fromRGB(10, 16, 32),
    PanelLight = Color3.fromRGB(16, 26, 48),
    PanelAccent = Color3.fromRGB(20, 34, 64),
    Accent = Color3.fromRGB(0, 180, 255),
    AccentGlow = Color3.fromRGB(80, 230, 255),
    AccentDark = Color3.fromRGB(0, 80, 160),
    Text = Color3.fromRGB(235, 245, 255),
    TextDim = Color3.fromRGB(120, 140, 180),
    Success = Color3.fromRGB(0, 240, 150),
    Danger = Color3.fromRGB(255, 60, 100),
    Warning = Color3.fromRGB(255, 200, 0)
}

-- ============================================================
-- STATE
-- ============================================================
local State = {
    AutoParry = false,
    AutoParryCurve = false,
    ParryRange = 60,
    ParryTiming = 0.32,
    ShowESP = false,
    AntiAFK = false,
    BallDetected = false,
    TargetConfirmed = false,
    InputBackendAvailable = (VirtualInputManager ~= nil),
    Destroyed = false,
    UserHasDraggedMain = false,
    -- STEALTH: track last action time untuk debounce
    LastSliderChange = 0
}

local LastVelocities = {}
local LastBall = nil
local ParryCooldown = 0
local LastParryTime = 0
local FKeyHeld = false
local ActivePopup = nil
local CachedBallsFolder = nil

-- ============================================================
-- CONNECTION MANAGER
-- ============================================================
local FeatureConnections = {}
local PersistentConnections = {}
local SliderConnections = {}
local UIConnections = {}

local function ConnectFeature(name, signal, callback)
    local old = FeatureConnections[name]
    if old then pcall(function() old:Disconnect() end) end
    FeatureConnections[name] = signal:Connect(callback)
    return FeatureConnections[name]
end

local function DisconnectFeature(name)
    local conn = FeatureConnections[name]
    if conn then
        pcall(function() conn:Disconnect() end)
        FeatureConnections[name] = nil
    end
end

local function ConnectPersistent(name, signal, callback)
    local old = PersistentConnections[name]
    if old then pcall(function() old:Disconnect() end) end
    PersistentConnections[name] = signal:Connect(callback)
    return PersistentConnections[name]
end

local function RegisterSliderConnection(id, signal, callback)
    local entry = SliderConnections[id]
    if entry then pcall(function() entry:Disconnect() end) end
    SliderConnections[id] = signal:Connect(callback)
end

local function RegisterUIConnection(id, conn)
    if UIConnections[id] then
        pcall(function() UIConnections[id]:Disconnect() end)
    end
    UIConnections[id] = conn
end

local function DisconnectAll()
    for _, conn in pairs(FeatureConnections) do
        pcall(function() conn:Disconnect() end)
    end
    FeatureConnections = {}

    for _, conn in pairs(PersistentConnections) do
        pcall(function() conn:Disconnect() end)
    end
    PersistentConnections = {}

    for _, conn in pairs(SliderConnections) do
        pcall(function() conn:Disconnect() end)
    end
    SliderConnections = {}

    for _, conn in pairs(UIConnections) do
        pcall(function() conn:Disconnect() end)
    end
    UIConnections = {}
end

-- ============================================================
-- HELPERS
-- ============================================================
local function Create(class, props)
    local ok, obj = pcall(Instance.new, class)
    if not ok or not obj then return nil end
    for k, v in pairs(props or {}) do
        pcall(function() obj[k] = v end)
    end
    return obj
end

local function Tween(obj, time, props)
    if not obj or not obj.Parent then return end
    local ok, t = pcall(function()
        return TweenService:Create(obj, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
    end)
    if ok and t then t:Play() return t end
end

local function GetHRP()
    local char = LocalPlayer.Character
    if char then return char:FindFirstChild("HumanoidRootPart") end
end

-- STEALTH: random delay generator
local function RandomDelay(base, variance)
    return base + (math.random() - 0.5) * variance * 2
end

-- ============================================================
-- RESPONSIVE LAYOUT
-- ============================================================
local function GetLayout()
    local camera = Workspace.CurrentCamera
    local vx, vy = 1280, 720
    if camera then
        vx, vy = camera.ViewportSize.X, camera.ViewportSize.Y
    end

    local isSmall = vx < 500
    local minWidth = math.min(240, vx - 10)
    local minHeight = math.min(220, vy - 20)

    local width = math.min(540, math.max(minWidth, vx - 20))
    local height = math.min(400, math.max(minHeight, vy - 40))

    local tabWidth = isSmall and 78 or 110
    local contentOffset = tabWidth + 12
    local contentPaddingRight = 10

    return {
        viewport = Vector2.new(vx, vy),
        isSmall = isSmall,
        width = width,
        height = height,
        tabWidth = tabWidth,
        contentOffset = contentOffset,
        contentPaddingRight = contentPaddingRight
    }
end

-- ============================================================
-- SCREEN GUI
-- ============================================================
local ScreenGui = Create("ScreenGui", {
    Name = "SGVA_BLADE_BALL",
    ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    IgnoreGuiInset = true,
    DisplayOrder = 999
})

if not ScreenGui then
    warn("[SGVA-BB] Cannot create ScreenGui.")
    return
end

local ok_parent = pcall(function() ScreenGui.Parent = UIParent end)
if not ok_parent or not ScreenGui.Parent then
    pcall(function() ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui", 5) end)
end
if not ScreenGui.Parent then
    warn("[SGVA-BB] Cannot parent ScreenGui.")
    return
end

-- ============================================================
-- HIGHLIGHT CONTAINER
-- ============================================================
local HighlightContainer = Create("Folder", {
    Name = "SGVA_BB_Highlights",
    Parent = Workspace
})

local BallHighlight = Create("Highlight", {
    Name = "SGVA_BallESP",
    FillColor = Color3.fromRGB(255, 0, 0),
    OutlineColor = Color3.fromRGB(255, 255, 255),
    FillTransparency = 0.7,
    OutlineTransparency = 0,
    Enabled = false,
    Parent = HighlightContainer
})

-- ============================================================
-- LOADING SCREEN (FAST: ~0.8 detik total)
-- ============================================================
local LoadingFrame = Create("Frame", {
    Size = UDim2.fromScale(1, 1),
    BackgroundColor3 = Color3.fromRGB(0, 0, 0),
    BackgroundTransparency = 0,
    BorderSizePixel = 0,
    ZIndex = 500,
    Parent = ScreenGui
})

local LoadingInner = Create("Frame", {
    Size = UDim2.fromOffset(360, 160),
    Position = UDim2.new(0.5, -180, 0.5, -80),
    BackgroundColor3 = Theme.Panel,
    BorderSizePixel = 0,
    ZIndex = 501,
    Parent = LoadingFrame
})
Create("UICorner", { CornerRadius = UDim.new(0, 14), Parent = LoadingInner })
Create("UIStroke", { Color = Theme.AccentGlow, Thickness = 2, Parent = LoadingInner })

Create("UIListLayout", {
    Padding = UDim.new(0, 6),
    SortOrder = Enum.SortOrder.LayoutOrder,
    HorizontalAlignment = Enum.HorizontalAlignment.Center,
    Parent = LoadingInner
})
Create("UIPadding", {
    PaddingTop = UDim.new(0, 16),
    PaddingBottom = UDim.new(0, 16),
    PaddingLeft = UDim.new(0, 16),
    PaddingRight = UDim.new(0, 16),
    Parent = LoadingInner
})

local LoadingTitle = Create("TextLabel", {
    Size = UDim2.new(1, 0, 0, 28),
    BackgroundTransparency = 1,
    Text = "SGVA HUB",
    TextColor3 = Theme.AccentGlow,
    Font = Enum.Font.GothamBold,
    TextSize = 22,
    LayoutOrder = 1,
    ZIndex = 502,
    Parent = LoadingInner
})

local LoadingSub = Create("TextLabel", {
    Size = UDim2.new(1, 0, 0, 18),
    BackgroundTransparency = 1,
    Text = "Loading...",
    TextColor3 = Theme.TextDim,
    Font = Enum.Font.Gotham,
    TextSize = 12,
    LayoutOrder = 2,
    ZIndex = 502,
    Parent = LoadingInner
})

local LoadingBarBg = Create("Frame", {
    Size = UDim2.new(1, 0, 0, 8),
    BackgroundColor3 = Theme.Background,
    BorderSizePixel = 0,
    LayoutOrder = 3,
    ZIndex = 502,
    Parent = LoadingInner
})
Create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = LoadingBarBg })

local LoadingBarFill = Create("Frame", {
    Size = UDim2.new(0, 0, 1, 0),
    BackgroundColor3 = Theme.Accent,
    BorderSizePixel = 0,
    ZIndex = 503,
    Parent = LoadingBarBg
})
Create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = LoadingBarFill })

local LoadingPercent = Create("TextLabel", {
    Size = UDim2.new(1, 0, 0, 16),
    BackgroundTransparency = 1,
    Text = "0%",
    TextColor3 = Theme.AccentGlow,
    Font = Enum.Font.GothamBold,
    TextSize = 12,
    LayoutOrder = 4,
    ZIndex = 502,
    Parent = LoadingInner
})

local function SetLoadingProgress(percent, text)
    if LoadingBarFill then
        Tween(LoadingBarFill, 0.1, { Size = UDim2.new(percent / 100, 0, 1, 0) })
    end
    if LoadingPercent then
        LoadingPercent.Text = tostring(percent) .. "%"
    end
    if text and LoadingSub then
        LoadingSub.Text = text
    end
end

local function UpdateLoadingSize()
    if not LoadingInner then return end
    local camera = Workspace.CurrentCamera
    if not camera then return end
    local vx, vy = camera.ViewportSize.X, camera.ViewportSize.Y
    local w = math.min(360, math.max(240, vx - 40))
    local h = math.min(160, math.max(160, vy - 60))
    LoadingInner.Size = UDim2.fromOffset(w, h)
    LoadingInner.Position = UDim2.new(0.5, -w / 2, 0.5, -h / 2)
end
UpdateLoadingSize()

-- ============================================================
-- NOTIFICATION QUEUE
-- ============================================================
local NotifContainer = Create("Frame", {
    Size = UDim2.fromOffset(340, 300),
    Position = UDim2.new(0.5, -170, 0, 20),
    BackgroundTransparency = 1,
    Parent = ScreenGui
})
Create("UIListLayout", {
    Padding = UDim.new(0, 6),
    SortOrder = Enum.SortOrder.LayoutOrder,
    HorizontalAlignment = Enum.HorizontalAlignment.Center,
    Parent = NotifContainer
})

local AllVisualNotifs = {}
local MaxVisualNotifs = 4
local NotifTasks = {}
local NotifRemoveTasks = {}

local function GetNotifWidth()
    local camera = Workspace.CurrentCamera
    local width = 320
    if camera then
        width = math.min(320, camera.ViewportSize.X - 20)
    end
    return width
end

local function EvictNotifInstantly(notif)
    if not notif then return end
    for i, n in ipairs(AllVisualNotifs) do
        if n == notif then
            table.remove(AllVisualNotifs, i)
            break
        end
    end
    if notif.Parent then notif:Destroy() end
end

local function FadeAndRemoveNotif(notif)
    if not notif then return end
    for i, n in ipairs(AllVisualNotifs) do
        if n == notif then
            table.remove(AllVisualNotifs, i)
            break
        end
    end
    if notif.Parent then
        Tween(notif, 0.3, { BackgroundTransparency = 1 })
        for _, v in pairs(notif:GetDescendants()) do
            if v:IsA("TextLabel") then Tween(v, 0.3, { TextTransparency = 1 }) end
            if v:IsA("Frame") then Tween(v, 0.3, { BackgroundTransparency = 1 }) end
        end
        local handle
        handle = task.delay(0.4, function()
            NotifRemoveTasks[handle] = nil
            if notif and notif.Parent then notif:Destroy() end
        end)
        NotifRemoveTasks[handle] = true
    end
end

local function Notify(title, text, duration)
    if State.Destroyed then return end
    duration = duration or 3

    while #AllVisualNotifs >= MaxVisualNotifs do
        local oldest = AllVisualNotifs[1]
        if oldest then EvictNotifInstantly(oldest) else break end
    end

    local w = GetNotifWidth()
    local notif = Create("Frame", {
        Size = UDim2.fromOffset(w, 56),
        BackgroundColor3 = Theme.Panel,
        BorderSizePixel = 0,
        Parent = NotifContainer
    })
    if not notif then return end

    Create("UICorner", { CornerRadius = UDim.new(0, 10), Parent = notif })
    Create("UIStroke", { Color = Theme.Accent, Thickness = 1.5, Parent = notif })
    Create("TextLabel", {
        Size = UDim2.new(1, -30, 0, 18),
        Position = UDim2.new(0, 16, 0, 8),
        BackgroundTransparency = 1,
        Text = title,
        TextColor3 = Theme.AccentGlow,
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = notif
    })
    Create("TextLabel", {
        Size = UDim2.new(1, -30, 0, 18),
        Position = UDim2.new(0, 16, 0, 28),
        BackgroundTransparency = 1,
        Text = text,
        TextColor3 = Theme.TextDim,
        Font = Enum.Font.Gotham,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = notif
    })

    table.insert(AllVisualNotifs, notif)

    local handle
    handle = task.delay(duration, function()
        NotifTasks[handle] = nil
        if State.Destroyed then return end
        FadeAndRemoveNotif(notif)
    end)
    NotifTasks[handle] = true
end

local function CancelAllNotifTasks()
    for handle, _ in pairs(NotifTasks) do
        pcall(function() task.cancel(handle) end)
    end
    NotifTasks = {}
    for handle, _ in pairs(NotifRemoveTasks) do
        pcall(function() task.cancel(handle) end)
    end
    NotifRemoveTasks = {}
    for _, n in ipairs(AllVisualNotifs) do
        if n and n.Parent then n:Destroy() end
    end
    AllVisualNotifs = {}
end

-- ============================================================
-- TOGGLE LOGO
-- ============================================================
local ToggleButton = Create("TextButton", {
    Size = UDim2.fromOffset(55, 55),
    Position = UDim2.fromOffset(25, 150),
    BackgroundColor3 = Theme.Accent,
    BorderSizePixel = 0,
    Text = "",
    AutoButtonColor = false,
    Visible = false,
    Parent = ScreenGui
})
Create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = ToggleButton })
Create("UIStroke", { Color = Theme.AccentGlow, Thickness = 2, Parent = ToggleButton })
Create("TextLabel", {
    Size = UDim2.new(1, 0, 1, 0),
    BackgroundTransparency = 1,
    Text = "BB",
    TextColor3 = Color3.fromRGB(255, 255, 255),
    Font = Enum.Font.GothamBold,
    TextSize = 22,
    ZIndex = 2,
    Parent = ToggleButton
})

-- ============================================================
-- MAIN FRAME
-- ============================================================
local MainFrame = Create("Frame", {
    Name = "MainFrame",
    Size = UDim2.fromOffset(540, 400),
    Position = UDim2.new(0.5, -270, 0.5, -200),
    BackgroundColor3 = Theme.Background,
    BorderSizePixel = 0,
    Visible = false,
    Parent = ScreenGui
})
Create("UICorner", { CornerRadius = UDim.new(0, 14), Parent = MainFrame })
Create("UIStroke", { Color = Theme.Accent, Thickness = 1.5, Transparency = 0.2, Parent = MainFrame })

local Header = Create("Frame", {
    Size = UDim2.new(1, 0, 0, 44),
    BackgroundColor3 = Theme.Panel,
    BorderSizePixel = 0,
    Parent = MainFrame
})
Create("UICorner", { CornerRadius = UDim.new(0, 14), Parent = Header })
Create("Frame", {
    Size = UDim2.new(1, 0, 0, 12),
    Position = UDim2.new(0, 0, 1, -12),
    BackgroundColor3 = Theme.Panel,
    BorderSizePixel = 0,
    Parent = Header
})

local TitleLabel = Create("TextLabel", {
    Size = UDim2.new(0.55, -20, 1, 0),
    Position = UDim2.new(0, 20, 0, 0),
    BackgroundTransparency = 1,
    Text = "SGVA BLADE BALL",
    TextColor3 = Theme.AccentGlow,
    Font = Enum.Font.GothamBold,
    TextSize = 15,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = Header
})

local DevLabel = Create("TextLabel", {
    Size = UDim2.new(0.35, -10, 1, 0),
    Position = UDim2.new(0.55, 0, 0, 0),
    BackgroundTransparency = 1,
    Text = "DEV: SAGA | v2",
    TextColor3 = Theme.TextDim,
    Font = Enum.Font.Gotham,
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Right,
    Parent = Header
})

local CloseBtn = Create("TextButton", {
    Size = UDim2.fromOffset(28, 28),
    Position = UDim2.new(1, -36, 0, 8),
    BackgroundColor3 = Theme.Danger,
    BackgroundTransparency = 0.3,
    BorderSizePixel = 0,
    Text = "X",
    TextColor3 = Theme.Text,
    Font = Enum.Font.GothamBold,
    TextSize = 14,
    AutoButtonColor = false,
    Parent = Header
})
Create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = CloseBtn })

local TabContainer = Create("Frame", {
    Size = UDim2.new(0, 110, 1, -58),
    Position = UDim2.new(0, 10, 0, 50),
    BackgroundColor3 = Theme.Panel,
    BorderSizePixel = 0,
    Parent = MainFrame
})
Create("UICorner", { CornerRadius = UDim.new(0, 10), Parent = TabContainer })
Create("UIListLayout", {
    Padding = UDim.new(0, 6),
    SortOrder = Enum.SortOrder.LayoutOrder,
    HorizontalAlignment = Enum.HorizontalAlignment.Center,
    Parent = TabContainer
})
Create("UIPadding", { PaddingTop = UDim.new(0, 10), Parent = TabContainer })

local ContentContainer = Create("Frame", {
    Size = UDim2.new(1, -132, 1, -60),
    Position = UDim2.new(0, 122, 0, 50),
    BackgroundColor3 = Theme.Panel,
    BorderSizePixel = 0,
    Parent = MainFrame
})
Create("UICorner", { CornerRadius = UDim.new(0, 10), Parent = ContentContainer })

local ContentScroll = Create("ScrollingFrame", {
    Size = UDim2.new(1, -6, 1, -6),
    Position = UDim2.new(0, 3, 0, 3),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 3,
    ScrollBarImageColor3 = Theme.Accent,
    CanvasSize = UDim2.new(0, 0, 0, 0),
    Parent = ContentContainer
})
Create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = ContentScroll })
Create("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6), Parent = ContentScroll })

-- ============================================================
-- POSITION HELPERS
-- ============================================================
local function ClampAbsPosition(absPos, objSize)
    local camera = Workspace.CurrentCamera
    if not camera then return absPos end
    local vx, vy = camera.ViewportSize.X, camera.ViewportSize.Y
    return Vector2.new(
        math.clamp(absPos.X, -objSize.X + 60, vx - 60),
        math.clamp(absPos.Y, 0, vy - 30)
    )
end

local function ClampMainFramePosition()
    if not MainFrame or not MainFrame.Parent then return end
    local size = MainFrame.AbsoluteSize
    if size.X == 0 or size.Y == 0 then return end
    local absPos = Vector2.new(MainFrame.AbsolutePosition.X, MainFrame.AbsolutePosition.Y)
    local clamped = ClampAbsPosition(absPos, size)
    if clamped.X ~= absPos.X or clamped.Y ~= absPos.Y then
        MainFrame.Position = UDim2.fromOffset(clamped.X, clamped.Y)
    end
end

-- ============================================================
-- RESPONSIVE UPDATE
-- ============================================================
local function UpdateLayout()
    local L = GetLayout()
    MainFrame.Size = UDim2.fromOffset(L.width, L.height)

    if not State.UserHasDraggedMain then
        MainFrame.Position = UDim2.new(0.5, -L.width / 2, 0.5, -L.height / 2)
    else
        ClampMainFramePosition()
    end

    TabContainer.Size = UDim2.new(0, L.tabWidth, 1, -58)
    ContentContainer.Position = UDim2.new(0, L.contentOffset, 0, 50)
    ContentContainer.Size = UDim2.new(1, -(L.contentOffset + L.contentPaddingRight), 1, -60)

    if L.isSmall then
        TitleLabel.Text = "SGVA BB"
        TitleLabel.Size = UDim2.new(0.6, -20, 1, 0)
        DevLabel.Visible = false
    else
        TitleLabel.Text = "SGVA BLADE BALL"
        TitleLabel.Size = UDim2.new(0.55, -20, 1, 0)
        DevLabel.Visible = true
    end

    if NotifContainer then
        local w = GetNotifWidth()
        NotifContainer.Size = UDim2.fromOffset(w, 300)
        NotifContainer.Position = UDim2.new(0.5, -w / 2, 0, 20)
    end

    UpdateLoadingSize()

    if ActivePopup and ActivePopup.Parent then
        local camera = Workspace.CurrentCamera
        if camera then
            local vx, vy = camera.ViewportSize.X, camera.ViewportSize.Y
            local pw = math.min(420, vx - 40)
            local ph = math.min(220, vy - 40)
            ActivePopup.Size = UDim2.fromOffset(pw, ph)
            ActivePopup.Position = UDim2.new(0.5, -pw / 2, 0.5, -ph / 2)
        end
    end
end

local function BindCamera()
    local cam = Workspace.CurrentCamera
    if cam then
        ConnectPersistent("Viewport", cam:GetPropertyChangedSignal("ViewportSize"), UpdateLayout)
    end
end
BindCamera()

ConnectPersistent("CameraChanged", Workspace:GetPropertyChangedSignal("CurrentCamera"), function()
    BindCamera()
    UpdateLayout()
end)

-- ============================================================
-- TAB SYSTEM
-- ============================================================
local Tabs = {}

local function CreateTab(name)
    local TabBtn = Create("TextButton", {
        Size = UDim2.new(1, -16, 0, 34),
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
        Text = name,
        TextColor3 = Theme.TextDim,
        Font = Enum.Font.Gotham,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        AutoButtonColor = false,
        Parent = TabContainer
    })
    Create("UICorner", { CornerRadius = UDim.new(0, 8), Parent = TabBtn })
    Create("UIPadding", { PaddingLeft = UDim.new(0, 10), Parent = TabBtn })

    local TabContent = Create("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Visible = false,
        Parent = ContentScroll
    })
    Create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = TabContent })

    Tabs[name] = { Button = TabBtn, Content = TabContent }

    RegisterUIConnection("Tab_" .. name, TabBtn.Activated:Connect(function()
        if State.Destroyed then return end
        for _, tab in pairs(Tabs) do
            Tween(tab.Button, 0.2, { BackgroundColor3 = Theme.Background })
            tab.Button.TextColor3 = Theme.TextDim
            tab.Content.Visible = false
        end
        Tween(TabBtn, 0.2, { BackgroundColor3 = Theme.AccentDark })
        TabBtn.TextColor3 = Theme.AccentGlow
        TabContent.Visible = true
    end))

    return TabContent
end

-- ============================================================
-- UI COMPONENTS
-- ============================================================
local function CreateSection(parent, title)
    local Section = Create("Frame", {
        Size = UDim2.new(1, 0, 0, 26),
        BackgroundColor3 = Theme.PanelAccent,
        BorderSizePixel = 0,
        Parent = parent
    })
    Create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = Section })
    Create("Frame", {
        Size = UDim2.new(0, 3, 0.6, 0),
        Position = UDim2.new(0, 8, 0.2, 0),
        BackgroundColor3 = Theme.AccentGlow,
        BorderSizePixel = 0,
        Parent = Section
    })
    Create("TextLabel", {
        Size = UDim2.new(1, -25, 1, 0),
        Position = UDim2.new(0, 18, 0, 0),
        BackgroundTransparency = 1,
        Text = title,
        TextColor3 = Theme.AccentGlow,
        Font = Enum.Font.GothamBold,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = Section
    })
end

local function CreateToggle(parent, text, default, callback)
    local Frame = Create("Frame", {
        Size = UDim2.new(1, 0, 0, 30),
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
        Parent = parent
    })
    Create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = Frame })

    Create("TextLabel", {
        Size = UDim2.new(0.72, 0, 1, 0),
        Position = UDim2.new(0, 12, 0, 0),
        BackgroundTransparency = 1,
        Text = text,
        TextColor3 = Theme.Text,
        Font = Enum.Font.Gotham,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = Frame
    })

    local ToggleBtn = Create("TextButton", {
        Size = UDim2.fromOffset(38, 18),
        Position = UDim2.new(1, -50, 0.5, -9),
        BackgroundColor3 = default and Theme.Success or Theme.Danger,
        BackgroundTransparency = default and 0 or 0.5,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        Parent = Frame
    })
    Create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = ToggleBtn })

    local Knob = Create("Frame", {
        Size = UDim2.fromOffset(14, 14),
        Position = default and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7),
        BackgroundColor3 = Theme.Text,
        BorderSizePixel = 0,
        Parent = ToggleBtn
    })
    Create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = Knob })

    local isOn = default

    RegisterUIConnection("Toggle_" .. text, ToggleBtn.Activated:Connect(function()
        if State.Destroyed then return end
        isOn = not isOn
        Tween(ToggleBtn, 0.2, { BackgroundColor3 = isOn and Theme.Success or Theme.Danger, BackgroundTransparency = isOn and 0 or 0.5 })
        Tween(Knob, 0.2, { Position = isOn and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7) })
        if callback then callback(isOn) end
    end))
end

-- STEALTH: Slider dengan debounce callback (biar tidak spam action)
local function CreateSlider(parent, text, min, max, default, callback, step)
    if not step then
        if max - min <= 1 then step = 0.01 else step = 1 end
    end

    local Frame = Create("Frame", {
        Size = UDim2.new(1, 0, 0, 42),
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
        Parent = parent
    })
    Create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = Frame })

    Create("TextLabel", {
        Size = UDim2.new(0.7, 0, 0, 18),
        Position = UDim2.new(0, 12, 0, 3),
        BackgroundTransparency = 1,
        Text = text,
        TextColor3 = Theme.Text,
        Font = Enum.Font.Gotham,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = Frame
    })

    local function formatValue(v)
        if step < 1 then return string.format("%.2f", v) else return tostring(math.floor(v)) end
    end

    local ValueLabel = Create("TextLabel", {
        Size = UDim2.new(0.3, -12, 0, 18),
        Position = UDim2.new(0.7, 0, 0, 3),
        BackgroundTransparency = 1,
        Text = formatValue(default),
        TextColor3 = Theme.AccentGlow,
        Font = Enum.Font.GothamBold,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = Frame
    })

    local BarBg = Create("Frame", {
        Size = UDim2.new(1, -24, 0, 6),
        Position = UDim2.new(0, 12, 0, 28),
        BackgroundColor3 = Theme.PanelLight,
        BorderSizePixel = 0,
        Parent = Frame
    })
    Create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = BarBg })

    local initialRel = (default - min) / (max - min)
    local BarFill = Create("Frame", {
        Size = UDim2.new(initialRel, 0, 1, 0),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0,
        Parent = BarBg
    })
    Create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = BarFill })

    local value = default
    local dragging = false
    local sliderId = "Slider_" .. tostring(math.random(1, 9999999))
    local lastCallbackTime = 0

    -- STEALTH: callback di-debounce supaya tidak spam
    local function safeCallback(v)
        local now = tick()
        if now - lastCallbackTime >= 0.15 then
            lastCallbackTime = now
            if callback then callback(v) end
        end
    end

    local function update(input)
        if State.Destroyed then return end
        local mouseX = input.Position.X
        local barPos = BarBg.AbsolutePosition.X
        local barSize = BarBg.AbsoluteSize.X
        if barSize <= 0 then return end
        local rel = math.clamp((mouseX - barPos) / barSize, 0, 1)
        local rawValue = min + (max - min) * rel
        local stepped = math.floor(rawValue / step + 0.5) * step
        value = math.clamp(stepped, min, max)
        local visualRel = (value - min) / (max - min)
        BarFill.Size = UDim2.new(visualRel, 0, 1, 0)
        ValueLabel.Text = formatValue(value)
        safeCallback(value)
    end

    RegisterUIConnection("Slider_" .. sliderId .. "_began", BarBg.InputBegan:Connect(function(input)
        if State.Destroyed then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            update(input)
        end
    end))

    RegisterSliderConnection(sliderId .. "_Changed", UserInputService.InputChanged, function(input)
        if dragging and not State.Destroyed and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            update(input)
        end
    end)
    RegisterSliderConnection(sliderId .. "_Ended", UserInputService.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
            -- Final callback saat release
            if callback then callback(value) end
        end
    end)
end

-- ============================================================
-- BALL DETECTION
-- ============================================================
local function FindBallsFolder()
    if CachedBallsFolder and CachedBallsFolder.Parent then
        return CachedBallsFolder
    end

    local direct = Workspace:FindFirstChild("Balls")
    if direct then CachedBallsFolder = direct return direct end

    local gameFolder = Workspace:FindFirstChild("Game")
    if gameFolder then
        local nested = gameFolder:FindFirstChild("Balls")
        if nested then CachedBallsFolder = nested return nested end
    end

    local function search(container, depth)
        if depth > 3 then return nil end
        for _, child in ipairs(container:GetChildren()) do
            if child.Name == "Balls" then return child end
            if child:IsA("Folder") or child:IsA("Model") then
                local found = search(child, depth + 1)
                if found then return found end
            end
        end
        return nil
    end

    local found = search(Workspace, 0)
    CachedBallsFolder = found
    return found
end

local function GetBall()
    local ballsFolder = FindBallsFolder()
    if not ballsFolder then
        State.BallDetected = false
        State.TargetConfirmed = false
        return nil
    end

    local myName = LocalPlayer.Name:lower()
    local myUserId = LocalPlayer.UserId
    local myBall = nil
    local anyBall = nil

    for _, ball in ipairs(ballsFolder:GetChildren()) do
        if ball:IsA("BasePart") and ball:GetAttribute("realBall") == true then
            if not anyBall then anyBall = ball end
            local target = ball:GetAttribute("target")
            if target then
                local targetStr = tostring(target):lower()
                local isMine = (targetStr == myName) or (tostring(target) == tostring(myUserId))
                if isMine then myBall = ball break end
            end
        end
    end

    local result = myBall or anyBall
    State.BallDetected = (result ~= nil)
    if not result then State.TargetConfirmed = false end
    return result
end

local function IsTargetingUs(ball)
    if not ball then
        State.TargetConfirmed = false
        return false
    end
    local target = ball:GetAttribute("target")
    if not target then
        State.TargetConfirmed = false
        return false
    end
    local targetStr = tostring(target):lower()
    local myName = LocalPlayer.Name:lower()
    if targetStr == myName or tostring(target) == tostring(LocalPlayer.UserId) then
        State.TargetConfirmed = true
        return true
    end
    State.TargetConfirmed = false
    return false
end

local function GetBallVelocity(ball)
    if not ball then return Vector3.zero end
    local zoomies = ball:FindFirstChild("zoomies")
    if zoomies and zoomies:IsA("BodyVelocity") then
        return zoomies.Velocity
    end
    return ball.AssemblyLinearVelocity or Vector3.zero
end

-- ============================================================
-- PARRY EXECUTION (STEALTH: RANDOMIZED)
-- ============================================================
local ParryReleaseTasks = {}

local function ReleaseFKey()
    if not FKeyHeld then return end
    FKeyHeld = false
    if VirtualInputManager then
        pcall(function()
            VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.F, false, game)
        end)
    end
end

local function ExecuteParry()
    local now = tick()
    if now - LastParryTime < 0.1 then return end
    LastParryTime = now

    if not VirtualInputManager then return end

    FKeyHeld = true
    pcall(function()
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.F, false, game)
    end)

    -- STEALTH: random release delay (0.02 - 0.05 detik)
    local releaseDelay = RandomDelay(0.035, 0.015)
    local handle
    handle = task.delay(releaseDelay, function()
        ParryReleaseTasks[handle] = nil
        if State.Destroyed then
            ReleaseFKey()
            return
        end
        ReleaseFKey()
    end)
    ParryReleaseTasks[handle] = true
end

local function CancelParryTasks()
    for handle, _ in pairs(ParryReleaseTasks) do
        pcall(function() task.cancel(handle) end)
    end
    ParryReleaseTasks = {}
    ReleaseFKey()
end

-- ============================================================
-- UNIFIED PIPELINE (STEALTH: RANDOMIZED TIMING)
-- ============================================================
local function StartAutoParryPipeline()
    if FeatureConnections["AutoParry"] then return end

    ConnectFeature("AutoParry", RunService.PreSimulation, function()
        if State.Destroyed then return end
        if not State.AutoParry and not State.AutoParryCurve then return end
        if ParryCooldown > tick() then return end

        if not VirtualInputManager then
            VirtualInputManager, VirtualUser = RefreshBackendServices()
            State.InputBackendAvailable = (VirtualInputManager ~= nil)
        end
        if not State.InputBackendAvailable then return end

        local ball = GetBall()
        if not ball then
            if LastBall then
                LastVelocities[LastBall] = nil
                LastBall = nil
            end
            return
        end
        if not IsTargetingUs(ball) then return end

        local hrp = GetHRP()
        if not hrp then return end

        local distance = (hrp.Position - ball.Position).Magnitude
        if distance > State.ParryRange then return end

        local velocity = GetBallVelocity(ball)
        local speed = velocity.Magnitude
        if speed < 1 then return end

        if LastBall and LastBall ~= ball then
            LastVelocities[LastBall] = nil
        end
        LastBall = ball

        local isCurving = false
        local lastVel = LastVelocities[ball]
        if lastVel then
            local angleDiff = (velocity.Unit - lastVel.Unit).Magnitude
            if angleDiff > 0.3 then isCurving = true end
        end
        LastVelocities[ball] = velocity

        local useCurve = State.AutoParryCurve and isCurving
        local baseTiming = State.ParryTiming
        if useCurve then baseTiming = baseTiming * 1.3 end

        -- STEALTH: tambah noise kecil di timing biar tidak terlalu perfect
        local timing = baseTiming + RandomDelay(0, 0.02)

        local timeToReach = distance / speed
        if timeToReach <= timing then
            ExecuteParry()
            -- STEALTH: random cooldown (0.4-0.6 detik)
            ParryCooldown = tick() + RandomDelay(0.5, 0.1)
        end
    end)
end

local function StopAutoParryPipeline()
    DisconnectFeature("AutoParry")
    ParryCooldown = 0
    LastParryTime = 0
    if LastBall then
        LastVelocities[LastBall] = nil
        LastBall = nil
    end
end

local function UpdateAutoParryLifecycle()
    local shouldRun = State.AutoParry or State.AutoParryCurve
    local isRunning = FeatureConnections["AutoParry"] ~= nil

    if shouldRun and not isRunning then
        StartAutoParryPipeline()
    elseif not shouldRun and isRunning then
        StopAutoParryPipeline()
    end
end

local function SetAutoParry(state)
    if State.AutoParry == state then return end
    State.AutoParry = state
    UpdateAutoParryLifecycle()
    Notify("AUTO PARRY", state and "Aktif" or "Dimatikan", 2)
end

local function SetAutoParryCurve(state)
    if State.AutoParryCurve == state then return end
    State.AutoParryCurve = state
    UpdateAutoParryLifecycle()
    Notify("PARRY CURVE", state and "Aktif" or "Dimatikan", 2)
end

-- ============================================================
-- BALL ESP
-- ============================================================
local function SetESP(state)
    if State.ShowESP == state then return end
    State.ShowESP = state

    if state then
        ConnectFeature("ESP", RunService.PreSimulation, function()
            if State.Destroyed then return end
            if not State.ShowESP then return end
            local ball = GetBall()
            if not ball then
                if BallHighlight then
                    BallHighlight.Enabled = false
                    BallHighlight.Adornee = nil
                end
                return
            end
            if BallHighlight then
                BallHighlight.Adornee = ball
                BallHighlight.Enabled = true
            end
        end)
        Notify("BALL ESP", "Aktif", 2)
    else
        DisconnectFeature("ESP")
        if BallHighlight then
            BallHighlight.Enabled = false
            BallHighlight.Adornee = nil
        end
        Notify("BALL ESP", "Dimatikan", 2)
    end
end

-- ============================================================
-- ANTI AFK (STEALTH: RANDOMIZED INTERVAL)
-- ============================================================
local AntiAFKThread = nil

local function SetAntiAFK(state)
    if State.AntiAFK == state then return end
    State.AntiAFK = state

    if state then
        if AntiAFKThread then
            pcall(function() task.cancel(AntiAFKThread) end)
            AntiAFKThread = nil
        end
        AntiAFKThread = task.spawn(function()
            while State.AntiAFK and not State.Destroyed do
                if not VirtualUser then
                    VirtualInputManager, VirtualUser = RefreshBackendServices()
                end
                pcall(function()
                    if VirtualUser then
                        VirtualUser:CaptureController()
                        VirtualUser:ClickButton2(Vector2.new())
                    end
                end)
                -- STEALTH: interval random 50-70 detik
                task.wait(RandomDelay(60, 10))
            end
            AntiAFKThread = nil
        end)
        Notify("ANTI AFK", "Aktif", 2)
    else
        if AntiAFKThread then
            pcall(function() task.cancel(AntiAFKThread) end)
            AntiAFKThread = nil
        end
        Notify("ANTI AFK", "Dimatikan", 2)
    end
end

-- ============================================================
-- STATUS LOOP
-- ============================================================
local StatusLabel = nil
local StatusThread = nil

local function StartStatusLoop()
    if StatusThread then return end
    StatusThread = task.spawn(function()
        while not State.Destroyed do
            if StatusLabel and StatusLabel.Parent then
                if not VirtualInputManager then
                    VirtualInputManager, VirtualUser = RefreshBackendServices()
                end
                State.InputBackendAvailable = (VirtualInputManager ~= nil)

                local s = "Status: "
                if not State.InputBackendAvailable then
                    s = s .. "Input backend unavailable"
                elseif not State.AutoParry and not State.AutoParryCurve then
                    s = s .. "Idle"
                elseif not State.BallDetected then
                    s = s .. "Ball not found"
                elseif not State.TargetConfirmed then
                    s = s .. "Ball targeting others"
                else
                    s = s .. "Tracking - ready to parry"
                end
                StatusLabel.Text = s
            end
            task.wait(0.5)
        end
        StatusThread = nil
    end)
end

-- ============================================================
-- BUILD UI
-- ============================================================
local ParryTab = CreateTab("PARRY")
CreateSection(ParryTab, "AUTO PARRY")
CreateToggle(ParryTab, "Auto Parry (Basic)", false, SetAutoParry)
CreateSlider(ParryTab, "Parry Range (studs)", 10, 100, 60, function(v) State.ParryRange = v end)
CreateSlider(ParryTab, "Parry Timing (s)", 0.1, 0.6, 0.32, function(v) State.ParryTiming = v end)
Create("TextLabel", {
    Size = UDim2.new(1, 0, 0, 60),
    BackgroundTransparency = 1,
    Text = "Auto Parry: Memantau bola yang menargetkan kamu. Timing 0.32 untuk ping normal, naikkan ke 0.40 kalau ping tinggi. Script akan menambahkan noise kecil supaya timing tidak terlalu perfect.",
    TextColor3 = Theme.TextDim,
    Font = Enum.Font.Gotham,
    TextSize = 10,
    TextWrapped = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = ParryTab
})

CreateSection(ParryTab, "AUTO PARRY CURVE")
CreateToggle(ParryTab, "Auto Parry Curve (Skill)", false, SetAutoParryCurve)

CreateSection(ParryTab, "STATUS")
StatusLabel = Create("TextLabel", {
    Size = UDim2.new(1, 0, 0, 40),
    BackgroundColor3 = Theme.Background,
    Text = "Status: Idle",
    TextColor3 = Theme.TextDim,
    Font = Enum.Font.Gotham,
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = ParryTab
})
Create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = StatusLabel })
Create("UIPadding", { PaddingLeft = UDim.new(0, 12), Parent = StatusLabel })

StartStatusLoop()

local VisualTab = CreateTab("VISUAL")
CreateSection(VisualTab, "BALL VISUAL")
CreateToggle(VisualTab, "Ball ESP (Highlight)", false, SetESP)

local SettingsTab = CreateTab("SETTINGS")
CreateSection(SettingsTab, "MISC")
CreateToggle(SettingsTab, "Anti AFK", false, SetAntiAFK)

-- ============================================================
-- CLEANUP
-- ============================================================
local function Cleanup()
    if State.Destroyed then return end
    State.Destroyed = true

    State.AutoParry = false
    State.AutoParryCurve = false
    State.ShowESP = false
    State.AntiAFK = false

    if AntiAFKThread then
        pcall(function() task.cancel(AntiAFKThread) end)
        AntiAFKThread = nil
    end

    if StatusThread then
        pcall(function() task.cancel(StatusThread) end)
        StatusThread = nil
    end

    CancelParryTasks()
    CancelAllNotifTasks()

    if BallHighlight then pcall(function() BallHighlight:Destroy() end) BallHighlight = nil end
    if HighlightContainer then pcall(function() HighlightContainer:Destroy() end) HighlightContainer = nil end

    LastBall = nil
    LastVelocities = {}
    CachedBallsFolder = nil
    ActivePopup = nil

    DisconnectAll()
    if ScreenGui then ScreenGui:Destroy() end
end

GlobalEnv.SGVA_BB_Cleanup = Cleanup

CreateSection(SettingsTab, "SCRIPT")
local UnloadBtn = Create("TextButton", {
    Size = UDim2.new(1, 0, 0, 32),
    BackgroundColor3 = Theme.AccentDark,
    BorderSizePixel = 0,
    Text = "Unload Script",
    TextColor3 = Theme.Text,
    Font = Enum.Font.GothamBold,
    TextSize = 12,
    AutoButtonColor = false,
    Parent = SettingsTab
})
Create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = UnloadBtn })

RegisterUIConnection("UnloadEnter", UnloadBtn.MouseEnter:Connect(function() Tween(UnloadBtn, 0.15, { BackgroundColor3 = Theme.Accent }) end))
RegisterUIConnection("UnloadLeave", UnloadBtn.MouseLeave:Connect(function() Tween(UnloadBtn, 0.15, { BackgroundColor3 = Theme.AccentDark }) end))
RegisterUIConnection("UnloadClick", UnloadBtn.Activated:Connect(Cleanup))

if Tabs["PARRY"] then
    Tabs["PARRY"].Button.BackgroundColor3 = Theme.AccentDark
    Tabs["PARRY"].Button.TextColor3 = Theme.AccentGlow
    Tabs["PARRY"].Content.Visible = true
end

-- ============================================================
-- DRAG SYSTEM
-- ============================================================
local DragState = {
    active = nil,
    startPress = Vector2.new(0, 0),
    dragOffset = Vector2.new(0, 0),
    moved = false
}

local function BeginDrag(target, input)
    DragState.active = target
    DragState.startPress = Vector2.new(input.Position.X, input.Position.Y)
    local obj = (target == "main") and MainFrame or ToggleButton
    DragState.dragOffset = Vector2.new(obj.AbsolutePosition.X, obj.AbsolutePosition.Y) - DragState.startPress
    DragState.moved = false
end

local function UpdateDrag(input)
    if not DragState.active then return end
    local mouseAbs = Vector2.new(input.Position.X, input.Position.Y)
    if (mouseAbs - DragState.startPress).Magnitude > 3 then
        DragState.moved = true
    end
    local obj = (DragState.active == "main") and MainFrame or ToggleButton
    local newAbs = mouseAbs + DragState.dragOffset
    newAbs = ClampAbsPosition(newAbs, obj.AbsoluteSize)
    obj.Position = UDim2.fromOffset(newAbs.X, newAbs.Y)
end

local function EndDrag()
    if not DragState.active then return end
    local wasActive = DragState.active
    local wasMoved = DragState.moved
    DragState.active = nil
    DragState.moved = false

    if wasActive == "main" then
        if wasMoved then State.UserHasDraggedMain = true end
    elseif wasActive == "logo" then
        if not wasMoved and not State.Destroyed then
            local isOpen = MainFrame.Visible and MainFrame.Size.X.Offset > 50
            if isOpen then
                Tween(MainFrame, 0.25, { Size = UDim2.fromOffset(0, 0) })
                task.wait(0.25)
                if State.Destroyed or not MainFrame.Parent then return end
                MainFrame.Visible = false
            else
                MainFrame.Visible = true
                MainFrame.Size = UDim2.fromOffset(0, 0)
                local L = GetLayout()
                Tween(MainFrame, 0.3, { Size = UDim2.fromOffset(L.width, L.height) })
                task.wait(0.3)
                if State.Destroyed or not MainFrame.Parent then return end
                if not State.UserHasDraggedMain then
                    MainFrame.Position = UDim2.new(0.5, -L.width / 2, 0.5, -L.height / 2)
                else
                    ClampMainFramePosition()
                end
            end
        end
    end
end

RegisterUIConnection("MainHeaderBegan", Header.InputBegan:Connect(function(input)
    if State.Destroyed then return end
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        BeginDrag("main", input)
    end
end))

RegisterUIConnection("LogoBegan", ToggleButton.InputBegan:Connect(function(input)
    if State.Destroyed then return end
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        BeginDrag("logo", input)
    end
end))

ConnectPersistent("GlobalDragChanged", UserInputService.InputChanged, function(input)
    if State.Destroyed then return end
    if DragState.active and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        UpdateDrag(input)
    end
end)

ConnectPersistent("GlobalDragEnded", UserInputService.InputEnded, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        EndDrag()
    end
end)

RegisterUIConnection("CloseClick", CloseBtn.Activated:Connect(function()
    if State.Destroyed then return end
    Tween(MainFrame, 0.25, { Size = UDim2.fromOffset(0, 0) })
    task.wait(0.25)
    if State.Destroyed or not MainFrame.Parent then return end
    MainFrame.Visible = false
end))

-- ============================================================
-- CANVAS SIZE
-- ============================================================
local ContentLayout = ContentScroll:FindFirstChildOfClass("UIListLayout")
local function UpdateCanvas()
    if ContentLayout and not State.Destroyed then
        ContentScroll.CanvasSize = UDim2.fromOffset(0, ContentLayout.AbsoluteContentSize.Y + 20)
    end
end
if ContentLayout then
    ConnectPersistent("Canvas", ContentLayout:GetPropertyChangedSignal("AbsoluteContentSize"), UpdateCanvas)
end
task.defer(UpdateCanvas)

-- ============================================================
-- THANKS POPUP
-- ============================================================
local function ShowThanksPopup()
    if State.Destroyed then return end

    local camera = Workspace.CurrentCamera
    local vx, vy = 1280, 720
    if camera then vx, vy = camera.ViewportSize.X, camera.ViewportSize.Y end
    local pw = math.min(420, vx - 40)
    local ph = math.min(220, vy - 40)

    local popup = Create("Frame", {
        Size = UDim2.fromOffset(pw, ph),
        Position = UDim2.new(0.5, -pw / 2, 0.5, -ph / 2),
        BackgroundColor3 = Theme.Panel,
        BorderSizePixel = 0,
        ZIndex = 600,
        Parent = ScreenGui
    })
    if not popup then return end
    ActivePopup = popup

    Create("UICorner", { CornerRadius = UDim.new(0, 16), Parent = popup })
    Create("UIStroke", { Color = Theme.AccentGlow, Thickness = 2, Parent = popup })

    Create("TextLabel", {
        Size = UDim2.new(1, 0, 0, 40),
        Position = UDim2.new(0, 0, 0, 20),
        BackgroundTransparency = 1,
        Text = "TERIMA KASIH",
        TextColor3 = Theme.AccentGlow,
        Font = Enum.Font.GothamBold,
        TextSize = 24,
        ZIndex = 601,
        Parent = popup
    })
    Create("TextLabel", {
        Size = UDim2.new(1, -40, 0, 30),
        Position = UDim2.new(0, 20, 0, 65),
        BackgroundTransparency = 1,
        Text = "Telah menggunakan",
        TextColor3 = Theme.Text,
        Font = Enum.Font.Gotham,
        TextSize = 14,
        ZIndex = 601,
        Parent = popup
    })
    Create("TextLabel", {
        Size = UDim2.new(1, -40, 0, 32),
        Position = UDim2.new(0, 20, 0, 92),
        BackgroundTransparency = 1,
        Text = "SGVA HUB v2",
        TextColor3 = Theme.Accent,
        Font = Enum.Font.GothamBold,
        TextSize = 20,
        ZIndex = 601,
        Parent = popup
    })
    Create("TextLabel", {
        Size = UDim2.new(1, -40, 0, 20),
        Position = UDim2.new(0, 20, 0, 124),
        BackgroundTransparency = 1,
        Text = "- Blade Ball Version -",
        TextColor3 = Theme.TextDim,
        Font = Enum.Font.Gotham,
        TextSize = 13,
        ZIndex = 601,
        Parent = popup
    })

    local okBtn = Create("TextButton", {
        Size = UDim2.fromOffset(140, 34),
        Position = UDim2.new(0.5, -70, 1, -48),
        BackgroundColor3 = Theme.AccentDark,
        BorderSizePixel = 0,
        Text = "OKE, MANTAP!",
        TextColor3 = Theme.Text,
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        AutoButtonColor = false,
        ZIndex = 601,
        Parent = popup
    })
    Create("UICorner", { CornerRadius = UDim.new(0, 8), Parent = okBtn })
    Create("UIStroke", { Color = Theme.Accent, Thickness = 1.5, Parent = okBtn })

    RegisterUIConnection("PopupOkEnter", okBtn.MouseEnter:Connect(function() Tween(okBtn, 0.15, { BackgroundColor3 = Theme.Accent }) end))
    RegisterUIConnection("PopupOkLeave", okBtn.MouseLeave:Connect(function() Tween(okBtn, 0.15, { BackgroundColor3 = Theme.AccentDark }) end))

    popup.Size = UDim2.fromOffset(0, 0)
    popup.Position = UDim2.new(0.5, 0, 0.5, 0)
    Tween(popup, 0.3, {
        Size = UDim2.fromOffset(pw, ph),
        Position = UDim2.new(0.5, -pw / 2, 0.5, -ph / 2)
    })

    RegisterUIConnection("PopupOkClick", okBtn.Activated:Connect(function()
        if State.Destroyed then return end
        Tween(popup, 0.3, { BackgroundTransparency = 1 })
        for _, v in pairs(popup:GetDescendants()) do
            if v:IsA("TextLabel") then Tween(v, 0.3, { TextTransparency = 1 }) end
            if v:IsA("Frame") or v:IsA("TextButton") then Tween(v, 0.3, { BackgroundTransparency = 1 }) end
            if v:IsA("UIStroke") then Tween(v, 0.3, { Transparency = 1 }) end
        end
        task.wait(0.4)
        if ActivePopup == popup then ActivePopup = nil end
        if popup and popup.Parent then popup:Destroy() end
    end))
end

-- ============================================================
-- LOADING SEQUENCE (FAST: ~0.8 DETIK)
-- ============================================================
local function RunLoadingSequence()
    -- STEALTH: loading cepat, 2 step saja
    local steps = {
        {50, "Init..."},
        {100, "Ready!"}
    }

    for _, step in ipairs(steps) do
        SetLoadingProgress(step[1], step[2])
        task.wait(0.15)
    end

    task.wait(0.1)
    if State.Destroyed then return end

    Tween(LoadingFrame, 0.3, { BackgroundTransparency = 1 })
    if LoadingInner then Tween(LoadingInner, 0.3, { BackgroundTransparency = 1 }) end
    if LoadingInner then
        for _, v in pairs(LoadingInner:GetDescendants()) do
            if v:IsA("TextLabel") then Tween(v, 0.3, { TextTransparency = 1 }) end
            if v:IsA("Frame") then Tween(v, 0.3, { BackgroundTransparency = 1 }) end
            if v:IsA("UIStroke") then Tween(v, 0.3, { Transparency = 1 }) end
        end
    end

    task.wait(0.35)
    if State.Destroyed then return end

    if LoadingFrame and LoadingFrame.Parent then LoadingFrame:Destroy() end

    UpdateLayout()
    if MainFrame then MainFrame.Visible = true end
    if ToggleButton then ToggleButton.Visible = true end

    -- Skip warning notif di stealth mode
    if not VirtualInputManager then
        task.wait(0.1)
        Notify("WARNING", "Input backend unavailable", 3)
    end

    task.wait(0.2)
    ShowThanksPopup()
end

task.spawn(RunLoadingSequence)

print("[SGVA-BB] SCRIPT LOADED v2")
