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
local practice=dofile(root .. 'practice.lua')(root)
local practiceRules=dofile(root .. 'practice_rules.lua')
local roles=dofile(root .. 'roles.lua')(root)
local state, controller, clock
local resetPending,queuedStart
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
    return roles.resolve(a)
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
    for _,class in ipairs({'WnBLine_BP_C','RnGLine_BP_C'}) do
        for _,line in ipairs(FindAllOf(class) or {}) do
            if valid(line) then retiredBlue[key(line)]=true end
        end
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
local function selected(stage)
    local value=practice.choice(stage)
    return value=='random' and practiceRules.random or value
end
local function transferDelta(plan)
    if not plan.swap then return end
    local from,to=plan.swap.from,plan.swap.to
    local fromKey,toKey=key(from),key(to)
    local function mapped(actor)
        if not valid(actor) then return actor end
        local k=key(actor)
        return k==fromKey and to or (k==toKey and from or actor)
    end
    local roster=array(controller.TeammatesRef)
    for i,actor in ipairs(roster) do roster[i]=mapped(actor) end
    setArray(controller.TeammatesRef,roster)
    setArray(controller.TeammatesRef_temp_R,plan.red)
    setArray(controller.TeammatesRef_temp_B,plan.blue)
    for _,class in ipairs({'WnBLine_BP_C','RnGLine_BP_C'}) do
        for _,line in ipairs(FindAllOf(class) or {}) do
            if valid(line) and not retiredBlue[key(line)] then
                line.Target_start=mapped(line.Target_start)
                line.Target_end=mapped(line.Target_end)
            end
        end
    end
    for _,entry in ipairs(plan.worlds) do
        local actor=entry.actor
        actor:RemoveBUFF(0);actor:RemoveBUFF(1)
        actor.HelloWorld=entry.world
        if entry.world>0 then actor:GetBUFF(40,entry.world-1) end
    end
    note('CHOICE delta='..practice.choice('delta')..' player='..roles.current())
end
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
    local choice=selected('delta')
    if practice.smallMonitor() and choice==practiceRules.random then
        -- The native small monitor can only target a blue-tether player.
        -- Keep the player's random blue slot if already there; otherwise choose
        -- one of the four blue slots and transfer its full mechanic assignment.
        local playerOnBlue=false
        for _,actor in ipairs(blue) do if role(actor)==roles.current() then playerOnBlue=true;break end end
        if not playerOnBlue then
            local blueMarks={5,6,8,9}
            choice=blueMarks[math.random(#blueMarks)]
        end
    end
    local plan=practiceRules.delta(rules,red,blue,roles.current(),choice,role,function(o)return o.HelloWorld end,config.d3_role)
    transferDelta(plan)
    local a=plan.assignment
    if not practice.idleMarks() then
        for _,m in ipairs(a.marks) do if m[2]==8 or m[2]==9 then m[2]=-1 end end
    end
    local seen={}
    for _,m in ipairs(a.marks) do assert(not seen[key(m[1])], 'Duplicate party member');seen[key(m[1])]=true end
    local front={};controller.Positions_line_R:ForEach(function(i,w) front[i]=vec(w:get()) end)
    local oldStack={};controller.Positions_linebreak_R:ForEach(function(i,w) oldStack[i]=vec(w:get()) end)
    local function midpoint(u,v)return {X=(u.X+v.X)/2,Y=(u.Y+v.Y)/2,Z=u.Z}end
    local right,left=midpoint(front[1],front[2]),midpoint(front[3],front[4])
    runId=runId+1
    local previousMonitors={}
    for _,monitor in ipairs(FindAllOf('MonitorBP_C') or {}) do
        if valid(monitor) then previousMonitors[key(monitor)]=true end
    end
    state={id=runId, start=clock:GetTimeSeconds(controller), assignment=a, front=front,
        oldStack=oldStack,stack={right,right,left,left},blueRepaired=blueRepaired,
        player=FindFirstOf('BP_PlayerCharacter_C'),smallMonitor=practice.smallMonitor(),previousMonitors=previousMonitors}
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
    if state.smallMonitor and t>=19 and t<25 and not state.smallMonitorAssigned and valid(state.player) and valid(controller.MonitorRef) then
        -- Both the controller and the spawned damage actor retain the native
        -- target. Change both while the actor is live, before the hit occurs.
        for _,monitor in ipairs(FindAllOf('MonitorBP_C') or {}) do
            if valid(monitor) and not state.previousMonitors[key(monitor)] and valid(monitor.Target) and key(monitor.Target)==key(controller.MonitorRef) then
                local original=role(controller.MonitorRef)
                monitor.Target=state.player
                controller.MonitorRef=state.player
                state.smallMonitorAssigned=true
                note('SMALL MONITOR run='..state.id..' original='..original..' target='..role(state.player))
                break
            end
        end
    end
    if state.smallMonitor and t>=25 and not state.smallMonitorAssigned and not state.smallMonitorError then
        state.smallMonitorError=true;note('SMALL MONITOR ERROR: native target was not available')
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
note('LOADED; P5 practice selection and reset')
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
    queuedStart=nil
    if resetPending then resetPending.ready=true;resetPending.readyAt=os.time() end
end)
local phaseHandlers={
    delta={'1stController_C','BndEvt__PlayerHUD_Skill_2_K2Node_ComponentBoundEvent_4_OnButtonClickedEvent__DelegateSignature'},
    sigma={'2ndController_C','BndEvt__PlayerHUD_Skill_3_K2Node_ComponentBoundEvent_6_OnButtonClickedEvent__DelegateSignature'},
    omega={'3rdController_C','BndEvt__PlayerHUD_Skill_4_K2Node_ComponentBoundEvent_7_OnButtonClickedEvent__DelegateSignature'},
}
local function inP5()
    return valid(FindFirstOf('1stController_C')) and valid(FindFirstOf('2ndController_C'))
end
local function startPractice(phase)
    local handler=assert(phaseHandlers[phase], 'Invalid practice phase')
    local player=FindFirstOf('BP_PlayerCharacter_C')
    local mechanic=FindFirstOf(handler[1])
    local party=roles.actors()
    assert(inP5() and valid(player) and valid(player.PlayerUIRef) and valid(mechanic),'P5 practice arena is unavailable')
    assert(party and #party==8,'Practice party is unavailable')
    assert(roles.isReady() and roles.role(player)==roles.current(),'Practice party role setup is not ready')
    assert(not roles.isBusy(),'A mechanic is already active')
    assert(valid(mechanic.PlayerRef) and key(mechanic.PlayerRef)==key(player),'Native controller has not finished initializing')
    -- Execute the original HUD event so it also performs the native player,
    -- controller and UI setup. The source button is no longer in the bar.
    local hud=player.PlayerUIRef
    hud[handler[2]](hud)
    if not mechanic.IsActive then
        -- The HUD event sets this flag before broadcasting to the native
        -- controller. Do not leave the next manual attempt permanently blocked.
        if not roles.isBusy() then player.isCampActive=false end
        error('Native practice did not start')
    end
    assert(player.isCampActive,'Native practice did not activate the player')
    practice.markStarted(phase)
    note('START phase='..phase)
end
local function resetPractice(mode)
    local player=FindFirstOf('BP_PlayerCharacter_C')
    if not inP5() or not valid(player) then return end
    local gameplay=StaticFindObject('/Script/Engine.Default__GameplayStatics')
    local level=gameplay:GetCurrentLevelName(player,true):ToString()
    local party=roles.actors()
    local resume
    if mode=='restart' then resume=roles.isBusy() and practice.lastPhase() or practice.selectedPhase() end
    -- A native wipe can reload the map and remove the AI before the user
    -- presses F5. A recorded run started with eight actors, so restore them
    -- for a restart even when the current post-wipe roster is empty.
    resetPending={party=(party and #party==8) or resume~=nil,started=os.time(),level=level,resume=resume}
    note('RESET level='..level)
    -- Map travel cancels all native latent timers, damage actors and AI tasks.
    -- InitGameState drops old wrappers while retaining practice preferences.
    gameplay:OpenLevel(player,FName(level),true,'')
end
local function restoreParty()
    if not resetPending then return end
    if not resetPending.ready then
        if os.time()-resetPending.started>30 then
            note('RESET ERROR timed out waiting for level travel')
            resetPending=nil;practice.setPanelOpen(true)
        end
        return
    end
    if not resetPending.party then resetPending=nil;practice.setPanelOpen(true);return end
    local player=FindFirstOf('BP_PlayerCharacter_C')
    if not valid(player)or not valid(player.PlayerUIRef)then
        if os.time()-resetPending.readyAt>30 then
            note('RESET ERROR timed out waiting for the preparation screen')
            resetPending=nil;practice.setPanelOpen(true)
        end
        return
    end
    local gameplay=StaticFindObject('/Script/Engine.Default__GameplayStatics')
    if not inP5() or gameplay:GetCurrentLevelName(player,true):ToString()~=resetPending.level then
        resetPending=nil;practice.setPanelOpen(true);return
    end
    -- The native Add AI action creates the same seven party slots as the
    -- preparation screen. Calling it once avoids a second manual setup step.
    if not resetPending.aiRequested then
        player.PlayerUIRef['BndEvt__PlayerHUD_Button_AddAI_K2Node_ComponentBoundEvent_21_OnButtonClickedEvent__DelegateSignature'](player.PlayerUIRef)
        resetPending.aiRequested=true
    elseif os.time()-resetPending.readyAt>30 and (not roles.actors() or not roles.isReady() or roles.role(player)~=roles.current()) then
        note('RESET ERROR timed out waiting for the party')
        resetPending=nil;practice.setPanelOpen(true)
    end
end
local verificationStarted=false
LoopInGameThreadWithDelay(config.poll_ms,function()
        local restored,restoreError=pcall(restoreParty)
        if not restored then resetPending=nil;practice.setPanelOpen(true);note('RESET PARTY ERROR '..tostring(restoreError))end
        local rolesOK,rolesError=pcall(roles.tick)
        if not rolesOK then note('ROLES ERROR '..tostring(rolesError))end
        local resetMode=practice.consumeReset()
        local requestedPhase=practice.consumeStart()
        if resetMode then
            queuedStart=nil;practice.setStarting(false)
            if resetPending then return end
            local ok,err=pcall(resetPractice,resetMode)
            if not ok then resetPending=nil;practice.setPanelOpen(true);note('RESET ERROR '..tostring(err))end
            return
        end
        local player=FindFirstOf('BP_PlayerCharacter_C')
        if resetPending and resetPending.ready and resetPending.aiRequested and rolesOK and valid(player) and
            roles.isReady() and roles.actors() and #roles.actors()==8 and roles.role(player)==roles.current() then
            local phase=resetPending.resume
            resetPending=nil
            if phase then queuedStart={phase=phase,started=os.time()};practice.setStarting(true)
            else practice.setPanelOpen(true)end
        elseif not resetPending and requestedPhase then
            queuedStart={phase=requestedPhase,started=os.time()};practice.setStarting(true)
        end
        if queuedStart and not resetPending then
            if not inP5() then queuedStart=nil;practice.setStarting(false)
            elseif os.time()-queuedStart.started>30 then
                queuedStart=nil;practice.setStarting(false);practice.setPanelOpen(true);note('START ERROR timed out waiting for the native controller')
            elseif valid(player) and rolesOK and roles.isReady() and not roles.isBusy() then
                local handler=phaseHandlers[queuedStart.phase]
                local mechanic=handler and FindFirstOf(handler[1])
                -- PlayerRef is populated by the native controller only after
                -- its BeginPlay has bound the stage-start delegate. Roster/UI
                -- initialization can complete more than a second earlier.
                if valid(mechanic) and valid(mechanic.PlayerRef) and key(mechanic.PlayerRef)==key(player) then
                    local phase=queuedStart.phase;queuedStart=nil;practice.setStarting(false)
                    local ok,err=pcall(startPractice,phase)
                    if not ok then practice.setPanelOpen(true);note('START ERROR '..tostring(err))end
                end
            end
        end
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


