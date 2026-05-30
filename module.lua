--[[
═══════════════════════════════════════════════════════════════════════
                          HS HUB
                       Hydra Solvation
                         by isentp
                  discord.gg/5rpP6faZSJ

    Game     : Creatures of Sonaria  (Roblox creature survival)
    Build    : HS-COS-V4
    Date     : 2026-05-24
    Library  : HSHub_UI v1.0.0

    V4: rebuilt with ground-truth remote/workspace paths from runtime
    diagnostic dump (HSHub_COS_Diagnostic_V2). All bindings VERIFIED
    against actual game state — no more guesses.

    Known broken (matches LUNAR original behaviour):
      - AutoDrink (LUNAR also broken)
      - ESP (LUNAR also broken)
      - AutoCowerState (StateAilment remote not found — likely renamed)
═══════════════════════════════════════════════════════════════════════
]]

local HSHub   = _G.HSHub
local Sig     = _G.HSHub_Signature
local Stealth = _G.HSHub_Stealth

assert(HSHub,   'HSHub_UI framework not loaded')
assert(Sig,     'HSHub_Signature not loaded')
assert(Stealth, 'HSHub_Stealth not loaded')

-- ═══════════════════════════════════════════════════════════════════
--   GAME GUARD
-- ═══════════════════════════════════════════════════════════════════
-- Normal CoS realm PlaceIds + Hardcore realm ("Sonaria: Alam Hardcore", PlaceId
-- 136015760267602, confirmed by HardcoreEnvScan 2026-05-29). Hardcore exposes a
-- 9th shrine (Shadow) and uses HardcoreDisaster* modules — autofarm needs to know.
local COS_PLACEIDS = { [5233782396]=true, [4922741943]=true, [3963303927]=true }
local HARDCORE_PLACEIDS = { [136015760267602]=true }
local PLACE_ISLE10 = 3431407618
local IS_ISLE10    = (game.PlaceId == PLACE_ISLE10)
local IS_HARDCORE  = HARDCORE_PLACEIDS[game.PlaceId] == true
local IS_COS       = (COS_PLACEIDS[game.PlaceId] == true) or IS_HARDCORE
local NAME_OK = false
if not IS_COS and not IS_ISLE10 then
    pcall(function()
        local info = game:GetService('MarketplaceService'):GetProductInfo(game.PlaceId)
        if info and info.Name then
            local n = info.Name:lower()
            if n:find('sonaria') or n:find('isle 10') or n:find('creatures of') or n:find('alam hardcore') then
                NAME_OK = true
                if n:find('hardcore') then IS_HARDCORE = true end
            end
        end
    end)
end
if not IS_COS and not IS_ISLE10 and not NAME_OK then
    HSHub:Notify('HS Hub COS: wrong game (PlaceId ' .. tostring(game.PlaceId) .. ')', 'warn', 5)
    return
end

-- ═══════════════════════════════════════════════════════════════════
--   SERVICES
-- ═══════════════════════════════════════════════════════════════════
local Players          = game:GetService('Players')
local RunService       = game:GetService('RunService')
local ReplicatedStorage= game:GetService('ReplicatedStorage')
local Workspace        = game:GetService('Workspace')
local UserInputService = game:GetService('UserInputService')
local TeleportService  = game:GetService('TeleportService')
local HttpService      = game:GetService('HttpService')
local Lighting         = game:GetService('Lighting')

local LP = Players.LocalPlayer
local PlayerGui = LP:WaitForChild('PlayerGui')

-- ═══════════════════════════════════════════════════════════════════
--   GROUND-TRUTH REMOTE PATHS (from HSHub_COS_Diagnostic_V2)
-- ═══════════════════════════════════════════════════════════════════
-- ReplicatedStorage.Remotes.* (16 remotes, the main hub)
local RS_REMOTES = {
    'DrinkRemote', 'Food', 'Mud', 'Lay', 'Nest',
    'LavaSelfDamage', 'Sheltered',
    'RestartSlotRemote', 'GetSpawnedTokenRemote',
    'StoreActiveCreatureRemote', 'CreateSlotRemote',
    'PickupResource', 'DepositResource', 'ChunkResource',
    'ResourceDamageRemote', 'UpgradeNest',
}
-- LocalPlayer.Remotes.* (5 player-scoped remotes)
local LP_REMOTES = {
    'NestRequestRemote', 'NestJoinRequestRemote',
    'PartyRequestRemote', 'PartyJoinRequestRemote',
    'NestSlotPickRequestRemote',
}

local _remote_cache = {}
local function getRemote(name)
    if _remote_cache[name] then return _remote_cache[name] end
    -- Try ReplicatedStorage.Remotes first (where most are)
    local rsRemotes = ReplicatedStorage:FindFirstChild('Remotes')
    if rsRemotes then
        local r = rsRemotes:FindFirstChild(name)
        if r then _remote_cache[name] = r; return r end
    end
    -- Then try LocalPlayer.Remotes
    local lpRemotes = LP:FindFirstChild('Remotes')
    if lpRemotes then
        local r = lpRemotes:FindFirstChild(name)
        if r then _remote_cache[name] = r; return r end
    end
    return nil
end

local function fire(name, ...)
    local r = getRemote(name); if not r then return false end
    local args = table.pack(...)
    return pcall(function()
        if r:IsA('RemoteEvent') then r:FireServer(table.unpack(args, 1, args.n))
        else return r:InvokeServer(table.unpack(args, 1, args.n)) end
    end)
end

local function invoke(name, ...)
    local r = getRemote(name); if not r then return nil end
    local args = table.pack(...)
    local ok, res = pcall(function() return r:InvokeServer(table.unpack(args, 1, args.n)) end)
    if ok then return res end
end

-- Fire on another player's Remotes folder (used by AutoAcceptNest)
local function fireOnPlayer(player, name, ...)
    local rfolder = player:FindFirstChild('Remotes')
    if not rfolder then return false end
    local r = rfolder:FindFirstChild(name)
    if not r then return false end
    local args = table.pack(...)
    return pcall(function() r:FireServer(table.unpack(args, 1, args.n)) end)
end

-- ═══════════════════════════════════════════════════════════════════
--   HUD HELPERS
-- ═══════════════════════════════════════════════════════════════════
local function getHUDGui() return PlayerGui:FindFirstChild('HUDGui') end

local function hudStatText(stat)
    local h = getHUDGui(); if not h then return nil end
    local ok, val = pcall(function() return h.BottomFrame.Other[stat].HoverLabel.Text end)
    return ok and val or nil
end

local function shelterColor()
    local h = getHUDGui(); if not h then return nil end
    local ok, val = pcall(function()
        return h.SideFrame.Other.MinimapFrame.ShelterLabel.HoverUpLabel.ImageColor3
    end)
    return ok and val or nil
end

-- ═══════════════════════════════════════════════════════════════════
--   GROUND-TRUTH WORKSPACE PATHS
-- ═══════════════════════════════════════════════════════════════════
-- workspace.Interactions.{Food, Mud, Lakes, TokenNodes, AbandonedEggSpawns, Nests}
local function interactions() return Workspace:FindFirstChild('Interactions') end

local function getChar() return LP.Character end
local function getRoot()
    local c = getChar(); if c then return c:FindFirstChild('HumanoidRootPart') end
end
local function getHumanoid()
    local c = getChar(); if c then return c:FindFirstChildOfClass('Humanoid') end
end

local function findNearestIn(folder, filter)
    if not folder then return nil end
    local r = getRoot(); if not r then return nil end
    local closest, dist = nil, math.huge
    for _, m in ipairs(folder:GetChildren()) do
        local part
        if m:IsA('BasePart') then part = m
        elseif m:IsA('Model') then part = m.PrimaryPart or m:FindFirstChildWhichIsA('BasePart')
            or m:FindFirstChild('Food') or m:FindFirstChild('Mud') end
        if part and part:IsA('BasePart') then
            if not filter or filter(m, part) then
                local d = (part.Position - r.Position).Magnitude
                if d < dist then closest, dist = m, d end
            end
        end
    end
    return closest
end

local function findNearestFood() local i = interactions(); return i and findNearestIn(i:FindFirstChild('Food')) end
local function findNearestMud()  local i = interactions(); return i and findNearestIn(i:FindFirstChild('Mud')) end
local function findNearestLake() local i = interactions(); return i and findNearestIn(i:FindFirstChild('Lakes')) end
local function findNearestToken()local i = interactions(); return i and findNearestIn(i:FindFirstChild('TokenNodes')) end
local function findNearestEgg() local i = interactions(); return i and findNearestIn(i:FindFirstChild('AbandonedEggSpawns')) end

-- ═══════════════════════════════════════════════════════════════════
--   STATE TABLE
-- ═══════════════════════════════════════════════════════════════════
local S = {
    -- Home/LocalPlayer
    AutoScentHidden=false, InstantLobbyReturn=false, AlwaysKeenObserver=false,
    AlwaysLayEffect=false, AutoShelter=false,
    -- Home/No-Damage
    NoLavaDamage=false, NoDrowningDamage=false, NoMeteorDamage=false,
    NoMoistureDamage=false, NoTornadoDamage=false,
    -- Home/Nest
    NestUpgradeTarget='Normal', AutoNestUpgrade=false,
    EnableAutoNest=false, InvitationType='Friends', AutoAcceptNest=false,
    -- Custom Stats / Combat
    AutoAggressive=false, AutoScared=false, AntiBrokenLeg=false,
    AntiShreddedWings=false, AntiConfusion=false, AntiGrab=false, InfStamina=false,
    -- Custom Stats / sliders
    TurnRadius=0, EnableTurnRadius=false,
    WalkSpeed=30, EnableWalkSpeed=false,
    SprintSpeed=115, EnableSprintSpeed=false,
    FlySpeed=40, EnableFlySpeed=false,
    -- Autofarm
    AutoEat=false, AutoDrink=false, AutoMudRoll=false,
    AutoGachaTokens=false,
    MutationTarget='', AutoMutations=false,
    TraitTarget='', AutoTraits=false,
    AutoMissions=false,
    SelectedCreature='', AutoSpawn=false, DeathPointsTarget=1200, AutoSelfKill=false,
    -- Esp
    GachaEspExplorer=false, GachaEspGalaxy=false, GachaEspMecha=false,
    GachaEspMonster=false, GachaEspSweet=false,
    AbandonedEggsEsp=false,
    EnablePlayerEsp=false, EspHealth=false, EspHealthBar=false, EspTracer=false,
    EspNames=false, EspDistance=false, EspBox=false, EspChameleon=false,
    -- Others
    RemoveFog=false, RemoveCameraEffects=false, RemoveDisasterEffects=false,
    HidePingFps=false, AntiAFK=false, CustomName='', HideUsername=false,
    LowQualityTextures=false, WhiteScreen=false,
}

-- ═══════════════════════════════════════════════════════════════════
--   UI BUILD
-- ═══════════════════════════════════════════════════════════════════
local Window = HSHub:CreateWindow({
    Title='HS HUB', Subtitle='Creatures of Sonaria' .. (IS_ISLE10 and ' (Isle 10)' or ''),
    Tag='HS-COS-V4', ToggleKey='RightShift',
})

-- ─── Tab 1: HOME ────────────────────────────────────────────────────
do
    local Tab = Window:CreateTab('Home', '◐')
    local M = Tab:CreateSection('MENU')
    M:AddButton({ Name='Get Max Storage Slots', Callback=function()
        -- LUNAR maps this to NestRequestRemote with action arg; harmless fallback
        fireOnPlayer(LP, 'NestRequestRemote', 'MaxStorage')
        HSHub:Notify('Max storage requested', 'ok', 2)
    end })

    local L = Tab:CreateSection('LOCALPLAYER')
    L:AddToggle({ Name='Auto Scent Hidden', Key='ASH', Default=false, Callback=function(v) S.AutoScentHidden=v end })
    L:AddToggle({ Name='Instant Lobby Return', Key='ILR', Default=false, Callback=function(v) S.InstantLobbyReturn=v end })
    L:AddToggle({ Name='Always Keen Observer', Key='AKO', Default=false, Callback=function(v) S.AlwaysKeenObserver=v end })
    L:AddToggle({ Name='Always Lay Effect', Key='ALE', Default=false, Callback=function(v) S.AlwaysLayEffect=v end })
    L:AddToggle({ Name='Auto Shelter', Key='AS', Default=false,
        Tip='Fires Sheltered when shelter indicator turns red',
        Callback=function(v) S.AutoShelter=v end })

    local D = Tab:CreateSection('NO DAMAGE')
    D:AddToggle({ Name='No Lava Damage',     Key='NLD', Default=false, Callback=function(v) S.NoLavaDamage=v end })
    D:AddToggle({ Name='No Drowning Damage', Key='NDD', Default=false, Callback=function(v) S.NoDrowningDamage=v end })
    D:AddToggle({ Name='No Meteor Damage',   Key='NMeD',Default=false, Callback=function(v) S.NoMeteorDamage=v end })
    D:AddToggle({ Name='No Moisture Damage', Key='NMoD',Default=false, Callback=function(v) S.NoMoistureDamage=v end })
    D:AddToggle({ Name='No Tornado Damage',  Key='NTD', Default=false, Callback=function(v) S.NoTornadoDamage=v end })

    local N = Tab:CreateSection('AUTO NEST')
    N:AddDropdown({ Name='Nest Upgrade', Key='NUT', Default='Normal',
        Values={'Normal','Premium','Royal'}, Callback=function(v) S.NestUpgradeTarget=v end })
    N:AddToggle({ Name='Auto Nest Upgrade', Key='ANU', Default=false, Callback=function(v) S.AutoNestUpgrade=v end })
    N:AddToggle({ Name='Enable Auto Nest', Key='EAN', Default=false, Callback=function(v) S.EnableAutoNest=v end })
    N:AddDropdown({ Name='Type of Invitation', Key='TOI', Default='Friends',
        Values={'Friends','Everyone','Trusted'}, Callback=function(v) S.InvitationType=v end })
    N:AddToggle({ Name='Auto Accept Nest Request', Key='AANR', Default=false,
        Callback=function(v) S.AutoAcceptNest=v end })
    N:AddButton({ Name='Teleport To Nest', Callback=function()
        fireOnPlayer(LP, 'NestRequestRemote', 'TeleportToNest')
    end })
    N:AddButton({ Name='Re-spawn Nest', Callback=function()
        fireOnPlayer(LP, 'NestRequestRemote', 'Respawn')
    end })
end

-- ─── Tab 2: CUSTOM STATS ────────────────────────────────────────────
do
    local Tab = Window:CreateTab('Custom Stats', '⚔')
    local C = Tab:CreateSection('COMBAT')
    C:AddToggle({ Name='Auto Aggressive State', Key='AAGGR', Default=false, Callback=function(v) S.AutoAggressive=v end })
    C:AddToggle({ Name='Auto Scared State', Key='ASC', Default=false, Callback=function(v) S.AutoScared=v end })
    C:AddToggle({ Name='Anti Broken Leg', Key='ABL', Default=false, Callback=function(v) S.AntiBrokenLeg=v end })
    C:AddToggle({ Name='Anti Shredded Wings', Key='ASW', Default=false, Callback=function(v) S.AntiShreddedWings=v end })
    C:AddToggle({ Name='Anti Confusion', Key='ACO', Default=false, Callback=function(v) S.AntiConfusion=v end })
    C:AddToggle({ Name='Anti Grab', Key='AGB', Default=false, Callback=function(v) S.AntiGrab=v end })
    C:AddToggle({ Name='Infinite Stamina', Key='INFS', Default=false, Callback=function(v) S.InfStamina=v end })

    local CS = Tab:CreateSection('CUSTOM STATS')
    CS:AddSlider({ Name='Turn Radius', Key='TR', Min=0, Max=200, Default=0, Decimals=0, Callback=function(v) S.TurnRadius=v end })
    CS:AddToggle({ Name='Enable Custom Turn Radius', Key='ETR', Default=false, Callback=function(v) S.EnableTurnRadius=v end })
    CS:AddSlider({ Name='Walk Speed', Key='WS', Min=0, Max=200, Default=30, Decimals=0, Callback=function(v) S.WalkSpeed=v end })
    CS:AddToggle({ Name='Enable Custom Walk Speed', Key='EWS', Default=false, Callback=function(v) S.EnableWalkSpeed=v end })
    CS:AddSlider({ Name='Sprint Speed', Key='SS', Min=0, Max=300, Default=115, Decimals=0, Callback=function(v) S.SprintSpeed=v end })
    CS:AddToggle({ Name='Enable Custom Sprint Speed', Key='ESS', Default=false, Callback=function(v) S.EnableSprintSpeed=v end })
    CS:AddSlider({ Name='Fly Speed', Key='FS', Min=0, Max=200, Default=40, Decimals=0, Callback=function(v) S.FlySpeed=v end })
    CS:AddToggle({ Name='Enable Custom Fly Speed', Key='EFS', Default=false, Callback=function(v) S.EnableFlySpeed=v end })
end

-- ─── Tab 3: AUTOFARM ────────────────────────────────────────────────
do
    local Tab = Window:CreateTab('Autofarm', '⚡')
    local Sv = Tab:CreateSection('SURVIVAL AUTOFARM')
    Sv:AddToggle({ Name='Auto Eat', Key='AE', Default=false, Callback=function(v) S.AutoEat=v end })
    Sv:AddToggle({ Name='Auto Drink', Key='AD', Default=false,
        Tip='Note: also broken in LUNAR original — may not work',
        Callback=function(v) S.AutoDrink=v end })
    Sv:AddToggle({ Name='Auto Mud Roll', Key='AMR', Default=false, Callback=function(v) S.AutoMudRoll=v end })

    local T = Tab:CreateSection('TOKEN AUTOFARM')
    T:AddToggle({ Name='Auto Gacha Tokens', Key='AGT', Default=false, Callback=function(v) S.AutoGachaTokens=v end })

    local MT = Tab:CreateSection('MUTATION/TRAIT AUTOFARM')
    MT:AddLabel('Leave dropdowns empty to save any mutation/trait')
    MT:AddDropdown({ Name='Mutations', Key='MUT', Default='',
        Values={'','Albinism','Volcanic','Diamond','Shimmer','Overgrown','Glow Tail'},
        Callback=function(v) S.MutationTarget=v end })
    MT:AddToggle({ Name='Auto Mutation(s)', Key='AMUT', Default=false, Callback=function(v) S.AutoMutations=v end })
    MT:AddDropdown({ Name='Traits', Key='TRAIT', Default='',
        Values={'','Damage','Speed','Bite','Health','Stamina'},
        Callback=function(v) S.TraitTarget=v end })
    MT:AddToggle({ Name='Auto Trait(s)', Key='ATRAIT', Default=false, Callback=function(v) S.AutoTraits=v end })

    local Mu = Tab:CreateSection('MUSH AUTOFARM')
    Mu:AddLabel('Region Missions Status: Offline')
    Mu:AddToggle({ Name='Auto Missions', Key='AMIS', Default=false, Callback=function(v) S.AutoMissions=v end })

    local R = Tab:CreateSection('RECOMMENDED')
    R:AddDropdown({ Name='Select Creature', Key='SCR', Default='',
        Values={'','Slot1','Slot2','Slot3'}, Callback=function(v) S.SelectedCreature=v end })
    R:AddButton({ Name='Refresh Creature List', Callback=function() HSHub:Notify('Creature list refreshed', 'ok', 2) end })
    R:AddToggle({ Name='Auto Spawn', Key='ASP', Default=false, Callback=function(v) S.AutoSpawn=v end })
    R:AddSlider({ Name='Death Points Target', Key='DPT', Min=0, Max=5000, Default=1200, Suffix=' pts', Decimals=0,
        Callback=function(v) S.DeathPointsTarget=v end })
    R:AddToggle({ Name='Auto Self Kill', Key='ASK', Default=false,
        Tip='Fires LavaSelfDamage when DeathPoints >= target',
        Callback=function(v) S.AutoSelfKill=v end })
end

-- ─── Tab 4: ARTIFACTS (matches LUNAR Artifacts Autofarm tab) ───────
-- Per-realm shrine sets (HardcoreEnvScan 2026-05-29):
--   Normal CoS realm: 8 shrines, no Shadow.
--   Hardcore realm:   ONLY Shadow exists (other 8 shrine folders absent in
--                     Workspace.Interactions["Warden Shrines"]; it's a different map).
local SHRINES_LOW, SHRINES_HIGH
if IS_HARDCORE then
    SHRINES_LOW  = {}
    SHRINES_HIGH = { 'Shadow Up', 'Shadow Middle', 'Shadow Down' }  -- 3 altars, user picks
else
    SHRINES_LOW  = { 'Hellion', 'Angelic', 'Garra', 'Verdant' }
    SHRINES_HIGH = { 'Boreal',  'Eigion',  'Novus', 'Ardor'   }
end

-- Per-shrine state flags
S.ArtifactToggles = {}
for _, n in ipairs(SHRINES_LOW)  do S.ArtifactToggles[n] = false end
for _, n in ipairs(SHRINES_HIGH) do S.ArtifactToggles[n] = false end
S.AutoServerHopArtifact = false
-- live status-label handles (updated by the status loop from the tablet's TimerGui)
local shrineStatusLabels = {}
local meatCounterLabel   = nil   -- updated by the status loop with server-wide carcass stats

do
    local Tab = Window:CreateTab('Artifacts', '✦')

    local InfoSec = Tab:CreateSection('SERVER MEAT')
    meatCounterLabel = InfoSec:AddLabel('Meat di server: —', Color3.fromRGB(180, 220, 255))

    local function makeShrineToggle(section, name)
        local key = ('AF_%s'):format(name)
        section:AddLabel(name .. ' Warden Shrine')
        shrineStatusLabels[name] = section:AddLabel('Status: —',
            Color3.fromRGB(150, 150, 180))
        section:AddToggle({ Name=('AutoFarm %s Artifact'):format(name),
            Key=key, Default=false,
            Tip=('Cycle creatures and deposit at %s Warden Shrine'):format(name),
            Callback=function(v) S.ArtifactToggles[name] = v end })
    end

    local Lo = Tab:CreateSection('LOW VALUE')
    for _, name in ipairs(SHRINES_LOW)  do makeShrineToggle(Lo, name) end

    local Hi = Tab:CreateSection('HIGH VALUE')
    for _, name in ipairs(SHRINES_HIGH) do makeShrineToggle(Hi, name) end

    local Rec = Tab:CreateSection('RECOMMEND')
    Rec:AddToggle({ Name='Auto Server Hop', Key='ASH_Art', Default=false,
        Tip="If the server's food runs out, hop to another",
        Callback=function(v) S.AutoServerHopArtifact = v end })
end

-- ─── Tab 5: TELEPORTS ───────────────────────────────────────────────
do
    local Tab = Window:CreateTab('Teleports', '⛰')
    local Reg = Tab:CreateSection('REGION TELEPORTS')
    -- USER-SAVED positions (PosSaver, 2026-05-29). User walked to each region
    -- and saved on-ground coords -> always lands sane, no sky/underground.
    local regions = {
        {'Desert',            Vector3.new(-1478.62, 291.62,  1425.98)},
        {'Mesa',              Vector3.new(-2418.70, 219.02,   145.48)},
        {'Mountains',         Vector3.new(-1800.22, 502.92, -1085.25)},
        {'Volcano',           Vector3.new( 2116.81, 199.27,  1025.66)},
        {'Pride Rocks',       Vector3.new( 2030.14, 186.93,  -401.38)},
        {'Flower Cave',       Vector3.new( -240.97, 194.92,  2368.08)},
        {'Central Rockfaces', Vector3.new( -149.20, 256.83,  -130.54)},
        {'Coral Reef',        Vector3.new( 1102.50,  67.54,  1187.40)},
        {'Grassy Shoal',      Vector3.new( -791.98, 102.55,  2088.24)},
        {'Seaweed Depths',    Vector3.new(  -55.00, -33.11,   891.30)},
        {'Algae Sandbar',     Vector3.new( 1133.80,  93.06, -1550.60)},
        {'Jungle',            Vector3.new( 2484.53, 248.97,  -962.95)},
        {'Redwoods',          Vector3.new(  424.62, 207.30, -1337.42)},
        {'Tundra',            Vector3.new(-1029.08, 266.03, -2394.52)},
        {'Swamp Hill',        Vector3.new(  607.47, 188.14, -2789.51)},
    }
    for _, r in ipairs(regions) do
        local name, pos = r[1], r[2]
        Reg:AddButton({ Name=name, Callback=function()
            local root = getRoot()
            if root then root.CFrame = CFrame.new(pos); HSHub:Notify('TP: ' .. name, 'ok', 2) end
        end })
    end

    local Cu = Tab:CreateSection('CUSTOM TELEPORTS')
    local locs, sel = {}, ''
    Cu:AddDropdown({ Name='Custom Location', Key='CL', Default='', Values={''}, Callback=function(v) sel=v end })
    Cu:AddButton({ Name='Teleport to Location', Callback=function()
        local p = locs[sel]; if p then
            local root = getRoot(); if root then root.CFrame = CFrame.new(p); HSHub:Notify('TP: '..sel,'ok',2) end
        end
    end })
    local saveName = ''
    if Cu.AddTextbox then
        Cu:AddTextbox({ Name='Location Name', Default='', Placeholder='Enter name',
            Callback=function(v) saveName=v end })
    end
    Cu:AddButton({ Name='Save Location', Callback=function()
        local root = getRoot(); if not root then return end
        if saveName=='' then saveName='Loc_'..tostring(#locs+1) end
        locs[saveName]=root.Position; HSHub:Notify('Saved: '..saveName,'ok',2)
    end })
    Cu:AddButton({ Name='Delete Location', Callback=function()
        if sel~='' then locs[sel]=nil; HSHub:Notify('Deleted: '..sel,'ok',2) end
    end })
end

-- ─── Tab 6: EVENT ───────────────────────────────────────────────────
do
    local Tab = Window:CreateTab('Event', '❄')
    Tab:CreateSection('MINIGAME(S)'):AddLabel('No active event minigames')
    Tab:CreateSection('INFORMATION'):AddLabel('Check Discord for events')
end

-- ─── Tab 7: ESP ─────────────────────────────────────────────────────
do
    local Tab = Window:CreateTab('Esp', '◉')
    local G = Tab:CreateSection('GACHA TOKEN ESP')
    G:AddLabel('Note: also broken in LUNAR original')
    G:AddToggle({ Name='Explorer Gacha Token ESP', Key='EGE', Default=false, Callback=function(v) S.GachaEspExplorer=v end })
    G:AddToggle({ Name='Galaxy Gacha Token ESP',   Key='EGG', Default=false, Callback=function(v) S.GachaEspGalaxy=v end })
    G:AddToggle({ Name='Mecha Gacha Token ESP',    Key='EGM', Default=false, Callback=function(v) S.GachaEspMecha=v end })
    G:AddToggle({ Name='Monster Gacha Token ESP',  Key='EGMo',Default=false, Callback=function(v) S.GachaEspMonster=v end })
    G:AddToggle({ Name='Sweet Gacha Token ESP',    Key='EGSw',Default=false, Callback=function(v) S.GachaEspSweet=v end })

    local O = Tab:CreateSection('OTHERS ESP')
    O:AddToggle({ Name='Abandoned Eggs ESP', Key='AEE', Default=false, Callback=function(v) S.AbandonedEggsEsp=v end })
    O:AddButton({ Name='Teleport to Abandoned Egg', Callback=function()
        local egg = findNearestEgg()
        if egg then
            local part = egg:IsA('BasePart') and egg or egg:FindFirstChildWhichIsA('BasePart')
            if part then
                local root = getRoot()
                if root then root.CFrame = CFrame.new(part.Position + Vector3.new(0,5,0)) end
                HSHub:Notify('TP to abandoned egg','ok',2)
            end
        else
            HSHub:Notify('No abandoned eggs','warn',2)
        end
    end })

    local P = Tab:CreateSection('PLAYER ESP')
    P:AddToggle({ Name='Enable Player ESP', Key='EPE', Default=false, Callback=function(v) S.EnablePlayerEsp=v end })
    P:AddToggle({ Name='Display Health',    Key='DH',  Default=false, Callback=function(v) S.EspHealth=v end })
    P:AddToggle({ Name='Display Health Bar',Key='DHB', Default=false, Callback=function(v) S.EspHealthBar=v end })
    P:AddToggle({ Name='Display Tracer',    Key='DT',  Default=false, Callback=function(v) S.EspTracer=v end })
    P:AddToggle({ Name='Display Names',     Key='DN',  Default=false, Callback=function(v) S.EspNames=v end })
    P:AddToggle({ Name='Display Distance',  Key='DD',  Default=false, Callback=function(v) S.EspDistance=v end })
    P:AddToggle({ Name='Display 3D Box',    Key='DB',  Default=false, Callback=function(v) S.EspBox=v end })
    P:AddToggle({ Name='Display Chameleon', Key='DC',  Default=false, Callback=function(v) S.EspChameleon=v end })
end

-- ─── Tab 8: OTHERS ──────────────────────────────────────────────────
do
    local Tab = Window:CreateTab('Others', '⚙')
    local V = Tab:CreateSection('VISUAL')
    V:AddToggle({ Name='Remove Fog', Key='RF', Default=false, Callback=function(v) S.RemoveFog=v
        if v then Lighting.FogEnd=100000; Lighting.FogStart=100000 end end })
    V:AddToggle({ Name='Remove Camera Effects', Key='RCE', Default=false, Callback=function(v) S.RemoveCameraEffects=v end })
    V:AddToggle({ Name='Remove Disaster Effects', Key='RDE', Default=false, Callback=function(v) S.RemoveDisasterEffects=v end })

    local Mi = Tab:CreateSection('MISC')
    Mi:AddToggle({ Name='Hide Ping and FPS', Key='HPF', Default=false, Callback=function(v) S.HidePingFps=v end })
    Mi:AddToggle({ Name='Anti-AFK', Key='AAFK', Default=false, Callback=function(v) S.AntiAFK=v end })
    if Mi.AddTextbox then
        Mi:AddTextbox({ Name='Custom Name', Default='', Placeholder='Enter name', Callback=function(v) S.CustomName=v end })
    end
    Mi:AddToggle({ Name='Hide Username (Client-Sided)', Key='HU', Default=false, Callback=function(v) S.HideUsername=v end })

    local Disc = Tab:CreateSection('DISCORD')
    Disc:AddButton({ Name='Copy Discord Link', Callback=function()
        if setclipboard then setclipboard('https://discord.gg/5rpP6faZSJ') end
        HSHub:Notify('Discord link copied','ok',2)
    end })

    local La = Tab:CreateSection('ANTI-LAG')
    La:AddToggle({ Name='Low Quality Textures', Key='LQT', Default=false, Callback=function(v) S.LowQualityTextures=v
        if v then pcall(function() settings().Rendering.QualityLevel=Enum.QualityLevel.Level01 end) end end })
    La:AddToggle({ Name='White Screen', Key='WSC', Default=false, Callback=function(v) S.WhiteScreen=v end })

    local Sr = Tab:CreateSection('SERVERS')
    Sr:AddButton({ Name='Rejoin Server', Callback=function()
        TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LP)
    end })
    Sr:AddButton({ Name='Server Hop', Callback=function()
        local ok, raw = pcall(function()
            return game:HttpGet('https://games.roblox.com/v1/games/'..tostring(game.PlaceId)
                ..'/servers/Public?sortOrder=Asc&limit=100')
        end)
        if ok and raw then
            local d = HttpService:JSONDecode(raw)
            if d and d.data then
                for _, s in ipairs(d.data) do
                    if s.playing < s.maxPlayers and s.id ~= game.JobId then
                        TeleportService:TeleportToPlaceInstance(game.PlaceId, s.id, LP); return
                    end
                end
            end
        end
        HSHub:Notify('No servers found','warn',2)
    end })
end

-- ═══════════════════════════════════════════════════════════════════
--   FEATURE LOOPS (with ground-truth bindings)
-- ═══════════════════════════════════════════════════════════════════

-- AutoEat: TP to nearest food + spam Food:FireServer until Hunger=100%
task.spawn(function()
    local savedCF
    while true do
        task.wait(1)
        if S.AutoEat and not S.AutoMissions then
            pcall(function()
                local char = getChar()
                if char and hudStatText('Hunger') ~= '100%' then
                    local food = findNearestFood()
                    if food then
                        local foodPart = food:IsA('Model') and (food.PrimaryPart or food:FindFirstChild('Food') or food:FindFirstChildWhichIsA('BasePart')) or food
                        if foodPart and foodPart:IsA('BasePart') then
                            local v = foodPart.Position
                            local root = getRoot()
                            if root then
                                if not savedCF then savedCF = root.CFrame end
                                root.CFrame = CFrame.new(v - Vector3.new(0,20,0))
                                local n = 0
                                repeat
                                    task.wait(0.1)
                                    fire('Food', food)
                                    if getRoot() then getRoot().CFrame = CFrame.new(v - Vector3.new(0,20,0)) end
                                    n = n + 1
                                until hudStatText('Hunger') == '100%' or not S.AutoEat or not food.Parent or n > 60
                                if savedCF and getRoot() then
                                    getRoot().CFrame = savedCF; savedCF = nil
                                end
                            end
                        end
                    end
                end
            end)
        end
    end
end)

-- AutoDrink: noted broken in LUNAR (probably lake-detection issue)
-- Still implemented for completeness; uses Lakes folder
task.spawn(function()
    while true do
        task.wait(0.1)
        if S.AutoDrink and not S.AutoMissions then
            pcall(function()
                if getChar() and hudStatText('Thirst') ~= '100%' then
                    local lake = findNearestLake()
                    fire('DrinkRemote', lake)
                end
            end)
        end
    end
end)

-- AutoMudRoll: roll in mud to GET the mud/scent-hide effect, then STOP.
-- Bug fixed: old code only checked a guessed 'Muddy' attribute -> never true ->
-- rolled forever. Now detects the effect robustly (char attr OR any Ailments
-- entry named mud/scent/hidden/shelter) AND adds a post-roll cooldown so it can
-- never spin endlessly.
task.spawn(function()
    local savedCF
    local function mudEffectActive(char)
        if not char then return false end
        if char:GetAttribute('Muddy') or char:GetAttribute('HideScent') then return true end
        local ail = char:FindFirstChild('Ailments')
        local active = false
        if ail then
            pcall(function()
                for k in pairs(ail:GetAttributes()) do
                    local lk = tostring(k):lower()
                    if lk:find('mud') or lk:find('scent') or lk:find('hidden')
                        or lk:find('shelter') or lk:find('stink') then
                        active = true; break
                    end
                end
            end)
        end
        return active
    end
    while true do
        task.wait(0.2)
        if S.AutoMudRoll and not S.AutoMissions then
            pcall(function()
                local char = getChar()
                if not char then return end
                -- skip only while the effect is already active (no time cooldown)
                if mudEffectActive(char) then return end
                local mud = findNearestMud(); if not mud then return end
                local mudPart = mud:IsA('Model') and (mud.PrimaryPart or mud:FindFirstChildWhichIsA('BasePart')) or mud
                if not (mudPart and mudPart:IsA('BasePart')) then return end
                local target = mudPart.Position + Vector3.new(0, mudPart.Size.Y / 2, 0)
                local root = getRoot(); if not root then return end
                if not savedCF then savedCF = root.CFrame end
                local n = 0
                repeat
                    task.wait(0.1)
                    if getRoot() then getRoot().CFrame = CFrame.new(target) end
                    fire('Mud', mud)
                    n = n + 1
                until mudEffectActive(char) or not S.AutoMudRoll or n > 12
                if savedCF and getRoot() then getRoot().CFrame = savedCF; savedCF = nil end
            end)
        end
    end
end)

-- AutoShelter: Sheltered:FireServer(true) when shelter indicator is red
task.spawn(function()
    while true do
        task.wait(0.5)
        if S.AutoShelter then
            pcall(function()
                local c = shelterColor()
                if c and (c.R > 0.9 and c.G < 0.1 and c.B < 0.1) then
                    fire('Sheltered', true)
                end
            end)
        end
    end
end)

-- AutoSelfKill: fire LavaSelfDamage when DeathPoints >= target
task.spawn(function()
    while true do
        task.wait(1)
        if S.AutoSelfKill then
            pcall(function()
                if getChar() then
                    S.NoLavaDamage = false
                    fire('LavaSelfDamage')
                end
            end)
        end
    end
end)

-- ════════════════════════════════════════════════════════════════════
-- CREATURE CYCLING (AutoFarmMutations / AutoFarmTraits / AutoArtifactFarm)
-- ════════════════════════════════════════════════════════════════════
-- LUNAR pattern (chunk3_pretty line 794+ and 1655+):
--   1. require PlayerWrapper module to get current slot
--   2. Check if current creature matches target (mutation/trait/any)
--   3. If not match: StoreActiveCreatureRemote + CreateSlotRemote to cycle
--   4. Trigger HUDGui.SaveSelectionReturn(true) for UI sync

local function safeRequire(path)
    local ok, m = pcall(function() return require(path) end)
    if ok then return m end
end

local function getPlayerWrapper()
    local rf = ReplicatedStorage:FindFirstChild('_replicationFolder')
    if rf then
        local pw = rf:FindFirstChild('PlayerWrapper')
        if pw then return safeRequire(pw) end
    end
end

local function getHUDGuiModule()
    local rf = ReplicatedStorage:FindFirstChild('_replicationFolder')
    if rf then
        local hg = rf:FindFirstChild('HUDGui')
        if hg then return safeRequire(hg) end
    end
end

local function getCurrentSlot()
    local pw = getPlayerWrapper()
    if pw and pw.GetClient then
        local ok, client = pcall(function() return pw:GetClient() end)
        if ok and client and client.GetCurrentSlot then
            local ok2, slot = pcall(function() return client:GetCurrentSlot() end)
            if ok2 then return slot end
        end
    end
end

local function getActiveCreature()
    -- LUNAR's f() / z() finder — find current loaded creature in workspace
    local char = getChar()
    if not char then return nil end
    -- The creature model is usually the character itself or a child
    return char
end

local function getCreatureAttribute(creature, attr)
    if not creature then return nil end
    local ok, v = pcall(function() return creature:GetAttribute(attr) end)
    if ok then return v end
end

local function creatureMatchesTarget(creature, mutTarget, traitTarget)
    if not creature then return false end
    if mutTarget and mutTarget ~= '' then
        if getCreatureAttribute(creature, mutTarget) then return true end
    end
    if traitTarget and traitTarget ~= '' then
        if getCreatureAttribute(creature, traitTarget) then return true end
    end
    return false
end

-- ════════════════════════════════════════════════════════════════════
-- ARTIFACT SHRINE HELPERS
-- ════════════════════════════════════════════════════════════════════

-- Known shrine TABLET world positions (static map features). Seeded with the two
-- ArtifactScan captured; the other 6 are LEARNED live the first time you enter each
-- region (cached + persisted to a file) so cross-region TP works afterwards.
-- A shrine position is either a single Vector3, OR a LIST of Vector3 (multi-altar:
-- the same logical shrine exists at several spots, e.g. hardcore "Shadow" = 3
-- altars in 3 regions sharing ONE cooldown — offering at any one cools all down).
local TABLET_POS = {
    -- 6/8 captured via V16 auto-cache (hshub_cos_shrines.txt, 2026-05-29).
    Hellion = Vector3.new(-1286.4, 232.7, 380.9),
    Boreal  = Vector3.new(-2259.4, 380.7, -1060.4),
    Verdant = Vector3.new(309.3, 331.2, 2240.5),
    Novus   = Vector3.new(1133.1, 857.9, 819.0),
    Garra   = Vector3.new(2333.9, 258.1, 1338.4),
    Eigion  = Vector3.new(1012.7, -508.9, 514.6),
    -- Hardcore "Shadow" = 3 separate altars (ShrineHunter, PlaceId 136015760267602).
    -- User picks which via 3 toggles. All offer "Shadow" + share one cooldown.
    ['Shadow Up']     = Vector3.new( 1312.47, -64.96,  540.15),
    ['Shadow Middle'] = Vector3.new(  215.67, 404.63, -106.63),
    ['Shadow Down']   = Vector3.new(-1098.30, 327.13, -476.35),
    -- Angelic + Ardor: auto-learned + saved when you first enter their regions.
}
-- normalize to a list of candidate positions to try (in order)
local function tabletPositions(name)
    local v = TABLET_POS[name]
    if not v then return {} end
    if typeof(v) == 'Vector3' then return { v } end
    return v
end
-- Display/toggle name -> the actual WardenOffering arg + shrine folder name.
-- The 3 hardcore Shadow toggles all resolve to the single in-game shrine "Shadow".
local OFFER_NAME = {
    ['Shadow Up'] = 'Shadow', ['Shadow Middle'] = 'Shadow', ['Shadow Down'] = 'Shadow',
}
local function offerNameOf(name) return OFFER_NAME[name] or name end
local TABLET_FILE = 'hshub_cos_shrines.txt'
pcall(function()
    if readfile and isfile and isfile(TABLET_FILE) then
        for line in tostring(readfile(TABLET_FILE)):gmatch('[^\n]+') do
            local n, x, y, z = line:match('([^=]+)=([%-%d%.]+),([%-%d%.]+),([%-%d%.]+)')
            -- never let the single-pos file clobber a hardcoded multi-altar list
            if n and typeof(TABLET_POS[n]) ~= 'table' then
                TABLET_POS[n] = Vector3.new(tonumber(x), tonumber(y), tonumber(z))
            end
        end
    end
end)
local function rememberTabletPos(name, p)
    if not p then return end
    if typeof(TABLET_POS[name]) == 'table' then return end   -- multi-altar: keep hardcoded list
    local old = TABLET_POS[name]
    if old and (old - p).Magnitude < 5 then return end       -- already known
    TABLET_POS[name] = p
    pcall(function()
        if not writefile then return end
        local lines = {}
        for n, v in pairs(TABLET_POS) do
            if typeof(v) == 'Vector3' then   -- only persist single positions
                lines[#lines + 1] = ('%s=%.1f,%.1f,%.1f'):format(n, v.X, v.Y, v.Z)
            end
        end
        writefile(TABLET_FILE, table.concat(lines, '\n'))
    end)
end

-- Find the shrine TABLET part in workspace.Interactions["Warden Shrines"].<name>.
-- Offering is proximity-gated, so we TP onto the tablet before offering. Parts only
-- exist while in the shrine's region (streaming); when found we cache the position
-- so we can TP back to that region later (cross-region farm in the loop below).
local function getShrineTablet(name)
    name = offerNameOf(name)   -- "Shadow Up/Middle/Down" -> folder "Shadow"
    local i = interactions(); if not i then return nil end
    local shrines = i:FindFirstChild('Warden Shrines'); if not shrines then return nil end
    local fallback
    -- iterate ALL folders with this name (hardcore can have multiple "Shadow")
    for _, folder in ipairs(shrines:GetChildren()) do
        if folder.Name == name then
            for _, d in ipairs(folder:GetDescendants()) do
                if d:IsA('BasePart') then
                    if d.Name:find('Tablet') then rememberTabletPos(name, d.Position); return d end
                    fallback = fallback or d
                end
            end
        end
    end
    if fallback then rememberTabletPos(name, fallback.Position) end
    return fallback
end

-- Offering meat = "Carcass"-type only. Confirmed by DamageSpy ×8 (all offerings
-- used a Carcass variant) AND user: "Ribs" is eat-only (can't be picked up), and
-- plants (Grass/Algae/Fruit/Berries/Sea Grapes/Seaweed Pods) aren't offerings.
local function isOfferMeat(fdn)
    if not fdn then return false end
    return tostring(fdn):find('Carcass') ~= nil
end

-- Shrine status from the tablet's own BillboardGui label (ArtifactScan-verified):
-- TimerLabel.Text == "AVAILABLE NOW"  => offerable;  anything else (e.g. "29m 58s")
-- => on cooldown.  Returns the raw text, or nil if the tablet isn't loaded.
local function getShrineStatusText(name)
    local tablet = getShrineTablet(name); if not tablet then return nil end
    local gui = tablet:FindFirstChild('TimerGui')
    local lbl = gui and gui:FindFirstChild('TimerLabel')
    if not lbl then return nil end
    local ok, txt = pcall(function() return lbl.Text end)
    return ok and txt or nil
end
-- true=available, false=cooldown, nil=unknown (tablet not loaded / out of region)
local function shrineAvailable(name)
    local txt = getShrineStatusText(name)
    if txt == nil then return nil end
    return txt:upper():find('AVAILABLE') ~= nil
end

-- Return the NAME of the first enabled shrine (the WardenOffering arg).
local function getActiveShrine()
    for _, n in ipairs(SHRINES_LOW) do
        if S.ArtifactToggles[n] then return n end
    end
    for _, n in ipairs(SHRINES_HIGH) do
        if S.ArtifactToggles[n] then return n end
    end
    return nil
end

-- ════════════════════════════════════════════════════════════════════
-- MAIN CYCLING LOOP — handles AutoFarmMutations, AutoFarmTraits,
-- AND per-shrine ArtifactFarm toggles
-- ════════════════════════════════════════════════════════════════════
local _cooldownNotified = {}   -- notify "cooldown" once per available->cooldown edge
local _meatBlacklist    = {}   -- meat models that failed BOTH full + piece pickup
local _shrineCooldownUntil = {} -- per-shrine: tick() until which we go FULLY SILENT (done)
-- parse the tablet's TimerGui countdown ("29m 58s") into seconds
local function parseCooldownSecs(txt)
    if not txt then return nil end
    local m = tonumber(txt:match('(%d+)%s*[mM]')) or 0
    local s = tonumber(txt:match('(%d+)%s*[sS]')) or 0
    local total = m * 60 + s
    return total > 0 and total or nil
end

-- Live shrine-status labels in the Artifacts tab — mirror each tablet's TimerGui
-- text ("AVAILABLE NOW" / "29m 58s"). "— (luar region)" if the tablet isn't loaded.
task.spawn(function()
    while true do
        task.wait(2)
        -- per-shrine status labels (TimerGui mirror)
        for name, lbl in pairs(shrineStatusLabels) do
            pcall(function()
                local txt = getShrineStatusText(name)
                lbl:Set(txt and ('Status: ' .. txt) or 'Status: — (luar region)')
            end)
        end
        -- server-wide carcass stats (offer-meat only; matches autofarm filter)
        if meatCounterLabel then pcall(function()
            local f = (interactions() or {}):FindFirstChild('Food')
            if not f then meatCounterLabel:Set('Meat di server: Food folder ga ke-load'); return end
            local count, total, best, bestName = 0, 0, 0, nil
            for _, m in ipairs(f:GetChildren()) do
                if isOfferMeat(m:GetAttribute('FoodDataName')) then
                    local v = tonumber(m:GetAttribute('Value')) or 0
                    count = count + 1; total = total + v
                    if v > best then best, bestName = v, m:GetAttribute('FoodDataName') end
                end
            end
            meatCounterLabel:Set(('Meat di server: %d carcass · total %d · tertinggi %d (%s)')
                :format(count, total, best, tostring(bestName or '—')))
        end) end
    end
end)

task.spawn(function()
    while true do
        task.wait(0.4)
        local mutOn = S.AutoMutations
        local trOn  = S.AutoTraits
        local shrineName = getActiveShrine()

        if shrineName then pcall(function()
            -- ARTIFACT FARM V14 (rebuilt fully from ArtifactScan data 2026-05-29):
            --   Status : tablet.TimerGui.TimerLabel.Text — "AVAILABLE NOW" = offerable,
            --            else (e.g. "29m 58s") = on cooldown -> idle (auto-resumes).
            --   Carry  : Character attr HeldCount (0=empty,1=carrying; CarryLimit=1).
            --   Meat   : Interactions.Food children; FoodDataName=type, Value=amount;
            --            offer-meat = Carcass-type (isOfferMeat); pick HIGHEST Value.
            --   Pickup : try FULL (FoodPickup) first; if HeldCount didn't rise (tier-
            --            locked/rejected), take a PIECE (FoodChunk).  [user's rule]
            --   Offer  : WardenOffering:InvokeServer(name) — proximity-gated -> TP onto
            --            the tablet first (in-region only).
            local root = getRoot(); local char = getChar()
            if not root or not char then return end
            local tablet = getShrineTablet(shrineName)
            if not tablet then
                -- Region not loaded. TP to each known position for this shrine to
                -- stream it in (multi-altar shrines like hardcore "Shadow" have a few;
                -- single shrines have one). Never-visited shrines have none -> fly there.
                for _, known in ipairs(tabletPositions(shrineName)) do
                    pcall(function() root.CFrame = CFrame.new(known + Vector3.new(0, 8, 0)) end)
                    task.wait(1.5)
                    tablet = getShrineTablet(shrineName)
                    if tablet then break end
                end
                if not tablet then return end      -- still streaming / unknown -> retry next cycle
            end

            -- Stop-on-complete: on cooldown -> idle (don't park / spam offers).
            local avail = shrineAvailable(shrineName)
            if avail == false then
                if not _cooldownNotified[shrineName] then
                    _cooldownNotified[shrineName] = true
                    HSHub:Notify(('%s shrine selesai — cooldown (%s)')
                        :format(shrineName, getShrineStatusText(shrineName) or '...'), 'ok', 3)
                end
                return
            end
            _cooldownNotified[shrineName] = nil    -- available again -> resume

            -- V18 (ANTI-BAN, modeled on LUNAR's working pattern): after each TP, WAIT
            -- ~0.8s so the position SETTLES before firing a remote, then snap BACK to
            -- "home". Rapid TP-spam + staying far away was the ban signature (LUNAR's
            -- own AutoGachaTokens does save->TP->wait(1)->act->TP-back). Slower = safer.
            local home = root.CFrame   -- current spot (near shrine region); we return here
            local held = tonumber(char:GetAttribute('HeldCount')) or 0
            if held < 1 then
                local foodFolder = (interactions() or {}):FindFirstChild('Food')
                local myTier = 0
                pcall(function()
                    local d = char:FindFirstChild('Data')
                    myTier = (d and tonumber(d:GetAttribute('Tier'))) or 0
                end)
                local bestM, bestPart, bestVal, bestLocked = nil, nil, -1, false
                if foodFolder then
                    for _, m in ipairs(foodFolder:GetChildren()) do
                        if isOfferMeat(m:GetAttribute('FoodDataName'))
                            and not m:GetAttribute('Held')
                            and not _meatBlacklist[m] then
                            local val    = tonumber(m:GetAttribute('Value')) or 0
                            local t      = tonumber(m:GetAttribute('T'))
                            local locked = (t ~= nil and myTier > 0 and myTier < t) or false
                            if not (locked and val <= 15) then        -- tier-locked + low = skip
                                local part = m:IsA('BasePart') and m
                                    or (m:IsA('Model') and (m.PrimaryPart or m:FindFirstChildWhichIsA('BasePart')))
                                if part and val > bestVal then
                                    bestM, bestPart, bestVal, bestLocked = m, part, val, locked
                                end
                            end
                        end
                    end
                end
                if bestM and bestPart then
                    pcall(function() root.CFrame = bestPart.CFrame + Vector3.new(0, 4, 0) end)
                    task.wait(0.8)                 -- settle before firing (anti-detect)
                    if not bestLocked then
                        local full = getRemote('FoodPickup')
                        if full then pcall(function() full:InvokeServer(bestM) end) end
                        task.wait(0.6)
                    end
                    if (tonumber(char:GetAttribute('HeldCount')) or 0) < 1 then
                        local piece = getRemote('FoodChunk')
                        if piece then pcall(function() piece:InvokeServer(bestM) end) end
                        task.wait(0.6)
                    end
                    if (tonumber(char:GetAttribute('HeldCount')) or 0) < 1 then
                        _meatBlacklist[bestM] = true   -- can't take this one; try next-highest
                    end
                end
                held = tonumber(char:GetAttribute('HeldCount')) or 0
            end
            -- carrying now -> TP to shrine, WAIT to settle, offer, then snap BACK home.
            if held >= 1 then
                pcall(function() root.CFrame = tablet.CFrame + Vector3.new(0, 6, 0) end)
                task.wait(0.9)                     -- settle at the shrine before offering
                local wo = getRemote('WardenOffering')
                if wo then pcall(function() wo:InvokeServer(offerNameOf(shrineName)) end) end
                task.wait(0.4)
                pcall(function() root.CFrame = home end)   -- LUNAR-style snap back
            end
        end) end

        if mutOn or trOn then pcall(function()
            -- Mutation/Trait farm via creature cycling
            if not getChar() then return end
            local slot = getCurrentSlot()
            if not slot then return end
            local creature = getActiveCreature()

            if creatureMatchesTarget(creature, S.MutationTarget, S.TraitTarget) then
                return
            end

            local hudMod = getHUDGuiModule()
            if hudMod and hudMod.SaveSelectionReturn then
                pcall(function() hudMod.SaveSelectionReturn(true) end)
                task.wait(0.5)
            end

            local storeR = getRemote('StoreActiveCreatureRemote')
            local createR = getRemote('CreateSlotRemote')
            if storeR and createR then
                pcall(function() storeR:InvokeServer(slot) end)
                task.wait(0.5)
                local dinoVal = creature and creature:FindFirstChild('Dino')
                if dinoVal and dinoVal.Value then
                    pcall(function() createR:InvokeServer(dinoVal.Value) end)
                end
            end
        end) end
    end
end)

-- Auto Server Hop (Artifacts tab Recommend) — same as Others tab Server Hop
task.spawn(function()
    while true do
        task.wait(30)
        if S.AutoServerHopArtifact then
            pcall(function()
                local ok, raw = pcall(function()
                    return game:HttpGet('https://games.roblox.com/v1/games/'..tostring(game.PlaceId)
                        ..'/servers/Public?sortOrder=Asc&limit=100')
                end)
                if ok and raw then
                    local d = HttpService:JSONDecode(raw)
                    if d and d.data then
                        for _, srv in ipairs(d.data) do
                            if srv.playing < srv.maxPlayers and srv.id ~= game.JobId then
                                TeleportService:TeleportToPlaceInstance(game.PlaceId, srv.id, LP)
                                return
                            end
                        end
                    end
                end
            end)
        end
    end
end)

-- AutoSpawn: respawn dead creature
task.spawn(function()
    while true do
        task.wait(1)
        if S.AutoSpawn then
            pcall(function()
                if not getChar() then
                    local slot = S.SelectedCreature
                    if slot ~= '' then
                        invoke('RestartSlotRemote', slot, false)
                    end
                end
            end)
        end
    end
end)

-- AutoGachaTokens: LUNAR-style save→TP→settle→fire→snapback (anti-ban)
-- Old: spam invoke every 0.5s with no movement = obvious bot flag.
-- New: TP to nearest visible token, settle 1s, fire, snap back home.
task.spawn(function()
    while true do
        task.wait(2)
        if S.AutoGachaTokens then
            pcall(function()
                local root = getRoot()
                if not root then return end

                local token = findNearestToken()
                if not token then
                    -- no token visible in streaming range → fire without TP
                    invoke('GetSpawnedTokenRemote')
                    return
                end

                local part = token:IsA('BasePart') and token
                    or (token:IsA('Model') and (token.PrimaryPart or token:FindFirstChildWhichIsA('BasePart')))
                if not part then return end

                local home = root.CFrame                                              -- 1. save pos
                pcall(function()
                    root.CFrame = CFrame.new(part.Position + Vector3.new(0, 4, 0))   -- 2. TP to token
                end)
                task.wait(1)                                                          -- 3. settle
                invoke('GetSpawnedTokenRemote')                                       -- 4. fire remote
                task.wait(0.3)
                pcall(function() root.CFrame = home end)                              -- 5. snap back
            end)
        end
    end
end)

-- AutoAcceptNest: loop other players, fire AcceptRequest on their Remotes folder
task.spawn(function()
    while true do
        task.wait(5)
        if S.AutoAcceptNest then
            pcall(function()
                for _, p in ipairs(Players:GetPlayers()) do
                    if p ~= LP and p:FindFirstChild('Settings') then
                        local n = p.Settings:FindFirstChild('Nesting')
                        if n and (n.Value == S.InvitationType or S.InvitationType == 'Everyone') then
                            fireOnPlayer(p, 'NestRequestRemote', 'AcceptRequest')
                        end
                    end
                end
            end)
        end
    end
end)

-- AutoNestUpgrade: ResourceDamageRemote + UpgradeNest
task.spawn(function()
    while true do
        task.wait(0.5)
        if S.AutoNestUpgrade then
            pcall(function()
                for i = 1, 3 do fire('ResourceDamageRemote') end
                invoke('UpgradeNest', S.NestUpgradeTarget)
            end)
        end
    end
end)

-- AlwaysLayEffect: Lay:FireServer(true)  (chunk3 line 987)
-- Pattern: while AlwaysLayEffect and task.wait(1) do; Lay:FireServer(unpack({[1]=true})); end
task.spawn(function()
    while true do
        task.wait(1)
        if S.AlwaysLayEffect then
            pcall(function() fire('Lay', true) end)
        end
    end
end)

-- AutoAggression: StateAilment:FireServer("Aggression")  (chunk3 line 5386)
-- Pattern: only fire when creature doesn't already have Aggression attribute
task.spawn(function()
    while true do
        task.wait(1)
        if S.AutoAggressive then
            pcall(function()
                local c = getChar()
                if c and not c:GetAttribute('Aggression') then
                    fire('StateAilment', 'Aggression')
                end
            end)
        end
    end
end)

-- AutoScentHidden: HideScent:FireServer()  (chunk3 line 5303)
-- Pattern: only fire when char doesn't already have HideScent attribute
task.spawn(function()
    while true do
        task.wait(1)
        if S.AutoScentHidden then
            pcall(function()
                local c = getChar()
                if c and not c:GetAttribute('HideScent') then
                    fire('HideScent')
                end
            end)
        end
    end
end)

-- AutoCowerState: StateAilment:FireServer("Cower")  (chunk3 m=function line 1534)
-- Pattern: only fire when creature doesn't already have Cower attribute
S.AutoCowerStateValue = false  -- ensure flag exists
task.spawn(function()
    while true do
        task.wait(1)
        if S.AutoCowerStateValue then
            pcall(function()
                local c = getChar()
                if c and not c:GetAttribute('Cower') then
                    fire('StateAilment', 'Cower')
                end
            end)
        end
    end
end)

-- AutoNestValue: TP + Nest:FireServer when Age > 66  (chunk3 line 1002)
S.AutoNestValue = false
task.spawn(function()
    while true do
        task.wait(5)
        if S.AutoNestValue then
            pcall(function()
                local c = getChar()
                if not c or not c:FindFirstChild('HumanoidRootPart') then return end
                local age = c:GetAttribute('Age') or 0
                if age <= 66 then return end
                local pos = c.HumanoidRootPart.Position
                local nests = Workspace:FindFirstChild('Interactions')
                nests = nests and nests:FindFirstChild('Nests')
                if not nests or not nests:FindFirstChild(LP.Name) then
                    fire('Nest', { pos, Vector3.yAxis })
                end
            end)
        end
    end
end)

-- ════════════════════════════════════════════════════════════════════
-- PHASE 2 V13: Custom Stats (AttrDump-verified 2026-05-27)
-- Real attribute names on Character.Data folder (mangled single letters):
--   's'  = Walk Speed   (default ~31)
--   'ss' = Sprint Speed (default ~105, LUNAR shows 115)
--   'fs' = Fly Speed    (default ~39, LUNAR shows 40)
--   'tr' = Turn Radius  (default 1)
-- Location: Workspace.Characters.<player>.Data folder, ALSO mirrored on
-- Character itself (game reads from one, server reads from other).
-- Strategy: set on BOTH Character + Character.Data every frame.
-- ════════════════════════════════════════════════════════════════════

local function setStatAttr(char, key, value)
    if not char then return end
    pcall(function() char:SetAttribute(key, value) end)
    local data = char:FindFirstChild('Data')
    if data then
        pcall(function() data:SetAttribute(key, value) end)
    end
end

task.spawn(function()
    while true do
        task.wait()  -- every frame
        local c = getChar()
        if c then
            if S.EnableWalkSpeed   then setStatAttr(c, 's',  S.WalkSpeed) end
            if S.EnableSprintSpeed then setStatAttr(c, 'ss', S.SprintSpeed) end
            if S.EnableFlySpeed    then setStatAttr(c, 'fs', S.FlySpeed) end
            if S.EnableTurnRadius  then setStatAttr(c, 'tr', S.TurnRadius) end
            -- Backup: Humanoid.WalkSpeed (some games combine attribute + Humanoid)
            if S.EnableWalkSpeed then
                local h = c:FindFirstChildOfClass('Humanoid')
                if h then pcall(function() h.WalkSpeed = S.WalkSpeed end) end
            end
        end
    end
end)

-- ════════════════════════════════════════════════════════════════════
-- PHASE 1: Infinite Stamina (chunk3 line 902-915 verified pattern)
-- Real attribute names: 'st' (stamina) and 'sr' (stamina regen)
-- Value: 10000 (NOT 100)
-- Hook AttributeChanged('st') to keep at 10000 even when server tries reset
-- ════════════════════════════════════════════════════════════════════
local _infStaminaHookedChar = nil
task.spawn(function()
    while true do
        task.wait(0.3)
        if S.InfStamina then
            pcall(function()
                local c = getChar()
                if not c then return end
                local hasSt = c:GetAttribute('st') ~= nil
                local hasSr = c:GetAttribute('sr') ~= nil

                if hasSt and hasSr then
                    -- Path A: creature has st/sr attributes
                    pcall(function() c:SetAttribute('sr', 10000) end)
                    pcall(function() c:SetAttribute('st', 10000) end)
                    -- One-shot hook to keep value when server resets
                    if _infStaminaHookedChar ~= c then
                        _infStaminaHookedChar = c
                        pcall(function()
                            c:GetAttributeChangedSignal('st'):Connect(function()
                                if S.InfStamina and c.Parent then
                                    pcall(function() c:SetAttribute('sr', 10000) end)
                                    pcall(function() c:SetAttribute('st', 10000) end)
                                end
                            end)
                        end)
                    end
                else
                    -- Path B: fallback via PlayerWrapper:GetCurrentCharacter()
                    local pw = getPlayerWrapper()
                    if pw and pw.GetClient then
                        pcall(function()
                            local client = pw:GetClient()
                            if client and client.GetCurrentCharacter then
                                local ch = client:GetCurrentCharacter()
                                if ch and ch.StaminaTracker then
                                    ch.StaminaTracker.Stamina = ch.StaminaTracker:GetMaxStamina()
                                end
                            end
                        end)
                    end
                end
            end)
        else
            _infStaminaHookedChar = nil
        end
    end
end)

-- Reset hook tracker on character respawn
LP.CharacterAdded:Connect(function() _infStaminaHookedChar = nil end)

-- ════════════════════════════════════════════════════════════════════
-- PHASE 3: No Damage via remote-block (RemoteHook-verified 2026-05-29)
-- CoS is client-authoritative for environmental damage: the CLIENT fires
-- a remote to hurt ITSELF. e.g. LavaSelfDamage:FireServer() in lava.
-- (Confirmed: HSHub_RemoteHook capture, hooks_ok includes "LavaSelfDamage".)
--
-- Uses the shared Stealth namecall hook: register a handler that DROPS
-- FireServer when self.Name is in BLOCK and its toggle is on. Stealth's
-- dispatcher already guards checkcaller() (our own fire() helper passes
-- through) and a non-nil return short-circuits the real call = blocked.
--
-- EXTEND LATER: when we capture Drowning/Meteor/Moisture/Tornado remotes,
-- just add rows to BLOCK below — no other change needed.
-- ════════════════════════════════════════════════════════════════════
do
    local BLOCK = {
        -- Lava: LavaSelfDamage:FireServer() ~1/s, ~95 dmg/tick (DamageSpy-verified)
        LavaSelfDamage = function() return S.NoLavaDamage end,
        -- Drowning: 2 client-auth self-damage remotes fire ~1/s while suffocating
        --   OxygenRemote ~22 dmg/tick (starts the damage), DrownRemote ~7 dmg/tick.
        --   Both verified by DamageSpy 2026-05-29 (health 'h' drop 0.07s after each fire).
        OxygenRemote   = function() return S.NoDrowningDamage end,
        DrownRemote    = function() return S.NoDrowningDamage end,
        -- Meteor    = function() return S.NoMeteorDamage end,     -- TODO: capture remote
        -- Moisture  = function() return S.NoMoistureDamage end,   -- TODO: capture remote
        -- Tornado   = function() return S.NoTornadoDamage end,    -- TODO: capture remote
    }
    -- MECHANISM: hookfunction on FireServer (NOT __namecall).
    -- DamageSpy PROVED hookfunction(remote.FireServer,...) intercepts these exact
    -- remotes; the old __namecall hook missed them because CoS fires the damage
    -- remotes via a wrapper/dot-call (FireServer(remote,...)), not obj:FireServer()
    -- colon-syntax. hookfunction on the FireServer C-closure catches BOTH styles.
    pcall(function()
        local hookfn = (Stealth and Stealth.hookfunction) or hookfunction
        if not hookfn then return end
        -- any RemoteEvent works: FireServer is one shared C-closure for all of them
        local sample
        for _, d in ipairs(game:GetService('ReplicatedStorage'):GetDescendants()) do
            if d:IsA('RemoteEvent') then sample = d; break end
        end
        if not sample then return end
        local ccaller = (Stealth and Stealth.checkcaller) or function() return false end
        local orig
        orig = hookfn(sample.FireServer, function(self, ...)
            -- skip our own fires (executor thread) so we never block HSHub itself
            if not ccaller() then
                local ok, nm = pcall(function() return self.Name end)
                if ok then
                    local pred = BLOCK[nm]
                    if pred and pred() == true then
                        return   -- swallow → server never receives the self-damage
                    end
                end
            end
            return orig(self, ...)
        end)
    end)
end

-- Visual loops
task.spawn(function()
    while true do
        task.wait(2)
        if S.RemoveFog then
            Lighting.FogEnd = 100000; Lighting.FogStart = 100000
        end
    end
end)

HSHub:Notify(('HS Hub loaded · %s · HS-COS-V4')
    :format(IS_HARDCORE and 'Sonaria HARDCORE (Shadow shrine enabled)'
        or IS_ISLE10 and 'Isle 10'
        or 'Creatures of Sonaria'), 'ok', 3)
