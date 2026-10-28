-- Unified P5 Omega runtime; Delta/Sigma run in the same process.
local FindFirstOf=MolingFindActor
local root=...
assert(root,'Missing unified Omega script root')
local config=dofile(root..'config.lua')
local R=dofile(root..'omega_rules.lua')(dofile(root..'omega_source.lua'))
local nativeClones=dofile(root..'omega_native_rules.lua')
local tetherRules=dofile(root..'omega_tethers.lua')
local log=assert(io.open(root..'../../omega.log','w'))
local function note(v)log:write(v..'\n');log:flush();print('[MolingOmega] '..v..'\n')end
local function valid(a)return a and a:IsValid()end
local function key(a)return a:GetFullName()end
local function arr(a)local t={};a:ForEach(function(i,w)t[i]=w:get()end);return t end
local function put(a,t)assert(a:GetArrayNum()==#t,'Unexpected native array length');for i,v in ipairs(t)do a[i]=v end end
local function role(a)
 return assert(_G.MolingRoles,'Role resolver unavailable').resolve(a)
end
local function move(a,v)if a:GetClass():GetFullName():find('/AI/',1,true)then a['移动'](a,v)end end
local arena=R.frame({X=0,Y=0,Z=120},{X=0,Y=-1})
local c,p,gs,s;local run=0;local failed=false
local previousEnergy,lastSigma,lastDelta;local roleGeneration=-1
local function captureSigma()
 if _G.MolingRoles and roleGeneration~=MolingRoles.generation then roleGeneration=MolingRoles.generation;previousEnergy=nil;lastSigma=nil;lastDelta=nil end
 local delta=_G.MolingDelta and MolingDelta.getState()
 local sigma=_G.MolingSigma and MolingSigma.getState()
 if delta and delta~=lastDelta then lastDelta=delta;previousEnergy=nil end
 if sigma and sigma~=lastSigma then lastSigma=sigma;previousEnergy=nil end
 if not sigma or sigma.phase~='hw' or gs:GetTimeSeconds(c)-sigma.hwStart<25 then return end
 local values,actors,ones,twos={},{},0,0
 for _,m in ipairs(sigma.members)do
  if not valid(m.actor)then return end
  local e=m.actor.DiveEnegy
  values[m.role]=e;actors[m.role]=key(m.actor)
  if e==1 then ones=ones+1 elseif e==2 then twos=twos+1 else return end
 end
 -- Preserve a fully resolved Sigma, before the native reset clears energy.
 -- Failed/incomplete runs keep the existing standalone practice fallback.
 if ones==4 and twos==4 then previousEnergy={values=values,actors=actors}end
end
local function marksVisible(show)
 for _,a in pairs(s.actors)do if valid(a.UMG_Marking)then a.UMG_Marking:SetHiddenInGame(not show,true)end end
end
local function scenes()
 local out={};for _,a in ipairs(FindAllOf('3rd_scenepart3_BP_C')or{})do if valid(a)then out[key(a)]=true end end;return out
end
local function snapshot()
 local a=arr(c.TeammatesRef);assert(#a==8,'Incomplete party')
 local members,actors={},{}
 for i,v in ipairs(a)do local r=role(v);actors[r]=v;members[i]={role=r,first=0,second=0,energy=v.DiveEnegy}end
 return members,actors,a
end
local function shuffled(t)local out={};for i,v in ipairs(t)do out[i]=v end;for i=#out,2,-1 do local j=math.random(i);out[i],out[j]=out[j],out[i]end;return out end
local function restore(front)
 for _,m in ipairs(s.members)do
  local a=s.actors[m.role];for i=0,4 do a:RemoveBUFF(i)end
  a.HelloWorld=m.first>0 and m.first or m.second;a.DiveEnegy=m.energy
  if a.HelloWorld>0 then a:GetBUFF((m.first>0 and 12 or 30)+(front and 20 or 0),a.HelloWorld-1)end
  a:GetBUFF(front and 58 or 38,m.energy+1)
 end
 local ordered={}
 for _,field in ipairs({'first','second'})do for w=1,2 do for _,m in ipairs(s.members)do if m[field]==w then ordered[#ordered+1]=s.actors[m.role]end end end end
 for _,m in ipairs(s.members)do if m.first==0 and m.second==0 then ordered[#ordered+1]=s.actors[m.role]end end
 put(c.TeammatesRef,ordered)
end
local function startHW()
 s.phase='hw';s.start=gs:GetTimeSeconds(c);s.targets={}
 c:HelloWorld();p.isCampActive=true;restore()
 marksVisible(false)
 s.third=R.third(s.members);s.yaw=c.HWRotationTemp.Yaw
 s.thirdPositions=R.thirdPositions(math.abs(s.yaw)<90 and '7B97'or'7B96',arena)
 s.oldScenes=scenes()
 note('HW run='..run..' yaw='..s.yaw)
end
local function begin()
 local members,actors,native=snapshot();run=run+1
 s={id=run,start=gs:GetTimeSeconds(c),members=members,actors=actors,targets={}}
 local count=0;for _,a in ipairs(native)do if a.HelloWorld>0 then count=count+1 end end
 if count==4 then
  for i,m in ipairs(members)do if i<=2 then m.first=native[i].HelloWorld elseif i<=4 then m.second=native[i].HelloWorld end end
  s.phase='hw';s.third=R.third(members);s.yaw=c.HWRotationTemp.Yaw
  s.thirdPositions=R.thirdPositions(math.abs(s.yaw)<90 and '7B97'or'7B96',arena);s.oldScenes=scenes()
 else
  s.phase='front'
  local worlds=shuffled(members);worlds[1].first=1;worlds[2].first=2;worlds[3].second=1;worlds[4].second=2
  local carried=previousEnergy~=nil
  if carried then for r,a in pairs(actors)do if previousEnergy.actors[r]~=key(a)then carried=false;break end end end
  for i,m in ipairs(shuffled(members))do m.energy=carried and previousEnergy.values[m.role]or(i<=4 and 2 or 1)end
  s.energySource=carried and 'sigma' or 'practice';previousEnergy=nil
  note('ENERGY source='..s.energySource)
  restore(true)
 end
 marksVisible(false)
 note('BEGIN '..run..' '..s.phase)
end
local function front(t)
 if not s.front then
  local a=arr(c.ActorTemps);if #a<5 then return end
  local wave
  for _,v in ipairs(FindAllOf('lightwaveBP_C')or{})do if valid(v)and v.Box:GetCollisionEnabled()~=0 then wave=v end end
  if not wave then return end
  local rows={}
  for index=2,5 do local v=a[index];rows[#rows+1]={class=v:GetClass():GetFullName(),position=v:K2_GetActorLocation()}end
  local clones=nativeClones(rows)
  local yaw=wave:K2_GetActorRotation().Yaw
  s.front=R.frontClones(clones,math.abs(yaw)%180<45 and '7B9B'or'7B9C',arena)
  s.wave=wave;s.waveYaw=yaw;s.frontStep=1
  note('FRONT '..s.front.key..' '..table.concat(s.front.labels,' -> '))
  for _,a2 in pairs(s.actors)do local v=s.front.points[1];move(a2,v);s.targets[key(a2)]=v end
 end
 if s.frontStep==1 and valid(s.wave)and math.abs(s.wave:K2_GetActorRotation().Yaw-s.waveYaw)>45 then
  s.frontStep=2;for _,a in pairs(s.actors)do local v=s.front.points[2];move(a,v);s.targets[key(a)]=v end
  note('FRONT step 2')
 end
end
local markOrder={5,6,0,1,2,3,8,9}
local function apply(plan,positions,moveNow)
 local a,v={},{}
 for i,id in ipairs(markOrder)do local actor=s.actors[plan.byMark[id].role];a[i]=actor;v[i]=positions[id]
  if actor.MarkIndex~=id then actor:Server_SetMark(id)end
  s.targets[key(actor)]=v[i];if moveNow then move(actor,v[i])end
 end
 put(c.TeammatesRef,a);if c.PositionsTemp:GetArrayNum()==8 then put(c.PositionsTemp,v)end
 marksVisible(true)
end
local function energy()local e={};for r,a in pairs(s.actors)do e[r]=a.DiveEnegy end;return e end
local function tethers(t)
 if not s.fourthPositions or t<15.3 or t>=27 then return end
 if not s.tetherAssignments then
  local lines={}
  for _,a in ipairs(FindAllOf('LinelineBP_C')or{})do if valid(a)and a.SplineMesh:IsVisible()and valid(a.CurrentTarget)then
   local v=a:K2_GetActorLocation()
   if (v.X-s.edgeBoss.X)^2+(v.Y-s.edgeBoss.Y)^2<100 then lines[#lines+1]=a end
  end end
  if #lines~=2 then return end
  local baits={[8]=s.actors[s.fourth.byMark[8].role],[9]=s.actors[s.fourth.byMark[9].role]}
  local assigned,used={},{}
  for _,line in ipairs(lines)do for _,id in ipairs({8,9})do
   if not used[id]and key(line.CurrentTarget)==key(baits[id])then assigned[key(line)]=id;used[id]=true;break end
  end end
  table.sort(lines,function(a,b)return key(a)<key(b)end)
  s.tetherAssignments={}
  for _,line in ipairs(lines)do
   local id=assigned[key(line)]
   if not id then id=used[8]and 9 or 8;used[id]=true end
   s.tetherAssignments[#s.tetherAssignments+1]={line=line,actor=baits[id],mark=id}
  end
 end
 local first,second=s.tetherAssignments[1],s.tetherAssignments[2]
 if valid(first.line)and valid(second.line)and valid(first.line.CurrentTarget)and valid(second.line.CurrentTarget)then
  local x,y=key(first.line.CurrentTarget),key(second.line.CurrentTarget)
  -- Either physical line can be intercepted first. Keep whichever line the
  -- NPC actually acquired instead of making both NPCs chase crossed claims.
  if (x==key(second.actor)and y~=key(second.actor))or(y==key(first.actor)and x~=key(first.actor))then
   first.line,second.line=second.line,first.line
   first.pickup,second.pickup=nil,nil;first.held,second.held=nil,nil
   first.lastMove,second.lastMove=nil,nil
  end
 end
 for _,entry in ipairs(s.tetherAssignments)do
  local line,a=entry.line,entry.actor
  if valid(line)and line.SplineMesh:IsVisible()and valid(line.CurrentTarget)then
   local held=key(line.CurrentTarget)==key(a)
   if entry.held~=held then
    entry.held=held;entry.holdPoint=nil
    note('TETHER '..entry.mark..' held='..tostring(held)..' t='..t)
   end
   local target
   if held then
    -- Keep the acquired line in front until the native gather/sort finishes.
    entry.holdPoint=entry.holdPoint or tetherRules.intercept(s.edgeBoss,a:K2_GetActorLocation(),arena.center)
    target=t>=20.2 and s.fourthPositions[entry.mark]or entry.holdPoint
   else
    local count=line.Spline:GetNumberOfSplinePoints()
    assert(count>=2,'Incomplete native tether spline')
    target=tetherRules.pickup(line.Spline:GetLocationAtSplinePoint(0,1),line.Spline:GetLocationAtSplinePoint(count-1,1),arena.center)
    entry.pickup=target
   end
   s.targets[key(a)]=target
   -- Native gather and the later spread can overwrite a move. Reissue only
   -- while a still-visible tether is owned by this run; never move the player.
   if not entry.lastMove or t-entry.lastMove>=0.25 then move(a,target);entry.lastMove=t end
  end
 end
end
local function hw(t)
 if t>=4.2 and t<13 then
  apply(s.third,s.thirdPositions,not s.thirdMoved);s.thirdMoved=true
 end
 if t>=13 and not s.checkedThird then
  s.checkedThird=true
  local observed=energy();local ok,err=pcall(R.verifyEnergy,s.third,observed)
  s.thirdValid=ok;note('THIRD energy '..tostring(ok)..' '..tostring(err))
  if ok then s.members=R.withObservedEnergy(s.members,observed);s.fourth=R.fourth(s.members)end
  s.targets={}
  marksVisible(false)
 end
 if t>=14.7 and not s.fourthPositions and s.fourth then
  for _,a in ipairs(FindAllOf('3rd_scenepart3_BP_C')or{})do
   if valid(a)and not s.oldScenes[key(a)]then
    local v=a.Omega_BP:K2_GetComponentLocation()
    if v.X*v.X+v.Y*v.Y>1000000 then
     -- Native model stands 23 m out; the source drawing's boss anchor is the
     -- 20 m arena rim. Keep the observed direction, calibrate model offset.
     local d=math.sqrt(v.X*v.X+v.Y*v.Y)
     s.scene=a;s.edgeBoss={X=v.X,Y=v.Y,Z=v.Z}
     s.fourthPositions=R.fourthPositions({X=v.X*2000/d,Y=v.Y*2000/d},arena.center)
     note('FOURTH anchor '..v.X..','..v.Y..' source rim=2000');break
    end
   end
  end
 end
 if t>=20.2 and t<32 and s.fourthPositions then apply(s.fourth,s.fourthPositions,not s.fourthMoved);s.fourthMoved=true end
 if t>=15.3 and t<20.2 and s.fourth then
  for id,m in pairs(s.fourth.byMark)do local a=s.actors[m.role];if a.MarkIndex~=id then a:Server_SetMark(id)end end
  marksVisible(true)
 end
 tethers(t)
 if t>=32 and not s.checkedFourth and s.fourth then
  s.checkedFourth=true;local ok,err=pcall(R.verifyEnergy,s.fourth,energy());s.fourthValid=ok;note('FOURTH energy '..tostring(ok)..' '..tostring(err))
 end
end
local function cleanup()
 if s then for _,a in pairs(s.actors)do if valid(a)then a:ClearMark();if valid(a.UMG_Marking)then a.UMG_Marking:SetHiddenInGame(false,true)end end end;note('END '..s.id)end
 s=nil
end
local function ui()
 if not valid(p)then return end
 local hud=p.PlayerUIRef;if not valid(hud)then return end
 for _,field in ipairs({'P5三运HWimg','P51st_plan','P52nd_plan','P53rd_plan','P53rd_plan2','dance'})do
  local w=hud[field];if valid(w)then w:SetVisibility(1)end
 end
 -- Practice owns the five reused buttons, including their enabled state.
 for _,field in ipairs({'P5三运HW'})do
  local w=hud[field];if valid(w)then w:SetVisibility(0);w:SetIsEnabled(false)end
 end
 for _,field in ipairs({'mark_attack','Mark_suolian','mark_stop','Mark_clear'})do
  local w=hud[field];if valid(w)then w:GetParent():SetVisibility(1)end
 end
end
local function tick()
 if not valid(c)then cleanup();failed=false;previousEnergy=nil;lastSigma=nil;lastDelta=nil;c=FindFirstOf('3rdController_C');p=FindFirstOf('BP_PlayerCharacter_C');if not valid(c)or not valid(p)then return end;gs=StaticFindObject('/Script/Engine.Default__GameplayStatics')end
 ui()
 captureSigma()
 if not c.IsActive then
  if s and s.phase=='front'and s.frontStep==2 and gs:GetTimeSeconds(c)-s.start>=18 and p.HP>0 then startHW();return end
  cleanup();failed=false;return
 end
 if failed then return end
 if not s then begin()end
 for _,a in pairs(s.actors)do assert(valid(a),'Party actor destroyed')end
 local t=gs:GetTimeSeconds(c)-s.start
 if s.phase=='front'then front(t)else hw(t)end
end
_G.MolingOmega={getState=function()return s end,rules=R}
RegisterInitGameStatePreHook(function()
 s=nil;c=nil;p=nil;gs=nil;failed=false
 previousEnergy=nil;lastSigma=nil;lastDelta=nil
end)
local verificationStarted=false
LoopInGameThreadWithDelay(50,function()
 local ok,err=pcall(tick)
 if not ok then note('ERROR '..tostring(err));failed=true;cleanup()end
 if config.verification_script and valid(c)and gs and gs:GetTimeSeconds(c)>3 and not verificationStarted then
  verificationStarted=true;local good,why=pcall(dofile,config.verification_script);if not good then note('VERIFY ERROR '..tostring(why))end
 end
end)
note('LOADED unified P5 Omega v1.0; active tether acquisition, Sigma energy carry')
