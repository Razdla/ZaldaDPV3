--[[
╔══════════════════════════════════════════════════════╗
║          HS HUB V2  ·  Roblox UI Library             ║
║              discord.gg/hydraSolvation               ║
╠══════════════════════════════════════════════════════╣
║  QUICK START:                                        ║
║    local W = HSHubV2:CreateWindow({                  ║
║        Title = "HS HUB", Subtitle = "Hydra Solvation"║
║    })                                                ║
║    local Tab = W:CreateTab("Home", "⌂")              ║
║    local Sec = Tab:CreateSection("General")          ║
║    Sec:AddToggle({ Name="Fly", Key="Fly",            ║
║        Default=false, Callback=function(v) end })    ║
║    Sec:AddSlider({ Name="Speed", Key="Speed",        ║
║        Min=1, Max=200, Default=16,                   ║
║        Callback=function(v) end })                   ║
║    Sec:AddDropdown({ Name="Mode", Key="Mode",        ║
║        Values={"A","B"}, Default="A",                ║
║        Callback=function(v) end })                   ║
║    Sec:AddButton({ Name="Click", Callback=fn })      ║
║    W:Notify("Loaded!", "ok", 3)                      ║
║                                                      ║
║  GLOBAL ACCESS (anywhere after CreateWindow):        ║
║    HSHubV2.Toggles.Key:Get() / :Set(true)            ║
║    HSHubV2.Options.Key:Get() / :Set(val)             ║
║                                                      ║
║  CONFIG:                                             ║
║    W:SaveConfig("Name")   W:LoadConfig("Name")       ║
║    W:BuildConfigTab()     W:BuildCreditsTab()        ║
╚══════════════════════════════════════════════════════╝
]]

-- ─── Services ──────────────────────────────────────────────────────────
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local HttpService      = game:GetService("HttpService")
local CoreGui          = game:GetService("CoreGui")

-- ─── Save folder (executor filesystem) ────────────────────────────────
local SAVE_FOLDER = "HSHubV2"
pcall(function()
    if makefolder and not isfolder(SAVE_FOLDER) then
        makefolder(SAVE_FOLDER)
    end
end)

-- ─── Theme (overrideable via SetTheme) ────────────────────────────────
local Theme = {
    BgMain    = Color3.fromRGB(24, 26, 34),
    BgPanel   = Color3.fromRGB(32, 34, 44),
    Text      = Color3.fromRGB(235, 235, 245),
    TextDim   = Color3.fromRGB(130, 130, 155),
    Border    = Color3.fromRGB(168, 95, 247),   -- purple accent
    GlowWhite = Color3.fromRGB(255, 255, 255),
}

-- ─── Helpers ───────────────────────────────────────────────────────────
local function New(Class, Props)
    local o = Instance.new(Class)
    for k, v in pairs(Props) do o[k] = v end
    return o
end

local function Corner(Parent, Radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, Radius or 8)
    c.Parent = Parent
    return c
end

local function Stroke(Parent, Color, Thickness)
    local s = Instance.new("UIStroke")
    s.Color = Color or Theme.Border
    s.Thickness = Thickness or 1
    s.Parent = Parent
    return s
end

local function getGuiParent()
    if gethui then
        local ok, h = pcall(gethui)
        if ok and h then return h end
    end
    return CoreGui
end

-- ─── Module ────────────────────────────────────────────────────────────
local HSHubV2 = {}

-- Global registries (script-wide access)
local Toggles, Options = {}, {}
HSHubV2.Toggles = Toggles
HSHubV2.Options  = Options

-- Built-in themes
HSHubV2.Themes = {
    Purple  = { Border = Color3.fromRGB(168, 95, 247) },
    Ice     = { Border = Color3.fromRGB(90, 210, 255) },
    Crimson = { Border = Color3.fromRGB(255, 80, 120) },
}

-- ─── Notification system ───────────────────────────────────────────────
local NotifyHolder, NotifyQueue

local function _initNotify(Gui)
    NotifyQueue = {}
    NotifyHolder = New("Frame", {
        Parent             = Gui,
        BackgroundTransparency = 1,
        AnchorPoint        = Vector2.new(1, 0),
        Position           = UDim2.new(1, -16, 0, 30),
        Size               = UDim2.fromOffset(300, 500),
    })
    local L = Instance.new("UIListLayout")
    L.Parent           = NotifyHolder
    L.Padding          = UDim.new(0, 8)
    L.VerticalAlignment = Enum.VerticalAlignment.Top
    L.SortOrder        = Enum.SortOrder.LayoutOrder
end

--[[
  HSHubV2:Notify(text, type, duration)
  type: "ok" | "warn" | "error" | "info"
  Max 4 visible; extras are queued automatically (FIX 8).
]]
function HSHubV2:Notify(Text, Type, Duration)
    if not NotifyHolder then return end
    Type     = Type or "info"
    Duration = Duration or 3

    local Accent = Theme.Border
    if Type == "warn" or Type == "warning" then
        Accent = Color3.fromRGB(255, 190, 80)
    elseif Type == "error" then
        Accent = Color3.fromRGB(255, 90, 90)
    elseif Type == "info" then
        Accent = Color3.fromRGB(180, 180, 180)
    end

    -- FIX 8: max 4 visible, queue the rest
    local count = 0
    for _, c in ipairs(NotifyHolder:GetChildren()) do
        if c:IsA("Frame") then count += 1 end
    end
    if count >= 4 then
        table.insert(NotifyQueue, { Text = Text, Type = Type, Duration = Duration })
        return
    end

    local Card = New("Frame", {
        Parent             = NotifyHolder,
        Size               = UDim2.fromOffset(290, 52),
        BackgroundColor3   = Theme.BgPanel,
        BorderSizePixel    = 0,
        BackgroundTransparency = 1,
    })
    Corner(Card, 10)

    local Bar = New("Frame", {
        Parent           = Card,
        Size             = UDim2.fromOffset(3, 32),
        Position         = UDim2.fromOffset(8, 10),
        BackgroundColor3 = Accent,
        BorderSizePixel  = 0,
    })
    Corner(Bar, 99)

    New("TextLabel", {
        Parent             = Card,
        BackgroundTransparency = 1,
        Position           = UDim2.fromOffset(20, 0),
        Size               = UDim2.new(1, -30, 1, 0),
        Text               = tostring(Text),
        Font               = Enum.Font.Gotham,
        TextSize           = 12,
        TextColor3         = Theme.Text,
        TextXAlignment     = Enum.TextXAlignment.Left,
        TextWrapped        = true,
    })

    TweenService:Create(Card, TweenInfo.new(0.2), { BackgroundTransparency = 0 }):Play()

    task.spawn(function()
        task.wait(Duration)
        TweenService:Create(Card, TweenInfo.new(0.2), { BackgroundTransparency = 1 }):Play()
        task.wait(0.2)
        pcall(Card.Destroy, Card)
        -- drain queue
        if NotifyQueue and #NotifyQueue > 0 then
            local nxt = table.remove(NotifyQueue, 1)
            HSHubV2:Notify(nxt.Text, nxt.Type, nxt.Duration)
        end
    end)
end

-- ─── CreateWindow ──────────────────────────────────────────────────────
--[[
  Config table:
    Title    (string)  default "HS HUB"
    Subtitle (string)  default "Hydra Solvation"
    Size     (Vector2) default {720, 460}
]]
function HSHubV2:CreateWindow(Config)
    Config = Config or {}
    local W_W = (Config.Size and Config.Size.X) or 720
    local W_H = (Config.Size and Config.Size.Y) or 460

    local Window = { Visible = true }

    -- ── GUI root ──
    local Gui = New("ScreenGui", {
        Name           = "HSHubV2_" .. math.random(1e5, 1e6 - 1),
        ResetOnSpawn   = false,
        IgnoreGuiInset = true,
        Parent         = getGuiParent(),
    })
    _initNotify(Gui)

    -- ── Main frame ──
    local Main = New("Frame", {
        Parent           = Gui,
        Size             = UDim2.fromOffset(W_W, W_H),
        Position         = UDim2.new(0.5, -W_W/2, 0.5, -W_H/2),
        BackgroundColor3 = Theme.BgMain,
        BorderSizePixel  = 0,
        ClipsDescendants = true,
    })
    Corner(Main, 14)

    local MainStroke = Stroke(Main, Theme.Border, 2)

    -- ── Title bar ──
    local TitleBar = New("Frame", {
        Parent           = Main,
        Size             = UDim2.new(1, 0, 0, 60),
        BackgroundTransparency = 1,
    })

    New("TextLabel", {
        Parent             = TitleBar,
        BackgroundTransparency = 1,
        Position           = UDim2.fromOffset(20, 10),
        Size               = UDim2.new(1, -60, 0, 28),
        Text               = Config.Title or "HS HUB",
        Font               = Enum.Font.GothamBlack,
        TextSize           = 24,
        TextColor3         = Theme.Border,
        TextXAlignment     = Enum.TextXAlignment.Left,
    })

    New("TextLabel", {
        Parent             = TitleBar,
        BackgroundTransparency = 1,
        Position           = UDim2.fromOffset(20, 38),
        Size               = UDim2.new(1, -60, 0, 16),
        Text               = Config.Subtitle or "Hydra Solvation",
        Font               = Enum.Font.Gotham,
        TextSize           = 12,
        TextColor3         = Theme.TextDim,
        TextXAlignment     = Enum.TextXAlignment.Left,
    })

    -- ── Segmented border (PART 1C) ──
    local function MakeSeg(Size, Pos)
        local s = New("Frame", {
            Parent           = Main,
            Size             = Size,
            Position         = Pos,
            BackgroundColor3 = Theme.GlowWhite,
            BorderSizePixel  = 0,
        })
        Corner(s, 99)
        local st = Stroke(s, Theme.GlowWhite, 1)
        st.Transparency = 0.3
        return s
    end
    MakeSeg(UDim2.fromOffset(90, 3),  UDim2.new(0, 24,    0, -1))   -- top-left
    MakeSeg(UDim2.fromOffset(120, 3), UDim2.new(1, -160,  0, -1))   -- top-right
    MakeSeg(UDim2.fromOffset(3, 90),  UDim2.new(0, -1,  .25, 0))    -- left-center
    MakeSeg(UDim2.fromOffset(3, 120), UDim2.new(1, -1,  .55, 0))    -- right-center
    MakeSeg(UDim2.fromOffset(140, 3), UDim2.new(.5, -70,  1, -1))   -- bottom-center

    -- ── Corner nodes (PART 1D, FIX 7: offset so they float slightly) ──
    local function MakeNode(XS, YS)
        local xo = XS == 1 and -8 or 8
        local yo = YS == 1 and -8 or 8
        local Holder = New("Frame", {
            Parent             = Main,
            BackgroundTransparency = 1,
            Size               = UDim2.fromOffset(30, 30),
            AnchorPoint        = Vector2.new(XS, YS),
            Position           = UDim2.new(XS, xo, YS, yo),
        })
        New("Frame", {
            Parent           = Holder,
            Size             = UDim2.fromOffset(20, 2),
            BackgroundColor3 = Theme.GlowWhite,
            BorderSizePixel  = 0,
        })
        New("Frame", {
            Parent           = Holder,
            Size             = UDim2.fromOffset(2, 20),
            BackgroundColor3 = Theme.GlowWhite,
            BorderSizePixel  = 0,
        })
        local Dot = New("Frame", {
            Parent           = Holder,
            Size             = UDim2.fromOffset(5, 5),
            BackgroundColor3 = Theme.Border,
            BorderSizePixel  = 0,
        })
        Corner(Dot, 99)
    end
    MakeNode(0, 0); MakeNode(1, 0); MakeNode(0, 1); MakeNode(1, 1)

    -- ── Animated spark (PART 1E) ──
    local Spark = New("TextLabel", {
        Parent             = Main,
        AnchorPoint        = Vector2.new(1, 1),
        Position           = UDim2.new(1, -12, 1, -12),
        Size               = UDim2.fromOffset(20, 20),
        BackgroundTransparency = 1,
        Text               = "✦",
        Font               = Enum.Font.GothamBold,
        TextSize           = 14,
        TextColor3         = Theme.GlowWhite,
    })
    task.spawn(function()
        while Spark.Parent do
            TweenService:Create(Spark, TweenInfo.new(2, Enum.EasingStyle.Sine),
                { Rotation = 180, TextTransparency = 0.4 }):Play()
            task.wait(2)
            TweenService:Create(Spark, TweenInfo.new(2, Enum.EasingStyle.Sine),
                { Rotation = 360, TextTransparency = 0 }):Play()
            task.wait(2)
        end
    end)

    -- ── Close button (PART 1F) ──
    local Close = New("TextButton", {
        Parent             = TitleBar,
        AnchorPoint        = Vector2.new(1, 0),
        Position           = UDim2.new(1, -14, 0, 14),
        Size               = UDim2.fromOffset(28, 28),
        BackgroundTransparency = 1,
        Text               = "✕",
        Font               = Enum.Font.GothamBold,
        TextSize           = 15,
        TextColor3         = Theme.TextDim,
    })
    Close.MouseEnter:Connect(function()
        TweenService:Create(Close, TweenInfo.new(0.15), { TextColor3 = Theme.GlowWhite }):Play()
    end)
    Close.MouseLeave:Connect(function()
        TweenService:Create(Close, TweenInfo.new(0.15), { TextColor3 = Theme.TextDim }):Play()
    end)

    -- ── Show / Hide / Toggle (PART 1G) ──
    function Window:Show()
        Main.Visible = true
        Main.Size = UDim2.fromOffset(W_W, 0)
        TweenService:Create(Main, TweenInfo.new(0.25, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
            { Size = UDim2.fromOffset(W_W, W_H) }):Play()
        Window.Visible = true
    end

    function Window:Hide()
        local t = TweenService:Create(Main, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { Size = UDim2.fromOffset(W_W, 0) })
        t:Play()
        Window.Visible = false
        t.Completed:Connect(function()
            if not Window.Visible then Main.Visible = false end
        end)
    end

    function Window:Toggle()
        if Window.Visible then Window:Hide() else Window:Show() end
    end

    -- ── Dragging (PART 1H, FIX 4: mobile throttle) ──
    local Dragging, DragStart, StartPos = false, nil, nil
    local LastDragUpdate = 0

    TitleBar.InputBegan:Connect(function(Input)
        if Input.UserInputType ~= Enum.UserInputType.MouseButton1
        and Input.UserInputType ~= Enum.UserInputType.Touch then return end
        Dragging  = true
        DragStart = Input.Position
        StartPos  = Main.Position
        Input.Changed:Connect(function()
            if Input.UserInputState == Enum.UserInputState.End then
                Dragging = false
            end
        end)
    end)

    UserInputService.InputChanged:Connect(function(Input)
        if not Dragging then return end
        if Input.UserInputType ~= Enum.UserInputType.MouseMovement
        and Input.UserInputType ~= Enum.UserInputType.Touch then return end
        -- FIX 4: throttle on low-end mobile
        local now = tick()
        if now - LastDragUpdate < 0.01 then return end
        LastDragUpdate = now
        local D = Input.Position - DragStart
        Main.Position = UDim2.new(
            StartPos.X.Scale, StartPos.X.Offset + D.X,
            StartPos.Y.Scale, StartPos.Y.Offset + D.Y
        )
    end)

    -- ── Floating HS button (PART 1I / 1J) ──
    local Float = New("TextButton", {
        Parent           = Gui,
        Size             = UDim2.fromOffset(52, 52),
        Position         = UDim2.new(0, 16, 0.5, -26),
        BackgroundColor3 = Theme.BgPanel,
        BorderSizePixel  = 0,
        Text             = "HS",
        Font             = Enum.Font.GothamBlack,
        TextSize         = 17,
        TextColor3       = Theme.Text,
        Visible          = false,
    })
    Corner(Float, 12)
    Stroke(Float, Theme.Border, 2)

    Close.MouseButton1Click:Connect(function()
        Main.Visible = false
        Float.Visible = true
        Window.Visible = false
    end)
    Float.MouseButton1Click:Connect(function()
        Main.Visible = true
        Float.Visible = false
        Window.Visible = true
    end)

    -- ── Border pulse (PART 1K) ──
    task.spawn(function()
        while Main.Parent do
            TweenService:Create(MainStroke, TweenInfo.new(2, Enum.EasingStyle.Sine),
                { Color = Color3.fromRGB(220, 220, 255) }):Play()
            task.wait(2)
            TweenService:Create(MainStroke, TweenInfo.new(2, Enum.EasingStyle.Sine),
                { Color = Theme.Border }):Play()
            task.wait(2)
        end
    end)

    -- ── Sidebar (PART 2A) ──
    local Sidebar = New("Frame", {
        Parent           = Main,
        BackgroundColor3 = Theme.BgPanel,
        BorderSizePixel  = 0,
        Position         = UDim2.fromOffset(0, 60),
        Size             = UDim2.new(0, 180, 1, -70),
    })
    Corner(Sidebar, 12)
    local SidebarStroke = Stroke(Sidebar, Theme.Border, 1)
    SidebarStroke.Transparency = 0.6

    -- Divider under the sidebar header (PART 2B)
    local SBDivider = New("Frame", {
        Parent             = Sidebar,
        BorderSizePixel    = 0,
        BackgroundColor3   = Theme.Border,
        Size               = UDim2.new(1, -28, 0, 1),
        Position           = UDim2.fromOffset(14, 62),
    })
    SBDivider.BackgroundTransparency = 0.65

    -- Tab list container (PART 2C)
    local TabHolder = New("Frame", {
        Parent             = Sidebar,
        BackgroundTransparency = 1,
        Position           = UDim2.fromOffset(0, 75),
        Size               = UDim2.new(1, 0, 1, -120),
    })
    local TabLayout = Instance.new("UIListLayout")
    TabLayout.Parent    = TabHolder
    TabLayout.Padding   = UDim.new(0, 4)
    TabLayout.SortOrder = Enum.SortOrder.LayoutOrder

    -- Content area (PART 2D)
    local Content = New("Frame", {
        Parent             = Main,
        BackgroundTransparency = 1,
        Position           = UDim2.fromOffset(190, 60),
        Size               = UDim2.new(1, -200, 1, -70),
    })
    Window.Content = Content

    -- ── State ──
    Window.Tabs       = {}
    Window.ActiveTab  = nil
    Window.Registry   = { Toggles = {}, Sliders = {}, Dropdowns = {}, Buttons = {} }
    Window.ThemeObjects = { MainStroke, SidebarStroke }

    -- ── SwitchTab (PART 2I, FIX 5: indicator animate) ──
    local function SwitchTab(Target)
        if Window.ActiveTab == Target then return end
        for _, T in pairs(Window.Tabs) do
            T.Page.Visible = false
            T.Indicator.Visible = false
            TweenService:Create(T.Label, TweenInfo.new(0.15),
                { TextColor3 = Theme.TextDim }):Play()
        end
        Target.Page.Visible = true
        Target.Page.CanvasPosition = Vector2.new()
        -- FIX 5: animate indicator grow
        Target.Indicator.Size    = UDim2.fromOffset(3, 0)
        Target.Indicator.Visible = true
        TweenService:Create(Target.Indicator, TweenInfo.new(0.15),
            { Size = UDim2.fromOffset(3, 22) }):Play()
        TweenService:Create(Target.Label, TweenInfo.new(0.15),
            { TextColor3 = Theme.Text }):Play()
        Window.ActiveTab = Target
    end

    -- ── CreateTab (PART 2F–2N) ──
    function Window:CreateTab(Name, Icon)
        local Tab = {}
        Icon = Icon or "•"

        local Button = New("TextButton", {
            Parent             = TabHolder,
            Size               = UDim2.new(1, -10, 0, 38),
            BackgroundTransparency = 1,
            Text               = "",
        })

        -- Active indicator bar
        local Indicator = New("Frame", {
            Parent           = Button,
            Size             = UDim2.fromOffset(3, 0),
            Position         = UDim2.new(0, 0, 0.5, -11),
            BackgroundColor3 = Theme.Border,
            BorderSizePixel  = 0,
            Visible          = false,
        })
        Corner(Indicator, 99)
        table.insert(Window.ThemeObjects, Stroke(Indicator, Theme.Border, 0))

        -- Tab label
        local Label = New("TextLabel", {
            Parent             = Button,
            BackgroundTransparency = 1,
            Position           = UDim2.fromOffset(14, 0),
            Size               = UDim2.new(1, -14, 1, 0),
            Text               = string.format("%s  %s", Icon, string.upper(Name)),
            Font               = Enum.Font.GothamBold,
            TextSize           = 13,
            TextColor3         = Theme.TextDim,
            TextXAlignment     = Enum.TextXAlignment.Left,
        })

        -- Tab page (scrollable)
        local Page = New("ScrollingFrame", {
            Parent             = Content,
            Visible            = false,
            BackgroundTransparency = 1,
            BorderSizePixel    = 0,
            ScrollBarThickness = 3,
            ScrollBarImageColor3 = Theme.Border,
            Size               = UDim2.new(1, 0, 1, 0),
            CanvasSize         = UDim2.new(),
        })
        local PageLayout = Instance.new("UIListLayout")
        PageLayout.Parent  = Page
        PageLayout.Padding = UDim.new(0, 8)
        local PagePad = Instance.new("UIPadding")
        PagePad.PaddingTop = UDim.new(0, 4)
        PagePad.Parent = Page

        -- FIX 1: auto canvas size so scrolling always works
        local function UpdateCanvas()
            Page.CanvasSize = UDim2.new(0, 0, 0, PageLayout.AbsoluteContentSize.Y + 15)
        end
        PageLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(UpdateCanvas)
        UpdateCanvas()

        -- Hover (PART 2J)
        Button.MouseEnter:Connect(function()
            if Window.ActiveTab == Tab then return end
            TweenService:Create(Label, TweenInfo.new(0.12),
                { TextColor3 = Color3.fromRGB(190, 190, 205) }):Play()
        end)
        Button.MouseLeave:Connect(function()
            if Window.ActiveTab == Tab then return end
            TweenService:Create(Label, TweenInfo.new(0.12),
                { TextColor3 = Theme.TextDim }):Play()
        end)
        Button.MouseButton1Click:Connect(function() SwitchTab(Tab) end)

        Tab.Button    = Button
        Tab.Label     = Label
        Tab.Page      = Page
        Tab.Indicator = Indicator
        Window.Tabs[Name] = Tab

        -- Auto-activate first tab (PART 2M)
        if not Window.ActiveTab then
            task.defer(function() SwitchTab(Tab) end)
        end

        -- ── Hero card  (PART 11A / 11B) ──────────────────────────────
        --[[
          Tab:AddHero({ Title="HS HUB", Subtitle="Hydra Solvation",
              Stats = { Executor="Delta", Version="V2", Platform="Mobile" } })
        ]]
        function Tab:AddHero(Data)
            Data = Data or {}
            local Stats = Data.Stats or {}
            local rowH  = 18
            local totalH = 78 + (#(function() local t={} for _ in pairs(Stats) do t[#t+1]=1 end return t end)()) * rowH + 10

            local Hero = New("Frame", {
                Parent           = Page,
                BackgroundColor3 = Theme.BgPanel,
                BorderSizePixel  = 0,
                Size             = UDim2.new(1, -10, 0, math.max(140, totalH)),
            })
            Corner(Hero, 14)
            local hs = Stroke(Hero, Theme.Border, 1)
            hs.Transparency = 0.5
            table.insert(Window.ThemeObjects, hs)

            New("TextLabel", {
                Parent             = Hero,
                BackgroundTransparency = 1,
                Position           = UDim2.fromOffset(18, 14),
                Size               = UDim2.new(1, -30, 0, 24),
                Text               = Data.Title or "HS HUB",
                Font               = Enum.Font.GothamBlack,
                TextSize           = 22,
                TextColor3         = Theme.Text,
                TextXAlignment     = Enum.TextXAlignment.Left,
            })
            New("TextLabel", {
                Parent             = Hero,
                BackgroundTransparency = 1,
                Position           = UDim2.fromOffset(18, 40),
                Size               = UDim2.new(1, -30, 0, 16),
                Text               = Data.Subtitle or "Hydra Solvation",
                Font               = Enum.Font.Gotham,
                TextSize           = 12,
                TextColor3         = Theme.TextDim,
                TextXAlignment     = Enum.TextXAlignment.Left,
            })
            local Div = New("Frame", {
                Parent             = Hero,
                BorderSizePixel    = 0,
                BackgroundColor3   = Theme.Border,
                Position           = UDim2.fromOffset(18, 66),
                Size               = UDim2.new(1, -36, 0, 1),
            })
            Div.BackgroundTransparency = 0.7

            local Y = 78
            for N, V in pairs(Stats) do
                New("TextLabel", {
                    Parent             = Hero,
                    BackgroundTransparency = 1,
                    Position           = UDim2.fromOffset(18, Y),
                    Size               = UDim2.new(0.4, 0, 0, 18),
                    Text               = tostring(N),
                    Font               = Enum.Font.Gotham,
                    TextSize           = 12,
                    TextColor3         = Theme.TextDim,
                    TextXAlignment     = Enum.TextXAlignment.Left,
                })
                New("TextLabel", {
                    Parent             = Hero,
                    BackgroundTransparency = 1,
                    Position           = UDim2.new(0.45, 0, 0, Y),
                    Size               = UDim2.new(0.5, 0, 0, 18),
                    Text               = tostring(V),
                    Font               = Enum.Font.GothamBold,
                    TextSize           = 12,
                    TextColor3         = Theme.Border,
                    TextXAlignment     = Enum.TextXAlignment.Right,
                })
                Y += rowH
            end
            return Hero
        end

        -- ── Status card (PART 11C) ─────────────────────────────────
        --[[
          local SC = Tab:AddStatusCard({ Name="AUTOFARM" })
          SC:Set("RUNNING")   SC:Set("IDLE")   SC:Set("ERROR")
        ]]
        function Tab:AddStatusCard(Cfg)
            Cfg = Cfg or {}
            local Card = New("Frame", {
                Parent           = Page,
                BackgroundColor3 = Theme.BgPanel,
                BorderSizePixel  = 0,
                Size             = UDim2.new(1, -10, 0, 80),
            })
            Corner(Card, 12)

            if Cfg.Name then
                New("TextLabel", {
                    Parent             = Card,
                    BackgroundTransparency = 1,
                    Position           = UDim2.fromOffset(14, 10),
                    Size               = UDim2.new(1, -20, 0, 16),
                    Text               = string.upper(tostring(Cfg.Name)),
                    Font               = Enum.Font.GothamBold,
                    TextSize           = 12,
                    TextColor3         = Theme.TextDim,
                    TextXAlignment     = Enum.TextXAlignment.Left,
                })
            end

            local StatusLbl = New("TextLabel", {
                Parent             = Card,
                AnchorPoint        = Vector2.new(0.5, 0.5),
                Position           = UDim2.new(0.5, 0, 0.65, 0),
                Size               = UDim2.new(1, 0, 0, 24),
                Text               = "IDLE",
                Font               = Enum.Font.GothamBlack,
                TextSize           = 17,
                TextColor3         = Theme.TextDim,
            })

            local API = {}
            function API:Set(State)
                StatusLbl.Text = string.upper(tostring(State))
                if State == "RUNNING" then
                    StatusLbl.TextColor3 = Theme.Border
                elseif State == "ERROR" then
                    StatusLbl.TextColor3 = Color3.fromRGB(255, 100, 100)
                else
                    StatusLbl.TextColor3 = Theme.TextDim
                end
            end
            return API
        end

        -- ── CreateSection (PART 3A–3F) ─────────────────────────────
        function Tab:CreateSection(Title)
            local Section = {}

            local Card = New("Frame", {
                Parent           = Page,
                BackgroundColor3 = Theme.BgPanel,
                BorderSizePixel  = 0,
                Size             = UDim2.new(1, -10, 0, 60),
            })
            Corner(Card, 12)
            local CardStroke = Stroke(Card, Theme.Border, 1)
            CardStroke.Transparency = 0.75
            table.insert(Window.ThemeObjects, CardStroke)

            New("TextLabel", {
                Parent             = Card,
                BackgroundTransparency = 1,
                Position           = UDim2.fromOffset(14, 10),
                Size               = UDim2.new(1, -20, 0, 18),
                Text               = string.upper(tostring(Title or "Section")),
                Font               = Enum.Font.GothamBold,
                TextSize           = 12,
                TextColor3         = Theme.Text,
                TextXAlignment     = Enum.TextXAlignment.Left,
            })

            local SecDiv = New("Frame", {
                Parent             = Card,
                BorderSizePixel    = 0,
                BackgroundColor3   = Theme.Border,
                Position           = UDim2.fromOffset(14, 32),
                Size               = UDim2.new(1, -28, 0, 1),
            })
            SecDiv.BackgroundTransparency = 0.75

            local Holder = New("Frame", {
                Parent             = Card,
                BackgroundTransparency = 1,
                Position           = UDim2.fromOffset(0, 42),
                Size               = UDim2.new(1, 0, 0, 10),
            })
            local HLayout = Instance.new("UIListLayout")
            HLayout.Parent  = Holder
            HLayout.Padding = UDim.new(0, 5)
            local HPad = Instance.new("UIPadding")
            HPad.PaddingLeft   = UDim.new(0, 14)
            HPad.PaddingRight  = UDim.new(0, 14)
            HPad.PaddingBottom = UDim.new(0, 6)
            HPad.Parent = Holder

            local function UpdateCardHeight()
                Card.Size = UDim2.new(1, -10, 0, HLayout.AbsoluteContentSize.Y + 52)
            end
            HLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(UpdateCardHeight)
            UpdateCardHeight()

            Section.Card   = Card
            Section.Holder = Holder

            -- ── AddToggle ──────────────────────────────────────────
            --[[
              Sec:AddToggle({ Name="", Key="", Default=false, Callback=fn })
              API: :Get() :Set(bool)
            ]]
            function Section:AddToggle(Cfg)
                Cfg = Cfg or {}
                local Toggle = { Value = Cfg.Default == true }

                local Row = New("Frame", {
                    Parent             = Holder,
                    Size               = UDim2.new(1, 0, 0, 32),
                    BackgroundTransparency = 1,
                })
                New("TextLabel", {
                    Parent             = Row,
                    BackgroundTransparency = 1,
                    Size               = UDim2.new(1, -56, 1, 0),
                    Text               = Cfg.Name or "Toggle",
                    Font               = Enum.Font.Gotham,
                    TextSize           = 13,
                    TextColor3         = Theme.Text,
                    TextXAlignment     = Enum.TextXAlignment.Left,
                })

                local Track = New("Frame", {
                    Parent           = Row,
                    AnchorPoint      = Vector2.new(1, 0.5),
                    Position         = UDim2.new(1, 0, 0.5, 0),
                    Size             = UDim2.fromOffset(44, 22),
                    BackgroundColor3 = Toggle.Value and Theme.Border or Color3.fromRGB(55, 57, 68),
                    BorderSizePixel  = 0,
                })
                Corner(Track, 99)
                local Knob = New("Frame", {
                    Parent           = Track,
                    AnchorPoint      = Vector2.new(0, 0.5),
                    Position         = Toggle.Value and UDim2.new(1, -20, 0.5, 0) or UDim2.new(0, 2, 0.5, 0),
                    Size             = UDim2.fromOffset(18, 18),
                    BackgroundColor3 = Color3.fromRGB(255, 255, 255),
                    BorderSizePixel  = 0,
                })
                Corner(Knob, 99)

                local Btn = New("TextButton", {
                    Parent             = Row,
                    AnchorPoint        = Vector2.new(1, 0.5),
                    Position           = UDim2.new(1, 0, 0.5, 0),
                    Size               = UDim2.fromOffset(44, 22),
                    BackgroundTransparency = 1,
                    Text               = "",
                })

                local function UpdateToggleVisual()
                    TweenService:Create(Track, TweenInfo.new(0.15), {
                        BackgroundColor3 = Toggle.Value and Theme.Border or Color3.fromRGB(55, 57, 68),
                    }):Play()
                    TweenService:Create(Knob, TweenInfo.new(0.15), {
                        Position = Toggle.Value
                            and UDim2.new(1, -20, 0.5, 0)
                            or  UDim2.new(0, 2,   0.5, 0),
                    }):Play()
                end

                function Toggle:Set(v)
                    Toggle.Value = v == true
                    UpdateToggleVisual()
                    if Cfg.Callback then
                        task.spawn(function() pcall(Cfg.Callback, Toggle.Value) end)
                    end
                end
                function Toggle:Get() return Toggle.Value end

                Btn.MouseButton1Click:Connect(function()
                    Toggle:Set(not Toggle.Value)
                end)

                if Cfg.Key then
                    Toggles[Cfg.Key]                       = Toggle
                    Options[Cfg.Key]                       = Toggle
                    Window.Registry.Toggles[Cfg.Key]       = Toggle
                end
                return Toggle
            end

            -- ── AddButton ──────────────────────────────────────────
            function Section:AddButton(Cfg)
                Cfg = Cfg or {}
                local Btn = New("TextButton", {
                    Parent           = Holder,
                    Size             = UDim2.new(1, 0, 0, 32),
                    BackgroundColor3 = Theme.BgMain,
                    BorderSizePixel  = 0,
                    Text             = Cfg.Name or "Button",
                    Font             = Enum.Font.GothamBold,
                    TextSize         = 13,
                    TextColor3       = Theme.Text,
                })
                Corner(Btn, 8)
                local BS = Stroke(Btn, Theme.Border, 1)
                BS.Transparency = 0.55
                table.insert(Window.ThemeObjects, BS)
                -- FIX 6: hover glow
                Btn.MouseEnter:Connect(function()
                    TweenService:Create(BS, TweenInfo.new(0.12), { Transparency = 0 }):Play()
                end)
                Btn.MouseLeave:Connect(function()
                    TweenService:Create(BS, TweenInfo.new(0.12), { Transparency = 0.55 }):Play()
                end)
                Btn.MouseButton1Click:Connect(function()
                    if Cfg.Callback then
                        task.spawn(function() pcall(Cfg.Callback) end)
                    end
                end)
                return Btn
            end

            -- ── AddSlider ──────────────────────────────────────────
            --[[
              Sec:AddSlider({ Name="", Key="", Min=0, Max=100, Default=50,
                  Suffix="%", Callback=fn })
              API: :Get() :Set(number)
            ]]
            function Section:AddSlider(Cfg)
                Cfg = Cfg or {}
                local Slider  = {}
                local Min     = Cfg.Min or 0
                local Max     = Cfg.Max or 100
                local Suffix  = Cfg.Suffix or ""
                Slider.Value  = math.clamp(Cfg.Default or Min, Min, Max)

                local Row = New("Frame", {
                    Parent             = Holder,
                    Size               = UDim2.new(1, 0, 0, 46),
                    BackgroundTransparency = 1,
                })
                New("TextLabel", {
                    Parent             = Row,
                    BackgroundTransparency = 1,
                    Size               = UDim2.new(1, -64, 0, 20),
                    Text               = Cfg.Name or "Slider",
                    Font               = Enum.Font.Gotham,
                    TextSize           = 13,
                    TextColor3         = Theme.Text,
                    TextXAlignment     = Enum.TextXAlignment.Left,
                })
                local ValLbl = New("TextLabel", {
                    Parent             = Row,
                    AnchorPoint        = Vector2.new(1, 0),
                    BackgroundTransparency = 1,
                    Position           = UDim2.new(1, 0, 0, 0),
                    Size               = UDim2.fromOffset(60, 20),
                    Text               = tostring(Slider.Value) .. Suffix,
                    Font               = Enum.Font.GothamBold,
                    TextSize           = 13,
                    TextColor3         = Theme.Border,
                    TextXAlignment     = Enum.TextXAlignment.Right,
                })
                local Track = New("Frame", {
                    Parent           = Row,
                    Position         = UDim2.fromOffset(0, 28),
                    Size             = UDim2.new(1, 0, 0, 6),
                    BackgroundColor3 = Color3.fromRGB(48, 50, 62),
                    BorderSizePixel  = 0,
                })
                Corner(Track, 99)
                local Alpha0 = (Slider.Value - Min) / math.max(Max - Min, 1)
                local Fill = New("Frame", {
                    Parent           = Track,
                    Size             = UDim2.new(Alpha0, 0, 1, 0),
                    BackgroundColor3 = Theme.Border,
                    BorderSizePixel  = 0,
                })
                Corner(Fill, 99)
                local SKnob = New("Frame", {
                    Parent           = Track,
                    AnchorPoint      = Vector2.new(0.5, 0.5),
                    Position         = UDim2.new(Alpha0, 0, 0.5, 0),
                    Size             = UDim2.fromOffset(14, 14),
                    BackgroundColor3 = Color3.fromRGB(255, 255, 255),
                    BorderSizePixel  = 0,
                })
                Corner(SKnob, 99)

                local function SetSlider(v)
                    v = math.clamp(math.round(v), Min, Max)
                    Slider.Value = v
                    local a = (v - Min) / math.max(Max - Min, 1)
                    Fill.Size         = UDim2.new(a, 0, 1, 0)
                    SKnob.Position    = UDim2.new(a, 0, 0.5, 0)
                    ValLbl.Text       = tostring(v) .. Suffix
                    if Cfg.Callback then
                        task.spawn(function() pcall(Cfg.Callback, v) end)
                    end
                end

                function Slider:Set(v) SetSlider(v) end
                function Slider:Get() return Slider.Value end

                -- Drag input
                local SDragging = false
                local DragBtn = New("TextButton", {
                    Parent             = Track,
                    Size               = UDim2.new(1, 0, 0, 20),
                    Position           = UDim2.fromOffset(0, -7),
                    BackgroundTransparency = 1,
                    Text               = "",
                })
                DragBtn.InputBegan:Connect(function(I)
                    if I.UserInputType == Enum.UserInputType.MouseButton1
                    or I.UserInputType == Enum.UserInputType.Touch then
                        SDragging = true
                    end
                end)
                DragBtn.InputEnded:Connect(function(I)
                    if I.UserInputType == Enum.UserInputType.MouseButton1
                    or I.UserInputType == Enum.UserInputType.Touch then
                        SDragging = false
                    end
                end)
                UserInputService.InputChanged:Connect(function(I)
                    if not SDragging then return end
                    if I.UserInputType ~= Enum.UserInputType.MouseMovement
                    and I.UserInputType ~= Enum.UserInputType.Touch then return end
                    local abs  = Track.AbsolutePosition
                    local size = Track.AbsoluteSize
                    local a    = math.clamp((I.Position.X - abs.X) / size.X, 0, 1)
                    SetSlider(Min + (Max - Min) * a)
                end)

                if Cfg.Key then
                    Window.Registry.Sliders[Cfg.Key] = Slider
                    Options[Cfg.Key]                 = Slider
                end
                return Slider
            end

            -- ── AddDropdown (PART 5A, FIX 2: auto ListHolder sizing) ──
            --[[
              Sec:AddDropdown({ Name="", Key="", Values={}, Default="", Callback=fn })
              API: :Get() :Set(value)
            ]]
            function Section:AddDropdown(Cfg)
                Cfg = Cfg or {}
                local Dropdown     = {}
                Dropdown.Values    = Cfg.Values or {}
                Dropdown.Value     = Cfg.Default or Dropdown.Values[1] or ""

                local Card = New("Frame", {
                    Parent           = Holder,
                    BackgroundColor3 = Theme.BgMain,
                    BorderSizePixel  = 0,
                    Size             = UDim2.new(1, 0, 0, 38),
                })
                Corner(Card, 10)
                local DS = Stroke(Card, Theme.Border, 1)
                DS.Transparency = 0.5
                table.insert(Window.ThemeObjects, DS)

                New("TextLabel", {
                    Parent             = Card,
                    BackgroundTransparency = 1,
                    Position           = UDim2.fromOffset(10, 0),
                    Size               = UDim2.new(0.5, 0, 1, 0),
                    Text               = Cfg.Name or "Dropdown",
                    Font               = Enum.Font.Gotham,
                    TextSize           = 13,
                    TextColor3         = Theme.Text,
                    TextXAlignment     = Enum.TextXAlignment.Left,
                })

                local Current = New("TextButton", {
                    Parent             = Card,
                    AnchorPoint        = Vector2.new(1, 0.5),
                    Position           = UDim2.new(1, -8, 0.5, 0),
                    Size               = UDim2.fromOffset(120, 24),
                    BackgroundTransparency = 1,
                    Text               = tostring(Dropdown.Value),
                    Font               = Enum.Font.GothamBold,
                    TextSize           = 12,
                    TextColor3         = Theme.Border,
                })

                local ListHolder = New("Frame", {
                    Parent             = Card,
                    Visible            = false,
                    BackgroundTransparency = 1,
                    Position           = UDim2.fromOffset(0, 40),
                    Size               = UDim2.new(1, 0, 0, 0),
                })
                local ListLayout = Instance.new("UIListLayout")
                ListLayout.Parent  = ListHolder
                ListLayout.Padding = UDim.new(0, 4)
                local LPad = Instance.new("UIPadding")
                LPad.PaddingLeft   = UDim.new(0, 6)
                LPad.PaddingRight  = UDim.new(0, 6)
                LPad.PaddingBottom = UDim.new(0, 6)
                LPad.Parent = ListHolder

                -- FIX 2: ListHolder auto-sizes so Section card pushes correctly
                ListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
                    ListHolder.Size = UDim2.new(1, 0, 0, ListLayout.AbsoluteContentSize.Y + 10)
                end)

                local Expanded = false
                local function SetExpanded(State)
                    Expanded          = State
                    ListHolder.Visible = State
                    local tH = State and (40 + ListLayout.AbsoluteContentSize.Y + 14) or 38
                    TweenService:Create(Card, TweenInfo.new(0.15),
                        { Size = UDim2.new(1, 0, 0, tH) }):Play()
                end

                Current.MouseButton1Click:Connect(function()
                    SetExpanded(not Expanded)
                end)

                -- Build option buttons
                for _, V in ipairs(Dropdown.Values) do
                    local Opt = New("TextButton", {
                        Parent           = ListHolder,
                        Size             = UDim2.new(1, 0, 0, 26),
                        BackgroundColor3 = Theme.BgPanel,
                        BorderSizePixel  = 0,
                        Text             = tostring(V),
                        Font             = Enum.Font.Gotham,
                        TextSize         = 12,
                        TextColor3       = Theme.Text,
                    })
                    Corner(Opt, 7)
                    Opt.MouseButton1Click:Connect(function()
                        Dropdown.Value = V
                        Current.Text   = tostring(V)
                        SetExpanded(false)
                        if Cfg.Callback then
                            task.spawn(function() pcall(Cfg.Callback, V) end)
                        end
                    end)
                end

                function Dropdown:Set(V)
                    Dropdown.Value = V
                    Current.Text   = tostring(V)
                end
                function Dropdown:Get() return Dropdown.Value end

                if Cfg.Key then
                    Window.Registry.Dropdowns[Cfg.Key] = Dropdown
                    Options[Cfg.Key]                   = Dropdown
                end
                return Dropdown
            end

            -- ── AddTextbox (PART 8F) ────────────────────────────────
            function Section:AddTextbox(Cfg)
                Cfg = Cfg or {}
                local Box = {}
                local Row = New("Frame", {
                    Parent             = Holder,
                    Size               = UDim2.new(1, 0, 0, 36),
                    BackgroundTransparency = 1,
                })
                New("TextLabel", {
                    Parent             = Row,
                    BackgroundTransparency = 1,
                    Size               = UDim2.new(0.45, 0, 1, 0),
                    Text               = Cfg.Name or "Textbox",
                    Font               = Enum.Font.Gotham,
                    TextSize           = 13,
                    TextColor3         = Theme.Text,
                    TextXAlignment     = Enum.TextXAlignment.Left,
                })
                local Input = New("TextBox", {
                    Parent             = Row,
                    AnchorPoint        = Vector2.new(1, 0.5),
                    Position           = UDim2.new(1, 0, 0.5, 0),
                    Size               = UDim2.fromOffset(150, 26),
                    Text               = Cfg.Default or "",
                    PlaceholderText    = Cfg.Placeholder or "",
                    Font               = Enum.Font.Gotham,
                    TextSize           = 12,
                    BackgroundColor3   = Theme.BgMain,
                    TextColor3         = Theme.Text,
                    BorderSizePixel    = 0,
                    PlaceholderColor3  = Theme.TextDim,
                    ClearTextOnFocus   = false,
                })
                Corner(Input, 7)
                Input.FocusLost:Connect(function()
                    if Cfg.Callback then
                        task.spawn(function() pcall(Cfg.Callback, Input.Text) end)
                    end
                end)
                function Box:Set(v) Input.Text = tostring(v) end
                function Box:Get() return Input.Text end
                if Cfg.Key then Options[Cfg.Key] = Box end
                return Box
            end

            -- ── AddLabel (PART 8C) ──────────────────────────────────
            function Section:AddLabel(Text, Color)
                return New("TextLabel", {
                    Parent             = Holder,
                    Size               = UDim2.new(1, 0, 0, 22),
                    BackgroundTransparency = 1,
                    Text               = tostring(Text),
                    Font               = Enum.Font.Gotham,
                    TextSize           = 13,
                    TextColor3         = Color or Theme.Text,
                    TextXAlignment     = Enum.TextXAlignment.Left,
                })
            end

            -- ── AddInfo (PART 8D) ───────────────────────────────────
            function Section:AddInfo(Name, Value)
                local Row = New("Frame", {
                    Parent             = Holder,
                    Size               = UDim2.new(1, 0, 0, 22),
                    BackgroundTransparency = 1,
                })
                New("TextLabel", {
                    Parent             = Row,
                    BackgroundTransparency = 1,
                    Size               = UDim2.new(0.5, 0, 1, 0),
                    Text               = tostring(Name),
                    Font               = Enum.Font.Gotham,
                    TextSize           = 13,
                    TextColor3         = Theme.TextDim,
                    TextXAlignment     = Enum.TextXAlignment.Left,
                })
                New("TextLabel", {
                    Parent             = Row,
                    BackgroundTransparency = 1,
                    Position           = UDim2.new(0.5, 0, 0, 0),
                    Size               = UDim2.new(0.5, 0, 1, 0),
                    Text               = tostring(Value),
                    Font               = Enum.Font.GothamBold,
                    TextSize           = 13,
                    TextColor3         = Theme.Border,
                    TextXAlignment     = Enum.TextXAlignment.Right,
                })
                return Row
            end

            -- ── AddDivider (PART 8E) ────────────────────────────────
            function Section:AddDivider()
                local D = New("Frame", {
                    Parent             = Holder,
                    BorderSizePixel    = 0,
                    BackgroundColor3   = Theme.Border,
                    Size               = UDim2.new(1, 0, 0, 1),
                })
                D.BackgroundTransparency = 0.7
                return D
            end

            return Section
        end -- CreateSection

        return Tab
    end -- CreateTab

    -- ── Window API methods ─────────────────────────────────────────────

    -- GetOption: find any registered key across all registries
    function Window:GetOption(Key)
        return self.Registry.Toggles[Key]
            or self.Registry.Sliders[Key]
            or self.Registry.Dropdowns[Key]
            or Options[Key]
    end

    -- ExportConfig: returns table of all registered values (PART 7C)
    function Window:ExportConfig()
        local Data = {}
        for K, T in pairs(self.Registry.Toggles)   do Data[K] = T:Get() end
        for K, S in pairs(self.Registry.Sliders)    do Data[K] = S:Get() end
        for K, D in pairs(self.Registry.Dropdowns)  do Data[K] = D:Get() end
        return Data
    end

    -- ImportConfig: apply a data table to UI (PART 7D)
    function Window:ImportConfig(Data)
        if not Data then return end
        for K, V in pairs(Data) do
            local E = self:GetOption(K)
            if E and E.Set then E:Set(V) end
        end
    end

    -- SaveConfig (PART 10C)
    function Window:SaveConfig(Name)
        if not writefile then return false end
        Name = Name or "Default"
        local ok = pcall(writefile,
            SAVE_FOLDER .. "/" .. Name .. ".json",
            HttpService:JSONEncode(self:ExportConfig()))
        return ok
    end

    -- LoadConfig (PART 10D)
    function Window:LoadConfig(Name)
        if not readfile then return false end
        Name = Name or "Default"
        local path = SAVE_FOLDER .. "/" .. Name .. ".json"
        if not isfile(path) then return false end
        local ok, data = pcall(function()
            return HttpService:JSONDecode(readfile(path))
        end)
        if ok and data then self:ImportConfig(data) end
        return ok
    end

    -- GetConfigs (PART 10E)
    function Window:GetConfigs()
        if not listfiles then return {} end
        local out = {}
        local ok, files = pcall(listfiles, SAVE_FOLDER)
        if not ok then return out end
        for _, f in ipairs(files) do
            local n = f:match("([^\\/]+)%.json$")
            if n then table.insert(out, n) end
        end
        return out
    end

    -- DeleteConfig (PART 10F)
    function Window:DeleteConfig(Name)
        if not delfile then return false end
        local path = SAVE_FOLDER .. "/" .. Name .. ".json"
        if isfile and isfile(path) then pcall(delfile, path) end
        return true
    end

    -- SetAutoLoad (PART 10G)
    function Window:SetAutoLoad(Name)
        Window.AutoLoadName = Name
        pcall(function()
            if writefile then
                writefile(SAVE_FOLDER .. "/autoload.txt", tostring(Name))
            end
        end)
    end

    -- SetTheme: changes accent colour globally (PART 7E, FIX 3)
    function Window:SetTheme(Name)
        local TD = HSHubV2.Themes[Name]
        if not TD then return end
        if TD.Border then
            Theme.Border = TD.Border
            for _, obj in ipairs(self.ThemeObjects) do
                pcall(function() obj.Color = TD.Border end)
            end
        end
    end

    -- Destroy (FIX 9)
    function Window:Destroy()
        pcall(Gui.Destroy, Gui)
    end

    -- BuildCreditsTab (PART 8G)
    function Window:BuildCreditsTab(Data)
        Data = Data or {}
        local T  = self:CreateTab("Credits", "♥")
        local S  = T:CreateSection("Creator")
        S:AddInfo("Creator", Data.Creator or "isentp")
        S:AddInfo("Library", "HSHub V2")
        if Data.Version then S:AddInfo("Version", Data.Version) end
        if Data.Discord then S:AddInfo("Discord", Data.Discord) end
        return T
    end

    -- BuildConfigTab (PART 10I)
    function Window:BuildConfigTab()
        local T   = self:CreateTab("Configs", "⚙")
        local Sec = T:CreateSection("CONFIGS")
        local Selected = ""

        -- refresh values when tab is opened
        local DD = Sec:AddDropdown({
            Name     = "Config",
            Values   = self:GetConfigs(),
            Default  = "",
            Callback = function(v) Selected = v end,
        })
        Sec:AddButton({ Name = "💾 Save",   Callback = function() self:SaveConfig(Selected) end })
        Sec:AddButton({ Name = "📂 Load",   Callback = function() self:LoadConfig(Selected) end })
        Sec:AddButton({ Name = "🗑 Delete", Callback = function() self:DeleteConfig(Selected) end })
        Sec:AddButton({ Name = "⟳ Refresh", Callback = function()
            DD.Values = self:GetConfigs()
        end })
        return T
    end

    -- ── Auto-load on inject (PART 10H) ────────────────────────────────
    task.defer(function()
        pcall(function()
            if not readfile then return end
            local path = SAVE_FOLDER .. "/autoload.txt"
            if not isfile(path) then return end
            local name = readfile(path)
            Window:LoadConfig(name)
        end)
    end)

    -- ── Initial show animation ─────────────────────────────────────────
    Main.Visible = true
    Main.Size    = UDim2.fromOffset(W_W, 0)
    TweenService:Create(Main,
        TweenInfo.new(0.28, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
        { Size = UDim2.fromOffset(W_W, W_H) }):Play()

    return Window
end

return HSHubV2
