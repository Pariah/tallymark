-- Tallymark tracked lists: what a module watches (quests, currencies, items, factions, cooldowns, pinned instances).
--
-- The defaults are the module's array in Data/Tracked.lua (TM.Tracked[moduleKey]); each entry is a table with an `id`
-- (number or string) plus whatever fields the module reads. The player's in-game changes live apart from them, in
-- TallymarkDB.lists[moduleKey]:
--   added   = { [id] = entry }   added in game, or a default edited in game (same id overrides the default)
--   removed = { [id] = true }    defaults taken off (Restore brings them back)
-- so editing Data/Tracked.lua after an update never fights with what was changed in game.
local _, TM = ...
local Module = TM.Module

local function Store(M)
    local lists = TM.db.lists
    local s = lists[M.key]
    if not s then
        s = { added = {}, removed = {} }
        lists[M.key] = s
    end
    s.added = s.added or {}
    s.removed = s.removed or {}
    return s
end

function Module:Defaults()
    return (TM.Tracked and TM.Tracked[self.key]) or {}
end

function Module:IsDefault(id)
    for _, e in ipairs(self:Defaults()) do
        if e.id == id then return true end
    end
    return false
end

-- Sort key: entry.group, then the module's display name for it.
local function SortName(M, e)
    local name = M.Describe and M:Describe(e) or e.name
    return ((e.group or "") .. "\1" .. tostring(name or e.id)):lower()
end

-- The live list: defaults not removed, overridden or extended by in-game additions. Sorted.
function Module:Entries()
    local s = Store(self)
    local out, seen = {}, {}
    for _, e in ipairs(self:Defaults()) do
        if e.id ~= nil and not s.removed[e.id] and not seen[e.id] then
            seen[e.id] = true
            out[#out + 1] = s.added[e.id] or e
        end
    end
    for id, e in pairs(s.added) do
        if not seen[id] then
            seen[id] = true
            e.id = id
            out[#out + 1] = e
        end
    end
    local keys = {}
    for _, e in ipairs(out) do keys[e] = SortName(self, e) end
    table.sort(out, function(a, b) return keys[a] < keys[b] end)
    return out
end

function Module:HasEntry(id)
    local s = Store(self)
    if s.added[id] then return true end
    return self:IsDefault(id) and not s.removed[id]
end

function Module:GetEntry(id)
    local s = Store(self)
    if s.added[id] then return s.added[id] end
    if s.removed[id] then return nil end
    for _, e in ipairs(self:Defaults()) do
        if e.id == id then return e end
    end
end

-- Adds (or replaces) an entry. Returns true when it was new.
function Module:AddEntry(entry)
    if type(entry) ~= "table" or entry.id == nil then return false end
    local s = Store(self)
    local isNew = not self:HasEntry(entry.id)
    s.removed[entry.id] = nil
    s.added[entry.id] = entry
    if TM.loggedIn and self:IsEnabled() and self.Collect then self:CollectSoon(0.2) end
    self:Changed()
    return isNew
end

-- Changes fields of an entry; a default is copied into the in-game list first.
function Module:UpdateEntry(id, fields)
    local e = self:GetEntry(id)
    if not e then return end
    local s = Store(self)
    if not s.added[id] then
        e = TM.DeepCopy(e)
        s.added[id] = e
    end
    for k, v in pairs(fields) do e[k] = v end
    if self.Collect and self:IsEnabled() then self:CollectSoon(0.2) end
    self:Changed()
end

function Module:RemoveEntry(id)
    local s = Store(self)
    s.added[id] = nil
    if self:IsDefault(id) then s.removed[id] = true end
    self:Changed()
end

function Module:RemovedDefaults()
    local n = 0
    for _ in pairs(Store(self).removed) do n = n + 1 end
    return n
end

function Module:RestoreDefaults()
    wipe(Store(self).removed)
    if self.Collect and self:IsEnabled() then self:CollectSoon(0.2) end
    self:Changed()
end
