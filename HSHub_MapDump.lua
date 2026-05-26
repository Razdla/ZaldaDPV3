--[[
═══════════════════════════════════════════════════════════════════════
                    HS HUB · MapDump
        Full workspace map scan — food, shrines, mud, lakes, etc.
                    discord.gg/5rpP6faZSJ

    Purpose:
        ONE-TIME scan of game map structure. Output exact names + paths
        + positions for ALL relevant objects so HSHub module can do
        dynamic lookups without guessing.

    What it dumps (per folder under workspace.Interactions):
        - Food (all models, especially carcass variants — for artifact farm)
        - Warden Shrines (all 8 with positions)
        - Mud (for AutoMudRoll)
        - Lakes (for AutoDrink)
        - TokenNodes, ResourceNodes (for token/resource farm)
        - AbandonedEggSpawns (for egg ESP)
        - Everything else under Interactions

    Workflow:
        1. Spawn in game
        2. Paste this script
        3. UI: "Scan Map" button → walks workspace + dumps JSON
        4. Save → file + clipboard
        5. Send JSON to me; I patch module.lua with hardcoded paths

    NO LUNAR LOAD NEEDED. Pure static scan.
═══════════════════════════════════════════════════════════════════════
]]

if shared.__HSHub_MapDump_Running then
    pcall(function() shared.__HSHub_MapDump_Running:Destroy() end)
end

local Players = game:GetService('Players')
local LP      = Players.LocalPlayer
local PG      = LP:WaitForChild('PlayerGui')
local WS      = game:GetService('Workspace')

local OUT = {
    time = os.date('%Y-%m-%d %H:%M:%S'),
    place_id = game.PlaceId,
    interactions = {},
    -- Detailed structures for key folders
    food_models = {},     -- per food model: name, class, position, has_carcass, children
    shrines = {},          -- per shrine: name, position, sub-parts
    mud_spots = {},
    lakes = {},
    abandoned_eggs = {},
    token_nodes = {},
}

-- ═════════════ HELPERS ══════════════════════════════════════════
local function partOf(inst)
    if not inst then return nil end
    if inst:IsA('BasePart') then return inst end
    if inst:IsA('Model') then
        return inst.PrimaryPart or inst:FindFirstChildWhichIsA('BasePart')
    end
    return nil
end

local function posStr(p)
    if not p then return nil end
    return ('%.1f,%.1f,%.1f'):format(p.X, p.Y, p.Z)
end

local function getPos(inst)
    local p = partOf(inst); return p and posStr(p.Position) or nil
end

-- Get all children of inst as list of {name, class}
local function childList(inst, max)
    local list = {}
    if not inst then return list end
    for i, c in ipairs(inst:GetChildren()) do
        if max and i > max then break end
        table.insert(list, { name = c.Name, class = c.ClassName })
    end
    return list
end

-- ═════════════ SCAN FUNCTIONS ═══════════════════════════════════
local function scanInteractions()
    local inter = WS:FindFirstChild('Interactions')
    if not inter then
        OUT.error = 'workspace.Interactions not found'
        return
    end

    for _, folder in ipairs(inter:GetChildren()) do
        local entry = {
            name = folder.Name,
            class = folder.ClassName,
            child_count = #folder:GetChildren(),
        }
        -- Sample first 5 child names (just for overview)
        local samples = {}
        for i, c in ipairs(folder:GetChildren()) do
            if i > 5 then break end
            samples[#samples+1] = c.Name
        end
        entry.sample_children = samples
        table.insert(OUT.interactions, entry)
    end
end

local function scanFood()
    local inter = WS:FindFirstChild('Interactions')
    local foodFolder = inter and inter:FindFirstChild('Food')
    if not foodFolder then return end

    for _, m in ipairs(foodFolder:GetChildren()) do
        local entry = {
            name = m.Name,
            class = m.ClassName,
            position = getPos(m),
            is_carcass = (m.Name:lower():find('carcass') ~= nil),
        }
        -- Look for common food internals
        if m:IsA('Model') then
            local internals = {}
            for _, c in ipairs(m:GetChildren()) do
                if c:IsA('Configuration') or c:IsA('NumberValue') or c:IsA('StringValue') or c:IsA('IntValue') then
                    internals[#internals+1] = { name = c.Name, class = c.ClassName, value = tostring(c.Value or '?') }
                end
            end
            -- attributes
            local attrs = {}
            pcall(function()
                for k, v in pairs(m:GetAttributes()) do
                    attrs[#attrs+1] = { key = k, value = tostring(v) }
                end
            end)
            if #internals > 0 then entry.internals = internals end
            if #attrs > 0 then entry.attributes = attrs end
        end
        table.insert(OUT.food_models, entry)
    end
end

local function scanShrines()
    local inter = WS:FindFirstChild('Interactions')
    local shrineFolder = inter and inter:FindFirstChild('Warden Shrines')
    if not shrineFolder then return end

    for _, s in ipairs(shrineFolder:GetChildren()) do
        local entry = {
            name = s.Name,
            class = s.ClassName,
            position = getPos(s),
            sub_parts = childList(s, 10),
        }
        -- attributes
        local attrs = {}
        pcall(function()
            for k, v in pairs(s:GetAttributes()) do
                attrs[#attrs+1] = { key = k, value = tostring(v) }
            end
        end)
        if #attrs > 0 then entry.attributes = attrs end
        table.insert(OUT.shrines, entry)
    end
end

local function scanMud()
    local inter = WS:FindFirstChild('Interactions')
    local mudFolder = inter and inter:FindFirstChild('Mud')
    if not mudFolder then return end
    for _, m in ipairs(mudFolder:GetChildren()) do
        table.insert(OUT.mud_spots, {
            name = m.Name, class = m.ClassName, position = getPos(m),
        })
    end
end

local function scanLakes()
    local inter = WS:FindFirstChild('Interactions')
    local lf = inter and inter:FindFirstChild('Lakes')
    if not lf then return end
    for _, m in ipairs(lf:GetChildren()) do
        table.insert(OUT.lakes, {
            name = m.Name, class = m.ClassName, position = getPos(m),
        })
    end
end

local function scanAbandonedEggs()
    local inter = WS:FindFirstChild('Interactions')
    -- Check both possible folder names
    for _, fname in ipairs({'AbandonedEggSpawns', 'AbandonedEggs'}) do
        local f = inter and inter:FindFirstChild(fname)
        if f then
            for _, m in ipairs(f:GetChildren()) do
                table.insert(OUT.abandoned_eggs, {
                    folder = fname, name = m.Name, class = m.ClassName, position = getPos(m),
                })
            end
        end
    end
end

local function scanTokens()
    local inter = WS:FindFirstChild('Interactions')
    local tf = inter and inter:FindFirstChild('TokenNodes')
    if not tf then return end
    for _, m in ipairs(tf:GetChildren()) do
        table.insert(OUT.token_nodes, {
            name = m.Name, class = m.ClassName, position = getPos(m),
        })
    end
end

-- ═════════════ JSON OUTPUT ════════════════════════════════════════
local function toJSON(v, indent)
    indent = indent or 0
    local pad1 = string.rep('  ', indent + 1)
    local t = type(v)
    if t == 'nil' then return 'null' end
    if t == 'boolean' or t == 'number' then return tostring(v) end
    if t == 'string' then
        return '"' .. v:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r') .. '"'
    end
    if t == 'table' then
        local isArr = true; local maxK = 0
        for k in pairs(v) do
            if type(k) ~= 'number' then isArr = false; break end
            if k > maxK then maxK = k end
        end
        if isArr and maxK > 0 then
            local p = {}
            for i = 1, maxK do p[i] = toJSON(v[i], indent + 1) end
            return '[\n' .. pad1 .. table.concat(p, ',\n' .. pad1) .. '\n' .. string.rep('  ', indent) .. ']'
        else
            local p = {}
            for k, val in pairs(v) do
                table.insert(p, '"' .. tostring(k) .. '": ' .. toJSON(val, indent + 1))
            end
            if #p == 0 then return '{}' end
            return '{\n' .. pad1 .. table.concat(p, ',\n' .. pad1) .. '\n' .. string.rep('  ', indent) .. '}'
        end
    end
    return '"<' .. t .. '>"'
end

local function saveDump()
    local json = toJSON(OUT)
    local path = ('HSHub_MapDump_%s_%d.json'):format(tostring(game.PlaceId), os.time())
    local saved = false
    pcall(function() if writefile then writefile(path, json); saved = true end end)
    pcall(function() if setclipboard then setclipboard(json) elseif toclipboard then toclipboard(json) end end)
    return saved, path
end

-- ═════════════ UI ════════════════════════════════════════════════
local gui = Instance.new('ScreenGui')
gui.Name = 'HSHub_MapDump_' .. tostring(math.random(100000, 999999))
gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true
gui.Parent = (gethui and gethui()) or PG
shared.__HSHub_MapDump_Running = gui

local frame = Instance.new('Frame', gui)
frame.Size = UDim2.new(0, 380, 0, 380)
frame.Position = UDim2.new(0, 20, 0.4, -190)
frame.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
frame.BorderSizePixel = 0
frame.Active = true; frame.Draggable = true
Instance.new('UICorner', frame).CornerRadius = UDim.new(0, 10)
local stroke = Instance.new('UIStroke', frame)
stroke.Color = Color3.fromRGB(140, 90, 220); stroke.Thickness = 1.5

local header = Instance.new('Frame', frame)
header.Size = UDim2.new(1, 0, 0, 48)
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
title.Size = UDim2.new(1, -60, 1, 0); title.Position = UDim2.new(0, 14, 0, 0)
title.Font = Enum.Font.GothamBold; title.TextSize = 15
title.TextColor3 = Color3.fromRGB(245, 245, 250)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = 'HS HUB · MapDump'

local closeBtn = Instance.new('TextButton', header)
closeBtn.BackgroundTransparency = 1
closeBtn.Size = UDim2.new(0, 40, 0, 40); closeBtn.Position = UDim2.new(1, -45, 0, 4)
closeBtn.Font = Enum.Font.GothamBold; closeBtn.TextSize = 22
closeBtn.TextColor3 = Color3.fromRGB(245, 245, 250); closeBtn.Text = '×'
closeBtn.MouseButton1Click:Connect(function()
    gui:Destroy(); shared.__HSHub_MapDump_Running = nil
end)

local stat = Instance.new('TextLabel', frame)
stat.BackgroundTransparency = 1
stat.Size = UDim2.new(1, -28, 0, 100); stat.Position = UDim2.new(0, 14, 0, 56)
stat.Font = Enum.Font.Gotham; stat.TextSize = 12
stat.TextColor3 = Color3.fromRGB(200, 220, 255)
stat.TextXAlignment = Enum.TextXAlignment.Left
stat.TextYAlignment = Enum.TextYAlignment.Top
stat.TextWrapped = true
stat.Text = 'Click "Scan Map" to dump workspace.Interactions full tree.\n\nNo LUNAR load needed — pure static scan.\nSaves: workspace/HSHub_MapDump_<placeId>_<ts>.json'

local function btn(label, color, x, y, w)
    local b = Instance.new('TextButton', frame)
    b.Size = UDim2.new(0, w or 160, 0, 36); b.Position = UDim2.new(0, x, 0, y)
    b.BackgroundColor3 = color; b.BorderSizePixel = 0
    b.Font = Enum.Font.GothamBold; b.TextSize = 13
    b.TextColor3 = Color3.fromRGB(245, 245, 250); b.Text = label
    Instance.new('UICorner', b).CornerRadius = UDim.new(0, 6)
    return b
end

local scanBtn = btn('🔍 Scan Map',  Color3.fromRGB(60, 140, 100), 14, 168)
local saveBtn = btn('💾 Save JSON', Color3.fromRGB(80, 120, 180), 192, 168)

-- Log
local scroll = Instance.new('ScrollingFrame', frame)
scroll.Size = UDim2.new(1, -20, 0, 162); scroll.Position = UDim2.new(0, 10, 0, 210)
scroll.BackgroundColor3 = Color3.fromRGB(14, 14, 22); scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 4
scroll.ScrollBarImageColor3 = Color3.fromRGB(140, 90, 220)
Instance.new('UICorner', scroll).CornerRadius = UDim.new(0, 6)
local layout = Instance.new('UIListLayout', scroll)
layout.Padding = UDim.new(0, 2); layout.SortOrder = Enum.SortOrder.LayoutOrder
local pad = Instance.new('UIPadding', scroll); pad.PaddingTop = UDim.new(0, 4); pad.PaddingLeft = UDim.new(0, 6)

local function logRow(text, color)
    local lbl = Instance.new('TextLabel', scroll)
    lbl.BackgroundTransparency = 1
    lbl.Size = UDim2.new(1, -12, 0, 18)
    lbl.LayoutOrder = #scroll:GetChildren()
    lbl.Font = Enum.Font.Code; lbl.TextSize = 11
    lbl.TextColor3 = color or Color3.fromRGB(180, 200, 220)
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.TextTruncate = Enum.TextTruncate.AtEnd; lbl.Text = text
    scroll.CanvasSize = UDim2.new(0, 0, 0, #scroll:GetChildren() * 20)
    scroll.CanvasPosition = Vector2.new(0, scroll.CanvasSize.Y.Offset)
end

-- Handlers
scanBtn.MouseButton1Click:Connect(function()
    OUT.interactions = {}
    OUT.food_models = {}
    OUT.shrines = {}
    OUT.mud_spots = {}
    OUT.lakes = {}
    OUT.abandoned_eggs = {}
    OUT.token_nodes = {}
    OUT.time = os.date('%Y-%m-%d %H:%M:%S')

    for _, c in ipairs(scroll:GetChildren()) do
        if c:IsA('TextLabel') then c:Destroy() end
    end

    logRow('Scanning Interactions tree...', Color3.fromRGB(170, 230, 180))
    scanInteractions()
    logRow(('  ✓ %d Interaction folders'):format(#OUT.interactions), Color3.fromRGB(180, 220, 255))

    scanFood()
    logRow(('  ✓ %d food models'):format(#OUT.food_models), Color3.fromRGB(180, 220, 255))
    local carcassCount = 0
    for _, f in ipairs(OUT.food_models) do if f.is_carcass then carcassCount = carcassCount + 1 end end
    logRow(('    (incl. %d carcass)'):format(carcassCount), Color3.fromRGB(180, 220, 255))

    scanShrines()
    logRow(('  ✓ %d shrines'):format(#OUT.shrines), Color3.fromRGB(180, 220, 255))
    for _, s in ipairs(OUT.shrines) do
        logRow('    • ' .. s.name .. (s.position and ' @ ' .. s.position or ''), Color3.fromRGB(160, 200, 220))
    end

    scanMud()
    logRow(('  ✓ %d mud spots'):format(#OUT.mud_spots), Color3.fromRGB(180, 220, 255))

    scanLakes()
    logRow(('  ✓ %d lakes'):format(#OUT.lakes), Color3.fromRGB(180, 220, 255))

    scanAbandonedEggs()
    logRow(('  ✓ %d abandoned eggs'):format(#OUT.abandoned_eggs), Color3.fromRGB(180, 220, 255))

    scanTokens()
    logRow(('  ✓ %d token nodes'):format(#OUT.token_nodes), Color3.fromRGB(180, 220, 255))

    stat.Text = ('Scan done. %d Interaction folders / %d food / %d shrines / %d mud / %d lakes / %d eggs / %d tokens.\n\nClick Save JSON to dump file.'):format(
        #OUT.interactions, #OUT.food_models, #OUT.shrines,
        #OUT.mud_spots, #OUT.lakes, #OUT.abandoned_eggs, #OUT.token_nodes)
end)

saveBtn.MouseButton1Click:Connect(function()
    if #OUT.interactions == 0 then
        logRow('Scan first.', Color3.fromRGB(255, 200, 120))
        return
    end
    local saved, path = saveDump()
    logRow(saved and ('Saved: workspace/' .. path) or 'Save FAILED',
        Color3.fromRGB(170, 230, 180))
    logRow('Clipboard also has JSON. Send to Claude.', Color3.fromRGB(180, 220, 255))
end)
