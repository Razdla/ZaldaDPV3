--[[
═══════════════════════════════════════════════════════════════════════
                HS HUB · RegionScan
   Dump REAL region positions so Teleports tab + autofarm cross-region TP
   stop landing underground. LUNAR uses RS._replicationFolder.RegionUtils
   (.getRegionModel(name) -> Instance with a real CFrame). We mirror that.
                    discord.gg/5rpP6faZSJ

   USE: run ONCE, anywhere. Writes _upload_v2 / clipboard.
═══════════════════════════════════════════════════════════════════════
]]

local RS = game:GetService('ReplicatedStorage')
local WS = game:GetService('Workspace')
local out = { regions = {}, regionutils_funcs = {}, workspace_region_hits = {}, current_region = nil }

-- Known region names (captured from ChangeRegionRemote in DamageSpy/RemoteHook
-- plus the names you've seen on the realm transition banner). Add any missing
-- ones here; the scanner will dump every one it can resolve.
local KNOWN = {
    'Desert','Volcano Island','Seaweed Depths','Rocky Drop','Jungle','Algae Sandbar',
    'Central Rockfaces','Swamp Hill','Coral Reef','Grassy Shoal','Redwoods','Mountains',
    'Tundra','Flower Cave','Mesa','Tropical Islands','The Forest','Mushroom Forest',
    'Mangrove','Plains','Steppe','Frozen Wastes','Northern Mountains','Cliffs',
    'Tar Pits','Plateau','Goose Glacier','Frostbite Spire','Ice Caves',
}

local function ser(v, d, seen)
    d = d or 0; seen = seen or {}
    local t = typeof(v)
    if t == 'Vector3'  then return ('V3(%.2f,%.2f,%.2f)'):format(v.X, v.Y, v.Z) end
    if t == 'CFrame'   then local p = v.Position; return ('CF(%.2f,%.2f,%.2f)'):format(p.X, p.Y, p.Z) end
    if t == 'Instance' then return '<' .. v:GetFullName() .. '>' end
    if t == 'number' or t == 'boolean' then return v end
    if t == 'string'   then return (#v > 120) and ('str[' .. #v .. ']') or v end
    if t == 'function' then return '<fn>' end
    if t == 'table' then
        if seen[v] then return '<cycle>' end
        if d > 5 then return '{...}' end
        seen[v] = true
        local r, n = {}, 0
        for k, val in pairs(v) do
            n = n + 1; if n > 200 then r['_more'] = true; break end
            r[tostring(k)] = ser(val, d + 1, seen)
        end
        return r
    end
    return '<' .. t .. '>'
end

-- require with timeout (RegionUtils is cached -> instant)
local function safeRequire(mod)
    if not mod then return nil end
    local res, done
    task.spawn(function() local ok, r = pcall(require, mod); done = true; if ok then res = r end end)
    local t0 = os.clock()
    while not done and os.clock() - t0 < 5 do task.wait(0.05) end
    return res
end

local rf = RS:FindFirstChild('_replicationFolder')
local regionUtils = safeRequire(rf and rf:FindFirstChild('RegionUtils'))

-- 1) list RegionUtils method names
if type(regionUtils) == 'table' then
    for k, v in pairs(regionUtils) do
        out.regionutils_funcs[#out.regionutils_funcs + 1] = ('%s = %s'):format(tostring(k), type(v))
    end
    -- 2) call getRegion (current region) and getRegionModel(name) for known names
    pcall(function()
        if regionUtils.getRegion then
            local cur = regionUtils.getRegion()
            out.current_region = ser(cur)
        end
    end)
    if regionUtils.getRegionModel then
        for _, name in ipairs(KNOWN) do
            local ok, model = pcall(regionUtils.getRegionModel, name)
            if ok and model then
                local rec = { name = name, class = typeof(model) }
                pcall(function()
                    if typeof(model) == 'Instance' then
                        rec.full = model:GetFullName()
                        if model:IsA('Model') then
                            local p = model:GetPivot().Position
                            rec.pivot = ('%.2f,%.2f,%.2f'):format(p.X, p.Y, p.Z)
                            local cf, sz = model:GetBoundingBox()
                            rec.bb_center = ('%.2f,%.2f,%.2f'):format(cf.Position.X, cf.Position.Y, cf.Position.Z)
                            rec.bb_size   = ('%.2f,%.2f,%.2f'):format(sz.X, sz.Y, sz.Z)
                        elseif model:IsA('BasePart') then
                            local p = model.Position
                            rec.pos = ('%.2f,%.2f,%.2f'):format(p.X, p.Y, p.Z)
                        end
                    elseif typeof(model) == 'CFrame' then
                        rec.cframe = ser(model)
                    elseif typeof(model) == 'Vector3' then
                        rec.vector = ser(model)
                    else
                        rec.value = ser(model)
                    end
                end)
                out.regions[#out.regions + 1] = rec
            end
        end
    end
end

-- 3) blind sweep for any workspace Region-named container (fallback)
pcall(function()
    local count = 0
    for _, d in ipairs(WS:GetDescendants()) do
        count = count + 1; if count > 80000 then break end
        local nm = d.Name
        if nm:find('Region') and not nm:find('RegionUtil') then
            local rec = { path = d:GetFullName(), class = d.ClassName }
            pcall(function()
                if d:IsA('BasePart') then local p=d.Position; rec.pos=('%.2f,%.2f,%.2f'):format(p.X,p.Y,p.Z) end
                if d:IsA('Model') then local p=d:GetPivot().Position; rec.pivot=('%.2f,%.2f,%.2f'):format(p.X,p.Y,p.Z) end
            end)
            out.workspace_region_hits[#out.workspace_region_hits + 1] = rec
            if #out.workspace_region_hits >= 50 then break end
        end
    end
end)

local json
local ok = pcall(function() json = game:GetService('HttpService'):JSONEncode(out) end)
if not ok or not json then json = '{"error":"JSONEncode failed"}' end
pcall(function() if writefile then writefile('HSHub_RegionScan.json', json) end end)
pcall(function() if setclipboard then setclipboard(json) elseif toclipboard then toclipboard(json) end end)

pcall(function()
    local g = Instance.new('ScreenGui'); g.Name = 'HSHub_RegionScan'
    g.Parent = (gethui and gethui()) or game:GetService('CoreGui')
    local l = Instance.new('TextLabel', g)
    l.Size = UDim2.new(0, 540, 0, 96); l.Position = UDim2.new(0.5, -270, 0, 80)
    l.BackgroundColor3 = Color3.fromRGB(20, 20, 28); l.TextColor3 = Color3.fromRGB(150, 230, 170)
    l.Font = Enum.Font.Code; l.TextSize = 12; l.TextWrapped = true
    l.Text = ('RegionScan DONE.\nRegionUtils funcs=%d  resolved regions=%d  workspace hits=%d\nSaved HSHub_RegionScan.json (+ clipboard).')
        :format(#out.regionutils_funcs, #out.regions, #out.workspace_region_hits)
    Instance.new('UICorner', l)
    task.delay(16, function() g:Destroy() end)
end)
