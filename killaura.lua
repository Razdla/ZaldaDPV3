--[[
═══════════════════════════════════════════════════════════════════════
        HS HUB · Hollowed Era · Killaura  (v1, standalone)
        discord.gg/5rpP6faZSJ
    Built from DeepRecon capture (partner's attack capture):
      ATTACK (M1)  = ReplicatedStorage.RsPackage.Swing:FireServer(combo, {})
                     combo cycles 1..4 (the M1 string).
      AIM          = RsPackage.UpdateMousePosition:FireServer(Vector3int16) [optional]
      ENEMIES      = Workspace.Humanoids children (Models w/ Humanoid) that are NOT
                     players and have a CombatSystem folder (= "Hollow" enemies).
    v1 = proximity killaura: target nearest enemies in range, (optionally TP to them),
    spam Swing with cycling combos. Tune after in-game test (does damage register? is
    TP needed? does the `{}` arg need targets?).
═══════════════════════════════════════════════════════════════════════
]]

if shared.__HSHub_HE_Killaura then pcall(function() shared.__HSHub_HE_Killaura:Destroy() end) end

local Players     = game:GetService('Players')
local RS          = game:GetService('ReplicatedStorage')
local RunService  = game:GetService('RunService')
local LP          = Players.LocalPlayer

local RsPackage   = RS:WaitForChild('RsPackage', 10)
local Swing       = RsPackage and RsPackage:FindFirstChild('Swing')             -- RemoteEvent
local UpdateMouse = RsPackage and RsPackage:FindFirstChild('UpdateMousePosition')-- RemoteEvent
local Humanoids   = workspace:WaitForChild('Humanoids', 10)

-- ═══════════ STATE ═══════════
local S = {
    On        = false,
    Range     = 60,      -- studs
    MaxTargets= 6,       -- enemies hit per cycle
    TP        = false,   -- teleport onto each target before swinging (stronger, riskier)
    Aim       = true,    -- send UpdateMousePosition toward target
    NameOnly  = false,   -- only hit models whose name contains "Hollow"
}
local combo = 1

-- ═══════════ HELPERS ═══════════
local function getRoot()
    local c = LP.Character
    return c and (c:FindFirstChild('HumanoidRootPart') or c.PrimaryPart)
end

-- enemy = a Model in Workspace.Humanoids that is NOT a player and is alive.
-- (players are R15/R6 rigs with no CombatSystem; enemies "Hollow" have CombatSystem + DamageLogs)
local function isEnemy(m)
    if not m:IsA('Model') then return false end
    if Players:GetPlayerFromCharacter(m) then return false end           -- skip players
    local h = m:FindFirstChildOfClass('Humanoid')
    if not h or h.Health <= 0 then return false end
    if S.NameOnly then return m.Name:lower():find('hollow') ~= nil end
    return m:FindFirstChild('CombatSystem') ~= nil or m.Name:lower():find('hollow') ~= nil
end

local function enemiesInRange()
    local root = getRoot(); if not root or not Humanoids then return {} end
    local list = {}
    for _, m in ipairs(Humanoids:GetChildren()) do
        if isEnemy(m) then
            local hrp = m:FindFirstChild('HumanoidRootPart') or m.PrimaryPart or m:FindFirstChildWhichIsA('BasePart')
            if hrp then
                local d = (hrp.Position - root.Position).Magnitude
                if d <= S.Range then list[#list+1] = { m = m, hrp = hrp, d = d } end
            end
        end
    end
    table.sort(list, function(a, b) return a.d < b.d end)
    return list
end

local function clamp16(n) return math.clamp(math.floor(n + 0.5), -32767, 32767) end
local function swingAt(hrp)
    if S.Aim and UpdateMouse and hrp then
        pcall(function()
            UpdateMouse:FireServer(Vector3int16.new(clamp16(hrp.Position.X), clamp16(hrp.Position.Y), clamp16(hrp.Position.Z)))
        end)
    end
    if Swing then pcall(function() Swing:FireServer(combo, {}) end) end
    combo = combo % 4 + 1     -- cycle the M1 string 1->2->3->4
end

-- ═══════════ KILLAURA LOOP ═══════════
task.spawn(function()
    while true do
        task.wait(0.18)
        if S.On then
            pcall(function()
                local enemies = enemiesInRange()
                if #enemies == 0 then return end
                local root = getRoot()
                local home = root and root.CFrame
                local n = math.min(#enemies, S.MaxTargets)
                for i = 1, n do
                    if not S.On then break end
                    local e = enemies[i]
                    if S.TP and root then
                        pcall(function() root.CFrame = e.hrp.CFrame * CFrame.new(0, 0, 4) end)
                        task.wait(0.05)
                    end
                    swingAt(e.hrp)
                end
                if S.TP and root and home then pcall(function() if getRoot() then getRoot().CFrame = home end end) end
            end)
        end
    end
end)

-- ═══════════ MINIMAL UI ═══════════
local gui = Instance.new('ScreenGui')
gui.Name = 'HSHub_HE_Killaura'
gui.ResetOnSpawn = false
gui.Parent = (gethui and gethui()) or LP:WaitForChild('PlayerGui')
shared.__HSHub_HE_Killaura = gui

local f = Instance.new('Frame', gui)
f.Size = UDim2.new(0, 230, 0, 196)
f.Position = UDim2.new(0, 24, 0.4, 0)
f.BackgroundColor3 = Color3.fromRGB(16, 18, 26)
f.BorderSizePixel = 0
f.Active = true; f.Draggable = true
Instance.new('UICorner', f).CornerRadius = UDim.new(0, 8)
local st = Instance.new('UIStroke', f); st.Color = Color3.fromRGB(200, 120, 60); st.Thickness = 1.5

local hdr = Instance.new('TextLabel', f)
hdr.Size = UDim2.new(1, 0, 0, 30); hdr.BackgroundColor3 = Color3.fromRGB(180, 100, 40); hdr.BorderSizePixel = 0
hdr.Font = Enum.Font.GothamBold; hdr.TextSize = 13; hdr.TextColor3 = Color3.fromRGB(245, 245, 250)
hdr.Text = 'HS HUB · Hollowed Era Killaura'
Instance.new('UICorner', hdr).CornerRadius = UDim.new(0, 8)

local status = Instance.new('TextLabel', f)
status.Position = UDim2.new(0, 10, 0, 36); status.Size = UDim2.new(1, -20, 0, 16)
status.BackgroundTransparency = 1; status.Font = Enum.Font.Code; status.TextSize = 11
status.TextColor3 = Color3.fromRGB(200, 160, 100); status.TextXAlignment = Enum.TextXAlignment.Left
status.Text = 'off'

local y = 56
local function rowBtn(text, getOn, onClick)
    local b = Instance.new('TextButton', f)
    b.Position = UDim2.new(0, 10, 0, y); b.Size = UDim2.new(1, -20, 0, 26)
    b.BackgroundColor3 = Color3.fromRGB(34, 38, 50); b.BorderSizePixel = 0
    b.Font = Enum.Font.GothamBold; b.TextSize = 12; b.TextColor3 = Color3.fromRGB(235, 240, 245)
    Instance.new('UICorner', b).CornerRadius = UDim.new(0, 6)
    local function refresh() b.Text = text .. ': ' .. (getOn() and 'ON' or 'OFF') end
    b.MouseButton1Click:Connect(function() onClick(); refresh() end); refresh()
    y = y + 30
    return b
end
rowBtn('Killaura',  function() return S.On end,       function() S.On = not S.On end)
rowBtn('Teleport',  function() return S.TP end,       function() S.TP = not S.TP end)
rowBtn('Hollow only',function() return S.NameOnly end, function() S.NameOnly = not S.NameOnly end)

-- range +/- row
local rl = Instance.new('TextLabel', f)
rl.Position = UDim2.new(0, 10, 0, y); rl.Size = UDim2.new(1, -80, 0, 24); rl.BackgroundTransparency = 1
rl.Font = Enum.Font.Code; rl.TextSize = 12; rl.TextColor3 = Color3.fromRGB(200, 220, 240)
rl.TextXAlignment = Enum.TextXAlignment.Left
local function rtxt() rl.Text = 'Range: ' .. S.Range end
local minus = Instance.new('TextButton', f)
minus.Position = UDim2.new(1, -70, 0, y); minus.Size = UDim2.new(0, 26, 0, 24)
minus.BackgroundColor3 = Color3.fromRGB(34, 38, 50); minus.BorderSizePixel = 0
minus.Font = Enum.Font.GothamBold; minus.TextSize = 14; minus.TextColor3 = Color3.fromRGB(235, 240, 245); minus.Text = '-'
Instance.new('UICorner', minus).CornerRadius = UDim.new(0, 6)
local plus = Instance.new('TextButton', f)
plus.Position = UDim2.new(1, -38, 0, y); plus.Size = UDim2.new(0, 26, 0, 24)
plus.BackgroundColor3 = Color3.fromRGB(34, 38, 50); plus.BorderSizePixel = 0
plus.Font = Enum.Font.GothamBold; plus.TextSize = 14; plus.TextColor3 = Color3.fromRGB(235, 240, 245); plus.Text = '+'
Instance.new('UICorner', plus).CornerRadius = UDim.new(0, 6)
minus.MouseButton1Click:Connect(function() S.Range = math.max(10, S.Range - 10); rtxt() end)
plus.MouseButton1Click:Connect(function() S.Range = math.min(300, S.Range + 10); rtxt() end)
rtxt()

-- live status
task.spawn(function()
    while gui.Parent do
        task.wait(0.3)
        if S.On then
            local n = #enemiesInRange()
            status.Text = ('ON · %d enemies in %d'):format(n, S.Range)
        else
            status.Text = (Swing and 'off (Swing ✓)' or 'off (Swing NOT FOUND)')
        end
    end
end)
