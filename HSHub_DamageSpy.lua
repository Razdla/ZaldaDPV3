--[[
═══════════════════════════════════════════════════════════════════════
                    HS HUB · DamageSpy
       Universal remote capture + health-drop damage correlation
                    discord.gg/5rpP6faZSJ

    PURPOSE (vs RemoteHook):
        RemoteHook only logs 21 PRE-CHOSEN remotes (TARGET_SET filter), so
        unknown damage remotes (drowning/meteor/moisture/tornado) get
        silently dropped. This tool captures EVERY FireServer/InvokeServer
        with NO filter, AND watches creature health.

        When health 'h' DROPS, it auto-records a "damage event" carrying:
          - hBefore / hAfter / drop amount
          - the last ~25 remote calls that fired just before (the cause)
          - a snapshot of the Ailments folder at that instant
        => directly reveals what causes each environmental damage.

    WORKFLOW:
        1. Spawn creature, paste this script
        2. Click ▶ Start
        3. Walk into LAVA, stay ~8s        (creates damage events)
        4. Walk out, then DROWN in water   (creates damage events)
        5. (optional) click ⚑ Mark right when something happens
        6. Click ■ Stop  →  💾 Save JSON
        7. Send the JSON

    READ THE OUTPUT:
        - summary       : every remote that fired + how many times
        - damage_events : each h-drop with the remotes that preceded it
        If a damage_event has NO remotes in `recent` and NO ailment change,
        that damage is purely server-side (not blockable client-side).
═══════════════════════════════════════════════════════════════════════
]]

if shared.__HSHub_DamageSpy then
    pcall(function() shared.__HSHub_DamageSpy:Destroy() end)
end

local Players   = game:GetService('Players')
local Workspace = game:GetService('Workspace')
local RS        = game:GetService('ReplicatedStorage')
local LP        = Players.LocalPlayer
local PG        = LP:WaitForChild('PlayerGui')

-- ═════════════ STATE ═════════════════════════════════════════════
local ACTIVE       = false
local START        = 0
local summary      = {}      -- name -> {count, firstT, lastT, method, sample}
local timeline     = {}      -- chronological {t, name, method, args}  (capped)
local ring         = {}      -- recent-call ring buffer
local RING_MAX     = 25
local damageEvents = {}      -- {t, hBefore, hAfter, drop, recent, ailments}
local markers      = {}      -- {t, label}
local MAX_TIMELINE = 2500
local hookStatus   = 'init'

local function now() return tick() - START end

-- ═════════════ CHARACTER / HEALTH ════════════════════════════════
local function getChar()
    local c = LP.Character
    if c and c:FindFirstChild('Data') then return c end
    local chars = Workspace:FindFirstChild('Characters')
    if chars then
        local byName = chars:FindFirstChild(LP.Name)
        if byName then return byName end
    end
    return c
end

-- ═════════════ ARG DUMP ══════════════════════════════════════════
local function dumpVal(v, depth)
    depth = depth or 0
    if depth > 2 then return '<...>' end
    local t = type(v)
    if t == 'string' then return (#v > 48) and ('str(' .. #v .. 'B)') or ('"' .. v:sub(1, 48) .. '"') end
    if t == 'number' or t == 'boolean' then return tostring(v) end
    if t == 'userdata' then
        local ok, nm = pcall(function() return v:GetFullName() end)
        return ok and ('<' .. nm .. '>') or '<userdata>'
    end
    if t == 'table' then return '{table}' end
    return '<' .. t .. '>'
end

local function dumpArgs(a, n)
    local p = {}
    local lim = math.min(n, 6)
    for i = 1, lim do p[i] = dumpVal(a[i]) end
    return table.concat(p, ', ')
end

-- ═════════════ RECORD ════════════════════════════════════════════
local ringIdx = 0
local function recordCall(name, method, argstr)
    local s = summary[name]
    if not s then
        s = { count = 0, firstT = now(), method = method, sample = argstr }
        summary[name] = s
    end
    s.count  = s.count + 1
    s.lastT  = now()
    -- ring buffer (overwrites oldest)
    ringIdx = (ringIdx % RING_MAX) + 1
    ring[ringIdx] = { t = now(), name = name, method = method, args = argstr }
    -- capped timeline
    if #timeline < MAX_TIMELINE then
        timeline[#timeline + 1] = { t = now(), name = name, method = method, args = argstr }
    end
end

local function snapshotRecent()
    local out = {}
    for i = 1, RING_MAX do
        if ring[i] then out[#out + 1] = ring[i] end
    end
    table.sort(out, function(x, y) return x.t < y.t end)
    return out
end

local function snapshotAilments()
    local out = {}
    local c = getChar()
    if not c then return out end
    local ail = c:FindFirstChild('Ailments')
    if ail then
        pcall(function()
            for k, v in pairs(ail:GetAttributes()) do out[tostring(k)] = tostring(v) end
        end)
    end
    return out
end

-- ═════════════ UNIVERSAL HOOKS (no filter) ═══════════════════════
local function findSample(className)
    for _, d in ipairs(RS:GetDescendants()) do
        if d:IsA(className) then return d end
    end
    return nil
end

pcall(function()
    if not hookfunction then hookStatus = 'no hookfunction — executor incompatible'; return end
    local sampleEvent = findSample('RemoteEvent')
    local sampleFn    = findSample('RemoteFunction')
    local okE, okF = false, false

    if sampleEvent then
        local of
        local ok = pcall(function()
            of = hookfunction(sampleEvent.FireServer, function(self, ...)
                if ACTIVE then
                    local a = table.pack(...)
                    pcall(recordCall, self.Name, 'FireServer', dumpArgs(a, a.n))
                end
                return of(self, ...)
            end)
        end)
        okE = ok
    end

    if sampleFn then
        local oi
        local ok = pcall(function()
            oi = hookfunction(sampleFn.InvokeServer, function(self, ...)
                if ACTIVE then
                    local a = table.pack(...)
                    pcall(recordCall, self.Name, 'InvokeServer', dumpArgs(a, a.n))
                end
                return oi(self, ...)
            end)
        end)
        okF = ok
    end

    hookStatus = ('FireServer:%s  InvokeServer:%s'):format(
        okE and 'OK' or (sampleEvent and 'FAIL' or 'no-sample'),
        okF and 'OK' or (sampleFn and 'FAIL' or 'no-sample'))
end)

-- ═════════════ HEALTH + AILMENT WATCH ════════════════════════════
local watchedChar = nil
local lastH = nil

local function onHealthChanged(data)
    local h = tonumber(data:GetAttribute('h'))
    if not ACTIVE then lastH = h; return end
    if lastH and h and h < lastH then
        damageEvents[#damageEvents + 1] = {
            t        = now(),
            hBefore  = lastH,
            hAfter   = h,
            drop     = lastH - h,
            recent   = snapshotRecent(),
            ailments = snapshotAilments(),
        }
    end
    lastH = h
end

local function attachWatch()
    local c = getChar()
    if not c or watchedChar == c then return end
    local data = c:FindFirstChild('Data')
    if not data then return end
    watchedChar = c
    lastH = tonumber(data:GetAttribute('h'))
    pcall(function()
        data:GetAttributeChangedSignal('h'):Connect(function() onHealthChanged(data) end)
    end)
    -- ailment changes -> inject into timeline so damage events capture them
    local ail = c:FindFirstChild('Ailments')
    if ail then
        pcall(function()
            ail.AttributeChanged:Connect(function(key)
                if ACTIVE then
                    pcall(recordCall, 'AILMENT:' .. tostring(key), 'attr',
                        tostring(ail:GetAttribute(key)))
                end
            end)
        end)
    end
end

task.spawn(function()
    while true do
        task.wait(0.5)
        pcall(attachWatch)
    end
end)
LP.CharacterAdded:Connect(function()
    watchedChar = nil
    task.wait(1)
    pcall(attachWatch)
end)

-- ═════════════ JSON ══════════════════════════════════════════════
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
        time           = os.date('%Y-%m-%d %H:%M:%S'),
        place_id       = game.PlaceId,
        hook_status    = hookStatus,
        duration       = ACTIVE and now() or (timeline[#timeline] and timeline[#timeline].t or 0),
        remotes_seen   = (function() local n = 0; for _ in pairs(summary) do n = n + 1 end; return n end)(),
        damage_events  = damageEvents,
        markers        = markers,
        summary        = summary,
        timeline_count = #timeline,
        timeline       = timeline,
    }
    local json = toJSON(report)
    local path = ('HSHub_DamageSpy_%s_%d.json'):format(tostring(game.PlaceId), os.time())
    local saved = false
    pcall(function() if writefile then writefile(path, json); saved = true end end)
    pcall(function() if setclipboard then setclipboard(json) elseif toclipboard then toclipboard(json) end end)
    return saved, path
end

-- ═════════════ UI ════════════════════════════════════════════════
local gui = Instance.new('ScreenGui')
gui.Name = 'HSHub_DamageSpy_' .. tostring(math.random(100000, 999999))
gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true
gui.Parent = (gethui and gethui()) or PG
shared.__HSHub_DamageSpy = gui

local frame = Instance.new('Frame', gui)
frame.Size = UDim2.new(0, 420, 0, 430)
frame.Position = UDim2.new(0, 20, 0.4, -215)
frame.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
frame.BorderSizePixel = 0
frame.Active = true; frame.Draggable = true
Instance.new('UICorner', frame).CornerRadius = UDim.new(0, 10)
local stroke = Instance.new('UIStroke', frame)
stroke.Color = Color3.fromRGB(220, 90, 110); stroke.Thickness = 1.5

local header = Instance.new('Frame', frame)
header.Size = UDim2.new(1, 0, 0, 48)
header.BackgroundColor3 = Color3.fromRGB(220, 90, 110)
header.BorderSizePixel = 0
Instance.new('UICorner', header).CornerRadius = UDim.new(0, 10)
local hGrad = Instance.new('UIGradient', header)
hGrad.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(220, 90, 110)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 90, 220)),
})

local title = Instance.new('TextLabel', header)
title.BackgroundTransparency = 1
title.Size = UDim2.new(1, -60, 1, 0); title.Position = UDim2.new(0, 14, 0, 0)
title.Font = Enum.Font.GothamBold; title.TextSize = 15
title.TextColor3 = Color3.fromRGB(245, 245, 250)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = 'HS HUB · DamageSpy'

local closeBtn = Instance.new('TextButton', header)
closeBtn.BackgroundTransparency = 1
closeBtn.Size = UDim2.new(0, 40, 0, 40); closeBtn.Position = UDim2.new(1, -45, 0, 4)
closeBtn.Font = Enum.Font.GothamBold; closeBtn.TextSize = 22
closeBtn.TextColor3 = Color3.fromRGB(245, 245, 250); closeBtn.Text = '×'
closeBtn.MouseButton1Click:Connect(function()
    gui:Destroy(); shared.__HSHub_DamageSpy = nil
end)

local stat = Instance.new('TextLabel', frame)
stat.BackgroundTransparency = 1
stat.Size = UDim2.new(1, -28, 0, 38); stat.Position = UDim2.new(0, 14, 0, 54)
stat.Font = Enum.Font.Gotham; stat.TextSize = 12
stat.TextColor3 = Color3.fromRGB(200, 220, 255)
stat.TextXAlignment = Enum.TextXAlignment.Left
stat.TextYAlignment = Enum.TextYAlignment.Top
stat.TextWrapped = true
stat.Text = 'Hooks: ' .. hookStatus .. '\nClick Start, then go take damage (lava / drowning).'

local function btn(label, color, x, w)
    local b = Instance.new('TextButton', frame)
    b.Size = UDim2.new(0, w, 0, 30); b.Position = UDim2.new(0, x, 0, 100)
    b.BackgroundColor3 = color; b.BorderSizePixel = 0
    b.Font = Enum.Font.GothamBold; b.TextSize = 12
    b.TextColor3 = Color3.fromRGB(245, 245, 250); b.Text = label
    Instance.new('UICorner', b).CornerRadius = UDim.new(0, 6)
    return b
end

local startBtn = btn('▶ Start', Color3.fromRGB(60, 140, 100), 14, 92)
local stopBtn  = btn('■ Stop',  Color3.fromRGB(160, 80, 80), 112, 92)
local markBtn  = btn('⚑ Mark',  Color3.fromRGB(180, 140, 60), 210, 92)
local saveBtn  = btn('💾 Save',  Color3.fromRGB(80, 120, 180), 308, 92)

local scroll = Instance.new('ScrollingFrame', frame)
scroll.Size = UDim2.new(1, -20, 0, 250); scroll.Position = UDim2.new(0, 10, 0, 140)
scroll.BackgroundColor3 = Color3.fromRGB(14, 14, 22); scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 4
scroll.ScrollBarImageColor3 = Color3.fromRGB(220, 90, 110)
Instance.new('UICorner', scroll).CornerRadius = UDim.new(0, 6)
local layout = Instance.new('UIListLayout', scroll)
layout.Padding = UDim.new(0, 2); layout.SortOrder = Enum.SortOrder.LayoutOrder
local pad = Instance.new('UIPadding', scroll); pad.PaddingTop = UDim.new(0, 4); pad.PaddingLeft = UDim.new(0, 6)

local function logRow(text, color)
    local lbl = Instance.new('TextLabel', scroll)
    lbl.BackgroundTransparency = 1
    lbl.Size = UDim2.new(1, -12, 0, 16)
    lbl.LayoutOrder = #scroll:GetChildren()
    lbl.Font = Enum.Font.Code; lbl.TextSize = 10
    lbl.TextColor3 = color or Color3.fromRGB(180, 200, 220)
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.TextTruncate = Enum.TextTruncate.AtEnd; lbl.Text = text
    scroll.CanvasSize = UDim2.new(0, 0, 0, #scroll:GetChildren() * 18)
    scroll.CanvasPosition = Vector2.new(0, scroll.CanvasSize.Y.Offset)
end

logRow('Hooks: ' .. hookStatus, Color3.fromRGB(220, 200, 255))
if not hookfunction then
    logRow('hookfunction NOT AVAILABLE — cannot capture.', Color3.fromRGB(255, 130, 130))
end

-- live forwarder: show damage events as they happen
local lastDmgShown = 0
task.spawn(function()
    while gui.Parent do
        task.wait(0.3)
        while lastDmgShown < #damageEvents do
            lastDmgShown = lastDmgShown + 1
            local e = damageEvents[lastDmgShown]
            logRow(('[%6.2fs] ⚠ DMG -%.1f (h %.0f→%.0f)'):format(e.t, e.drop, e.hBefore, e.hAfter),
                Color3.fromRGB(255, 150, 150))
            -- show the 3 most recent remotes before this damage
            local r = e.recent
            for i = math.max(1, #r - 2), #r do
                if r[i] then
                    logRow(('        ← %s.%s(%s)'):format(r[i].name, r[i].method, r[i].args:sub(1, 40)),
                        Color3.fromRGB(170, 200, 240))
                end
            end
        end
    end
end)

startBtn.MouseButton1Click:Connect(function()
    ACTIVE = true
    START = tick()
    summary = {}; timeline = {}; ring = {}; ringIdx = 0
    damageEvents = {}; markers = {}; lastDmgShown = 0
    lastH = nil; watchedChar = nil
    pcall(attachWatch)
    for _, c in ipairs(scroll:GetChildren()) do
        if c:IsA('TextLabel') then c:Destroy() end
    end
    logRow('Recording STARTED. Go take damage now.', Color3.fromRGB(170, 230, 180))
end)

stopBtn.MouseButton1Click:Connect(function()
    if not ACTIVE then return end
    ACTIVE = false
    local nseen = 0; for _ in pairs(summary) do nseen = nseen + 1 end
    logRow(('STOPPED. remotes=%d  damage_events=%d'):format(nseen, #damageEvents),
        Color3.fromRGB(230, 180, 130))
end)

markBtn.MouseButton1Click:Connect(function()
    if not ACTIVE then return end
    markers[#markers + 1] = { t = now(), label = 'manual' }
    logRow(('[%6.2fs] ⚑ MARK'):format(now()), Color3.fromRGB(230, 210, 130))
end)

saveBtn.MouseButton1Click:Connect(function()
    local saved, path = saveJSON()
    logRow(saved and ('Saved: workspace/' .. path) or 'Save FAILED (no writefile)',
        Color3.fromRGB(170, 230, 180))
    logRow('JSON also in clipboard.', Color3.fromRGB(180, 220, 255))
end)
