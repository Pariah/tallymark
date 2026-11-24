-- Darkmoon Faire: when it opens, when it closes and where, with one chat reminder per Faire.
-- Account-wide, nothing per character.
--
-- Schedule (Forever, worked out from the dates seen Nov 2026 - Jul 2027): it opens on the first Monday on or after
-- the 3rd of each month (the Monday after the first Saturday) at 04:00 US Eastern time, and runs seven days.
-- It alternates between Elwynn Forest and Mulgore, Elwynn in November 2026.
-- Everything is worked out in UTC with the US daylight-saving rule, so the player's own clock and time zone never
-- matter.
local _, TM = ...

local M = TM:NewModule("darkmoon", {
    title = "Darkmoon Faire",
    icon = "Darkmoon", -- Media/Icons
    subtitle = "When the Faire opens and closes, and where it is, with one reminder per Faire.",
    order = 95,
    defaults = { header = true, remind = true, remindDays = 3 },
})

local OPEN_HOUR_ET = 4
local LENGTH = 7 * 86400
local ANCHOR = { year = 2026, month = 11 } -- Elwynn Forest that month
local LOCATIONS = { "Elwynn Forest", "Mulgore" }

-- Days since 1970-01-01 for a calendar date (proleptic Gregorian, no time zones involved).
local function DaysFromCivil(y, m, d)
    if m <= 2 then y = y - 1 end
    local era = math.floor(y / 400)
    local yoe = y - era * 400
    local mp = (m + 9) % 12
    local doy = math.floor((153 * mp + 2) / 5) + d - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    return era * 146097 + doe - 719468
end

local function CivilFromDays(z)
    z = z + 719468
    local era = math.floor(z / 146097)
    local doe = z - era * 146097
    local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
    local y = yoe + era * 400
    local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
    local mp = math.floor((5 * doy + 2) / 153)
    local d = doy - math.floor((153 * mp + 2) / 5) + 1
    local m = mp < 10 and mp + 3 or mp - 9
    if m <= 2 then y = y + 1 end
    return y, m, d
end

local function Weekday(days) return (days + 4) % 7 end -- 0 = Sunday (1970-01-01 was a Thursday)

-- The n-th Sunday of a month, as a day of the month.
local function NthSunday(y, m, n)
    local first = DaysFromCivil(y, m, 1)
    return 1 + (7 - Weekday(first)) % 7 + (n - 1) * 7
end

-- Eastern daylight time on this date (US rule: second Sunday of March to first Sunday of November). The Faire
-- changes hands on a Monday, never on a switch-over Sunday, so the date alone decides it.
local function EasternDST(y, m, d)
    if m < 3 or m > 11 then return false end
    if m > 3 and m < 11 then return true end
    if m == 3 then return d >= NthSunday(y, 3, 2) end
    return d < NthSunday(y, 11, 1)
end

-- 04:00 Eastern on a date, as a UTC timestamp.
local function EasternMorning(days)
    local y, m, d = CivilFromDays(days)
    local offset = EasternDST(y, m, d) and 4 or 5
    return days * 86400 + (OPEN_HOUR_ET + offset) * 3600
end

-- The Faire of one month: { start, stop, location }.
function M.Faire(y, m)
    local third = DaysFromCivil(y, m, 3)
    local startDay = third + (1 - Weekday(third)) % 7
    local months = (y * 12 + m) - (ANCHOR.year * 12 + ANCHOR.month)
    return {
        start = EasternMorning(startDay),
        stop = EasternMorning(startDay + 7),
        location = LOCATIONS[months % 2 + 1],
        year = y, month = m,
    }
end

-- The Faire that is on now, or the next one.
function M.Current(now)
    now = now or time()
    local y, m = CivilFromDays(math.floor(now / 86400))
    local f = M.Faire(y, m)
    if now >= f.stop then
        if m == 12 then y, m = y + 1, 1 else m = m + 1 end
        f = M.Faire(y, m)
    end
    f.open = now >= f.start
    return f
end

local function When(t) return date("%a %d %b, %H:%M", t) end

function M:Header(add)
    if not self.db.header then return end
    local f = M.Current()
    local now = time()
    local short = f.location == "Elwynn Forest" and "Elwynn" or f.location
    if f.open then
        add("Faire " .. TM.Paint(short, TM.C.good) .. " " .. TM.Paint(TM.Duration(f.stop - now) .. " left", TM.C.text))
    else
        add("Faire " .. short .. " " .. TM.Paint(TM.Duration(f.start - now), TM.C.text))
    end
end

-- One chat line per Faire: the first time Tallymark sees it open, or within remindDays of opening.
function M:CheckReminder()
    if not self.db.remind then return end
    local f = M.Current()
    local now = time()
    local due = f.open or (f.start - now) <= self.db.remindDays * 86400
    if not due or TM.db.darkmoonReminded == f.start then return end
    TM.db.darkmoonReminded = f.start
    if f.open then
        TM.Say(("The Darkmoon Faire is open in %s until %s (%s left)."):format(f.location, When(f.stop), TM.Duration(f.stop - now)))
    else
        TM.Say(("The Darkmoon Faire opens in %s on %s (in %s)."):format(f.location, When(f.start), TM.Duration(f.start - now)))
    end
end

function M:OnEnable()
    C_Timer.After(8, function() if self:IsEnabled() then self:CheckReminder() end end)
    -- Played straight through the reminder window or the opening: catch it within ten minutes.
    C_Timer.NewTicker(600, function() if self:IsEnabled() then self:CheckReminder() end end)
end

function M:BuildOptions(W, parent, y, O)
    local R = O.Rows(self.db)
    local f = M.Current()
    y = O.Note(parent, y, (f.open and "Open now in %s, until %s." or "Next: %s, %s to %s."):format(
        f.location, f.open and When(f.stop) or When(f.start), When(f.stop)))
    y = O.Header(W, parent, y, "TITLE BAR")
    y = O.Pair(W, parent, y, R.Toggle("header", "Faire countdown", { tooltip = "Where the Faire is and how long until it opens or closes, beside the reset timers." }))
    y = O.Header(W, parent, y, "REMINDER")
    y = O.Pair(W, parent, y,
        R.Toggle("remind", "Remind me in chat", { tooltip = "Once per Faire, never again until the next one." }),
        R.Slider("remindDays", "Days ahead (0 = once it opens)", 0, 7, 1))
    return y
end
