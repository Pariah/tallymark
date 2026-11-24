-- Cooldowns: long spell and item cooldowns per character (Hearthstone, transmutes, cloth cooldowns).
-- Entries are "spell:<id>" or "item:<id>"; a character gets a cell once they know the spell or carry the item.
local _, TM = ...

local M = TM:NewModule("cooldowns", {
    title = "Cooldowns",
    icon = "Cooldowns", -- Media/Icons
    subtitle = "Spell and item cooldowns, ready or counting down.",
    order = 70,
    list = true,
    defaults = { minDuration = 60, readyText = true },
})

local function Split(id)
    local kind, n = tostring(id):match("^(%a+):(%d+)$")
    return kind, tonumber(n)
end

function M:Describe(e)
    local kind, n = Split(e.id)
    if kind == "spell" then
        local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(n)
        return e.name or name or ("Spell " .. tostring(n)), C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(n)
    elseif kind == "item" then
        local name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(n)
        return e.name or name or ("Item " .. tostring(n)), C_Item.GetItemIconByID and C_Item.GetItemIconByID(n)
    end
    return e.name or tostring(e.id)
end

local function Knows(spellID)
    if IsPlayerSpell and IsPlayerSpell(spellID) then return true end
    if C_SpellBook and C_SpellBook.IsSpellKnown then return C_SpellBook.IsSpellKnown(spellID) end
    return IsSpellKnown and IsSpellKnown(spellID) or false
end

-- Seconds of cooldown left (0 when ready), or nil when the character has no such spell or item.
local function Remaining(kind, n)
    local start, duration
    if kind == "spell" then
        if not Knows(n) then return nil end
        local info = C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(n)
        if info then start, duration = info.startTime, info.duration end
    elseif kind == "item" then
        if (C_Item.GetItemCount(n) or 0) == 0 and not (PlayerHasToy and PlayerHasToy(n)) then return nil end
        local get = (C_Container and C_Container.GetItemCooldown) or (C_Item and C_Item.GetItemCooldown)
        if get then start, duration = get(n) end
    else
        return nil
    end
    if not (TM.Usable(start) and TM.Usable(duration)) then return false end -- unreadable right now
    if start <= 0 or duration <= 0 then return 0 end
    return math.max(start + duration - GetTime(), 0), duration
end

function M:OnEnable()
    for _, ev in ipairs({ "SPELL_UPDATE_COOLDOWN", "BAG_UPDATE_COOLDOWN", "BAG_UPDATE_DELAYED", "SPELLS_CHANGED" }) do
        self:On(ev, function() self:CollectSoon(2) end)
    end
end

function M:Collect()
    if InCombatLockdown() then return self:CollectSoon(5) end
    local d = self:Data()
    d.cd = d.cd or {}
    local now = time()
    local keep = {}
    for _, e in ipairs(self:Entries()) do
        local kind, n = Split(e.id)
        local left, duration = Remaining(kind, n)
        if left == false then
            keep[e.id] = d.cd[e.id] -- keep the last good reading
        elseif left then
            -- Short cooldowns (the global cooldown, a fresh login) are not worth a timer.
            if duration and duration < self.db.minDuration then left = 0 end
            keep[e.id] = { expires = left > 0 and math.floor(now + left) or 0 }
        end
    end
    d.cd = keep
    self:Changed()
end

function M:Rows(add)
    for _, e in ipairs(self:Entries()) do
        local id = e.id
        local name, icon = self:Describe(e)
        local kind, n = Split(id)
        add({
            key = id, label = name, icon = icon, group = e.group,
            tip = function(tt)
                if kind == "spell" and tt.SetSpellByID then tt:SetSpellByID(n)
                elseif kind == "item" then tt:SetItemByID(n)
                else tt:AddLine(name, 1, 1, 1) end
            end,
            cell = function(toon)
                local d = self:Peek(toon)
                local v = d and d.cd and d.cd[id]
                if not v then return nil end
                local left = (v.expires or 0) - time()
                if left <= 0 then return self.db.readyText and TM.Paint("Ready", TM.C.good) or TM.CHECK end
                return TM.Paint(TM.Duration(left), TM.C.warn), function(tt)
                    tt:AddLine(name, 1, 1, 1)
                    tt:AddDoubleLine("Ready", date("%a %H:%M", v.expires), 0.7, 0.7, 0.7, 1, 1, 1)
                end
            end,
        })
    end
end

function M:BuildOptions(W, parent, y, O)
    local R = O.Rows(self.db)
    y = O.Header(W, parent, y, "BOARD")
    y = O.Pair(W, parent, y,
        R.Toggle("readyText", "Write \"Ready\"", { tooltip = "Off: a check mark when the cooldown is up." }),
        R.Slider("minDuration", "Ignore cooldowns under (sec)", 0, 600, 10))

    y = O.Header(W, parent, y, "TRACKED COOLDOWNS")
    y = O.Note(parent, y, "Shift-click a spell or item, or type spell:ID / item:ID. A bare number is taken as a spell.")
    y = O.TrackedList(self, W, parent, y, {
        placeholder = "spell:17187, item:6948 or a link",
        parse = function(text)
            local out, seen = {}, {}
            local function Add(kind, n)
                local id = kind .. ":" .. n
                if not seen[id] then
                    seen[id] = true
                    out[#out + 1] = { id = id }
                end
            end
            for kind, n in (text or ""):gmatch("|H(%a+):(%d+)") do
                if kind == "spell" or kind == "item" then Add(kind, n) end
            end
            local rest = (text or ""):gsub("|H.-|h.-|h", " ")
            for kind, n in rest:gmatch("(%a+):(%d+)") do
                kind = kind:lower()
                if kind == "spell" or kind == "item" then Add(kind, n) end
            end
            rest = rest:gsub("%a+:%d+", " ")
            for n in rest:gmatch("%d+") do Add("spell", n) end
            return out
        end,
        describe = function(e)
            local name, icon = self:Describe(e)
            return name, icon, tostring(e.id)
        end,
        tooltip = function(e, tt)
            local kind, n = Split(e.id)
            if kind == "spell" and tt.SetSpellByID then tt:SetSpellByID(n) elseif kind == "item" then tt:SetItemByID(n) end
        end,
    })
    return y
end
