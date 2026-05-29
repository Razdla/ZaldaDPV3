--[[
═══════════════════════════════════════════════════════════════════════
                    HS HUB · RemoteHook
            Targeted FireServer/InvokeServer hook via hookfunction
                    discord.gg/5rpP6faZSJ

    WHY THIS WORKS (vs Inspector/MapScan __namecall approach):
        Previous tools hooked __namecall metatable. LUNAR caches remote
        refs at load time (local fire = remote.FireServer) and bypasses
        the metatable when calling. So __namecall hook misses cached
        calls.

        This tool uses hookfunction() to patch the FireServer/InvokeServer
        FUNCTION itself, before LUNAR loads. Even cached refs end up
        calling the patched version.

    WORKFLOW:
        1. Paste THIS first (before LUNAR)
        2. UI shows hooks installed on 17 high-value LUNAR remotes
        3. Load LUNAR (catnex loader)
        4. Toggle artifact farm (Hellion)
        5. Wait 30-60s while LUNAR fires hooked remotes
        6. Stop + Save JSON
        7. Send file
═══════════════════════════════════════════════════════════════════════
]]

if shared.__HSHub_RemoteHook_Running then
    pcall(function() shared.__HSHub_RemoteHook_Running:Destroy() end)
end

local Players = game:GetService('Players')
local LP = Players.LocalPlayer
local PG = LP:WaitForChild('PlayerGui')
local RS = game:GetService('ReplicatedStorage')

-- ═════════════ TARGETS (LUNAR-relevant remotes) ════════════════════
local TARGETS = {
    -- artifact farm critical
    'WardenOffering', 'StoreActiveCreatureRemote', 'CreateSlotRemote',
    'SwapStoredCreaturesRemote', 'RestartSlotRemote',
    -- core feature remotes
    'DrinkRemote', 'Food', 'Mud', 'Lay', 'Nest',
    'LavaSelfDamage', 'Sheltered', 'StateAilment', 'HideScent',
    'PickupResource', 'DepositResource', 'ChunkResource',
    'ResourceDamageRemote', 'UpgradeNest',
    'GetSpawnedTokenRemote',
}

-- ═════════════ STATE ═════════════════════════════════════════════
local CAPTURES = {}
local HOOKS_OK = {}
local HOOKS_FAIL = {}
local CAPTURE_ACTIVE = false
local START_TIME = 0

-- ═════════════ ARG DUMP ══════════════════════════════════════════
local function dumpVal(v, depth)
    depth = depth or 0
    if depth > 3 then return '<...>' end
    local t = type(v)
    if t == 'string' then return (#v > 60) and ('str(' .. #v .. 'B)') or ('"' .. v:sub(1, 60) .. '"') end
    if t == 'number' or t == 'boolean' then return tostring(v) end
    if t == 'table' then
        local parts = {}
        local n = 0
        for k, val in pairs(v) do
            n = n + 1
            if n <= 8 then
                table.insert(parts, tostring(k) .. '=' .. dumpVal(val, depth + 1))
            end
        end
        return '{' .. table.concat(parts, ', ') .. (n > 8 and ', ...' or '') .. '}'
    end
    if t == 'userdata' then
        local ok, name = pcall(function() return v:GetFullName() end)
        return ok and ('<' .. name .. '>') or '<userdata>'
    end
    return '<' .. t .. '>'
end

local function dumpArgs(args, n)
    local parts = {}
    for i = 1, n do parts[i] = dumpVal(args[i]) end
    return table.concat(parts, ', ')
end

-- ═════════════ INSTALL HOOKS (v2: hook-once, dispatch-by-self) ════
-- BUG FIX 2026-05-27: previous version hooked r.FireServer per-instance,
-- but that's the GLOBAL class method. Caused all hooks to chain on one
-- real call, logging it with N different remote names. v2 hooks the
-- class method ONCE and dispatches by self.Name lookup.
local rs_remotes = RS:FindFirstChild('Remotes')
local TARGET_SET = {}; for _, n in ipairs(TARGETS) do TARGET_SET[n] = true end

local function record(name, method, args, n, results)
    if not CAPTURE_ACTIVE then return end
    local entry = {
        t = tick() - START_TIME,
        remote = name,
        method = method,
        args = dumpArgs(args, n),
    }
    if results and results.n and results.n > 0 then
        entry.returned = dumpArgs(results, results.n)
    end
    table.insert(CAPTURES, entry)
end

if not hookfunction then
    for _, n in ipairs(TARGETS) do HOOKS_FAIL[n] = 'no hookfunction' end
else
    -- Find a sample RemoteEvent + RemoteFunction to get the class methods
    local sampleEvent, sampleFn
    if rs_remotes then
        for _, c in ipairs(rs_remotes:GetChildren()) do
            if c:IsA('RemoteEvent') and not sampleEvent then sampleEvent = c end
            if c:IsA('RemoteFunction') and not sampleFn then sampleFn = c end
            if sampleEvent and sampleFn then break end
        end
    end

    -- Hook FireServer once
    if sampleEvent then
        local origFire
        local ok, err = pcall(function()
            origFire = hookfunction(sampleEvent.FireServer, function(self, ...)
                if CAPTURE_ACTIVE and TARGET_SET[self.Name] then
                    local args = table.pack(...)
                    record(self.Name, 'FireServer', args, args.n)
                end
                return origFire(self, ...)
            end)
        end)
        if ok then
            for _, n in ipairs(TARGETS) do
                local r = rs_remotes and rs_remotes:FindFirstChild(n)
                if r and r:IsA('RemoteEvent') then HOOKS_OK[n] = true end
            end
        else
            for _, n in ipairs(TARGETS) do
                local r = rs_remotes and rs_remotes:FindFirstChild(n)
                if r and r:IsA('RemoteEvent') then HOOKS_FAIL[n] = tostring(err):sub(1, 80) end
            end
        end
    end

    -- Hook InvokeServer once
    if sampleFn then
        local origInvoke
        local ok, err = pcall(function()
            origInvoke = hookfunction(sampleFn.InvokeServer, function(self, ...)
                if CAPTURE_ACTIVE and TARGET_SET[self.Name] then
                    local args = table.pack(...)
                    local results = table.pack(origInvoke(self, ...))
                    record(self.Name, 'InvokeServer', args, args.n, results)
                    return table.unpack(results, 1, results.n)
                end
                return origInvoke(self, ...)
            end)
        end)
        if ok then
            for _, n in ipairs(TARGETS) do
                local r = rs_remotes and rs_remotes:FindFirstChild(n)
                if r and r:IsA('RemoteFunction') then HOOKS_OK[n] = true end
            end
        else
            for _, n in ipairs(TARGETS) do
                local r = rs_remotes and rs_remotes:FindFirstChild(n)
                if r and r:IsA('RemoteFunction') then HOOKS_FAIL[n] = tostring(err):sub(1, 80) end
            end
        end
    end

    -- Mark missing remotes
    for _, n in ipairs(TARGETS) do
        if not HOOKS_OK[n] and not HOOKS_FAIL[n] then
            HOOKS_FAIL[n] = 'remote not found in RS.Remotes'
        end
    end
end

-- ═════════════ JSON OUTPUT ═══════════════════════════════════════
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

local function saveJSON()
    local report = {
        time = os.date('%Y-%m-%d %H:%M:%S'),
        place_id = game.PlaceId,
        hooks_ok = (function() local r = {}; for k in pairs(HOOKS_OK) do table.insert(r, k) end; return r end)(),
        hooks_fail = HOOKS_FAIL,
        captures = CAPTURES,
        capture_count = #CAPTURES,
    }
    local json = toJSON(report)
    local path = ('HSHub_RemoteHook_%s_%d.json'):format(tostring(game.PlaceId), os.time())
    local saved = false
    pcall(function() if writefile then writefile(path, json); saved = true end end)
    pcall(function() if setclipboard then setclipboard(json) elseif toclipboard then toclipboard(json) end end)
    return saved, path
end

-- ═════════════ UI ════════════════════════════════════════════════
local gui = Instance.new('ScreenGui')
gui.Name = 'HSHub_RemoteHook_' .. tostring(math.random(100000, 999999))
gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true
gui.Parent = (gethui and gethui()) or PG
shared.__HSHub_RemoteHook_Running = gui

local frame = Instance.new('Frame', gui)
frame.Size = UDim2.new(0, 400, 0, 420)
frame.Position = UDim2.new(0, 20, 0.4, -210)
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
title.Text = 'HS HUB · RemoteHook'

local closeBtn = Instance.new('TextButton', header)
closeBtn.BackgroundTransparency = 1
closeBtn.Size = UDim2.new(0, 40, 0, 40); closeBtn.Position = UDim2.new(1, -45, 0, 4)
closeBtn.Font = Enum.Font.GothamBold; closeBtn.TextSize = 22
closeBtn.TextColor3 = Color3.fromRGB(245, 245, 250); closeBtn.Text = '×'
closeBtn.MouseButton1Click:Connect(function()
    gui:Destroy(); shared.__HSHub_RemoteHook_Running = nil
end)

local okCount = 0; for _ in pairs(HOOKS_OK) do okCount = okCount + 1 end
local failCount = 0; for _ in pairs(HOOKS_FAIL) do failCount = failCount + 1 end

local stat = Instance.new('TextLabel', frame)
stat.BackgroundTransparency = 1
stat.Size = UDim2.new(1, -28, 0, 40); stat.Position = UDim2.new(0, 14, 0, 54)
stat.Font = Enum.Font.Gotham; stat.TextSize = 12
stat.TextColor3 = (failCount == 0) and Color3.fromRGB(170, 230, 180) or Color3.fromRGB(255, 200, 120)
stat.TextXAlignment = Enum.TextXAlignment.Left
stat.TextYAlignment = Enum.TextYAlignment.Top
stat.TextWrapped = true
stat.Text = ('Hooks installed: %d / %d  (%s)\n%s'):format(
    okCount, #TARGETS,
    (okCount == #TARGETS) and 'all OK' or 'partial',
    (failCount > 0 and HOOKS_FAIL[next(HOOKS_FAIL)] or 'ready'))

-- Buttons
local function btn(label, color, x, y)
    local b = Instance.new('TextButton', frame)
    b.Size = UDim2.new(0, 120, 0, 30); b.Position = UDim2.new(0, x, 0, y)
    b.BackgroundColor3 = color; b.BorderSizePixel = 0
    b.Font = Enum.Font.GothamBold; b.TextSize = 12
    b.TextColor3 = Color3.fromRGB(245, 245, 250); b.Text = label
    Instance.new('UICorner', b).CornerRadius = UDim.new(0, 6)
    return b
end

local startBtn = btn('▶ Start Record', Color3.fromRGB(60, 140, 100), 14, 102)
local stopBtn  = btn('■ Stop',         Color3.fromRGB(160, 80, 80),  138, 102)
local saveBtn  = btn('💾 Save JSON',   Color3.fromRGB(80, 120, 180), 262, 102)

-- Log
local scroll = Instance.new('ScrollingFrame', frame)
scroll.Size = UDim2.new(1, -20, 0, 244); scroll.Position = UDim2.new(0, 10, 0, 142)
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
    lbl.Font = Enum.Font.Code; lbl.TextSize = 10
    lbl.TextColor3 = color or Color3.fromRGB(180, 200, 220)
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.TextTruncate = Enum.TextTruncate.AtEnd; lbl.Text = text
    scroll.CanvasSize = UDim2.new(0, 0, 0, #scroll:GetChildren() * 20)
    scroll.CanvasPosition = Vector2.new(0, scroll.CanvasSize.Y.Offset)
end

logRow('=== Hook results ===', Color3.fromRGB(220, 200, 255))
for _, name in ipairs(TARGETS) do
    if HOOKS_OK[name] then
        logRow('  ✓ ' .. name, Color3.fromRGB(170, 230, 180))
    else
        logRow('  ✗ ' .. name .. ' : ' .. tostring(HOOKS_FAIL[name] or '?'),
            Color3.fromRGB(255, 150, 150))
    end
end

if not hookfunction then
    logRow('hookfunction NOT AVAILABLE — executor incompatible',
        Color3.fromRGB(255, 130, 130))
end

-- Live capture forwarder
local lastShown = 0
task.spawn(function()
    while gui.Parent do
        task.wait(0.3)
        while lastShown < #CAPTURES do
            lastShown = lastShown + 1
            local e = CAPTURES[lastShown]
            logRow(('[%6.2fs] %s.%s(%s)'):format(e.t, e.remote, e.method, e.args:sub(1, 80)),
                e.method:find('Invoke') and Color3.fromRGB(230, 200, 130) or Color3.fromRGB(170, 200, 240))
        end
    end
end)

-- Handlers
startBtn.MouseButton1Click:Connect(function()
    CAPTURE_ACTIVE = true
    START_TIME = tick()
    CAPTURES = {}
    lastShown = 0
    for _, c in ipairs(scroll:GetChildren()) do
        if c:IsA('TextLabel') then c:Destroy() end
    end
    logRow('Recording STARTED. Load LUNAR + toggle feature now.', Color3.fromRGB(170, 230, 180))
end)

stopBtn.MouseButton1Click:Connect(function()
    if not CAPTURE_ACTIVE then return end
    CAPTURE_ACTIVE = false
    logRow(('Recording STOPPED. Captured: %d calls'):format(#CAPTURES),
        Color3.fromRGB(230, 180, 130))
end)

saveBtn.MouseButton1Click:Connect(function()
    local saved, path = saveJSON()
    logRow(saved and ('Saved: workspace/' .. path) or 'Save FAILED (no writefile)',
        Color3.fromRGB(170, 230, 180))
    logRow('JSON also in clipboard. Send to Claude AI.', Color3.fromRGB(180, 220, 255))
end)
