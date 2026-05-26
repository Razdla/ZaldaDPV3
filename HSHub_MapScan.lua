--[[
═══════════════════════════════════════════════════════════════════════
                    HS HUB · MapScan
            Runtime variable + module mapper (artifact-farm focused)
                    discord.gg/5rpP6faZSJ

    Purpose:
        Map mangled variable names (J/w/z/F/o/B/q in chunk3) and module
        APIs to actual game objects/functions. Output JSON for Claude AI
        to use as ground truth for HS Hub module patches.

    What it captures:
        1. Deep module API dump (require + recursive table walk):
             ArtifactUtils, WardenShrine, PlayerWrapper, HUDGui,
             Nest, NestingService, plus any user-added
        2. Live RemoteEvent/RemoteFunction calls (FireServer/InvokeServer)
        3. Workspace path resolution (shrines, food, mud, lakes, etc.)
        4. Module-method invocations (which functions of which module
           the working hub calls during user-triggered features)

    Workflow:
        1. Paste this MapScan in executor FIRST
        2. UI auto-scans static structure + modules
        3. Click "Start" with label like "Hellion artifact toggle 60s"
        4. Load working hub (e.g. catnex loader)
        5. Toggle the feature whose binding you need to map
        6. Wait 30-60s
        7. Click "Stop" then "Save JSON"
        8. Send file to Claude AI for analysis
═══════════════════════════════════════════════════════════════════════
]]

if shared.__HSHub_MapScan_Running then
    pcall(function() shared.__HSHub_MapScan_Running:Destroy() end)
end

local Players = game:GetService('Players')
local LP      = Players.LocalPlayer
local PG      = LP:WaitForChild('PlayerGui')
local RS      = game:GetService('ReplicatedStorage')
local WS      = game:GetService('Workspace')

-- ═════════════ CONFIG ════════════════════════════════════════════
local PRIORITY_MODULES = {
    'HUDGui',                  -- LUNAR's UI module source
    'ArtifactUtils',           -- artifact deposit logic
    'WardenShrine',            -- shrine class
    'PlayerWrapper',           -- player state accessor
    'Nest',                    -- nest logic
    'NestingService',          -- nesting backend
    'CharacterWrapper',        -- character state
    'AilmentsService',         -- ailments (Cower, Aggression)
    'StatsService',            -- stat reads
    'TokenService',            -- gacha tokens
    'GachaService',
    'StorageUtils',            -- storage upgrade
    'CombatService',
    'MissionsService',
    'ResourceService',
}

local NOISE = {
    'EventExportClientMetrics', 'StaminaAnalytics',
    'SHImpressionsAnalytics', 'EventRsvpAnalytics',
    'SendHomePurchaseAnalytics', 'GameAnalytics',
}
local function isNoise(path)
    for _, p in ipairs(NOISE) do if path:find(p, 1, true) then return true end end
    return false
end

-- ═════════════ STATE ═════════════════════════════════════════════
local OUT = {
    place_id = game.PlaceId,
    game_name = 'unknown',
    captured_at = os.date('%Y-%m-%d %H:%M:%S'),
    capture_label = 'unlabeled',
    static = { remotes_RS = {}, remotes_LP = {}, interactions = {}, shrines = {} },
    modules = {},
    runtime = { events = {}, gui_events = {}, kick_events = {} },
}

local CAPTURE_ACTIVE = false
local CAPTURE_START = 0

-- ═════════════ STATIC SCAN ═══════════════════════════════════════
local function scanStatic()
    pcall(function()
        local info = game:GetService('MarketplaceService'):GetProductInfo(game.PlaceId)
        if info and info.Name then OUT.game_name = info.Name end
    end)

    -- RS.Remotes
    local rsR = RS:FindFirstChild('Remotes')
    if rsR then
        for _, c in ipairs(rsR:GetChildren()) do
            table.insert(OUT.static.remotes_RS, { name = c.Name, class = c.ClassName })
        end
    end

    -- LP.Remotes
    local lpR = LP:FindFirstChild('Remotes')
    if lpR then
        for _, c in ipairs(lpR:GetChildren()) do
            table.insert(OUT.static.remotes_LP, { name = c.Name, class = c.ClassName })
        end
    end

    -- Workspace.Interactions
    local inter = WS:FindFirstChild('Interactions')
    if inter then
        for _, c in ipairs(inter:GetChildren()) do
            local count = 0
            pcall(function() count = #c:GetChildren() end)
            table.insert(OUT.static.interactions, {
                name = c.Name, class = c.ClassName, children = count,
            })
        end
        -- Special: warden shrines
        local shrines = inter:FindFirstChild('Warden Shrines')
        if shrines then
            for _, s in ipairs(shrines:GetChildren()) do
                local pos = 'unknown'
                pcall(function()
                    local part = s:IsA('Model') and (s.PrimaryPart or s:FindFirstChildWhichIsA('BasePart')) or s
                    if part and part:IsA('BasePart') then
                        local p = part.Position
                        pos = ('%.1f,%.1f,%.1f'):format(p.X, p.Y, p.Z)
                    end
                end)
                table.insert(OUT.static.shrines, {
                    name = s.Name, class = s.ClassName, position = pos,
                })
            end
        end
    end
end

-- ═════════════ MODULE DEEP DUMP ══════════════════════════════════
local function valueDesc(v, depth, max_depth)
    depth = depth or 0
    if depth > (max_depth or 3) then return '<...>' end
    local t = type(v)
    if t == 'function' then return 'function' end
    if t == 'string' then
        if #v > 80 then return ('string(len=%d)'):format(#v) end
        return ('%q'):format(v)
    end
    if t == 'number' or t == 'boolean' or t == 'nil' then return tostring(v) end
    if t == 'table' then
        local entries = {}
        local count = 0
        for k, val in pairs(v) do
            count = count + 1
            if count <= 20 then
                table.insert(entries, {
                    key = tostring(k),
                    type = type(val),
                    summary = (type(val) == 'function') and 'function'
                        or (type(val) == 'table') and ('table(n=' .. (function()
                            local n = 0; for _ in pairs(val) do n = n + 1 end; return n end)() .. ')')
                        or valueDesc(val, depth + 1, max_depth),
                })
            end
        end
        return { _table = true, total_keys = count, entries = entries }
    end
    if t == 'userdata' then
        local ok, name = pcall(function() return v.ClassName end)
        return ok and ('Instance<' .. tostring(name) .. '>') or 'userdata'
    end
    return '<' .. t .. '>'
end

local function dumpModule(mod)
    if not mod or not mod:IsA('ModuleScript') then return nil end
    local ok, result = pcall(function() return require(mod) end)
    if not ok then return { error = tostring(result):sub(1, 300) } end
    return {
        return_type = type(result),
        structure = valueDesc(result, 0, 3),
    }
end

local function scanModules()
    local rf = RS:FindFirstChild('_replicationFolder')
    if not rf then return end
    for _, name in ipairs(PRIORITY_MODULES) do
        local mod = rf:FindFirstChild(name)
        if mod then
            OUT.modules[name] = dumpModule(mod)
        else
            OUT.modules[name] = { error = 'NOT FOUND in _replicationFolder' }
        end
    end
end

-- ═════════════ RUNTIME HOOK ══════════════════════════════════════
local function dumpArgs(args, n)
    local out = {}
    for i = 1, n do
        local v = args[i]
        local t = type(v)
        if t == 'string' then
            out[i] = (#v > 60) and ('string(' .. #v .. 'B)') or ('"' .. v:sub(1, 60) .. '"')
        elseif t == 'number' or t == 'boolean' then
            out[i] = tostring(v)
        elseif t == 'table' then
            local n2 = 0; for _ in pairs(v) do n2 = n2 + 1 end
            out[i] = 'table(n=' .. n2 .. ')'
        elseif t == 'userdata' then
            local ok, nm = pcall(function() return v:GetFullName() end)
            out[i] = ok and ('<' .. nm .. '>') or 'userdata'
        else
            out[i] = '<' .. t .. '>'
        end
    end
    return table.concat(out, ', ')
end

local hookInstalled = false
local function installHook()
    if hookInstalled then return true end
    local ok, mt = pcall(getrawmetatable, game)
    if not ok or not mt then return false end
    pcall(setreadonly, mt, false)
    local old = mt.__namecall
    local hooked = function(self, ...)
        local m = getnamecallmethod and getnamecallmethod() or '?'
        if CAPTURE_ACTIVE and (m == 'FireServer' or m == 'InvokeServer') then
            local path = 'unknown'
            pcall(function() path = self:GetFullName() end)
            if not isNoise(path) then
                local args = table.pack(...)
                table.insert(OUT.runtime.events, {
                    t = tick() - CAPTURE_START,
                    kind = m,
                    path = path,
                    args = dumpArgs(args, args.n),
                })
            end
        end
        return old(self, ...)
    end
    if newcclosure then hooked = newcclosure(hooked) end
    mt.__namecall = hooked
    pcall(setreadonly, mt, true)
    hookInstalled = true
    return true
end

-- ═════════════ KICK / GUI WATCH ══════════════════════════════════
Players.PlayerRemoving:Connect(function(p)
    if p == LP and CAPTURE_ACTIVE then
        table.insert(OUT.runtime.kick_events, {
            t = tick() - CAPTURE_START,
            reason = 'PlayerRemoving fired for LocalPlayer',
        })
    end
end)

PG.ChildAdded:Connect(function(c)
    if CAPTURE_ACTIVE then
        local n = c.Name:lower()
        if n:find('ban') or n:find('warn') or n:find('detect') or n:find('exploit') then
            table.insert(OUT.runtime.gui_events, {
                t = tick() - CAPTURE_START,
                gui = c.Name,
                class = c.ClassName,
            })
        end
    end
end)

-- ═════════════ JSON OUTPUT ═══════════════════════════════════════
local function toJSON(v, indent)
    indent = indent or 0
    local pad = string.rep('  ', indent)
    local pad1 = string.rep('  ', indent + 1)
    local t = type(v)
    if t == 'nil' then return 'null' end
    if t == 'boolean' or t == 'number' then return tostring(v) end
    if t == 'string' then
        return '"' .. v:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r'):gsub('\t', '\\t') .. '"'
    end
    if t == 'table' then
        -- Detect array
        local isArr = true; local maxK = 0
        for k in pairs(v) do
            if type(k) ~= 'number' then isArr = false; break end
            if k > maxK then maxK = k end
        end
        if isArr and maxK > 0 then
            local parts = {}
            for i = 1, maxK do parts[i] = toJSON(v[i], indent + 1) end
            return '[\n' .. pad1 .. table.concat(parts, ',\n' .. pad1) .. '\n' .. pad .. ']'
        else
            local parts = {}
            for k, val in pairs(v) do
                table.insert(parts, ('"%s": %s'):format(tostring(k), toJSON(val, indent + 1)))
            end
            if #parts == 0 then return '{}' end
            return '{\n' .. pad1 .. table.concat(parts, ',\n' .. pad1) .. '\n' .. pad .. '}'
        end
    end
    return '"<' .. t .. '>"'
end

local function saveReport()
    local json = toJSON(OUT)
    local path = ('HSHub_MapScan_%s_%d.json'):format(tostring(game.PlaceId), os.time())
    local saved = false
    pcall(function() if writefile then writefile(path, json); saved = true end end)
    pcall(function()
        if setclipboard then setclipboard(json)
        elseif toclipboard then toclipboard(json) end
    end)
    return saved, path
end

-- ═════════════ INITIAL SCAN ══════════════════════════════════════
scanStatic()
scanModules()

-- ═════════════ UI ════════════════════════════════════════════════
local gui = Instance.new('ScreenGui')
gui.Name = 'HSHub_MapScan_' .. tostring(math.random(100000, 999999))
gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true
gui.Parent = (gethui and gethui()) or PG
shared.__HSHub_MapScan_Running = gui

local frame = Instance.new('Frame', gui)
frame.Size = UDim2.new(0, 420, 0, 440)
frame.Position = UDim2.new(0, 20, 0.4, -220)
frame.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
frame.BorderSizePixel = 0
frame.Active = true; frame.Draggable = true
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
title.Size = UDim2.new(1, -60, 1, 0); title.Position = UDim2.new(0, 14, 0, 0)
title.Font = Enum.Font.GothamBold; title.TextSize = 15
title.TextColor3 = Color3.fromRGB(245, 245, 250)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = 'HS HUB · MapScan'

local closeBtn = Instance.new('TextButton', header)
closeBtn.BackgroundTransparency = 1
closeBtn.Size = UDim2.new(0, 40, 0, 40); closeBtn.Position = UDim2.new(1, -45, 0, 5)
closeBtn.Font = Enum.Font.GothamBold; closeBtn.TextSize = 22
closeBtn.TextColor3 = Color3.fromRGB(245, 245, 250); closeBtn.Text = '×'
closeBtn.MouseButton1Click:Connect(function()
    gui:Destroy(); shared.__HSHub_MapScan_Running = nil
end)

-- Stats
local moduleCount = 0; for _ in pairs(OUT.modules) do moduleCount = moduleCount + 1 end
local moduleOK = 0
for _, m in pairs(OUT.modules) do if not m.error then moduleOK = moduleOK + 1 end end

local stat = Instance.new('TextLabel', frame)
stat.BackgroundTransparency = 1
stat.Size = UDim2.new(1, -28, 0, 60); stat.Position = UDim2.new(0, 14, 0, 56)
stat.Font = Enum.Font.Gotham; stat.TextSize = 12
stat.TextColor3 = Color3.fromRGB(200, 220, 255)
stat.TextXAlignment = Enum.TextXAlignment.Left
stat.TextYAlignment = Enum.TextYAlignment.Top
stat.TextWrapped = true
stat.Text = ('Game: %s\nRS.Remotes: %d · LP.Remotes: %d · Shrines: %d\nModules dumped: %d/%d (%s)'):format(
    OUT.game_name,
    #OUT.static.remotes_RS, #OUT.static.remotes_LP, #OUT.static.shrines,
    moduleOK, moduleCount,
    moduleOK == moduleCount and 'all OK' or 'some errored — check JSON')

-- Label
local lblBox = Instance.new('TextBox', frame)
lblBox.Size = UDim2.new(1, -28, 0, 30); lblBox.Position = UDim2.new(0, 14, 0, 124)
lblBox.BackgroundColor3 = Color3.fromRGB(28, 28, 36); lblBox.BorderSizePixel = 0
lblBox.Font = Enum.Font.Gotham; lblBox.TextSize = 12
lblBox.TextColor3 = Color3.fromRGB(220, 220, 240)
lblBox.PlaceholderText = 'Capture label (e.g. "Hellion artifact ON 60s")'
lblBox.PlaceholderColor3 = Color3.fromRGB(120, 120, 150)
lblBox.Text = ''; lblBox.ClearTextOnFocus = false
Instance.new('UICorner', lblBox).CornerRadius = UDim.new(0, 6)

-- Buttons
local function btn(label, color, x, y)
    local b = Instance.new('TextButton', frame)
    b.Size = UDim2.new(0, 125, 0, 32); b.Position = UDim2.new(0, x, 0, y)
    b.BackgroundColor3 = color; b.BorderSizePixel = 0
    b.Font = Enum.Font.GothamBold; b.TextSize = 12
    b.TextColor3 = Color3.fromRGB(245, 245, 250); b.Text = label
    Instance.new('UICorner', b).CornerRadius = UDim.new(0, 6)
    return b
end

local startBtn = btn('▶  Start',     Color3.fromRGB(60, 140, 100), 14,  164)
local stopBtn  = btn('■  Stop',      Color3.fromRGB(160, 80, 80),  144, 164)
local saveBtn  = btn('💾 Save JSON', Color3.fromRGB(80, 120, 180), 274, 164)

-- Log
local scroll = Instance.new('ScrollingFrame', frame)
scroll.Size = UDim2.new(1, -20, 0, 220); scroll.Position = UDim2.new(0, 10, 0, 206)
scroll.BackgroundColor3 = Color3.fromRGB(14, 14, 22); scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 4
scroll.ScrollBarImageColor3 = Color3.fromRGB(140, 90, 220)
Instance.new('UICorner', scroll).CornerRadius = UDim.new(0, 6)

local layout = Instance.new('UIListLayout', scroll)
layout.Padding = UDim.new(0, 2); layout.SortOrder = Enum.SortOrder.LayoutOrder
local pad = Instance.new('UIPadding', scroll)
pad.PaddingTop = UDim.new(0, 4); pad.PaddingLeft = UDim.new(0, 6)

local function logRow(text, color)
    local lbl = Instance.new('TextLabel', scroll)
    lbl.BackgroundTransparency = 1
    lbl.Size = UDim2.new(1, -12, 0, 18)
    lbl.LayoutOrder = #scroll:GetChildren()
    lbl.Font = Enum.Font.Code; lbl.TextSize = 10
    lbl.TextColor3 = color or Color3.fromRGB(180, 200, 220)
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.TextTruncate = Enum.TextTruncate.AtEnd; lbl.Text = text
    scroll.CanvasSize = UDim2.new(0, 0, 0, #scroll:GetChildren() * 20)
    scroll.CanvasPosition = Vector2.new(0, scroll.CanvasSize.Y.Offset)
end

logRow('Static + module scan complete.', Color3.fromRGB(170, 230, 180))
for name, info in pairs(OUT.modules) do
    if info.error then
        logRow(('  ✗ %s: %s'):format(name, info.error:sub(1, 60)), Color3.fromRGB(255, 150, 150))
    else
        logRow(('  ✓ %s: %s'):format(name, info.return_type), Color3.fromRGB(180, 220, 255))
    end
end

local lastShown = 0
task.spawn(function()
    while gui.Parent do
        task.wait(0.3)
        while lastShown < #OUT.runtime.events do
            lastShown = lastShown + 1
            local e = OUT.runtime.events[lastShown]
            local short = e.path:gsub('^game%.', ''):sub(1, 55)
            logRow(('[%6.2fs] %s %s'):format(e.t, e.kind:sub(1,4), short),
                e.kind:find('Invoke') and Color3.fromRGB(230, 200, 130) or Color3.fromRGB(170, 200, 240))
        end
    end
end)

-- Footer
local footer = Instance.new('TextLabel', frame)
footer.BackgroundTransparency = 1
footer.Size = UDim2.new(1, -28, 0, 16); footer.Position = UDim2.new(0, 14, 1, -22)
footer.Font = Enum.Font.Gotham; footer.TextSize = 10
footer.TextColor3 = Color3.fromRGB(160, 150, 200)
footer.TextXAlignment = Enum.TextXAlignment.Left
footer.Text = 'Output: workspace/HSHub_MapScan_<placeId>_<ts>.json + clipboard'

-- Handlers
startBtn.MouseButton1Click:Connect(function()
    local ok = installHook()
    if not ok then
        logRow('Hook FAILED', Color3.fromRGB(255, 130, 130)); return
    end
    CAPTURE_ACTIVE = true
    CAPTURE_START = tick()
    OUT.capture_label = lblBox.Text ~= '' and lblBox.Text or 'unlabeled'
    OUT.runtime.events = {}
    OUT.runtime.gui_events = {}
    OUT.runtime.kick_events = {}
    lastShown = 0
    for _, c in ipairs(scroll:GetChildren()) do
        if c:IsA('TextLabel') then c:Destroy() end
    end
    logRow(('Capture STARTED: "%s"'):format(OUT.capture_label), Color3.fromRGB(170, 230, 180))
    logRow('Now load the hub + toggle the feature to map.', Color3.fromRGB(220, 200, 130))
end)

stopBtn.MouseButton1Click:Connect(function()
    if not CAPTURE_ACTIVE then return end
    CAPTURE_ACTIVE = false
    local elapsed = tick() - CAPTURE_START
    logRow(('Capture STOPPED. %d events / %.1fs'):format(#OUT.runtime.events, elapsed),
        Color3.fromRGB(230, 180, 130))
end)

saveBtn.MouseButton1Click:Connect(function()
    OUT.captured_at = os.date('%Y-%m-%d %H:%M:%S')
    local saved, path = saveReport()
    logRow(saved and ('Saved: workspace/' .. path) or 'Save failed', Color3.fromRGB(170, 230, 180))
    logRow('JSON also in clipboard. Send to Claude AI.', Color3.fromRGB(180, 220, 255))
end)
