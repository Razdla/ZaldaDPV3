-- ══════════════════════════════════════════════════════════════════
--  HSHub CoS — Loader
--  Version : 1.0 (Simple Key)
--
--  STATUS SAAT INI:
--    [✓] Load script dari GitHub Raw (obfuscated)
--    [✓] Simple text key check (lokal, tanpa server)
--    [ ] HWID lock         → lihat LOADER_NOTES.md
--    [ ] API server auth   → lihat LOADER_NOTES.md
--    [ ] Auto-update       → lihat LOADER_NOTES.md
-- ══════════════════════════════════════════════════════════════════

-- ─── KONFIGURASI ─────────────────────────────────────────────────

-- [!] Ganti dengan URL GitHub Raw script yang sudah di-obfuscate
local SCRIPT_URL = "https://raw.githubusercontent.com/USER/REPO/main/HSHub_CoS_obf.lua"

-- [!] Daftar key yang valid — ganti / tambah sesukamu
--     Nanti ini akan diganti dengan validasi ke API server (lihat LOADER_NOTES.md)
local VALID_KEYS = {
    "HSHUB-XXXXX-XXXXX-XXXXX",  -- ganti dengan key asli
    -- "HSHUB-AAAAA-BBBBB-CCCCC",
}

-- ─── KEY INPUT ───────────────────────────────────────────────────

-- Ambil key dari _G kalau sudah di-set sebelumnya (opsional),
-- atau user edit langsung variabel MY_KEY di bawah ini.
local MY_KEY = _G._HSHub_Key or ""

-- Kalau MY_KEY kosong, tampilkan prompt via executor (jika didukung)
if MY_KEY == "" then
    pcall(function()
        -- Beberapa executor support input prompt — kalau tidak support, lewat saja
        if typeof(inputbox) == "function" then
            MY_KEY = inputbox("HSHub CoS", "Masukkan key kamu:") or ""
        end
    end)
end

-- ─── VALIDASI KEY ────────────────────────────────────────────────

local keyValid = false
for _, k in ipairs(VALID_KEYS) do
    if k == MY_KEY then
        keyValid = true
        break
    end
end

if not keyValid then
    -- ──────────────────────────────────────────────────────────────
    -- TODO (API SERVER): Ganti blok ini dengan POST /auth ke API
    --   local resp = httpRequest({
    --       Url    = API_BASE_URL .. "/auth",
    --       Method = "POST",
    --       Headers = {
    --           ["Content-Type"] = "application/json",
    --           ["x-hwid"]       = HWID,          -- tambah nanti
    --       },
    --       Body = HttpService:JSONEncode({ key = MY_KEY, hwid = HWID })
    --   })
    --   local data = HttpService:JSONDecode(resp.Body)
    --   keyValid = (resp.StatusCode == 200 and data.valid == true)
    -- ──────────────────────────────────────────────────────────────

    warn("[HSHub] ✗ Key tidak valid. Script tidak dijalankan.")
    return  -- stop eksekusi
end

-- ─── SET _G (untuk komunikasi ke main script) ────────────────────

_G._HSHub_Key      = MY_KEY
_G._HSHub_Loaded   = true

-- TODO (HWID): Tambah ini setelah API server siap — lihat LOADER_NOTES.md
-- _G._HSHub_HWID  = HWID

-- TODO (API SERVER): Isi ini setelah punya server — lihat LOADER_NOTES.md
-- _G._HSHub_ApiKey    = "..."
-- _G._HSHub_BaseUrl   = "..."

-- ─── LOAD MAIN SCRIPT ────────────────────────────────────────────

local http = (syn and syn.request)
    or (http and http.request)
    or (fluxus and fluxus.request)
    or (request)
    or nil

local src = nil

if http then
    local ok, resp = pcall(function()
        return http({ Url = SCRIPT_URL, Method = "GET" })
    end)
    if ok and resp and resp.StatusCode == 200 and #resp.Body > 100 then
        src = resp.Body
    else
        warn("[HSHub] ✗ Gagal fetch via httpRequest. Status: " .. tostring(resp and resp.StatusCode))
    end
end

-- Fallback ke HttpGetAsync kalau httpRequest tidak tersedia
if not src then
    local ok, result = pcall(function()
        return game:HttpGetAsync(SCRIPT_URL)
    end)
    if ok and result and #result > 100 then
        src = result
    else
        warn("[HSHub] ✗ Gagal fetch via HttpGetAsync.")
    end
end

if not src then
    warn("[HSHub] ✗ Tidak bisa load script. Cek URL atau koneksi.")
    return
end

-- ─── EKSEKUSI ────────────────────────────────────────────────────

local fn, err = loadstring(src)
if not fn then
    warn("[HSHub] ✗ loadstring error: " .. tostring(err))
    return
end

print("[HSHub] ✓ Key valid. Memuat HSHub CoS...")
local ok, runErr = pcall(fn)
if not ok then
    warn("[HSHub] ✗ Runtime error: " .. tostring(runErr))
end
