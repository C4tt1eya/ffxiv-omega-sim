-- Sigma shares Delta's game-thread scheduler. No background UObject access.
return function(root,config)
 local FindFirstOf=MolingFindActor
 local R=dofile(root..'sigma_rules.lua')
 local P=dofile(root..'practice_rules.lua')
 local practice=assert(_G.MolingPractice)
 local function choice(stage)local value=practice.choice(stage);return value=='random'and P.random or value end
 local f=io.open(root..'../sigma.log','w')
 local function note(s)print('[MolingSigma] '..s..'\n');if f then f:write(s..'\n');f:flush()end end
 local function valid(a)return a and a:IsValid()end
 local function key(a)return a:GetFullName()end
 local function arr(a)local t={};a:ForEach(function(i,w)t[i]=w:get()end);return t end
 local function put(a,t)assert(a:GetArrayNum()==#t,'Unexpected Sigma array size');for i,v in ipairs(t)do a[i]=v end end
 local function role(a)
  return assert(_G.MolingRoles,'Role resolver unavailable').resolve(a)
 end
 local function move(a,v)if a:GetClass():GetFullName():find('/AI/',1,true)then a['移动'](a,v)end end
 local function actors(slots)local t={};for i,m in ipairs(slots)do t[i]=m.actor end;return t end
 local function marked(plan)for id,m in pairs(plan.byMark)do if m.actor.MarkIndex~=id then m.actor:Server_SetMark(id)end end end
 local c,p,gs,s;local id=0;local previousEnergy,lastDelta;local roleGeneration=-1
 local frontTargetClasses={'LianxianDM_BP_C','shanxingDM_BP_C','shanxingdmgBP_C'}
 local retiredTargets={}
 local function releaseFarTowers()
  if not s or not s.farTowerLines then return end
  for _,entry in ipairs(s.farTowerLines)do
   if valid(entry.actor)then
    -- EndSep can already have hidden/unregistered this line before the
    -- phase changes. Leave completed lines stopped; restore only live ones.
    entry.ended=not entry.actor.SplineMesh:IsVisible()
    if not entry.ended then entry.actor:SetActorTickEnabled(entry.wasTicking)end
    entry.restored=entry.ended or entry.actor:IsActorTickEnabled()==entry.wasTicking
   end
  end
  s.farTowerLines=nil
 end
 local function farTowers(t)
  if s.near or not s.towerPlan or t<30 or t>=32.6 then releaseFarTowers();return end
  if s.farTowerFailed then return end
  local ok,err=pcall(function()
   if not s.farTowerLines then
    local roster,seen,lines={},{},{}
    for _,m in ipairs(s.members)do roster[key(m.actor)]=m.shape end
    for _,a in ipairs(FindAllOf('FarLine_BP_C')or{})do
     if valid(a)and valid(a.Target_start)and valid(a.Target_end)and a.SplineMesh:IsVisible()then
      local x,y=key(a.Target_start),key(a.Target_end)
      if roster[x]and roster[x]==roster[y]then
       assert(x~=y and not seen[x]and not seen[y],'Duplicate far tower pair')
       seen[x]=true;seen[y]=true;lines[#lines+1]={actor=a,wasTicking=a:IsActorTickEnabled()}
      end
     end
    end
    if #lines~=4 then return end
    s.farTowerBaseTick=StaticFindObject('/Game/MainScene/Omega_P5/2ndCampaign/BaseLine_BP.BaseLine_BP_C:ReceiveTick')
    assert(valid(s.farTowerBaseTick),'Missing native line visual tick')
    s.farTowerLines=lines;s.farTowerLast=t
    -- The child tick recomputes the hard-coded distance every frame. Suspend
    -- only that tick while applying the tower rule; retain the parent's
    -- spline/material updates and the native damage/lifetime timers.
    for _,entry in ipairs(lines)do entry.actor:SetActorTickEnabled(false)end
    note('FAR TOWER distance='..R.farTowerMinimum..' pairs='..#lines)
   end
   local dt=t-s.farTowerLast;s.farTowerLast=t
   for _,entry in ipairs(s.farTowerLines)do
    local a=entry.actor
    if valid(a)and valid(a.Target_start)and valid(a.Target_end)then
     local safe=R.farTowerSafe(a.Target_start:K2_GetActorLocation(),a.Target_end:K2_GetActorLocation())
     a.Safe=safe;a.Target_start.HurtHeavily=not safe;a.Target_end.HurtHeavily=not safe
     s.farTowerBaseTick(a,dt)
    end
   end
  end)
  if not ok then releaseFarTowers();s.farTowerFailed=true;note('FAR TOWER ERROR '..tostring(err))end
 end
 local function stamp(plan)local t={};for _,r in ipairs(R.order)do for k,m in pairs(plan.byMark)do if m.role==r then t[#t+1]=r..'='..k end end end;return table.concat(t,' ')end
 local function ui()
  if not valid(p)then return end
  local hud=p.PlayerUIRef;if not valid(hud)then return end
  hud['P5二运HW']:SetVisibility(0);hud['P5二运HW']:SetIsEnabled(false)
  hud['P5二运HWimg']:SetVisibility(1)
 end
 local function restoreBuffs(duration)
  for _,m in ipairs(s.members)do
   local a=m.actor
   for _,index in ipairs({0,1,2,3,4})do a:RemoveBUFF(index)end
   a.HelloWorld=m.world;a.DiveEnegy=m.energy
   if m.world>0 then a:GetBUFF(duration,m.world-1)end
   if m.energy>0 then a:GetBUFF(duration+6,m.energy+1)end
  end
 end
 local function begin()
  local roster=arr(c.TeammatesRef);if #roster~=8 then return end
  local members,shapes={},{}
  for _,a in ipairs(roster)do
   if a.MarkIndex<10 or a.MarkIndex>13 then return end
   local m={actor=a,role=role(a),shape=a.MarkIndex,world=0,energy=0}
   members[#members+1]=m;shapes[m.shape]=(shapes[m.shape]or 0)+1
  end
  for k=10,13 do if shapes[k]~=2 then return end end
  -- Worlds and practice energy are independent of Sony pair order. Select
  -- once here; never reroll these assignments when entering the HW phase.
  local function shuffled()
   local t={};for i,m in ipairs(members)do t[i]=m end
   for i=#t,2,-1 do local j=math.random(i);t[i],t[j]=t[j],t[i]end;return t
  end
  local worlds=shuffled();worlds[1].world=1;worlds[2].world=2
  for i,m in ipairs(shuffled())do m.energy=previousEnergy and previousEnergy[m.role]or(i<=6 and 1 or 0)end
  previousEnergy=nil
  local hw=P.hw(R,members,MolingRoles.current(),choice('sigma_hw'))
  members=hw.members
  id=id+1;s={id=id,start=gs:GetTimeSeconds(c),phase='front',members=members,hwPlan=hw.assignment,frontChoice=choice('sigma_front'),yaw=c.RotationTemp.Yaw,near=c.isNear,targets={},oldTowers={}}
  for _,cl in ipairs({'Tower_1_BP_C','Tower_2_BP_C'})do for _,a in ipairs(FindAllOf(cl)or{})do if valid(a)then s.oldTowers[key(a)]=true end end end
  -- Native Sony order is O X triangle square (verified SlateBrush assets).
  local priority={};for i,r in ipairs(R.order)do priority[r]=i end
  local ordered={};for i,m in ipairs(members)do ordered[i]=m end
  table.sort(ordered,function(a,b)return a.shape==b.shape and priority[a.role]<priority[b.role]or a.shape<b.shape end)
  put(c.TeammatesRef,actors(ordered))
  restoreBuffs(55)
  note('BEGIN run='..id..' near='..tostring(s.near)..' yaw='..s.yaw)
 end
 local function front(t)
  if t>=10 and not s.assignment then
   local n=0;for _,m in ipairs(s.members)do m.laser=m.actor.isLined;if m.laser then n=n+1 end end
   if n~=6 then return end
   local chosen=P.front(R,s.members,MolingRoles.current(),s.frontChoice)
   if chosen.swap then
    local from,to=chosen.swap.from.actor,chosen.swap.to.actor
    local fromKey,toKey=key(from),key(to)
    local function mapped(actor)
     if not valid(actor)then return actor end
     local k=key(actor);return k==fromKey and to or(k==toKey and from or actor)
    end
    -- Sony pairing and laser ownership move with the selected mechanic slot.
    -- Update live tethers as well as the native roster used by later towers.
    for _,class in ipairs({'NearLine_BP_C','FarLine_BP_C'})do
     for _,line in ipairs(FindAllOf(class)or{})do
      if valid(line)and valid(line.Target_start)and valid(line.Target_end)and line.SplineMesh:IsVisible()then
       line.Target_start=mapped(line.Target_start);line.Target_end=mapped(line.Target_end)
      end
     end
    end
    for _,class in ipairs(frontTargetClasses)do
     for _,actor in ipairs(FindAllOf(class)or{})do
      if valid(actor)and not retiredTargets[key(actor)]then actor.Target=mapped(actor.Target)end
     end
    end
    for _,m in ipairs(chosen.members)do m.actor.isLined=m.laser end
   end
   s.members=chosen.members;s.hwPlan=P.rebind(s.hwPlan,s.members)
   s.assignment=chosen.assignment;s.spread=R.spread(s.near,s.yaw)
   put(c.TeammatesRef,actors(s.assignment.slots));marked(s.assignment)
   note('FRONT '..stamp(s.assignment))
  end
  if not s.assignment then return end
  if t<12.1 then put(c.TeammatesRef,actors(s.assignment.slots))end
  if t>=12.1 and t<20.9 then
   put(c.Positions_temp,s.spread)
   if not s.spreadMoved then s.spreadMoved=true;for i,m in ipairs(s.assignment.slots)do move(m.actor,s.spread[i])end end
   s.targets={};for i,m in ipairs(s.assignment.slots)do s.targets[key(m.actor)]=s.spread[i]end
  end
  if t>=21 and not s.towers then
   local towers={}
   for cap=1,2 do for _,a in ipairs(FindAllOf('Tower_'..cap..'_BP_C')or{})do
    if valid(a)and not s.oldTowers[key(a)]then local v=a:K2_GetActorLocation();towers[#towers+1]={actor=a,capacity=cap,position={X=v.X,Y=v.Y,Z=120}}end
   end end
   if #towers==(s.near and 6 or 5)then
    table.sort(towers,function(a,b)return key(a.actor)<key(b.actor)end)
    s.towerPlan=R.towers(s.spread,towers,s.near);s.towers=towers
    note('TOWERS run='..s.id..' count='..#towers..'; adjacent double priority')
   end
  end
  if s.towerPlan and t>=22.1 and t<28 then
   local final={};for i,v in ipairs(s.towerPlan)do final[i]=v.position end
   put(c.Positions_temp,final)
   if not s.towerMoved then
    s.towerMoved=true;s.targets={}
    for i,m in ipairs(s.assignment.slots)do local v=s.towerPlan[i].preKnock;move(m.actor,v);s.targets[key(m.actor)]=v end
   end
   -- Native chooses its own pre-knock targets at 23 s; correct that command.
   if t>=23.15 and not s.corrected then s.corrected=true;for i,m in ipairs(s.assignment.slots)do move(m.actor,s.towerPlan[i].preKnock)end end
  elseif s.towerPlan and t>=30 and t<32.6 then
   s.targets={};for i,m in ipairs(s.assignment.slots)do local v=s.towerPlan[i].position;s.targets[key(m.actor)]=v;if not s.postKnock then move(m.actor,v)end end;s.postKnock=true
  end
  if t<32.6 then marked(s.assignment)end
  farTowers(t)
 end
 local function startHW()
  releaseFarTowers()
  local hwAssignment=P.rebind(s.hwPlan,s.members)
  s.phase='hw';s.hwStart=gs:GetTimeSeconds(c);s.targets={}
  -- Invoke the native mechanic, then replace its practice-only random setup in
  -- this same game-thread callback, before rendering or any delayed mechanic.
  local old={};for _,a in ipairs(FindAllOf('2nd_scenepart3_BP_C')or{})do if valid(a)then old[key(a)]=true end end
  c['2ndHW'](c);p.isCampActive=true
  for _,a in ipairs(FindAllOf('2nd_scenepart3_BP_C')or{})do if valid(a)and not old[key(a)]then s.hwScene=a end end
  restoreBuffs(22)
  s.hw=hwAssignment;s.hwYaw=c.RotationTemp.Yaw;s.hwClockwise=c.Clockwise
  put(c.TeammatesRef,actors(s.hw.slots))
  for _,m in ipairs(s.members)do m.actor:ClearMark();m.actor.UMG_Marking:SetHiddenInGame(true,true)end
  note('HW CONTINUE run='..s.id..' yaw='..s.hwYaw..' CW='..s.hwClockwise..' '..stamp(s.hw)..' omega='..(s.hwScene and key(s.hwScene.OmegaRef)or'?'))
 end
 local function hw(t)
  if t>=5.25 and not s.hwRanked then
   -- Let the native delayed sorter finish traversing its own array. Replacing
   -- that array between its iterations makes it count the same actor twice.
   s.hwRanked=true;put(c.TeammatesRef,actors(s.hw.slots))
   for _,m in ipairs(s.members)do m.actor.UMG_Marking:SetHiddenInGame(false,true)end
  end
  if t>=6.15 and not s.hwReady then
   s.hwReady=true;put(c.TeammatesRef,actors(s.hw.slots))
   s.worldTargets=R.worldPositions(s.hwYaw,s.hwClockwise)
   local positions={};for i,m in ipairs(s.hw.slots)do for mark,mm in pairs(s.hw.byMark)do if m==mm then positions[i]=s.worldTargets[mark]end end end
   put(c.Positions_temp,positions)
   local beginPos=arr(c.Positions_HWbegin_temp);s.targets={}
   for k,m in pairs(s.hw.byMark)do
    local v=beginPos[(k==0 or k==8 or k==9)and 1 or 2]
    s.targets[key(m.actor)]={X=v.X,Y=v.Y,Z=120};move(m.actor,s.targets[key(m.actor)])
   end
  end
  if t>=13 and not s.womanResolved then
   s.womanResolved=true
   if s.hwScene and key(s.hwScene.OmegaRef):find('OmegaF_BP_mid_2nd_C',1,true)then
    -- Mid-safe / wings: wait for the rotating laser to clear the centreline,
    -- then step in before the 14.5-second wing snapshot. Cross keeps the sides.
    for k,m in pairs(s.hw.byMark)do
     local y=(k==0 or k==8 or k==9)and 1580 or -1580
     local v=R.rotate({X=0,Y=y},s.hwYaw);s.targets[key(m.actor)]=v;move(m.actor,v)
    end
    note('WINGS run='..s.id..'; centreline after laser turns')
   end
  end
  if t>=15.15 and not s.worldMoved then
   s.worldMoved=true;s.targets={}
   for k,m in pairs(s.hw.byMark)do
    local v=s.worldTargets[k]
    -- Far world follows the outside of the turning laser before stepping in.
    -- A straight diagonal to its inner drop point clips the final laser ticks.
    if k==5 then v=R.radial(v,1700)end
    s.targets[key(m.actor)]=v;move(m.actor,v)
   end
   note('HW SPREAD run='..s.id)
  end
  if t>=19.15 and not s.farIn then
   s.farIn=true;local a=s.hw.byMark[5].actor;local v=s.worldTargets[5]
   s.targets[key(a)]=v;move(a,v)
  end
  if t>=5.25 and t<27.5 then marked(s.hw)end
 end
 local function cleanup()
  if not s then return end
  releaseFarTowers()
  for _,class in ipairs(frontTargetClasses)do
   for _,actor in ipairs(FindAllOf(class)or{})do if valid(actor)then retiredTargets[key(actor)]=true end end
  end
  for _,m in ipairs(s.members)do if valid(m.actor)then m.actor:ClearMark();m.actor.UMG_Marking:SetHiddenInGame(false,true)end end
  note('END run='..s.id);s=nil
 end
 local function tick()
  if not valid(c)then cleanup();previousEnergy=nil;lastDelta=nil;c=FindFirstOf('2ndController_C');p=FindFirstOf('BP_PlayerCharacter_C');if not valid(c)or not valid(p)then return end;gs=StaticFindObject('/Script/Engine.Default__GameplayStatics')end
  ui()
  if _G.MolingRoles and roleGeneration~=MolingRoles.generation then roleGeneration=MolingRoles.generation;previousEnergy=nil;lastDelta=nil end
  local d=_G.MolingDelta and MolingDelta.getState()
  if d and d~=lastDelta then lastDelta=d;previousEnergy=nil end
  if d and gs:GetTimeSeconds(c)-d.start>=40 then
   local snapshot,total,normal={},0,true
   for _,m in ipairs(d.assignment.marks)do local energy=m[1].DiveEnegy;snapshot[role(m[1])]=energy;total=total+energy;if energy~=0 and energy~=1 then normal=false end end
   -- Capture the completed six HW applications, not a partly resolved chain
   -- or the zeroed fields written by native end/reset.
   if total==6 and normal then previousEnergy=snapshot end
  end
  if not s then if c.IsActive then begin()end;return end
  for _,m in ipairs(s.members)do if not valid(m.actor)then cleanup();return end end
  local now=gs:GetTimeSeconds(c)
  if s.phase=='front'then
   local t=now-s.start
   if not c.IsActive then
    if t>=32 and t<36 and s.towerPlan then startHW()else cleanup()end
   else front(t)end
  else
   if not c.IsActive then cleanup()else hw(now-s.hwStart)end
  end
 end
 note('LOADED v0.9 Sigma; tower-only far distance tolerance; native tower damage')
 RegisterInitGameStatePreHook(function()
  s=nil;c=nil;p=nil;gs=nil;previousEnergy=nil;lastDelta=nil;retiredTargets={}
 end)
 _G.MolingSigma={getState=function()return s end,rules=R}
 return tick
end
