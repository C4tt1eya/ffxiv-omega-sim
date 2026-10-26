-- v2.2 trigger ordering; IDs here are the simulator's verified zero-based IDs.
local R={order={'MT','ST','H1','H2','D1','D2','D3','D4'}}
-- User transfer priority; Sony/front-half order remains the v2.2 order above.
R.hwOrder={'MT','ST','H1','H2','D1','D2','D3','D4'}
local rank={};for i,r in ipairs(R.order)do rank[r]=i end
local hwRank={};for i,r in ipairs(R.hwOrder)do hwRank[r]=i end
local function sorted(a,priority)local b={};priority=priority or rank;for i,v in ipairs(a)do b[i]=v end;table.sort(b,function(x,y)return assert(priority[x.role])<assert(priority[y.role])end);return b end
function R.front(members)
 assert(#members==8,'Sigma requires eight members')
 local pairs,untargeted={},{}
 for _,m in ipairs(sorted(members))do
  assert(m.shape>=10 and m.shape<=13,'Invalid Sony shape')
  pairs[m.shape]=pairs[m.shape]or{};table.insert(pairs[m.shape],m)
  if not m.laser then table.insert(untargeted,m)end
 end
 assert(#untargeted==2,'Expected six laser targets')
 assert(untargeted[1].shape~=untargeted[2].shape,'Untargeted Sony pairs must differ')
 local byMark={};local function assign(m,k)assert(not byMark[k]);byMark[k]=m end
 assign(untargeted[1],0);assign(untargeted[2],5)
 for i,m in ipairs(untargeted)do
  local pair=pairs[m.shape];assert(#pair==2)
  assign(pair[1]==m and pair[2]or pair[1],i==1 and 10 or 3)
 end
 local doubles={}
 for shape=10,13 do local pair=pairs[shape];assert(pair and #pair==2);if pair[1].laser and pair[2].laser then table.insert(doubles,pair)end end
 assert(#doubles==2)
 assign(doubles[1][1],1);assign(doubles[2][1],2)
 assign(doubles[2][2],6);assign(doubles[1][2],7)
 local slots={};for _,k in ipairs({0,10,5,3,1,7,6,2})do table.insert(slots,byMark[k])end
 return {byMark=byMark,slots=slots}
end
function R.hw(members)
 local byMark,stops={},{}
 for _,m in ipairs(sorted(members,hwRank))do
  if m.world==1 then assert(not byMark[5]);byMark[5]=m
  elseif m.world==2 then assert(not byMark[6]);byMark[6]=m
  elseif m.energy==1 and #stops<2 then table.insert(stops,m)end
 end
 assert(byMark[5]and byMark[6]and #stops==2,'HW world/one-energy bait assignment is incomplete')
 byMark[8],byMark[9]=stops[1],stops[2]
 local k=0
 for _,m in ipairs(sorted(members,hwRank))do
  if m.world==0 and m~=stops[1]and m~=stops[2]then byMark[k]=m;k=k+1 end
 end
 assert(k==4)
 -- Native initial safe groups: slots 4,5,6 near Omega-F; all others away.
 local slots={};for _,id in ipairs({5,6,1,8,0,9,2,3})do table.insert(slots,byMark[id])end
 return {byMark=byMark,slots=slots}
end
function R.rotate(v,yaw)
 local a=math.rad(yaw);local c,s=math.cos(a),math.sin(a)
 return {X=v.X*c-v.Y*s,Y=v.X*s+v.Y*c,Z=v.Z or 120}
end
function R.radial(v,r)
 local d=math.sqrt(v.X*v.X+v.Y*v.Y);assert(d>0)
 return {X=v.X*r/d,Y=v.Y*r/d,Z=120}
end
-- Tower-only practice tolerance: ordinary outer-half positions should work
-- without requiring both partners to add an exact lateral offset. Keep the
-- native far-line distance during the earlier spread and all near-line rules.
R.farTowerMinimum=3500
function R.farTowerSafe(a,b)
 return (a.X-b.X)^2+(a.Y-b.Y)^2>=R.farTowerMinimum^2
end
function R.spread(near,yaw)
 local raw=near and {{520,1257},{-430,-1040},{-520,1257},{430,-1040},{1040,430},{-1040,-430},{-1040,430},{1040,-430}}
  or {{750,1810},{-750,-1810},{-750,1810},{750,-1810},{1726,715},{-1810,-750},{-1726,715},{1810,-750}}
 local t={};for i,v in ipairs(raw)do t[i]=R.rotate({X=v[1],Y=v[2]},yaw)end;return t
end
local function angle(v)return math.atan(v.Y,v.X)end
local function delta(a,b)return math.abs((a-b+math.pi)%(2*math.pi)-math.pi)end
function R.towers(spread,towers,near)
 assert(#spread==8 and #towers==(near and 6 or 5),'Tower pattern not ready')
 local chosen,counts={},{}
 for i,v in ipairs(spread)do
  local options={}
  for j,t in ipairs(towers)do
   local d=math.deg(delta(angle(v),angle(t.position)))
   -- Near: ignore a tower directly behind the spread ray; take +/-45 degrees.
   -- Far: take the two flanking waypoint rays (+/-22.5 degrees).
   if d>(near and 25 or 8)and d<(near and 65 or 37)then options[#options+1]=j end
  end
  assert(#options>=1 and #options<=2,'Unexpected flanking tower geometry')
  table.sort(options,function(a,b)
   if towers[a].capacity~=towers[b].capacity then return towers[a].capacity>towers[b].capacity end
   return delta(angle(v),angle(towers[a].position))<delta(angle(v),angle(towers[b].position))
  end)
  local j=options[1];chosen[i]=j;counts[j]=(counts[j]or 0)+1
 end
 for j,t in ipairs(towers)do assert(counts[j]==t.capacity,'No-brain tower capacity mismatch')end
 local result,used={},{}
 for i,j in ipairs(chosen)do
  local tower=towers[j];used[j]=(used[j]or 0)+1
  local target=near and {X=tower.position.X,Y=tower.position.Y,Z=120}or R.radial(tower.position,1955)
  if not near then
   local partner=chosen[i%2==1 and i+1 or i-1]
   local difference=(angle(target)-angle(towers[partner].position)+math.pi)%(2*math.pi)-math.pi
   -- Stay inside the actual Sphere2 overlap volume, not a guessed 400-unit
   -- tower radius. Runtime sweeps verify this radius/angle also keeps the
   -- real far tether safe; the old 1970/3.2 point missed tower collisions.
   target=R.rotate(target,difference>=0 and 3.5 or -3.5)
  end
  -- Separate two AI capsules within the same tower without changing its ray.
  local d=math.sqrt(target.X*target.X+target.Y*target.Y)
  local shift=near and tower.capacity==2 and (used[j]==1 and -50 or 50)or 0
  local x,y=target.X,target.Y;target.X=x-y/d*shift;target.Y=y+x/d*shift
  result[i]={tower=j,position=target,preKnock=R.radial(target,near and 170 or 195.5)}
 end
 return result
end
-- Local frame: Omega-F at (0,+1000), arena centre at (0,0). Values from the
-- user's mlm v2.1 Splatoon drawings, converted from yalms to simulator units.
function R.worldPositions(yaw,clockwise)
 local mirror=clockwise==0 and -1 or 1
 local byMark={
  [5]={X=940*mirror,Y=18},[6]=R.radial({X=598,Y=-1626},1950),
  [0]={X=-1844*mirror,Y=18},[1]={X=1848*mirror,Y=18},
  [2]={X=-330,Y=-990},[3]={X=-452,Y=-1706},
  [8]={X=1102,Y=1536},[9]={X=-1092,Y=1536},
 }
 -- With Omega-F at 12 o'clock, UE local +X projects to the viewer's left.
 -- Near world stays rear-left; attack 3/4 rear-right; stop 1 left, stop 2 right.
 -- Only attack 1/2 and far world follow the rotating laser. Near world,
 -- attack 3/4 and arm baits retain the reference drawing's fixed sides.
 -- The two arms select distant players: both baits stay on Omega-F's side.
 for k,v in pairs(byMark)do byMark[k]=R.rotate(v,yaw)end
 return byMark
end
return R
