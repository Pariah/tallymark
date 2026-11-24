-- Currencies: tracked currency IDs, amount per character, with caps and weekly earnings when the currency has them.
local _, TM = ...

local M = TM:NewModule("currencies", {
    title = "Currencies",
    icon = "Currencies", -- Media/Icons
    subtitle = "Currency totals for every character.",
    order = 40,
    list = true,
    defaults = { showCap = false, showWeekly = false },
})

function M:OnLoad()
    TM.db.currencyInfo = TM.db.currencyInfo or {} -- id -> { name, icon }: names known on any character
end

local function Info(id)
    local ci = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(id)
    if ci and ci.name and ci.name ~= "" then
        TM.db.currencyInfo[id] = { name = ci.name, icon = ci.iconFileID }
    end
    return ci
end

function M:Describe(e)
    local known = TM.db.currencyInfo[e.id]
    return e.name or (known and known.name) or ("Currency " .. e.id), known and known.icon
end

function M:OnEnable()
    self:On("CURRENCY_DISPLAY_UPDATE", function() self:CollectSoon(0.5) end)
end

function M:Collect()
    if TM.loggingOut then return end -- amounts read during logout are unreliable
    local d = self:Data()
    local c = {}
    for _, e in ipairs(self:Entries()) do
        local ci = Info(e.id)
        if ci and (ci.discovered or (ci.quantity or 0) > 0) then
            c[e.id] = {
                n = ci.quantity or 0,
                max = (ci.maxQuantity or 0) > 0 and ci.maxQuantity or nil,
                week = (ci.quantityEarnedThisWeek or 0) > 0 and ci.quantityEarnedThisWeek or nil,
                weekMax = (ci.maxWeeklyQuantity or 0) > 0 and ci.maxWeeklyQuantity or nil,
                weekEnds = (ci.maxWeeklyQuantity or 0) > 0 and TM.NextReset("weekly") or nil,
            }
        end
    end
    d.c = c
    self:Changed()
end

function M:Prune(d, now)
    if not d.c then return end
    for _, v in pairs(d.c) do
        if v.weekEnds and v.weekEnds <= now then v.week, v.weekEnds = nil, nil end
    end
end

function M:Rows(add)
    for _, e in ipairs(self:Entries()) do
        local id = e.id
        local name, icon = self:Describe(e)
        add({
            key = id, label = name, icon = icon, group = e.group,
            tip = function(tt)
                if tt.SetCurrencyByID then tt:SetCurrencyByID(id) else tt:AddLine(name, 1, 1, 1) end
            end,
            cell = function(toon)
                local d = self:Peek(toon)
                local v = d and d.c and d.c[id]
                if not v then return nil end
                local text = TM.Number(v.n)
                if self.db.showCap and v.max then text = text .. TM.Paint("/" .. TM.Number(v.max), TM.C.dim) end
                if v.max and v.n >= v.max then text = TM.Paint(text, TM.C.warn) end
                if self.db.showWeekly and v.weekMax then
                    text = text .. " " .. TM.Paint(("(%s/%s)"):format(TM.Number(v.week or 0), TM.Number(v.weekMax)), TM.C.dim)
                end
                return text, function(tt)
                    tt:AddLine(name, 1, 1, 1)
                    tt:AddDoubleLine("Amount", TM.Commas(v.n) .. (v.max and (" / " .. TM.Commas(v.max)) or ""), 0.7, 0.7, 0.7, 1, 1, 1)
                    if v.weekMax then
                        tt:AddDoubleLine("This week", TM.Commas(v.week or 0) .. " / " .. TM.Commas(v.weekMax), 0.7, 0.7, 0.7, 1, 1, 1)
                    end
                end
            end,
        })
    end
end

-- The currency tab, minus headers: { id, name, icon }.
local function CurrencyTab()
    local out = {}
    local CI = C_CurrencyInfo
    if not (CI and CI.GetCurrencyListSize and CI.GetCurrencyListInfo) then return out end
    for i = 1, CI.GetCurrencyListSize() do
        local info = CI.GetCurrencyListInfo(i)
        if info and not info.isHeader then
            local id = info.currencyID
            if not id and CI.GetCurrencyListLink and CI.GetCurrencyIDFromLink then
                local link = CI.GetCurrencyListLink(i)
                id = link and CI.GetCurrencyIDFromLink(link)
            end
            if id then out[#out + 1] = { id = id, name = info.name, icon = info.iconFileID } end
        end
    end
    return out
end

function M:BuildOptions(W, parent, y, O)
    local R = O.Rows(self.db)
    y = O.Header(W, parent, y, "BOARD")
    y = O.Pair(W, parent, y,
        R.Toggle("showCap", "Show the cap", { tooltip = "12/50 instead of 12, for currencies with a maximum." }),
        R.Toggle("showWeekly", "Show weekly earnings", { tooltip = "(30/100) after the amount, for currencies with a weekly limit." }))

    y = O.Header(W, parent, y, "TRACKED CURRENCIES")
    y = O.TrackedList(self, W, parent, y, {
        placeholder = "Currency ID or link",
        parse = function(text)
            local out = {}
            for _, id in ipairs(TM.ParseIDs(text, "currency")) do
                Info(id)
                out[#out + 1] = { id = id }
            end
            return out
        end,
        describe = function(e)
            local name, icon = self:Describe(e)
            return name, icon, "ID " .. e.id
        end,
        tooltip = function(e, tt) if tt.SetCurrencyByID then tt:SetCurrencyByID(e.id) end end,
        discoverTitle = "IN YOUR CURRENCY TAB",
        discover = function()
            local out = {}
            for _, c in ipairs(CurrencyTab()) do
                if not self:HasEntry(c.id) then
                    TM.db.currencyInfo[c.id] = { name = c.name, icon = c.icon }
                    out[#out + 1] = { entry = { id = c.id }, text = c.name, icon = c.icon, sub = "ID " .. c.id }
                end
            end
            return out
        end,
        emptyDiscover = "Your currency tab is empty on this character.",
    })
    return y
end
