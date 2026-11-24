-- Items: tracked item IDs counted in bags and bank per character (keys, tokens, farmed reagents).
-- The bank count is what the client last saw, so a character's bank total is right once they have opened it.
local _, TM = ...

local M = TM:NewModule("items", {
    title = "Items",
    icon = "Items", -- Media/Icons
    subtitle = "Counts of the items you track, for every character.",
    order = 50,
    list = true,
    defaults = { includeBank = true, hideZero = true, totalInLabel = false },
})

function M:Describe(e)
    local name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(e.id)
    return name or e.name or ("Item " .. e.id), C_Item.GetItemIconByID and C_Item.GetItemIconByID(e.id)
end

function M:OnEnable()
    for _, ev in ipairs({ "BAG_UPDATE_DELAYED", "BANKFRAME_OPENED", "PLAYERBANKSLOTS_CHANGED" }) do
        self:On(ev, function() self:CollectSoon(1) end)
    end
end

function M:Collect()
    local d = self:Data()
    local i = {}
    for _, e in ipairs(self:Entries()) do
        local bags = C_Item.GetItemCount(e.id, false) or 0
        local all = C_Item.GetItemCount(e.id, true) or bags
        i[e.id] = { bags = bags, bank = math.max(all - bags, 0) }
        TM.OnItemLoaded(e.id, function() self:Changed() end)
    end
    d.i = i
    self:Changed()
end

function M:Count(toon, id)
    local d = self:Peek(toon)
    local v = d and d.i and d.i[id]
    if not v then return nil end
    return v.bags + (self.db.includeBank and v.bank or 0), v
end

function M:Rows(add, toons)
    for _, e in ipairs(self:Entries()) do
        local id = e.id
        local name, icon = self:Describe(e)
        local label = name
        if self.db.totalInLabel then
            local total = 0
            for _, t in ipairs(toons) do total = total + (self:Count(t.toon, id) or 0) end
            label = name .. TM.Paint(" (" .. TM.Number(total) .. ")", TM.C.dim)
        end
        add({
            key = id, label = label, icon = icon, group = e.group,
            tip = function(tt)
                tt:SetItemByID(id)
                local total = 0
                for _, t in ipairs(TM:Toons(true)) do total = total + (self:Count(t.toon, id) or 0) end
                tt:AddLine(" ")
                tt:AddDoubleLine("All characters", TM.Commas(total), 0.7, 0.7, 0.7, 1, 1, 1)
            end,
            cell = function(toon)
                local n, v = self:Count(toon, id)
                if not n or (n == 0 and self.db.hideZero) then return nil end
                return TM.Number(n), function(tt)
                    tt:AddLine(name, 1, 1, 1)
                    tt:AddDoubleLine("Bags", TM.Commas(v.bags), 0.7, 0.7, 0.7, 1, 1, 1)
                    tt:AddDoubleLine("Bank", TM.Commas(v.bank), 0.7, 0.7, 0.7, 1, 1, 1)
                end
            end,
        })
    end
end

function M:BuildOptions(W, parent, y, O)
    local R = O.Rows(self.db)
    y = O.Header(W, parent, y, "BOARD")
    y = O.Pair(W, parent, y,
        R.Toggle("includeBank", "Count the bank"),
        R.Toggle("hideZero", "Leave zero counts empty"))
    y = O.Pair(W, parent, y, R.Toggle("totalInLabel", "Total after the item name"))

    y = O.Header(W, parent, y, "TRACKED ITEMS")
    y = O.Note(parent, y, "Item IDs or shift-clicked items, separated by commas.")
    y = O.TrackedList(self, W, parent, y, {
        placeholder = "Item ID or link",
        parse = function(text)
            local out = {}
            for _, id in ipairs(TM.ParseIDs(text, "item")) do out[#out + 1] = { id = id } end
            return out
        end,
        describe = function(e)
            local name, icon = self:Describe(e)
            return name, icon, "ID " .. e.id
        end,
        tooltip = function(e, tt) tt:SetItemByID(e.id) end,
    })
    return y
end
