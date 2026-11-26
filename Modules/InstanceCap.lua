-- Instance cap: counts the instances you entered in the last hour (and day), account-wide, against limits you set,
-- and says when the next slot frees up. Entering the same instance again before it is reset does not count twice.
-- An estimate built from what the client sees: set the limits to what the realm enforces.
local _, TM = ...

local M = TM:NewModule("instancecap", {
    title = "Instance Cap",
    icon = "InstanceCap", -- Media/Icons
    subtitle = "Instances entered this hour and today, against the cap.",
    order = 90,
    defaults = { perHour = 5, perDay = 30, announce = true },
})

local HOUR, DAY = 3600, 86400

function M:OnLoad()
    TM.db.history = TM.db.history or {} -- array of { map, name, at, last, closed }
end

local function Prune()
    local h, now = TM.db.history, time()
    for i = #h, 1, -1 do
        if now - (h[i].at or 0) > DAY then table.remove(h, i) end
    end
end

local function Count(window)
    local n, oldest, now = 0, nil, time()
    for _, e in ipairs(TM.db.history) do
        if now - e.at < window then
            n = n + 1
            if not oldest or e.at < oldest then oldest = e.at end
        end
    end
    return n, oldest and (oldest + window - now)
end

function M:Entered()
    local inInstance, kind = IsInInstance()
    if not inInstance or (kind ~= "party" and kind ~= "raid") then return end
    local name, _, _, _, _, _, _, mapID = GetInstanceInfo()
    if not mapID then return end
    local now = time()
    local h = TM.db.history
    for i = #h, 1, -1 do
        local e = h[i]
        if e.map == mapID and not e.closed and now - e.at < DAY then
            e.last = now
            return
        end
    end
    h[#h + 1] = { map = mapID, name = name, at = now, last = now }
    Prune()
    if self.db.announce and self.db.perHour > 0 then
        local n, frees = Count(HOUR)
        if n >= self.db.perHour - 1 then
            local msg = ("Instance %d of %d this hour."):format(n, self.db.perHour)
            if n >= self.db.perHour and frees then msg = msg .. (" Next slot frees in %s."):format(TM.Duration(frees)) end
            TM.Say(msg)
        end
    end
    self:Changed()
end

-- "X has been reset." closes the instance, so going back in counts as a new one.
local resetPattern
local function ResetName(msg)
    if not resetPattern and INSTANCE_RESET_SUCCESS then
        resetPattern = "^" .. INSTANCE_RESET_SUCCESS:gsub("([%(%)%.%-%+%*%?%[%]%^%$])", "%%%1"):gsub("%%s", "(.+)") .. "$"
    end
    return resetPattern and msg:match(resetPattern)
end

function M:OnEnable()
    self:On("PLAYER_ENTERING_WORLD", function() C_Timer.After(1, function() self:Entered() end) end)
    self:On("CHAT_MSG_SYSTEM", function(_, _, msg)
        -- System chat arrives as a secret string while chat is locked down (combat); a reset never happens then.
        if type(msg) ~= "string" or (issecretvalue and issecretvalue(msg)) then return end
        local name = ResetName(msg)
        if not name then return end
        for _, e in ipairs(TM.db.history) do
            if e.name == name then e.closed = true end
        end
    end)
    Prune()
end

function M:Footer(add)
    local function Line(label, n, limit, frees)
        local text = ("%s %d/%d"):format(label, n, limit)
        if n >= limit then
            text = TM.Paint(text, TM.C.bad)
            if frees then text = text .. (" · next in %s"):format(TM.Duration(frees)) end
        elseif n >= limit - 1 then
            text = TM.Paint(text, TM.C.warn)
        end
        return text
    end
    local parts = {}
    if self.db.perHour > 0 then
        local n, frees = Count(HOUR)
        parts[#parts + 1] = Line("Instances this hour", n, self.db.perHour, frees)
    end
    if self.db.perDay > 0 then
        local n, frees = Count(DAY)
        parts[#parts + 1] = Line("today", n, self.db.perDay, frees)
    end
    if #parts > 0 then add(table.concat(parts, "  ·  ")) end
end

function M:BuildOptions(W, parent, y, O)
    local R = O.Rows(self.db)
    y = O.Header(W, parent, y, "LIMITS")
    y = O.Pair(W, parent, y,
        R.Slider("perHour", "Per hour (0 = off)", 0, 20, 1),
        R.Slider("perDay", "Per day (0 = off)", 0, 60, 1))
    y = O.Pair(W, parent, y, R.Toggle("announce", "Warn in chat near the cap"),
        { type = "button", label = "History", text = "Clear history", onClick = function()
            wipe(TM.db.history)
            TM:RequestRefresh()
            TM.Say("Instance history cleared.")
        end })
    y = O.Note(parent, y, "Counted from what this client sees: instances entered on another PC are not known.")
    return y
end
