-- Explicit, dormant adapter. No FindFirstOf, hooks, scheduling, global exports,
-- UI changes, controller-array writes, or loading of Delta/Sigma modules here.
-- Bind only after the user authorizes integration. Call on the game thread.
return function(rules)
    local A={}
    function A.bind(session,token,actors,isCurrentRun)
        assert(type(isCurrentRun)=='function','Native current-run guard is required')
        local owned={}
        for _,role in ipairs(rules.order) do
            local actor=actors[role]
            assert(actor and actor:IsValid(),'Missing actor '..role)
            owned[role]=actor
        end
        local function validRun()
            assert(session.generation==token and session.state,'Stale Omega binding')
            assert(isCurrentRun(),'Omega is not the current native campaign')
            for _,role in ipairs(rules.order) do assert(owned[role]:IsValid(),'Destroyed Omega actor') end
        end
        local function npc(actor)
            return actor:GetClass():GetFullName():find('/AI/',1,true)~=nil
        end
        local binding={}
        local appliedRevision=-1
        function binding:apply(commands)
            validRun()
            assert(commands.token==token and commands.phase==session.state.phase,'Stale command batch')
            assert(commands.revision==session.state.revision,'Stale command revision')
            if appliedRevision==commands.revision then return false end
            local seen={}
            -- Validate the complete batch before invoking any native mutation.
            for _,c in ipairs(commands.marks) do
                assert(owned[c.role] and not seen[c.role],'Invalid/duplicate marked role')
                assert(c.mark==-1 or c.mark==0 or c.mark==1 or c.mark==2 or c.mark==3 or c.mark==5 or c.mark==6 or c.mark==8 or c.mark==9,'Invalid Omega marker')
                seen[c.role]=true
            end
            for _,c in ipairs(commands.moves) do
                assert(owned[c.role] and c.position,'Invalid movement role')
                for _,axis in ipairs({'X','Y','Z'}) do
                    local n=c.position[axis]
                    assert(type(n)=='number' and n==n and math.abs(n)<math.huge,'Invalid movement coordinate')
                end
            end
            for _,c in ipairs(commands.marks) do
                local actor=owned[c.role]
                if actor.MarkIndex~=c.mark then
                    if c.mark<0 then actor:ClearMark() else actor:Server_SetMark(c.mark) end
                end
            end
            for _,c in ipairs(commands.moves) do
                local actor=owned[c.role]
                if npc(actor) then actor['移动'](actor,c.position) end
            end
            appliedRevision=commands.revision
            return true
        end
        function binding:readEnergy()
            validRun()
            local energy={}
            for _,role in ipairs(rules.order) do energy[role]=owned[role].DiveEnegy end
            return energy
        end
        function binding:clear()
            validRun()
            for _,role in ipairs(rules.order) do
                local a=owned[role]
                if a.MarkIndex~=-1 then a:ClearMark() end
            end
            session:cancel(token)
        end
        return binding
    end
    return A
end
