-- Professions: skill levels per character on three lines: first profession, second profession, and the secondary
-- skills in shorthand (Cooking / First Aid / Fishing, plus Lockpicking for rogues).
-- Skills are read by skill line ID (C_SkillInfo.GetSkillLineInfoByID), so a collapsed header in the skill window
-- hides nothing.
local _, TM = ...

local M = TM:NewModule("professions", {
    title = "Professions",
    icon = "Professions", -- Media/Icons
    subtitle = "Both professions and the secondary skills, with skill and cap.",
    order = 65,
    defaults = { rows = { prof1 = true, prof2 = true, secondary = true }, showCap = false },
})

-- Skill line IDs (vanilla's, which Forever keeps).
local PRIMARY = {
    171, -- Alchemy
    164, -- Blacksmithing
    333, -- Enchanting
    202, -- Engineering
    182, -- Herbalism
    165, -- Leatherworking
    186, -- Mining
    393, -- Skinning
    197, -- Tailoring
    755, -- Jewelcrafting
    773, -- Inscription
}
local SECONDARY = {
    { id = 185, short = "Cook" },
    { id = 129, short = "Aid" },
    { id = 356, short = "Fish" },
    { id = 633, short = "Lock" }, -- rogues only: shown when the character has it
}
M.SECONDARY = SECONDARY

local function Read(id)
    local get = C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID
    local info = get and get(id)
    if not (info and info.name and TM.Usable(info.rank) and info.rank > 0) then return nil end
    return { id = id, name = info.name, rank = info.rank, max = TM.Usable(info.maxRank) and info.maxRank or nil }
end

function M:OnEnable()
    self:On("SKILL_LINES_CHANGED", function() self:CollectSoon(1) end)
end

function M:Collect()
    if not (C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID) then return end
    local d = self:Data()
    local primary = {}
    for _, id in ipairs(PRIMARY) do
        local s = Read(id)
        if s then primary[#primary + 1] = s end
    end
    -- Highest skill first, so the main profession sits on the first line.
    table.sort(primary, function(a, b)
        if a.rank ~= b.rank then return a.rank > b.rank end
        return a.name < b.name
    end)
    d.primary = primary
    local secondary = {}
    for _, s in ipairs(SECONDARY) do secondary[s.id] = Read(s.id) or false end
    d.secondary = secondary
    self:Changed()
end

local function Skill(s, showCap)
    if showCap and s.max then return ("%d/%d"):format(s.rank, s.max) end
    return tostring(s.rank)
end

local function SkillTip(list)
    return function(tt)
        for _, s in ipairs(list) do
            local capped = s.max and s.rank >= s.max
            tt:AddDoubleLine(s.name, s.max and ("%d / %d"):format(s.rank, s.max) or tostring(s.rank),
                1, 1, 1, capped and 0.3 or 1, capped and 0.85 or 1, capped and 0.45 or 1)
        end
    end
end

local function PrimaryRow(self, n, key)
    return {
        key = key, label = "Profession " .. n, wrap = true,
        cell = function(toon)
            local d = self:Peek(toon)
            if not (d and d.primary) then return nil end
            local s = d.primary[n]
            if not s then return TM.Paint("-", TM.C.dim) end
            return s.name .. " " .. TM.Paint(Skill(s, self.db.showCap), TM.C.text), SkillTip({ s })
        end,
    }
end

function M:Rows(add)
    local r = self.db.rows
    if r.prof1 then add(PrimaryRow(self, 1, "prof1")) end
    if r.prof2 then add(PrimaryRow(self, 2, "prof2")) end
    if r.secondary then
        add({
            key = "secondary", label = "Cook / Aid / Fish / Lock",
            tip = function(tt)
                tt:AddLine("Secondary skills", 1, 1, 1)
                tt:AddLine("Cooking / First Aid / Fishing, then Lockpicking for rogues. A dash: not learned.", 0.7, 0.7, 0.7, true)
            end,
            cell = function(toon)
                local d = self:Peek(toon)
                if not (d and d.secondary) then return nil end
                local parts, known = {}, {}
                for _, s in ipairs(SECONDARY) do
                    local v = d.secondary[s.id]
                    if v then
                        parts[#parts + 1] = Skill(v, self.db.showCap)
                        known[#known + 1] = v
                    elseif s.id ~= 633 then
                        parts[#parts + 1] = TM.Paint("-", TM.C.dim)
                    end
                end
                return table.concat(parts, TM.Paint("/", TM.C.dim)), #known > 0 and SkillTip(known) or nil
            end,
        })
    end
end

function M:BuildOptions(W, parent, y, O)
    local R = O.Rows(self.db.rows)
    local G = O.Rows(self.db)
    y = O.Header(W, parent, y, "ROWS")
    y = O.Pair(W, parent, y, R.Toggle("prof1", "Profession 1", { tooltip = "The higher-skilled of the two." }), R.Toggle("prof2", "Profession 2"))
    y = O.Pair(W, parent, y, R.Toggle("secondary", "Secondary skills", { tooltip = "Cooking / First Aid / Fishing on one line, Lockpicking added for rogues." }))
    y = O.Header(W, parent, y, "CELLS")
    y = O.Pair(W, parent, y, G.Toggle("showCap", "Show the skill cap (225/300)", { tooltip = "Off: just the skill. The tooltip always has both." }))
    return y
end
