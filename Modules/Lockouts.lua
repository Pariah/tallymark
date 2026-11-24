-- Lockouts: raid and dungeon saves (and world bosses) from the Raid Info panel, with boss progress per character.
-- Every instance anyone is saved to gets a row; pinned instances (Data/Tracked.lua `lockouts`, or the options) keep
-- their row when nobody is, so you can see who is free.
local _, TM = ...

local M = TM:NewModule("lockouts", {
    title = "Lockouts",
    icon = "Lockouts", -- Media/Icons
    subtitle = "Raid and dungeon saves for every character, with reset timers.",
    order = 20,
    list = true,
    defaults = { showAllSaved = true, groupByType = true, worldBosses = true, worldBossKills = true, style = "progress", footerSoonest = true },
})

-- World bosses may not leave a save on Forever, so a kill is recorded too (until the weekly reset) from BOSS_KILL /
-- ENCOUNTER_END. Addons can't read the combat log on Forever, so these two events are the only signal.
local function IsWorldBoss(name)
    for _, n in ipairs(TM.Tracked and TM.Tracked.worldBosses or {}) do
        if n == name then return true end
    end
    return false
end

function M:SeenKill(name)
    if not (self.db.worldBossKills and type(name) == "string" and IsWorldBoss(name)) then return end
    local d = self:Data()
    d.kills = d.kills or {}
    d.kills[name] = { at = time(), expires = TM.NextReset("weekly") or (time() + 7 * 86400) }
    TM.db.instances[name] = { world = true }
    self:CollectSoon(0.5)
end

M.STYLE_VALUES = { progress = "Bosses killed (3/10)", check = "Saved mark only" }
M.STYLE_ORDER = { "progress", "check" }

function M:OnLoad()
    TM.db.instances = TM.db.instances or {} -- every instance name seen in a lockout: { raid = bool, world = bool }
end

function M:OnEnable()
    self:On("UPDATE_INSTANCE_INFO", function() self:CollectSoon(0.5) end)
    local function Ask() C_Timer.After(2, function() if RequestRaidInfo then RequestRaidInfo() end end) end
    self:On("BOSS_KILL", Ask)
    self:On("ENCOUNTER_END", function(_, _, _, _, _, _, success) if success == 1 then Ask() end end)
    self:On("BOSS_KILL", function(_, _, _, name) self:SeenKill(name) end)
    self:On("ENCOUNTER_END", function(_, _, _, name, _, _, success) if success == 1 then self:SeenKill(name) end end)
    self:On("RAID_INSTANCE_WELCOME", Ask)
    self:On("PLAYER_ENTERING_WORLD", Ask)
    if RequestRaidInfo then RequestRaidInfo() end
end

function M:Collect()
    if not (GetNumSavedInstances and GetSavedInstanceInfo) then return end
    local d = self:Data()
    local locks = {}
    local now = time()
    for i = 1, GetNumSavedInstances() do
        local name, lockID, reset, diffID, locked, extended, _, isRaid, maxPlayers, diffName, numEnc, encDone = GetSavedInstanceInfo(i)
        if name and (locked or extended) and TM.Usable(reset) and reset > 0 then
            local bosses
            if TM.Usable(numEnc) and numEnc > 0 and GetSavedInstanceEncounterInfo then
                bosses = {}
                for j = 1, numEnc do
                    local bossName, _, killed = GetSavedInstanceEncounterInfo(i, j)
                    bosses[j] = { bossName or ("Boss " .. j), killed and true or false }
                end
            end
            locks[name .. "|" .. tostring(diffName or diffID or "")] = {
                name = name, diff = diffName, id = lockID, expires = now + reset, extended = extended and true or nil,
                raid = isRaid and true or nil, size = maxPlayers, killed = encDone, total = numEnc, bosses = bosses,
            }
            TM.db.instances[name] = { raid = isRaid and true or nil }
        end
    end
    if GetNumSavedWorldBosses and GetSavedWorldBossInfo then
        for i = 1, GetNumSavedWorldBosses() do
            local name, _, reset = GetSavedWorldBossInfo(i)
            if name and TM.Usable(reset) and reset > 0 then
                locks["world|" .. name] = { name = name, diff = "World boss", expires = now + reset, world = true }
                TM.db.instances[name] = { world = true }
            end
        end
    end
    -- Kills seen without a save: a lock of their own until the weekly reset.
    for name, k in pairs(d.kills or {}) do
        if not TM.Expired(k.expires, now) and not locks["world|" .. name] then
            locks["kill|" .. name] = { name = name, diff = "Kill seen", expires = k.expires, world = true, kill = k.at }
        end
    end
    d.locks = locks
    self:Changed()
end

function M:Prune(d, now)
    for k, l in pairs(d.locks or {}) do
        if TM.Expired(l.expires, now) then d.locks[k] = nil end
    end
    for name, k in pairs(d.kills or {}) do
        if TM.Expired(k.expires, now) then d.kills[name] = nil end
    end
end

function M:Describe(e)
    return e.name or e.id
end

-- Locks a character holds on one instance name, live ones only.
local function LocksFor(d, name)
    local out
    if not (d and d.locks) then return nil end
    local now = time()
    for _, l in pairs(d.locks) do
        if l.name == name and not TM.Expired(l.expires, now) then
            out = out or {}
            out[#out + 1] = l
        end
    end
    if out then table.sort(out, function(a, b) return tostring(a.diff) < tostring(b.diff) end) end
    return out
end

local function Short(diff)
    if not diff or diff == "" then return "" end
    local n = diff:match("(%d+)")
    if diff:find("Heroic") then return "H" .. (n or "") end
    if diff:find("Mythic") then return "M" .. (n or "") end
    return n or diff:sub(1, 1)
end

local function LockText(l, style, several)
    local text
    if style == "check" or not (l.total and l.total > 0) then
        text = TM.CHECK
    else
        local k = l.killed or 0
        local c = k >= l.total and TM.C.bad or TM.C.warn
        text = TM.Paint(("%d/%d"):format(k, l.total), c)
    end
    if several then text = TM.Paint(Short(l.diff), TM.C.dim) .. " " .. text end
    return text
end

local function LockTip(locks)
    return function(tt)
        local now = time()
        for i, l in ipairs(locks) do
            if i > 1 then tt:AddLine(" ") end
            tt:AddDoubleLine(l.diff or (l.world and "World boss") or "Saved", "resets in " .. TM.Duration(l.expires - now), 1, 0.82, 0, 1, 1, 1)
            if l.id and l.id ~= 0 then tt:AddDoubleLine("Lock ID", tostring(l.id), 0.7, 0.7, 0.7, 0.7, 0.7, 0.7) end
            if l.extended then tt:AddLine("Extended", 0.4, 0.8, 1) end
            if l.kill then
                tt:AddDoubleLine("Killed", date("%a %d %b, %H:%M", l.kill), 0.7, 0.7, 0.7, 1, 1, 1)
                tt:AddLine("No save in the Raid Info panel: this is the kill Tallymark saw.", 0.7, 0.7, 0.7, true)
            end
            if l.bosses then
                for _, b in ipairs(l.bosses) do
                    if b[2] then
                        tt:AddDoubleLine(b[1], "Defeated", 1, 1, 1, 1, 0.38, 0.38)
                    else
                        tt:AddDoubleLine(b[1], "Available", 1, 1, 1, 0.3, 0.85, 0.45)
                    end
                end
            end
        end
    end
end

function M:Rows(add, toons)
    local names, pinned = {}, {}
    for _, e in ipairs(self:Entries()) do
        names[e.id] = true
        pinned[e.id] = true
    end
    if self.db.showAllSaved then
        for _, entry in ipairs(toons) do
            local d = self:Peek(entry.toon)
            if d and d.locks then
                for _, l in pairs(d.locks) do
                    if not TM.Expired(l.expires) and (self.db.worldBosses or not l.world) then names[l.name] = true end
                end
            end
        end
    end
    local list = {}
    for name in pairs(names) do list[#list + 1] = name end
    local info = TM.db.instances
    local function Kind(name)
        local i = info[name]
        if i and i.world then return 3, "World Bosses" end
        if i and i.raid then return 1, "Raids" end
        return 2, "Dungeons"
    end
    table.sort(list, function(a, b)
        local ka, kb = Kind(a), Kind(b)
        if self.db.groupByType and ka ~= kb then return ka < kb end
        return a < b
    end)
    local style = self.db.style
    for _, name in ipairs(list) do
        local _, group = Kind(name)
        add({
            key = name, label = name, keep = pinned[name], group = self.db.groupByType and group or nil,
            cell = function(toon)
                local locks = LocksFor(self:Peek(toon), name)
                if not locks then return nil end
                local parts = {}
                for i, l in ipairs(locks) do parts[i] = LockText(l, style, #locks > 1) end
                return table.concat(parts, "  "), LockTip(locks)
            end,
        })
    end
end

function M:Footer(add)
    -- The soonest reset among the shown characters' locks, the one worth knowing about.
    local soonest
    for _, e in ipairs(TM:Toons()) do
        local d = self:Peek(e.toon)
        if d and d.locks then
            for _, l in pairs(d.locks) do
                if not TM.Expired(l.expires) and (not soonest or l.expires < soonest.expires) then soonest = l end
            end
        end
    end
    if soonest and self.db.footerSoonest then
        add(("Next lockout reset: %s (%s)"):format(TM.Duration(soonest.expires - time()), soonest.name))
    end
end

function M:BuildOptions(W, parent, y, O)
    local R = O.Rows(self.db)
    y = O.Header(W, parent, y, "BOARD")
    y = O.Pair(W, parent, y,
        R.Toggle("showAllSaved", "Show every saved instance", { tooltip = "Off: only pinned instances get rows." }),
        R.Toggle("groupByType", "Group by raid / dungeon"))
    y = O.Pair(W, parent, y,
        R.Toggle("worldBosses", "World boss saves"),
        R.Dropdown("style", "Cell shows", M.STYLE_VALUES, M.STYLE_ORDER))
    y = O.Pair(W, parent, y, R.Toggle("footerSoonest", "Next reset in the footer"),
        R.Toggle("worldBossKills", "Record world boss kills", { tooltip = "A world boss kill (Data/Tracked.lua worldBosses) shows until the weekly reset, for when the Raid Info panel has no save for it." }))

    y = O.Header(W, parent, y, "PINNED INSTANCES")
    y = O.Note(parent, y, "Pinned instances always get a row. Type the name as the Raid Info panel shows it.")
    y = O.TrackedList(self, W, parent, y, {
        placeholder = "Instance name",
        parse = function(text)
            text = strtrim(text or "")
            if text == "" then return {} end
            return { { id = text } }
        end,
        describe = function(e)
            local i = TM.db.instances[e.id]
            return e.id, nil, i and (i.world and "World boss" or i.raid and "Raid" or "Dungeon") or "Not seen yet"
        end,
        discoverTitle = "SEEN IN A LOCKOUT",
        discover = function()
            local out = {}
            for name, i in pairs(TM.db.instances) do
                if not self:HasEntry(name) then
                    out[#out + 1] = { entry = { id = name }, text = name, sub = i.world and "World boss" or i.raid and "Raid" or "Dungeon" }
                end
            end
            table.sort(out, function(a, b) return a.text < b.text end)
            return out
        end,
    })
    return y
end
