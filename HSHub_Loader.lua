-- ══════════════════════════════════════════════════════════════════
--  HSHub CoS — Loader + Keysystem UI
--  Version : 2.0
-- ══════════════════════════════════════════════════════════════════

local SCRIPT_URL = "https://raw.githubusercontent.com/Razdla/ZaldaDPV3/refs/heads/main/HSHub_CoSKeysystemLoader.lua"
local VALID_KEYS = { "Halycon" }

-- ─── SERVICES ────────────────────────────────────────────────────
local Players          = game:GetService("Players")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local LP               = Players.LocalPlayer

-- ─── HTTP HELPER ─────────────────────────────────────────────────
local function getHttp()
    return (syn and syn.request)
        or (http and http.request)
        or (fluxus and fluxus.request)
        or (request)
        or nil
end

-- ─── GUI PARENT ──────────────────────────────────────────────────
local function getGuiParent()
    local hui
    pcall(function() hui = gethui() end)
    if hui then return hui end
    local ok, cg = pcall(function() return game:GetService("CoreGui") end)
    if ok and cg then return cg end
    return LP:WaitForChild("PlayerGui")
end

-- ─── LOAD MAIN SCRIPT ────────────────────────────────────────────
local function loadMainScript(onDone, onError)
    task.spawn(function()
        local src = nil
        local httpReq = getHttp()

        if httpReq then
            local ok, resp = pcall(function()
                return httpReq({ Url = SCRIPT_URL, Method = "GET" })
            end)
            if ok and resp and resp.StatusCode == 200 and #resp.Body > 100 then
                src = resp.Body
            end
        end

        if not src then
            local ok, result = pcall(function() return game:HttpGetAsync(SCRIPT_URL) end)
            if ok and result and #result > 100 then src = result end
        end

        if not src then
            onError("Gagal fetch script. Cek koneksi.")
            return
        end

        local fn, err = loadstring(src)
        if not fn then
            onError("loadstring error: " .. tostring(err))
            return
        end

        onDone()

        local ok2, runErr = pcall(fn)
        if not ok2 then
            warn("[HSHub] Runtime error: " .. tostring(runErr))
        end
    end)
end

-- ─── KEYSYSTEM UI ────────────────────────────────────────────────
local C = {
    Bg      = Color3.fromRGB(8,   8,  18),
    Panel   = Color3.fromRGB(14, 12,  28),
    Input   = Color3.fromRGB(10, 10,  22),
    AccA    = Color3.fromRGB(140, 90, 245),
    AccB    = Color3.fromRGB(60, 200, 230),
    Border  = Color3.fromRGB(45,  35,  80),
    Text    = Color3.fromRGB(220, 220, 235),
    TextSub = Color3.fromRGB(100, 100, 140),
    Green   = Color3.fromRGB(40,  200, 120),
    Red     = Color3.fromRGB(220,  50,  60),
}

local function new(cls, props)
    local o = Instance.new(cls)
    for k, v in pairs(props or {}) do
        if k ~= "Parent" then o[k] = v end
    end
    if props and props.Parent then o.Parent = props.Parent end
    return o
end
local function corner(r, p) Instance.new("UICorner", p).CornerRadius = UDim.new(0, r) end
local function tw(obj, t, props)
    TweenService:Create(obj, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
end

-- ScreenGui
local sg = new("ScreenGui", {
    Name = "HSHub_Keysystem",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    DisplayOrder = 9999,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})
pcall(function()
    if syn and syn.protect_gui then syn.protect_gui(sg)
    elseif protect_gui then protect_gui(sg) end
end)
sg.Parent = getGuiParent()

-- Dim overlay
new("Frame", {
    Parent = sg, ZIndex = 1,
    Size = UDim2.new(1,0,1,0),
    BackgroundColor3 = Color3.fromRGB(0,0,0),
    BackgroundTransparency = 0.45,
    BorderSizePixel = 0,
})

-- Card
local card = new("Frame", {
    Parent = sg, ZIndex = 2,
    Size = UDim2.new(0, 340, 0, 290),
    Position = UDim2.new(0.5, -170, 1, 20), -- starts off-screen (animasi masuk)
    BackgroundColor3 = C.Panel,
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
})
corner(14, card)
do
    local s = Instance.new("UIStroke", card)
    s.Color = C.Border; s.Thickness = 1.5
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
end

-- Top accent bar
local topBar = new("Frame", {
    Parent = card, ZIndex = 3,
    Size = UDim2.new(1,0,0,3),
    BackgroundColor3 = C.AccA,
    BorderSizePixel = 0,
})
corner(14, topBar)
do
    local g = Instance.new("UIGradient", topBar)
    g.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, C.AccA),
        ColorSequenceKeypoint.new(1, C.AccB),
    })
end

-- Logo
local logoLbl = new("TextLabel", {
    Parent = card, ZIndex = 3,
    Size = UDim2.new(1,0,0,44),
    Position = UDim2.new(0,0,0,14),
    BackgroundTransparency = 1,
    Text = "HS HUB",
    TextSize = 26,
    Font = Enum.Font.GothamBlack,
    TextXAlignment = Enum.TextXAlignment.Center,
    TextColor3 = C.Text,
})
do
    local g = Instance.new("UIGradient", logoLbl)
    g.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, C.AccA),
        ColorSequenceKeypoint.new(1, C.AccB),
    })
end

-- Subtitle
new("TextLabel", {
    Parent = card, ZIndex = 3,
    Size = UDim2.new(1,0,0,18),
    Position = UDim2.new(0,0,0,58),
    BackgroundTransparency = 1,
    Text = "Hydra Solvation  ·  Creatures of Sonaria",
    TextColor3 = C.TextSub,
    TextSize = 11,
    Font = Enum.Font.Gotham,
    TextXAlignment = Enum.TextXAlignment.Center,
})

-- Divider
new("Frame", {
    Parent = card, ZIndex = 3,
    Size = UDim2.new(1,-40,0,1),
    Position = UDim2.new(0,20,0,86),
    BackgroundColor3 = C.Border,
    BorderSizePixel = 0,
})

-- Label "Masukkan Key"
new("TextLabel", {
    Parent = card, ZIndex = 3,
    Size = UDim2.new(1,-40,0,20),
    Position = UDim2.new(0,20,0,98),
    BackgroundTransparency = 1,
    Text = "Masukkan Key",
    TextColor3 = C.TextSub,
    TextSize = 11,
    Font = Enum.Font.GothamBold,
    TextXAlignment = Enum.TextXAlignment.Left,
})

-- Input frame
local inputFrame = new("Frame", {
    Parent = card, ZIndex = 3,
    Size = UDim2.new(1,-40,0,40),
    Position = UDim2.new(0,20,0,122),
    BackgroundColor3 = C.Input,
    BorderSizePixel = 0,
})
corner(8, inputFrame)
local inputStroke = Instance.new("UIStroke", inputFrame)
inputStroke.Color = C.Border
inputStroke.Thickness = 1.5
inputStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

local inputBox = new("TextBox", {
    Parent = inputFrame, ZIndex = 4,
    Size = UDim2.new(1,-16,1,0),
    Position = UDim2.new(0,8,0,0),
    BackgroundTransparency = 1,
    Text = "",
    PlaceholderText = "Ketik key di sini...",
    TextColor3 = C.Text,
    PlaceholderColor3 = C.TextSub,
    TextSize = 13,
    Font = Enum.Font.Gotham,
    ClearTextOnFocus = false,
})

inputBox.Focused:Connect(function() tw(inputStroke, 0.15, {Color = C.AccA}) end)
inputBox.FocusLost:Connect(function() tw(inputStroke, 0.15, {Color = C.Border}) end)

-- Status label
local statusLbl = new("TextLabel", {
    Parent = card, ZIndex = 3,
    Size = UDim2.new(1,-40,0,18),
    Position = UDim2.new(0,20,0,168),
    BackgroundTransparency = 1,
    Text = "",
    TextColor3 = C.Red,
    TextSize = 11,
    Font = Enum.Font.Gotham,
    TextXAlignment = Enum.TextXAlignment.Left,
})

-- Submit button
local submitBtn = new("TextButton", {
    Parent = card, ZIndex = 3,
    Size = UDim2.new(1,-40,0,42),
    Position = UDim2.new(0,20,0,196),
    BackgroundColor3 = Color3.fromRGB(35,25,70),
    BorderSizePixel = 0,
    Text = "SUBMIT",
    TextColor3 = C.Text,
    TextSize = 13,
    Font = Enum.Font.GothamBold,
    AutoButtonColor = false,
})
corner(8, submitBtn)
do
    local s = Instance.new("UIStroke", submitBtn)
    s.Color = C.AccA; s.Thickness = 1
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
end
do
    local g = Instance.new("UIGradient", submitBtn)
    g.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(35,25,70)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(50,35,95)),
    })
    g.Rotation = 90
end

submitBtn.MouseEnter:Connect(function() tw(submitBtn, 0.12, {BackgroundColor3 = Color3.fromRGB(55,40,110)}) end)
submitBtn.MouseLeave:Connect(function() tw(submitBtn, 0.12, {BackgroundColor3 = Color3.fromRGB(35,25,70)}) end)

-- ─── LOGIC ───────────────────────────────────────────────────────
local isLoading = false

local function shakeCard()
    for _, ox in ipairs({9,-9,7,-7,4,-4,0}) do
        card.Position = UDim2.new(0.5, -170 + ox, 0.5, -145)
        task.wait(0.04)
    end
    card.Position = UDim2.new(0.5, -170, 0.5, -145)
end

local function trySubmit()
    if isLoading then return end
    local key = inputBox.Text:match("^%s*(.-)%s*$")

    local valid = false
    for _, k in ipairs(VALID_KEYS) do
        if k == key then valid = true; break end
    end

    if not valid then
        statusLbl.Text = "✗  Key tidak valid."
        statusLbl.TextColor3 = C.Red
        tw(inputStroke, 0.1, {Color = C.Red})
        task.delay(1.2, function() tw(inputStroke, 0.2, {Color = C.Border}) end)
        task.spawn(shakeCard)
        return
    end

    -- Valid
    statusLbl.Text = "✓  Key valid! Memuat HSHub..."
    statusLbl.TextColor3 = C.Green
    isLoading = true
    submitBtn.Text = "MEMUAT..."
    submitBtn.TextColor3 = C.TextSub

    _G._HSHub_Key    = key
    _G._HSHub_Loaded = true

    loadMainScript(
        function() -- onDone: tutup UI
            tw(card, 0.3, {
                Size = UDim2.new(0,340,0,0),
                Position = UDim2.new(0.5,-170,0.5,0),
                BackgroundTransparency = 1,
            })
            task.delay(0.35, function() pcall(function() sg:Destroy() end) end)
        end,
        function(msg) -- onError
            isLoading = false
            submitBtn.Text = "SUBMIT"
            submitBtn.TextColor3 = C.Text
            statusLbl.Text = "✗  " .. tostring(msg)
            statusLbl.TextColor3 = C.Red
        end
    )
end

submitBtn.MouseButton1Click:Connect(trySubmit)
inputBox.FocusLost:Connect(function(enter) if enter then trySubmit() end end)

-- ─── ANIMASI MASUK ───────────────────────────────────────────────
task.delay(0.05, function()
    tw(card, 0.35, {
        Position = UDim2.new(0.5, -170, 0.5, -145),
        BackgroundTransparency = 0,
    })
end)
