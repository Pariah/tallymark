-- Mail: what sits in each character's mailbox and when it expires.
-- The inbox can only be read at a mailbox, so this is what the character saw on their last visit; expiry times are
-- stored as absolute times and keep counting down after that.
local _, TM = ...

local M = TM:NewModule("mail", {
    title = "Mail",
    icon = "Mail", -- Media/Icons
    subtitle = "Mail per character and when the next one expires.",
    order = 80,
    defaults = { showCount = true, showExpiry = true, warnDays = 3, urgentDays = 1 },
})

function M:OnEnable()
    self:On("MAIL_INBOX_UPDATE", function() self:CollectSoon(0.5) end)
    self:On("MAIL_SHOW", function() self.atMailbox = true end)
    self:On("MAIL_CLOSED", function() self.atMailbox = false end)
end

function M:Collect()
    -- The inbox reads as empty away from a mailbox: keep the last visit's picture.
    if not (self.atMailbox and GetInboxNumItems and GetInboxHeaderInfo) then return end
    local shown, total = GetInboxNumItems()
    if not TM.Usable(shown) then return end
    local now = time()
    local list = {}
    for i = 1, shown do
        local _, _, sender, subject, money, cod, daysLeft, itemCount, _, wasReturned, _, canReply = GetInboxHeaderInfo(i)
        if TM.Usable(daysLeft) then
            local hasStuff = (TM.Usable(money) and money > 0) or (TM.Usable(itemCount) and itemCount > 0)
            list[#list + 1] = {
                expires = math.floor(now + daysLeft * 86400),
                -- What expiry does: player mail with something attached goes back once; the rest is deleted.
                returns = hasStuff and canReply and not wasReturned or nil,
                stuff = hasStuff or nil,
                money = TM.Usable(money) and money > 0 and money or nil,
                cod = TM.Usable(cod) and cod > 0 or nil,
                from = sender, subject = subject,
            }
        end
    end
    table.sort(list, function(a, b) return a.expires < b.expires end)
    local d = self:Data()
    d.list = list
    d.total = TM.Usable(total) and total or shown
    d.at = now
    self:Changed()
end

function M:Prune(d, now)
    if not d.list then return end
    local keep = {}
    for _, m in ipairs(d.list) do
        if m.expires > now then keep[#keep + 1] = m end
    end
    if #keep < #d.list and d.total then d.total = math.max(d.total - (#d.list - #keep), #keep) end
    d.list = keep
end

local function Color(self, left)
    if left < self.db.urgentDays * 86400 then return TM.C.bad end
    if left < self.db.warnDays * 86400 then return TM.C.warn end
    return TM.C.dim
end

function M:Rows(add)
    add({
        key = "mail", label = "Mailbox",
        cell = function(toon)
            local d = self:Peek(toon)
            if not (d and d.list) then return nil end
            local now = time()
            local n = d.total or #d.list
            if n == 0 then return TM.Paint("0", TM.C.dim) end
            local parts = {}
            if self.db.showCount then parts[#parts + 1] = tostring(n) end
            local first = d.list[1]
            if self.db.showExpiry and first and first.expires > now then
                local left = first.expires - now
                parts[#parts + 1] = TM.Paint(TM.Duration(left), Color(self, left))
            end
            if #parts == 0 then parts[1] = TM.CHECK end
            return table.concat(parts, TM.Paint(" · ", TM.C.dim)), function(tt)
                tt:AddDoubleLine("Mail", tostring(n), 1, 1, 1, 1, 1, 1)
                if n > #d.list then tt:AddLine(("Only %d of %d were readable; the rest show up as mail is taken."):format(#d.list, n), 0.7, 0.7, 0.7, true) end
                local shown = 0
                for _, m in ipairs(d.list) do
                    if m.expires > now then
                        shown = shown + 1
                        if shown > 12 then
                            tt:AddLine(("...and %d more"):format(#d.list - 12), 0.7, 0.7, 0.7)
                            break
                        end
                        local left = m.expires - now
                        local c = Color(self, left)
                        local what = m.returns and "returns" or (m.stuff and "deleted with contents" or "deleted")
                        tt:AddDoubleLine((m.subject and m.subject ~= "" and m.subject or "(no subject)") .. TM.Paint("  " .. tostring(m.from or ""), TM.C.dim),
                            TM.Duration(left) .. " " .. what, 1, 1, 1, c[1], c[2], c[3])
                    end
                end
                tt:AddLine("Checked " .. TM.Ago(d.at), 0.5, 0.5, 0.5)
            end
        end,
    })
end

function M:BuildOptions(W, parent, y, O)
    local R = O.Rows(self.db)
    y = O.Note(parent, y, "The mailbox is only readable at a mailbox: each character shows what they saw on their last visit.")
    y = O.Header(W, parent, y, "CELL")
    y = O.Pair(W, parent, y, R.Toggle("showCount", "Number of mails"), R.Toggle("showExpiry", "Time until the next one expires"))
    y = O.Header(W, parent, y, "WARNINGS")
    y = O.Pair(W, parent, y, R.Slider("warnDays", "Amber under (days)", 1, 15, 1), R.Slider("urgentDays", "Red under (days)", 1, 7, 1))
    return y
end
