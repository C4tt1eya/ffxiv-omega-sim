-- Pure rules: no Unreal globals, timers, file writes, random rerolls or player movement.
return function(source)
    local R = {}
    R.order = {'MT','ST','H1','H2','D1','D2','D3','D4'}
    R.markIds = {0,1,2,3,5,6,8,9}
    local priority = {}; for i, role in ipairs(R.order) do priority[role] = i end
    local function finite(n) return type(n)=='number' and n==n and math.abs(n)<math.huge end
    local function integer(n) return finite(n) and n%1==0 end
    local function copy(m)
        return {role=m.role,energy=m.energy,first=m.first,second=m.second}
    end
    function R.roster(members)
        assert(type(members)=='table' and #members==8,'Omega requires eight members')
        local out, seen, counts = {}, {}, {{[1]=0,[2]=0},{[1]=0,[2]=0}}
        for _, m in ipairs(members) do
            assert(priority[m.role] and not seen[m.role],'Missing or duplicate role')
            assert(integer(m.energy) and m.energy>=0 and m.energy<=3,'Invalid Dynamis count')
            for i, field in ipairs({'first','second'}) do
                assert(integer(m[field]) and m[field]>=0 and m[field]<=2,'World must be 0/1(far)/2(near)')
                if m[field]>0 then counts[i][m[field]]=counts[i][m[field]]+1 end
            end
            assert(m.first==0 or m.second==0,'Two world rounds cannot share a holder')
            seen[m.role]=true;out[#out+1]=copy(m)
        end
        for _, c in ipairs(counts) do assert(c[1]==1 and c[2]==1,'Each round needs one far and one near world') end
        table.sort(out,function(a,b)return priority[a.role]<priority[b.role]end)
        return out
    end
    local function finish(roster, baits, worldField)
        assert(#baits==2,'Expected exactly two baits')
        local byMark, byRole = {}, {}
        local function mark(id,m)
            assert(not byMark[id] and not byRole[m.role],'Conflicting world/bait assignments')
            byMark[id]=m;byRole[m.role]=id
        end
        for _, m in ipairs(roster) do
            if m[worldField]>0 then mark(m[worldField]==1 and 5 or 6,m) end
        end
        mark(8,baits[1]);mark(9,baits[2])
        local attack=0
        for _, m in ipairs(roster) do
            if byRole[m.role]==nil then mark(attack,m);attack=attack+1 end
        end
        assert(attack==4,'Expected four attack markers')
        return {byMark=byMark,byRole=byRole,roster=roster}
    end
    function R.third(members)
        local roster=R.roster(members)
        local candidates={}
        -- XML list: second-world + 2 stacks first, then no-world + 2 stacks.
        -- Each tier uses the user transfer priority; tiers remain separate.
        for _, m in ipairs(roster) do
            if m.energy==2 and m.second>0 then candidates[#candidates+1]=m end
        end
        for _, m in ipairs(roster) do
            if m.energy==2 and m.first==0 and m.second==0 then candidates[#candidates+1]=m end
        end
        assert(#candidates>=2,'Third-transfer monitor candidates are incomplete')
        return finish(roster,{candidates[1],candidates[2]},'first')
    end
    function R.fourth(members)
        local roster=R.roster(members)
        local baits={}
        for _, m in ipairs(roster) do
            if m.energy==3 then baits[#baits+1]=m end
        end
        return finish(roster,baits,'second')
    end
    -- A prediction for validation only. Runtime never sets live energy from this.
    function R.expectedEnergy(plan)
        local result={}
        for role, mark in pairs(plan.byRole) do
            local value=plan.byMark[mark].energy+((mark==8 or mark==9) and 0 or 1)
            assert(value<=3,'World transfer would overcap Dynamis')
            result[role]=value
        end
        return result
    end
    function R.withObservedEnergy(members, energy)
        assert(type(energy)=='table','Missing observed Dynamis')
        local out={}
        for _, m in ipairs(R.roster(members)) do
            local n=energy[m.role]
            assert(integer(n) and n>=0 and n<=3,'Missing/invalid observed energy for '..m.role)
            m.energy=n;out[#out+1]=m
        end
        return out
    end
    function R.verifyEnergy(plan, observed)
        local expected=R.expectedEnergy(plan)
        for role, value in pairs(expected) do
            assert(observed[role]==value,'Unexpected transfer recipient/energy: '..role)
        end
        return true
    end
    -- Arena frame: north points from the centre to the current new 12 o'clock.
    -- right=(-north.Y,north.X); local +Y is away from 12 o'clock.
    function R.frame(center,north)
        assert(type(center)=='table' and finite(center.X) and finite(center.Y),'Missing arena centre')
        assert(type(north)=='table' and finite(north.X) and finite(north.Y),'Missing new 12 oclock')
        local d=math.sqrt(north.X*north.X+north.Y*north.Y)
        assert(d>1e-6,'Degenerate new 12 oclock')
        local x,y=north.X/d,north.Y/d
        return {center={X=center.X,Y=center.Y,Z=center.Z or 120},north={X=x,Y=y},right={X=-y,Y=x}}
    end
    function R.point(localPoint,frame)
        return {X=frame.center.X+frame.right.X*localPoint.X-frame.north.X*localPoint.Y,
                Y=frame.center.Y+frame.right.Y*localPoint.X-frame.north.Y*localPoint.Y,
                Z=frame.center.Z}
    end
    function R.front(positions,forms,cast,frame)
        assert(#positions==4 and #forms==4,'Need four clones in descending actor-ID order')
        assert(cast=='7B9B' or cast=='7B9C','Unknown diffuse-wave cast')
        local seen,p,t={},{},{}
        for i=1,4 do
            assert(integer(positions[i]) and positions[i]>=0 and positions[i]<=3 and not seen[positions[i]],'Invalid clone quadrants')
            assert(forms[i]==0 or forms[i]==1,'Missing clone transformation')
            seen[positions[i]]=true;p[i]=tostring(positions[i]);t[i]=tostring(forms[i])
        end
        local key=table.concat(p)..'/'..table.concat(t)..'/'..cast
        local labels=source.front[key]
        assert(labels,'Clone arrangement is not covered by the supplied trigger')
        local result={key=key,labels={labels[1],labels[2]},points={}}
        for i,label in ipairs(labels) do result.points[i]=R.point(source.points[label],frame) end
        return result
    end
    function R.frontClones(clones,cast,frame)
        assert(type(clones)=='table' and #clones==4,'Need the four current-run clones')
        local ordered,seen={},{ }
        for _,clone in ipairs(clones) do
            assert(integer(clone.id) and not seen[clone.id],'Invalid/duplicate clone actor ID')
            assert(clone.position and finite(clone.position.X) and finite(clone.position.Y),'Missing clone position')
            seen[clone.id]=true;ordered[#ordered+1]=clone
        end
        table.sort(ordered,function(a,b)return a.id>b.id end)
        local positions,forms={},{}
        for i,clone in ipairs(ordered) do
            local dx,dy=clone.position.X-frame.center.X,clone.position.Y-frame.center.Y
            assert(dx*dx+dy*dy>1,'Central Omega is not a clone')
            local x=dx*frame.right.X+dy*frame.right.Y
            local y=-dx*frame.north.X-dy*frame.north.Y
            -- Exact trigger convention: NW=0, SW=1, SE=2, NE=3.
            positions[i]=math.floor(math.atan(x,y)/math.pi*2+2)%4
            forms[i]=clone.transformed
        end
        return R.front(positions,forms,cast,frame)
    end
    function R.thirdPositions(cast,arena)
        assert(cast=='7B96' or cast=='7B97','Unknown monitor/side cleave cast')
        -- Trigger: 7B96 -> face B, 7B97 -> face D. Convert its two drawings
        -- into that view independently; the drawings have real asymmetries.
        local left=cast=='7B97'
        local direction=left and 'D' or 'B'
        local north={X=arena.right.X*(left and -1 or 1),Y=arena.right.Y*(left and -1 or 1)}
        local frame=R.frame(arena.center,north)
        local result={}
        for id,xy in pairs(source.third[left and '左' or '右']) do
            local sign=left and 1 or -1
            result[id]=R.point({X=sign*xy[2]*100,Y=sign*xy[1]*100},frame)
        end
        return result,frame,direction
    end
    function R.fourthPositions(bossPosition,center)
        assert(bossPosition and finite(bossPosition.X) and finite(bossPosition.Y),'Missing actual edge Omega position')
        local n={X=bossPosition.X-center.X,Y=bossPosition.Y-center.Y}
        local distance=math.sqrt(n.X*n.X+n.Y*n.Y)
        assert(distance>1,'Cannot use the central/old Omega as fourth-transfer anchor')
        local frame=R.frame(center,n)
        local result={}
        -- Splatoon offsets originate at the actual boss, facing toward centre.
        for id,xy in pairs(source.fourth) do
            result[id]=R.point({X=-xy[1]*100,Y=xy[2]*100-distance},frame)
        end
        return result,frame
    end
    return R
end
