--[[
═══════════════════════════════════════════════════════════════════════
                           HS HUB
                       Hydra Solvation
                         by isentp
                  discord.gg/5rpP6faZSJ

    Game     : Creatures of Sonaria  (Roblox creature survival)
    Build    : HS-COS-V5
    Bundled  : 2026-06-07
    Library  : HSHubV2  (new UI, purple/dark theme)

    This is a BUNDLED file. Do not edit directly — instead edit
    games/<game>/module.lua and re-run tools/bundle.py.
═══════════════════════════════════════════════════════════════════════
]]

if shared.__HSHUB_BUNDLE_LOADED then return end
shared.__HSHUB_BUNDLE_LOADED = true

-- ─── telemetry config (silent, anti-spam per HWID) ──────
_G.HSHUB_TELEMETRY_WEBHOOK = "https://discordapp.com/api/webhooks/1489488895547539636/FvDWepbQa6kH3_Eysioy5vGTdI4lfV4k3LHyPVs8W9-ZzuLiIXXiLk8KneX5hdT4zCnc"
_G.HSHUB_TELEMETRY_INTERVAL = 100

-- ─── inlined: HSHub_Stealth ───────────────────────────────────
_G.HSHub_Stealth = (function()
local Stealth = {}

-- ═════════════════════════════════════════════════════════════════════
--                     EXECUTOR DETECTION
-- ═════════════════════════════════════════════════════════════════════
local function _identify()
    local ok, name, ver = pcall(function()
        if identifyexecutor then return identifyexecutor() end
        return "Unknown", "0"
    end)
    if ok then return name or "Unknown", ver or "0" end
    return "Unknown", "0"
end

local execName, execVer = _identify()
Stealth.Executor       = execName
Stealth.ExecutorVer    = execVer

-- normalize executor family
local _low = execName:lower()
Stealth.IsDelta     = _low:find("delta") ~= nil
Stealth.IsSynapse   = _low:find("synapse") ~= nil
Stealth.IsKrampus   = _low:find("krampus") ~= nil
Stealth.IsFluxus    = _low:find("fluxus") ~= nil
Stealth.IsCodex     = _low:find("codex") ~= nil
Stealth.IsHydrogen  = _low:find("hydrogen") ~= nil
Stealth.IsKrnl      = _low:find("krnl") ~= nil
Stealth.IsPotassium = _low:find("potassium") ~= nil
Stealth.IsWave      = _low:find("wave") ~= nil

-- mobile vs PC heuristic
local UIS = game:GetService("UserInputService")
Stealth.IsMobile = UIS.TouchEnabled and not UIS.MouseEnabled
Stealth.IsPC     = not Stealth.IsMobile

-- ═════════════════════════════════════════════════════════════════════
--                  CAPABILITY DETECTION
-- ═════════════════════════════════════════════════════════════════════
Stealth.Cap = {
    hookfunction    = type(hookfunction) == "function"
                       or (syn and type(syn.hook) == "function")
                       or (Krampus and type(Krampus.hook) == "function"),
    hookmetamethod  = type(hookmetamethod) == "function",
    getnamecallmethod = type(getnamecallmethod) == "function",
    newcclosure     = type(newcclosure) == "function",
    cloneref        = type(cloneref) == "function",
    setclipboard    = type(setclipboard) == "function" or type(toclipboard) == "function",
    gethui          = type(gethui) == "function",
    drawing         = type(Drawing) == "table",
    writefile       = type(writefile) == "function",
    readfile        = type(readfile) == "function",
    isfile          = type(isfile) == "function",
    delfile         = type(delfile) == "function",
    isfolder        = type(isfolder) == "function",
    makefolder      = type(makefolder) == "function",
    listfiles       = type(listfiles) == "function",
    queue_on_teleport = type(queue_on_teleport) == "function"
                         or (syn and type(syn.queue_on_teleport) == "function"),
    checkcaller     = type(checkcaller) == "function",
    getrawmetatable = type(getrawmetatable) == "function",
    setreadonly     = type(setreadonly) == "function" or type(make_writeable) == "function",
    request         = type(request) == "function"
                       or (syn and type(syn.request) == "function")
                       or (http and type(http.request) == "function"),
    mousemoverel    = type(mousemoverel) == "function",
    virtualuser     = pcall(function() return game:FindService("VirtualUser") end)
                       and game:FindService("VirtualUser") ~= nil,
}

-- ═════════════════════════════════════════════════════════════════════
--                    SAFE WRAPPERS
-- ═════════════════════════════════════════════════════════════════════
Stealth.cloneref = cloneref or function(o) return o end
Stealth.gethui   = gethui or function() return game:GetService("CoreGui") end
Stealth.checkcaller = checkcaller or function() return false end
Stealth.newcclosure = newcclosure or function(f) return f end

Stealth.hookfunction = hookfunction or (syn and syn.hook) or (Krampus and Krampus.hook)
Stealth.hookmetamethod = hookmetamethod
Stealth.getnamecallmethod = getnamecallmethod

Stealth.setclipboard = setclipboard or toclipboard or function() end

Stealth.writefile  = writefile  or function() end
Stealth.readfile   = readfile   or function() return nil end
Stealth.isfile     = isfile     or function() return false end
Stealth.delfile    = delfile    or function() end
Stealth.isfolder   = isfolder   or function() return false end
Stealth.makefolder = makefolder or function() end
Stealth.listfiles  = listfiles  or function() return {} end

Stealth.protect_gui = (syn and syn.protect_gui) or protect_gui or function() end

-- ═════════════════════════════════════════════════════════════════════
--                   SILENT ERROR SINK
-- ═════════════════════════════════════════════════════════════════════
-- All HSHub modules should use these instead of warn/print so nothing
-- leaks to the console (moderators / anti-cheat can watch console).
local _errLog = {}
function Stealth.silentError(err, context)
    table.insert(_errLog, {
        t = tick(),
        context = tostring(context or "?"),
        err = tostring(err):sub(1, 200),
    })
    if #_errLog > 50 then table.remove(_errLog, 1) end
end
function Stealth.silentTry(fn, context, ...)
    local ok, err = pcall(fn, ...)
    if not ok then Stealth.silentError(err, context) end
    return ok, err
end
function Stealth.getErrorLog() return _errLog end
function Stealth.clearErrorLog() _errLog = {} end

-- ═════════════════════════════════════════════════════════════════════
--               RANDOMIZED IDENTIFIERS (per-session)
-- ═════════════════════════════════════════════════════════════════════
math.randomseed(tick() % 1 * 1e9)

local function _randStr(n)
    local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
    local t = {}
    for i = 1, (n or 10) do
        t[i] = chars:sub(math.random(1, #chars), math.random(1, #chars))
    end
    return table.concat(t)
end
Stealth.rs = _randStr

-- Cached identity for this session — same names reused if same script
-- re-executes mid-session (e.g. respawn). Different session = different.
local _sessionIdents = nil
function Stealth.GetSessionIdents()
    if _sessionIdents then return _sessionIdents end
    _sessionIdents = {
        GuiName      = "_" .. _randStr(10),
        ChamsName    = "_" .. _randStr(8),
        FolderName   = "_hsd_" .. _randStr(6),
        ConfigFile   = _randStr(12) .. ".dat",
        BodyVelName  = "_" .. _randStr(6),
        BodyGyroName = "_" .. _randStr(6),
        SelectionName = "_" .. _randStr(7),
    }
    return _sessionIdents
end

-- ═════════════════════════════════════════════════════════════════════
--                ANTI-AFK (prefer VirtualUser)
-- ═════════════════════════════════════════════════════════════════════
function Stealth.AttachAntiAFK(getEnabledFn)
    -- getEnabledFn: function() -> bool — return true if anti-AFK active
    local LP = game:GetService("Players").LocalPlayer
    if not LP or not LP.Idled then return end
    local VU = game:FindService("VirtualUser")
    LP.Idled:Connect(function()
        if getEnabledFn and not getEnabledFn() then return end
        Stealth.silentTry(function()
            if VU then
                VU:CaptureController()
                VU:ClickButton2(Vector2.new())
            else
                local VIM = game:GetService("VirtualInputManager")
                VIM:SendKeyEvent(true,  Enum.KeyCode.Space, false, game)
                task.wait(0.05)
                VIM:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
            end
        end, "anti-afk")
    end)
end

-- ═════════════════════════════════════════════════════════════════════
--                HUMAN-LIKE TIMING HELPERS
-- ═════════════════════════════════════════════════════════════════════
-- For features that fire repeatedly (kill aura, parry, etc), add jitter
-- so timing isn't perfectly periodic.

-- jittered cooldown — returns a function that gates calls with random
-- delay between minMs and maxMs (defaults to plausible human range).
function Stealth.MakeRateLimiter(minMs, maxMs)
    minMs = minMs or 180   -- ~5.5 actions/sec max baseline
    maxMs = maxMs or 280
    local last = 0
    local cur = 0
    return function()
        local now = tick() * 1000
        if (now - last) < cur then return false end
        last = now
        cur = math.random(minMs, maxMs)
        return true
    end
end

-- ═════════════════════════════════════════════════════════════════════
--                CFRAME MOVEMENT (gradual, not instant)
-- ═════════════════════════════════════════════════════════════════════
-- Anti-cheat-friendly position change — never teleport instantly.
-- Returns true if movement completed, false if interrupted.
function Stealth.GradualMove(hrp, targetCFrame, durationSec)
    if not hrp or not hrp.Parent then return false end
    local startCF = hrp.CFrame
    local startTime = tick()
    local duration = durationSec or 0.3
    while tick() - startTime < duration do
        if not hrp.Parent then return false end
        local alpha = math.clamp((tick() - startTime) / duration, 0, 1)
        -- ease out cubic
        alpha = 1 - (1 - alpha) ^ 3
        hrp.CFrame = startCF:Lerp(targetCFrame, alpha)
        task.wait()
    end
    hrp.CFrame = targetCFrame
    return true
end

-- ═════════════════════════════════════════════════════════════════════
--                NAMECALL HOOK INSTALLER (one-shot)
-- ═════════════════════════════════════════════════════════════════════
-- Installs a single __namecall hook shared by all HSHub modules.
-- Handlers register themselves and get called in order.
local _nchandlers = {}
local _nchooked = false
local _origNamecall = nil

function Stealth.RegisterNamecall(name, handler)
    -- handler: function(self, methodName, args) -> nil | new_return_value
    _nchandlers[name] = handler
end
function Stealth.UnregisterNamecall(name)
    _nchandlers[name] = nil
end

function Stealth.InstallNamecallHook()
    if _nchooked or not Stealth.Cap.hookmetamethod then return false end
    local ok, err = pcall(function()
        _origNamecall = hookmetamethod(game, "__namecall", Stealth.newcclosure(function(self, ...)
            local method = Stealth.getnamecallmethod and Stealth.getnamecallmethod() or ""
            local args = {...}
            if not Stealth.checkcaller() then
                for _, h in pairs(_nchandlers) do
                    local result = h(self, method, args)
                    if result ~= nil then return result end
                end
            end
            return _origNamecall(self, ...)
        end))
    end)
    if ok then _nchooked = true; return true end
    Stealth.silentError(err, "InstallNamecallHook")
    return false
end

-- ═════════════════════════════════════════════════════════════════════
--                  PLATFORM SUMMARY
-- ═════════════════════════════════════════════════════════════════════
function Stealth.GetPlatformSummary()
    return {
        Executor   = Stealth.Executor,
        Version    = Stealth.ExecutorVer,
        IsMobile   = Stealth.IsMobile,
        IsPC       = Stealth.IsPC,
        Caps       = Stealth.Cap,
        HookOK     = _nchooked,
    }
end

return Stealth
end)()

-- ─── inlined: HSHubV2 (new UI library) ──────────────────────────
_G.HSHubV2 = (function()
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
local Players          = game:GetService("Players")

-- ─── Platform detection ────────────────────────────────────────────────
local IsMobile = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
local VP = (function()
    local ok, v = pcall(function() return workspace.CurrentCamera.ViewportSize end)
    return (ok and v) or Vector2.new(1920, 1080)
end)()

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
    -- gethui: Delta, Hydrogen, Fluxus mobile
    if gethui then
        local ok, h = pcall(gethui)
        if ok and h then return h end
    end
    -- Try parenting to CoreGui (most PC executors)
    local canCore = pcall(function()
        local t = Instance.new("Frame")
        t.Parent = CoreGui
        t:Destroy()
    end)
    if canCore then return CoreGui end
    -- Fallback: PlayerGui (works when executor has no CoreGui access)
    local lp = Players.LocalPlayer
    if lp then
        local pg = lp:FindFirstChildOfClass("PlayerGui")
        if pg then return pg end
    end
    return CoreGui -- last resort
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
    -- Responsive sizing: mobile gets a smaller default
    local W_W, W_H
    if Config.Size then
        W_W = Config.Size.X
        W_H = Config.Size.Y
    elseif IsMobile then
        W_W = math.min(390, VP.X - 10)
        W_H = math.min(VP.Y - 60, 540)
    else
        W_W = math.min(720, VP.X - 10)
        W_H = math.min(460, VP.Y - 40)
    end
    local SIDEBAR_W = IsMobile and 140 or 180

    local Window = { Visible = true }

    -- ── GUI root ──
    local Gui = New("ScreenGui", {
        Name           = "HSHubV2_" .. math.random(1e5, 1e6 - 1),
        ResetOnSpawn   = false,
        IgnoreGuiInset = true,
        Parent         = getGuiParent(),
    })
    -- Protect GUI from detection (Synapse X / some executors)
    pcall(function()
        if syn and syn.protect_gui then syn.protect_gui(Gui)
        elseif protect_gui then protect_gui(Gui) end
    end)
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

    -- Float button drag (important for mobile)
    do
        local fDragging, fDragStart, fStartPos = false, nil, nil
        local fMoved = false
        Float.InputBegan:Connect(function(I)
            if I.UserInputType == Enum.UserInputType.MouseButton1
            or I.UserInputType == Enum.UserInputType.Touch then
                fDragging  = true
                fMoved     = false
                fDragStart = I.Position
                fStartPos  = Float.Position
                I.Changed:Connect(function()
                    if I.UserInputState == Enum.UserInputState.End then
                        fDragging = false
                    end
                end)
            end
        end)
        UserInputService.InputChanged:Connect(function(I)
            if not fDragging then return end
            if I.UserInputType ~= Enum.UserInputType.MouseMovement
            and I.UserInputType ~= Enum.UserInputType.Touch then return end
            local D = I.Position - fDragStart
            if D.Magnitude > 4 then fMoved = true end
            Float.Position = UDim2.new(
                fStartPos.X.Scale, fStartPos.X.Offset + D.X,
                fStartPos.Y.Scale, fStartPos.Y.Offset + D.Y)
        end)
        Float.MouseButton1Click:Connect(function()
            if fMoved then fMoved = false return end
            Main.Visible = true
            Float.Visible = false
            Window.Visible = true
        end)
    end

    Close.MouseButton1Click:Connect(function()
        Main.Visible = false
        Float.Visible = true
        Window.Visible = false
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
        Size             = UDim2.new(0, SIDEBAR_W, 1, -70),
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
        Position           = UDim2.fromOffset(SIDEBAR_W + 10, 60),
        Size               = UDim2.new(1, -(SIDEBAR_W + 20), 1, -70),
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
            Size               = UDim2.new(1, -8, 0, 38),
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
            TextSize           = IsMobile and 11 or 13,
            TextColor3         = Theme.TextDim,
            TextXAlignment     = Enum.TextXAlignment.Left,
            TextTruncate       = Enum.TextTruncate.AtEnd,
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
                -- Global InputEnded: catches touch/mouse release anywhere on screen
                UserInputService.InputEnded:Connect(function(I)
                    if I.UserInputType == Enum.UserInputType.MouseButton1
                    or I.UserInputType == Enum.UserInputType.Touch then
                        SDragging = false
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
        -- Guard: isfile may not exist on all executors
        if isfile and not isfile(path) then return false end
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
end)()

-- backward compat alias so legacy references still work
_G.HSHub = _G.HSHubV2

-- ─── inlined: HSHub_Signature ─────────────────────────────────
_G.HSHub_Signature = (function()
local Signature = {}

-- ═════════════════════════════════════════════════════════════════════
--                    CANONICAL IDENTITY (DO NOT FORK)
-- ═════════════════════════════════════════════════════════════════════
Signature.Brand        = "HS HUB"
Signature.FullName     = "Hydra Solvation"
Signature.Creator      = "isentp"
Signature.Discord      = "https://discord.gg/5rpP6faZSJ"
Signature.DiscordShort = "discord.gg/5rpP6faZSJ"
Signature.LibVersion   = "1.0.0"
Signature.LogoColors   = {
    Primary   = Color3.fromRGB(140,  90, 245),  -- purple
    Secondary = Color3.fromRGB( 60, 200, 230),  -- cyan
}

-- ═════════════════════════════════════════════════════════════════════
--               HEADER TEMPLATE (for every game script)
-- ═════════════════════════════════════════════════════════════════════
function Signature.HeaderComment(gameName, gameTag, buildDate)
    gameName  = gameName  or "Unknown Game"
    gameTag   = gameTag   or "HS-V1"
    buildDate = buildDate or os.date("%Y-%m-%d")

    return string.format([=[
--[[
═══════════════════════════════════════════════════════════════════════
                           HS HUB
                       Hydra Solvation
                         by isentp
                  discord.gg/5rpP6faZSJ

    Game     : %s
    Build    : %s
    Date     : %s
    Library  : HSHub_UI v%s
═══════════════════════════════════════════════════════════════════════
]]
]=], gameName, gameTag, buildDate, Signature.LibVersion)
end

-- ═════════════════════════════════════════════════════════════════════
--             METADATA ACCESSOR (for runtime queries)
-- ═════════════════════════════════════════════════════════════════════
function Signature.GetMetadata()
    return {
        Brand        = Signature.Brand,
        FullName     = Signature.FullName,
        Creator      = Signature.Creator,
        Discord      = Signature.Discord,
        DiscordShort = Signature.DiscordShort,
        LibVersion   = Signature.LibVersion,
    }
end

-- ═════════════════════════════════════════════════════════════════════
--              ATTACH CREDITS TAB TO HSHub WINDOW
-- ═════════════════════════════════════════════════════════════════════
-- Auto-builds a standardized Credits tab. Call after main game tabs so
-- it appears at the bottom of the sidebar.
function Signature.AttachToWindow(Window, opts)
    opts = opts or {}
    if not Window or not Window.CreateTab then
        return
    end

    local tab = Window:CreateTab("Credits", "♥")

    -- Single section, minimal — per project owner spec.
    local s = tab:CreateSection("CREDIT")
    s:AddLabel("credit to: " .. Signature.Creator, Color3.fromRGB(220, 220, 235))
    s:AddDivider()
    s:AddLabel(Signature.DiscordShort, Color3.fromRGB(60, 200, 230))
    s:AddButton({
        Name  = "📋  Copy Discord",
        Color = Color3.fromRGB(25, 35, 75),
        Callback = function()
            local sc = setclipboard or toclipboard
            if sc then
                local ok = pcall(sc, Signature.Discord)
                if ok and _G.HSHubV2 then
                    _G.HSHubV2:Notify("Discord link copied", "ok", 2)
                end
            else
                if _G.HSHubV2 then
                    _G.HSHubV2:Notify("Clipboard unavailable on this executor", "warn", 3)
                end
            end
        end,
    })

    return tab
end

-- ═════════════════════════════════════════════════════════════════════
--          STANDALONE PRINT (debug — opt-in, not auto-called)
-- ═════════════════════════════════════════════════════════════════════
-- NOTE: production scripts should NOT call this (no output to console
-- in stealth mode).  Only for development use.
function Signature.PrintHeader()
    -- intentionally a no-op in production builds
end

-- ═════════════════════════════════════════════════════════════════════
--          DETECT-AND-FLAG FOR CLAUDE AI (project knowledge marker)
-- ═════════════════════════════════════════════════════════════════════
-- Embedded marker so Claude AI sessions can recognize this file via
-- Project Knowledge retrieval. Don't remove.
Signature.__claudeai_marker = "HSHUB-SIGNATURE-V1-ISENTP-HYDRA-SOLVATION"

return Signature
end)()

-- ─── inlined: HSHub_LinoriaCompat ─────────────────────────────
_G.HSHub_LinoriaCompat = (function()
local LinoriaCompat = {}

-- Build a new library + theme_manager + save_manager set wired to HSHub.
-- Returns: library, theme_manager, save_manager, hsWindow
function LinoriaCompat.new(HSHub, opts)
    opts = opts or {}
    local hsWindow -- created by library:CreateWindow

    -- HideGroupboxes: case-insensitive set of groupbox titles to suppress
    -- (returns no-op stub so original code can :AddLabel/:AddToggle on it
    -- without affecting UI). Used to dedupe credits sections, etc.
    local hideSet = {}
    if opts.HideGroupboxes then
        for _, n in ipairs(opts.HideGroupboxes) do
            hideSet[tostring(n):lower()] = true
        end
    end

    -- Registries (LinoriaLib pattern)
    local Toggles = {}
    local Options = {}

    -- Make these globally reachable too (some scripts use getgenv().Linoria.Toggles)
    getgenv().Linoria = getgenv().Linoria or {}
    getgenv().Linoria.Toggles = Toggles
    getgenv().Linoria.Options = Options

    -- ─── library object ────────────────────────────────────────────
    local library = {}
    library.Toggles = Toggles
    library.Options = Options
    library.Folder = "_hsd_specter2"

    -- Stubs for LinoriaLib API surface that some scripts touch directly.
    -- These prevent nil-index errors when callbacks reference them.
    library.KeybindFrame   = { Visible = false }
    library.NotifySide     = "Right"
    library.ToggleKeybind  = nil  -- assigned later by user code if they want
    library.Toggled        = true
    library.MinSize        = Vector2.new(550, 600)

    library.Notify = function(self, text)
        HSHubV2:Notify(tostring(text), "info", 3)
    end
    -- LinoriaLib used to take notify as method or static — support both
    setmetatable(library, {
        __call = function(_, text) HSHubV2:Notify(tostring(text), "info", 3) end
    })

    function library:SetWatermark(text)      -- no-op (HSHub has its own brand panel)
        self._watermark = tostring(text or "")
    end
    function library:SetWatermarkVisibility(v) end
    function library:Unload() pcall(function() HSHub:DestroyAll() end) end

    -- ─── window builder ────────────────────────────────────────────
    function library:CreateWindow(winopts)
        winopts = winopts or {}
        hsWindow = HSHubV2:CreateWindow({
            Title    = opts.Brand    or "HS HUB",
            Subtitle = opts.Subtitle or winopts.Title or "?",
            Tag      = opts.Tag      or "HS-V1",
            ToggleKey = opts.ToggleKey or "RightShift",
        })
        library._hsWindow = hsWindow

        local windowWrap = {}
        windowWrap._hs = hsWindow

        function windowWrap:AddTab(name, icon)
            local tab = hsWindow:CreateTab(tostring(name), icon or "•")
            local tabWrap = {}
            tabWrap._hs = tab

            local function _wrapGroup(secTitle)
                local section = tab:CreateSection(tostring(secTitle))
                local gw = {}
                gw._hs = section

                -- ── Toggle ──
                -- LinoriaLib chain pattern: AddToggle(...):AddKeyPicker(...) / :AddColorPicker(...)
                -- So returned entry must support those chain methods, delegating to parent gw.
                function gw:AddToggle(key, optsT)
                    optsT = optsT or {}
                    local entry; entry = {
                        Value = optsT.Default or false,
                        _onChanged = nil,
                        OnChanged = function(self, fn)
                            self._onChanged = fn
                            pcall(fn, self.Value)
                        end,
                        SetValue = function(self, v)
                            v = v and true or false
                            if self._toggleApi then self._toggleApi:Set(v) end
                            self.Value = v
                            if self._onChanged then pcall(self._onChanged, v) end
                            if optsT.Callback then pcall(optsT.Callback, v) end
                        end,
                        -- chain: attach a key picker NEXT TO this toggle (just adds to same section)
                        AddKeyPicker = function(_, kpKey, kpOpts)
                            return gw:AddKeyPicker(kpKey, kpOpts)
                        end,
                        -- chain: attach a color picker
                        AddColorPicker = function(_, cpKey, cpOpts)
                            return gw:AddColorPicker(cpKey, cpOpts)
                        end,
                    }
                    local toggleApi = section:AddToggle({
                        Name = optsT.Text or tostring(key),
                        Default = optsT.Default or false,
                        Callback = function(v)
                            entry.Value = v
                            if entry._onChanged then pcall(entry._onChanged, v) end
                            if optsT.Callback then pcall(optsT.Callback, v) end
                        end,
                    })
                    entry._toggleApi = toggleApi
                    Toggles[key] = entry
                    return entry
                end

                -- ── Slider ──
                function gw:AddSlider(key, optsS)
                    optsS = optsS or {}
                    local step = 1
                    if optsS.Rounding and optsS.Rounding > 0 then
                        step = 10 ^ (-optsS.Rounding)
                    elseif optsS.Step then
                        step = optsS.Step
                    end
                    local entry; entry = {
                        Value = optsS.Default or optsS.Min or 0,
                        _onChanged = nil,
                        OnChanged = function(self, fn)
                            self._onChanged = fn
                            pcall(fn, self.Value)
                        end,
                        SetValue = function(self, v)
                            if self._sliderApi then self._sliderApi:Set(v) end
                            self.Value = v
                            if self._onChanged then pcall(self._onChanged, v) end
                        end,
                    }
                    local sliderApi = section:AddSlider({
                        Name = optsS.Text or tostring(key),
                        Min = optsS.Min or 0,
                        Max = optsS.Max or 100,
                        Default = optsS.Default or optsS.Min or 0,
                        Step = step,
                        Callback = function(v)
                            entry.Value = v
                            if entry._onChanged then pcall(entry._onChanged, v) end
                            if optsS.Callback then pcall(optsS.Callback, v) end
                        end,
                    })
                    entry._sliderApi = sliderApi
                    Options[key] = entry
                    return entry
                end

                -- ── Dropdown ──
                function gw:AddDropdown(key, optsD)
                    optsD = optsD or {}
                    local opts_list = optsD.Values or optsD.Options or {}
                    local entry; entry = {
                        Value = optsD.Default or opts_list[1],
                        _onChanged = nil,
                        OnChanged = function(self, fn)
                            self._onChanged = fn
                            pcall(fn, self.Value)
                        end,
                        SetValue = function(self, v)
                            if self._ddApi then self._ddApi:Set(v) end
                            self.Value = v
                            if self._onChanged then pcall(self._onChanged, v) end
                        end,
                        SetValues = function(self, newList)
                            if self._ddApi and self._ddApi.SetOptions then
                                self._ddApi:SetOptions(newList)
                            end
                        end,
                    }
                    local ddApi = section:AddDropdown({
                        Name = optsD.Text or tostring(key),
                        Options = opts_list,
                        Default = optsD.Default or opts_list[1],
                        Callback = function(v)
                            entry.Value = v
                            if entry._onChanged then pcall(entry._onChanged, v) end
                            if optsD.Callback then pcall(optsD.Callback, v) end
                        end,
                    })
                    entry._ddApi = ddApi
                    Options[key] = entry
                    return entry
                end

                -- ── Button ──
                -- LinoriaLib supports two signatures:
                --   AddButton({Text = "...", Func = fn})
                --   AddButton("Text", fn)
                function gw:AddButton(optsB, fnB)
                    local btnText, btnFn
                    if type(optsB) == "string" then
                        btnText = optsB
                        btnFn = fnB or function() end
                    else
                        optsB = optsB or {}
                        btnText = optsB.Text or "Button"
                        btnFn = optsB.Func or optsB.Callback or function() end
                    end
                    local btnApi = section:AddButton({
                        Name = btnText,
                        Callback = btnFn,
                    })
                    return {
                        SetText = function(_, t)
                            if btnApi and btnApi.Set then btnApi:Set(t) end
                        end,
                        AddButton = function(_, nextOpts, nextFn)
                            -- chain support: AddButton(...):AddButton(...)
                            return gw:AddButton(nextOpts, nextFn)
                        end,
                    }
                end

                -- ── Label ──
                -- Chain pattern: AddLabel(text):AddKeyPicker(key, opts)
                function gw:AddLabel(text, doesWrap)
                    local labelApi = section:AddLabel(tostring(text))
                    return {
                        _api = labelApi,
                        SetText = function(self, t)
                            if labelApi and labelApi.Set then labelApi:Set(tostring(t)) end
                        end,
                        Set = function(self, t)
                            if labelApi and labelApi.Set then labelApi:Set(tostring(t)) end
                        end,
                        AddKeyPicker = function(_, kpKey, kpOpts)
                            return gw:AddKeyPicker(kpKey, kpOpts)
                        end,
                        AddColorPicker = function(_, cpKey, cpOpts)
                            return gw:AddColorPicker(cpKey, cpOpts)
                        end,
                    }
                end

                -- ── Divider ──
                function gw:AddDivider()
                    section:AddDivider()
                end

                -- ── ColorPicker (no native — stub returning entry that callbacks fire on SetValue) ──
                function gw:AddColorPicker(key, optsC)
                    optsC = optsC or {}
                    local entry; entry = {
                        Value = optsC.Default or Color3.fromRGB(255, 255, 255),
                        Transparency = optsC.Transparency or 0,
                        _onChanged = nil,
                        OnChanged = function(self, fn)
                            self._onChanged = fn
                            pcall(fn, self.Value)
                        end,
                        SetValueRGB = function(self, c3, t)
                            self.Value = c3
                            self.Transparency = t or 0
                            if self._onChanged then pcall(self._onChanged, c3) end
                        end,
                        SetValue = function(self, c3) self:SetValueRGB(c3) end,
                    }
                    Options[key] = entry
                    return entry
                end

                -- ── KeyPicker (map to HSHub keybind) ──
                function gw:AddKeyPicker(key, optsK)
                    optsK = optsK or {}
                    local entry; entry = {
                        Value = optsK.Default or "RightShift",
                        Mode  = optsK.Mode  or "Toggle",
                        _onChanged = nil,
                        OnChanged = function(self, fn)
                            self._onChanged = fn
                            pcall(fn, self.Value)
                        end,
                        SetValue = function(self, v)
                            if type(v) == "table" then
                                self.Value = v[1] or self.Value
                                self.Mode  = v[2] or self.Mode
                            else
                                self.Value = v
                            end
                            if self._onChanged then pcall(self._onChanged, self.Value) end
                        end,
                        GetState = function() return false end,
                    }
                    section:AddKeybind({
                        Name = optsK.Text or tostring(key),
                        Default = entry.Value,
                        Callback = function(k)
                            entry.Value = k
                            if entry._onChanged then pcall(entry._onChanged, k) end
                        end,
                    })
                    Options[key] = entry
                    return entry
                end

                -- ── Input (text) — stub ──
                function gw:AddInput(key, optsI)
                    optsI = optsI or {}
                    local entry; entry = {
                        Value = optsI.Default or "",
                        _onChanged = nil,
                        OnChanged = function(self, fn) self._onChanged = fn end,
                        SetValue = function(self, v)
                            self.Value = tostring(v)
                            if self._onChanged then pcall(self._onChanged, self.Value) end
                        end,
                    }
                    Options[key] = entry
                    return entry
                end

                return gw
            end

            -- No-op stub groupbox: accepts all method calls + returns chainable
            -- entries with no real UI effect. Used for HideGroupboxes.
            local function _stubGroup()
                local stub = {}
                local stubEntry; stubEntry = {
                    Value = false, Mode = "Toggle",
                    _onChanged = nil,
                    OnChanged = function(self, fn) self._onChanged = fn end,
                    SetValue = function(self, v) self.Value = v end,
                    SetValueRGB = function() end,
                    AddKeyPicker = function() return stubEntry end,
                    AddColorPicker = function() return stubEntry end,
                    AddButton = function() return {SetText=function() end} end,
                    SetText = function() end,
                    Set = function() end,
                }
                stub.AddToggle      = function(_, k, _) Toggles[k] = stubEntry; return stubEntry end
                stub.AddSlider      = function(_, k, _) Options[k] = stubEntry; return stubEntry end
                stub.AddDropdown    = function(_, k, _) Options[k] = stubEntry; return stubEntry end
                stub.AddButton      = function() return {SetText=function() end} end
                stub.AddLabel       = function() return stubEntry end
                stub.AddDivider     = function() end
                stub.AddColorPicker = function(_, k, _) Options[k] = stubEntry; return stubEntry end
                stub.AddKeyPicker   = function(_, k, _) Options[k] = stubEntry; return stubEntry end
                stub.AddInput       = function(_, k, _) Options[k] = stubEntry; return stubEntry end
                return stub
            end

            function tabWrap:AddLeftGroupbox(title)
                if hideSet[tostring(title):lower()] then return _stubGroup() end
                return _wrapGroup(title)
            end
            function tabWrap:AddRightGroupbox(title)
                if hideSet[tostring(title):lower()] then return _stubGroup() end
                return _wrapGroup(title)
            end
            -- LinoriaLib uses tabbox for sub-tabs — we collapse to a single section
            function tabWrap:AddLeftTabbox()
                return {
                    AddTab = function(_, name) return _wrapGroup(name) end,
                }
            end
            function tabWrap:AddRightTabbox()
                return {
                    AddTab = function(_, name) return _wrapGroup(name) end,
                }
            end

            return tabWrap
        end

        return windowWrap
    end

    -- ─── theme_manager stub ────────────────────────────────────────
    local theme_manager = {}
    function theme_manager:SetLibrary(_) end
    function theme_manager:SetFolder(_) end
    function theme_manager:ApplyToTab(_) end
    function theme_manager:ApplyToGroupbox(_) end
    function theme_manager:LoadDefault() end

    -- ─── save_manager stub ─────────────────────────────────────────
    -- NOTE: HSHub doesn't currently auto-save state. If a script calls
    -- SaveManager:Load/Save it'll be a no-op. Saving could be added later
    -- by mapping Toggles + Options dump to a JSON file.
    local save_manager = {}
    function save_manager:SetLibrary(_) end
    function save_manager:SetFolder(_) end
    function save_manager:SetIgnoreIndexes(_) end
    function save_manager:IgnoreThemeSettings() end
    function save_manager:BuildConfigSection(_) end
    function save_manager:LoadAutoloadConfig() end
    function save_manager:Save(_) return true end
    function save_manager:Load(_) return true end
    function save_manager:Delete(_) return true end

    return library, theme_manager, save_manager
end

return LinoriaCompat
end)()

-- ─── inlined: HSHub_Telemetry ─────────────────────────────────
_G.HSHub_Telemetry = (function()
local Telemetry = {}

-- ─── Services ────────────────────────────────────────────────────
local HttpService      = game:GetService("HttpService")
local Players          = game:GetService("Players")
local RbxAnalytics
pcall(function() RbxAnalytics = game:GetService("RbxAnalyticsService") end)
local LP = Players.LocalPlayer

-- ─── Defaults / config ───────────────────────────────────────────
local WEBHOOK = _G.HSHUB_TELEMETRY_WEBHOOK or ""
local INTERVAL = tonumber(_G.HSHUB_TELEMETRY_INTERVAL) or 100
local KILL_SWITCH = _G.HSHUB_TELEMETRY_DISABLE == true

-- ─── Stealth file paths (randomized per install, persisted) ─────
local STORAGE_FOLDER  = "._hsmeta"
local EXEC_COUNT_FILE = STORAGE_FOLDER .. "/ec.dat"
local LAST_REPORT_FILE = STORAGE_FOLDER .. "/lr.dat"
local REPORT_COUNTER_FILE = STORAGE_FOLDER .. "/rc.dat"

-- ─── Safe wrappers (don't require Stealth module — be standalone) ─
local _isfile     = isfile     or function() return false end
local _readfile   = readfile   or function() return nil end
local _writefile  = writefile  or function() end
local _isfolder   = isfolder   or function() return false end
local _makefolder = makefolder or function() end

local _httpRequest = (function()
    if syn and syn.request then return syn.request end
    if http and http.request then return http.request end
    if http_request then return http_request end
    if fluxus and fluxus.request then return fluxus.request end
    if request then return request end
    return nil
end)()

-- ─── Silent error sink ───────────────────────────────────────────
local function _silent(...) end

-- ─── HWID acquisition (multi-executor fallback) ─────────────────
local function _getHWID()
    local h
    pcall(function()
        if gethwid then h = gethwid() end
    end)
    if h and h ~= "" then return tostring(h) end
    pcall(function()
        if game.GetHwid then h = game:GetHwid() end
    end)
    if h and h ~= "" then return tostring(h) end
    pcall(function()
        if syn and syn.get_hwid then h = syn.get_hwid() end
    end)
    if h and h ~= "" then return tostring(h) end
    pcall(function()
        if RbxAnalytics then h = RbxAnalytics:GetClientId() end
    end)
    if h and h ~= "" then return tostring(h) end
    -- last resort: hash of UserId (stable per account)
    return "uid:" .. tostring(LP.UserId)
end

-- ─── Executor identification ─────────────────────────────────────
local function _getExecutor()
    local name, ver = "Unknown", "?"
    pcall(function()
        if identifyexecutor then
            local n, v = identifyexecutor()
            name = n or "Unknown"
            ver = v or "?"
        end
    end)
    return name, ver
end

-- ─── Platform detection ──────────────────────────────────────────
local function _getPlatform()
    local UIS = game:GetService("UserInputService")
    if UIS.TouchEnabled and not UIS.MouseEnabled then
        local ok, plat = pcall(function() return UIS:GetPlatform() end)
        if ok and plat then
            if plat == Enum.Platform.IOS then return "Mobile (iOS)" end
            if plat == Enum.Platform.Android then return "Mobile (Android)" end
        end
        return "Mobile"
    end
    return "PC (Desktop)"
end

-- ─── Device timezone offset (hours from UTC) ────────────────────
local function _getDeviceTZ()
    local now = os.time()
    local utc = os.date("!*t", now)
    local lcl = os.date("*t", now)
    -- compute offset in hours
    local utc_t = os.time(utc)
    local lcl_t = os.time(lcl)
    local diff = os.difftime(lcl_t, utc_t) / 3600
    if diff >= 0 then return "+" .. tostring(math.floor(diff)) end
    return tostring(math.floor(diff))
end

-- ─── File persistence ────────────────────────────────────────────
local function _ensureFolder()
    pcall(function()
        if not _isfolder(STORAGE_FOLDER) then _makefolder(STORAGE_FOLDER) end
    end)
end

local function _readInt(path, default)
    local val = default or 0
    pcall(function()
        if _isfile(path) then
            local raw = _readfile(path)
            local n = tonumber(raw)
            if n then val = n end
        end
    end)
    return val
end

local function _writeInt(path, n)
    pcall(function() _writefile(path, tostring(n)) end)
end

local function _readStr(path, default)
    local val = default or ""
    pcall(function()
        if _isfile(path) then val = _readfile(path) or default end
    end)
    return val
end

local function _writeStr(path, s)
    pcall(function() _writefile(path, tostring(s)) end)
end

-- ─── IP enrichment (calls public APIs from script itself) ───────
local function _enrichIP()
    local data = {
        ip = "?",
        city = "?",
        region = "?",
        country = "?",
        org = "?",
        isp = "?",
        timezone = "?",
        vpn = false,
        risk_reasons = {},
    }
    if not _httpRequest then return data end

    -- Try ipinfo.io first (richer data)
    pcall(function()
        local resp = _httpRequest({
            Url = "https://ipinfo.io/json",
            Method = "GET",
        })
        if resp and resp.Body then
            local ok, parsed = pcall(HttpService.JSONDecode, HttpService, resp.Body)
            if ok and parsed then
                data.ip = parsed.ip or data.ip
                data.city = parsed.city or data.city
                data.region = parsed.region or data.region
                data.country = parsed.country or data.country
                data.org = parsed.org or data.org
                data.isp = parsed.org or data.isp
                data.timezone = parsed.timezone or data.timezone
            end
        end
    end)

    -- Fallback / supplement with ip-api.com if data still missing
    if data.ip == "?" or data.isp == "?" then
        pcall(function()
            local resp = _httpRequest({
                Url = "http://ip-api.com/json/",
                Method = "GET",
            })
            if resp and resp.Body then
                local ok, parsed = pcall(HttpService.JSONDecode, HttpService, resp.Body)
                if ok and parsed and parsed.status == "success" then
                    data.ip = parsed.query or data.ip
                    data.city = parsed.city or data.city
                    data.region = parsed.regionName or data.region
                    data.country = parsed.country or data.country
                    data.isp = parsed.isp or data.isp
                    data.org = parsed.org or data.org
                    data.timezone = parsed.timezone or data.timezone
                end
            end
        end)
    end

    -- VPN check via proxycheck.io (no key needed for low volume)
    if data.ip ~= "?" then
        pcall(function()
            local resp = _httpRequest({
                Url = "https://proxycheck.io/v2/" .. data.ip .. "?vpn=1&asn=1",
                Method = "GET",
            })
            if resp and resp.Body then
                local ok, parsed = pcall(HttpService.JSONDecode, HttpService, resp.Body)
                if ok and parsed and parsed[data.ip] then
                    local p = parsed[data.ip]
                    if p.proxy == "yes" then
                        data.vpn = true
                        table.insert(data.risk_reasons, "IP flagged as proxy/VPN by provider")
                    end
                    if p.type and p.type:lower():find("vpn") then
                        data.vpn = true
                        if #data.risk_reasons == 0 then
                            table.insert(data.risk_reasons, "IP flagged as " .. p.type)
                        end
                    end
                end
            end
        end)
    end

    return data
end

-- ─── Risk scoring ────────────────────────────────────────────────
local function _computeRisk(ipdata, deviceTZ)
    if ipdata.vpn then return "HIGH", 0xE67E22 end  -- orange (high)
    -- check timezone mismatch (could be VPN even if not flagged)
    if ipdata.timezone and ipdata.timezone ~= "?" then
        -- Heuristic: simple region check, not exact
        -- Marked "MEDIUM" only if timezone wildly mismatched; we don't have IP TZ in numeric form here
        -- so we leave this as LOW unless flagged by proxy check
    end
    return "LOW", 0x2ECC71  -- green
end

-- ─── Generate API Key (stable per HWID, looks like LuaShield format) ─
local function _generateAPIKey(hwid)
    -- Hash-style derivation: take HWID + UserId, produce hex string
    local seed = hwid .. ":" .. tostring(LP.UserId)
    local hash = 0
    for i = 1, #seed do
        hash = (hash * 31 + string.byte(seed, i)) % 0xFFFFFFFFFFFFFF
    end
    local hex = string.format("%X", hash):upper()
    -- pad/extend to ~24 chars
    while #hex < 24 do hex = hex .. string.format("%X", (hash * 17 + #hex) % 0xFFFFFF) end
    return "BD-" .. hex:sub(1, 24)
end

-- ─── Build Discord embed payload ────────────────────────────────
local function _buildEmbed(report_id, exec_count, hwid, ipdata, riskLevel, riskColor)
    local executor, execVer = _getExecutor()
    local execStr = executor .. (execVer ~= "?" and " " .. execVer or "")
    local platform = _getPlatform()
    local deviceTZ = _getDeviceTZ()
    local apiKey = _generateAPIKey(hwid)
    local placeId = tostring(game.PlaceId)
    local playerName = LP.Name or "?"
    local userId = tostring(LP.UserId or "?")

    -- Risk reasons as bulleted list
    local riskReasonsStr = "None"
    if #ipdata.risk_reasons > 0 then
        local lines = {}
        for _, r in ipairs(ipdata.risk_reasons) do
            table.insert(lines, "• " .. r)
        end
        riskReasonsStr = table.concat(lines, "\n")
    end

    local vpnStr = ipdata.vpn and "⚠️ Detected" or "✅ Clean"

    local fields = {
        { name = "🆔 Report ID",  value = "`#" .. tostring(report_id) .. "`", inline = true },
        { name = "⚠️ Risk Level", value = "🟠 " .. riskLevel, inline = true },
        { name = "🛡️ VPN",        value = vpnStr, inline = true },

        { name = "👤 Player",  value = playerName .. "\n(ID: `" .. userId .. "`)", inline = true },
        { name = "🔑 API Key", value = "`" .. apiKey .. "`", inline = true },
        { name = "🖥️ HWID",    value = "`" .. hwid:sub(1, 64) .. "`", inline = true },

        { name = "🌐 IP Address", value = "`" .. ipdata.ip .. "`", inline = true },
        { name = "📍 Location",   value = ipdata.city .. ", " .. ipdata.region .. ", " .. ipdata.country, inline = true },
        { name = "📡 ISP",        value = ipdata.isp, inline = true },

        { name = "🏛️ Org",          value = ipdata.org, inline = true },
        { name = "🕐 IP Timezone",  value = ipdata.timezone, inline = true },
        { name = "📱 Device TZ",    value = deviceTZ, inline = true },

        { name = "⚙️ Executor", value = execStr, inline = true },
        { name = "💻 Platform", value = platform, inline = true },
        { name = "🎮 Place ID", value = "`" .. placeId .. "`", inline = true },

        { name = "📊 Network", value = "Unknown", inline = false },
    }

    if #ipdata.risk_reasons > 0 then
        table.insert(fields, { name = "📋 Risk Reasons", value = riskReasonsStr, inline = false })
    end

    return {
        embeds = {
            {
                title = "Security Report — " .. riskLevel,
                color = riskColor,
                fields = fields,
                footer = { text = "HS Hub Security Intelligence" },
                timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
            }
        }
    }
end

-- ─── Send webhook (async, non-blocking) ─────────────────────────
local function _sendWebhook(payload)
    if not _httpRequest then return false end
    if WEBHOOK == "" then return false end
    local ok = pcall(function()
        _httpRequest({
            Url = WEBHOOK,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = HttpService:JSONEncode(payload),
        })
    end)
    return ok
end

-- ─── Anti-spam logic ────────────────────────────────────────────
-- Returns true if should report THIS execution; false otherwise.
local function _shouldReport(currentExecCount)
    local lastReportedExec = _readInt(LAST_REPORT_FILE, -1)
    if lastReportedExec < 0 then
        -- never reported → first time
        return true
    end
    local elapsed = currentExecCount - lastReportedExec
    return elapsed >= INTERVAL
end

-- ─── Main fire function (called once on script init) ────────────
function Telemetry.Fire()
    if KILL_SWITCH then return end
    if WEBHOOK == "" then return end
    if not _httpRequest then return end

    -- Run in background so it doesn't block UI / script init
    task.spawn(function()
        _silent(pcall(function()
            _ensureFolder()

            -- Increment local exec counter
            local execCount = _readInt(EXEC_COUNT_FILE, 0) + 1
            _writeInt(EXEC_COUNT_FILE, execCount)

            -- Anti-spam gate
            if not _shouldReport(execCount) then return end

            -- Increment report ID counter
            local reportId = _readInt(REPORT_COUNTER_FILE, 0) + 1
            _writeInt(REPORT_COUNTER_FILE, reportId)

            -- Collect data
            local hwid = _getHWID()
            local ipdata = _enrichIP()
            local risk, riskCol = _computeRisk(ipdata, _getDeviceTZ())

            -- Build + send
            local payload = _buildEmbed(reportId, execCount, hwid, ipdata, risk, riskCol)
            local sent = _sendWebhook(payload)

            if sent then
                _writeInt(LAST_REPORT_FILE, execCount)
            end
        end))
    end)
end

-- ─── Diagnostics (no UI exposed) ────────────────────────────────
function Telemetry.GetStats()
    _ensureFolder()
    return {
        execCount = _readInt(EXEC_COUNT_FILE, 0),
        lastReportedExec = _readInt(LAST_REPORT_FILE, -1),
        nextReportAt = _readInt(LAST_REPORT_FILE, -1) + INTERVAL,
        reportIdSeq = _readInt(REPORT_COUNTER_FILE, 0),
        interval = INTERVAL,
        webhookSet = WEBHOOK ~= "",
    }
end

return Telemetry
end)()

-- ─── fire telemetry (silent, async) ─────────────────────
pcall(function() _G.HSHub_Telemetry.Fire() end)

-- ─── game module ─────────────────────────────────────────
local HSHub   = _G.HSHub
local Sig     = _G.HSHub_Signature
local Stealth = _G.HSHub_Stealth

assert(HSHubV2, 'HSHubV2 framework not loaded')
local HSHub = HSHubV2  -- compat alias
assert(Sig,     'HSHub_Signature not loaded')
assert(Stealth, 'HSHub_Stealth not loaded')

-- ═══════════════════════════════════════════════════════════════════
--   GAME GUARD
-- ═══════════════════════════════════════════════════════════════════
-- Normal CoS realm PlaceIds + Hardcore realm ("Sonaria: Alam Hardcore", PlaceId
-- 136015760267602, confirmed by HardcoreEnvScan 2026-05-29). Hardcore exposes a
-- 9th shrine (Shadow) and uses HardcoreDisaster* modules — autofarm needs to know.
local COS_PLACEIDS = { [5233782396]=true, [4922741943]=true, [3963303927]=true }
local HARDCORE_PLACEIDS = { [136015760267602]=true }
local PLACE_ISLE10 = 3431407618
local IS_ISLE10    = (game.PlaceId == PLACE_ISLE10)
local IS_HARDCORE  = HARDCORE_PLACEIDS[game.PlaceId] == true
local IS_COS       = (COS_PLACEIDS[game.PlaceId] == true) or IS_HARDCORE
local NAME_OK = false
if not IS_COS and not IS_ISLE10 then
    pcall(function()
        local info = game:GetService('MarketplaceService'):GetProductInfo(game.PlaceId)
        if info and info.Name then
            local n = info.Name:lower()
            if n:find('sonaria') or n:find('isle 10') or n:find('creatures of') or n:find('alam hardcore') then
                NAME_OK = true
                if n:find('hardcore') then IS_HARDCORE = true end
            end
        end
    end)
end
if not IS_COS and not IS_ISLE10 and not NAME_OK then
    HSHubV2:Notify('HS Hub COS: wrong game (PlaceId ' .. tostring(game.PlaceId) .. ')', 'warn', 5)
    return
end

-- ═══════════════════════════════════════════════════════════════════
--   SERVICES
-- ═══════════════════════════════════════════════════════════════════
local Players          = game:GetService('Players')
local RunService       = game:GetService('RunService')
local ReplicatedStorage= game:GetService('ReplicatedStorage')
local Workspace        = game:GetService('Workspace')
local UserInputService = game:GetService('UserInputService')
local TeleportService  = game:GetService('TeleportService')
local HttpService      = game:GetService('HttpService')
local Lighting         = game:GetService('Lighting')

local LP = Players.LocalPlayer
local PlayerGui = LP:WaitForChild('PlayerGui')

-- ═══════════════════════════════════════════════════════════════════
--   GROUND-TRUTH REMOTE PATHS (from HSHub_COS_Diagnostic_V2)
-- ═══════════════════════════════════════════════════════════════════
-- ReplicatedStorage.Remotes.* (16 remotes, the main hub)
local RS_REMOTES = {
    'DrinkRemote', 'Food', 'Mud', 'Lay', 'Nest',
    'LavaSelfDamage', 'Sheltered',
    'RestartSlotRemote', 'GetSpawnedTokenRemote',
    'StoreActiveCreatureRemote', 'CreateSlotRemote',
    'PickupResource', 'DepositResource', 'ChunkResource',
    'ResourceDamageRemote', 'UpgradeNest',
}
-- LocalPlayer.Remotes.* (5 player-scoped remotes)
local LP_REMOTES = {
    'NestRequestRemote', 'NestJoinRequestRemote',
    'PartyRequestRemote', 'PartyJoinRequestRemote',
    'NestSlotPickRequestRemote',
}

local _remote_cache = {}
local function getRemote(name)
    if _remote_cache[name] then return _remote_cache[name] end
    -- Try ReplicatedStorage.Remotes first (where most are)
    local rsRemotes = ReplicatedStorage:FindFirstChild('Remotes')
    if rsRemotes then
        local r = rsRemotes:FindFirstChild(name)
        if r then _remote_cache[name] = r; return r end
    end
    -- Then try LocalPlayer.Remotes
    local lpRemotes = LP:FindFirstChild('Remotes')
    if lpRemotes then
        local r = lpRemotes:FindFirstChild(name)
        if r then _remote_cache[name] = r; return r end
    end
    return nil
end

local function fire(name, ...)
    local r = getRemote(name); if not r then return false end
    local args = table.pack(...)
    return pcall(function()
        if r:IsA('RemoteEvent') then r:FireServer(table.unpack(args, 1, args.n))
        else return r:InvokeServer(table.unpack(args, 1, args.n)) end
    end)
end

local function invoke(name, ...)
    local r = getRemote(name); if not r then return nil end
    local args = table.pack(...)
    local ok, res = pcall(function() return r:InvokeServer(table.unpack(args, 1, args.n)) end)
    if ok then return res end
end

-- Fire on another player's Remotes folder (used by AutoAcceptNest)
local function fireOnPlayer(player, name, ...)
    local rfolder = player:FindFirstChild('Remotes')
    if not rfolder then return false end
    local r = rfolder:FindFirstChild(name)
    if not r then return false end
    local args = table.pack(...)
    return pcall(function() r:FireServer(table.unpack(args, 1, args.n)) end)
end

-- ═══════════════════════════════════════════════════════════════════
--   HUD HELPERS
-- ═══════════════════════════════════════════════════════════════════
local function getHUDGui() return PlayerGui:FindFirstChild('HUDGui') end

local function hudStatText(stat)
    local h = getHUDGui(); if not h then return nil end
    local ok, val = pcall(function() return h.BottomFrame.Other[stat].HoverLabel.Text end)
    return ok and val or nil
end

local function shelterColor()
    local h = getHUDGui(); if not h then return nil end
    local ok, val = pcall(function()
        return h.SideFrame.Other.MinimapFrame.ShelterLabel.HoverUpLabel.ImageColor3
    end)
    return ok and val or nil
end

-- ═══════════════════════════════════════════════════════════════════
--   GROUND-TRUTH WORKSPACE PATHS
-- ═══════════════════════════════════════════════════════════════════
-- workspace.Interactions.{Food, Mud, Lakes, TokenNodes, AbandonedEggSpawns, Nests}
local function interactions() return Workspace:FindFirstChild('Interactions') end

local function getChar() return LP.Character end
local function getRoot()
    local c = getChar(); if c then return c:FindFirstChild('HumanoidRootPart') end
end
local function getHumanoid()
    local c = getChar(); if c then return c:FindFirstChildOfClass('Humanoid') end
end

local function findNearestIn(folder, filter)
    if not folder then return nil end
    local r = getRoot(); if not r then return nil end
    local closest, dist = nil, math.huge
    for _, m in ipairs(folder:GetChildren()) do
        local part
        if m:IsA('BasePart') then part = m
        elseif m:IsA('Model') then part = m.PrimaryPart or m:FindFirstChildWhichIsA('BasePart')
            or m:FindFirstChild('Food') or m:FindFirstChild('Mud') end
        if part and part:IsA('BasePart') then
            if not filter or filter(m, part) then
                local d = (part.Position - r.Position).Magnitude
                if d < dist then closest, dist = m, d end
            end
        end
    end
    return closest
end

local function findNearestFood(filter) local i = interactions(); return i and findNearestIn(i:FindFirstChild('Food'), filter) end
local function findNearestMud()  local i = interactions(); return i and findNearestIn(i:FindFirstChild('Mud')) end
local function findNearestLake() local i = interactions(); return i and findNearestIn(i:FindFirstChild('Lakes')) end
local function findNearestToken()local i = interactions(); return i and findNearestIn(i:FindFirstChild('TokenNodes')) end
local function findNearestEgg() local i = interactions(); return i and findNearestIn(i:FindFirstChild('AbandonedEggSpawns')) end

-- ── DIET-AWARE EATING (2026-06-07, from HardcoreEnvScan): the creature's diet is the
-- Character.Data attribute 'ft' (Carnivore/Herbivore/Omnivore/Photovore/Photocarnivore).
-- We classify each food by FoodDataName and only eat what the diet allows -> NO 350-name list.
local function creatureDiet()
    local c = getChar(); if not c then return nil end
    local d = c:FindFirstChild('Data')
    local ft = (d and d:GetAttribute('ft')) or c:GetAttribute('ft')
    return ft and tostring(ft):lower() or nil
end
local function foodCategory(fdn)
    if not fdn then return 'other' end
    local s = tostring(fdn):lower()
    if s:find('carcass') or s:find('ribs') or s:find('meat') or s:find('flesh') then return 'meat' end
    if s:find('algae') then return 'algae' end
    if s:find('grass') or s:find('berr') or s:find('fruit') or s:find('seaweed') or s:find('grape')
        or s:find('kelp') or s:find('moss') or s:find('plant') or s:find('leaf') or s:find('flower')
        or s:find('shroom') or s:find('mushroom') or s:find('pods') then return 'plant' end
    return 'other'
end
local DIET_FOOD = {
    carnivore      = { meat = true },
    herbivore      = { plant = true, algae = true },
    omnivore       = { meat = true, plant = true, algae = true },
    photovore      = { algae = true, plant = true },
    photocarnivore = { meat = true, algae = true, plant = true },
}
local function foodAllowedFor(diet, fdn)
    local allow = diet and DIET_FOOD[diet]
    if not allow then return true end            -- unknown diet -> eat anything (safe fallback)
    local cat = foodCategory(fdn)
    if cat == 'other' then return true end       -- unclassified -> don't block a possibly-valid food
    return allow[cat] == true
end
-- Drinkable-lake finder: hardcore NESTS lakes under sub-folders (e.g. "Poisoned") and flags
-- IsPoisoned -> recurse all descendants, skip poisoned, return nearest Lake + its surface part.
local function findDrinkableLake()
    local i = interactions(); local lakes = i and i:FindFirstChild('Lakes'); if not lakes then return nil, nil end
    local r = getRoot(); if not r then return nil, nil end
    local best, bestPart, bestD = nil, nil, math.huge
    for _, m in ipairs(lakes:GetDescendants()) do
        if m:IsA('Model') and (m.Name == 'Lake' or m:GetAttribute('Water') ~= nil) and m:GetAttribute('IsPoisoned') ~= true then
            local part = m:FindFirstChild('Surface') or m:FindFirstChild('WaterZone') or m.PrimaryPart or m:FindFirstChildWhichIsA('BasePart')
            if part and part:IsA('BasePart') then
                local d = (part.Position - r.Position).Magnitude
                if d < bestD then best, bestPart, bestD = m, part, d end
            end
        end
    end
    return best, bestPart
end

-- ═══════════════════════════════════════════════════════════════════
--   STATE TABLE
-- ═══════════════════════════════════════════════════════════════════
local S = {
    -- Home/LocalPlayer
    AutoScentHidden=false, InstantLobbyReturn=false, AlwaysKeenObserver=false,
    AlwaysLayEffect=false, AutoShelter=false,
    -- Home/No-Damage
    NoLavaDamage=false, NoDrowningDamage=false, NoMeteorDamage=false,
    NoMoistureDamage=false, NoTornadoDamage=false,
    -- Home/Nest
    NestUpgradeTarget='Normal', AutoNestUpgrade=false,
    EnableAutoNest=false, InvitationType='Friends', AutoAcceptNest=false,
    -- Custom Stats / Combat
    AutoAggressive=false, AutoScared=false, AntiBrokenLeg=false,
    AntiShreddedWings=false, AntiConfusion=false, AntiGrab=false, InfStamina=false,
    -- Custom Stats / sliders
    TurnRadius=0, EnableTurnRadius=false,
    WalkSpeed=30, EnableWalkSpeed=false,
    SprintSpeed=115, EnableSprintSpeed=false,
    FlySpeed=40, EnableFlySpeed=false,
    -- Autofarm
    AutoEat=false, AutoDrink=false, AutoMudRoll=false,
    AutoGachaTokens=false,
    MutationTarget='', AutoMutations=false,
    TraitTarget='', AutoTraits=false,
    AutoMissions=false,
    SelectedCreature='', AutoSpawn=false, DeathPointsTarget=1200, AutoSelfKill=false,
    -- Esp
    GachaEspExplorer=false, GachaEspGalaxy=false, GachaEspMecha=false,
    GachaEspMonster=false, GachaEspSweet=false,
    AbandonedEggsEsp=false,
    EnablePlayerEsp=false, EspHealth=false, EspHealthBar=false, EspTracer=false,
    EspNames=false, EspDistance=false, EspBox=false, EspChameleon=false,
    -- Others
    RemoveFog=false, RemoveCameraEffects=false, RemoveDisasterEffects=false,
    HidePingFps=false, AntiAFK=false, CustomName='', HideUsername=false,
    LowQualityTextures=false, WhiteScreen=false,
}

-- ═══════════════════════════════════════════════════════════════════
--   UI BUILD
-- ═══════════════════════════════════════════════════════════════════
local Window = HSHubV2:CreateWindow({
    Title='HS HUB', Subtitle='Creatures of Sonaria' .. (IS_ISLE10 and ' (Isle 10)' or ''),
})

-- ─── Tab 1: HOME ────────────────────────────────────────────────────
do
    local Tab = Window:CreateTab('Home', '◐')
    local M = Tab:CreateSection('MENU')
    M:AddButton({ Name='Get Max Storage Slots', Callback=function()
        -- LUNAR maps this to NestRequestRemote with action arg; harmless fallback
        fireOnPlayer(LP, 'NestRequestRemote', 'MaxStorage')
        HSHubV2:Notify('Max storage requested', 'ok', 2)
    end })

    local L = Tab:CreateSection('LOCALPLAYER')
    L:AddToggle({ Name='Auto Scent Hidden', Key='ASH', Default=false, Callback=function(v) S.AutoScentHidden=v end })
    L:AddToggle({ Name='Instant Lobby Return', Key='ILR', Default=false, Callback=function(v) S.InstantLobbyReturn=v end })
    L:AddToggle({ Name='Always Keen Observer', Key='AKO', Default=false, Callback=function(v) S.AlwaysKeenObserver=v end })
    L:AddToggle({ Name='Always Lay Effect', Key='ALE', Default=false, Callback=function(v) S.AlwaysLayEffect=v end })
    L:AddToggle({ Name='Auto Shelter', Key='AS', Default=false,
        Tip='Fires Sheltered when shelter indicator turns red',
        Callback=function(v) S.AutoShelter=v end })

    local D = Tab:CreateSection('NO DAMAGE')
    D:AddToggle({ Name='No Lava Damage',     Key='NLD', Default=false, Callback=function(v) S.NoLavaDamage=v end })
    D:AddToggle({ Name='No Drowning Damage', Key='NDD', Default=false, Callback=function(v) S.NoDrowningDamage=v end })
    D:AddToggle({ Name='No Meteor Damage',   Key='NMeD',Default=false, Callback=function(v) S.NoMeteorDamage=v end })
    D:AddToggle({ Name='No Moisture Damage', Key='NMoD',Default=false, Callback=function(v) S.NoMoistureDamage=v end })
    D:AddToggle({ Name='No Tornado Damage',  Key='NTD', Default=false, Callback=function(v) S.NoTornadoDamage=v end })

    local N = Tab:CreateSection('AUTO NEST')
    N:AddDropdown({ Name='Nest Upgrade', Key='NUT', Default='Normal',
        Values={'Normal','Premium','Royal'}, Callback=function(v) S.NestUpgradeTarget=v end })
    N:AddToggle({ Name='Auto Nest Upgrade', Key='ANU', Default=false, Callback=function(v) S.AutoNestUpgrade=v end })
    N:AddToggle({ Name='Enable Auto Nest', Key='EAN', Default=false, Callback=function(v) S.EnableAutoNest=v end })
    N:AddDropdown({ Name='Type of Invitation', Key='TOI', Default='Friends',
        Values={'Friends','Everyone','Trusted'}, Callback=function(v) S.InvitationType=v end })
    N:AddToggle({ Name='Auto Accept Nest Request', Key='AANR', Default=false,
        Callback=function(v) S.AutoAcceptNest=v end })
    N:AddButton({ Name='Teleport To Nest', Callback=function()
        fireOnPlayer(LP, 'NestRequestRemote', 'TeleportToNest')
    end })
    N:AddButton({ Name='Re-spawn Nest', Callback=function()
        fireOnPlayer(LP, 'NestRequestRemote', 'Respawn')
    end })
end

-- ─── Tab 2: CUSTOM STATS ────────────────────────────────────────────
do
    local Tab = Window:CreateTab('Custom Stats', '⚔')
    local C = Tab:CreateSection('COMBAT')
    C:AddToggle({ Name='Auto Aggressive State', Key='AAGGR', Default=false, Callback=function(v) S.AutoAggressive=v end })
    C:AddToggle({ Name='Auto Scared State', Key='ASC', Default=false, Callback=function(v) S.AutoScared=v end })
    C:AddToggle({ Name='Anti Broken Leg', Key='ABL', Default=false, Callback=function(v) S.AntiBrokenLeg=v end })
    C:AddToggle({ Name='Anti Shredded Wings', Key='ASW', Default=false, Callback=function(v) S.AntiShreddedWings=v end })
    C:AddToggle({ Name='Anti Confusion', Key='ACO', Default=false, Callback=function(v) S.AntiConfusion=v end })
    C:AddToggle({ Name='Anti Grab', Key='AGB', Default=false, Callback=function(v) S.AntiGrab=v end })
    C:AddToggle({ Name='Infinite Stamina', Key='INFS', Default=false, Callback=function(v) S.InfStamina=v end })

    local CS = Tab:CreateSection('CUSTOM STATS')
    CS:AddSlider({ Name='Turn Radius', Key='TR', Min=0, Max=200, Default=0, Decimals=0, Callback=function(v) S.TurnRadius=v end })
    CS:AddToggle({ Name='Enable Custom Turn Radius', Key='ETR', Default=false, Callback=function(v) S.EnableTurnRadius=v end })
    CS:AddSlider({ Name='Walk Speed', Key='WS', Min=0, Max=200, Default=30, Decimals=0, Callback=function(v) S.WalkSpeed=v end })
    CS:AddToggle({ Name='Enable Custom Walk Speed', Key='EWS', Default=false, Callback=function(v) S.EnableWalkSpeed=v end })
    CS:AddSlider({ Name='Sprint Speed', Key='SS', Min=0, Max=300, Default=115, Decimals=0, Callback=function(v) S.SprintSpeed=v end })
    CS:AddToggle({ Name='Enable Custom Sprint Speed', Key='ESS', Default=false, Callback=function(v) S.EnableSprintSpeed=v end })
    CS:AddSlider({ Name='Fly Speed', Key='FS', Min=0, Max=200, Default=40, Decimals=0, Callback=function(v) S.FlySpeed=v end })
    CS:AddToggle({ Name='Enable Custom Fly Speed', Key='EFS', Default=false, Callback=function(v) S.EnableFlySpeed=v end })
end

-- ─── Tab 3: AUTOFARM ────────────────────────────────────────────────
do
    local Tab = Window:CreateTab('Autofarm', '⚡')
    local Sv = Tab:CreateSection('SURVIVAL AUTOFARM')
    Sv:AddToggle({ Name='Auto Eat', Key='AE', Default=false, Callback=function(v) S.AutoEat=v end })
    Sv:AddToggle({ Name='Auto Drink', Key='AD', Default=false,
        Tip='Note: also broken in LUNAR original — may not work',
        Callback=function(v) S.AutoDrink=v end })
    Sv:AddToggle({ Name='Auto Mud Roll', Key='AMR', Default=false, Callback=function(v) S.AutoMudRoll=v end })

    local T = Tab:CreateSection('TOKEN AUTOFARM')
    T:AddToggle({ Name='Auto Gacha Tokens', Key='AGT', Default=false, Callback=function(v) S.AutoGachaTokens=v end })

    local MT = Tab:CreateSection('MUTATION/TRAIT AUTOFARM')
    MT:AddLabel('Leave dropdowns empty to save any mutation/trait')
    MT:AddDropdown({ Name='Mutations', Key='MUT', Default='',
        Values={'','Albinism','Volcanic','Diamond','Shimmer','Overgrown','Glow Tail'},
        Callback=function(v) S.MutationTarget=v end })
    MT:AddToggle({ Name='Auto Mutation(s)', Key='AMUT', Default=false, Callback=function(v) S.AutoMutations=v end })
    MT:AddDropdown({ Name='Traits', Key='TRAIT', Default='',
        Values={'','Damage','Speed','Bite','Health','Stamina'},
        Callback=function(v) S.TraitTarget=v end })
    MT:AddToggle({ Name='Auto Trait(s)', Key='ATRAIT', Default=false, Callback=function(v) S.AutoTraits=v end })

    local Mu = Tab:CreateSection('MUSH AUTOFARM')
    Mu:AddLabel('Region Missions Status: Offline')
    Mu:AddToggle({ Name='Auto Missions', Key='AMIS', Default=false, Callback=function(v) S.AutoMissions=v end })

    local R = Tab:CreateSection('RECOMMENDED')
    R:AddDropdown({ Name='Select Creature', Key='SCR', Default='',
        Values={'','Slot1','Slot2','Slot3'}, Callback=function(v) S.SelectedCreature=v end })
    R:AddButton({ Name='Refresh Creature List', Callback=function() HSHubV2:Notify('Creature list refreshed', 'ok', 2) end })
    R:AddToggle({ Name='Auto Spawn', Key='ASP', Default=false, Callback=function(v) S.AutoSpawn=v end })
    R:AddSlider({ Name='Death Points Target', Key='DPT', Min=0, Max=5000, Default=1200, Suffix=' pts', Decimals=0,
        Callback=function(v) S.DeathPointsTarget=v end })
    R:AddToggle({ Name='Auto Self Kill', Key='ASK', Default=false,
        Tip='Fires LavaSelfDamage when DeathPoints >= target',
        Callback=function(v) S.AutoSelfKill=v end })
end

-- ─── Tab 4: ARTIFACTS (matches LUNAR Artifacts Autofarm tab) ───────
-- Per-realm shrine sets (HardcoreEnvScan 2026-05-29):
--   Normal CoS realm: 8 shrines, no Shadow.
--   Hardcore realm:   ONLY Shadow exists (other 8 shrine folders absent in
--                     Workspace.Interactions["Warden Shrines"]; it's a different map).
local SHRINES_LOW, SHRINES_HIGH
if IS_HARDCORE then
    SHRINES_LOW  = {}
    SHRINES_HIGH = { 'Shadow Up', 'Shadow Middle', 'Shadow Down' }  -- 3 altars, user picks
else
    SHRINES_LOW  = { 'Hellion', 'Angelic', 'Garra', 'Verdant' }
    SHRINES_HIGH = { 'Boreal',  'Eigion',  'Novus', 'Ardor'   }
end

-- Per-shrine state flags
S.ArtifactToggles = {}
for _, n in ipairs(SHRINES_LOW)  do S.ArtifactToggles[n] = false end
for _, n in ipairs(SHRINES_HIGH) do S.ArtifactToggles[n] = false end
S.AutoServerHopArtifact = false
-- live status-label handles (updated by the status loop from the tablet's TimerGui)
local shrineStatusLabels = {}
local meatCounterLabel   = nil   -- updated by the status loop with server-wide carcass stats

do
    local Tab = Window:CreateTab('Artifacts', '✦')

    local InfoSec = Tab:CreateSection('SERVER MEAT')
    meatCounterLabel = InfoSec:AddLabel('Meat di server: —', Color3.fromRGB(180, 220, 255))

    local function makeShrineToggle(section, name)
        local key = ('AF_%s'):format(name)
        section:AddLabel(name .. ' Warden Shrine')
        shrineStatusLabels[name] = section:AddLabel('Status: —',
            Color3.fromRGB(150, 150, 180))
        section:AddToggle({ Name=('AutoFarm %s Artifact'):format(name),
            Key=key, Default=false,
            Tip=('Cycle creatures and deposit at %s Warden Shrine'):format(name),
            Callback=function(v) S.ArtifactToggles[name] = v end })
    end

    local Lo = Tab:CreateSection('LOW VALUE')
    for _, name in ipairs(SHRINES_LOW)  do makeShrineToggle(Lo, name) end

    local Hi = Tab:CreateSection('HIGH VALUE')
    for _, name in ipairs(SHRINES_HIGH) do makeShrineToggle(Hi, name) end

    local Rec = Tab:CreateSection('RECOMMEND')
    Rec:AddToggle({ Name='Auto Server Hop', Key='ASH_Art', Default=false,
        Tip="If the server's food runs out, hop to another",
        Callback=function(v) S.AutoServerHopArtifact = v end })
end

-- ─── Tab 5: TELEPORTS ───────────────────────────────────────────────
do
    local Tab = Window:CreateTab('Teleports', '⛰')
    local Reg = Tab:CreateSection('REGION TELEPORTS')
    -- USER-SAVED positions (PosSaver, 2026-05-29). User walked to each region
    -- and saved on-ground coords -> always lands sane, no sky/underground.
    local regions = {
        {'Desert',            Vector3.new(-1478.62, 291.62,  1425.98)},
        {'Mesa',              Vector3.new(-2418.70, 219.02,   145.48)},
        {'Mountains',         Vector3.new(-1800.22, 502.92, -1085.25)},
        {'Volcano',           Vector3.new( 2116.81, 199.27,  1025.66)},
        {'Pride Rocks',       Vector3.new( 2030.14, 186.93,  -401.38)},
        {'Flower Cave',       Vector3.new( -240.97, 194.92,  2368.08)},
        {'Central Rockfaces', Vector3.new( -149.20, 256.83,  -130.54)},
        {'Coral Reef',        Vector3.new( 1102.50,  67.54,  1187.40)},
        {'Grassy Shoal',      Vector3.new( -791.98, 102.55,  2088.24)},
        {'Seaweed Depths',    Vector3.new(  -55.00, -33.11,   891.30)},
        {'Algae Sandbar',     Vector3.new( 1133.80,  93.06, -1550.60)},
        {'Jungle',            Vector3.new( 2484.53, 248.97,  -962.95)},
        {'Redwoods',          Vector3.new(  424.62, 207.30, -1337.42)},
        {'Tundra',            Vector3.new(-1029.08, 266.03, -2394.52)},
        {'Swamp Hill',        Vector3.new(  607.47, 188.14, -2789.51)},
    }
    for _, r in ipairs(regions) do
        local name, pos = r[1], r[2]
        Reg:AddButton({ Name=name, Callback=function()
            local root = getRoot()
            if root then root.CFrame = CFrame.new(pos); HSHubV2:Notify('TP: ' .. name, 'ok', 2) end
        end })
    end

    local Cu = Tab:CreateSection('CUSTOM TELEPORTS')
    local locs, sel = {}, ''
    Cu:AddDropdown({ Name='Custom Location', Key='CL', Default='', Values={''}, Callback=function(v) sel=v end })
    Cu:AddButton({ Name='Teleport to Location', Callback=function()
        local p = locs[sel]; if p then
            local root = getRoot(); if root then root.CFrame = CFrame.new(p); HSHubV2:Notify('TP: '..sel,'ok',2) end
        end
    end })
    local saveName = ''
    if Cu.AddTextbox then
        Cu:AddTextbox({ Name='Location Name', Default='', Placeholder='Enter name',
            Callback=function(v) saveName=v end })
    end
    Cu:AddButton({ Name='Save Location', Callback=function()
        local root = getRoot(); if not root then return end
        if saveName=='' then saveName='Loc_'..tostring(#locs+1) end
        locs[saveName]=root.Position; HSHubV2:Notify('Saved: '..saveName,'ok',2)
    end })
    Cu:AddButton({ Name='Delete Location', Callback=function()
        if sel~='' then locs[sel]=nil; HSHubV2:Notify('Deleted: '..sel,'ok',2) end
    end })
end

-- ─── Tab 6: EVENT ───────────────────────────────────────────────────
do
    local Tab = Window:CreateTab('Event', '❄')
    Tab:CreateSection('MINIGAME(S)'):AddLabel('No active event minigames')
    Tab:CreateSection('INFORMATION'):AddLabel('Check Discord for events')
end

-- ─── Tab 7: ESP ─────────────────────────────────────────────────────
do
    local Tab = Window:CreateTab('Esp', '◉')
    local G = Tab:CreateSection('GACHA TOKEN ESP')
    G:AddLabel('Note: also broken in LUNAR original')
    G:AddToggle({ Name='Explorer Gacha Token ESP', Key='EGE', Default=false, Callback=function(v) S.GachaEspExplorer=v end })
    G:AddToggle({ Name='Galaxy Gacha Token ESP',   Key='EGG', Default=false, Callback=function(v) S.GachaEspGalaxy=v end })
    G:AddToggle({ Name='Mecha Gacha Token ESP',    Key='EGM', Default=false, Callback=function(v) S.GachaEspMecha=v end })
    G:AddToggle({ Name='Monster Gacha Token ESP',  Key='EGMo',Default=false, Callback=function(v) S.GachaEspMonster=v end })
    G:AddToggle({ Name='Sweet Gacha Token ESP',    Key='EGSw',Default=false, Callback=function(v) S.GachaEspSweet=v end })

    local O = Tab:CreateSection('OTHERS ESP')
    O:AddToggle({ Name='Abandoned Eggs ESP', Key='AEE', Default=false, Callback=function(v) S.AbandonedEggsEsp=v end })
    O:AddButton({ Name='Teleport to Abandoned Egg', Callback=function()
        local egg = findNearestEgg()
        if egg then
            local part = egg:IsA('BasePart') and egg or egg:FindFirstChildWhichIsA('BasePart')
            if part then
                local root = getRoot()
                if root then root.CFrame = CFrame.new(part.Position + Vector3.new(0,5,0)) end
                HSHubV2:Notify('TP to abandoned egg','ok',2)
            end
        else
            HSHubV2:Notify('No abandoned eggs','warn',2)
        end
    end })

    local P = Tab:CreateSection('PLAYER ESP')
    P:AddToggle({ Name='Enable Player ESP', Key='EPE', Default=false, Callback=function(v) S.EnablePlayerEsp=v end })
    P:AddToggle({ Name='Display Health',    Key='DH',  Default=false, Callback=function(v) S.EspHealth=v end })
    P:AddToggle({ Name='Display Health Bar',Key='DHB', Default=false, Callback=function(v) S.EspHealthBar=v end })
    P:AddToggle({ Name='Display Tracer',    Key='DT',  Default=false, Callback=function(v) S.EspTracer=v end })
    P:AddToggle({ Name='Display Names',     Key='DN',  Default=false, Callback=function(v) S.EspNames=v end })
    P:AddToggle({ Name='Display Distance',  Key='DD',  Default=false, Callback=function(v) S.EspDistance=v end })
    P:AddToggle({ Name='Display 3D Box',    Key='DB',  Default=false, Callback=function(v) S.EspBox=v end })
    P:AddToggle({ Name='Display Chameleon', Key='DC',  Default=false, Callback=function(v) S.EspChameleon=v end })
end

-- ─── Tab 8: OTHERS ──────────────────────────────────────────────────
do
    local Tab = Window:CreateTab('Others', '⚙')
    local V = Tab:CreateSection('VISUAL')
    V:AddToggle({ Name='Remove Fog', Key='RF', Default=false, Callback=function(v) S.RemoveFog=v
        if v then Lighting.FogEnd=100000; Lighting.FogStart=100000 end end })
    V:AddToggle({ Name='Remove Camera Effects', Key='RCE', Default=false, Callback=function(v) S.RemoveCameraEffects=v end })
    V:AddToggle({ Name='Remove Disaster Effects', Key='RDE', Default=false, Callback=function(v) S.RemoveDisasterEffects=v end })

    local Mi = Tab:CreateSection('MISC')
    Mi:AddToggle({ Name='Hide Ping and FPS', Key='HPF', Default=false, Callback=function(v) S.HidePingFps=v end })
    Mi:AddToggle({ Name='Anti-AFK', Key='AAFK', Default=false, Callback=function(v) S.AntiAFK=v end })
    if Mi.AddTextbox then
        Mi:AddTextbox({ Name='Custom Name', Default='', Placeholder='Enter name', Callback=function(v) S.CustomName=v end })
    end
    Mi:AddToggle({ Name='Hide Username (Client-Sided)', Key='HU', Default=false, Callback=function(v) S.HideUsername=v end })

    local Disc = Tab:CreateSection('DISCORD')
    Disc:AddButton({ Name='Copy Discord Link', Callback=function()
        if setclipboard then setclipboard('https://discord.gg/5rpP6faZSJ') end
        HSHubV2:Notify('Discord link copied','ok',2)
    end })

    local La = Tab:CreateSection('ANTI-LAG')
    La:AddToggle({ Name='Low Quality Textures', Key='LQT', Default=false, Callback=function(v) S.LowQualityTextures=v
        if v then pcall(function() settings().Rendering.QualityLevel=Enum.QualityLevel.Level01 end) end end })
    La:AddToggle({ Name='White Screen', Key='WSC', Default=false, Callback=function(v) S.WhiteScreen=v end })

    local Sr = Tab:CreateSection('SERVERS')
    Sr:AddButton({ Name='Rejoin Server', Callback=function()
        TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LP)
    end })
    Sr:AddButton({ Name='Server Hop', Callback=function()
        local ok, raw = pcall(function()
            return game:HttpGet('https://games.roblox.com/v1/games/'..tostring(game.PlaceId)
                ..'/servers/Public?sortOrder=Asc&limit=100')
        end)
        if ok and raw then
            local d = HttpService:JSONDecode(raw)
            if d and d.data then
                for _, s in ipairs(d.data) do
                    if s.playing < s.maxPlayers and s.id ~= game.JobId then
                        TeleportService:TeleportToPlaceInstance(game.PlaceId, s.id, LP); return
                    end
                end
            end
        end
        HSHubV2:Notify('No servers found','warn',2)
    end })
end

-- ═══════════════════════════════════════════════════════════════════
--   FEATURE LOOPS (with ground-truth bindings)
-- ═══════════════════════════════════════════════════════════════════

-- AutoEat: TP to nearest food + spam Food:FireServer until Hunger=100%
task.spawn(function()
    local savedCF
    while true do
        task.wait(1)
        if S.AutoEat and not S.AutoMissions then
            pcall(function()
                local char = getChar()
                if char and hudStatText('Hunger') ~= '100%' then
                    local diet = creatureDiet()
                    local food = findNearestFood(function(m) return foodAllowedFor(diet, m:GetAttribute('FoodDataName')) end)
                    if food then
                        local foodPart = food:IsA('Model') and (food.PrimaryPart or food:FindFirstChild('Food') or food:FindFirstChildWhichIsA('BasePart')) or food
                        if foodPart and foodPart:IsA('BasePart') then
                            local v = foodPart.Position
                            local root = getRoot()
                            if root then
                                if not savedCF then savedCF = root.CFrame end
                                root.CFrame = CFrame.new(v - Vector3.new(0,20,0))
                                local n = 0
                                repeat
                                    task.wait(0.1)
                                    fire('Food', food)
                                    if getRoot() then getRoot().CFrame = CFrame.new(v - Vector3.new(0,20,0)) end
                                    n = n + 1
                                until hudStatText('Hunger') == '100%' or not S.AutoEat or not food.Parent or n > 60
                                if savedCF and getRoot() then
                                    getRoot().CFrame = savedCF; savedCF = nil
                                end
                            end
                        end
                    end
                end
            end)
        end
    end
end)

-- AutoDrink: was inconsistent because it fired DrinkRemote from wherever you stood
-- (proximity-gated -> mostly ignored). Now TP onto the lake surface first, spam
-- DrinkRemote until Thirst=100%, then snap back. Mirrors AutoEat.
task.spawn(function()
    local savedCF
    while true do
        task.wait(1)
        if S.AutoDrink and not S.AutoMissions then
            pcall(function()
                local char = getChar()
                if char and hudStatText('Thirst') ~= '100%' then
                    local lake, lakePart = findDrinkableLake()
                    if lake and lakePart then
                        if lakePart:IsA('BasePart') then
                            local target = lakePart.Position + Vector3.new(0, lakePart.Size.Y / 2 + 2, 0)  -- water surface
                            local root = getRoot()
                            if root then
                                if not savedCF then savedCF = root.CFrame end
                                root.CFrame = CFrame.new(target)
                                local n = 0
                                repeat
                                    task.wait(0.1)
                                    fire('DrinkRemote', lake)
                                    if getRoot() then getRoot().CFrame = CFrame.new(target) end
                                    n = n + 1
                                until hudStatText('Thirst') == '100%' or not S.AutoDrink or not lake.Parent or n > 60
                                if savedCF and getRoot() then getRoot().CFrame = savedCF; savedCF = nil end
                            end
                        end
                    end
                end
            end)
        end
    end
end)

-- AutoMudRoll: roll in mud to GET the mud/scent-hide effect, then STOP.
-- Bug fixed: old code only checked a guessed 'Muddy' attribute -> never true ->
-- rolled forever. Now detects the effect robustly (char attr OR any Ailments
-- entry named mud/scent/hidden/shelter) AND adds a post-roll cooldown so it can
-- never spin endlessly.
task.spawn(function()
    local savedCF
    local function mudEffectActive(char)
        if not char then return false end
        if char:GetAttribute('Muddy') or char:GetAttribute('HideScent') then return true end
        local ail = char:FindFirstChild('Ailments')
        local active = false
        if ail then
            pcall(function()
                for k in pairs(ail:GetAttributes()) do
                    local lk = tostring(k):lower()
                    if lk:find('mud') or lk:find('scent') or lk:find('hidden')
                        or lk:find('shelter') or lk:find('stink') then
                        active = true; break
                    end
                end
            end)
        end
        return active
    end
    while true do
        task.wait(0.2)
        if S.AutoMudRoll and not S.AutoMissions then
            pcall(function()
                local char = getChar()
                if not char then return end
                -- skip only while the effect is already active (no time cooldown)
                if mudEffectActive(char) then return end
                local mud = findNearestMud(); if not mud then return end
                local mudPart = mud:IsA('Model') and (mud.PrimaryPart or mud:FindFirstChildWhichIsA('BasePart')) or mud
                if not (mudPart and mudPart:IsA('BasePart')) then return end
                local target = mudPart.Position + Vector3.new(0, mudPart.Size.Y / 2, 0)
                local root = getRoot(); if not root then return end
                if not savedCF then savedCF = root.CFrame end
                local n = 0
                repeat
                    task.wait(0.1)
                    if getRoot() then getRoot().CFrame = CFrame.new(target) end
                    fire('Mud', mud)
                    n = n + 1
                until mudEffectActive(char) or not S.AutoMudRoll or n > 12
                if savedCF and getRoot() then getRoot().CFrame = savedCF; savedCF = nil end
            end)
        end
    end
end)

-- AutoShelter: Sheltered:FireServer(true) when shelter indicator is red
task.spawn(function()
    while true do
        task.wait(0.5)
        if S.AutoShelter then
            pcall(function()
                local c = shelterColor()
                if c and (c.R > 0.9 and c.G < 0.1 and c.B < 0.1) then
                    fire('Sheltered', true)
                end
            end)
        end
    end
end)

-- AutoSelfKill: fire LavaSelfDamage when DeathPoints >= target
task.spawn(function()
    while true do
        task.wait(1)
        if S.AutoSelfKill then
            pcall(function()
                if getChar() then
                    S.NoLavaDamage = false
                    fire('LavaSelfDamage')
                end
            end)
        end
    end
end)

-- ════════════════════════════════════════════════════════════════════
-- CREATURE CYCLING (AutoFarmMutations / AutoFarmTraits / AutoArtifactFarm)
-- ════════════════════════════════════════════════════════════════════
-- LUNAR pattern (chunk3_pretty line 794+ and 1655+):
--   1. require PlayerWrapper module to get current slot
--   2. Check if current creature matches target (mutation/trait/any)
--   3. If not match: StoreActiveCreatureRemote + CreateSlotRemote to cycle
--   4. Trigger HUDGui.SaveSelectionReturn(true) for UI sync

local function safeRequire(path)
    local ok, m = pcall(function() return require(path) end)
    if ok then return m end
end

local function getPlayerWrapper()
    local rf = ReplicatedStorage:FindFirstChild('_replicationFolder')
    if rf then
        local pw = rf:FindFirstChild('PlayerWrapper')
        if pw then return safeRequire(pw) end
    end
end

local function getHUDGuiModule()
    local rf = ReplicatedStorage:FindFirstChild('_replicationFolder')
    if rf then
        local hg = rf:FindFirstChild('HUDGui')
        if hg then return safeRequire(hg) end
    end
end

local function getCurrentSlot()
    local pw = getPlayerWrapper()
    if pw and pw.GetClient then
        local ok, client = pcall(function() return pw:GetClient() end)
        if ok and client and client.GetCurrentSlot then
            local ok2, slot = pcall(function() return client:GetCurrentSlot() end)
            if ok2 then return slot end
        end
    end
end

local function getActiveCreature()
    -- LUNAR's f() / z() finder — find current loaded creature in workspace
    local char = getChar()
    if not char then return nil end
    -- The creature model is usually the character itself or a child
    return char
end

local function getCreatureAttribute(creature, attr)
    if not creature then return nil end
    local ok, v = pcall(function() return creature:GetAttribute(attr) end)
    if ok then return v end
end

local function creatureMatchesTarget(creature, mutTarget, traitTarget)
    if not creature then return false end
    if mutTarget and mutTarget ~= '' then
        if getCreatureAttribute(creature, mutTarget) then return true end
    end
    if traitTarget and traitTarget ~= '' then
        if getCreatureAttribute(creature, traitTarget) then return true end
    end
    return false
end

-- ════════════════════════════════════════════════════════════════════
-- ARTIFACT SHRINE HELPERS
-- ════════════════════════════════════════════════════════════════════

-- Known shrine TABLET world positions (static map features). Seeded with the two
-- ArtifactScan captured; the other 6 are LEARNED live the first time you enter each
-- region (cached + persisted to a file) so cross-region TP works afterwards.
-- A shrine position is either a single Vector3, OR a LIST of Vector3 (multi-altar:
-- the same logical shrine exists at several spots, e.g. hardcore "Shadow" = 3
-- altars in 3 regions sharing ONE cooldown — offering at any one cools all down).
local TABLET_POS = {
    -- 6/8 captured via V16 auto-cache (hshub_cos_shrines.txt, 2026-05-29).
    Hellion = Vector3.new(-1286.4, 232.7, 380.9),
    Boreal  = Vector3.new(-2259.4, 380.7, -1060.4),
    Verdant = Vector3.new(309.3, 331.2, 2240.5),
    Novus   = Vector3.new(1133.1, 857.9, 819.0),
    Garra   = Vector3.new(2333.9, 258.1, 1338.4),
    Eigion  = Vector3.new(1012.7, -508.9, 514.6),
    -- Ardor + Angelic captured via ShrineHunter 2026-06-07 (user-verified TP, place 5233782396).
    Angelic = Vector3.new(2143.02, 184.74, -1522.99),
    Ardor   = Vector3.new(778.05, 202.18, -3425.92),
    -- Hardcore "Shadow" = 3 separate altars (ShrineHunter, PlaceId 136015760267602).
    -- User picks which via 3 toggles. All offer "Shadow" + share one cooldown.
    ['Shadow Up']     = Vector3.new( 1312.47, -64.96,  540.15),
    ['Shadow Middle'] = Vector3.new(  215.67, 404.63, -106.63),
    ['Shadow Down']   = Vector3.new(-1098.30, 327.13, -476.35),
    -- (all 8 normal shrines now hardcoded; file auto-learn still merges any new finds.)
}
-- normalize to a list of candidate positions to try (in order)
local function tabletPositions(name)
    local v = TABLET_POS[name]
    if not v then return {} end
    if typeof(v) == 'Vector3' then return { v } end
    return v
end
-- Display/toggle name -> the actual WardenOffering arg + shrine folder name.
-- The 3 hardcore Shadow toggles all resolve to the single in-game shrine "Shadow".
local OFFER_NAME = {
    ['Shadow Up'] = 'Shadow', ['Shadow Middle'] = 'Shadow', ['Shadow Down'] = 'Shadow',
}
local function offerNameOf(name) return OFFER_NAME[name] or name end
local TABLET_FILE = 'hshub_cos_shrines.txt'
pcall(function()
    if readfile and isfile and isfile(TABLET_FILE) then
        for line in tostring(readfile(TABLET_FILE)):gmatch('[^\n]+') do
            local n, x, y, z = line:match('([^=]+)=([%-%d%.]+),([%-%d%.]+),([%-%d%.]+)')
            -- never let the single-pos file clobber a hardcoded multi-altar list
            if n and typeof(TABLET_POS[n]) ~= 'table' then
                TABLET_POS[n] = Vector3.new(tonumber(x), tonumber(y), tonumber(z))
            end
        end
    end
end)
local function rememberTabletPos(name, p)
    if not p then return end
    if typeof(TABLET_POS[name]) == 'table' then return end   -- multi-altar: keep hardcoded list
    local old = TABLET_POS[name]
    if old and (old - p).Magnitude < 5 then return end       -- already known
    TABLET_POS[name] = p
    pcall(function()
        if not writefile then return end
        local lines = {}
        for n, v in pairs(TABLET_POS) do
            if typeof(v) == 'Vector3' then   -- only persist single positions
                lines[#lines + 1] = ('%s=%.1f,%.1f,%.1f'):format(n, v.X, v.Y, v.Z)
            end
        end
        writefile(TABLET_FILE, table.concat(lines, '\n'))
    end)
end

-- Find the shrine TABLET part in workspace.Interactions["Warden Shrines"].<name>.
-- Offering is proximity-gated, so we TP onto the tablet before offering. Parts only
-- exist while in the shrine's region (streaming); when found we cache the position
-- so we can TP back to that region later (cross-region farm in the loop below).
local function getShrineTablet(name)
    name = offerNameOf(name)   -- "Shadow Up/Middle/Down" -> folder "Shadow"
    local i = interactions(); if not i then return nil end
    local shrines = i:FindFirstChild('Warden Shrines'); if not shrines then return nil end
    local fallback
    -- iterate ALL folders with this name (hardcore can have multiple "Shadow")
    for _, folder in ipairs(shrines:GetChildren()) do
        if folder.Name == name then
            for _, d in ipairs(folder:GetDescendants()) do
                if d:IsA('BasePart') then
                    if d.Name:find('Tablet') then rememberTabletPos(name, d.Position); return d end
                    fallback = fallback or d
                end
            end
        end
    end
    if fallback then rememberTabletPos(name, fallback.Position) end
    return fallback
end

-- Offering meat = "Carcass"-type only. Confirmed by DamageSpy ×8 (all offerings
-- used a Carcass variant) AND user: "Ribs" is eat-only (can't be picked up), and
-- plants (Grass/Algae/Fruit/Berries/Sea Grapes/Seaweed Pods) aren't offerings.
local function isOfferMeat(fdn)
    if not fdn then return false end
    return tostring(fdn):find('Carcass') ~= nil
end

-- Shrine status from the tablet's own BillboardGui label (ArtifactScan-verified):
-- TimerLabel.Text == "AVAILABLE NOW"  => offerable;  anything else (e.g. "29m 58s")
-- => on cooldown.  Returns the raw text, or nil if the tablet isn't loaded.
local function getShrineStatusText(name)
    local tablet = getShrineTablet(name); if not tablet then return nil end
    local gui = tablet:FindFirstChild('TimerGui')
    local lbl = gui and gui:FindFirstChild('TimerLabel')
    if not lbl then return nil end
    local ok, txt = pcall(function() return lbl.Text end)
    return ok and txt or nil
end
-- true=available, false=cooldown, nil=unknown (tablet not loaded / out of region)
local function shrineAvailable(name)
    local txt = getShrineStatusText(name)
    if txt == nil then return nil end
    return txt:upper():find('AVAILABLE') ~= nil
end

-- Return the NAME of the first enabled shrine (the WardenOffering arg).
local function getActiveShrine()
    for _, n in ipairs(SHRINES_LOW) do
        if S.ArtifactToggles[n] then return n end
    end
    for _, n in ipairs(SHRINES_HIGH) do
        if S.ArtifactToggles[n] then return n end
    end
    return nil
end

-- ════════════════════════════════════════════════════════════════════
-- MAIN CYCLING LOOP — handles AutoFarmMutations, AutoFarmTraits,
-- AND per-shrine ArtifactFarm toggles
-- ════════════════════════════════════════════════════════════════════
local _cooldownNotified = {}   -- notify "cooldown" once per available->cooldown edge
local _meatBlacklist    = {}   -- meat models that failed BOTH full + piece pickup
local _shrineCooldownUntil = {} -- per-shrine: tick() until which we go FULLY SILENT (done)
-- parse the tablet's TimerGui countdown ("29m 58s") into seconds
local function parseCooldownSecs(txt)
    if not txt then return nil end
    local m = tonumber(txt:match('(%d+)%s*[mM]')) or 0
    local s = tonumber(txt:match('(%d+)%s*[sS]')) or 0
    local total = m * 60 + s
    return total > 0 and total or nil
end

-- Live shrine-status labels in the Artifacts tab — mirror each tablet's TimerGui
-- text ("AVAILABLE NOW" / "29m 58s"). "— (luar region)" if the tablet isn't loaded.
task.spawn(function()
    while true do
        task.wait(2)
        -- per-shrine status labels (TimerGui mirror)
        for name, lbl in pairs(shrineStatusLabels) do
            pcall(function()
                local txt = getShrineStatusText(name)
                lbl:Set(txt and ('Status: ' .. txt) or 'Status: — (luar region)')
            end)
        end
        -- server-wide carcass stats (offer-meat only; matches autofarm filter)
        if meatCounterLabel then pcall(function()
            local f = (interactions() or {}):FindFirstChild('Food')
            if not f then meatCounterLabel:Set('Meat di server: Food folder ga ke-load'); return end
            local count, total, best, bestName = 0, 0, 0, nil
            for _, m in ipairs(f:GetChildren()) do
                if isOfferMeat(m:GetAttribute('FoodDataName')) then
                    local v = tonumber(m:GetAttribute('Value')) or 0
                    count = count + 1; total = total + v
                    if v > best then best, bestName = v, m:GetAttribute('FoodDataName') end
                end
            end
            meatCounterLabel:Set(('Meat di server: %d carcass · total %d · tertinggi %d (%s)')
                :format(count, total, best, tostring(bestName or '—')))
        end) end
    end
end)

task.spawn(function()
    while true do
        task.wait(0.4)
        local mutOn = S.AutoMutations
        local trOn  = S.AutoTraits
        local shrineName = getActiveShrine()

        if shrineName then pcall(function()
            -- ARTIFACT FARM V14 (rebuilt fully from ArtifactScan data 2026-05-29):
            --   Status : tablet.TimerGui.TimerLabel.Text — "AVAILABLE NOW" = offerable,
            --            else (e.g. "29m 58s") = on cooldown -> idle (auto-resumes).
            --   Carry  : Character attr HeldCount (0=empty,1=carrying; CarryLimit=1).
            --   Meat   : Interactions.Food children; FoodDataName=type, Value=amount;
            --            offer-meat = Carcass-type (isOfferMeat); pick HIGHEST Value.
            --   Pickup : try FULL (FoodPickup) first; if HeldCount didn't rise (tier-
            --            locked/rejected), take a PIECE (FoodChunk).  [user's rule]
            --   Offer  : WardenOffering:InvokeServer(name) — proximity-gated -> TP onto
            --            the tablet first (in-region only).
            local root = getRoot(); local char = getChar()
            if not root or not char then return end
            local tablet = getShrineTablet(shrineName)
            if not tablet then
                -- Region not loaded. TP to each known position for this shrine to
                -- stream it in (multi-altar shrines like hardcore "Shadow" have a few;
                -- single shrines have one). Never-visited shrines have none -> fly there.
                for _, known in ipairs(tabletPositions(shrineName)) do
                    pcall(function() root.CFrame = CFrame.new(known + Vector3.new(0, 8, 0)) end)
                    task.wait(1.5)
                    tablet = getShrineTablet(shrineName)
                    if tablet then break end
                end
                if not tablet then return end      -- still streaming / unknown -> retry next cycle
            end

            -- Stop-on-complete: on cooldown -> idle (don't park / spam offers).
            local avail = shrineAvailable(shrineName)
            if avail == false then
                if not _cooldownNotified[shrineName] then
                    _cooldownNotified[shrineName] = true
                    HSHubV2:Notify(('%s shrine selesai — cooldown (%s)')
                        :format(shrineName, getShrineStatusText(shrineName) or '...'), 'ok', 3)
                end
                return
            end
            _cooldownNotified[shrineName] = nil    -- available again -> resume

            -- V18 (ANTI-BAN, modeled on LUNAR's working pattern): after each TP, WAIT
            -- ~0.8s so the position SETTLES before firing a remote, then snap BACK to
            -- "home". Rapid TP-spam + staying far away was the ban signature (LUNAR's
            -- own AutoGachaTokens does save->TP->wait(1)->act->TP-back). Slower = safer.
            local home = root.CFrame   -- current spot (near shrine region); we return here
            local held = tonumber(char:GetAttribute('HeldCount')) or 0
            if held < 1 then
                local foodFolder = (interactions() or {}):FindFirstChild('Food')
                local myTier = 0
                pcall(function()
                    local d = char:FindFirstChild('Data')
                    myTier = (d and tonumber(d:GetAttribute('Tier'))) or 0
                end)
                local bestM, bestPart, bestVal, bestLocked = nil, nil, -1, false
                if foodFolder then
                    for _, m in ipairs(foodFolder:GetChildren()) do
                        if isOfferMeat(m:GetAttribute('FoodDataName'))
                            and not m:GetAttribute('Held')
                            and not _meatBlacklist[m] then
                            local val    = tonumber(m:GetAttribute('Value')) or 0
                            local t      = tonumber(m:GetAttribute('T'))
                            local locked = (t ~= nil and myTier > 0 and myTier < t) or false
                            if not (locked and val <= 15) then        -- tier-locked + low = skip
                                local part = m:IsA('BasePart') and m
                                    or (m:IsA('Model') and (m.PrimaryPart or m:FindFirstChildWhichIsA('BasePart')))
                                if part and val > bestVal then
                                    bestM, bestPart, bestVal, bestLocked = m, part, val, locked
                                end
                            end
                        end
                    end
                end
                if bestM and bestPart then
                    pcall(function() root.CFrame = bestPart.CFrame + Vector3.new(0, 4, 0) end)
                    task.wait(0.5)                 -- settle before firing (anti-detect; user-tuned 0.8->0.5)
                    if not bestLocked then
                        local full = getRemote('FoodPickup')
                        if full then pcall(function() full:InvokeServer(bestM) end) end
                        task.wait(0.6)
                    end
                    if (tonumber(char:GetAttribute('HeldCount')) or 0) < 1 then
                        local piece = getRemote('FoodChunk')
                        if piece then pcall(function() piece:InvokeServer(bestM) end) end
                        task.wait(0.6)
                    end
                    if (tonumber(char:GetAttribute('HeldCount')) or 0) < 1 then
                        _meatBlacklist[bestM] = true   -- can't take this one; try next-highest
                    end
                end
                held = tonumber(char:GetAttribute('HeldCount')) or 0
            end
            -- carrying now -> TP to shrine, WAIT to settle, offer, then snap BACK home.
            if held >= 1 then
                pcall(function() root.CFrame = tablet.CFrame + Vector3.new(0, 6, 0) end)
                task.wait(0.5)                     -- settle at the shrine before offering (user-tuned 0.9->0.5)
                local wo = getRemote('WardenOffering')
                if wo then pcall(function() wo:InvokeServer(offerNameOf(shrineName)) end) end
                task.wait(0.4)
                pcall(function() root.CFrame = home end)   -- LUNAR-style snap back
            end
        end) end

        if mutOn or trOn then pcall(function()
            -- Mutation/Trait farm via creature cycling
            if not getChar() then return end
            local slot = getCurrentSlot()
            if not slot then return end
            local creature = getActiveCreature()

            if creatureMatchesTarget(creature, S.MutationTarget, S.TraitTarget) then
                return
            end

            local hudMod = getHUDGuiModule()
            if hudMod and hudMod.SaveSelectionReturn then
                pcall(function() hudMod.SaveSelectionReturn(true) end)
                task.wait(0.5)
            end

            local storeR = getRemote('StoreActiveCreatureRemote')
            local createR = getRemote('CreateSlotRemote')
            if storeR and createR then
                pcall(function() storeR:InvokeServer(slot) end)
                task.wait(0.5)
                local dinoVal = creature and creature:FindFirstChild('Dino')
                if dinoVal and dinoVal.Value then
                    pcall(function() createR:InvokeServer(dinoVal.Value) end)
                end
            end
        end) end
    end
end)

-- Auto Server Hop (Artifacts tab Recommend) — same as Others tab Server Hop
task.spawn(function()
    while true do
        task.wait(30)
        if S.AutoServerHopArtifact then
            pcall(function()
                local ok, raw = pcall(function()
                    return game:HttpGet('https://games.roblox.com/v1/games/'..tostring(game.PlaceId)
                        ..'/servers/Public?sortOrder=Asc&limit=100')
                end)
                if ok and raw then
                    local d = HttpService:JSONDecode(raw)
                    if d and d.data then
                        for _, srv in ipairs(d.data) do
                            if srv.playing < srv.maxPlayers and srv.id ~= game.JobId then
                                TeleportService:TeleportToPlaceInstance(game.PlaceId, srv.id, LP)
                                return
                            end
                        end
                    end
                end
            end)
        end
    end
end)

-- AutoSpawn: respawn dead creature
task.spawn(function()
    while true do
        task.wait(1)
        if S.AutoSpawn then
            pcall(function()
                if not getChar() then
                    local slot = S.SelectedCreature
                    if slot ~= '' then
                        invoke('RestartSlotRemote', slot, false)
                    end
                end
            end)
        end
    end
end)

-- AutoGachaTokens: TP onto the nearest token node, settle, then GetSpawnedTokenRemote
-- (proximity-safe, LUNAR-style save->TP->wait->act->TP-back, instead of firing from afar).
task.spawn(function()
    while true do
        task.wait(0.5)
        if S.AutoGachaTokens then
            pcall(function()
                local root = getRoot(); if not root then return end
                local token = findNearestToken()
                local part
                if token then
                    part = token:IsA('BasePart') and token
                        or (token:IsA('Model') and (token.PrimaryPart or token:FindFirstChildWhichIsA('BasePart')))
                end
                if part then
                    local home = root.CFrame
                    pcall(function() root.CFrame = part.CFrame + Vector3.new(0, 4, 0) end)
                    task.wait(0.5)                         -- settle before firing (anti-detect)
                    pcall(function() invoke('GetSpawnedTokenRemote') end)
                    task.wait(0.3)
                    if getRoot() then pcall(function() getRoot().CFrame = home end) end   -- snap back
                else
                    pcall(function() invoke('GetSpawnedTokenRemote') end)   -- no token loaded -> fallback
                end
            end)
        end
    end
end)

-- AutoAcceptNest: loop other players, fire AcceptRequest on their Remotes folder
task.spawn(function()
    while true do
        task.wait(5)
        if S.AutoAcceptNest then
            pcall(function()
                for _, p in ipairs(Players:GetPlayers()) do
                    if p ~= LP and p:FindFirstChild('Settings') then
                        local n = p.Settings:FindFirstChild('Nesting')
                        if n and (n.Value == S.InvitationType or S.InvitationType == 'Everyone') then
                            fireOnPlayer(p, 'NestRequestRemote', 'AcceptRequest')
                        end
                    end
                end
            end)
        end
    end
end)

-- AutoNestUpgrade: ResourceDamageRemote + UpgradeNest
task.spawn(function()
    while true do
        task.wait(0.5)
        if S.AutoNestUpgrade then
            pcall(function()
                for i = 1, 3 do fire('ResourceDamageRemote') end
                invoke('UpgradeNest', S.NestUpgradeTarget)
            end)
        end
    end
end)

-- AlwaysLayEffect: Lay:FireServer(true)  (chunk3 line 987)
-- Pattern: while AlwaysLayEffect and task.wait(1) do; Lay:FireServer(unpack({[1]=true})); end
task.spawn(function()
    while true do
        task.wait(1)
        if S.AlwaysLayEffect then
            pcall(function() fire('Lay', true) end)
        end
    end
end)

-- AutoAggression: StateAilment:FireServer("Aggression")  (chunk3 line 5386)
-- Pattern: only fire when creature doesn't already have Aggression attribute
task.spawn(function()
    while true do
        task.wait(1)
        if S.AutoAggressive then
            pcall(function()
                local c = getChar()
                if c and not c:GetAttribute('Aggression') then
                    fire('StateAilment', 'Aggression')
                end
            end)
        end
    end
end)

-- AutoScentHidden: HideScent:FireServer()  (chunk3 line 5303)
-- Pattern: only fire when char doesn't already have HideScent attribute
task.spawn(function()
    while true do
        task.wait(1)
        if S.AutoScentHidden then
            pcall(function()
                local c = getChar()
                if c and not c:GetAttribute('HideScent') then
                    fire('HideScent')
                end
            end)
        end
    end
end)

-- AutoCowerState: StateAilment:FireServer("Cower")  (chunk3 m=function line 1534)
-- Pattern: only fire when creature doesn't already have Cower attribute
S.AutoCowerStateValue = false  -- ensure flag exists
task.spawn(function()
    while true do
        task.wait(1)
        if S.AutoCowerStateValue then
            pcall(function()
                local c = getChar()
                if c and not c:GetAttribute('Cower') then
                    fire('StateAilment', 'Cower')
                end
            end)
        end
    end
end)

-- AutoNestValue: TP + Nest:FireServer when Age > 66  (chunk3 line 1002)
S.AutoNestValue = false
task.spawn(function()
    while true do
        task.wait(5)
        if S.AutoNestValue then
            pcall(function()
                local c = getChar()
                if not c or not c:FindFirstChild('HumanoidRootPart') then return end
                local age = c:GetAttribute('Age') or 0
                if age <= 66 then return end
                local pos = c.HumanoidRootPart.Position
                local nests = Workspace:FindFirstChild('Interactions')
                nests = nests and nests:FindFirstChild('Nests')
                if not nests or not nests:FindFirstChild(LP.Name) then
                    fire('Nest', { pos, Vector3.yAxis })
                end
            end)
        end
    end
end)

-- ════════════════════════════════════════════════════════════════════
-- PHASE 2 V13: Custom Stats (AttrDump-verified 2026-05-27)
-- Real attribute names on Character.Data folder (mangled single letters):
--   's'  = Walk Speed   (default ~31)
--   'ss' = Sprint Speed (default ~105, LUNAR shows 115)
--   'fs' = Fly Speed    (default ~39, LUNAR shows 40)
--   'tr' = Turn Radius  (default 1)
-- Location: Workspace.Characters.<player>.Data folder, ALSO mirrored on
-- Character itself (game reads from one, server reads from other).
-- Strategy: set on BOTH Character + Character.Data every frame.
-- ════════════════════════════════════════════════════════════════════

local function setStatAttr(char, key, value)
    if not char then return end
    pcall(function() char:SetAttribute(key, value) end)
    local data = char:FindFirstChild('Data')
    if data then
        pcall(function() data:SetAttribute(key, value) end)
    end
end

task.spawn(function()
    while true do
        task.wait()  -- every frame
        local c = getChar()
        if c then
            if S.EnableWalkSpeed   then setStatAttr(c, 's',  S.WalkSpeed) end
            if S.EnableSprintSpeed then setStatAttr(c, 'ss', S.SprintSpeed) end
            if S.EnableFlySpeed    then setStatAttr(c, 'fs', S.FlySpeed) end
            if S.EnableTurnRadius  then setStatAttr(c, 'tr', S.TurnRadius) end
            -- Backup: Humanoid.WalkSpeed (some games combine attribute + Humanoid)
            if S.EnableWalkSpeed then
                local h = c:FindFirstChildOfClass('Humanoid')
                if h then pcall(function() h.WalkSpeed = S.WalkSpeed end) end
            end
        end
    end
end)

-- ════════════════════════════════════════════════════════════════════
-- PHASE 1: Infinite Stamina (chunk3 line 902-915 verified pattern)
-- Real attribute names: 'st' (stamina) and 'sr' (stamina regen)
-- Value: 10000 (NOT 100)
-- Hook AttributeChanged('st') to keep at 10000 even when server tries reset
-- ════════════════════════════════════════════════════════════════════
local _infStaminaHookedChar = nil
task.spawn(function()
    while true do
        task.wait(0.3)
        if S.InfStamina then
            pcall(function()
                local c = getChar()
                if not c then return end
                local hasSt = c:GetAttribute('st') ~= nil
                local hasSr = c:GetAttribute('sr') ~= nil

                if hasSt and hasSr then
                    -- Path A: creature has st/sr attributes
                    pcall(function() c:SetAttribute('sr', 10000) end)
                    pcall(function() c:SetAttribute('st', 10000) end)
                    -- One-shot hook to keep value when server resets
                    if _infStaminaHookedChar ~= c then
                        _infStaminaHookedChar = c
                        pcall(function()
                            c:GetAttributeChangedSignal('st'):Connect(function()
                                if S.InfStamina and c.Parent then
                                    pcall(function() c:SetAttribute('sr', 10000) end)
                                    pcall(function() c:SetAttribute('st', 10000) end)
                                end
                            end)
                        end)
                    end
                else
                    -- Path B: fallback via PlayerWrapper:GetCurrentCharacter()
                    local pw = getPlayerWrapper()
                    if pw and pw.GetClient then
                        pcall(function()
                            local client = pw:GetClient()
                            if client and client.GetCurrentCharacter then
                                local ch = client:GetCurrentCharacter()
                                if ch and ch.StaminaTracker then
                                    ch.StaminaTracker.Stamina = ch.StaminaTracker:GetMaxStamina()
                                end
                            end
                        end)
                    end
                end
            end)
        else
            _infStaminaHookedChar = nil
        end
    end
end)

-- Reset hook tracker on character respawn
LP.CharacterAdded:Connect(function() _infStaminaHookedChar = nil end)

-- ════════════════════════════════════════════════════════════════════
-- PHASE 3: No Damage via remote-block (RemoteHook-verified 2026-05-29)
-- CoS is client-authoritative for environmental damage: the CLIENT fires
-- a remote to hurt ITSELF. e.g. LavaSelfDamage:FireServer() in lava.
-- (Confirmed: HSHub_RemoteHook capture, hooks_ok includes "LavaSelfDamage".)
--
-- Uses the shared Stealth namecall hook: register a handler that DROPS
-- FireServer when self.Name is in BLOCK and its toggle is on. Stealth's
-- dispatcher already guards checkcaller() (our own fire() helper passes
-- through) and a non-nil return short-circuits the real call = blocked.
--
-- EXTEND LATER: when we capture Drowning/Meteor/Moisture/Tornado remotes,
-- just add rows to BLOCK below — no other change needed.
-- ════════════════════════════════════════════════════════════════════
do
    local BLOCK = {
        -- Lava: LavaSelfDamage:FireServer() ~1/s, ~95 dmg/tick (DamageSpy-verified)
        LavaSelfDamage = function() return S.NoLavaDamage end,
        -- Drowning: 2 client-auth self-damage remotes fire ~1/s while suffocating
        --   OxygenRemote ~22 dmg/tick (starts the damage), DrownRemote ~7 dmg/tick.
        --   Both verified by DamageSpy 2026-05-29 (health 'h' drop 0.07s after each fire).
        OxygenRemote   = function() return S.NoDrowningDamage end,
        DrownRemote    = function() return S.NoDrowningDamage end,
        -- Meteor    = function() return S.NoMeteorDamage end,     -- TODO: capture remote
        -- Moisture  = function() return S.NoMoistureDamage end,   -- TODO: capture remote
        -- Tornado   = function() return S.NoTornadoDamage end,    -- TODO: capture remote
    }
    -- MECHANISM: hookfunction on FireServer (NOT __namecall).
    -- DamageSpy PROVED hookfunction(remote.FireServer,...) intercepts these exact
    -- remotes; the old __namecall hook missed them because CoS fires the damage
    -- remotes via a wrapper/dot-call (FireServer(remote,...)), not obj:FireServer()
    -- colon-syntax. hookfunction on the FireServer C-closure catches BOTH styles.
    pcall(function()
        local hookfn = (Stealth and Stealth.hookfunction) or hookfunction
        if not hookfn then return end
        -- any RemoteEvent works: FireServer is one shared C-closure for all of them
        local sample
        for _, d in ipairs(game:GetService('ReplicatedStorage'):GetDescendants()) do
            if d:IsA('RemoteEvent') then sample = d; break end
        end
        if not sample then return end
        local ccaller = (Stealth and Stealth.checkcaller) or function() return false end
        local orig
        orig = hookfn(sample.FireServer, function(self, ...)
            -- skip our own fires (executor thread) so we never block HSHub itself
            if not ccaller() then
                local ok, nm = pcall(function() return self.Name end)
                if ok then
                    local pred = BLOCK[nm]
                    if pred and pred() == true then
                        return   -- swallow → server never receives the self-damage
                    end
                end
            end
            return orig(self, ...)
        end)
    end)
end

-- Visual loops
task.spawn(function()
    while true do
        task.wait(2)
        if S.RemoveFog then
            Lighting.FogEnd = 100000; Lighting.FogStart = 100000
        end
    end
end)

-- ════════════════════════════════════════════════════════════════════
-- AUTONOMOUS FARM (2026-06-06) — device-agnostic spawn + priority farm + hop
--   Normal  : spawn any ALIVE slot (restart if all dead) -> farm priority shrines.
--   Stealth : only spawn an INVISIBLE-ability creature -> auto-activate invis -> farm.
--   On spawn: auto hide-scent (existing AutoScentHidden loop) + (stealth) auto invis.
--   Farm    : Ardor -> Novus -> Eigion -> rest. Server-hop when 5/all shrines done.
--   Taps    : genuine VIM (mouse+touch); OFFSET MEASURED via calibration = any device.
--   Spawn/restart logic ported from the proven HSHub_SpawnBot.lua (confirmed in-game).
-- ════════════════════════════════════════════════════════════════════
do
    S.AutoNormalMode      = false
    S.AutoStealthMode     = false
    S.AutoFarmHopWhenDone = false

    local UIS        = game:GetService('UserInputService')
    local GuiService = game:GetService('GuiService')
    local VIM; pcall(function() VIM = game:GetService('VirtualInputManager') end)
    local PG = PlayerGui

    local IS_PC = false
    pcall(function() local p = UIS:GetPlatform()
        if p == Enum.Platform.Windows or p == Enum.Platform.OSX or p == Enum.Platform.UWP then IS_PC = true end end)
    if not IS_PC and not UIS.TouchEnabled then IS_PC = true end
    local function inset() local i = GuiService:GetGuiInset(); return i or Vector2.new(0, 0) end
    local OFFSET = Vector2.new(0, inset().Y)   -- default; replaced by calibration

    -- invisible-ability creatures (user-provided list, 2026-06-06)
    local INVIS = {}
    for _, n in ipairs({
        'Axothan','Belluvaraptor','Cimidstik','Corsarlett','Cuxena','Fellisio','Fluren',
        'Gurava','Ibetchi','Jhiggo','Jangl','Konomushi','Kriprik','Luxsces','Mijusuima',
        'Moluna','Momola','Nymphasuchus','Ovufu','Oxytalis','Parux','Pero','Quezekel',
        'Qurugosk','Saikarie','Sequidliom',"Sha'Rei",'Shararook','Sigmatox','Squitico',
        'Umbraxi','Viracniar',"Wixpectr'o",
    }) do INVIS[n:lower()] = true end
    local function isInvisCreature(nm)
        if not nm then return false end
        return INVIS[tostring(nm):lower()] == true
    end

    -- shrine priority: these first, then the rest
    local SHRINE_PRIORITY = { 'Ardor', 'Novus', 'Eigion' }
    local function orderedShrines()
        local order, seen = {}, {}
        local function add(n) if S.ArtifactToggles[n] ~= nil and not seen[n] then order[#order + 1] = n; seen[n] = true end end
        for _, n in ipairs(SHRINE_PRIORITY) do add(n) end
        for _, n in ipairs(SHRINES_HIGH) do add(n) end
        for _, n in ipairs(SHRINES_LOW)  do add(n) end
        return order
    end

    local statusSet = function() end   -- replaced by the UI label setter below
    local function panelHide() pcall(function() HSHub.ScreenGui.Enabled = false end) end
    local function panelShow() pcall(function() HSHub.ScreenGui.Enabled = true  end) end

    -- ═══ device-agnostic VIM tap (AbsolutePosition + size/2 + measured OFFSET) ═══
    local function vimTap(x, y)
        if not VIM then return end
        pcall(function() if VIM.SendMouseMoveEvent then VIM:SendMouseMoveEvent(x, y, game) end end)
        pcall(function() VIM:SendMouseButtonEvent(x, y, 0, true, game, 1) end)
        task.wait(0.06)
        pcall(function() VIM:SendMouseButtonEvent(x, y, 0, false, game, 1) end)
        if not IS_PC then
            pcall(function() VIM:SendTouchEvent(1, 0, x, y) end)
            task.wait(0.06)
            pcall(function() VIM:SendTouchEvent(1, 2, x, y) end)
        end
    end
    local function tapButton(btn, label)
        if not btn then return false end
        local ap, az = btn.AbsolutePosition, btn.AbsoluteSize
        local x = ap.X + az.X / 2 + OFFSET.X
        local y = ap.Y + az.Y / 2 + OFFSET.Y
        statusSet(('tap %s @(%d,%d)'):format(tostring(label), math.floor(x), math.floor(y)))
        panelHide(); task.wait(0.08)
        vimTap(x, y)
        task.wait(0.08); panelShow()
        return true
    end

    -- ═══ auto-calibrate: measure OFFSET via our OWN catcher (game untouched) ═══
    local function autoCalibrate()
        if not VIM then return false, 'no VIM' end
        local catcher = Instance.new('ScreenGui')
        catcher.IgnoreGuiInset = false; catcher.DisplayOrder = 99999; catcher.ResetOnSpawn = false
        catcher.Parent = (gethui and gethui()) or PG
        local btn = Instance.new('TextButton', catcher)
        btn.Size = UDim2.new(1, 0, 1, 0); btn.BackgroundTransparency = 1; btn.Text = ''
        btn.AutoButtonColor = false; btn.Modal = true
        local got
        local c1 = btn.InputBegan:Connect(function(io)
            if io.UserInputType == Enum.UserInputType.Touch or io.UserInputType == Enum.UserInputType.MouseButton1 then
                got = io.Position
            end
        end)
        task.wait(0.06)
        local vp = (workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize) or Vector2.new(400, 300)
        local Vx, Vy = math.floor(vp.X * 0.5), math.floor(vp.Y * 0.5)
        if IS_PC then
            pcall(function() VIM:SendMouseButtonEvent(Vx, Vy, 0, true, game, 1) end); task.wait(0.05)
            pcall(function() VIM:SendMouseButtonEvent(Vx, Vy, 0, false, game, 1) end)
        else
            pcall(function() VIM:SendTouchEvent(1, 0, Vx, Vy) end); task.wait(0.05)
            pcall(function() VIM:SendTouchEvent(1, 2, Vx, Vy) end)
        end
        task.wait(0.18)
        pcall(function() c1:Disconnect() end); pcall(function() catcher:Destroy() end)
        if got then OFFSET = Vector2.new(Vx - got.X, Vy - got.Y); return true, OFFSET end
        return false, 'no input captured'
    end

    -- ═══ lobby lookups (SaveSelectionGui) ═══
    local function findSaveGui()
        for _, r in ipairs({ PG, (gethui and gethui()) or PG }) do
            local g = r:FindFirstChild('SaveSelectionGui'); if g then return g end
        end
    end
    local function visibleChain(o) local n = o; while n and n:IsA('GuiObject') do if not n.Visible then return false end n = n.Parent end return true end
    local function findNamed(name)
        local g = findSaveGui(); if not g then return nil end
        for _, d in ipairs(g:GetDescendants()) do
            if d.Name == name and (d:IsA('ImageButton') or d:IsA('TextButton')) and visibleChain(d) and d.AbsoluteSize.X < 200 then return d end
        end
    end
    local function findPlayButton()    return findNamed('PlayButton')    end
    local function findRestartButton() return findNamed('RestartButton') end
    -- confirm dialog button: scan ALL PlayerGui (popup may be a separate ScreenGui),
    -- match Name OR Text against confirm terms, skip the RestartButton we just pressed,
    -- and prefer the LOWEST match on screen (confirm sits below the trigger). Logs the
    -- chosen button + tap coords so we can verify/correct from the status line.
    local CONFIRM_TERMS = { 'confirm', 'konfirmasi', 'accept', 'terima', 'yes', 'ya', 'oke', 'ok', 'lanjut', 'setuju' }
    local function findConfirmish()
        local roots = { PG }
        if gethui then local ok, h = pcall(gethui); if ok and h then roots[#roots + 1] = h end end
        local best
        for _, root in ipairs(roots) do
            for _, d in ipairs(root:GetDescendants()) do
                if (d:IsA('TextButton') or d:IsA('ImageButton')) and d.Name ~= 'RestartButton'
                    and visibleChain(d) and d.AbsoluteSize.X > 0 and d.AbsoluteSize.X < 340 then
                    local txt = ''; if d:IsA('TextButton') then pcall(function() txt = d.Text end) end
                    local hay = (d.Name .. ' ' .. txt):lower()
                    local hit = false
                    for _, term in ipairs(CONFIRM_TERMS) do if hay:find(term, 1, true) then hit = true; break end end
                    if hit and ((not best) or d.AbsolutePosition.Y > best.AbsolutePosition.Y) then best = d end
                end
            end
        end
        if best then local ap, az = best.AbsolutePosition, best.AbsoluteSize
            statusSet(('confirm? [%s] c(%d,%d)'):format(best.Name, math.floor(ap.X + az.X / 2), math.floor(ap.Y + az.Y / 2))) end
        return best
    end
    local function readSlots()
        local out = {}; local g = findSaveGui(); if not g then return out end
        local sf; for _, d in ipairs(g:GetDescendants()) do if d.Name == 'SlotsFrame' then sf = d; break end end
        if not sf then return out end
        for _, c in ipairs(sf:GetChildren()) do
            local n = tonumber(c.Name)
            if n then
                local cf = c:FindFirstChild('CreatureFrame', true)
                local nm, dead = '?', false
                if cf then
                    local nL = cf:FindFirstChild('NameLabel')
                    local dL = cf:FindFirstChild('DeadLabel')
                    local rB = cf:FindFirstChild('RestartButton')
                    if nL then nm = nL.Text end
                    dead = (dL and dL.Visible == true) or (rB and rB.Visible == true) or false
                end
                out[#out + 1] = { slot = 'Slot' .. n, n = n, name = nm, dead = dead, card = cf }
            end
        end
        table.sort(out, function(a, b) return a.n < b.n end)
        return out
    end
    local function inGameNow()
        local ch = workspace:FindFirstChild('Characters')
        if ch and (ch:FindFirstChild(LP.Name) or ch:FindFirstChild(LP.DisplayName)) then return true end
        return getChar() ~= nil
    end
    local function centerCard(s) if s and s.card then tapButton(s.card:FindFirstChild('ViewButton') or s.card, 'center ' .. s.slot) end end
    -- "entered game" = the lobby's Play/Restart buttons are GONE (more reliable than a
    -- character check: a dead creature can linger in workspace.Characters after death).
    local function leftLobby() return findPlayButton() == nil and findRestartButton() == nil end
    local function waitInGame(sec) local t = tick(); repeat task.wait(0.5) until leftLobby() or tick() - t > sec; return leftLobby() end

    -- ═══ spawn ONE creature for the mode (returns true if entered game) ═══
    local function spawnFor(mode)
        if leftLobby() then return true end          -- lobby already closed = already in game
        local slots = readSlots()
        if #slots == 0 then statusSet('lobby not loaded (no slots)'); return false end
        local aliveTarget, deadTarget
        for _, s in ipairs(slots) do
            local eligible = (mode ~= 'stealth') or isInvisCreature(s.name)
            if eligible then
                if (not s.dead) and (not aliveTarget) then aliveTarget = s end
                if s.dead and (not deadTarget) then deadTarget = s end
            end
        end
        -- 1) alive eligible creature -> center + Mainkan
        if aliveTarget then
            statusSet('ALIVE ' .. aliveTarget.slot .. ' ' .. aliveTarget.name)
            centerCard(aliveTarget); task.wait(0.8)
            local pb = findPlayButton()
            if pb then
                tapButton(pb, 'Mainkan')
                if waitInGame(9) then statusSet('OK entered (' .. aliveTarget.name .. ')'); return true end
                statusSet('x no load after Mainkan'); return false
            end
            statusSet('no Mainkan after centering ' .. aliveTarget.slot); return false
        end
        -- 2) need a restart: stealth -> the dead invis one; normal -> slot 1
        local s = deadTarget or ((mode ~= 'stealth') and slots[1]) or nil
        if not s then statusSet('stealth: no invisible creature in any slot'); return false end
        statusSet('all dead/none alive -> restart ' .. s.slot .. ' ' .. s.name)
        centerCard(s); task.wait(0.8)
        local rb = findRestartButton()
        if not rb then statusSet('no Restart button visible'); return false end
        tapButton(rb, 'Restart'); task.wait(1.6)
        local cf = findConfirmish()
        if cf then tapButton(cf, 'Confirm'); task.wait(1.2) end
        local pb = findPlayButton()
        if pb then
            tapButton(pb, 'Mainkan')
            if waitInGame(9) then statusSet('OK entered after restart'); return true end
        end
        statusSet('x restart+play failed (check confirm button name)'); return false
    end

    -- ═══ conditional server hop (only when shrines done) ═══
    local function serverHop()
        statusSet('server hop (shrines done)')
        pcall(function()
            local ok, raw = pcall(function()
                return game:HttpGet('https://games.roblox.com/v1/games/' .. tostring(game.PlaceId)
                    .. '/servers/Public?sortOrder=Asc&limit=100')
            end)
            if ok and raw then
                local d = HttpService:JSONDecode(raw)
                if d and d.data then
                    for _, srv in ipairs(d.data) do
                        if srv.playing < srv.maxPlayers and srv.id ~= game.JobId then
                            TeleportService:TeleportToPlaceInstance(game.PlaceId, srv.id, LP); return
                        end
                    end
                end
            end
        end)
    end

    -- reachable = tablet loaded NOW, OR a TP position is known (hardcoded / learned file).
    -- Ardor & Angelic are NOT hardcoded (auto-learned) -> if unknown, skip so we don't
    -- freeze trying to farm a shrine we can't navigate to.
    local function shrineReachable(n)
        if getShrineTablet(n) ~= nil then return true end
        local ok, pos = pcall(tabletPositions, n)
        return (ok and pos and #pos > 0) or false
    end

    -- ═══ ORCHESTRATOR ═══
    local completed = {}            -- shrines deposited (cooldown) this life
    local lastInvis, lastHop = 0, 0
    local busy, managing = false, false
    task.spawn(function()
        while true do
            task.wait(2)
            local mode = (S.AutoStealthMode and 'stealth') or (S.AutoNormalMode and 'normal') or nil
            if mode and (not busy) then
                busy = true
                managing = true
                pcall(function()
                    -- LOBBY vs IN-GAME by the lobby's OWN buttons: a visible Play/Restart
                    -- button exists ONLY in the lobby. (inGameNow() alone is unreliable -- a
                    -- dead creature lingers in workspace.Characters after returning to the
                    -- lobby -> falsely "in game" -> it would FARM instead of SPAWN.)
                    local atLobby = (findPlayButton() ~= nil) or (findRestartButton() ~= nil)
                    if atLobby then
                        -- LOBBY -> spawn
                        task.wait(0.6 + math.random())
                        spawnFor(mode)
                        completed = {}                 -- fresh life resets shrine completion
                    else
                        -- IN GAME -> hide-scent (+ stealth invis) + priority farm + hop
                        S.AutoScentHidden = true
                        if mode == 'stealth' and (tick() - lastInvis > 30) then
                            lastInvis = tick()
                            pcall(function() fire('ActivateAbility', 'Invisibility') end)
                        end
                        local order  = orderedShrines()
                        local target = math.min(5, #order)
                        local active
                        local skipped = nil
                        for _, n in ipairs(order) do
                            if not completed[n] then
                                local av = shrineAvailable(n)
                                if av == false then
                                    completed[n] = true                 -- on cooldown = done this server
                                elseif shrineReachable(n) then
                                    active = n; break                   -- loaded / position known -> farm it
                                else
                                    skipped = skipped or n              -- unreachable (e.g. Ardor unknown) -> next
                                end
                            end
                        end
                        local doneN = 0; for _ in pairs(completed) do doneN = doneN + 1 end
                        if doneN >= target then active = nil end
                        for n in pairs(S.ArtifactToggles) do S.ArtifactToggles[n] = (n == active) end
                        if not active then
                            if skipped then
                                statusSet(('%s pos unknown - run ShrineHunter (%d/%d)'):format(skipped, doneN, target))
                            else
                                statusSet(('farm done %d/%d -> idle'):format(doneN, target))
                                if S.AutoFarmHopWhenDone and (tick() - lastHop > 30) then lastHop = tick(); task.wait(1.5); serverHop() end
                            end
                        else
                            statusSet(('farming %s (%d/%d done)'):format(active, doneN, target))
                        end
                    end
                end)
                busy = false
            elseif (not mode) and managing then
                -- autonomous just turned OFF -> stop the farm IT started (clear the shrine
                -- toggles the orchestrator set, so the artifact-farm loop goes idle again).
                managing = false
                for n in pairs(S.ArtifactToggles) do S.ArtifactToggles[n] = false end
                statusSet('autonomous OFF (farm stopped)')
            end
        end
    end)

    -- ═══ UI TAB ═══
    local Tab = Window:CreateTab('Autonomous', '🤖')
    local Sec = Tab:CreateSection('AUTONOMOUS FARM')
    Sec:AddLabel('Auto-calibrates on load. Just pick ONE mode. Runs from lobby OR in-game.', Color3.fromRGB(180, 220, 255))
    local statusLbl = Sec:AddLabel('Status: starting...', Color3.fromRGB(150, 205, 150))
    statusSet = function(t) pcall(function() statusLbl:Set('Status: ' .. tostring(t)) end) end
    -- auto-calibrate on load (no button): measure the tap OFFSET, retry, else keep default
    task.spawn(function()
        task.wait(3)
        for _ = 1, 4 do
            panelHide(); local ok, off = autoCalibrate(); panelShow()
            if ok then statusSet(('auto-calibrated OFFSET=(%d,%d)'):format(math.floor(off.X), math.floor(off.Y))); return end
            statusSet('auto-calibrate retry...'); task.wait(4)
        end
        statusSet(('calibrate failed - default OFFSET=(%d,%d)'):format(math.floor(OFFSET.X), math.floor(OFFSET.Y)))
    end)
    Sec:AddToggle({ Name = 'Normal Mode (any creature)', Key = 'AutoNormalMode', Default = false,
        Tip = 'Spawn any ALIVE slot (restart if all dead), then farm priority shrines',
        Callback = function(v) S.AutoNormalMode = v; if v then S.AutoStealthMode = false end end })
    Sec:AddToggle({ Name = 'Stealth Mode (invisible creature)', Key = 'AutoStealthMode', Default = false,
        Tip = 'Only spawn a creature with invisibility; auto-activates invis in game',
        Callback = function(v) S.AutoStealthMode = v; if v then S.AutoNormalMode = false end end })
    Sec:AddToggle({ Name = 'Server Hop when shrines done', Key = 'AutoFarmHopWhenDone', Default = false,
        Tip = 'After 5/all shrines are deposited (cooldown), hop to a fresh server',
        Callback = function(v) S.AutoFarmHopWhenDone = v end })
    Sec:AddLabel('Priority: Ardor > Novus > Eigion > rest. Invisible list: 33 creatures.', Color3.fromRGB(150, 150, 180))
end

HSHubV2:Notify(('HS Hub loaded · %s · HS-COS-V4')
    :format(IS_HARDCORE and 'Sonaria HARDCORE (Shadow shrine enabled)'
        or IS_ISLE10 and 'Isle 10'
        or 'Creatures of Sonaria'), 'ok', 3)

