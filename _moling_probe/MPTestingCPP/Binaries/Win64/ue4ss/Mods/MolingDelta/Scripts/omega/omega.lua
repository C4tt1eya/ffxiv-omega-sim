-- Event-driven Omega session. Loading this file does not install hooks or run
-- anything. A future game-thread adapter supplies actual native phase events.
return function(root)
    local R=dofile(root..'omega_rules.lua')(dofile(root..'omega_source.lua'))
    local M={rules=R}
    function M.new()
        local self={generation=0,state=nil}
        local function checked(token,phase)
            assert(self.state and token==self.generation,'Stale Omega run event')
            if phase then assert(self.state.phase==phase,'Unexpected Omega phase: '..self.state.phase) end
            return self.state
        end
        local function batch(s,token,plan,positions)
            s.revision=s.revision+1
            local commands={token=token,revision=s.revision,phase=s.phase,marks={},moves={}}
            if plan then
                for _, role in ipairs(R.order) do
                    commands.marks[#commands.marks+1]={role=role,mark=plan.byRole[role]}
                    if positions then commands.moves[#commands.moves+1]={role=role,position=positions[plan.byRole[role]]} end
                end
            end
            return commands
        end
        function self:begin(members,arena)
            local roster=R.roster(members)
            local frame=R.frame(arena.center,arena.north)
            self.generation=self.generation+1
            self.state={phase='front',members=roster,arena=frame,step=0,revision=0}
            return self.generation
        end
        function self:frontPlan(token,positions,forms,cast)
            local s=checked(token,'front')
            assert(s.step==0,'Cannot replace a committed front plan')
            s.front=R.front(positions,forms,cast,s.arena)
            return s.front
        end
        function self:frontClones(token,clones,cast)
            local s=checked(token,'front')
            assert(s.step==0,'Cannot replace a committed front plan')
            s.front=R.frontClones(clones,cast,s.arena)
            return s.front
        end
        function self:frontStep(token,step)
            local s=checked(token,'front')
            assert(s.front and step==s.step+1 and step<=2,'Out-of-order clone resolution')
            local commands=batch(s,token)
            for _,role in ipairs(R.order) do commands.moves[#commands.moves+1]={role=role,position=s.front.points[step]} end
            s.step=step
            return commands
        end
        function self:third(token,cast)
            local s=checked(token,'front')
            assert(s.step==2,'Both clone waves must complete before third transfer')
            local plan=R.third(s.members)
            local positions,frame,direction=R.thirdPositions(cast,s.arena)
            s.phase='third';s.third=plan;s.thirdPositions=positions;s.thirdFrame=frame;s.direction=direction
            return batch(s,token,plan,positions)
        end
        function self:thirdResolved(token,observedEnergy)
            local s=checked(token,'third')
            R.verifyEnergy(s.third,observedEnergy)
            local members=R.withObservedEnergy(s.members,observedEnergy)
            local nextPlan=R.fourth(members) -- prove allocation before changing state
            s.members=members;s.fourth=nextPlan;s.phase='between'
            local commands=batch(s,token)
            for _,role in ipairs(R.order) do commands.marks[#commands.marks+1]={role=role,mark=-1} end
            return commands
        end
        function self:fourth(token,actualBossPosition)
            local s=checked(token,'between')
            local positions,frame=R.fourthPositions(actualBossPosition,s.arena.center)
            s.phase='fourth';s.fourthPositions=positions;s.fourthFrame=frame
            return batch(s,token,s.fourth,positions)
        end
        function self:finish(token,observedEnergy)
            local s=checked(token,'fourth')
            R.verifyEnergy(s.fourth,observedEnergy)
            s.members=R.withObservedEnergy(s.members,observedEnergy);s.phase='complete'
            local commands=batch(s,token)
            for _,role in ipairs(R.order) do commands.marks[#commands.marks+1]={role=role,mark=-1} end
            return commands
        end
        function self:cancel(token)
            checked(token)
            self.generation=self.generation+1;self.state=nil
        end
        return self
    end
    return M
end
