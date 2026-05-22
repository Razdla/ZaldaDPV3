--[[
    ╔══════════════════════════════════════════════════════════╗
    ║              GAME SCANNER v1.1                           ║
    ║   Scanner fondasi untuk pengembangan fitur baru          ║
    ║   Mount pattern: gethui → PlayerGui → CoreGui            ║
    ║   Support: Delta, Arceus X, Hydrogen, Codex, Fluxus,     ║
    ║            Krnl, Synapse, Script-Ware, Wave, dll         ║
    ╚══════════════════════════════════════════════════════════╝

    PERBAIKAN dari v1.0 (kenapa UI tak muncul sebelumnya):
      • Mount urut: gethui() → PlayerGui → CoreGui (bukan CoreGui dulu)
      • pcall di setiap parent assignment
      • DisplayOrder = 9999 supaya di atas UI game
      • Mobile detect pakai `not MouseEnabled` (bukan KeyboardEnabled)
      • Floating toggle button (HS) sebagai jaring pengaman visibilitas
      • Marker attribute untuk cleanup re-exec yang aman
--]]

------------------------------------------------------------
-- SERVICES
------------------------------------------------------------
local Players          = game:GetService("Players")
local CoreGui          = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local RunService       = game:GetService("RunService")
local HttpService      = game:GetService("HttpService")
local StarterGui       = game:GetService("StarterGui")

local LP = Players.LocalPlayer

------------------------------------------------------------
-- EXECUTOR DETECT + COMPATIBILITY
------------------------------------------------------------
local execName = "Unknown"
pcall(function() if identifyexecutor then execName = (identifyexecutor()) end end)

-- Mobile vs PC (PERBAIKAN: pakai MouseEnabled, bukan KeyboardEnabled)
local IS_MOBILE = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
local IS_PC     = not IS_MOBILE

-- gethui dengan fallback
local _gethui = gethui or function() return CoreGui end

-- protect_gui untuk Synapse-family
local _protect_gui = (syn and syn.protect_gui) or protect_gui or function() end

-- clipboard fallback
local _clip = setclipboard or toclipboard
    or (syn and syn.write_clipboard)
    or (Clipboard and Clipboard.set)
    or writeclipboard
    or function() end

local _hookmetamethod   = hookmetamethod
local _newcclosure      = newcclosure or function(f) return f end
local _getnamecallmethod= getnamecallmethod or get_namecall_method
local _checkcaller      = checkcaller or function() return false end

local function notify(title, text, dur)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title, Text = text, Duration = dur or 3
        })
    end)
end

------------------------------------------------------------
-- CLEANUP EXISTING (cek di SEMUA kemungkinan parent)
------------------------------------------------------------
pcall(function()
    local parents = { _gethui(), CoreGui, LP:FindFirstChild("PlayerGui") }
    for _, par in ipairs(parents) do
        if par then
            for _, c in ipairs(par:GetChildren()) do
                if c:IsA("ScreenGui") and c:GetAttribute("GameScannerMarker") then
                    c:Destroy()
                end
            end
        end
    end
end)

------------------------------------------------------------
-- SCREENGUI ROOT (mount pattern yang benar)
------------------------------------------------------------
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "GameScanner"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.IgnoreGuiInset = true
ScreenGui.DisplayOrder = 9999          -- ★ supaya di atas UI game
ScreenGui:SetAttribute("GameScannerMarker", true)

pcall(_protect_gui, ScreenGui)

-- ★ KUNCINYA: coba gethui → PlayerGui → CoreGui, pcall semua
local mounted = false
local ok1 = pcall(function() ScreenGui.Parent = _gethui() end)
if ok1 and ScreenGui.Parent then mounted = true end

if not mounted then
    local ok2 = pcall(function() ScreenGui.Parent = LP:WaitForChild("PlayerGui", 5) end)
    if ok2 and ScreenGui.Parent then mounted = true end
end

if not mounted then
    pcall(function() ScreenGui.Parent = CoreGui end)
end

if not ScreenGui.Parent then
    warn("[Scanner] GAGAL mount ScreenGui ke parent manapun!")
    return
end

------------------------------------------------------------
-- SCAN CONFIG
------------------------------------------------------------
local SCAN_TYPES = {
    { name = "RemoteEvents",   class = "RemoteEvent",    icon = "📡" },
    { name = "RemoteFuncs",    class = "RemoteFunction", icon = "🔄" },
    { name = "BindableEvents", class = "BindableEvent",  icon = "🔔" },
    { name = "BindableFuncs",  class = "BindableFunction",icon = "⚙️" },
    { name = "ModuleScripts",  class = "ModuleScript",   icon = "📦" },
    { name = "LocalScripts",   class = "LocalScript",    icon = "📜" },
    { name = "Scripts",        class = "Script",         icon = "📄" },
}

local SCAN_ROOTS = {
    workspace,
    game:GetService("ReplicatedStorage"),
    game:GetService("ReplicatedFirst"),
    game:GetService("Players"),
    game:GetService("StarterPlayer"),
    game:GetService("StarterGui"),
    game:GetService("StarterPack"),
    game:GetService("Lighting"),
    game:GetService("SoundService"),
}

------------------------------------------------------------
-- MAIN FRAME
------------------------------------------------------------
local MAIN_W = IS_MOBILE and 340 or 480
local MAIN_H = IS_MOBILE and 400 or 520

local Main = Instance.new("Frame")
Main.Name = "Main"
Main.Size = UDim2.new(0, MAIN_W, 0, MAIN_H)
Main.Position = UDim2.new(0.5, -MAIN_W/2, 0.5, -MAIN_H/2)
Main.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
Main.BorderSizePixel = 0
Main.Active = true
Main.Visible = true
Main.ZIndex = 100
Main.Parent = ScreenGui

local mc = Instance.new("UICorner", Main); mc.CornerRadius = UDim.new(0, 10)
local ms = Instance.new("UIStroke", Main)
ms.Color = Color3.fromRGB(60, 60, 75); ms.Thickness = 1

------------------------------------------------------------
-- TITLE BAR
------------------------------------------------------------
local TitleBar = Instance.new("Frame", Main)
TitleBar.Size = UDim2.new(1, 0, 0, 36)
TitleBar.BackgroundColor3 = Color3.fromRGB(32, 32, 42)
TitleBar.BorderSizePixel = 0
TitleBar.ZIndex = 101
local tbc = Instance.new("UICorner", TitleBar); tbc.CornerRadius = UDim.new(0, 10)
local tbfix = Instance.new("Frame", TitleBar)
tbfix.Size = UDim2.new(1, 0, 0, 12); tbfix.Position = UDim2.new(0, 0, 1, -12)
tbfix.BackgroundColor3 = TitleBar.BackgroundColor3; tbfix.BorderSizePixel = 0
tbfix.ZIndex = 101

local Title = Instance.new("TextLabel", TitleBar)
Title.Size = UDim2.new(1, -90, 1, 0)
Title.Position = UDim2.new(0, 12, 0, 0)
Title.BackgroundTransparency = 1
Title.Text = "🔍  Game Scanner"
Title.TextColor3 = Color3.fromRGB(235, 235, 240)
Title.TextSize = 15
Title.Font = Enum.Font.GothamBold
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.ZIndex = 102

local function makeIconBtn(text, color, posX)
    local b = Instance.new("TextButton", TitleBar)
    b.Size = UDim2.new(0, 28, 0, 24)
    b.Position = UDim2.new(1, posX, 0, 6)
    b.BackgroundColor3 = color
    b.Text = text
    b.TextColor3 = Color3.fromRGB(255, 255, 255)
    b.TextSize = 14
    b.Font = Enum.Font.GothamBold
    b.BorderSizePixel = 0
    b.ZIndex = 102
    local c = Instance.new("UICorner", b); c.CornerRadius = UDim.new(0, 4)
    return b
end

local CloseBtn = makeIconBtn("✕", Color3.fromRGB(200, 65, 65), -34)
local MinBtn   = makeIconBtn("—", Color3.fromRGB(85, 85, 100), -66)

------------------------------------------------------------
-- FLOATING TOGGLE BUTTON (jaring pengaman visibilitas)
------------------------------------------------------------
local FloatBtn = Instance.new("TextButton")
FloatBtn.Name = "FloatBtn"
FloatBtn.Size = UDim2.new(0, 48, 0, 48)
FloatBtn.Position = UDim2.new(0, 10, 0, IS_PC and 60 or 100)
FloatBtn.BackgroundColor3 = Color3.fromRGB(80, 130, 220)
FloatBtn.Text = "GS"
FloatBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
FloatBtn.TextSize = 16
FloatBtn.Font = Enum.Font.GothamBold
FloatBtn.BorderSizePixel = 0
FloatBtn.AutoButtonColor = false
FloatBtn.Active = true
FloatBtn.ZIndex = 200
FloatBtn.Parent = ScreenGui
local fbc = Instance.new("UICorner", FloatBtn); fbc.CornerRadius = UDim.new(1, 0)
local fbs = Instance.new("UIStroke", FloatBtn)
fbs.Color = Color3.fromRGB(255, 255, 255); fbs.Thickness = 1.5; fbs.Transparency = 0.5

local function toggleMain()
    Main.Visible = not Main.Visible
end

CloseBtn.MouseButton1Click:Connect(function()
    Main.Visible = false   -- jangan destroy, supaya bisa dibuka lagi via float
end)

FloatBtn.MouseButton1Click:Connect(toggleMain)

local minimized = false
local origSize = Main.Size
MinBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    local newSize = minimized and UDim2.new(0, MAIN_W, 0, 36) or origSize
    TweenService:Create(Main, TweenInfo.new(0.22), {Size = newSize}):Play()
end)

------------------------------------------------------------
-- DRAGGING (untuk Main DAN FloatBtn, dukung mouse + touch)
------------------------------------------------------------
local function makeDraggable(handle, target)
    local dragging, dragStart, startPos, activeInput
    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
           or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = target.Position
            activeInput = input
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if input == activeInput
           or input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Position - dragStart
            target.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)
end

makeDraggable(TitleBar, Main)
makeDraggable(FloatBtn, FloatBtn)

------------------------------------------------------------
-- CATEGORY BAR (horizontal scroll)
------------------------------------------------------------
local CatBar = Instance.new("ScrollingFrame", Main)
CatBar.Size = UDim2.new(1, -16, 0, 34)
CatBar.Position = UDim2.new(0, 8, 0, 42)
CatBar.BackgroundColor3 = Color3.fromRGB(28, 28, 36)
CatBar.BorderSizePixel = 0
CatBar.ScrollBarThickness = 2
CatBar.ScrollingDirection = Enum.ScrollingDirection.X
CatBar.AutomaticCanvasSize = Enum.AutomaticSize.X
CatBar.CanvasSize = UDim2.new(0, 0, 0, 0)
CatBar.ClipsDescendants = true
CatBar.ZIndex = 101
local cbc = Instance.new("UICorner", CatBar); cbc.CornerRadius = UDim.new(0, 6)

local cbl = Instance.new("UIListLayout", CatBar)
cbl.FillDirection = Enum.FillDirection.Horizontal
cbl.Padding = UDim.new(0, 4); cbl.SortOrder = Enum.SortOrder.LayoutOrder
local cbp = Instance.new("UIPadding", CatBar)
cbp.PaddingLeft = UDim.new(0, 4); cbp.PaddingRight = UDim.new(0, 4)
cbp.PaddingTop = UDim.new(0, 4);  cbp.PaddingBottom = UDim.new(0, 4)

local selectedType = SCAN_TYPES[1]
local catButtons = {}
for i, st in ipairs(SCAN_TYPES) do
    local b = Instance.new("TextButton", CatBar)
    b.Size = UDim2.new(0, 110, 1, -8)
    b.BackgroundColor3 = Color3.fromRGB(45, 45, 58)
    b.Text = st.icon .. " " .. st.name
    b.TextColor3 = Color3.fromRGB(220, 220, 225)
    b.TextSize = 11
    b.Font = Enum.Font.GothamMedium
    b.BorderSizePixel = 0
    b.AutoButtonColor = false
    b.LayoutOrder = i
    b.ZIndex = 102
    local c = Instance.new("UICorner", b); c.CornerRadius = UDim.new(0, 4)
    catButtons[st] = b
    b.MouseButton1Click:Connect(function()
        selectedType = st
        for s, btn in pairs(catButtons) do
            TweenService:Create(btn, TweenInfo.new(0.15), {
                BackgroundColor3 = s == st and Color3.fromRGB(80, 130, 220)
                                          or Color3.fromRGB(45, 45, 58)
            }):Play()
        end
    end)
end
catButtons[selectedType].BackgroundColor3 = Color3.fromRGB(80, 130, 220)

------------------------------------------------------------
-- ACTION BAR (Scan + Search)
------------------------------------------------------------
local ActionBar = Instance.new("Frame", Main)
ActionBar.Size = UDim2.new(1, -16, 0, 32)
ActionBar.Position = UDim2.new(0, 8, 0, 82)
ActionBar.BackgroundTransparency = 1
ActionBar.ZIndex = 101

local ScanBtn = Instance.new("TextButton", ActionBar)
ScanBtn.Size = UDim2.new(0, 80, 1, 0)
ScanBtn.BackgroundColor3 = Color3.fromRGB(70, 170, 100)
ScanBtn.Text = "▶ SCAN"
ScanBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ScanBtn.TextSize = 13
ScanBtn.Font = Enum.Font.GothamBold
ScanBtn.BorderSizePixel = 0
ScanBtn.ZIndex = 102
local sbc = Instance.new("UICorner", ScanBtn); sbc.CornerRadius = UDim.new(0, 5)

local SearchBox = Instance.new("TextBox", ActionBar)
SearchBox.Size = UDim2.new(1, -88, 1, 0)
SearchBox.Position = UDim2.new(0, 88, 0, 0)
SearchBox.BackgroundColor3 = Color3.fromRGB(40, 40, 52)
SearchBox.Text = ""
SearchBox.PlaceholderText = "🔎  Cari nama atau path..."
SearchBox.TextColor3 = Color3.fromRGB(230, 230, 230)
SearchBox.PlaceholderColor3 = Color3.fromRGB(140, 140, 150)
SearchBox.TextSize = 12
SearchBox.Font = Enum.Font.Gotham
SearchBox.TextXAlignment = Enum.TextXAlignment.Left
SearchBox.BorderSizePixel = 0
SearchBox.ClearTextOnFocus = false
SearchBox.ZIndex = 102
local sbxc = Instance.new("UICorner", SearchBox); sbxc.CornerRadius = UDim.new(0, 5)
local sbxp = Instance.new("UIPadding", SearchBox)
sbxp.PaddingLeft = UDim.new(0, 10); sbxp.PaddingRight = UDim.new(0, 10)

------------------------------------------------------------
-- RESULTS (vertical scroll)
------------------------------------------------------------
local Results = Instance.new("ScrollingFrame", Main)
Results.Size = UDim2.new(1, -16, 1, -158)
Results.Position = UDim2.new(0, 8, 0, 122)
Results.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
Results.BorderSizePixel = 0
Results.ScrollBarThickness = 4
Results.ScrollBarImageColor3 = Color3.fromRGB(90, 90, 110)
Results.AutomaticCanvasSize = Enum.AutomaticSize.Y
Results.CanvasSize = UDim2.new(0, 0, 0, 0)
Results.ScrollingDirection = Enum.ScrollingDirection.Y
Results.ZIndex = 101
local rc = Instance.new("UICorner", Results); rc.CornerRadius = UDim.new(0, 6)

local rl = Instance.new("UIListLayout", Results)
rl.Padding = UDim.new(0, 4); rl.SortOrder = Enum.SortOrder.LayoutOrder
local rp = Instance.new("UIPadding", Results)
rp.PaddingLeft = UDim.new(0, 6); rp.PaddingRight = UDim.new(0, 6)
rp.PaddingTop  = UDim.new(0, 6); rp.PaddingBottom = UDim.new(0, 6)

------------------------------------------------------------
-- STATUS BAR
------------------------------------------------------------
local StatusBar = Instance.new("Frame", Main)
StatusBar.Size = UDim2.new(1, -16, 0, 22)
StatusBar.Position = UDim2.new(0, 8, 1, -28)
StatusBar.BackgroundColor3 = Color3.fromRGB(28, 28, 36)
StatusBar.BorderSizePixel = 0
StatusBar.ZIndex = 101
local stc = Instance.new("UICorner", StatusBar); stc.CornerRadius = UDim.new(0, 4)
local Status = Instance.new("TextLabel", StatusBar)
Status.Size = UDim2.new(1, -16, 1, 0)
Status.Position = UDim2.new(0, 8, 0, 0)
Status.BackgroundTransparency = 1
Status.TextColor3 = Color3.fromRGB(170, 170, 180)
Status.TextSize = 11
Status.Font = Enum.Font.Gotham
Status.TextXAlignment = Enum.TextXAlignment.Left
Status.ZIndex = 102
Status.Text = string.format("Mounted di %s | %s | %s",
    tostring(ScreenGui.Parent), execName, IS_MOBILE and "📱 Mobile" or "🖥 PC")

------------------------------------------------------------
-- SCANNER LOGIC
------------------------------------------------------------
local lastResults = {}

local function fullPath(inst)
    local segs, cur = {}, inst
    while cur and cur ~= game do
        local n = cur.Name
        table.insert(segs, 1, n:match("[^%w_]") and string.format("[%q]", n) or n)
        cur = cur.Parent
    end
    return "game." .. table.concat(segs, ".")
end

local function scan(scanType)
    local found = {}
    for _, root in ipairs(SCAN_ROOTS) do
        local ok, descendants = pcall(function() return root:GetDescendants() end)
        if ok then
            for _, d in ipairs(descendants) do
                if d:IsA(scanType.class) then table.insert(found, d) end
            end
        end
    end
    return found
end

------------------------------------------------------------
-- SPY / HOOK
------------------------------------------------------------
local hooks = {}

local function setupHook(remote)
    if hooks[remote] then return end
    hooks[remote] = true

    if remote:IsA("RemoteEvent") then
        remote.OnClientEvent:Connect(function(...)
            print(string.format("[SPY << SERVER] %s args=%s",
                fullPath(remote), HttpService:JSONEncode({...})))
        end)
        notify("Scanner", "Spy aktif: " .. remote.Name)
    elseif remote:IsA("BindableEvent") then
        remote.Event:Connect(function(...)
            print(string.format("[SPY] %s args=%s",
                fullPath(remote), HttpService:JSONEncode({...})))
        end)
        notify("Scanner", "Spy aktif: " .. remote.Name)
    end
end

local globalSpyActive = false
local function enableGlobalSpy()
    if globalSpyActive then return end
    if not _hookmetamethod then
        notify("Scanner", "hookmetamethod tak tersedia", 4)
        return
    end
    globalSpyActive = true
    local oldNc
    oldNc = _hookmetamethod(game, "__namecall", _newcclosure(function(self, ...)
        local method = _getnamecallmethod()
        if not _checkcaller() and (method == "FireServer" or method == "InvokeServer") then
            local ok, json = pcall(function() return HttpService:JSONEncode({...}) end)
            print(string.format("[SPY >> SERVER] %s:%s(%s)",
                fullPath(self), method, ok and json or "<unserializable>"))
        end
        return oldNc(self, ...)
    end))
    notify("Scanner", "Global Spy AKTIF — log di console", 4)
end

------------------------------------------------------------
-- BUILD ITEM
------------------------------------------------------------
local function buildItem(inst, index)
    local item = Instance.new("Frame", Results)
    item.Size = UDim2.new(1, 0, 0, 50)
    item.BackgroundColor3 = Color3.fromRGB(34, 34, 44)
    item.BorderSizePixel = 0
    item.LayoutOrder = index
    item.ZIndex = 102
    local ic = Instance.new("UICorner", item); ic.CornerRadius = UDim.new(0, 5)

    local name = Instance.new("TextLabel", item)
    name.Size = UDim2.new(1, -120, 0, 20)
    name.Position = UDim2.new(0, 10, 0, 4)
    name.BackgroundTransparency = 1
    name.Text = inst.Name
    name.TextColor3 = Color3.fromRGB(235, 235, 240)
    name.TextSize = 13
    name.Font = Enum.Font.GothamBold
    name.TextXAlignment = Enum.TextXAlignment.Left
    name.TextTruncate = Enum.TextTruncate.AtEnd
    name.ZIndex = 103

    local path = Instance.new("TextLabel", item)
    path.Size = UDim2.new(1, -20, 0, 18)
    path.Position = UDim2.new(0, 10, 0, 26)
    path.BackgroundTransparency = 1
    path.Text = fullPath(inst)
    path.TextColor3 = Color3.fromRGB(155, 165, 180)
    path.TextSize = 10
    path.Font = Enum.Font.Code
    path.TextXAlignment = Enum.TextXAlignment.Left
    path.TextTruncate = Enum.TextTruncate.AtEnd
    path.ZIndex = 103

    local function actionBtn(label, color, offset, cb)
        local b = Instance.new("TextButton", item)
        b.Size = UDim2.new(0, 48, 0, 22)
        b.Position = UDim2.new(1, offset, 0, 4)
        b.BackgroundColor3 = color
        b.Text = label
        b.TextColor3 = Color3.fromRGB(255, 255, 255)
        b.TextSize = 10
        b.Font = Enum.Font.GothamBold
        b.BorderSizePixel = 0
        b.ZIndex = 104
        local c = Instance.new("UICorner", b); c.CornerRadius = UDim.new(0, 4)
        b.MouseButton1Click:Connect(cb)
        return b
    end

    actionBtn("COPY", Color3.fromRGB(75, 130, 200), -56, function()
        _clip(fullPath(inst))
        Status.Text = "✓ Disalin: " .. inst.Name
    end)

    if inst:IsA("RemoteEvent") or inst:IsA("BindableEvent") then
        actionBtn("SPY", Color3.fromRGB(180, 100, 200), -108, function()
            setupHook(inst)
            Status.Text = "🔭 Spy: " .. inst.Name
        end)
    end
end

------------------------------------------------------------
-- RENDER + FILTER
------------------------------------------------------------
local function clearResults()
    for _, c in ipairs(Results:GetChildren()) do
        if c:IsA("Frame") then c:Destroy() end
    end
end

local function render(list)
    clearResults()
    for i, inst in ipairs(list) do
        if i > 500 then
            Status.Text = string.format("⚠ Tampil 500/%d — gunakan search", #list)
            break
        end
        buildItem(inst, i)
    end
end

local function applyFilter()
    local q = SearchBox.Text:lower()
    if q == "" then render(lastResults); return end
    local filtered = {}
    for _, inst in ipairs(lastResults) do
        if inst.Name:lower():find(q, 1, true)
           or fullPath(inst):lower():find(q, 1, true) then
            table.insert(filtered, inst)
        end
    end
    render(filtered)
    Status.Text = string.format("Filter: %d / %d", #filtered, #lastResults)
end

SearchBox:GetPropertyChangedSignal("Text"):Connect(applyFilter)

ScanBtn.MouseButton1Click:Connect(function()
    Status.Text = "⏳ Memindai " .. selectedType.name .. "..."
    task.wait()
    lastResults = scan(selectedType)
    table.sort(lastResults, function(a, b) return a.Name < b.Name end)
    render(lastResults)
    Status.Text = string.format("✓ %d %s ditemukan", #lastResults, selectedType.name)
end)

------------------------------------------------------------
-- GLOBAL SPY trigger: klik kanan title (PC) atau long-press (mobile)
------------------------------------------------------------
local pressStart = 0
TitleBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        enableGlobalSpy()
    elseif input.UserInputType == Enum.UserInputType.Touch then
        pressStart = tick()
    end
end)
TitleBar.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch then
        if tick() - pressStart > 1.2 then enableGlobalSpy() end
    end
end)

------------------------------------------------------------
-- DEBUG INFO + READY
------------------------------------------------------------
print(string.format("[GameScanner v1.1] Mounted=%s | Exec=%s | Mobile=%s | DisplayOrder=%d",
    tostring(ScreenGui.Parent), execName, tostring(IS_MOBILE), ScreenGui.DisplayOrder))
notify("Game Scanner v1.1", "Loaded! Klik kategori → SCAN.", 4)
