-- Pure practice selection. A chosen marker transfers a complete mechanic slot,
-- never just its overhead icon. The adapter applies the returned actor states
-- and physical tether endpoints before delayed native mechanics can run.
local P = {}
P.random = -1
P.choices = {
    delta = {0, 1, 2, 3, 5, 6, 8, 9},
    sigma_front = {0, 1, 2, 3, 5, 6, 7, 10},
    sigma_hw = {0, 1, 2, 3, 5, 6, 8, 9},
}

function P.valid(stage, selected)
    assert(P.choices[stage], 'Unknown practice stage')
    if selected == P.random then return true end
    for _, mark in ipairs(P.choices[stage]) do if selected == mark then return true end end
    return false
end

local function selection(stage, selected)
    if selected == nil then selected = P.random end
    assert(P.valid(stage, selected), 'Invalid practice marker for ' .. stage)
    return selected
end

local function mappedArray(values, map)
    local result = {}
    for i, value in ipairs(values) do result[i] = map(value) end
    return result
end

-- Input blue slots must already describe the repaired real blue tethers.
-- The plan remains explicit: rerunning role-based assignment after transferring
-- the slots could undo the selection (especially for the configured D3 role).
function P.delta(rules, red, blue, controlledRole, selected, role, world, d3)
    selected = selection('delta', selected)
    local original = rules.assign(red, blue, role, world, d3, true)
    local player, target, seen = nil, nil, {}
    for _, entry in ipairs(original.marks) do
        assert(not seen[entry[1]], 'Duplicate Delta actor')
        seen[entry[1]] = true
        if role(entry[1]) == controlledRole then
            assert(not player, 'Duplicate controlled Delta role'); player = entry[1]
        end
        if entry[2] == selected then target = entry[1] end
    end
    assert(player, 'Controlled Delta role is missing')
    local changed = selected ~= P.random and player ~= target
    if selected ~= P.random then assert(target, 'Requested Delta marker is missing') end
    local function map(actor)
        if changed then
            if actor == player then return target end
            if actor == target then return player end
        end
        return actor
    end
    local assignment = {
        attack = mappedArray(original.attack, map), idle = mappedArray(original.idle, map),
        far = map(original.far), near = map(original.near), marks = {},
    }
    for i, entry in ipairs(original.marks) do assignment.marks[i] = {map(entry[1]), entry[2]} end
    local worlds = {}
    for _, list in ipairs({red, blue}) do
        for _, actor in ipairs(list) do worlds[#worlds + 1] = {actor = map(actor), world = world(actor)} end
    end
    return {
        red = mappedArray(red, map), blue = mappedArray(blue, map),
        assignment = assignment, worlds = worlds,
        swap = changed and {from = player, to = target} or nil,
    }
end

local function cloneMembers(members, controlledRole)
    assert(#members == 8, 'Practice selection requires eight members')
    local result, byRole, player = {}, {}, nil
    for i, member in ipairs(members) do
        assert(member.role and not byRole[member.role], 'Duplicate or missing practice role')
        local clone = {}; for k, v in pairs(member) do clone[k] = v end
        result[i], byRole[member.role] = clone, clone
        if member.role == controlledRole then player = clone end
    end
    assert(player, 'Controlled practice role is missing')
    return result, byRole, player
end

-- Rebind a stored HW plan after the independently selected front-half fields
-- have been copied. Identity follows role/actor, rather than a transient record.
function P.rebind(plan, members)
    local byRole = {}
    for _, member in ipairs(members) do
        assert(member.role and not byRole[member.role], 'Duplicate or missing practice role')
        byRole[member.role] = member
    end
    local function map(member)
        local replacement = assert(byRole[member.role], 'Practice plan role is missing')
        assert(replacement.actor == member.actor, 'Practice plan actor changed')
        return replacement
    end
    local result = {byMark = {}, slots = mappedArray(plan.slots, map)}
    for mark, member in pairs(plan.byMark) do result.byMark[mark] = map(member) end
    return result
end

local function choose(stage, assign, members, controlledRole, selected, fields)
    selected = selection(stage, selected)
    local result, byRole, player = cloneMembers(members, controlledRole)
    local original = assign(members)
    local target = selected ~= P.random and assert(original.byMark[selected], 'Requested practice marker is missing') or nil
    local changed = target and target.role ~= controlledRole
    if changed then
        local other = byRole[target.role]
        for _, field in ipairs(fields) do player[field], other[field] = other[field], player[field] end
    end
    local function map(member)
        if changed then
            if member.role == controlledRole then return byRole[target.role] end
            if member.role == target.role then return player end
        end
        return assert(byRole[member.role])
    end
    local assignment = {byMark = {}, slots = mappedArray(original.slots, map)}
    for mark, member in pairs(original.byMark) do assignment.byMark[mark] = map(member) end
    return {
        members = result, assignment = assignment,
        swap = changed and {from = player, to = byRole[target.role]} or nil,
    }
end

function P.front(rules, members, controlledRole, selected)
    return choose('sigma_front', rules.front, members, controlledRole, selected, {'shape', 'laser'})
end

-- Select this once when the attempt starts, before displaying world/energy
-- buffs. Keep its explicit assignment until HW; role sorting can otherwise
-- change which one-energy actor is stop 1/2 or attack 1/2/3/4.
function P.hw(rules, members, controlledRole, selected)
    return choose('sigma_hw', rules.hw, members, controlledRole, selected, {'world', 'energy'})
end

return P
