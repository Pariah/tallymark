-- Quests: tracked quest IDs with a reset kind (daily, weekly or once), done or not per character.
-- Daily and weekly completions expire at the next reset; one-time quests (attunements, unlocks) stay done.
-- With auto-track on, any daily or weekly quest you turn in is added to the list by itself.
--
-- A pool is one row over several quest IDs: `any = { ids }`, done when any of them is. It suits a quest that comes
-- back under a new ID each week (Weekly Pix). With `npc` set, a quest of the pool's reset kind turned in to that NPC
-- joins the pool by itself. The IDs from Data/Tracked.lua and the ones learned in game are merged.
local _, TM = ...

local M = TM:NewModule("quests", {
    title = "Quests",
    icon = "Quests", -- Media/Icons
    subtitle = "Daily, weekly and one-time quests: who has done them and who has not.",
    order = 30,
    list = true,
    defaults = { autoTrack = true, showNotDone = true, groupByReset = true },
})

local RESETS = { daily = "Daily", weekly = "Weekly", once = "One-time" }
local RESET_CYCLE = { daily = "weekly", weekly = "once", once = "daily" }
local RESET_RANK = { daily = 1, weekly = 2, once = 3 }
M.RESETS = RESETS

local logFrequency = {} -- questID -> "daily" | "weekly" for quests in the log, so a turn-in knows what it was
local turnInNPC = {} -- questID -> name of the NPC on the reward window

function M:OnLoad()
    TM.db.questNames = TM.db.questNames or {}
end

-- A pool's quest IDs: the default entry's and the in-game copy's, merged (learning an ID copies the default into
-- the in-game list, and IDs added to Data/Tracked.lua later must still count).
function M:PoolIDs(e)
    if not e.any then return nil end
    local ids, seen = {}, {}
    local function Add(list)
        for _, id in ipairs(list or {}) do
            if not seen[id] then
                seen[id] = true
                ids[#ids + 1] = id
            end
        end
    end
    for _, d in ipairs(self:Defaults()) do
        if d.id == e.id then Add(d.any) end
    end
    Add(e.any)
    return ids
end

-- The pool a quest ID belongs to, or the pool fed by this NPC for a quest of its reset kind.
function M:PoolFor(questID, npc, kind)
    for _, e in ipairs(self:Entries()) do
        if e.any then
            for _, id in ipairs(self:PoolIDs(e)) do
                if id == questID then return e, false end
            end
            if npc and e.npc == npc and kind == e.reset then return e, true end
        end
    end
end

local function IsDone(M, e)
    local done = C_QuestLog.IsQuestFlaggedCompleted
    if not e.any then return done(e.id) end
    for _, id in ipairs(M:PoolIDs(e)) do
        if done(id) then return true end
    end
    return false
end

local function FrequencyKind(freq)
    local F = Enum and Enum.QuestFrequency
    if not freq or not F then return nil end
    if freq == F.Daily then return "daily" end
    if freq == F.Weekly then return "weekly" end
end

local function ScanLog()
    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries) then return end
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and info.questID then
            local kind = FrequencyKind(info.frequency)
            if kind then logFrequency[info.questID] = kind end
            if info.title then TM.db.questNames[info.questID] = info.title end
        end
    end
end

function M:QuestName(id, fallback)
    local name = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id)
    if name and name ~= "" then
        TM.db.questNames[id] = name
        return name
    end
    name = TM.db.questNames[id] or fallback
    if not name and C_QuestLog.RequestLoadQuestByID then C_QuestLog.RequestLoadQuestByID(id) end
    return name or ("Quest " .. id)
end

function M:Describe(e)
    if e.any then return e.name or tostring(e.id) end
    return self:QuestName(e.id, e.name)
end

function M:OnEnable()
    self:On("QUEST_LOG_UPDATE", function() TM.Debounce("questlog", 2, ScanLog) end)
    self:On("QUEST_DATA_LOAD_RESULT", function() self:Changed() end)
    -- The reward window still knows whether the quest repeats; the log entry may be gone by QUEST_TURNED_IN.
    self:On("QUEST_COMPLETE", function()
        local id = GetQuestID and GetQuestID()
        if not id or id == 0 then return end
        if QuestIsDaily and QuestIsDaily() then logFrequency[id] = "daily"
        elseif QuestIsWeekly and QuestIsWeekly() then logFrequency[id] = "weekly" end
        -- In battlegrounds the NPC name comes back as a secret string; comparing it later taints us, so drop it.
        local npc = UnitName("npc")
        if type(npc) ~= "string" or (issecretvalue and issecretvalue(npc)) then npc = nil end
        turnInNPC[id] = npc
    end)
    self:On("QUEST_TURNED_IN", function(_, _, questID) self:TurnedIn(questID) end)
    ScanLog()
end

function M:TurnedIn(questID)
    if not questID then return end
    local kind = logFrequency[questID]
    local pool, learned = self:PoolFor(questID, turnInNPC[questID], kind)
    if pool then
        if learned then
            local ids = self:PoolIDs(pool)
            ids[#ids + 1] = questID
            self:UpdateEntry(pool.id, { any = ids })
            TM.Say(("%s: learned quest ID %d."):format(self:Describe(pool), questID))
        end
        local d = self:Data()
        d.q = d.q or {}
        d.q[pool.id] = TM.NextReset(pool.reset) or true
        return self:Changed()
    end
    if kind and self.db.autoTrack and not self:HasEntry(questID) then
        self:AddEntry({ id = questID, reset = kind, name = TM.db.questNames[questID], auto = true })
        TM.Say(("Now tracking %s quest %s."):format(RESETS[kind]:lower(), self:QuestName(questID)))
    end
    local e = self:GetEntry(questID)
    if e then
        local d = self:Data()
        d.q = d.q or {}
        d.q[questID] = e.reset == "once" and true or TM.NextReset(e.reset) or true
        self:Changed()
    end
end

function M:Collect()
    local d = self:Data()
    local q = {}
    for _, e in ipairs(self:Entries()) do
        if IsDone(self, e) then
            local prev = d.q and d.q[e.id]
            if e.reset == "once" then
                q[e.id] = true
            else
                q[e.id] = (type(prev) == "number" and prev > time() and prev) or TM.NextReset(e.reset) or true
            end
        else
            q[e.id] = false
        end
    end
    d.q = q
    self:Changed()
end

function M:Prune(d, now)
    if not d.q then return end
    for id, v in pairs(d.q) do
        if type(v) == "number" and v <= now then d.q[id] = false end
    end
end

function M:Rows(add)
    local entries = self:Entries()
    if self.db.groupByReset then
        table.sort(entries, function(a, b)
            local ra, rb = RESET_RANK[a.reset] or 4, RESET_RANK[b.reset] or 4
            if ra ~= rb then return ra < rb end
            return self:Describe(a):lower() < self:Describe(b):lower()
        end)
    end
    for _, e in ipairs(entries) do
        local id, reset = e.id, e.reset
        add({
            key = id, label = self:Describe(e), keep = true,
            group = e.group or (self.db.groupByReset and RESETS[reset]) or nil,
            tip = function(tt)
                tt:AddLine(self:Describe(e), 1, 1, 1)
                local ids = self:PoolIDs(e)
                if ids then
                    if e.npc then tt:AddDoubleLine("From", e.npc, 0.7, 0.7, 0.7, 1, 1, 1) end
                    tt:AddDoubleLine("Quest IDs", table.concat(ids, ", "), 0.7, 0.7, 0.7, 1, 1, 1)
                else
                    tt:AddDoubleLine("Quest ID", tostring(id), 0.7, 0.7, 0.7, 1, 1, 1)
                end
                tt:AddDoubleLine("Resets", RESETS[reset] or "Never", 0.7, 0.7, 0.7, 1, 1, 1)
                if reset == "daily" or reset == "weekly" then
                    local t = TM.NextReset(reset)
                    if t then tt:AddDoubleLine("Next reset", TM.Duration(t - time()), 0.7, 0.7, 0.7, 1, 1, 1) end
                end
            end,
            cell = function(toon)
                local d = self:Peek(toon)
                local v = d and d.q and d.q[id]
                if v == nil then return nil end
                if v == false or TM.Expired(v) then return self.db.showNotDone and TM.CROSS or "" end
                return TM.CHECK
            end,
        })
    end
end

function M:BuildOptions(W, parent, y, O)
    local R = O.Rows(self.db)
    y = O.Header(W, parent, y, "BOARD")
    y = O.Pair(W, parent, y,
        R.Toggle("autoTrack", "Auto-track repeatable quests", { tooltip = "Daily and weekly quests you turn in are added to the list." }),
        R.Toggle("showNotDone", "Mark quests not done", { tooltip = "A cross where a character has not done the quest; off leaves the cell empty." }))
    y = O.Pair(W, parent, y, R.Toggle("groupByReset", "Group by reset", { tooltip = "Daily, Weekly and One-time sub-headings. A quest's own group wins." }))

    y = O.Header(W, parent, y, "TRACKED QUESTS")
    y = O.Note(parent, y, "Quest IDs or shift-clicked quests. Click the reset tag on a quest to change it.")
    y = O.TrackedList(self, W, parent, y, {
        placeholder = "Quest ID or link",
        parse = function(text)
            local out = {}
            for _, id in ipairs(TM.ParseIDs(text, "quest")) do
                out[#out + 1] = { id = id, reset = logFrequency[id] or "once" }
            end
            return out
        end,
        describe = function(e)
            local ids = self:PoolIDs(e)
            local idText = ids and (#ids .. " quest IDs" .. (e.npc and (" · " .. e.npc) or "")) or ("ID " .. e.id)
            local sub = e.group and (e.group .. " · " .. idText) or idText
            if e.auto then sub = sub .. " · auto" end
            return self:Describe(e), nil, sub
        end,
        actions = function(e)
            return { {
                text = RESETS[e.reset] or "Once",
                tip = "Click to change: daily, weekly, one-time.",
                onClick = function() self:UpdateEntry(e.id, { reset = RESET_CYCLE[e.reset] or "daily" }) end,
            } }
        end,
        discoverTitle = "IN YOUR QUEST LOG",
        discover = function()
            local out = {}
            if not C_QuestLog.GetNumQuestLogEntries then return out end
            for i = 1, C_QuestLog.GetNumQuestLogEntries() do
                local info = C_QuestLog.GetInfo(i)
                if info and not info.isHeader and not info.isHidden and info.questID and not self:HasEntry(info.questID)
                    and not self:PoolFor(info.questID) then
                    local kind = FrequencyKind(info.frequency) or "once"
                    out[#out + 1] = {
                        entry = { id = info.questID, reset = kind, name = info.title },
                        text = info.title or ("Quest " .. info.questID), sub = RESETS[kind] .. " · ID " .. info.questID,
                    }
                end
            end
            return out
        end,
    })
    return y
end
