--[[
═══════════════════════════════════════════════════════════════════════
    HS HUB COS — Diagnostic V2 EXTENDED
    Full game-structure map: finds the 17 LUNAR remotes wherever they
    live in the current game build. Output: UI panel + writefile.
═══════════════════════════════════════════════════════════════════════
]]

-- ═════════════ TARGET REMOTES TO LOCATE ═══════════════════════════
local TARGETS = {
    'DrinkRemote', 'Food', 'Mud', 'Lay', 'Nest',
    'LavaSelfDamage', 'StatAilment', 'Sheltered',
    'RestartSlotRemote', 'GetSpawnedTokenRemote',
    'StoreActiveCreatureRemote', 'CreateSlotRemote',
    'PickupResource', 'DepositResource', 'ChunkResource',
    'ResourceDamageRemote', 'UpgradeNest',
    -- already found in LP.Remotes (for completeness)
    'NestRequestRemote', 'NestJoinRequestRemote',
    'PartyRequestRemote', 'PartyJoinRequestRemote',
    'NestSlotPickRequestRemote',
}

-- ═════════════ COLLECT ═══════════════════════════════════════════
local LP = game:GetService('Players').LocalPlayer
local RS = game:GetService('ReplicatedStorage')
local WS = game:GetService('Workspace')

local results = { _order = {} }
local function R(key, ok, detail)
    results[key] = { ok = ok, detail = detail or '' }
    table.insert(results._order, key)
end

-- ═════════════ SCAN: full descendant walk per root ═══════════════
local found = {}  -- found[remote_name] = {path1, path2, ...}
local containers = {}  -- containers[full_path] = count of children

local function fullPath(inst)
    local segments = {}
    local cur = inst
    while cur and cur ~= game do
        table.insert(segments, 1, cur.Name)
        cur = cur.Parent
    end
    return 'game.' .. table.concat(segments, '.')
end

local function isRemote(inst)
    return inst:IsA('RemoteEvent') or inst:IsA('RemoteFunction')
        or inst:IsA('BindableEvent') or inst:IsA('BindableFunction')
end

local targetSet = {}
for _, n in ipairs(TARGETS) do targetSet[n] = true end

local function scanRoot(root, label, maxDepth)
    maxDepth = maxDepth or 8
    local function walk(node, depth)
        if depth > maxDepth then return end
        local ok, children = pcall(function() return node:GetChildren() end)
        if not ok or not children then return end
        for _, c in ipairs(children) do
            local cls = c.ClassName
            -- Track ANY remote
            if isRemote(c) then
                local key = c.Name
                if not found[key] then found[key] = {} end
                table.insert(found[key], fullPath(c) .. '  [' .. cls .. ']')
            end
            -- Track folders/models for context
            if cls == 'Folder' or cls == 'Configuration' or c.Name:lower():find('remote') then
                local p = fullPath(c)
                if not containers[p] then
                    -- count remote-like children
                    local cnt = 0
                    pcall(function()
                        for _, cc in ipairs(c:GetChildren()) do
                            if isRemote(cc) then cnt = cnt + 1 end
                        end
                    end)
                    if cnt > 0 then containers[p] = cnt end
                end
            end
            walk(c, depth + 1)
        end
    end
    walk(root, 0)
end

-- Scan in order of likelihood
scanRoot(RS,             'ReplicatedStorage', 10)
scanRoot(LP,             'LocalPlayer',        6)
scanRoot(WS,             'Workspace',          6)
local char = LP.Character
if char then scanRoot(char, 'Character', 4) end

-- Specific paths chunk3_pretty mentioned
do
    local ok, rfolder = pcall(function() return RS._replicationFolder end)
    R('RS._replicationFolder', ok and rfolder ~= nil, ok and rfolder and 'exists' or 'NOT FOUND')
    if ok and rfolder then
        local hud = rfolder:FindFirstChild('HUDGui')
        R('RS._replicationFolder.HUDGui', hud ~= nil, hud and ('class=' .. hud.ClassName) or 'NOT FOUND')
    end
end

-- Workspace.Interactions paths (for findNearestFood / Mud / WaterSources)
do
    local interactions = WS:FindFirstChild('Interactions')
    R('Workspace.Interactions', interactions ~= nil,
        interactions and ('children=' .. #interactions:GetChildren()) or 'NOT FOUND')
    if interactions then
        local kids = {}
        for _, c in ipairs(interactions:GetChildren()) do table.insert(kids, c.Name) end
        R('Interactions children', true, table.concat(kids, ', '):sub(1, 200))

        for _, sub in ipairs({'Food', 'Mud', 'WaterSources', 'Water', 'Nests', 'AbandonedEggs', 'GachaTokens'}) do
            local f = interactions:FindFirstChild(sub)
            R('Interactions.' .. sub, f ~= nil, f and ('children=' .. #f:GetChildren()) or 'missing')
        end
    end
end

-- ═════════════ BUILD FINDINGS TABLE ════════════════════════════════
for _, name in ipairs(TARGETS) do
    local paths = found[name]
    if paths and #paths > 0 then
        for i, p in ipairs(paths) do
            R('R: ' .. name .. (i > 1 and (' #' .. i) or ''), true, p)
        end
    else
        R('R: ' .. name, false, 'NOT FOUND anywhere')
    end
end

-- ALL containers with remotes
local containerKeys = {}
for k in pairs(containers) do table.insert(containerKeys, k) end
table.sort(containerKeys)
for _, p in ipairs(containerKeys) do
    R('FOLDER: ' .. p, true, containers[p] .. ' remotes')
end

-- ═════════════ WRITE TO FILE + UI ════════════════════════════════
local pass, fail = 0, 0
for _, k in ipairs(results._order) do
    if results[k].ok then pass = pass + 1 else fail = fail + 1 end
end

local out_lines = {
    'HS Hub COS — Diagnostic V2 EXTENDED',
    ('Time: %s'):format(os.date('%Y-%m-%d %H:%M:%S')),
    ('Place: %s  Game: %s'):format(tostring(game.PlaceId),
        (function()
            local ok, info = pcall(function() return game:GetService('MarketplaceService'):GetProductInfo(game.PlaceId) end)
            return ok and info and info.Name or '?'
        end)()),
    ('Pass: %d  Fail: %d  Total: %d'):format(pass, fail, #results._order),
    string.rep('=', 70),
    'TARGET REMOTES (the 17 LUNAR features need these):',
    string.rep('-', 70),
}
for _, name in ipairs(TARGETS) do
    local paths = found[name]
    if paths and #paths > 0 then
        table.insert(out_lines, ('[FOUND] %s'):format(name))
        for _, p in ipairs(paths) do
            table.insert(out_lines, ('         %s'):format(p))
        end
    else
        table.insert(out_lines, ('[MISS]  %s  --  not found anywhere'):format(name))
    end
end

table.insert(out_lines, '')
table.insert(out_lines, string.rep('=', 70))
table.insert(out_lines, 'CONTAINERS holding remote-likes:')
table.insert(out_lines, string.rep('-', 70))
for _, p in ipairs(containerKeys) do
    table.insert(out_lines, ('  %-50s  (%d remotes)'):format(p, containers[p]))
end

table.insert(out_lines, '')
table.insert(out_lines, string.rep('=', 70))
table.insert(out_lines, 'OTHER CHECKS:')
table.insert(out_lines, string.rep('-', 70))
for _, k in ipairs(results._order) do
    if not k:find('^R: ') and not k:find('^FOLDER: ') then
        local r = results[k]
        table.insert(out_lines, ('%s  %-32s  %s'):format(r.ok and '[OK]' or '[FAIL]', k, tostring(r.detail)))
    end
end

local out_text = table.concat(out_lines, '\n')
local save_path = 'HSHub_COS_Diagnostic_V2.txt'
local save_ok = false
pcall(function()
    if type(writefile) == 'function' then writefile(save_path, out_text); save_ok = true end
end)
pcall(function()
    if setclipboard then setclipboard(out_text)
    elseif toclipboard then toclipboard(out_text) end
end)

-- ═════════════ UI PANEL ═══════════════════════════════════════════
local PG = LP:WaitForChild('PlayerGui')
pcall(function()
    for _, g in ipairs((gethui and gethui() or PG):GetChildren()) do
        if g.Name and g.Name:find('^HSHub_Diag') then pcall(function() g:Destroy() end) end
    end
end)

local gui = Instance.new('ScreenGui')
gui.Name = 'HSHub_Diag_V2_' .. tostring(math.random(100000, 999999))
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = (gethui and gethui()) or PG

local frame = Instance.new('Frame', gui)
frame.Size = UDim2.new(0, 420, 0, 520)
frame.Position = UDim2.new(0.5, -210, 0.5, -260)
frame.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true
Instance.new('UICorner', frame).CornerRadius = UDim.new(0, 10)
local stroke = Instance.new('UIStroke', frame)
stroke.Color = Color3.fromRGB(140, 90, 220); stroke.Thickness = 1.5

local header = Instance.new('Frame', frame)
header.Size = UDim2.new(1, 0, 0, 50)
header.BackgroundColor3 = Color3.fromRGB(140, 90, 220)
header.BorderSizePixel = 0
Instance.new('UICorner', header).CornerRadius = UDim.new(0, 10)
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
title.Text = 'HS HUB · Diagnostic V2 (remote-finder)'

local closeBtn = Instance.new('TextButton', header)
closeBtn.BackgroundTransparency = 1
closeBtn.Size = UDim2.new(0, 40, 0, 40)
closeBtn.Position = UDim2.new(1, -45, 0, 5)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 22
closeBtn.TextColor3 = Color3.fromRGB(245, 245, 250)
closeBtn.Text = '×'
closeBtn.MouseButton1Click:Connect(function() gui:Destroy() end)

local foundCount = 0; for _ in pairs(found) do foundCount = foundCount + 1 end
local targetFoundCount = 0
for _, n in ipairs(TARGETS) do if found[n] then targetFoundCount = targetFoundCount + 1 end end

local summary = Instance.new('TextLabel', frame)
summary.BackgroundTransparency = 1
summary.Size = UDim2.new(1, -28, 0, 22)
summary.Position = UDim2.new(0, 14, 0, 56)
summary.Font = Enum.Font.GothamSemibold
summary.TextSize = 13
summary.TextColor3 = Color3.fromRGB(140, 230, 200)
summary.TextXAlignment = Enum.TextXAlignment.Left
summary.Text = ('Targets found: %d / %d   |   Total remotes seen: %d')
    :format(targetFoundCount, #TARGETS, foundCount)

local savedLbl = Instance.new('TextLabel', frame)
savedLbl.BackgroundTransparency = 1
savedLbl.Size = UDim2.new(1, -28, 0, 16)
savedLbl.Position = UDim2.new(0, 14, 0, 80)
savedLbl.Font = Enum.Font.Gotham
savedLbl.TextSize = 11
savedLbl.TextColor3 = Color3.fromRGB(160, 150, 200)
savedLbl.TextXAlignment = Enum.TextXAlignment.Left
savedLbl.Text = save_ok
    and ('Saved: workspace/' .. save_path .. ' · also in clipboard')
    or  'writefile unavailable. Clipboard has full results.'

local scroll = Instance.new('ScrollingFrame', frame)
scroll.Size = UDim2.new(1, -20, 1, -150)
scroll.Position = UDim2.new(0, 10, 0, 104)
scroll.BackgroundColor3 = Color3.fromRGB(14, 14, 22)
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 4
scroll.ScrollBarImageColor3 = Color3.fromRGB(140, 90, 220)
Instance.new('UICorner', scroll).CornerRadius = UDim.new(0, 6)

local layout = Instance.new('UIListLayout', scroll)
layout.Padding = UDim.new(0, 2); layout.SortOrder = Enum.SortOrder.LayoutOrder
local pad = Instance.new('UIPadding', scroll)
pad.PaddingTop = UDim.new(0, 4); pad.PaddingLeft = UDim.new(0, 6); pad.PaddingRight = UDim.new(0, 4)

local function row(text, color, lo)
    local lbl = Instance.new('TextLabel', scroll)
    lbl.BackgroundTransparency = 1
    lbl.Size = UDim2.new(1, -12, 0, 18)
    lbl.LayoutOrder = lo
    lbl.Font = Enum.Font.Code
    lbl.TextSize = 11
    lbl.TextColor3 = color
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.TextTruncate = Enum.TextTruncate.AtEnd
    lbl.Text = text
end

local lo = 0
row('=== TARGET REMOTES (17 LUNAR features) ===',
    Color3.fromRGB(220, 200, 255), lo); lo = lo + 1
for _, name in ipairs(TARGETS) do
    local paths = found[name]
    if paths and #paths > 0 then
        row(('[OK] %s'):format(name), Color3.fromRGB(170, 230, 180), lo); lo = lo + 1
        for _, p in ipairs(paths) do
            row(('     %s'):format(p), Color3.fromRGB(150, 180, 220), lo); lo = lo + 1
        end
    else
        row(('[MISS] %s'):format(name), Color3.fromRGB(255, 150, 150), lo); lo = lo + 1
    end
end

row('', Color3.fromRGB(255, 255, 255), lo); lo = lo + 1
row('=== FOLDERS containing remotes ===',
    Color3.fromRGB(220, 200, 255), lo); lo = lo + 1
for _, p in ipairs(containerKeys) do
    row(('[%d] %s'):format(containers[p], p), Color3.fromRGB(200, 200, 230), lo); lo = lo + 1
end

row('', Color3.fromRGB(255, 255, 255), lo); lo = lo + 1
row('=== STRUCTURE ===',
    Color3.fromRGB(220, 200, 255), lo); lo = lo + 1
for _, k in ipairs(results._order) do
    if not k:find('^R: ') and not k:find('^FOLDER: ') then
        local r = results[k]
        row(('%s %s = %s'):format(r.ok and '✓' or '✗', k, tostring(r.detail):sub(1, 60)),
            r.ok and Color3.fromRGB(170, 230, 180) or Color3.fromRGB(255, 150, 150), lo); lo = lo + 1
    end
end

scroll.CanvasSize = UDim2.new(0, 0, 0, lo * 20 + 8)

local footer = Instance.new('TextLabel', frame)
footer.BackgroundTransparency = 1
footer.Size = UDim2.new(1, -28, 0, 36)
footer.Position = UDim2.new(0, 14, 1, -42)
footer.Font = Enum.Font.Gotham
footer.TextSize = 11
footer.TextColor3 = Color3.fromRGB(180, 180, 210)
footer.TextXAlignment = Enum.TextXAlignment.Left
footer.TextYAlignment = Enum.TextYAlignment.Top
footer.TextWrapped = true
footer.Text = save_ok
    and ('Send HSHub_COS_Diagnostic_V2.txt to Claude. ' ..
         'Targets found: ' .. targetFoundCount .. '/' .. #TARGETS)
    or  'writefile unavailable — clipboard has full text.'
