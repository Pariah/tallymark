-- Reputation: tracked faction IDs, standing and progress per character.
local _, TM = ...

local M = TM:NewModule("reputation", {
    title = "Reputation",
    icon = "Reputation", -- Media/Icons
    subtitle = "Standing with the factions you track, for every character.",
    order = 60,
    list = true,
    defaults = { style = "short" },
})

M.STYLE_VALUES = { short = "Standing (Hon)", label = "Standing (Honored)", progress = "Progress (Hon 4.2k/12k)", percent = "Percent (Hon 35%)" }
M.STYLE_ORDER = { "short", "label", "progress", "percent" }

function M:OnLoad()
    TM.db.factionNames = TM.db.factionNames or {}
end

local function FactionData(id)
    local R = C_Reputation
    return R and R.GetFactionDataByID and R.GetFactionDataByID(id)
end

function M:Describe(e)
    local fd = FactionData(e.id)
    if fd and fd.name and fd.name ~= "" then TM.db.factionNames[e.id] = fd.name end
    return e.name or TM.db.factionNames[e.id] or ("Faction " .. e.id)
end

-- Faction IDs on this character's reputation panel (only factions they have met).
local function Panel()
    local out, ids = {}, {}
    local R = C_Reputation
    if not (R and R.GetNumFactions and R.GetFactionDataByIndex) then return out, ids end
    for i = 1, R.GetNumFactions() do
        local fd = R.GetFactionDataByIndex(i)
        if fd and fd.factionID and fd.factionID ~= 0 and (not fd.isHeader or fd.isHeaderWithRep) then
            ids[fd.factionID] = true
            out[#out + 1] = fd
        end
    end
    return out, ids
end

function M:OnEnable()
    self:On("UPDATE_FACTION", function() self:CollectSoon(1) end)
end

function M:Collect()
    local d = self:Data()
    local r = {}
    local _, met = Panel()
    for _, e in ipairs(self:Entries()) do
        local fd = FactionData(e.id)
        if fd and fd.reaction and (met[e.id] or (fd.currentStanding or 0) ~= 0) then
            r[e.id] = {
                reaction = fd.reaction,
                cur = (fd.currentStanding or 0) - (fd.currentReactionThreshold or 0),
                max = (fd.nextReactionThreshold or 0) - (fd.currentReactionThreshold or 0),
            }
            if fd.name then TM.db.factionNames[e.id] = fd.name end
        end
    end
    d.r = r
    self:Changed()
end

local function StandingName(reaction)
    return _G["FACTION_STANDING_LABEL" .. tostring(reaction)] or ("Rank " .. tostring(reaction))
end

local function ReactionColor(reaction)
    local c = FACTION_BAR_COLORS and FACTION_BAR_COLORS[reaction]
    if c then return { c.r, c.g, c.b } end
    return TM.C.text
end

function M:Rows(add)
    local style = self.db.style
    for _, e in ipairs(self:Entries()) do
        local id = e.id
        local name = self:Describe(e)
        add({
            key = id, label = name, group = e.group,
            cell = function(toon)
                local d = self:Peek(toon)
                local v = d and d.r and d.r[id]
                if not v then return nil end
                local label = StandingName(v.reaction)
                local short = label:sub(1, 3)
                local text
                if style == "label" then
                    text = label
                elseif style == "progress" and v.max > 0 then
                    text = ("%s %s/%s"):format(short, TM.Number(v.cur), TM.Number(v.max))
                elseif style == "percent" and v.max > 0 then
                    text = ("%s %d%%"):format(short, math.floor(v.cur / v.max * 100))
                else
                    text = short
                end
                return TM.Paint(text, ReactionColor(v.reaction)), function(tt)
                    tt:AddLine(name, 1, 1, 1)
                    tt:AddDoubleLine(label, v.max > 0 and (TM.Commas(v.cur) .. " / " .. TM.Commas(v.max)) or "",
                        unpack(ReactionColor(v.reaction)))
                end
            end,
        })
    end
end

function M:BuildOptions(W, parent, y, O)
    local R = O.Rows(self.db)
    y = O.Header(W, parent, y, "BOARD")
    y = O.Pair(W, parent, y, R.Dropdown("style", "Cell shows", M.STYLE_VALUES, M.STYLE_ORDER))

    y = O.Header(W, parent, y, "TRACKED FACTIONS")
    y = O.TrackedList(self, W, parent, y, {
        placeholder = "Faction ID",
        parse = function(text)
            local out = {}
            for _, id in ipairs(TM.ParseIDs(text)) do out[#out + 1] = { id = id } end
            return out
        end,
        describe = function(e) return self:Describe(e), nil, "ID " .. e.id end,
        discoverTitle = "ON YOUR REPUTATION PANEL",
        discover = function()
            local out = {}
            for _, fd in ipairs((Panel())) do
                if not self:HasEntry(fd.factionID) then
                    TM.db.factionNames[fd.factionID] = fd.name
                    out[#out + 1] = { entry = { id = fd.factionID }, text = fd.name, sub = StandingName(fd.reaction) }
                end
            end
            return out
        end,
        emptyDiscover = "Nothing new on this character's reputation panel (collapsed headers hide their factions).",
    })
    return y
end
