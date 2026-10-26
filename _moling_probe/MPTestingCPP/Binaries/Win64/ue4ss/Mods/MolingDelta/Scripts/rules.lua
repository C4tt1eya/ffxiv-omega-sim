-- Pure assignment rules. Internal simulator markers are zero based.
local M = {}
-- Keep the world buffs on their original owners. If both were randomized
-- onto the same blue tether, exchange near world with the idle slot on the
-- same side of the arena. The caller must update BOTH real tethers and AI.
function M.blueSlots(blue, world)
    assert(#blue == 4, 'Delta requires four blue tether players')
    local slots,far,near={}
    for i,actor in ipairs(blue) do
        slots[i]=actor
        if world(actor)==1 then assert(not far,'Duplicate distant world');far=i
        elseif world(actor)==2 then assert(not near,'Duplicate near world');near=i end
    end
    assert(far and near,'Incomplete blue world assignment')
    local repaired=far%2==near%2
    if repaired then
        local other=near%2==1 and near+1 or near-1
        assert(world(blue[other])==0,'Expected idle blue player')
        slots[near],slots[other]=slots[other],slots[near]
    end
    -- Native slots 2/4 are the inner, long blue tether: they break first.
    -- Slots 1/3 are the outer short tether and handle the later break.
    -- Exchange whole pairs to preserve partners after repairing an invalid pair.
    local reordered=far%2==1
    if reordered then slots={slots[2],slots[1],slots[4],slots[3]} end
    return slots,{repaired=repaired,reordered=reordered,changed=repaired or reordered}
end
function M.assign(red, blue, role, world, d3, idleMarks)
    assert(#red == 4 and #blue == 4, 'Delta requires two pairs of each tether')
    -- The simulator spawns tethers between entries (1,3) and (2,4).
    local inner = {red[1], red[3]}
    local outer = {red[2], red[4]}
    if role(inner[1]) == d3 or role(inner[2]) == d3 then inner, outer = outer, inner end
    local a = {attack = {inner[1], inner[2], outer[1], outer[2]}, idle = {}, marks = {}}
    for i, actor in ipairs(a.attack) do a.marks[#a.marks+1] = {actor, i-1} end
    for _, actor in ipairs(blue) do
        local hw = world(actor)
        if hw == 1 then assert(not a.far, 'Duplicate distant world'); a.far = actor
        elseif hw == 2 then assert(not a.near, 'Duplicate near world'); a.near = actor
        else a.idle[#a.idle+1] = actor end
    end
    assert(a.far and a.near and #a.idle == 2, 'Incomplete world assignment')
    a.marks[#a.marks+1] = {a.far, 5}
    a.marks[#a.marks+1] = {a.near, 6}
    for i, actor in ipairs(a.idle) do a.marks[#a.marks+1] = {actor, idleMarks and (7+i) or -1} end
    return a
end
function M.redSlots(a, swap)
    return {a.attack[1], a.attack[swap and 4 or 3], a.attack[2], a.attack[swap and 3 or 4]}
end
-- Native arm slots are outer-right, inner-right, inner-left, outer-left.
-- Our outer players share a green tether. When both arms turn inward, the
-- native outer waypoints are only ~1126 apart and break that tether (<1200)
-- during blue-tether vulnerability. Spread just this pair around the arena,
-- preserving radius and leaving room for the native AI arrival tolerance.
function M.armPositions(native)
    assert(#native==4,'Expected four arm waypoints')
    local points={}
    for i,j in ipairs({2,1,3,4}) do
        local p=native[j];points[i]={X=p.X,Y=p.Y,Z=p.Z}
    end
    local a,b=points[2],points[4]
    local minimum=1360
    local dx,dy=a.X-b.X,a.Y-b.Y
    if dx*dx+dy*dy>=minimum*minimum then return points,false end
    local ra,rb=math.sqrt(a.X*a.X+a.Y*a.Y),math.sqrt(b.X*b.X+b.Y*b.Y)
    assert(ra>0 and rb>0 and ra+rb>=minimum,'Invalid outer arm radii')
    local aa,ab=math.atan(a.Y,a.X),math.atan(b.Y,b.X)
    local delta=(ab-aa+math.pi)%(2*math.pi)-math.pi
    local cosine=(ra*ra+rb*rb-minimum*minimum)/(2*ra*rb)
    local angle=math.acos(math.max(-1,math.min(1,cosine)))
    local extra=(angle-math.abs(delta))/2
    local sign=delta>=0 and 1 or -1
    aa,ab=aa-sign*extra,ab+sign*extra
    a.X,a.Y=ra*math.cos(aa),ra*math.sin(aa)
    b.X,b.Y=rb*math.cos(ab),rb*math.sin(ab)
    return points,true
end
function M.worldSlots(a)
    return {a.far, a.near, a.idle[1], a.idle[2], a.attack[1], a.attack[3], a.attack[4], a.attack[2]}
end
-- Assign the four native monitor waypoints once, after arm guidance. Enumerate
-- the 24 one-to-one assignments so no two players claim the same waypoint.
-- Origins follow the current red roster, including any outer-pair fist swap.
function M.monitorPositions(origins, points)
    assert(#origins==4 and #points==4,'Expected four red origins and waypoints')
    local best,bestCost,used,order=nil,math.huge,{},{}
    local function visit(i,cost)
        if i==5 then
            if cost<bestCost then bestCost=cost;best={table.unpack(order)} end
            return
        end
        for j,p in ipairs(points) do
            if not used[j] then
                used[j]=true;order[i]=j
                local dx,dy=origins[i].X-p.X,origins[i].Y-p.Y
                visit(i+1,cost+math.sqrt(dx*dx+dy*dy))
                used[j]=nil
            end
        end
    end
    visit(1,0)
    local result={}
    for i,j in ipairs(best) do result[i]=points[j] end
    return result,best
end
-- Native blue monitor slots: isolated+monitor, stack+monitor,
-- isolated without monitor, stack without monitor. Keep its safe lateral
-- side, but keep the isolated player outside the 300-radius stack and
-- the 700-radius monitor explosions at the red waypoints (plus capsules).
function M.blueMonitorPositions(points,yaw)
    assert(#points==4,'Expected four blue monitor points')
    local angle=math.rad(yaw)
    local co,si=math.cos(angle),math.sin(angle)
    local side=(points[4].X*co+points[4].Y*si)<0 and -1 or 1
    local dx,dy=-400*si,400*co
    local outer={X=side*400*co,Y=side*400*si}
    local inner={X=side*200*co,Y=side*200*si}
    return {
        {X=outer.X+dx,Y=outer.Y+dy,Z=120},
        {X=outer.X,Y=outer.Y,Z=120},
        -- Without TV, be farther from Omega-M than the outer TV stack player;
        -- Pile Pitch chooses among the nearest three, not by vulnerability.
        {X=inner.X-650*si,Y=inner.Y+650*co,Z=120},
        {X=inner.X,Y=inner.Y,Z=120},
    }
end
-- Splatoon offsets converted to the native arena frame: beetle is on +Y,
-- not -Y (runtime Omega location is (0,+2300) before arena rotation).
-- Preserve the safe half-plane X; reflect the longitudinal axis before yaw.
M.worldLeft = {
    {-1876, 32}, {-878, -6}, {-1534, -1048},
    {-298, 1818}, {-858, 1080}, {-1344, 1298}, {-1032, -1574},
}
M.worldRight = {
    {1804, 58}, {672, -6}, {1578, -1048},
    {186, 1896}, {878, 966}, {1566, 1106}, {1042, -1528},
}
function M.worldPositions(half, yaw)
    local points = half == 1 and M.worldLeft or M.worldRight
    local angle=math.rad(yaw); local co,si=math.cos(angle),math.sin(angle)
    local result={}
    for i,p in ipairs(points) do result[i]={X=p[1]*co-p[2]*si,Y=p[1]*si+p[2]*co,Z=120} end
    return result
end
return M
