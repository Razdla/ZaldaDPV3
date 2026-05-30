
local NcZJ = (function()
  local WCp = {}
  local Zc = {
    "print","type","pairs","ipairs","next","select","pcall","xpcall",
    "error","tostring","tonumber","rawget","rawset","rawequal","rawlen",
    "setmetatable","getmetatable","require","assert","load","dofile",
    "loadstring","string","table","math","io","os","coroutine","package","utf8",
    "game","workspace","script","task","wait","spawn","delay","tick",
    "Vector2","Vector3","CFrame","Color3","BrickColor","UDim","UDim2",
    "Enum","Instance","Ray","Region3","NumberRange","TweenInfo",
    "ColorSequence","ColorSequenceKeypoint","NumberSequence","NumberSequenceKeypoint",
    "PathWaypoint","PhysicalProperties","Random","DateTime","Faces","Axes",
    "RaycastParams","OverlapParams","CatalogSearchParams",
    "_G","_VERSION","warn","print","typeof"
  }
  local WOqq = _ENV or (getfenv and getfenv()) or _G or {}
  for X4s6l, QE in ipairs(Zc) do
    local Oqzl, j3 = pcall(rawget, WOqq, QE)
    if not Oqzl then
      local RhKe3, H5EQJ = pcall(function() return _G and _G[QE] end)
      if RhKe3 then WCp[QE] = H5EQJ end
    else
      WCp[QE] = j3
    end
  end
  
  WCp.print = print WCp.type = type WCp.pairs = pairs WCp.ipairs = ipairs
  WCp.next = next WCp.select = select WCp.pcall = pcall WCp.xpcall = xpcall
  WCp.error = error WCp.tostring = tostring WCp.tonumber = tonumber
  WCp.rawget = rawget WCp.rawset = rawset WCp.setmetatable = setmetatable
  WCp.getmetatable = getmetatable WCp.table = table WCp.string = string
  WCp.math = math WCp.coroutine = coroutine
  
  
  
  local ZT = _G or WOqq
  setmetatable(WCp, { ["__index"] = function(X4s6l, Mft)
    return ZT[Mft]
  end })
  return WCp
end)()
local function mGr(Xpv, j9te, ...)
  local I9PZP = {}
  local sN = 1
  local lJ = Xpv[1]
  local OI = Xpv[2]
  local KwVo = Xpv[3]
  local Q9es = j9te or {}
  local is = -1
  local function qg6SV(uH) if uH >= 256 then return OI[uH - 255] end return I9PZP[uH] end
  local Dz = select("#", ...)
  for l8P = 1, Dz do I9PZP[l8P - 1] = select(l8P, ...) end
  while true do
    local Vwb = lJ[sN]
    local q3VMl = Vwb[1]
    local tK0 = Vwb[2]
    local FTKNY = Vwb[3]
    local ib = Vwb[4]
    sN = sN + 1
    if q3VMl == 36 then
      sN = sN + FTKNY
    elseif q3VMl == 37 then
      I9PZP[tK0] = not I9PZP[FTKNY]
    elseif q3VMl == 9 then
      I9PZP[tK0] = I9PZP[FTKNY]
    elseif q3VMl == 8 then
      if FTKNY == 1 then return end
      local Zf
      if FTKNY == 0 then Zf = is - tK0 + 1 else Zf = FTKNY - 1 end
      local Drn = {}
      for b4M = 0, Zf - 1 do Drn[b4M + 1] = I9PZP[tK0 + b4M] end
      return table.unpack(Drn, 1, Zf)
    elseif q3VMl == 38 then
      I9PZP[tK0] = I9PZP[tK0] - I9PZP[tK0 + 2]
      sN = sN + FTKNY
    elseif q3VMl == 23 then
      I9PZP[tK0] = qg6SV(FTKNY) / qg6SV(ib)
    elseif q3VMl == 39 then
      if (qg6SV(FTKNY) <= qg6SV(ib)) ~= (tK0 ~= 0) then sN = sN + 1 end
    elseif q3VMl == 7 then
      I9PZP[tK0] = qg6SV(FTKNY) + qg6SV(ib)
    elseif q3VMl == 26 then
      I9PZP[tK0] = qg6SV(FTKNY) * qg6SV(ib)
    elseif q3VMl == 6 then
      I9PZP[tK0] = FTKNY ~= 0
      if ib ~= 0 then sN = sN + 1 end
    elseif q3VMl == 4 then
      Q9es[FTKNY + 1][1] = I9PZP[tK0]
    elseif q3VMl == 30 then
      I9PZP[tK0][1] = I9PZP[FTKNY]
    elseif q3VMl == 5 then
      I9PZP[tK0] = I9PZP[FTKNY][1]
    elseif q3VMl == 0 then
      if (qg6SV(FTKNY) == qg6SV(ib)) ~= (tK0 ~= 0) then sN = sN + 1 end
    elseif q3VMl == 40 then
      local prn = I9PZP[tK0]
      local AF = {}
      for b4M = 1, FTKNY - 1 do AF[b4M] = I9PZP[tK0 + b4M] end
      return prn(table.unpack(AF))
    elseif q3VMl == 3 then
      I9PZP[tK0][qg6SV(FTKNY)] = qg6SV(ib)
    elseif q3VMl == 12 then
      I9PZP[tK0] = OI[FTKNY + 1]
    elseif q3VMl == 34 then
      local Kqf = I9PZP[FTKNY]
      I9PZP[tK0 + 1] = Kqf
      I9PZP[tK0] = Kqf[qg6SV(ib)]
    elseif q3VMl == 1 then
      I9PZP[tK0] = qg6SV(FTKNY) % qg6SV(ib)
    elseif q3VMl == 15 then
      local prn = I9PZP[tK0]
      local Zf
      if FTKNY == 0 then Zf = is - tK0 else Zf = FTKNY - 1 end
      local AF = {}
      for b4M = 1, Zf do AF[b4M] = I9PZP[tK0 + b4M] end
      local Drn = table.pack(prn(table.unpack(AF, 1, Zf)))
      if ib == 0 then
        for b4M = 0, Drn.n - 1 do I9PZP[tK0 + b4M] = Drn[b4M + 1] end
        is = tK0 + Drn.n - 1
      else
        for b4M = 0, ib - 2 do I9PZP[tK0 + b4M] = Drn[b4M + 1] end
      end
    elseif q3VMl == 17 then
      I9PZP[tK0] = Q9es[FTKNY + 1][1]
    elseif q3VMl == 21 then
      I9PZP[tK0] = {I9PZP[tK0]}
    elseif q3VMl == 16 then
      I9PZP[tK0] = NcZJ[OI[FTKNY + 1]]
    elseif q3VMl == 29 then
      local dI = KwVo[FTKNY + 1]
      local zls = {}
      local Aogt = dI[6]
      for b4M = 1, #Aogt do
        local dC = Aogt[b4M]
        if dC[1] == 1 then
          if dC[3] == 1 then
            zls[b4M] = I9PZP[dC[2]]
          else
            zls[b4M] = {I9PZP[dC[2]]}
          end
        else
          zls[b4M] = Q9es[dC[2] + 1]
        end
      end
      I9PZP[tK0] = function(...)
        return mGr(dI, zls, ...)
      end
    elseif q3VMl == 20 then
      I9PZP[tK0] = I9PZP[FTKNY][qg6SV(ib)]
    elseif q3VMl == 27 then
      local AzMTT = {}
      for b4M = FTKNY, ib do AzMTT[#AzMTT + 1] = tostring(I9PZP[b4M]) end
      I9PZP[tK0] = table.concat(AzMTT)
    elseif q3VMl == 10 then
      if FTKNY == 0 then
        local vfUP = select("#", ...)
        for b4M = 0, vfUP - 1 do I9PZP[tK0 + b4M] = select(b4M + 1, ...) end
        is = tK0 + vfUP - 1
      else
        for b4M = 0, FTKNY - 2 do I9PZP[tK0 + b4M] = select(b4M + 1, ...) end
      end
    elseif q3VMl == 33 then
      I9PZP[tK0] = qg6SV(FTKNY) - qg6SV(ib)
    elseif q3VMl == 2 then
      if (not not I9PZP[FTKNY]) ~= (ib ~= 0) then
        sN = sN + 1
      else
        I9PZP[tK0] = I9PZP[FTKNY]
      end
    elseif q3VMl == 24 then
      I9PZP[tK0] = {}
    elseif q3VMl == 14 then
      I9PZP[tK0] = -I9PZP[FTKNY]
    elseif q3VMl == 22 then
      for b4M = tK0, FTKNY do I9PZP[b4M] = nil end
    elseif q3VMl == 31 then
      I9PZP[tK0] = I9PZP[tK0] + I9PZP[tK0 + 2]
      if (I9PZP[tK0 + 2] > 0 and I9PZP[tK0] <= I9PZP[tK0 + 1]) or
         (I9PZP[tK0 + 2] < 0 and I9PZP[tK0] >= I9PZP[tK0 + 1]) then
        I9PZP[tK0 + 3] = I9PZP[tK0]
        sN = sN + FTKNY
      end
    elseif q3VMl == 28 then
      if (qg6SV(FTKNY) < qg6SV(ib)) ~= (tK0 ~= 0) then sN = sN + 1 end
    elseif q3VMl == 19 then
      if (not not I9PZP[tK0]) ~= (ib ~= 0) then sN = sN + 1 end
    elseif q3VMl == 32 then
      local BMF = I9PZP[tK0]
      local LFYo = I9PZP[tK0 + 1]
      local _hvj = I9PZP[tK0 + 2]
      local sANxF = table.pack(BMF(LFYo, _hvj))
      for b4M = 0, ib - 1 do I9PZP[tK0 + 3 + b4M] = sANxF[b4M + 1] end
      if I9PZP[tK0 + 3] ~= nil then
        I9PZP[tK0 + 2] = I9PZP[tK0 + 3]
      else
        sN = sN + 1
      end
    elseif q3VMl == 13 then
      local EuOp = I9PZP[tK0]
      local c17X = (ib - 1) * 50
      local Zf = FTKNY
      if FTKNY == 0 then Zf = is - tK0 end
      for b4M = 1, Zf do EuOp[c17X + b4M] = I9PZP[tK0 + b4M] end
    elseif q3VMl == 11 then
      I9PZP[tK0] = #I9PZP[FTKNY]
    elseif q3VMl == 25 then
      NcZJ[OI[FTKNY + 1]] = I9PZP[tK0]
    elseif q3VMl == 18 then
      I9PZP[tK0] = qg6SV(FTKNY) ^ qg6SV(ib)
    end
  end
end

local t8WTs, Vs0yS, Qo, uGv = string.byte, string.char, table.concat, tonumber
local function Qyge(mBn, iJSc)
  local hrBhj = (iJSc * 167 + 3) % 256
  local OD = {}
  for b4M = 1, #mBn do
    hrBhj = (hrBhj * 73 + 220 + 41) % 256
    OD[b4M] = Vs0yS((t8WTs(mBn, b4M) - hrBhj) % 256)
  end
  return Qo(OD)
end

local MJ6m, yn, cEz, uyL, J9E, Ja =
  string.byte, string.sub, string.char, table.concat, math.floor, tonumber



local E5jE = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local C7Wo = {}
for p1 = 1, #E5jE do C7Wo[MJ6m(E5jE, p1)] = p1 - 1 end
local function rMDXw(yOr)
  local OD, k8z, vx, P0DR = {}, 0, 1, #yOr
  while vx <= P0DR do
    local a8 = C7Wo[MJ6m(yOr, vx)]; local Qw_Ga = C7Wo[MJ6m(yOr, vx + 1)]
    local fWG = MJ6m(yOr, vx + 2); local Mo = MJ6m(yOr, vx + 3); vx = vx + 4
    local Zf = a8 * 262144 + Qw_Ga * 4096
    if fWG ~= 61 then Zf = Zf + C7Wo[fWG] * 64 end
    if Mo ~= 61 then Zf = Zf + C7Wo[Mo] end
    k8z = k8z + 1; OD[k8z] = cEz(J9E(Zf / 65536) % 256)
    if fWG ~= 61 then k8z = k8z + 1; OD[k8z] = cEz(J9E(Zf / 256) % 256) end
    if Mo ~= 61 then k8z = k8z + 1; OD[k8z] = cEz(Zf % 256) end
  end
  return uyL(OD)
end
local function gTtRP(qF, iJSc)
  if iJSc then qF = Qyge(qF, iJSc) end
  local oG = 1
  local function KC()
    local iqtCt, N7 = 0, 1
    while true do
      local Qw_Ga = MJ6m(qF, oG); oG = oG + 1
      iqtCt = iqtCt + (Qw_Ga % 128) * N7
      if Qw_Ga < 128 then break end
      N7 = N7 * 128
    end
    return iqtCt
  end
  local function vMU()
    local o_f1N = KC()
    local Zf = J9E(o_f1N / 2)
    if o_f1N % 2 == 1 then Zf = -Zf - 1 end
    return Zf
  end
  local function jVuf()
    local P0DR = KC()
    local ct = yn(qF, oG, oG + P0DR - 1)
    oG = oG + P0DR
    return ct
  end
  local function m0Amj()
    local ViI = MJ6m(qF, oG); oG = oG + 1
    if ViI == 3 then return jVuf()
    elseif ViI == 2 then return Ja(jVuf())
    elseif ViI == 1 then local Qw_Ga = MJ6m(qF, oG); oG = oG + 1; return Qw_Ga ~= 0
    else return nil end
  end
  local function Mi()
    local zDP = KC()
    local dF8IR = MJ6m(qF, oG); oG = oG + 1
    local reW9 = KC()
    local lJ = {}
    for vx = 1, reW9 do
      local q3VMl = KC(); local a8 = vMU(); local Qw_Ga = vMU(); local mBn = vMU()
      lJ[vx] = { q3VMl, a8, Qw_Ga, mBn }
    end
    local W3 = KC()
    local Mft = {}
    for vx = 1, W3 do Mft[vx] = m0Amj() end
    local jx = KC()
    local jo43 = {}
    for vx = 1, jx do
      local MSuw = MJ6m(qF, oG); oG = oG + 1
      local OmcRF = KC()
      local ND = MJ6m(qF, oG); oG = oG + 1
      jo43[vx] = { MSuw, OmcRF, ND }
    end
    local W2E2 = KC()
    local KwVo = {}
    for vx = 1, W2E2 do KwVo[vx] = Mi() end
    return { lJ, Mft, KwVo, zDP, dF8IR, jo43 }
  end
  return Mi()
end

mGr(gTtRP(rMDXw("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"),250))