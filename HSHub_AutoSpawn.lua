--[[
    HS HUB · AutoSpawn v11  —  per-slot toggles + direct VIM tap
    discord.gg/5rpP6faZSJ

    FIX vs v10:
    - REMOVED fireGuiButton (firesignal NEVER works for CoS — centralized input).
      v10 was wasting 3s waiting for it, then tapping too late.
    - Direct VIM tap immediately after PlayButton is found.
    - Slot select wait bumped 0.9 → 1.2s (carousel anim).

    NEW: per-slot ON/OFF toggle buttons (S1 / S2 / S3).
    AUTO only uses slots with toggle ON. Press Read to fill in creature names.

    FLOW: Read → (toggle slots) → TEST Play / AUTO.
]]

if shared.__HSHub_AutoSpawn then pcall(function() shared.__HSHub_AutoSpawn:Destroy() end) end

local Players    = game:GetService('Players')
local Workspace  = game:GetService('Workspace')
local UIS        = game:GetService('UserInputService')
local GuiService = game:GetService('GuiService')
local LP = Players.LocalPlayer
local PG = LP:WaitForChild('PlayerGui')

local AUTO       = false
local logFn
local logLines   = {}
local learnedOff = nil
local panelGui   = nil

-- per-slot toggle state
local slotEnabled = { [1]=true, [2]=true, [3]=true }
local slotToggleBtns = {}   -- [n] = TextButton
local lastSlotData   = {}   -- cached from last Read

-- ═══ platform + input (unchanged from v10) ═══════════════════════
local IS_MOBILE, IS_PC, IS_IOS, IS_POTASSIUM = false, false, false, false
pcall(function()
    local p = UIS:GetPlatform()
    if p == Enum.Platform.IOS then IS_IOS=true; IS_MOBILE=true
    elseif p == Enum.Platform.Android then IS_MOBILE=true
    elseif p==Enum.Platform.Windows or p==Enum.Platform.OSX or p==Enum.Platform.UWP then IS_PC=true end
end)
if not IS_PC and not IS_MOBILE then if UIS.TouchEnabled then IS_MOBILE=true else IS_PC=true end end
pcall(function() if getexecutorname and tostring(getexecutorname()):lower():find('potassium') then IS_POTASSIUM=true end end)
local VIM; pcall(function() VIM = game:GetService('VirtualInputManager') end)
local GUI_INSET = Vector2.new(0,0); pcall(function() GUI_INSET = GuiService:GetGuiInset() end)

local function vimTouch(x,y) if not VIM then return end
    pcall(function() VIM:SendTouchEvent(1,0,x,y) end); task.wait(0.06); pcall(function() VIM:SendTouchEvent(1,2,x,y) end) end
local function vimMouse(x,y) if not VIM then return end
    pcall(function() VIM:SendMouseButtonEvent(x,y,0,true,game,1) end); task.wait(0.05); pcall(function() VIM:SendMouseButtonEvent(x,y,0,false,game,1) end) end
local function potClick(x,y) pcall(function() mousemoveabs(x,y) end); task.wait(0.03); pcall(function() mouse1click() end) end
local function vimClick(x,y)
    if IS_POTASSIUM and IS_PC then potClick(x,y); return end
    if IS_PC then if VIM then vimMouse(x,y) elseif IS_POTASSIUM then potClick(x,y) end
    else vimMouse(x,y); task.wait(0.1); vimTouch(x,y) end
end
local function clickHidden(x,y)
    local was = panelGui and panelGui.Enabled
    if panelGui then panelGui.Enabled=false; task.wait(0.05) end
    vimClick(x,y)
    if panelGui then task.wait(0.05); panelGui.Enabled=was end
end
local function centerOf(b) local ap,as=b.AbsolutePosition,b.AbsoluteSize; return ap.X+as.X/2, ap.Y+as.Y/2 end

-- ═══ lobby GUI helpers (unchanged from v10) ══════════════════════
local function findSaveGui()
    for _,r in ipairs({PG, gethui and gethui() or PG}) do local g=r:FindFirstChild('SaveSelectionGui'); if g then return g end end
end
local function visibleChain(o)
    local n=o; while n and n:IsA('GuiObject') do if not n.Visible then return false end; n=n.Parent end; return true
end
local function findPlayButton()
    local roots={PG}; pcall(function() if gethui then roots[#roots+1]=gethui() end end)
    for _,root in ipairs(roots) do
        for _,sg in ipairs(root:GetChildren()) do
            if sg:IsA('ScreenGui') and sg.Name=='SaveSelectionGui' then
                for _,d in ipairs(sg:GetDescendants()) do
                    if d.Name=='PlayButton' and (d:IsA('ImageButton') or d:IsA('TextButton')) and visibleChain(d) then
                        if d.AbsoluteSize.X < 200 then return d end
                    end
                end
            end
        end
    end
    return nil
end
local function readSlots()
    local out={}; local gui=findSaveGui(); if not gui then return out end
    local sf; for _,d in ipairs(gui:GetDescendants()) do if d.Name=='SlotsFrame' then sf=d; break end end
    if not sf then return out end
    for _,child in ipairs(sf:GetChildren()) do
        local n=tonumber(child.Name)
        if n then
            local cf=child:FindFirstChild('CreatureFrame',true)
            local nm,dead='?',false
            if cf then
                local nameL=cf:FindFirstChild('NameLabel')
                local deadL=cf:FindFirstChild('DeadLabel')
                local restB=cf:FindFirstChild('RestartButton')
                if nameL then nm=nameL.Text end
                dead=(deadL and deadL.Visible==true) or (restB and restB.Visible==true) or false
            end
            out[#out+1]={slot='Slot'..n, n=n, name=nm, dead=dead, card=cf}
        end
    end
    table.sort(out, function(a,b) return a.n<b.n end)
    return out
end
local function slotByN(n) for _,s in ipairs(readSlots()) do if s.n==n then return s end end end
local function inGame()
    local chars=Workspace:FindFirstChild('Characters')
    return chars and (chars:FindFirstChild(LP.Name) or chars:FindFirstChild(LP.DisplayName)) and true or false
end
local function lobbyReady()
    local pb=findPlayButton(); if not pb then return false end
    local ok=true; pcall(function() local n=pb; while n and n:IsA('GuiObject') do if not n.Visible then ok=false; break end; n=n.Parent end end)
    return ok
end
local function tapButton(btn,label)
    if not btn then logFn('tap nil: '..tostring(label),true); return false end
    local rx,ry=centerOf(btn)
    local off=IS_PC and GUI_INSET.Y or (learnedOff or 0)
    logFn(('tap %s @(%d,%d) off=%d'):format(label,math.floor(rx),math.floor(ry+off),math.floor(off)))
    clickHidden(rx,ry+off)
    return true
end

-- ═══ PLAY — v11 FIX: no fireGuiButton, direct tap immediately ════
--
--  v10 BUG (now removed):
--    fireGuiButton(pb)                         ← never works for CoS
--    repeat task.wait(0.5) until ... t > 3     ← 3s wasted
--    if not inGame() then tapButton(pb, ...)   ← tap 3s too late
--
--  v11: find PlayButton → VIM tap immediately → wait up to 10s.
--  Only tries slots whose per-slot toggle is ON.
--
local function playAlive()
    if inGame() then return true end
    local slots=readSlots()
    local aliveList={}
    for _,s in ipairs(slots) do
        if not s.dead and slotEnabled[s.n] then
            aliveList[#aliveList+1]=s
        end
    end
    if #aliveList==0 then logFn('no enabled ALIVE slot (check toggles)', true); return false end
    for _,tgt in ipairs(aliveList) do
        logFn('select '..tgt.slot..' ('..tgt.name..')')
        tapButton(tgt.card and (tgt.card:FindFirstChild('ViewButton') or tgt.card), 'select '..tgt.slot)
        task.wait(1.2)  -- was 0.9 — give carousel anim time to settle
        local pb=findPlayButton()
        if not pb then
            logFn('  PlayButton not visible for '..tgt.slot..' → next slot', true)
        else
            -- ── DIRECT TAP — no firesignal middleman ──────────────
            logFn(('Mainkan %s → direct VIM tap'):format(tgt.name))
            tapButton(pb, 'Mainkan '..tgt.name)
            local t=tick()
            repeat task.wait(0.5) until inGame() or tick()-t > 10
            if inGame() then logFn('✓ IN GAME ('..tgt.name..')'); return true end
            logFn('✗ tap sent, not in game after 10s (blackscreen?)', true)
            return false
        end
    end
    logFn('no enabled alive slot became playable', true)
    return false
end

local busy=false
task.spawn(function()
    while true do task.wait(2)
        if AUTO and not busy and not inGame() and lobbyReady() then
            busy=true; task.wait(1.5+math.random())
            if not inGame() and lobbyReady() then
                for _=1,2 do if playAlive() then break end; task.wait(2) end
            end
            busy=false
        end
    end
end)

-- ═══ UI ══════════════════════════════════════════════════════════
local gui=Instance.new('ScreenGui'); gui.Name='HSHub_AutoSpawn_'..math.random(1e5,1e6)
gui.ResetOnSpawn=false; gui.IgnoreGuiInset=true; gui.Parent=(gethui and gethui()) or PG
shared.__HSHub_AutoSpawn=gui; panelGui=gui

local FRAME_W=380
local frame=Instance.new('Frame',gui)
frame.Size=UDim2.new(0,FRAME_W,0,450); frame.Position=UDim2.new(0,20,0.5,-225)
frame.BackgroundColor3=Color3.fromRGB(18,20,28); frame.BorderSizePixel=0; frame.Active=true; frame.Draggable=true
Instance.new('UICorner',frame).CornerRadius=UDim.new(0,10)
Instance.new('UIStroke',frame).Color=Color3.fromRGB(140,100,220)

-- header
local hdr=Instance.new('Frame',frame); hdr.Size=UDim2.new(1,0,0,38); hdr.BackgroundColor3=Color3.fromRGB(110,80,190); hdr.BorderSizePixel=0
Instance.new('UICorner',hdr).CornerRadius=UDim.new(0,10)
local ttl=Instance.new('TextLabel',hdr); ttl.BackgroundTransparency=1; ttl.Size=UDim2.new(1,-44,1,0); ttl.Position=UDim2.new(0,12,0,0)
ttl.Font=Enum.Font.GothamBold; ttl.TextSize=14; ttl.TextColor3=Color3.fromRGB(245,245,250); ttl.TextXAlignment=Enum.TextXAlignment.Left; ttl.Text='HS HUB · AutoSpawn v11'
local xB=Instance.new('TextButton',hdr); xB.BackgroundTransparency=1; xB.Size=UDim2.new(0,34,0,34); xB.Position=UDim2.new(1,-38,0,2)
xB.Font=Enum.Font.GothamBold; xB.TextSize=20; xB.TextColor3=Color3.fromRGB(255,255,255); xB.Text='×'
xB.MouseButton1Click:Connect(function() AUTO=false; gui:Destroy(); shared.__HSHub_AutoSpawn=nil end)

local function mkBtn(lbl,col,x,w,y)
    local b=Instance.new('TextButton',frame); b.Size=UDim2.new(0,w,0,28); b.Position=UDim2.new(0,x,0,y)
    b.BackgroundColor3=col; b.BorderSizePixel=0; b.Font=Enum.Font.GothamBold; b.TextSize=12; b.TextColor3=Color3.fromRGB(245,245,250); b.Text=lbl
    Instance.new('UICorner',b).CornerRadius=UDim.new(0,6); return b
end

-- row 1
local readBtn = mkBtn('🔍 Read',        Color3.fromRGB(60,130,190),  10,110, 46)
local tapMain = mkBtn('👆 TAP Mainkan', Color3.fromRGB(170,120,60), 126,130, 46)
local playBtn = mkBtn('▶ TEST Play',    Color3.fromRGB(60,160,110),  262,108, 46)
-- row 2
local s1      = mkBtn('Tap S1', Color3.fromRGB(70,110,160),  10, 84, 80)
local s2      = mkBtn('Tap S2', Color3.fromRGB(70,110,160), 100, 84, 80)
local s3      = mkBtn('Tap S3', Color3.fromRGB(70,110,160), 190, 84, 80)
local saveBtn = mkBtn('💾 Save Log', Color3.fromRGB(90,100,130), 280, 90, 80)

-- ── slot toggle section ──────────────────────────────────────────
local sepLabel=Instance.new('TextLabel',frame)
sepLabel.Size=UDim2.new(1,-20,0,14); sepLabel.Position=UDim2.new(0,10,0,115)
sepLabel.BackgroundTransparency=1; sepLabel.Font=Enum.Font.GothamBold; sepLabel.TextSize=11
sepLabel.TextColor3=Color3.fromRGB(160,140,200); sepLabel.TextXAlignment=Enum.TextXAlignment.Left
sepLabel.Text='AUTO slot toggles  (tap to enable/disable):'

local TW=math.floor((FRAME_W-26)/3)  -- toggle button width (~118px)
local function refreshToggleBtn(n)
    local b=slotToggleBtns[n]; if not b then return end
    local on=slotEnabled[n]
    b.BackgroundColor3=on and Color3.fromRGB(55,140,90) or Color3.fromRGB(100,40,40)
    local nm='Slot'..n
    for _,s in ipairs(lastSlotData) do if s.n==n then nm=s.name:sub(1,10); break end end
    b.Text=('S%d  %s\n%s'):format(n, nm, on and '✓ ON' or '✗ OFF')
end

for i=1,3 do
    local b=Instance.new('TextButton',frame)
    b.Size=UDim2.new(0,TW,0,42); b.Position=UDim2.new(0,10+(i-1)*(TW+3),0,133)
    b.BackgroundColor3=Color3.fromRGB(55,140,90); b.BorderSizePixel=0
    b.Font=Enum.Font.GothamBold; b.TextSize=11; b.TextColor3=Color3.fromRGB(245,245,250)
    b.Text=('S%d  Slot%d\n✓ ON'):format(i,i); b.TextWrapped=true
    Instance.new('UICorner',b).CornerRadius=UDim.new(0,6)
    slotToggleBtns[i]=b
    local idx=i
    b.MouseButton1Click:Connect(function()
        slotEnabled[idx]=not slotEnabled[idx]
        refreshToggleBtn(idx)
        logFn(('Slot%d AUTO toggle: %s'):format(idx, slotEnabled[idx] and 'ON' or 'OFF'))
    end)
end

-- AUTO button
local autoBtn=mkBtn('AUTO: OFF', Color3.fromRGB(70,74,88), 10,360, 183)
autoBtn.MouseButton1Click:Connect(function()
    AUTO=not AUTO
    autoBtn.BackgroundColor3=AUTO and Color3.fromRGB(70,150,110) or Color3.fromRGB(70,74,88)
    autoBtn.Text='AUTO: '..(AUTO and 'ON' or 'OFF')
    logFn(AUTO and 'AUTO on' or 'AUTO off')
end)

-- log scroll
local scroll=Instance.new('ScrollingFrame',frame)
scroll.Size=UDim2.new(1,-18,0,220); scroll.Position=UDim2.new(0,9,0,218)
scroll.BackgroundColor3=Color3.fromRGB(11,13,19); scroll.BorderSizePixel=0
scroll.ScrollBarThickness=4; scroll.ScrollBarImageColor3=Color3.fromRGB(140,100,220)
Instance.new('UICorner',scroll).CornerRadius=UDim.new(0,6)
local lo=Instance.new('UIListLayout',scroll); lo.Padding=UDim.new(0,2); lo.SortOrder=Enum.SortOrder.LayoutOrder
local pd=Instance.new('UIPadding',scroll); pd.PaddingTop=UDim.new(0,4); pd.PaddingLeft=UDim.new(0,6)

logFn=function(txt,isErr)
    logLines[#logLines+1]=txt
    local lb=Instance.new('TextLabel',scroll); lb.BackgroundTransparency=1
    lb.Size=UDim2.new(1,-12,0,16); lb.LayoutOrder=#scroll:GetChildren()
    lb.Font=Enum.Font.Code; lb.TextSize=12
    lb.TextColor3=isErr and Color3.fromRGB(255,140,140) or Color3.fromRGB(190,215,235)
    lb.TextXAlignment=Enum.TextXAlignment.Left; lb.TextTruncate=Enum.TextTruncate.AtEnd; lb.Text=txt
    scroll.CanvasSize=UDim2.new(0,0,0,#scroll:GetChildren()*18)
    scroll.CanvasPosition=Vector2.new(0,scroll.CanvasSize.Y.Offset)
end
logFn(('v11. %s VIM=%s inset.Y=%d'):format(IS_PC and 'PC' or 'MOBILE',tostring(VIM~=nil),math.floor(GUI_INSET.Y)))
logFn('Read first → names fill the toggles.')
logFn('Toggle S1/S2/S3 = which slots AUTO will use.')

-- ── button handlers ───────────────────────────────────────────────
readBtn.MouseButton1Click:Connect(function()
    local slots=readSlots(); lastSlotData=slots
    logFn(('── slots:%d inGame=%s PlayBtn=%s ──'):format(#slots,tostring(inGame()),findPlayButton() and 'found' or 'MISSING'), Color3.fromRGB(120,210,255))
    for _,s in ipairs(slots) do
        logFn(('  %s %s %s'):format(s.slot,s.name,s.dead and 'DEAD' or 'ALIVE'),
              s.dead and Color3.fromRGB(255,140,140) or Color3.fromRGB(150,230,150))
    end
    for i=1,3 do refreshToggleBtn(i) end  -- fill creature names into toggle buttons
end)

local function testSlot(n)
    local s=slotByN(n)
    if s and s.card then tapButton(s.card:FindFirstChild('ViewButton') or s.card,'Slot'..n..'('..s.name..')')
    else logFn('slot '..n..' not found',true) end
end
s1.MouseButton1Click:Connect(function() task.spawn(function() testSlot(1) end) end)
s2.MouseButton1Click:Connect(function() task.spawn(function() testSlot(2) end) end)
s3.MouseButton1Click:Connect(function() task.spawn(function() testSlot(3) end) end)

local ACTION_TEXTS={Mainkan=1,MAINKAN=1,Play=1,PLAY=1,Sunting=1,SUNTING=1,Edit=1,EDIT=1,
    ['Mulai ulang']=1,Menghidupkan=1,['Menghidupkan kembali']=1,Restart=1,Revive=1}
local function btnText(d)
    if d:IsA('TextButton') and ACTION_TEXTS[d.Text] then return d.Text end
    for _,c in ipairs(d:GetDescendants()) do if c:IsA('TextLabel') and ACTION_TEXTS[c.Text] then return c.Text end end
    return nil
end
tapMain.MouseButton1Click:Connect(function() task.spawn(function()
    local cands={}
    local roots={PG}; pcall(function() if gethui then roots[#roots+1]=gethui() end end)
    for _,root in ipairs(roots) do
        for _,sg in ipairs(root:GetChildren()) do
            if sg:IsA('ScreenGui') then
                pcall(function() for _,d in ipairs(sg:GetDescendants()) do
                    if (d:IsA('TextButton') or d:IsA('ImageButton')) and visibleChain(d) then
                        local txt=btnText(d)
                        if txt then
                            local x,y=centerOf(d); local az=d.AbsoluteSize
                            cands[#cands+1]={gui=sg.Name,name=d.Name,x=x,y=y,w=az.X,h=az.Y,txt=txt}
                        end
                    end
                end end)
            end
        end
    end
    logFn(('── ACTION buttons: %d ──'):format(#cands), Color3.fromRGB(120,210,255))
    if #cands==0 then logFn('  NONE — select a creature first',true) end
    for _,c in ipairs(cands) do
        logFn(('  %s.%s [%s] @(%d,%d) %dx%d'):format(c.gui,c.name,c.txt,math.floor(c.x),math.floor(c.y),math.floor(c.w),math.floor(c.h)))
    end
end) end)

playBtn.MouseButton1Click:Connect(function() task.spawn(playAlive) end)
saveBtn.MouseButton1Click:Connect(function()
    local txt=table.concat(logLines,'\n'); local s=false
    pcall(function() if writefile then writefile('HSHub_AutoSpawn_log.txt',txt); s=true end end)
    pcall(function() if setclipboard then setclipboard(txt) elseif toclipboard then toclipboard(txt) end end)
    logFn(s and 'saved log.txt + clipboard' or 'clipboard only')
end)
