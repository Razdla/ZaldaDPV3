
local xPws = (function()
  local ns = {}
  local V08ok = {
    "print","type","pairs","ipairs","next","select","pcall","xpcall",
    "error","tostring","tonumber","rawget","rawset","rawequal","rawlen",
    "setmetatable","getmetatable","require","assert","load","dofile",
    "string","table","math","io","os","coroutine","package","utf8",
    "game","workspace","script","task","wait","spawn","delay","tick",
    "Vector2","Vector3","CFrame","Color3","BrickColor","UDim","UDim2",
    "Enum","Instance","Ray","Region3","NumberRange","TweenInfo",
    "_G","_VERSION","warn","print","typeof"
  }
  for Jkhn4, AaqkQ in ipairs(V08ok) do
    local ZF4, OT9z = pcall(rawget, _ENV or getfenv and getfenv() or {}, AaqkQ)
    if not ZF4 then
      
      if type(AaqkQ) == "string" then
        local TK, w4aao = pcall(function() return _G and _G[AaqkQ] end)
        if TK then ns[AaqkQ] = w4aao end
      end
    else
      ns[AaqkQ] = OT9z
    end
  end
  
  ns.print = print ns.type = type ns.pairs = pairs ns.ipairs = ipairs
  ns.next = next ns.select = select ns.pcall = pcall ns.xpcall = xpcall
  ns.error = error ns.tostring = tostring ns.tonumber = tonumber
  ns.rawget = rawget ns.rawset = rawset ns.setmetatable = setmetatable
  ns.getmetatable = getmetatable ns.table = table ns.string = string
  ns.math = math ns.coroutine = coroutine
  return ns
end)()
local function J5(OqYD, SWQaq, ...)
  local EAzw = {}
  local SNB = 1
  local CmgI = OqYD[1]
  local C2RB = OqYD[2]
  local WEvl = OqYD[3]
  local SdFK = SWQaq or {}
  local zKaAr = -1
  local function Tbqx(VNzc) if VNzc >= 256 then return C2RB[VNzc - 255] end return EAzw[VNzc] end
  local QB = select("#", ...)
  for Ka = 1, QB do EAzw[Ka - 1] = select(Ka, ...) end
  while true do
    local qv = CmgI[SNB]
    local t8 = qv[1]
    local luCJ = qv[2]
    local xuZ = qv[3]
    local EO1zv = qv[4]
    SNB = SNB + 1
    if t8 == 8 then
      local np1N5 = EAzw[luCJ]
      local eOp
      if xuZ == 0 then eOp = zKaAr - luCJ else eOp = xuZ - 1 end
      local tiB = {}
      for QuwF_ = 1, eOp do tiB[QuwF_] = EAzw[luCJ + QuwF_] end
      local Syy_9 = table.pack(np1N5(table.unpack(tiB, 1, eOp)))
      if EO1zv == 0 then
        for QuwF_ = 0, Syy_9.n - 1 do EAzw[luCJ + QuwF_] = Syy_9[QuwF_ + 1] end
        zKaAr = luCJ + Syy_9.n - 1
      else
        for QuwF_ = 0, EO1zv - 2 do EAzw[luCJ + QuwF_] = Syy_9[QuwF_ + 1] end
      end
    elseif t8 == 38 then
      EAzw[luCJ] = {}
    elseif t8 == 31 then
      EAzw[luCJ] = SdFK[xuZ + 1][1]
    elseif t8 == 18 then
      EAzw[luCJ] = xPws[C2RB[xuZ + 1]]
    elseif t8 == 5 then
      EAzw[luCJ] = EAzw[luCJ] + EAzw[luCJ + 2]
      if (EAzw[luCJ + 2] > 0 and EAzw[luCJ] <= EAzw[luCJ + 1]) or
         (EAzw[luCJ + 2] < 0 and EAzw[luCJ] >= EAzw[luCJ + 1]) then
        EAzw[luCJ + 3] = EAzw[luCJ]
        SNB = SNB + xuZ
      end
    elseif t8 == 25 then
      if xuZ == 0 then
        local PW = select("#", ...)
        for QuwF_ = 0, PW - 1 do EAzw[luCJ + QuwF_] = select(QuwF_ + 1, ...) end
        zKaAr = luCJ + PW - 1
      else
        for QuwF_ = 0, xuZ - 2 do EAzw[luCJ + QuwF_] = select(QuwF_ + 1, ...) end
      end
    elseif t8 == 2 then
      EAzw[luCJ] = EAzw[xuZ][1]
    elseif t8 == 1 then
      EAzw[luCJ] = xuZ ~= 0
      if EO1zv ~= 0 then SNB = SNB + 1 end
    elseif t8 == 3 then
      if (not not EAzw[luCJ]) ~= (EO1zv ~= 0) then SNB = SNB + 1 end
    elseif t8 == 10 then
      if (Tbqx(xuZ) <= Tbqx(EO1zv)) ~= (luCJ ~= 0) then SNB = SNB + 1 end
    elseif t8 == 34 then
      xPws[C2RB[xuZ + 1]] = EAzw[luCJ]
    elseif t8 == 40 then
      local np1N5 = EAzw[luCJ]
      local tiB = {}
      for QuwF_ = 1, xuZ - 1 do tiB[QuwF_] = EAzw[luCJ + QuwF_] end
      return np1N5(table.unpack(tiB))
    elseif t8 == 29 then
      EAzw[luCJ] = -EAzw[xuZ]
    elseif t8 == 7 then
      EAzw[luCJ] = #EAzw[xuZ]
    elseif t8 == 26 then
      EAzw[luCJ] = {EAzw[luCJ]}
    elseif t8 == 12 then
      EAzw[luCJ] = not EAzw[xuZ]
    elseif t8 == 16 then
      EAzw[luCJ] = C2RB[xuZ + 1]
    elseif t8 == 33 then
      if xuZ == 1 then return end
      local eOp
      if xuZ == 0 then eOp = zKaAr - luCJ + 1 else eOp = xuZ - 1 end
      local Syy_9 = {}
      for QuwF_ = 0, eOp - 1 do Syy_9[QuwF_ + 1] = EAzw[luCJ + QuwF_] end
      return table.unpack(Syy_9, 1, eOp)
    elseif t8 == 36 then
      EAzw[luCJ] = Tbqx(xuZ) % Tbqx(EO1zv)
    elseif t8 == 0 then
      EAzw[luCJ] = EAzw[xuZ]
    elseif t8 == 22 then
      EAzw[luCJ] = Tbqx(xuZ) + Tbqx(EO1zv)
    elseif t8 == 27 then
      EAzw[luCJ] = Tbqx(xuZ) - Tbqx(EO1zv)
    elseif t8 == 6 then
      local Il2Xx = EAzw[luCJ]
      local P77I = EAzw[luCJ + 1]
      local AZ = EAzw[luCJ + 2]
      local JSyr = table.pack(Il2Xx(P77I, AZ))
      for QuwF_ = 0, EO1zv - 1 do EAzw[luCJ + 3 + QuwF_] = JSyr[QuwF_ + 1] end
      if EAzw[luCJ + 3] ~= nil then
        EAzw[luCJ + 2] = EAzw[luCJ + 3]
      else
        SNB = SNB + 1
      end
    elseif t8 == 17 then
      for QuwF_ = luCJ, xuZ do EAzw[QuwF_] = nil end
    elseif t8 == 11 then
      local ya9 = {}
      for QuwF_ = xuZ, EO1zv do ya9[#ya9 + 1] = tostring(EAzw[QuwF_]) end
      EAzw[luCJ] = table.concat(ya9)
    elseif t8 == 39 then
      if (Tbqx(xuZ) < Tbqx(EO1zv)) ~= (luCJ ~= 0) then SNB = SNB + 1 end
    elseif t8 == 9 then
      SNB = SNB + xuZ
    elseif t8 == 37 then
      EAzw[luCJ] = EAzw[luCJ] - EAzw[luCJ + 2]
      SNB = SNB + xuZ
    elseif t8 == 20 then
      local jHUEZ = EAzw[luCJ]
      local gGIXO = (EO1zv - 1) * 50
      local eOp = xuZ
      if xuZ == 0 then eOp = zKaAr - luCJ end
      for QuwF_ = 1, eOp do jHUEZ[gGIXO + QuwF_] = EAzw[luCJ + QuwF_] end
    elseif t8 == 32 then
      EAzw[luCJ] = Tbqx(xuZ) ^ Tbqx(EO1zv)
    elseif t8 == 15 then
      EAzw[luCJ] = Tbqx(xuZ) / Tbqx(EO1zv)
    elseif t8 == 19 then
      EAzw[luCJ][1] = EAzw[xuZ]
    elseif t8 == 23 then
      EAzw[luCJ] = EAzw[xuZ][Tbqx(EO1zv)]
    elseif t8 == 4 then
      if (not not EAzw[xuZ]) ~= (EO1zv ~= 0) then
        SNB = SNB + 1
      else
        EAzw[luCJ] = EAzw[xuZ]
      end
    elseif t8 == 30 then
      if (Tbqx(xuZ) == Tbqx(EO1zv)) ~= (luCJ ~= 0) then SNB = SNB + 1 end
    elseif t8 == 14 then
      local mNb = WEvl[xuZ + 1]
      local esMOb = {}
      local Ny = mNb[6]
      for QuwF_ = 1, #Ny do
        local mw = Ny[QuwF_]
        if mw[1] == 1 then
          if mw[3] == 1 then
            esMOb[QuwF_] = EAzw[mw[2]]
          else
            esMOb[QuwF_] = {EAzw[mw[2]]}
          end
        else
          esMOb[QuwF_] = SdFK[mw[2] + 1]
        end
      end
      EAzw[luCJ] = function(...)
        return J5(mNb, esMOb, ...)
      end
    elseif t8 == 28 then
      EAzw[luCJ][Tbqx(xuZ)] = Tbqx(EO1zv)
    elseif t8 == 21 then
      local bp = EAzw[xuZ]
      EAzw[luCJ + 1] = bp
      EAzw[luCJ] = bp[Tbqx(EO1zv)]
    elseif t8 == 13 then
      EAzw[luCJ] = Tbqx(xuZ) * Tbqx(EO1zv)
    elseif t8 == 24 then
      SdFK[xuZ + 1][1] = EAzw[luCJ]
    end
  end
end

local sw, K1ro, sOou, Eck = string.byte, string.char, table.concat, tonumber
local function fiT(xIxG, Yp3n)
  local RiS = (Yp3n * 167 + 253) % 256
  local ZpP = {}
  for QuwF_ = 1, #xIxG do
    RiS = (RiS * 73 + 213 + 41) % 256
    ZpP[QuwF_] = K1ro((sw(xIxG, QuwF_) - RiS) % 256)
  end
  return sOou(ZpP)
end

local Z39, kf, lserv, fDS, QpYRB, yZCP =
  string.byte, string.sub, string.char, table.concat, math.floor, tonumber



local jB = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local QX9q = {}
for F82hI = 1, #jB do QX9q[Z39(jB, F82hI)] = F82hI - 1 end
local function k6yGY(MLYwx)
  local ZpP, ry, rb, uJB6z = {}, 0, 1, #MLYwx
  while rb <= uJB6z do
    local e4z = QX9q[Z39(MLYwx, rb)]; local Ktop = QX9q[Z39(MLYwx, rb + 1)]
    local Hvd1 = Z39(MLYwx, rb + 2); local wow = Z39(MLYwx, rb + 3); rb = rb + 4
    local eOp = e4z * 262144 + Ktop * 4096
    if Hvd1 ~= 61 then eOp = eOp + QX9q[Hvd1] * 64 end
    if wow ~= 61 then eOp = eOp + QX9q[wow] end
    ry = ry + 1; ZpP[ry] = lserv(QpYRB(eOp / 65536) % 256)
    if Hvd1 ~= 61 then ry = ry + 1; ZpP[ry] = lserv(QpYRB(eOp / 256) % 256) end
    if wow ~= 61 then ry = ry + 1; ZpP[ry] = lserv(eOp % 256) end
  end
  return fDS(ZpP)
end
local function Fr(Nxg, Yp3n)
  if Yp3n then Nxg = fiT(Nxg, Yp3n) end
  local Fdm = 1
  local function ACfn()
    local ktC, KzrkH = 0, 1
    while true do
      local Ktop = Z39(Nxg, Fdm); Fdm = Fdm + 1
      ktC = ktC + (Ktop % 128) * KzrkH
      if Ktop < 128 then break end
      KzrkH = KzrkH * 128
    end
    return ktC
  end
  local function fQu_()
    local Nhbs = ACfn()
    local eOp = QpYRB(Nhbs / 2)
    if Nhbs % 2 == 1 then eOp = -eOp - 1 end
    return eOp
  end
  local function EC8c7()
    local uJB6z = ACfn()
    local VMjT = kf(Nxg, Fdm, Fdm + uJB6z - 1)
    Fdm = Fdm + uJB6z
    return VMjT
  end
  local function Am()
    local KA29o = Z39(Nxg, Fdm); Fdm = Fdm + 1
    if KA29o == 3 then return EC8c7()
    elseif KA29o == 2 then return yZCP(EC8c7())
    elseif KA29o == 1 then local Ktop = Z39(Nxg, Fdm); Fdm = Fdm + 1; return Ktop ~= 0
    else return nil end
  end
  local function vKDch()
    local fbN3m = ACfn()
    local jVxHo = Z39(Nxg, Fdm); Fdm = Fdm + 1
    local BrhRA = ACfn()
    local CmgI = {}
    for rb = 1, BrhRA do
      local t8 = ACfn(); local e4z = fQu_(); local Ktop = fQu_(); local xIxG = fQu_()
      CmgI[rb] = { t8, e4z, Ktop, xIxG }
    end
    local vq4ki = ACfn()
    local KFTx9 = {}
    for rb = 1, vq4ki do KFTx9[rb] = Am() end
    local LbU = ACfn()
    local aMZDS = {}
    for rb = 1, LbU do
      local GrP = Z39(Nxg, Fdm); Fdm = Fdm + 1
      local rm = ACfn()
      local _IlWh = Z39(Nxg, Fdm); Fdm = Fdm + 1
      aMZDS[rb] = { GrP, rm, _IlWh }
    end
    local _uXk = ACfn()
    local WEvl = {}
    for rb = 1, _uXk do WEvl[rb] = vKDch() end
    return { CmgI, KFTx9, WEvl, fbN3m, jVxHo, aMZDS }
  end
  return vKDch()
end

J5(Fr(k6yGY("3QSz5KV7Eddn80nPK22Bx83nu7+JXfO5R9Upr/dPZaeyx50lWUvZnw27DZXJPUeLfbh/hbsfwYH3k/F1qw87bV2Da2cZ+6Zf1fnNX5H3AU9FaT0/Ad9xTrdfNzN/1eEnN08ZH+PJURegP5cPVrnPBwsx+//PqzH3eyVt7zibs+cDFdnfp5Eh12QHX2EJe5fbvfPR03VrC80t2z236WdzP6HXq7VlO+irI0UNn9tFQZeVv3mPTzmxfwGb7Yu3qyV7b5lpXywPp+nRg99xhfsZaT1zU2P144U/sW+71Wnf8z0tQzAz601VJ6NbiR9d1cEXF0/5B8mjNRN/wW0DN6Gx5/QX73GZiycHTQNhAQV7m/u9683HeXcDbTHnO8X1S3i7s1Wdr2tz0acl7Qmf32dBj5GrfZtH2bWL/6n5b7wfN/lhk2+fFQupl82D45GF8xVPQX9LA/nvg029U8BDe13lNzOJGS/tAVEnp1uJF1mzxSMP6/0Tx7FB94Qnf4Epm7cx3RPxEZWLKyNN+13XCYeTlcH3y9WFWwjLQ2Utv/uLYbe1E5mvb2vRnyG7DavX/UWbl7V5f0YvxXf7p+9vtiE3Z2uZYV8vE5FX243TT5gDG0c9fU0/BffFN9NxqS916zcnOWHxI/W8cReNT6fpScvCJ/8jFR2Rn1EHjXFpC0NrpQfvJzvfrJ01u1EKafHrb53loefZx49h9dFH0ynBAbNhtbvPmadxP9WXKcEJl+EtRYmbvXmbUwW1k+2v/W+1KY1ng6NZXxcdq1fpk7NTp/sjtT1/WS/5/YNbH1PAUYm/5TdBsRkv+zFRJ7WhiR9vIcEPHy39G9WTNRl/N3nvPK3FeeET/VWVizdNTQNxRQVzo8/B/9m5eX0B2anTRc/jT4O3vzmZu3W71rkVzw+TxUdVh43B5X9bO7F377UDb8ErC2t/k3vhFvutd71362GpXQFeX4ctQwX/5ze9eS0wZdsJnR1TQ6XWu1k5lzelLz2v4xkhlfkW178l+3038fAlm8lx3gP2Bb17If+781n5kWyBz9/tvduV6fbZL/c7r/xthUeh37mZWV3huXuzJa/DL2OXnxl5m1Wbtpn1r+9zvychZ12hb18lG6tXz5XlT40JB0tPg8lA9fKPV6FXuU/3zOEpP18ZJ/PBVRmvRYkmZc1/C/1FF//RvcX8jSOJhSaLoQn7A/UB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"),6))