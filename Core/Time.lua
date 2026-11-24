-- Tallymark reset clock: when the next daily and weekly resets land, as absolute times (time()).
-- Last known values are saved so an expiry can still be worked out before the client answers at login.
local _, TM = ...

local DAY, WEEK = 86400, 7 * 86400

local function Live(kind)
    local s
    if kind == "daily" then
        if C_DateAndTime and C_DateAndTime.GetSecondsUntilDailyReset then s = C_DateAndTime.GetSecondsUntilDailyReset() end
        if not (TM.Usable(s) and s > 0) and GetQuestResetTime then s = GetQuestResetTime() end
        if TM.Usable(s) and s > 0 and s <= DAY + 60 then return time() + s end
    else
        if C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset then s = C_DateAndTime.GetSecondsUntilWeeklyReset() end
        if TM.Usable(s) and s > 0 and s <= WEEK + 60 then return time() + s end
    end
end

-- The next reset of a kind ("daily" | "weekly"); nil for anything else (a one-time quest never resets).
function TM.NextReset(kind)
    if kind ~= "daily" and kind ~= "weekly" then return nil end
    local resets = TM.db and TM.db.resets
    if not resets then
        resets = {}
        if TM.db then TM.db.resets = resets end
    end
    local t = Live(kind)
    if t then
        resets[kind] = t
        return t
    end
    t = resets[kind]
    if not t then return nil end
    local period = kind == "daily" and DAY or WEEK
    local now = time()
    while t <= now do t = t + period end
    return t
end

function TM.Expired(expires, now)
    return type(expires) == "number" and expires <= (now or time())
end
