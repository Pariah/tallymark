-- Character: level, gold, rested XP, item level, where they logged out, hearthstone, played time and when they were
-- last played.
local _, TM = ...

local M = TM:NewModule("character", {
    title = "Character",
    icon = "Character", -- Media/Icons
    subtitle = "Level, gold, rested XP, location, hearthstone, played time and last played for each character.",
    order = 10,
    defaults = {
        rows = {
            level = true, gold = true, rested = true, ilvl = false, zone = false, hearth = true,
            played = true, playedLevel = false, lastSeen = true,
        },
        totalGold = true,
        playedHeader = true, -- account-wide played time beside the reset timers
        quietPlayed = true, -- keep the /played answer Tallymark asks for out of chat
    },
})

local REST_PER_8H = 0.05 -- rested XP gained per 8 hours in an inn, as a share of a level (a quarter of it outside)
local REST_CAP = 1.5

-- Well Rested, a Legacy talent (up to 5 ranks): each rank makes rested XP build 4% faster and raises the cap.
-- The cap is read as additive (150% + 4 points a rank, 170% at 5/5). If it turns out to be multiplicative
-- (150% x 1.2 = 180%), change RestCap to REST_CAP * (1 + rank * WELL_RESTED_STEP).
local WELL_RESTED_SPELL = 1225478
local WELL_RESTED_STEP = 0.04
local LEGACY_TREES = { 1187, 1188, 1189 } -- Professions, Adventure, Progression (Constants.LegacyConsts)

local function RestRate(rank) return REST_PER_8H * (1 + (rank or 0) * WELL_RESTED_STEP) end
local function RestCap(rank) return REST_CAP + (rank or 0) * WELL_RESTED_STEP end

local function LegacyTrees()
    local c = Constants and Constants.LegacyConsts
    if c and c.LEGACY_TREE_PROFESSIONS_ID then
        return { c.LEGACY_TREE_PROFESSIONS_ID, c.LEGACY_TREE_ADVENTURE_ID, c.LEGACY_TREE_PROGRESSION_ID }
    end
    return LEGACY_TREES
end

-- Rank in Well Rested, or nil when the Legacy trees can't be read yet (no config before the trait system loads).
-- The node is found once per session by its spell, then read directly.
local wellRestedNode -- { configID, nodeID }
local function WellRestedRank()
    if not (C_Traits and C_Traits.GetConfigIDByTreeID) then return nil end
    if wellRestedNode then
        local info = C_Traits.GetNodeInfo(wellRestedNode[1], wellRestedNode[2])
        if info then return info.activeRank or 0 end
        wellRestedNode = nil
    end
    local anyConfig = false
    for _, treeID in ipairs(LegacyTrees()) do
        local configID = treeID and C_Traits.GetConfigIDByTreeID(treeID)
        if configID then
            anyConfig = true
            for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
                local info = C_Traits.GetNodeInfo(configID, nodeID)
                for _, entryID in ipairs(info and info.entryIDs or {}) do
                    local entry = C_Traits.GetEntryInfo(configID, entryID)
                    local def = entry and entry.definitionID and C_Traits.GetDefinitionInfo(entry.definitionID)
                    if def and def.spellID == WELL_RESTED_SPELL then
                        wellRestedNode = { configID, nodeID }
                        return info.activeRank or 0
                    end
                end
            end
        end
    end
    -- Trees loaded but no such talent on them: count it as none rather than asking again every collect.
    return anyConfig and 0 or nil
end

local function MaxLevel()
    if GetMaxLevelForPlayerExpansion then return GetMaxLevelForPlayerExpansion() end
    return MAX_PLAYER_LEVEL or 60
end

-- Played time comes from RequestTimePlayed, answered by TIME_PLAYED_MSG, which every chat frame also prints
-- (ChatFrameUtil.DisplayTimePlayed). With quietPlayed on, that printer is a no-op only from our request until the
-- answer has been handled, so a /played you type yourself still shows.
local restorePrinter
local function RestorePrinter()
    if restorePrinter then
        restorePrinter()
        restorePrinter = nil
    end
end

function M:WantsPlayed()
    local r = self.db.rows
    return r.played or r.playedLevel or self.db.playedHeader
end

function M:RequestPlayed()
    if not RequestTimePlayed then return end
    local util = ChatFrameUtil
    if self.db.quietPlayed and util and util.DisplayTimePlayed and not restorePrinter then
        local original = util.DisplayTimePlayed
        util.DisplayTimePlayed = function() end
        restorePrinter = function() util.DisplayTimePlayed = original end
        C_Timer.After(10, RestorePrinter) -- the answer never came
    end
    RequestTimePlayed()
end

function M:OnEnable()
    for _, e in ipairs({ "PLAYER_MONEY", "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION", "PLAYER_UPDATE_RESTING",
        "ZONE_CHANGED_NEW_AREA", "PLAYER_EQUIPMENT_CHANGED", "HEARTHSTONE_BOUND" }) do
        self:On(e, function() self:CollectSoon(1) end)
    end
    self:On("TIME_PLAYED_MSG", function(_, _, total, thisLevel)
        local d = self:Data()
        if TM.Usable(total) then d.played = total end
        if TM.Usable(thisLevel) then d.playedLevel = thisLevel end
        d.playedAt = time()
        -- Every chat frame handles this same event; put the printer back once they all have.
        if restorePrinter then C_Timer.After(0, RestorePrinter) end
        self:Changed()
    end)
    -- A new level starts its own clock: fold the time so far into the total.
    self:On("PLAYER_LEVEL_UP", function()
        local d = self:Data()
        if d.played and d.playedAt then
            d.played = d.played + (time() - d.playedAt)
            d.playedLevel, d.playedAt = 0, time()
        end
    end)
    if self:WantsPlayed() then C_Timer.After(5, function() self:RequestPlayed() end) end
    -- Legacy points spent or refunded: read Well Rested again.
    for _, e in ipairs({ "TRAIT_CONFIG_UPDATED", "TRAIT_TREE_CURRENCY_INFO_UPDATED" }) do
        self:On(e, function()
            self.recheckLegacy = true
            self:CollectSoon(1)
        end)
    end
end

function M:Collect()
    if TM.loggingOut then return end
    local d = self:Data()
    -- Well Rested: read the first time a character is seen, then only after Legacy points change.
    if d.wellRested == nil or self.recheckLegacy then
        local rank = WellRestedRank()
        if rank then
            d.wellRested = rank
            self.recheckLegacy = nil
        end
    end
    d.money = GetMoney()
    d.xp, d.xpMax = UnitXP("player"), UnitXPMax("player")
    d.rested = GetXPExhaustion() or 0
    d.resting = IsResting() and true or false
    d.maxLevel = (UnitLevel("player") or 0) >= MaxLevel()
    if GetAverageItemLevel then
        local _, equipped = GetAverageItemLevel()
        if TM.Usable(equipped) and equipped > 0 then d.ilvl = equipped end
    end
    d.zone = GetRealZoneText and GetRealZoneText() or d.zone
    local bind = GetBindLocation and GetBindLocation()
    if type(bind) == "string" and bind ~= "" then d.hearth = bind end
    d.at = time()
    self:Changed()
end

-- Rested XP now, as a share of a level: what was saved plus what accrued since (offline characters keep resting).
local function RestedShare(d)
    if not (d.xpMax and d.xpMax > 0) or d.maxLevel then return nil end
    local share = (d.rested or 0) / d.xpMax
    if d.at then
        local hours8 = (time() - d.at) / 28800
        share = share + hours8 * RestRate(d.wellRested) * (d.resting and 1 or 0.25)
    end
    return math.min(share, RestCap(d.wellRested))
end

-- Played seconds (total, this level). The character being played keeps counting from the last answer.
local function Played(d, current)
    if not (d and d.played) then return nil end
    local extra = (current and d.playedAt) and math.max(time() - d.playedAt, 0) or 0
    return d.played + extra, d.playedLevel and (d.playedLevel + extra)
end
M.Played = Played

local function PlayedTip(d, current)
    return function(tt)
        local total, level = Played(d, current)
        tt:AddDoubleLine("Played", TM.Duration(total), 1, 1, 1, 1, 1, 1)
        if level then tt:AddDoubleLine("This level", TM.Duration(level), 0.7, 0.7, 0.7, 1, 1, 1) end
    end
end

local ROWS = {
    {
        key = "level", label = "Level",
        cell = function(toon, d)
            if not toon.level then return nil end
            local text = tostring(toon.level)
            if d and d.xpMax and d.xpMax > 0 and not d.maxLevel then
                return text, function(tt)
                    tt:AddDoubleLine("Experience", ("%s / %s (%d%%)"):format(TM.Commas(d.xp or 0), TM.Commas(d.xpMax),
                        math.floor((d.xp or 0) / d.xpMax * 100)), 1, 1, 1, 1, 1, 1)
                end
            end
            return text
        end,
    },
    {
        key = "gold", label = "Gold",
        cell = function(_, d)
            if not (d and d.money) then return nil end
            return TM.Gold(d.money), function(tt) tt:AddLine(TM.Gold(d.money, true), 1, 1, 1) end
        end,
    },
    {
        key = "rested", label = "Rested",
        cell = function(_, d)
            local share = d and RestedShare(d)
            if not share then return nil end
            local cap = RestCap(d.wellRested)
            local pct = math.floor(share * 100 + 0.5)
            local text = pct .. "%"
            if share >= cap then text = TM.Paint(text, TM.C.good) elseif pct == 0 then text = TM.Paint(text, TM.C.dim) end
            return text, function(tt)
                tt:AddDoubleLine("Rested", ("%d%% of a level"):format(pct), 1, 1, 1, 1, 1, 1)
                tt:AddDoubleLine("Max", ("%d%%"):format(math.floor(cap * 100 + 0.5)), 0.7, 0.7, 0.7, 1, 1, 1)
                if (d.wellRested or 0) > 0 then
                    tt:AddDoubleLine("Well Rested", ("Rank %d (+%d%% rate)"):format(d.wellRested,
                        math.floor(d.wellRested * WELL_RESTED_STEP * 100 + 0.5)), 0.7, 0.7, 0.7, 0.7, 0.7, 0.7)
                end
                tt:AddLine(d.resting and "Logged out resting." or "Logged out outside an inn (rests at a quarter rate).", 0.7, 0.7, 0.7, true)
            end
        end,
    },
    {
        key = "ilvl", label = "Item level",
        cell = function(_, d)
            if not (d and d.ilvl) then return nil end
            return ("%.1f"):format(d.ilvl)
        end,
    },
    {
        key = "zone", label = "Location", wrap = true, -- long zone names take a second line
        cell = function(_, d)
            if not (d and d.zone and d.zone ~= "") then return nil end
            return TM.Paint(d.zone, TM.C.dim), function(tt) tt:AddLine(d.zone, 1, 1, 1) end
        end,
    },
    {
        key = "hearth", label = "Hearthstone", wrap = true,
        cell = function(_, d)
            if not (d and d.hearth) then return nil end
            return TM.Paint(d.hearth, TM.C.dim), function(tt)
                tt:AddDoubleLine("Hearthstone", d.hearth, 0.7, 0.7, 0.7, 1, 1, 1)
            end
        end,
    },
    {
        key = "played", label = "Played",
        cell = function(_, d, current)
            local total = Played(d, current)
            if not total then return nil end
            return TM.Duration(total), PlayedTip(d, current)
        end,
    },
    {
        key = "playedLevel", label = "Played this level",
        cell = function(_, d, current)
            local _, level = Played(d, current)
            if not level then return nil end
            return TM.Duration(level), PlayedTip(d, current)
        end,
    },
    {
        key = "lastSeen", label = "Last played",
        cell = function(toon, _, current)
            if current then return TM.Paint("now", TM.C.good) end
            if not toon.lastSeen then return nil end
            return TM.Paint(TM.Duration(time() - toon.lastSeen), TM.C.dim), function(tt)
                tt:AddLine(date("%A %d %B, %H:%M", toon.lastSeen), 1, 1, 1)
            end
        end,
    },
}
M.ROWS = ROWS

function M:Rows(add)
    for _, r in ipairs(ROWS) do
        if self.db.rows[r.key] then
            add({
                key = r.key, label = r.label, wrap = r.wrap,
                cell = function(toon, _, current) return r.cell(toon, self:Peek(toon), current) end,
            })
        end
    end
end

function M:Footer(add, toons)
    if not self.db.totalGold then return end
    local total, n = 0, 0
    for _, e in ipairs(TM:Toons(true)) do
        local d = self:Peek(e.toon)
        if d and d.money then
            total = total + d.money
            n = n + 1
        end
    end
    if n > 1 then add(("Gold across %d characters: %s"):format(n, TM.Gold(total, true))) end
end

-- Account played time, every known character (hidden ones too), beside the reset timers.
function M:Header(add)
    if not self.db.playedHeader then return end
    local total, any = 0, false
    for guid, t in pairs(TM.db.toons) do
        local p = Played(self:Peek(t), guid == TM.thisGUID)
        if p then
            total = total + p
            any = true
        end
    end
    if any then add("Played " .. TM.Paint(TM.Duration(total), TM.C.text)) end
end

function M:BuildOptions(W, parent, y, O)
    local R = O.Rows(self.db.rows)
    y = O.Header(W, parent, y, "ROWS")
    y = O.Pair(W, parent, y, R.Toggle("level", "Level"), R.Toggle("gold", "Gold"))
    y = O.Pair(W, parent, y, R.Toggle("rested", "Rested XP", { tooltip = "Keeps counting while a character is offline: full rate if they logged out in an inn, a quarter outside." }),
        R.Toggle("ilvl", "Item level"))
    y = O.Pair(W, parent, y, R.Toggle("zone", "Location", { tooltip = "Where the character logged out." }),
        R.Toggle("hearth", "Hearthstone", { tooltip = "Where the character's hearthstone is set." }))
    -- A played row turned on mid-session asks the server once, so it fills in without a relog.
    local function AskPlayed()
        TM.board:ApplySettings()
        if TM.loggedIn and self:IsEnabled() and self:WantsPlayed() and not self:Data().played then self:RequestPlayed() end
    end
    local RP = O.Rows(self.db.rows, AskPlayed)
    y = O.Pair(W, parent, y, RP.Toggle("played", "Played time"), RP.Toggle("playedLevel", "Played this level"))
    y = O.Pair(W, parent, y, R.Toggle("lastSeen", "Last played"))
    local G = O.Rows(self.db)
    local GP = O.Rows(self.db, AskPlayed)
    y = O.Header(W, parent, y, "TITLE BAR")
    y = O.Pair(W, parent, y,
        GP.Toggle("playedHeader", "Played time, all characters", { tooltip = "Beside the daily and weekly reset timers." }),
        G.Toggle("quietPlayed", "Keep /played out of chat", { tooltip = "Tallymark asks the server for played time once per login. On: that answer is not printed. A /played you type still is." }))
    y = O.Header(W, parent, y, "FOOTER")
    y = O.Pair(W, parent, y, G.Toggle("totalGold", "Total gold across characters"))
    return y
end
