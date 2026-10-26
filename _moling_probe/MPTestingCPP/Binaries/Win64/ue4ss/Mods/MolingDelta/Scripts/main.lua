-- Lua's narrow-path fopen cannot open an absolute UTF-8 Windows path containing
-- Chinese characters. The launcher sets Win64 as CWD; also support bootstrap CWD.
local root
for _,base in ipairs({'ue4ss/Mods/','MPTestingCPP/Binaries/Win64/ue4ss/Mods/','Binaries/Win64/ue4ss/Mods/'}) do
    local candidate=base..'MolingDelta/Scripts/'
    local file=io.open(candidate..'config.lua','r')
    if file then file:close();root=candidate;break end
end
assert(root,'MolingDelta: launch using the supplied .cmd file')
_G.MolingFindActor=dofile(root .. 'find_actor.lua')
local FindFirstOf=MolingFindActor
local config = dofile(root .. 'config.lua')
local rules = dofile(root .. 'rules.lua')
if not config.enabled then return end
local roles=dofile(root .. 'roles.lua')(root)
local state, controller, clock
local retiredBlue={}
local log = io.open(root .. '../delta.log', 'w')
local function note(s)
    local line = '[MolingDelta] ' .. s
    print(line .. '\n')
    if log then log:write(line .. '\n'); log:flush() end
end
local function valid(a) return a and a:IsValid() end
local function key(a) return a:GetFullName() end
local function vec(v) return {X=v.X, Y=v.Y, Z=v.Z} end
local function array(a)
    local t={}; a:ForEach(function(i,w) t[i]=w:get() end); return t
end
local function setArray(a, values)
    assert(a:GetArrayNum() == #values, 'Unexpected array length')
    for i,v in ipairs(values) do a[i]=v end
end
local function role(a)
    local chosen=roles.role(a);if chosen then return chosen end
    local r=a:GetClass():GetFullName():match('NPC_(%w+)_BP_C')
    if r then return r end
    -- The local player occupies whichever NPC slot is absent.
    for _,r2 in ipairs({'MT','ST','H1','H2','D1','D2','D3','D4'}) do
        if not valid(FindFirstOf('NPC_'..r2..'_BP_C')) then return r2 end
    end
    return a.Name:ToString()
end
local function move(a, destination)
    if a:GetClass():GetFullName():find('/AI/',1,true) then a['移动'](a,destination) end
end
local function mark(a,id)
    if id<0 then a:ClearMark() else a:Server_SetMark(id) end
end
local function cleanup()
    if not state then return end
    -- Native reset hides the completed line actors but keeps them alive.
    -- Remember their identities so the next pull cannot select stale lines.
    for _,line in ipairs(FindAllOf('WnBLine_BP_C') or {}) do
        if valid(line) then retiredBlue[key(line)]=true end
    end
    -- Native end/reset already restores its unrotated coordinate templates.
    -- Writing this run's rotated snapshots back here corrupts the next pull's
    -- frame and makes AI cross the arena to reach otherwise correct arms.
    for _,m in ipairs(state.assignment.marks) do
        if valid(m[1]) and m[1].MarkIndex == m[2] then m[1]:ClearMark() end
    end
    note('END run='..state.id)
    state=nil
end
local runId=0
local function prepareBlue(blue)
    local slots,plan=rules.blueSlots(blue,function(o)return o.HelloWorld end)
    local indices={};for i,a in ipairs(blue) do indices[key(a)]=i end
    local lines,seen={},{}
    for _,line in ipairs(FindAllOf('WnBLine_BP_C') or {}) do
        if valid(line) and not retiredBlue[key(line)] and valid(line.Target_start) and valid(line.Target_end) then
            local i,j=indices[key(line.Target_start)],indices[key(line.Target_end)]
            if i and j then
                assert(math.abs(i-j)==2,'Unexpected initial blue tether pairing')
                assert(not seen[i] and not seen[j],'Duplicate blue tether endpoint')
                seen[i],seen[j]=true,true
                lines[#lines+1]={actor=line,first=i,last=j}
            end
        end
    end
    -- Wait until native Blueprint has created both real tether actors.
    if #lines~=2 then return end
    if plan.changed then
        -- Native later phases also read the master roster. Preserve its other
        -- entries and replace these two blue slots consistently.
        local roster=array(controller.TeammatesRef)
        for i,actor in ipairs(roster) do
            local slot=indices[key(actor)]
            if slot then roster[i]=slots[slot] end
        end
        setArray(controller.TeammatesRef,roster)
        setArray(controller.TeammatesRef_temp_B,slots)
        for _,line in ipairs(lines) do
            line.actor.Target_start=slots[line.first]
            line.actor.Target_end=slots[line.last]
        end
        note('BLUE ORDER repaired='..tostring(plan.repaired)..' reordered='..tostring(plan.reordered)..'; bind1 inner/first, bind2 outer/second')
    end
    return slots,plan.repaired
end
local function begin()
    local red,blue=array(controller.TeammatesRef_temp_R),array(controller.TeammatesRef_temp_B)
    if #red~=4 or #blue~=4 then return end
    local blueRepaired
    blue,blueRepaired=prepareBlue(blue)
    if not blue then return end
    local a=rules.assign(red,blue,role,function(o)return o.HelloWorld end,config.d3_role,config.mark_idle_with_stop)
    local seen={}
    for _,m in ipairs(a.marks) do assert(not seen[key(m[1])], 'Duplicate party member');seen[key(m[1])]=true end
    local front={};controller.Positions_line_R:ForEach(function(i,w) front[i]=vec(w:get()) end)
    local oldStack={};controller.Positions_linebreak_R:ForEach(function(i,w) oldStack[i]=vec(w:get()) end)
    local function midpoint(u,v)return {X=(u.X+v.X)/2,Y=(u.Y+v.Y)/2,Z=u.Z}end
    local right,left=midpoint(front[1],front[2]),midpoint(front[3],front[4])
    runId=runId+1
    state={id=runId, start=clock:GetTimeSeconds(controller), assignment=a, front=front,
        oldStack=oldStack,stack={right,right,left,left},blueRepaired=blueRepaired,
        player=FindFirstOf('BP_PlayerCharacter_C')}
    setArray(controller.TeammatesRef_temp_R,rules.redSlots(a,false))
    -- Keep linked 1/2 inside and linked 3/4 outside on BOTH sides.
    setArray(controller.Positions_line_R,{front[2],front[1],front[3],front[4]})
    local s='BEGIN run='..runId..' half='..controller.HalfAoeL..' yaw='..controller.RotationTemp.Yaw
    for _,m in ipairs(a.marks) do mark(m[1],m[2]);s=s..' '..role(m[1])..'='..m[2] end
    note(s)
end
local function tick()
    if not valid(controller) then
        state=nil; retiredBlue={}; controller=FindFirstOf('1stController_C')
        if not valid(controller) then return end
        clock=StaticFindObject('/Script/Engine.Default__GameplayStatics')
    end
    if not controller.IsActive then cleanup();return end
    if not state then begin(); if not state then return end end
    for _,m in ipairs(state.assignment.marks) do
        if not valid(m[1]) then state=nil;controller=nil;return end
    end
    local t=clock:GetTimeSeconds(controller)-state.start
    local a=state.assignment
    -- Record real damage without changing HP, movement or mechanic timing.
    -- The player reference belongs to this attempt and is dropped on map load.
    if valid(state.player) then
        local hp=state.player.HP
        if state.playerHP~=hp then
            local v=state.player:K2_GetActorLocation()
            note(string.format('PLAYER HP run=%d t=%.3f role=%s mark=%d hp=%.0f previous=%s pos=%.0f,%.0f',
                state.id,t,roles.current(),state.player.MarkIndex,hp,tostring(state.playerHP),v.X,v.Y))
            state.playerHP=hp
        end
    end
    if t>=10.2 and not state.fists then
        state.fists=true
        local swap=a.attack[1].PunchID==a.attack[3].PunchID
        state.swap=swap
        setArray(controller.TeammatesRef_temp_R,rules.redSlots(a,swap))
        if swap then
            -- Only the outside green pair exchanges, as in the guide.
            move(a.attack[3],state.front[4]);move(a.attack[4],state.front[1])
        end
        note('FISTS run='..state.id..' swap34='..tostring(swap))
    end
    if t>=10.2 and t<12 then setArray(controller.TeammatesRef_temp_R,rules.redSlots(a,state.swap)) end
    if t>=12.2 and not state.stacked then
        state.stacked=true
        local slots=rules.redSlots(a,state.swap)
        setArray(controller.TeammatesRef_temp_R,slots)
        setArray(controller.Positions_linebreak_R,state.stack)
        for i,actor in ipairs(slots) do move(actor,state.stack[i]) end
        note('STACK run='..state.id)
    end
    if t>=19 and not state.oldLaser then
        -- Native red laser slots are outer-right, inner-right, inner-left,
        -- outer-left. Our red roster is inner-right, outer-right, inner-left,
        -- outer-left, so the first two destinations must exchange as well.
        -- Wait for the arms to compute their clockwise/counterclockwise points,
        -- then patch before the native 20-second move.
        local laser={};controller.Positions_laser_R:ForEach(function(i,w) laser[i]=vec(w:get()) end)
        if #laser==4 then
            state.oldLaser=laser
            local targets,adjusted=rules.armPositions(laser)
            state.armSpacingAdjusted=adjusted
            setArray(controller.Positions_laser_R,targets)
            note('ARMS run='..state.id..'; attack12 inner, attack34 outer; green-spacing='..tostring(adjusted))
        end
    end
    if t>=25 and t<26 and not state.monitor then
        -- The native 26 s return still indexes the old outer/inner order.
        -- Reassign its legal points from the completed arm positions, before
        -- that move. Use the intended arm point for the human so their manual
        -- movement cannot redirect the other red-tether players.
        local slots=rules.redSlots(a,state.swap)
        local origins,points={},{}
        controller.Positions_monitor_R:ForEach(function(i,w) points[i]=vec(w:get()) end)
        for i,actor in ipairs(slots) do
            origins[i]=vec(controller.Positions_laser_R[i])
            if actor:GetClass():GetFullName():find('/AI/',1,true) then
                origins[i]=vec(actor:K2_GetActorLocation())
            end
        end
        local targets,indices=rules.monitorPositions(origins,points)
        state.monitor={origins=origins,candidates=points,targets=targets,indices=indices}
        state.beforeShield={}
        for _,actor in ipairs(array(controller.TeammatesRef_temp_B)) do
            state.beforeShield[key(actor)]=actor.HurtHeavily
        end
        setArray(controller.Positions_monitor_R,targets)
        note('RETURN run='..state.id..' points='..table.concat(indices,','))
    end
    if t>=26 and t<29 and not state.blueMonitor and state.beforeShield then
        -- Beyond Defense marks its actual victim with HurtHeavily at 26 s.
        -- Identify that victim from the mechanic, not from a roster index
        -- that blue-tether repair or the native distance sort may have changed.
        local blue=array(controller.TeammatesRef_temp_B)
        local victims={}
        for _,actor in ipairs(blue) do
            if actor.HurtHeavily and not state.beforeShield[key(actor)] then victims[#victims+1]=actor end
        end
        if #victims==1 and valid(controller.MonitorRef) then
            local points={};controller.Positions_monitor_B_r:ForEach(function(i,w) points[i]=vec(w:get()) end)
            local positions=rules.blueMonitorPositions(points,controller.RotationTemp.Yaw)
            local victim,monitor=victims[1],controller.MonitorRef
            state.blueMonitor={victim=victim,monitor=monitor,positions=positions,targets={}}
            setArray(controller.Positions_monitor_B_r,positions)
            for _,actor in ipairs(blue) do
                local isolated=key(actor)==key(victim)
                local hasMonitor=key(actor)==key(monitor)
                local slot=hasMonitor and (isolated and 1 or 2) or (isolated and 3 or 4)
                local target=positions[slot]
                state.blueMonitor.targets[key(actor)]=target
                move(actor,target)
            end
            note('BLUE MONITOR run='..state.id..' isolated='..role(victim)..' television='..role(monitor)..'; beetle-side wait, monitor outside')
        end
    end
    if t>=37 and t<39 then
        local combined=array(controller.TeammatesRef_temp)
        if #combined==8 then
            setArray(controller.TeammatesRef_temp,rules.worldSlots(a))
            -- Native Blueprint reloads saved coordinates at 37 s. Patch its
            -- transformed output after that reload, before the 38 s move.
            setArray(controller.Positions_temp,rules.worldPositions(controller.HalfAoeL,controller.RotationTemp.Yaw))
            if not state.world then state.world=true;note('WORLD run='..state.id) end
        end
    end
    -- Reapply only on a mismatch; original resets cannot silently change the assignment.
    if t<49 then
        for _,m in ipairs(a.marks) do if m[1].MarkIndex~=m[2] then mark(m[1],m[2]) end end
    end
    if t>65 then cleanup() end
end
note('LOADED v0.10; Delta arm green-tether spacing + restart safety; idle stop markers='..tostring(config.mark_idle_with_stop))
-- Exposed only for the local verification harness; no player movement in normal use.
_G.MolingDelta={getState=function() return state end, rules=rules}
local sigmaTick=function()end
if config.sigma_enabled~=false then sigmaTick=dofile(root .. 'sigma.lua')(root,config)end
assert(loadfile(root .. 'omega/main.lua'))(root .. 'omega/')
-- InitGameState runs on each new level before the next gameplay tick.
-- Reset Lua state only: cleanup() would dereference the destroyed old world.
RegisterInitGameStatePreHook(function()
    state=nil;controller=nil;clock=nil;retiredBlue={}
    roles.resetWorld()
end)
local verificationStarted=false
LoopInGameThreadWithDelay(config.poll_ms,function()
        local rolesOK,rolesError=pcall(roles.tick)
        if not rolesOK then note('ROLES ERROR '..tostring(rolesError))end
        local sigmaOK,sigmaError=pcall(sigmaTick)
        if not sigmaOK then note('SIGMA ERROR '..tostring(sigmaError)) end
        local ok,err=pcall(tick)
        if not ok then note('ERROR '..tostring(err)) end
        if config.verification_script and valid(controller) and clock:GetTimeSeconds(controller)>3 and not verificationStarted then
            verificationStarted=true
            local good,why=pcall(dofile,config.verification_script)
            if not good then note('VERIFY ERROR '..tostring(why)) end
        end
end)


