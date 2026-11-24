-- PvP: honor, honor level and the seasonal PvP rank per character.
-- Forever's rank is a renown track on faction 2800 (Blizzard_UIPanels_Game/Camelot/PVPRankFrame.lua): a rank level,
-- points towards the next one, and a weekly cap on how high you may climb this week.
local _, TM = ...

local M = TM:NewModule("pvp", {
    title = "PvP",
    icon = "PvP", -- Media/Icons
    subtitle = "Honor, honor level and PvP rank, with this week's rank cap.",
    order = 75,
    defaults = { rows = { honor = true, honorLevel = true, rank = true, rankProgress = true, weeklyCap = true } },
})

local RANK_FACTION = 2800 -- PVP_RANK_POINTS_FACTION_ID in PVPRankFrame.lua

-- "Sergeant", "Knight-Captain": the game's own rank title for this faction and gender.
local function RankTitle(rank)
    if not rank or rank <= 0 then return PVP_RANK_0_NAME end
    local base = Enum and Enum.PvPRanks and Enum.PvPRanks.Rank_1
    if not (base and GetText) then return nil end
    local alliance = UnitFactionGroup("player") == "Alliance" and 1 or 0
    local ok, title = pcall(GetText, "PVP_RANK_" .. (base + rank - 1) .. "_" .. alliance, UnitSex("player"))
    return ok and title or nil
end

function M:OnEnable()
    for _, e in ipairs({ "HONOR_XP_UPDATE", "HONOR_LEVEL_UPDATE", "MAJOR_FACTION_RENOWN_LEVEL_CHANGED", "UPDATE_FACTION" }) do
        self:On(e, function() self:CollectSoon(1) end)
    end
end

function M:Collect()
    local d = self:Data()
    if UnitHonor then
        local honor, max, level = UnitHonor("player"), UnitHonorMax and UnitHonorMax("player"), UnitHonorLevel and UnitHonorLevel("player")
        if TM.Usable(honor) then d.honor = honor end
        if TM.Usable(max) then d.honorMax = max end
        if TM.Usable(level) then d.honorLevel = level end
    end
    local info = C_MajorFactions and C_MajorFactions.GetMajorFactionProgressionInfo
        and C_MajorFactions.GetMajorFactionProgressionInfo(RANK_FACTION)
    if info and TM.Usable(info.renownLevel) then
        d.rank = info.renownLevel
        d.rankTitle = RankTitle(info.renownLevel)
        d.rankPoints, d.rankNext = info.renownReputationEarned, info.renownLevelThreshold
        d.weekCap, d.seasonCap = info.currentWeekProgressiveMaxLevel, info.maxLevel
        d.week = info.weekNumber
        local left = C_SeasonInfo and C_SeasonInfo.GetTimeUntilCurrentPVPSeasonEnd and C_SeasonInfo.GetTimeUntilCurrentPVPSeasonEnd()
        d.seasonEnds = TM.Usable(left) and left > 0 and (time() + left) or nil
        d.capReset = TM.NextReset("weekly")
    end
    self:Changed()
end

-- This week's cap stops meaning anything at the weekly reset: the next login reads the new one.
function M:Prune(d, now)
    if d.capReset and d.capReset <= now then d.weekCap, d.capReset = nil, nil end
end

local function RankTip(d)
    return function(tt)
        tt:AddDoubleLine("Rank " .. tostring(d.rank or 0), d.rankTitle or "", 1, 1, 1, 1, 0.82, 0)
        if TM.Usable(d.rankPoints) and TM.Usable(d.rankNext) and d.rankNext > 0 then
            tt:AddDoubleLine("Next rank", ("%s / %s"):format(TM.Commas(d.rankPoints), TM.Commas(d.rankNext)), 0.7, 0.7, 0.7, 1, 1, 1)
        end
        if d.weekCap then tt:AddDoubleLine("Highest rank this week", tostring(d.weekCap), 0.7, 0.7, 0.7, 1, 1, 1) end
        if d.seasonCap and d.seasonCap > 0 then tt:AddDoubleLine("Highest rank this season", tostring(d.seasonCap), 0.7, 0.7, 0.7, 1, 1, 1) end
        if d.seasonEnds and d.seasonEnds > time() then
            tt:AddDoubleLine("Season ends in", TM.Duration(d.seasonEnds - time()), 0.7, 0.7, 0.7, 1, 1, 1)
        end
    end
end

local ROWS = {
    {
        key = "honor", label = "Honor",
        cell = function(d)
            if not d.honor then return nil end
            return TM.Number(d.honor), function(tt)
                tt:AddDoubleLine("Honor", d.honorMax and d.honorMax > 0
                    and ("%s / %s"):format(TM.Commas(d.honor), TM.Commas(d.honorMax)) or TM.Commas(d.honor), 1, 1, 1, 1, 1, 1)
            end
        end,
    },
    {
        key = "honorLevel", label = "Honor level",
        cell = function(d)
            if not d.honorLevel then return nil end
            return tostring(d.honorLevel)
        end,
    },
    {
        key = "rank", label = "PvP rank",
        cell = function(d)
            if not d.rank then return nil end
            if d.rank <= 0 then return TM.Paint("-", TM.C.dim), RankTip(d) end
            return tostring(d.rank) .. (d.rankTitle and (" " .. TM.Paint(d.rankTitle, TM.C.dim)) or ""), RankTip(d)
        end,
        wrap = true,
    },
    {
        key = "rankProgress", label = "Rank progress",
        cell = function(d)
            if not (TM.Usable(d.rankPoints) and TM.Usable(d.rankNext) and d.rankNext > 0) then return nil end
            return ("%d%%"):format(math.floor(d.rankPoints / d.rankNext * 100)), RankTip(d)
        end,
    },
    {
        key = "weeklyCap", label = "Weekly rank cap",
        cell = function(d)
            if not (d.rank and d.weekCap) then return nil end
            local capped = d.rank >= d.weekCap
            local text = ("%d / %d"):format(d.rank, d.weekCap)
            return capped and TM.Paint(text, TM.C.good) or text, function(tt)
                tt:AddLine(capped and "At this week's highest rank." or "Room to climb this week.", 1, 1, 1)
                if d.capReset then tt:AddDoubleLine("Cap rises in", TM.Duration(d.capReset - time()), 0.7, 0.7, 0.7, 1, 1, 1) end
            end
        end,
    },
}

function M:Rows(add)
    for _, r in ipairs(ROWS) do
        if self.db.rows[r.key] then
            add({
                key = r.key, label = r.label, wrap = r.wrap,
                cell = function(toon)
                    local d = self:Peek(toon)
                    if not d then return nil end
                    return r.cell(d)
                end,
            })
        end
    end
end

function M:BuildOptions(W, parent, y, O)
    local R = O.Rows(self.db.rows)
    y = O.Header(W, parent, y, "HONOR")
    y = O.Pair(W, parent, y, R.Toggle("honor", "Honor"), R.Toggle("honorLevel", "Honor level"))
    y = O.Header(W, parent, y, "RANK")
    y = O.Pair(W, parent, y, R.Toggle("rank", "PvP rank", { tooltip = "Rank number and title. The tooltip has the season." }),
        R.Toggle("rankProgress", "Progress to next rank"))
    y = O.Pair(W, parent, y, R.Toggle("weeklyCap", "Weekly rank cap", { tooltip = "Rank against the highest rank allowed this week. Green once you have reached it." }))
    return y
end
