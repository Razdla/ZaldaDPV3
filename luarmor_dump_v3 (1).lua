--[[ =====================================================================
    MARBEG HUB — LUARMOR V4 RUNTIME DUMPER  (v3 — perf pass)
    Target executor: Delta (also Synapse X / Krampus / Fluxus / Wave)

    CHANGES from v2 (all perf-related, no feature loss):
      [P1] Debounced manifest flush — was: per-capture write.
           Now: dirty flag + background flush every CONFIG.flush_interval_sec.
           Manual SAVE NOW button forces immediate flush.
      [P2] Bounded load(fn) capture — was: drain entire function, concat all.
           Now: cap pieces at CONFIG.max_fn_pieces, stop reading beyond limit.
           Can be disabled entirely via CONFIG.hook_load_fn = false.
      [P3] Ring-bounded readfile/writefile logs — was: unbounded append.
           Now: keep last CONFIG.max_io_log_entries, drop oldest.
      [P4] Deferred caller info — was: debug.getinfo before dedupe check.
           Now: only walk stack when capture actually passes dedupe.
      [P5] Globals snapshot throttled — was: 5s, always write.
           Now: CONFIG.snapshot_every_sec (default 30s), skip if unchanged.
      [P6] Adaptive UI poll — was: 0.5s constant.
           Now: 0.5s when activity seen, 2s when idle.
      [P7] UI history row cap — was: unbounded append (memory leak).
           Now: trim to CONFIG.max_ui_history rows.
      [P8] Fixed ok_ui scope bug — was: always reported UI failed.

    USAGE: same as v2. Paste, run, wait for UI, then run Marbeg loader.
===================================================================== ]]--

if getgenv().__marbeg_dumper_v3_active then
    warn("[MARBEG DUMPER v3] Already running — won't double-hook.")
    if getgenv().__marbeg_dumper_show_ui then getgenv().__marbeg_dumper_show_ui() end
    return
end
-- also respect older guards so we don't stack with v1/v2
if getgenv().__marbeg_dumper_v2_active or getgenv().__marbeg_dumper_active then
    warn("[MARBEG DUMPER v3] v1/v2 already active in this session — rejoin game first.")
    return
end
getgenv().__marbeg_dumper_v3_active = true

-- ---------- 0. CONFIG ---------------------------------------------------
local CONFIG = {
    output_folder          = "marbeg_dumps",
    max_capture_bytes      = 16 * 1024 * 1024,
    -- perf knobs
    flush_interval_sec     = 2.0,    -- how often to flush manifest to disk
    max_fn_pieces          = 256,    -- cap pieces when hooking load(fn)
    max_io_log_entries     = 200,    -- ring buffer size for readfile/writefile logs
    snapshot_every_sec     = 30,     -- was 5 in v2
    snapshot_skip_if_same  = true,   -- skip disk write if globals unchanged
    -- feature toggles (turn off for max perf in heavy games)
    hook_load_fn           = true,   -- set false if load(function) path is heavy
    hook_readfile          = true,
    hook_writefile         = true,
    enable_global_watcher  = true,
    -- UI
    ui_poll_active_sec     = 0.5,
    ui_poll_idle_sec       = 2.0,
    max_ui_history         = 5,
    ui_position = UDim2.new(0, 20, 0, 100),
    ui_size     = UDim2.new(0, 300, 0, 260),
}

-- ---------- 1. EXECUTOR API DETECTION ---------------------------------
local hookfunction  = hookfunction or (syn and syn.hook) or (Krampus and Krampus.hook) or hookfunc
local writefile     = writefile
local readfile_orig = readfile
local isfolder      = isfolder or function() return false end
local makefolder    = makefolder or function() end
local newcclosure   = newcclosure or function(f) return f end
local identifyexecutor = identifyexecutor or function() return "unknown", "0.0" end
local setclipboard  = setclipboard or (toclipboard) or function() end

if not hookfunction then
    warn("[MARBEG DUMPER v3] hookfunction unavailable. ABORT.")
    return
end
if not writefile then
    warn("[MARBEG DUMPER v3] writefile unavailable. ABORT.")
    return
end

-- ---------- 2. WORKSPACE SETUP ----------------------------------------
if not isfolder(CONFIG.output_folder) then
    pcall(makefolder, CONFIG.output_folder)
end

local exec_name, exec_ver = identifyexecutor()
local start_epoch = os.time()
local start_label = os.date("%Y%m%d_%H%M%S")

-- ---------- 3. STATE --------------------------------------------------
local state = {
    captures = {},
    readfile_log = {},          -- ring-bounded
    writefile_log = {},         -- ring-bounded
    rf_dropped = 0,             -- count of dropped entries beyond ring
    wf_dropped = 0,
    capture_count = 0,
    dupe_hashes = {},
    start_time = tick(),
    hooks_attached = {
        load = false, loadstring = false,
        readfile = false, writefile = false,
    },
    last_error = nil,
    last_activity_time = 0,     -- for adaptive UI poll
}

-- dirty flags for debounced flush
local dirty = { manifest = false }
local function mark_dirty() dirty.manifest = true end

-- ---------- 4. UTILITIES ----------------------------------------------
local function fnv1a(s)
    if type(s) ~= "string" then s = tostring(s) end
    local h = 2166136261
    for i = 1, math.min(#s, 2048) do
        h = (h * 16777619) % 4294967296
        h = bit32.bxor(h, string.byte(s, i))
    end
    return string.format("%08x", h)
end

local function json_encode(v, depth)
    depth = depth or 0
    if depth > 6 then return '"<depth-limit>"' end
    local t = type(v)
    if t == "nil" then return "null"
    elseif t == "boolean" then return v and "true" or "false"
    elseif t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then return "null" end
        return tostring(v)
    elseif t == "string" then
        return '"' .. v:gsub('[\\"%c]', function(c)
            local b = string.byte(c)
            if b == 0x22 then return '\\"'
            elseif b == 0x5C then return '\\\\'
            elseif b == 0x0A then return '\\n'
            elseif b == 0x0D then return '\\r'
            elseif b == 0x09 then return '\\t'
            elseif b < 0x20 then return string.format('\\u%04x', b)
            else return c end
        end) .. '"'
    elseif t == "table" then
        local n, len = 0, #v
        for _ in pairs(v) do n = n + 1 end
        if len == n and n > 0 then
            local parts = {}
            for i = 1, len do parts[i] = json_encode(v[i], depth + 1) end
            return "[" .. table.concat(parts, ",") .. "]"
        else
            local parts = {}
            for k, val in pairs(v) do
                parts[#parts + 1] = json_encode(tostring(k), depth + 1) .. ":" .. json_encode(val, depth + 1)
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
    end
    return '"<' .. t .. '>"'
end

local function write_json(path, data)
    local ok, err = pcall(writefile, path, json_encode(data))
    if not ok then state.last_error = tostring(err):sub(1, 80) end
end

-- [P4] Only called AFTER dedupe passes
local function get_caller()
    local ok, info = pcall(debug.getinfo, 4, "Sn")
    if not ok or not info then return {short="?", line=0, name="?"} end
    return {
        short = (info.short_src or "?"):sub(1, 60),
        line  = info.currentline or 0,
        name  = (info.name or "?"):sub(1, 20),
    }
end

-- [P3] Ring buffer push — drop oldest when over limit
local function ring_push(buf, item, max)
    buf[#buf + 1] = item
    if #buf > max then
        -- shift one out; table.remove O(n) but amortized fine at this rate
        table.remove(buf, 1)
        return true  -- indicates dropped
    end
    return false
end

-- ---------- 5. CAPTURE ENGINE -----------------------------------------
-- [P1] Build manifest object only at flush time
local function build_manifest()
    return {
        session_start = start_label,
        session_epoch = start_epoch,
        executor = exec_name,
        executor_ver = exec_ver,
        elapsed_sec = tick() - state.start_time,
        capture_count = state.capture_count,
        captures = state.captures,
        hooks_attached = state.hooks_attached,
        readfile_dropped = state.rf_dropped,
        writefile_dropped = state.wf_dropped,
    }
end

local function flush_manifest_now()
    write_json(CONFIG.output_folder .. "/manifest.json", build_manifest())
    write_json(CONFIG.output_folder .. "/readfile_log.json", state.readfile_log)
    write_json(CONFIG.output_folder .. "/writefile_log.json", state.writefile_log)
    dirty.manifest = false
end

-- [P1] Background flush coroutine — coalesces writes
task.spawn(function()
    while true do
        task.wait(CONFIG.flush_interval_sec)
        if dirty.manifest then
            pcall(flush_manifest_now)
        end
    end
end)

local function capture_source(origin, src, chunk_name)
    if type(src) ~= "string" then return end
    if #src < 32 then return end
    if #src > CONFIG.max_capture_bytes then
        src = src:sub(1, CONFIG.max_capture_bytes)
    end

    local h = fnv1a(src)
    if state.dupe_hashes[h] then return end
    state.dupe_hashes[h] = true

    -- [P4] caller info NOW (post-dedupe)
    state.capture_count = state.capture_count + 1
    local n = state.capture_count
    local filename = string.format("%03d_%s.lua", n, h)

    local info = {
        n = n, hash = h, origin = origin,
        chunk_name = tostring(chunk_name or ""):sub(1, 80),
        size = #src,
        time = tick() - state.start_time,
        caller = get_caller(),
    }
    state.captures[#state.captures + 1] = info

    local header = string.format(
        "--[[ MARBEG DUMP #%d\n  origin: %s\n  chunk:  %s\n  size:   %d bytes\n  hash:   %s\n  time:   %.2fs\n  caller: %s:%d (%s)\n]]--\n",
        n, origin, info.chunk_name, #src, h, info.time,
        info.caller.short, info.caller.line, info.caller.name
    )
    -- Individual dump file still written immediately (one-shot, not replayed)
    local ok, err = pcall(writefile, CONFIG.output_folder .. "/" .. filename, header .. src)
    if not ok then state.last_error = "writefile: " .. tostring(err):sub(1, 60) end

    -- [P1] mark dirty instead of flushing manifest now
    mark_dirty()
    state.last_activity_time = tick()
end

-- ---------- 6. HOOKS --------------------------------------------------
local loadstring_hook, load_hook, readfile_hook, writefile_hook

local ok
ok = pcall(function()
    loadstring_hook = hookfunction(loadstring, newcclosure(function(src, chunk)
        pcall(capture_source, "loadstring", src, chunk)
        return loadstring_hook(src, chunk)
    end))
    state.hooks_attached.loadstring = true
end)
if not ok then state.last_error = "hook loadstring failed" end

ok = pcall(function()
    load_hook = hookfunction(load, newcclosure(function(chunk_or_fn, chunk_name, mode, env)
        if type(chunk_or_fn) == "string" then
            pcall(capture_source, "load", chunk_or_fn, chunk_name)
            return load_hook(chunk_or_fn, chunk_name, mode, env)
        end
        -- [P2] function-chunk path — bounded, or skippable entirely
        if type(chunk_or_fn) == "function" then
            if not CONFIG.hook_load_fn then
                return load_hook(chunk_or_fn, chunk_name, mode, env)
            end
            local pieces, total, overflow = {}, 0, false
            local wrapped = function()
                local piece = chunk_or_fn()
                if piece and #piece > 0 and not overflow then
                    if #pieces < CONFIG.max_fn_pieces
                       and total < CONFIG.max_capture_bytes then
                        pieces[#pieces + 1] = piece
                        total = total + #piece
                    else
                        overflow = true
                    end
                end
                return piece
            end
            local fn_result, err = load_hook(wrapped, chunk_name, mode, env)
            if #pieces > 0 then
                local joined = table.concat(pieces)
                if overflow then
                    joined = joined .. "\n--[[ MARBEG: truncated, overflow ]]--"
                end
                pcall(capture_source, "load(fn)", joined, chunk_name)
            end
            return fn_result, err
        end
        return load_hook(chunk_or_fn, chunk_name, mode, env)
    end))
    state.hooks_attached.load = true
end)
if not ok then state.last_error = "hook load failed" end

if readfile_orig and CONFIG.hook_readfile then
    ok = pcall(function()
        readfile_hook = hookfunction(readfile, newcclosure(function(path)
            local result = readfile_hook(path)
            -- [P3] ring-bounded + minimal work; pcall so bad __tostring can't break us
            pcall(function()
                local dropped = ring_push(state.readfile_log, {
                    path = tostring(path),
                    size = type(result) == "string" and #result or 0,
                    time = tick() - state.start_time,
                }, CONFIG.max_io_log_entries)
                if dropped then state.rf_dropped = state.rf_dropped + 1 end
                state.last_activity_time = tick()
                mark_dirty()
            end)
            return result
        end))
        state.hooks_attached.readfile = true
    end)
end

if CONFIG.hook_writefile then
    ok = pcall(function()
        writefile_hook = hookfunction(writefile, newcclosure(function(path, content)
            -- pcall the log so a bad __tostring path can't break writefile itself
            pcall(function()
                local p = tostring(path)
                if not p:find(CONFIG.output_folder, 1, true) then
                    local dropped = ring_push(state.writefile_log, {
                        path = p,
                        size = type(content) == "string" and #content or 0,
                        time = tick() - state.start_time,
                    }, CONFIG.max_io_log_entries)
                    if dropped then state.wf_dropped = state.wf_dropped + 1 end
                    state.last_activity_time = tick()
                    mark_dirty()
                end
            end)
            return writefile_hook(path, content)
        end))
        state.hooks_attached.writefile = true
    end)
end

-- ---------- 7. GLOBAL WATCHER (throttled + dedupe) --------------------
if CONFIG.enable_global_watcher then
    task.spawn(function()
        local snap_count = 0
        local last_signature = nil
        while true do
            task.wait(CONFIG.snapshot_every_sec)
            local g = getgenv()
            local snap = {
                time = tick() - state.start_time,
                script_key = type(g.script_key) == "string" and g.script_key:sub(1, 80) or nil,
                _G_keys = {},
            }
            for _, k in ipairs({"superflow_bytecode","_bsdata0","script_key",
                                "KRNL_LOADED","LRM_loaded","LURMOR","Luarmor"}) do
                local v = g[k] or _G[k]
                if v ~= nil then
                    snap._G_keys[k] = {type = type(v)}
                    if type(v) == "table" then
                        snap._G_keys[k].len = #v
                        local samples = {}
                        for i = 1, math.min(#v, 3) do
                            samples[i] = {t = type(v[i]),
                                          len = type(v[i]) == "string" and #v[i] or nil,
                                          prefix = type(v[i]) == "string" and v[i]:sub(1, 30):gsub("[^%g ]", "?") or nil}
                        end
                        snap._G_keys[k].samples = samples
                    elseif type(v) == "string" then
                        snap._G_keys[k].len = #v
                        snap._G_keys[k].prefix = v:sub(1, 60):gsub("[^%g ]", "?")
                    end
                end
            end
            -- [P5] signature = cheap dedupe — skip write if unchanged
            local sig_parts = {}
            for k, meta in pairs(snap._G_keys) do
                sig_parts[#sig_parts + 1] = k .. ":" .. (meta.type or "?") .. ":" .. tostring(meta.len or "")
            end
            table.sort(sig_parts)
            local sig = table.concat(sig_parts, "|") .. "|" .. tostring(snap.script_key or "")
            if CONFIG.snapshot_skip_if_same and sig == last_signature then
                -- nothing new, don't write
            else
                snap_count = snap_count + 1
                last_signature = sig
                write_json(string.format("%s/globals_snapshot_%03d.json",
                                         CONFIG.output_folder, snap_count), snap)
            end
        end
    end)
end

-- ---------- 8. UI ------------------------------------------------------
local function build_ui()
    local ok_ui, err_ui = pcall(function()
        local parent
        local ok_hui, hui_result = pcall(function() return gethui and gethui() end)
        if ok_hui and hui_result then
            parent = hui_result
        else
            parent = game:GetService("CoreGui")
        end

        for _, c in ipairs(parent:GetChildren()) do
            if c.Name == "MarbegDumperUIv3" or c.Name == "MarbegDumperUIv2" then
                c:Destroy()
            end
        end

        local gui = Instance.new("ScreenGui")
        gui.Name = "MarbegDumperUIv3"
        gui.ResetOnSpawn = false
        gui.DisplayOrder = 999999
        gui.IgnoreGuiInset = true
        gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        pcall(function() gui.Parent = parent end)
        if not gui.Parent then
            local plr = game:GetService("Players").LocalPlayer
            if plr and plr:FindFirstChild("PlayerGui") then
                gui.Parent = plr.PlayerGui
            end
        end

        local frame = Instance.new("Frame", gui)
        frame.Size = CONFIG.ui_size
        frame.Position = CONFIG.ui_position
        frame.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
        frame.BorderSizePixel = 0
        frame.Active = true
        frame.Draggable = true
        Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

        local stroke = Instance.new("UIStroke", frame)
        stroke.Color = Color3.fromRGB(60, 70, 90)
        stroke.Thickness = 1

        local bar = Instance.new("Frame", frame)
        bar.Size = UDim2.new(1, 0, 0, 28)
        bar.BackgroundColor3 = Color3.fromRGB(30, 34, 46)
        bar.BorderSizePixel = 0
        Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 8)

        local title = Instance.new("TextLabel", bar)
        title.Size = UDim2.new(1, -60, 1, 0)
        title.Position = UDim2.new(0, 10, 0, 0)
        title.BackgroundTransparency = 1
        title.Text = "MARBEG DUMPER v3"
        title.TextColor3 = Color3.fromRGB(200, 210, 230)
        title.Font = Enum.Font.Code
        title.TextSize = 13
        title.TextXAlignment = Enum.TextXAlignment.Left

        local minBtn = Instance.new("TextButton", bar)
        minBtn.Size = UDim2.new(0, 24, 0, 20)
        minBtn.Position = UDim2.new(1, -28, 0, 4)
        minBtn.BackgroundColor3 = Color3.fromRGB(50, 60, 80)
        minBtn.Text = "—"
        minBtn.TextColor3 = Color3.fromRGB(230, 230, 230)
        minBtn.Font = Enum.Font.Code
        minBtn.TextSize = 14
        minBtn.BorderSizePixel = 0
        Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 4)

        local badge = Instance.new("TextLabel", frame)
        badge.Size = UDim2.new(1, -20, 0, 26)
        badge.Position = UDim2.new(0, 10, 0, 34)
        badge.BackgroundColor3 = Color3.fromRGB(80, 65, 20)
        badge.BorderSizePixel = 0
        badge.Text = "● ARMED — waiting for load()"
        badge.TextColor3 = Color3.fromRGB(255, 220, 140)
        badge.Font = Enum.Font.Code
        badge.TextSize = 12
        badge.TextXAlignment = Enum.TextXAlignment.Center
        Instance.new("UICorner", badge).CornerRadius = UDim.new(0, 4)

        local hooks_label = Instance.new("TextLabel", frame)
        hooks_label.Size = UDim2.new(1, -20, 0, 16)
        hooks_label.Position = UDim2.new(0, 10, 0, 64)
        hooks_label.BackgroundTransparency = 1
        hooks_label.TextColor3 = Color3.fromRGB(160, 170, 190)
        hooks_label.Font = Enum.Font.Code
        hooks_label.TextSize = 11
        hooks_label.TextXAlignment = Enum.TextXAlignment.Left

        local stats = Instance.new("TextLabel", frame)
        stats.Size = UDim2.new(1, -20, 0, 44)
        stats.Position = UDim2.new(0, 10, 0, 82)
        stats.BackgroundTransparency = 1
        stats.TextColor3 = Color3.fromRGB(220, 225, 240)
        stats.Font = Enum.Font.Code
        stats.TextSize = 11
        stats.TextXAlignment = Enum.TextXAlignment.Left
        stats.TextYAlignment = Enum.TextYAlignment.Top

        local history = Instance.new("ScrollingFrame", frame)
        history.Size = UDim2.new(1, -20, 0, 72)
        history.Position = UDim2.new(0, 10, 0, 128)
        history.BackgroundColor3 = Color3.fromRGB(12, 14, 20)
        history.BorderSizePixel = 0
        history.ScrollBarThickness = 4
        history.CanvasSize = UDim2.new(0, 0, 0, 0)
        Instance.new("UICorner", history).CornerRadius = UDim.new(0, 4)

        local hlayout = Instance.new("UIListLayout", history)
        hlayout.SortOrder = Enum.SortOrder.LayoutOrder
        hlayout.Padding = UDim.new(0, 2)
        local hpad = Instance.new("UIPadding", history)
        hpad.PaddingLeft = UDim.new(0, 4)
        hpad.PaddingTop = UDim.new(0, 2)

        local function make_btn(text, color, xoffset)
            local b = Instance.new("TextButton", frame)
            b.Size = UDim2.new(0.333, -8, 0, 24)
            b.Position = UDim2.new(0.333 * xoffset, (xoffset == 0 and 10 or 4), 0, 208)
            b.BackgroundColor3 = color
            b.Text = text
            b.TextColor3 = Color3.fromRGB(255, 255, 255)
            b.Font = Enum.Font.Code
            b.TextSize = 11
            b.BorderSizePixel = 0
            Instance.new("UICorner", b).CornerRadius = UDim.new(0, 4)
            return b
        end
        local saveBtn = make_btn("SAVE NOW",     Color3.fromRGB(40,  95, 60), 0)
        local copyBtn = make_btn("COPY MANIFEST", Color3.fromRGB(50,  70, 100), 1)
        local clearBtn= make_btn("CLEAR DUMPS",  Color3.fromRGB(110, 50, 50), 2)

        local foot = Instance.new("TextLabel", frame)
        foot.Size = UDim2.new(1, -20, 0, 14)
        foot.Position = UDim2.new(0, 10, 1, -18)
        foot.BackgroundTransparency = 1
        foot.TextColor3 = Color3.fromRGB(120, 130, 150)
        foot.Font = Enum.Font.Code
        foot.TextSize = 10
        foot.TextXAlignment = Enum.TextXAlignment.Left
        foot.Text = string.format("exec: %s | folder: %s | flush:%.1fs",
                                  tostring(exec_name), CONFIG.output_folder,
                                  CONFIG.flush_interval_sec)

        saveBtn.MouseButton1Click:Connect(function()
            pcall(flush_manifest_now)  -- force immediate
            badge.Text = "● SAVED MANUALLY @ " .. string.format("%.1fs", tick() - state.start_time)
        end)

        copyBtn.MouseButton1Click:Connect(function()
            local ok_c = pcall(setclipboard, json_encode({
                captures = state.captures, hooks = state.hooks_attached,
                readfile_count = #state.readfile_log,
                writefile_count = #state.writefile_log,
                rf_dropped = state.rf_dropped,
                wf_dropped = state.wf_dropped,
            }))
            if ok_c then
                badge.Text = "● MANIFEST COPIED TO CLIPBOARD"
            else
                badge.Text = "✗ CLIPBOARD FAILED (see workspace/" .. CONFIG.output_folder .. ")"
            end
        end)

        clearBtn.MouseButton1Click:Connect(function()
            state.captures = {}
            state.dupe_hashes = {}
            state.capture_count = 0
            state.readfile_log = {}
            state.writefile_log = {}
            state.rf_dropped = 0
            state.wf_dropped = 0
            for _, child in ipairs(history:GetChildren()) do
                if child:IsA("TextLabel") then child:Destroy() end
            end
            pcall(flush_manifest_now)
            badge.Text = "● CLEARED"
        end)

        local minimized = false
        local saved_size = frame.Size
        minBtn.MouseButton1Click:Connect(function()
            minimized = not minimized
            if minimized then
                frame.Size = UDim2.new(0, CONFIG.ui_size.X.Offset, 0, 28)
                minBtn.Text = "+"
            else
                frame.Size = saved_size
                minBtn.Text = "—"
            end
        end)

        -- [P6] Adaptive UI poll — fast when active, slow when idle
        local last_seen_capture = 0
        task.spawn(function()
            while gui.Parent do
                local now = tick()
                local elapsed = now - state.start_time

                local function mk(name)
                    return state.hooks_attached[name] and
                        ('<font color="rgb(120,220,140)">'..name..'✓</font>') or
                        ('<font color="rgb(220,100,100)">'..name..'✗</font>')
                end
                hooks_label.RichText = true
                hooks_label.Text = "hooks: " .. mk("load") .. " " .. mk("loadstring") .. " " .. mk("readfile") .. " " .. mk("writefile")

                local last_size = 0
                local last_origin = "-"
                if #state.captures > 0 then
                    last_size = state.captures[#state.captures].size
                    last_origin = state.captures[#state.captures].origin
                end
                stats.Text = string.format(
                    "captures:  %d\nreadfile:  %d%s   writefile: %d%s\nelapsed:   %.1fs   last: %s (%d B)",
                    state.capture_count,
                    #state.readfile_log, state.rf_dropped > 0 and ("+"..state.rf_dropped) or "",
                    #state.writefile_log, state.wf_dropped > 0 and ("+"..state.wf_dropped) or "",
                    elapsed, last_origin, last_size
                )

                if state.last_error then
                    badge.BackgroundColor3 = Color3.fromRGB(90, 30, 30)
                    badge.TextColor3 = Color3.fromRGB(255, 180, 180)
                    badge.Text = "✗ ERROR: " .. state.last_error
                elseif state.capture_count > 0 then
                    badge.BackgroundColor3 = Color3.fromRGB(25, 80, 40)
                    badge.TextColor3 = Color3.fromRGB(180, 255, 200)
                    if state.capture_count ~= last_seen_capture then
                        badge.Text = string.format("● CAPTURED #%d (%d B) — saved to disk",
                            state.capture_count, last_size)
                    end
                elseif #state.readfile_log > 0 or #state.writefile_log > 0 then
                    badge.BackgroundColor3 = Color3.fromRGB(60, 70, 30)
                    badge.TextColor3 = Color3.fromRGB(255, 250, 180)
                    badge.Text = "● ACTIVE — file I/O seen, awaiting load()"
                end

                -- [P7] add new history rows + cap at max_ui_history
                while last_seen_capture < state.capture_count do
                    last_seen_capture = last_seen_capture + 1
                    local cap = state.captures[last_seen_capture]
                    if cap then
                        local row = Instance.new("TextLabel", history)
                        row.Size = UDim2.new(1, -8, 0, 14)
                        row.BackgroundTransparency = 1
                        row.TextColor3 = Color3.fromRGB(180, 210, 170)
                        row.Font = Enum.Font.Code
                        row.TextSize = 10
                        row.TextXAlignment = Enum.TextXAlignment.Left
                        row.LayoutOrder = -last_seen_capture
                        row.Text = string.format("#%d  %s  %dB  %.1fs",
                            cap.n, cap.origin:sub(1, 12), cap.size, cap.time)
                    end
                end
                -- prune oldest rows over cap
                local rows = {}
                for _, c in ipairs(history:GetChildren()) do
                    if c:IsA("TextLabel") then rows[#rows+1] = c end
                end
                if #rows > CONFIG.max_ui_history then
                    -- sort by LayoutOrder asc (oldest last since we used -n)
                    table.sort(rows, function(a, b) return a.LayoutOrder > b.LayoutOrder end)
                    for i = CONFIG.max_ui_history + 1, #rows do
                        rows[i]:Destroy()
                    end
                end
                history.CanvasSize = UDim2.new(0, 0, 0, hlayout.AbsoluteContentSize.Y + 4)

                -- adaptive wait: fast if recent activity
                local wait_sec
                if now - state.last_activity_time < 3 then
                    wait_sec = CONFIG.ui_poll_active_sec
                else
                    wait_sec = CONFIG.ui_poll_idle_sec
                end
                task.wait(wait_sec)
            end
        end)
    end)
    if not ok_ui then
        warn("[MARBEG DUMPER v3] UI build failed: " .. tostring(err_ui))
        state.last_error = "UI failed"
    end
    return ok_ui
end

getgenv().__marbeg_dumper_show_ui = build_ui
build_ui()

-- ---------- 9. READY --------------------------------------------------
pcall(flush_manifest_now)
print(string.format("[MARBEG DUMPER v3] armed.  exec=%s  folder=workspace/%s",
      tostring(exec_name), CONFIG.output_folder))
print(string.format("[MARBEG DUMPER v3] hooks:  load=%s  loadstring=%s  readfile=%s  writefile=%s",
      tostring(state.hooks_attached.load),
      tostring(state.hooks_attached.loadstring),
      tostring(state.hooks_attached.readfile),
      tostring(state.hooks_attached.writefile)))
print(string.format("[MARBEG DUMPER v3] perf:  flush=%.1fs  io_ring=%d  snap=%ds  load_fn=%s",
      CONFIG.flush_interval_sec, CONFIG.max_io_log_entries,
      CONFIG.snapshot_every_sec, tostring(CONFIG.hook_load_fn)))
print("[MARBEG DUMPER v3] now run Marbeg Hub loader in the same session.")
