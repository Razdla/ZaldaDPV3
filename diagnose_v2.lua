--[[
═══════════════════════════════════════════════════════════════════════
    HS HUB COS — V2 Diagnostic Script (UI version)
    Output: small floating UI panel + writefile to executor workspace.
    No console output.
═══════════════════════════════════════════════════════════════════════
]]

local results = { _order = {} }
local function R(key, ok, detail)
    results[key] = { ok = ok, detail = detail or '' }
    table.insert(results._order, key)
end

-- ═══════════════════════════════════════════════════════════════════
--   ALL DIAGNOSTIC CHECKS (silent — populate `results` only)
-- ═══════════════════════════════════════════════════════════════════

-- 1. EXECUTOR
do
    local n = 'unknown'
    pcall(function() n = identifyexecutor and identifyexecutor() or 'no_identifyexecutor' end)
    R('executor', true, tostring(n))
    R('_VERSION', true, tostring(_VERSION))
end

-- 2. CORE PRIMITIVES
R('loadstring',    type(loadstring) == 'function', type(loadstring))
R('load',          type(load) == 'function', type(load))
R('setfenv',       type(setfenv) == 'function', type(setfenv))
R('getfenv',       type(getfenv) == 'function', type(getfenv))
R('getgenv',       type(getgenv) == 'function', type(getgenv))
R('task.wait',     type(task) == 'table' and type(task.wait) == 'function', '')
R('table.unpack',  type(table.unpack) == 'function' or type(unpack) == 'function', '')

-- 3. BIT32
do
    local b = bit32
    if type(b) ~= 'table' then R('bit32', false, 'NIL') else
        R('bit32.band',     type(b.band)    == 'function', '')
        R('bit32.countrz',  type(b.countrz) == 'function', '')
        R('bit32.countlz',  type(b.countlz) == 'function', '')
        R('bit32.byteswap', type(b.byteswap)== 'function', '')
        R('bit32.replace',  type(b.replace) == 'function', '')
        R('bit32.lrotate',  type(b.lrotate) == 'function', '')
    end
end

-- 4. STRING.UNPACK
do
    local ok1, v = pcall(string.unpack, '<I4', '\x01\x02\x03\x04')
    R('string.unpack <I4', ok1, tostring(v))
    local ok2, v2 = pcall(string.unpack, '<d', '\x00\x00\x00\x00\x00\x00\xf0\x3f')
    R('string.unpack <d', ok2, tostring(v2))
    local ok3, v3 = pcall(string.unpack, '<i8', '\x01\x00\x00\x00\x00\x00\x00\x00')
    R('string.unpack <i8', ok3, tostring(v3))
end

-- 5. LOADSTRING
do
    local fn, err = (loadstring or load)('return 1+2+3+4+5', 'test')
    if fn then
        local ok, val = pcall(fn)
        R('loadstring small', ok and val == 15, tostring(val))
    else
        R('loadstring small', false, tostring(err))
    end
    local big = 'return (' .. string.rep('1+', 5000) .. '0)'
    local bfn, berr = (loadstring or load)(big, 'big')
    R('loadstring big', bfn ~= nil, bfn and 'compiled' or tostring(berr))
    local cn, cerr = (loadstring or load)('return 1', 'Luraph    ')
    R('loadstring chunkname', cn ~= nil, cn and 'ok' or tostring(cerr))
end

-- 6. STRING ALLOC
do
    local parts = {}
    for i = 1, 100 do parts[i] = string.rep('\xAB\xCD\xEF', 100) end
    local s = table.concat(parts)
    R('hex concat 30KB', #s == 30000, ('%d bytes'):format(#s))
    local big_parts = {}
    for i = 1, 1500 do big_parts[i] = string.rep('\xAB', 400) end
    local huge = table.concat(big_parts)
    R('hex concat 600KB', #huge == 600000, ('%d bytes'):format(#huge))
    local ok, big = pcall(function() return string.rep('X', 2 * 1024 * 1024) end)
    R('alloc 2MB', ok, ok and 'ok' or 'failed')
end

-- 7. SERVICES
R('svc Players', pcall(game.GetService, game, 'Players'), '')
R('svc ReplicatedStorage', pcall(game.GetService, game, 'ReplicatedStorage'), '')
R('svc Workspace', pcall(game.GetService, game, 'Workspace'), '')

-- 8. LOCALPLAYER + PLAYERGUI + HUDGUI
do
    local LP = game:GetService('Players').LocalPlayer
    R('LocalPlayer', LP ~= nil, LP and LP.Name or 'nil')
    local PG = LP and LP:FindFirstChild('PlayerGui')
    R('PlayerGui', PG ~= nil, '')
    if PG then
        local hud = PG:FindFirstChild('HUDGui')
        R('HUDGui', hud ~= nil, hud and 'found' or 'NOT FOUND')
        if hud then
            local ok, t = pcall(function() return hud.BottomFrame.Other.Thirst.HoverLabel.Text end)
            R('HUDGui Thirst path', ok, ok and t or 'path missing')
            local ok2 = pcall(function() return hud.BottomFrame.Other.Hunger.HoverLabel.Text end)
            R('HUDGui Hunger path', ok2, '')
        end
    end
end

-- 9. REMOTES FOLDER
do
    local LP = game:GetService('Players').LocalPlayer
    local rfolder = LP and LP:FindFirstChild('Remotes')
    R('LP.Remotes', rfolder ~= nil, rfolder and 'found' or 'NOT FOUND')
    if rfolder then
        local names = {}
        for _, c in ipairs(rfolder:GetChildren()) do table.insert(names, c.Name) end
        R('LP.Remotes count', #names > 0, ('%d remotes'):format(#names))
        R('LP.Remotes names', #names > 0, table.concat(names, ', '))
    end
end

-- 10. GAME IDENTITY
R('PlaceId', true, tostring(game.PlaceId))
do
    local ok, info = pcall(function() return game:GetService('MarketplaceService'):GetProductInfo(game.PlaceId) end)
    R('GameName', ok, ok and info and info.Name or 'unknown')
end

-- 11. WRITEFILE CAPABILITY
do
    R('writefile', type(writefile) == 'function', type(writefile))
    R('readfile',  type(readfile)  == 'function', type(readfile))
    R('isfolder',  type(isfolder)  == 'function', type(isfolder))
    R('makefolder',type(makefolder)== 'function', type(makefolder))
end

-- ═══════════════════════════════════════════════════════════════════
--   SAVE TO WORKSPACE (writefile)
-- ═══════════════════════════════════════════════════════════════════
local pass, fail = 0, 0
for _, k in ipairs(results._order) do
    if results[k].ok then pass = pass + 1 else fail = fail + 1 end
end

local out_lines = {
    'HS Hub COS — V2 Diagnostic Results',
    ('Time: %s'):format(os.date('%Y-%m-%d %H:%M:%S')),
    ('Pass: %d  Fail: %d  Total: %d'):format(pass, fail, #results._order),
    string.rep('-', 60),
}
for _, k in ipairs(results._order) do
    local r = results[k]
    table.insert(out_lines, ('%s  %-26s  %s'):format(r.ok and '[OK]' or '[FAIL]', k, tostring(r.detail)))
end
local out_text = table.concat(out_lines, '\n')

local save_path = 'HSHub_COS_Diagnostic.txt'
local save_ok, save_err = pcall(function()
    if type(writefile) == 'function' then writefile(save_path, out_text) end
end)

-- Also clipboard
pcall(function()
    if setclipboard then setclipboard(out_text)
    elseif toclipboard then toclipboard(out_text) end
end)

-- ═══════════════════════════════════════════════════════════════════
--   UI PANEL (HS Hub branded — purple→cyan gradient)
-- ═══════════════════════════════════════════════════════════════════
local LP = game:GetService('Players').LocalPlayer
local PG = LP:WaitForChild('PlayerGui')

pcall(function()
    -- Cleanup previous diag UI
    for _, g in ipairs((gethui and gethui() or PG):GetChildren()) do
        if g.Name and g.Name:find('^HSHub_Diag_') then pcall(function() g:Destroy() end) end
    end
end)

local gui = Instance.new('ScreenGui')
gui.Name = 'HSHub_Diag_' .. tostring(math.random(100000, 999999))
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = (gethui and gethui()) or PG

-- Outer frame
local frame = Instance.new('Frame', gui)
frame.Size = UDim2.new(0, 380, 0, 470)
frame.Position = UDim2.new(0.5, -190, 0.5, -235)
frame.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
frame.BackgroundTransparency = 0.05
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true

local corner = Instance.new('UICorner', frame); corner.CornerRadius = UDim.new(0, 10)
local stroke = Instance.new('UIStroke', frame)
stroke.Color = Color3.fromRGB(140, 90, 220); stroke.Thickness = 1.5

-- Header gradient bar
local header = Instance.new('Frame', frame)
header.Size = UDim2.new(1, 0, 0, 50)
header.Position = UDim2.new(0, 0, 0, 0)
header.BackgroundColor3 = Color3.fromRGB(140, 90, 220)
header.BorderSizePixel = 0
local hCorner = Instance.new('UICorner', header); hCorner.CornerRadius = UDim.new(0, 10)
local hGrad = Instance.new('UIGradient', header)
hGrad.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(140, 90, 220)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(90, 200, 230)),
})

local title = Instance.new('TextLabel', header)
title.BackgroundTransparency = 1
title.Size = UDim2.new(1, -60, 1, 0)
title.Position = UDim2.new(0, 14, 0, 0)
title.Font = Enum.Font.GothamBold
title.TextSize = 16
title.TextColor3 = Color3.fromRGB(245, 245, 250)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = 'HS HUB · V2 Diagnostic'

local closeBtn = Instance.new('TextButton', header)
closeBtn.BackgroundTransparency = 1
closeBtn.Size = UDim2.new(0, 40, 0, 40)
closeBtn.Position = UDim2.new(1, -45, 0, 5)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 20
closeBtn.TextColor3 = Color3.fromRGB(245, 245, 250)
closeBtn.Text = '×'
closeBtn.MouseButton1Click:Connect(function() gui:Destroy() end)

-- Status summary
local summary = Instance.new('TextLabel', frame)
summary.BackgroundTransparency = 1
summary.Size = UDim2.new(1, -28, 0, 26)
summary.Position = UDim2.new(0, 14, 0, 56)
summary.Font = Enum.Font.Gotham
summary.TextSize = 13
summary.TextColor3 = (fail == 0) and Color3.fromRGB(120, 230, 150) or Color3.fromRGB(255, 180, 120)
summary.TextXAlignment = Enum.TextXAlignment.Left
summary.Text = ('PASS: %d   FAIL: %d   TOTAL: %d'):format(pass, fail, #results._order)

-- Save path label
local savedLbl = Instance.new('TextLabel', frame)
savedLbl.BackgroundTransparency = 1
savedLbl.Size = UDim2.new(1, -28, 0, 16)
savedLbl.Position = UDim2.new(0, 14, 0, 82)
savedLbl.Font = Enum.Font.Gotham
savedLbl.TextSize = 11
savedLbl.TextColor3 = Color3.fromRGB(160, 150, 200)
savedLbl.TextXAlignment = Enum.TextXAlignment.Left
savedLbl.Text = save_ok
    and ('Saved: workspace/' .. save_path .. '  ·  also copied to clipboard')
    or  ('writefile failed: ' .. tostring(save_err))

-- Scrollable result list
local scroll = Instance.new('ScrollingFrame', frame)
scroll.Size = UDim2.new(1, -20, 1, -160)
scroll.Position = UDim2.new(0, 10, 0, 106)
scroll.BackgroundColor3 = Color3.fromRGB(14, 14, 22)
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 4
scroll.ScrollBarImageColor3 = Color3.fromRGB(140, 90, 220)
scroll.CanvasSize = UDim2.new(0, 0, 0, #results._order * 22 + 8)

local sCorner = Instance.new('UICorner', scroll); sCorner.CornerRadius = UDim.new(0, 6)
local layout = Instance.new('UIListLayout', scroll)
layout.Padding = UDim.new(0, 2)
layout.SortOrder = Enum.SortOrder.LayoutOrder
local pad = Instance.new('UIPadding', scroll); pad.PaddingTop = UDim.new(0, 4); pad.PaddingLeft = UDim.new(0, 6)

for i, k in ipairs(results._order) do
    local r = results[k]
    local row = Instance.new('TextLabel', scroll)
    row.BackgroundTransparency = 1
    row.Size = UDim2.new(1, -12, 0, 20)
    row.LayoutOrder = i
    row.Font = Enum.Font.Code
    row.TextSize = 11
    row.TextColor3 = r.ok and Color3.fromRGB(170, 230, 180) or Color3.fromRGB(255, 150, 150)
    row.TextXAlignment = Enum.TextXAlignment.Left
    row.TextTruncate = Enum.TextTruncate.AtEnd
    row.Text = ('%s %-22s %s'):format(r.ok and '✓' or '✗', k, tostring(r.detail))
end

-- Footer with instructions
local footer = Instance.new('TextLabel', frame)
footer.BackgroundTransparency = 1
footer.Size = UDim2.new(1, -28, 0, 40)
footer.Position = UDim2.new(0, 14, 1, -46)
footer.Font = Enum.Font.Gotham
footer.TextSize = 11
footer.TextColor3 = Color3.fromRGB(180, 180, 210)
footer.TextXAlignment = Enum.TextXAlignment.Left
footer.TextYAlignment = Enum.TextYAlignment.Top
footer.TextWrapped = true
footer.Text = save_ok
    and 'Send HSHub_COS_Diagnostic.txt OR clipboard text to Claude.\nDiscord: discord.gg/5rpP6faZSJ'
    or  'writefile unavailable. Use clipboard (already copied) OR screenshot this panel.'
