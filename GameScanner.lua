--[[
    ╔══════════════════════════════════════════════════════════╗
    ║              GAME SCANNER v1.0                           ║
    ║   Scanner untuk dasar pengembangan fitur baru            ║
    ║   Support: PC Executor & Mobile Executor (Delta,         ║
    ║            Arceus X, Hydrogen, Codex, dll)               ║
    ╚══════════════════════════════════════════════════════════╝

    CARA PAKAI:
      1. Pilih tipe scan di tombol kategori (atas)
      2. Klik "SCAN" untuk mulai menjelajahi game
      3. Klik item hasil untuk copy path ke clipboard
      4. Pakai search bar untuk memfilter hasil
      5. Klik "SPY" pada RemoteEvent/Function untuk hook callnya
      6. Hasil hook bisa dilihat di console (F9 / executor console)

    TAMBAH FITUR BARU:
      - Tambah kategori baru di tabel SCAN_TYPES (cari komentar)
      - Tambah action baru di function buildItem (cari "ACTION BUTTONS")
      - Logika hook ada di function setupHook
--]]

------------------------------------------------------------
-- SERVICES
------------------------------------------------------------
local Players           = game:GetService("Players")
local CoreGui           = game:GetService("CoreGui")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")
local HttpService       = game:GetService("HttpService")
local StarterGui        = game:GetService("StarterGui")

local LocalPlayer = Players.LocalPlayer

------------------------------------------------------------
-- EXECUTOR COMPATIBILITY (PC + Mobile)
------------------------------------------------------------
local IsMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

-- setclipboard (PC: Synapse/Script-Ware/Mobile: Delta/Arceus)
local clipboard = setclipboard
    or (syn and syn.write_clipboard)
    or (Clipboard and Clipboard.set)
    or writeclipboard
    or toclipboard
    or function(t) warn("[Scanner] Clipboard tidak didukung executor ini") end

-- hookfunction / hookmetamethod (untuk fitur SPY)
local hookfunction = hookfunction or hookfunc or replaceclosure
local newcclosure  = newcclosure or function(f) return f end
local getnamecallmethod = getnamecallmethod or get_namecall_method
local checkcaller  = checkcaller or function() return false end

-- Parent yang aman supaya UI tak ke-destroy game
local function getGuiParent()
    if gethui then return gethui() end
    local ok, parent = pcall(function()
        if syn and syn.protect_gui then
            local sg = Instance.new("ScreenGui")
            syn.protect_gui(sg)
            sg.Parent = CoreGui
            return sg
        end
        return CoreGui
    end)
    if ok and parent then return parent end
    return LocalPlayer:WaitForChild("PlayerGui")
end

-- Notifikasi singkat
local function notify(title, text, duration)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title,
            Text = text,
            Duration = duration or 3
        })
    end)
end

-- Cleanup lama
pcall(function()
    local p = getGuiParent()
    if p:FindFirstChild("GameScanner") then p.GameScanner:Destroy() end
end)

------------------------------------------------------------
-- SCAN TYPES (★ Tambah kategori baru di sini ★)
------------------------------------------------------------
local SCAN_TYPES = {
    { name = "RemoteEvents",     class = "RemoteEvent",     icon = "📡" },
    { name = "RemoteFunctions",  class = "RemoteFunction",  icon = "🔄" },
    { name = "BindableEvents",   class = "BindableEvent",   icon = "🔔" },
    { name = "BindableFuncs",    class = "BindableFunction",icon = "⚙️" },
    { name = "ModuleScripts",    class = "ModuleScript",    icon = "📦" },
    { name = "LocalScripts",     class = "LocalScript",     icon = "📜" },
    { name = "Scripts",          class = "Script",          icon = "📄" },
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
-- GUI ROOT
------------------------------------------------------------
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "GameScanner"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.IgnoreGuiInset = true
pcall(function() if syn and syn.protect_gui then syn.protect_gui(ScreenGui) end end)
ScreenGui.Parent = getGuiParent()

------------------------------------------------------------
-- MAIN FRAME
------------------------------------------------------------
local MAIN_W = IsMobile and 340 or 480
local MAIN_H = IsMobile and 400 or 520

local Main = Instance.new("Frame")
Main.Name = "Main"
Main.Size = UDim2.new(0, MAIN_W, 0, MAIN_H)
Main.Position = UDim2.new(0.5, -MAIN_W/2, 0.5, -MAIN_H/2)
Main.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
Main.BorderSizePixel = 0
Main.Active = true
Main.Parent = ScreenGui

local mc = Instance.new("UICorner", Main); mc.CornerRadius = UDim.new(0, 10)
local ms = Instance.new("UIStroke", Main)
ms.Color = Color3.fromRGB(60, 60, 75); ms.Thickness = 1

------------------------------------------------------------
-- TITLE BAR (DRAG ZONE)
------------------------------------------------------------
local TitleBar = Instance.new("Frame")
TitleBar.Name = "TitleBar"
TitleBar.Size = UDim2.new(1, 0, 0, 36)
TitleBar.BackgroundColor3 = Color3.fromRGB(32, 32, 42)
TitleBar.BorderSizePixel = 0
TitleBar.Parent = Main
local tbc = Instance.new("UICorner", TitleBar); tbc.CornerRadius = UDim.new(0, 10)
local tbfix = Instance.new("Frame", TitleBar)
tbfix.Size = UDim2.new(1, 0, 0, 12); tbfix.Position = UDim2.new(0, 0, 1, -12)
tbfix.BackgroundColor3 = TitleBar.BackgroundColor3; tbfix.BorderSizePixel = 0

local Title = Instance.new("TextLabel", TitleBar)
Title.Size = UDim2.new(1, -90, 1, 0)
Title.Position = UDim2.new(0, 12, 0, 0)
Title.BackgroundTransparency = 1
Title.Text = "🔍  Game Scanner"
Title.TextColor3 = Color3.fromRGB(235, 235, 240)
Title.TextSize = 15
Title.Font = Enum.Font.GothamBold
Title.TextXAlignment = Enum.TextXAlignment.Left

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
    b.AutoButtonColor = true
    local c = Instance.new("UICorner", b); c.CornerRadius = UDim.new(0, 4)
    return b
end

local CloseBtn = makeIconBtn("✕", Color3.fromRGB(200, 65, 65), -34)
local MinBtn   = makeIconBtn("—", Color3.fromRGB(85, 85, 100), -66)

CloseBtn.MouseButton1Click:Connect(function() ScreenGui:Destroy() end)

local minimized = false
local origSize = Main.Size
MinBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    local newSize = minimized
        and UDim2.new(0, MAIN_W, 0, 36)
        or origSize
    TweenService:Create(Main, TweenInfo.new(0.22), {Size = newSize}):Play()
end)

------------------------------------------------------------
-- DRAGGING (mouse + touch, support multi-input)
------------------------------------------------------------
do
    local dragging, dragStart, startPos, activeInput

    local function update(input)
        local delta = input.Position - dragStart
        Main.Position = UDim2.new(
            startPos.X.Scale,
            startPos.X.Offset + delta.X,
            startPos.Y.Scale,
            startPos.Y.Offset + delta.Y
        )
    end

    TitleBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
           or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = Main.Position
            activeInput = input
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if dragging and input == activeInput then update(input) end
        -- mouse fallback
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            update(input)
        end
    end)
end

------------------------------------------------------------
-- CATEGORY BAR (scrollable horizontal)
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
local cbc = Instance.new("UICorner", CatBar); cbc.CornerRadius = UDim.new(0, 6)

local cbl = Instance.new("UIListLayout", CatBar)
cbl.FillDirection = Enum.FillDirection.Horizontal
cbl.Padding = UDim.new(0, 4)
cbl.SortOrder = Enum.SortOrder.LayoutOrder
local cbp = Instance.new("UIPadding", CatBar)
cbp.PaddingLeft = UDim.new(0, 4); cbp.PaddingRight = UDim.new(0, 4)
cbp.PaddingTop = UDim.new(0, 4); cbp.PaddingBottom = UDim.new(0, 4)

local selectedType = SCAN_TYPES[1]
local categoryButtons = {}

local function makeCatBtn(scanType, index)
    local b = Instance.new("TextButton", CatBar)
    b.Size = UDim2.new(0, 110, 1, -8)
    b.BackgroundColor3 = Color3.fromRGB(45, 45, 58)
    b.Text = scanType.icon .. " " .. scanType.name
    b.TextColor3 = Color3.fromRGB(220, 220, 225)
    b.TextSize = 11
    b.Font = Enum.Font.GothamMedium
    b.BorderSizePixel = 0
    b.AutoButtonColor = false
    b.LayoutOrder = index
    local c = Instance.new("UICorner", b); c.CornerRadius = UDim.new(0, 4)
    return b
end

local function refreshCatColors()
    for st, btn in pairs(categoryButtons) do
        if st == selectedType then
            TweenService:Create(btn, TweenInfo.new(0.15),
                {BackgroundColor3 = Color3.fromRGB(80, 130, 220)}):Play()
        else
            TweenService:Create(btn, TweenInfo.new(0.15),
                {BackgroundColor3 = Color3.fromRGB(45, 45, 58)}):Play()
        end
    end
end

for i, st in ipairs(SCAN_TYPES) do
    local b = makeCatBtn(st, i)
    categoryButtons[st] = b
    b.MouseButton1Click:Connect(function()
        selectedType = st
        refreshCatColors()
    end)
end
refreshCatColors()

------------------------------------------------------------
-- ACTION BAR (Scan / Search)
------------------------------------------------------------
local ActionBar = Instance.new("Frame", Main)
ActionBar.Size = UDim2.new(1, -16, 0, 32)
ActionBar.Position = UDim2.new(0, 8, 0, 82)
ActionBar.BackgroundTransparency = 1

local ScanBtn = Instance.new("TextButton", ActionBar)
ScanBtn.Size = UDim2.new(0, 80, 1, 0)
ScanBtn.Position = UDim2.new(0, 0, 0, 0)
ScanBtn.BackgroundColor3 = Color3.fromRGB(70, 170, 100)
ScanBtn.Text = "▶ SCAN"
ScanBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ScanBtn.TextSize = 13
ScanBtn.Font = Enum.Font.GothamBold
ScanBtn.BorderSizePixel = 0
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
local sbxc = Instance.new("UICorner", SearchBox); sbxc.CornerRadius = UDim.new(0, 5)
local sbxp = Instance.new("UIPadding", SearchBox)
sbxp.PaddingLeft = UDim.new(0, 10); sbxp.PaddingRight = UDim.new(0, 10)

------------------------------------------------------------
-- RESULTS (scrollable, virtualized via UIListLayout)
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
local rc = Instance.new("UICorner", Results); rc.CornerRadius = UDim.new(0, 6)

local rl = Instance.new("UIListLayout", Results)
rl.Padding = UDim.new(0, 4)
rl.SortOrder = Enum.SortOrder.LayoutOrder
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
local stc = Instance.new("UICorner", StatusBar); stc.CornerRadius = UDim.new(0, 4)

local Status = Instance.new("TextLabel", StatusBar)
Status.Size = UDim2.new(1, -16, 1, 0)
Status.Position = UDim2.new(0, 8, 0, 0)
Status.BackgroundTransparency = 1
Status.Text = "Siap. Pilih kategori lalu klik SCAN."
Status.TextColor3 = Color3.fromRGB(170, 170, 180)
Status.TextSize = 11
Status.Font = Enum.Font.Gotham
Status.TextXAlignment = Enum.TextXAlignment.Left

------------------------------------------------------------
-- SCANNER LOGIC
------------------------------------------------------------
local lastResults = {}     -- semua hasil scan terakhir
local hooks = {}           -- daftar event yang sudah di-spy

local function fullPath(inst)
    -- Buat path lengkap, contoh: game.ReplicatedStorage.Events.HitEvent
    local segs = {}
    local cur = inst
    while cur and cur ~= game do
        table.insert(segs, 1, cur.Name:match("[^%w_]") and string.format("[%q]", cur.Name) or cur.Name)
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
                if d:IsA(scanType.class) then
                    table.insert(found, d)
                end
            end
        end
    end
    return found
end

------------------------------------------------------------
-- SPY / HOOK (untuk RemoteEvent/Function)
------------------------------------------------------------
local function setupHook(remote)
    if hooks[remote] then
        warn("[Scanner] Sudah di-spy: " .. fullPath(remote))
        return
    end
    hooks[remote] = true

    -- Pendekatan signal-based: aman & tak butuh hookmetamethod
    if remote:IsA("RemoteEvent") then
        local conn = remote.OnClientEvent:Connect(function(...)
            local args = {...}
            print(string.format("[SPY << SERVER] %s args=%s",
                fullPath(remote), HttpService:JSONEncode(args)))
        end)
        notify("Scanner", "Spy aktif (server→client) pada " .. remote.Name)
    elseif remote:IsA("BindableEvent") then
        local conn = remote.Event:Connect(function(...)
            print(string.format("[SPY] %s args=%s",
                fullPath(remote), HttpService:JSONEncode({...})))
        end)
        notify("Scanner", "Spy aktif pada " .. remote.Name)
    else
        notify("Scanner", "Tipe ini tidak bisa di-spy via signal")
    end

    -- Untuk hook ARAH SEBALIK (client→server FireServer), butuh hookmetamethod.
    -- Aktifkan blok ini sekali per sesi via tombol "GLOBAL SPY" jika perlu.
end

local globalSpyActive = false
local function enableGlobalSpy()
    if globalSpyActive then return end
    if not hookmetamethod then
        notify("Scanner", "hookmetamethod tidak tersedia di executor ini", 4)
        return
    end
    globalSpyActive = true
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        local method = getnamecallmethod()
        if not checkcaller() and (method == "FireServer" or method == "InvokeServer") then
            local ok, json = pcall(function() return HttpService:JSONEncode({...}) end)
            print(string.format("[SPY >> SERVER] %s:%s(%s)",
                fullPath(self), method, ok and json or "<unserializable>"))
        end
        return oldNamecall(self, ...)
    end))
    notify("Scanner", "Global Spy AKTIF — log di console", 4)
end

------------------------------------------------------------
-- BUILD UI ITEM PER HASIL
------------------------------------------------------------
local function buildItem(inst, index)
    local item = Instance.new("Frame", Results)
    item.Size = UDim2.new(1, 0, 0, 50)
    item.BackgroundColor3 = Color3.fromRGB(34, 34, 44)
    item.BorderSizePixel = 0
    item.LayoutOrder = index
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

    -- ACTION BUTTONS (★ tambah aksi baru di sini ★)
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
        local c = Instance.new("UICorner", b); c.CornerRadius = UDim.new(0, 4)
        b.MouseButton1Click:Connect(cb)
        return b
    end

    actionBtn("COPY", Color3.fromRGB(75, 130, 200), -56, function()
        clipboard(fullPath(inst))
        Status.Text = "✓ Disalin: " .. inst.Name
    end)

    if inst:IsA("RemoteEvent") or inst:IsA("RemoteFunction")
       or inst:IsA("BindableEvent") then
        actionBtn("SPY", Color3.fromRGB(180, 100, 200), -108, function()
            setupHook(inst)
            Status.Text = "🔭 Spy: " .. inst.Name .. " (cek console)"
        end)
    end

    return item
end

------------------------------------------------------------
-- RENDER & FILTER
------------------------------------------------------------
local function clearResults()
    for _, c in ipairs(Results:GetChildren()) do
        if c:IsA("Frame") then c:Destroy() end
    end
end

local function render(list)
    clearResults()
    for i, inst in ipairs(list) do
        if i > 500 then  -- batasi render untuk performa mobile
            Status.Text = string.format("⚠ Terlalu banyak (%d) — tampil 500 pertama. Pakai search.", #list)
            break
        end
        buildItem(inst, i)
    end
end

local function applyFilter()
    local q = SearchBox.Text:lower()
    if q == "" then
        render(lastResults)
        return
    end
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
    task.wait()  -- biarkan UI update dulu
    lastResults = scan(selectedType)
    table.sort(lastResults, function(a, b) return a.Name < b.Name end)
    render(lastResults)
    Status.Text = string.format("✓ %d %s ditemukan",
        #lastResults, selectedType.name)
end)

------------------------------------------------------------
-- HOTKEY: tombol Global Spy lewat menu (opsional)
-- Klik kanan title (PC) atau long-press (mobile) → aktifkan
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

notify("Game Scanner", "Loaded. Klik kategori → SCAN.", 4)
Status.Text = IsMobile
    and "📱 Mobile mode | Long-press title = Global Spy"
    or  "🖥 PC mode | Klik kanan title = Global Spy"
