-- Tallymark helpers: colours, number/money/time formatting and ID parsing shared by every module.
local _, TM = ...

local floor, format = math.floor, string.format

TM.C = {
    good = { 0.30, 0.85, 0.45 },
    warn = { 1.00, 0.78, 0.25 },
    bad = { 1.00, 0.38, 0.38 },
    dim = { 1, 1, 1, 0.38 },
    text = { 1, 1, 1, 0.92 },
}

TM.CHECK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t"
TM.CROSS = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:12:12|t"
TM.WAIT = "|TInterface\\RaidFrame\\ReadyCheck-Waiting:13:13|t"

function TM.Hex(r, g, b)
    return format("%02x%02x%02x", floor((r or 1) * 255 + 0.5), floor((g or 1) * 255 + 0.5), floor((b or 1) * 255 + 0.5))
end

function TM.Paint(text, c, g, b)
    if type(c) == "table" then c, g, b = c[1], c[2], c[3] end
    return "|cff" .. TM.Hex(c, g, b) .. tostring(text) .. "|r"
end

-- The accent colour picked in Board > Display (amber until the saved settings are loaded).
function TM.Accent()
    local accents = TM.Theme and TM.Theme.ACCENTS
    local key = TM.db and TM.db.settings.board.accent
    local a = accents and (accents[key] or accents.amber)
    if a then return a[2], a[3], a[4] end
    return 0.93, 0.64, 0.28
end

function TM.ClassColor(class)
    local c = class and (C_ClassColor and C_ClassColor.GetClassColor(class) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]))
    if c then return c.r, c.g, c.b end
    return 0.85, 0.85, 0.85
end

-- Forever gives every character a first name and a surname (UnitName's second return).
function TM.HasSurnames()
    return RegionalUniqueNamesEnabled ~= nil and RegionalUniqueNamesEnabled() == true
end

local NAME_SEP = Constants and Constants.CharacterNameSeparatorConsts
    and Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR
if type(NAME_SEP) ~= "string" or NAME_SEP == "" then NAME_SEP = " " end

-- Class-coloured when the board's class colours are on.
function TM.ToonPaint(text, toon)
    if not TM.db.settings.board.classColors then return text end
    return TM.Paint(text, TM.ClassColor(toon and toon.class))
end

-- "First Surname" (or just the name where there are no surnames).
function TM.ToonName(toon, plain)
    local name = toon and toon.name or UNKNOWN or "?"
    if toon and toon.surname and toon.surname ~= "" then name = name .. NAME_SEP .. toon.surname end
    if plain then return name end
    return TM.ToonPaint(name, toon)
end

local function Commas(n)
    local s = tostring(floor(n))
    local sign, digits = s:match("^(-?)(%d+)$")
    if not digits then return s end
    digits = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return sign .. digits
end
TM.Commas = Commas

-- 12345 -> "12.3k" when compact numbers are on, "12,345" otherwise.
function TM.Number(n)
    if type(n) ~= "number" then return "" end
    if TM.db.settings.board.compactNumbers then
        local a = math.abs(n)
        if a >= 1e6 then return (format("%.1fm", n / 1e6):gsub("%.0m", "m")) end
        if a >= 1e4 then return (format("%.1fk", n / 1e3):gsub("%.0k", "k")) end
    end
    return Commas(n)
end

-- Copper -> "1,234g" (cells) or the coin-texture string (tooltips).
function TM.Gold(copper, full)
    if type(copper) ~= "number" then return "" end
    if full then
        if C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then return C_CurrencyInfo.GetCoinTextureString(copper) end
        if GetMoneyString then return GetMoneyString(copper, true) end
    end
    local g = floor(copper / 10000)
    if g >= 1 then return TM.Number(g) .. "|cffffd100g|r" end
    return floor(copper / 100) % 100 .. "|cffc0c0c0s|r"
end

-- Seconds -> "2d 4h", "4h 12m", "12m", "<1m".
function TM.Duration(sec)
    if type(sec) ~= "number" then return "" end
    if sec < 60 then return "<1m" end
    local d, h, m = floor(sec / 86400), floor(sec % 86400 / 3600), floor(sec % 3600 / 60)
    if d > 0 then return h > 0 and format("%dd %dh", d, h) or format("%dd", d) end
    if h > 0 then return m > 0 and format("%dh %dm", h, m) or format("%dh", h) end
    return format("%dm", m)
end

function TM.Ago(t)
    if type(t) ~= "number" then return "never" end
    local s = time() - t
    if s < 120 then return "just now" end
    return TM.Duration(s) .. " ago"
end

-- Every ID in free text: numbers, or links of the given kind (item, currency, quest, spell). Returns an array.
function TM.ParseIDs(text, kind)
    local ids, seen = {}, {}
    if type(text) ~= "string" then return ids end
    local function Add(id)
        id = tonumber(id)
        if id and id > 0 and not seen[id] then
            seen[id] = true
            ids[#ids + 1] = id
        end
    end
    local stripped = text
    for linkKind, id in text:gmatch("|H(%a+):(%d+)") do
        if not kind or linkKind == kind then Add(id) end
    end
    stripped = stripped:gsub("|H.-|h.-|h", " ")
    for id in stripped:gmatch("%d+") do Add(id) end
    return ids
end

-- Values the client may hand back as secrets (in combat on modern clients) are unusable.
function TM.Usable(v)
    return type(v) == "number" and not (issecretvalue and issecretvalue(v))
end

-- Item data loads lazily; fn runs once the item is cached (now, if it already is).
function TM.OnItemLoaded(itemID, fn)
    if C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID) then return fn() end
    if Item and Item.CreateFromItemID then
        local item = Item:CreateFromItemID(itemID)
        if not item:IsItemEmpty() then item:ContinueOnItemLoad(fn) end
    end
end
