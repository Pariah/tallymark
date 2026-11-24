-- Tallymark core: namespace, saved data, the module registry and event dispatch.
--
-- A module is one file with one call:
--   local M = TM:NewModule("key", {
--       title    = "Currencies",   -- board section header and options page name
--       order    = 30,             -- board order (low first)
--       defaults = { ... },        -- its settings, TallymarkDB.settings.modules.key (`enabled` is added)
--       list     = true,           -- it has a tracked list, seeded from TM.Tracked.key (see Core/Lists.lua)
--   })
-- and any of these methods:
--   M:OnLoad()              saved data is in place (M.db = settings)
--   M:OnEnable()            at login, while enabled; register events with M:On(event, handler)
--   M:Collect()             write this character's data into M:Data() (and call M:Changed())
--   M:Rows(add, toons)      board rows: add{ key, label, icon, group, tip, cell = function(toon) -> text, tipFn }
--   M:Footer(add)           board footer lines: add(text)
--   M:Header(add)           short texts beside the reset timers in the board's title bar: add(text). Runs every second
--                           while the board is open, so keep it cheap.
--   M:Prune(data, now)      drop anything in one character's M:Data() that has expired
--   M:BuildOptions(W, parent, y, O) -> y   its options page (Options/Pages.lua)
local ADDON, TM = ...
_G.Tallymark = TM

TM.name = ADDON
TM.version = C_AddOns.GetAddOnMetadata(ADDON, "Version") or "?"

local DB_VERSION = 1

TM.defaults = {
    board = {
        accent = "amber", font = "manrope",
        scale = 1, alpha = 0.94, fontSize = 12, rowHeight = 20, colWidth = 92, labelWidth = 0, maxHeight = 640,
        locked = false, escapeCloses = true, hideEmptyRows = true, showFooter = true, showLevel = true,
        classColors = true, compactNumbers = true, stripes = true, highlightCurrent = true,
    },
    characters = { sort = "custom", currentFirst = true, minLevel = 1, maxColumns = 10, thisRealmOnly = false },
    launcher = { minimap = true, angle = 205, hoverPeek = true },
    modules = {},
}

TM.modules, TM.moduleList = {}, {}

local function DeepCopy(v)
    if type(v) ~= "table" then return v end
    local c = {}
    for k, x in pairs(v) do c[k] = DeepCopy(x) end
    return c
end
TM.DeepCopy = DeepCopy

-- Fills missing keys of t from defaults, recursing into tables both sides have.
local function Merge(t, defaults)
    for k, v in pairs(defaults) do
        if t[k] == nil then
            t[k] = DeepCopy(v)
        elseif type(v) == "table" and type(t[k]) == "table" then
            Merge(t[k], v)
        end
    end
    return t
end
TM.Merge = Merge

function TM.Say(text)
    DEFAULT_CHAT_FRAME:AddMessage(("|cff%sTallymark|r %s"):format(TM.Hex(TM.Accent()), tostring(text)))
end

local function Report(err)
    local handler = geterrorhandler()
    if handler then handler(err) end
end

--------------------------------------------------------------------------------
-- Modules
--------------------------------------------------------------------------------
local Module = {}
Module.__index = Module
TM.Module = Module

function TM:NewModule(key, spec)
    assert(type(key) == "string" and not self.modules[key], "Tallymark: bad or duplicate module key " .. tostring(key))
    local M = setmetatable(spec or {}, Module)
    M.key = key
    M.title = M.title or key
    M.order = M.order or 100
    self.modules[key] = M
    self.moduleList[#self.moduleList + 1] = M
    table.sort(self.moduleList, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.key < b.key
    end)
    return M
end

function TM:GetModule(key)
    return self.modules[key]
end

function Module:IsEnabled()
    return self.db and self.db.enabled and true or false
end

-- This module's slot in one character's data (the current character by default).
function Module:Data(toon)
    toon = toon or TM.thisToon
    if not toon then return nil end
    toon.data = toon.data or {}
    local d = toon.data[self.key]
    if not d then
        d = {}
        toon.data[self.key] = d
    end
    return d
end

-- Read-only peek: nil when the character has nothing for this module.
function Module:Peek(toon)
    return toon and toon.data and toon.data[self.key]
end

function Module:Changed()
    TM:RequestRefresh()
end

-- Runs handler(self, event, ...) on the event while the module is enabled. handler: function or method name.
function Module:On(event, handler)
    TM:Register(event, self, handler)
end

-- Collect, at most once per `delay` seconds however often it is asked for.
function Module:CollectSoon(delay)
    TM.Debounce("collect:" .. self.key, delay or 0.5, function()
        if self:IsEnabled() and self.Collect then self:Collect() end
    end)
end

function Module:SetEnabled(on)
    self.db.enabled = on and true or false
    if on and TM.loggedIn then
        if not self.enabledOnce and self.OnEnable then
            self.enabledOnce = true
            self:OnEnable()
        end
        if self.Collect then self:Collect() end
    end
    TM:RequestRefresh()
end

--------------------------------------------------------------------------------
-- Events: one frame, handlers per event in registration order, each guarded.
--------------------------------------------------------------------------------
local frame = CreateFrame("Frame")
local handlers = {}

function TM:Register(event, owner, handler)
    local list = handlers[event]
    if not list then
        list = {}
        handlers[event] = list
        frame:RegisterEvent(event)
    end
    list[#list + 1] = { owner = owner, fn = handler }
end

local function Dispatch(event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do
        local h = list[i]
        local owner, fn = h.owner, h.fn
        if owner == TM or not owner.IsEnabled or owner:IsEnabled() then
            if type(fn) == "string" then fn = owner[fn] end
            if fn then xpcall(fn, Report, owner, event, ...) end
        end
    end
end
frame:SetScript("OnEvent", function(_, event, ...) Dispatch(event, ...) end)

-- Coalesces calls under one key: fn runs once, `delay` seconds after the first call.
do
    local pending = {}
    function TM.Debounce(key, delay, fn)
        if pending[key] then return end
        pending[key] = true
        C_Timer.After(delay, function()
            pending[key] = nil
            xpcall(fn, Report)
        end)
    end
end

--------------------------------------------------------------------------------
-- Board refresh requests. UI/Board.lua sets TM.board; until then nothing draws.
--------------------------------------------------------------------------------
function TM:RequestRefresh()
    if not (self.board and self.board.Refresh) then return end
    TM.Debounce("board", 0.15, function() self.board:Refresh() end)
end

--------------------------------------------------------------------------------
-- Characters
--------------------------------------------------------------------------------
local function NextOrder(toons)
    local n = 0
    for _, t in pairs(toons) do
        if type(t.order) == "number" and t.order > n then n = t.order end
    end
    return n + 1
end

function TM:UpdatePlayer()
    local t = self.thisToon
    if not t then return end
    local name, second = UnitFullName("player")
    t.name = name or t.name or UNKNOWN
    if TM.HasSurnames() then
        -- Forever: names are unique per region and the second return is the surname, not a realm.
        t.surname = (second and second ~= "" and second) or t.surname
        t.realm = GetRealmName() or t.realm or ""
    else
        t.realm = (second and second ~= "" and second) or GetRealmName() or t.realm or ""
    end
    local _, class = UnitClass("player")
    t.class = class or t.class
    t.faction = UnitFactionGroup("player") or t.faction
    t.level = UnitLevel("player") or t.level
    t.lastSeen = time()
end

function TM:InitPlayer()
    local guid = UnitGUID("player")
    if not guid then return end
    local toons = self.db.toons
    -- Saves from before surname support stored the surname as the realm. Move it over once.
    if TM.HasSurnames() and not self.db.surnames then
        local realm = GetRealmName() or ""
        for _, old in pairs(toons) do
            if not old.surname and old.realm and old.realm ~= "" then
                old.surname, old.realm = old.realm, realm
            end
        end
        self.db.surnames = true
    end
    local t = toons[guid]
    if not t then
        t = { data = {}, order = NextOrder(toons) }
        toons[guid] = t
    end
    self.thisGUID, self.thisToon = guid, t
    self:UpdatePlayer()
end

-- Characters for the board, filtered and sorted by the Characters settings. Each is { guid, toon }.
local function ByName(a, b) return TM.ToonName(a.toon, true) < TM.ToonName(b.toon, true) end
local SORTS = {
    custom = function(a, b) return (a.toon.order or 0) < (b.toon.order or 0) end,
    name = ByName,
    level = function(a, b)
        if (a.toon.level or 0) ~= (b.toon.level or 0) then return (a.toon.level or 0) > (b.toon.level or 0) end
        return ByName(a, b)
    end,
    class = function(a, b)
        if (a.toon.class or "") ~= (b.toon.class or "") then return (a.toon.class or "") < (b.toon.class or "") end
        return ByName(a, b)
    end,
    lastSeen = function(a, b) return (a.toon.lastSeen or 0) > (b.toon.lastSeen or 0) end,
}
TM.SORT_VALUES = { custom = "Custom order", name = "Name", level = "Level", class = "Class", lastSeen = "Last played" }
TM.SORT_ORDER = { "custom", "name", "level", "class", "lastSeen" }

function TM:Toons(includeHidden)
    local cs = self.db.settings.characters
    local list = {}
    local myRealm = self.thisToon and self.thisToon.realm
    for guid, t in pairs(self.db.toons) do
        local show = includeHidden or guid == self.thisGUID or (
            not t.hidden
            and (t.level or 0) >= (cs.minLevel or 1)
            and (not cs.thisRealmOnly or t.realm == myRealm))
        if show then list[#list + 1] = { guid = guid, toon = t, current = guid == self.thisGUID } end
    end
    table.sort(list, SORTS[cs.sort] or SORTS.custom)
    if cs.currentFirst then
        for i, e in ipairs(list) do
            if e.current then
                table.remove(list, i)
                table.insert(list, 1, e)
                break
            end
        end
    end
    if not includeHidden and cs.maxColumns and #list > cs.maxColumns then
        for i = #list, cs.maxColumns + 1, -1 do list[i] = nil end
    end
    return list
end

-- Custom order: swaps a character with its neighbour (delta -1 up, +1 down).
function TM:MoveToon(guid, delta)
    local all = {}
    for g, t in pairs(self.db.toons) do all[#all + 1] = { guid = g, toon = t } end
    table.sort(all, SORTS.custom)
    for i, e in ipairs(all) do e.toon.order = i end
    for i, e in ipairs(all) do
        if e.guid == guid then
            local other = all[i + delta]
            if other then e.toon.order, other.toon.order = other.toon.order, e.toon.order end
            break
        end
    end
    self:RequestRefresh()
end

function TM:DeleteToon(guid)
    if guid == self.thisGUID then return false end
    self.db.toons[guid] = nil
    self:RequestRefresh()
    return true
end

function TM:PruneAll()
    local now = time()
    for _, t in pairs(self.db.toons) do
        for _, M in ipairs(self.moduleList) do
            local d = M:Peek(t)
            if d and M.Prune then xpcall(M.Prune, Report, M, d, now) end
        end
    end
end

-- Re-reads everything for the current character.
function TM:CollectAll()
    self:UpdatePlayer()
    for _, M in ipairs(self.moduleList) do
        if M:IsEnabled() and M.Collect then xpcall(M.Collect, Report, M) end
    end
    self:RequestRefresh()
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------
local function InitDB()
    local db = TallymarkDB
    if type(db) ~= "table" then db = {} end
    TallymarkDB = db
    db.version = db.version or DB_VERSION
    db.toons = db.toons or {}
    db.lists = db.lists or {}
    db.collapsed = db.collapsed or {}
    db.settings = Merge(db.settings or {}, TM.defaults)
    TM.db = db
    for _, M in ipairs(TM.moduleList) do
        local s = db.settings.modules[M.key] or {}
        db.settings.modules[M.key] = s
        if s.enabled == nil then s.enabled = M.enabledByDefault ~= false end
        Merge(s, M.defaults or {})
        M.db = s
    end
    for _, M in ipairs(TM.moduleList) do
        if M.OnLoad then xpcall(M.OnLoad, Report, M) end
    end
end

TM:Register("ADDON_LOADED", TM, function(_, _, name)
    if name == ADDON then InitDB() end
end)

TM:Register("PLAYER_LOGIN", TM, function()
    TM:InitPlayer()
    TM:PruneAll()
    TM.loggedIn = true
    for _, M in ipairs(TM.moduleList) do
        if M:IsEnabled() and M.OnEnable then
            M.enabledOnce = true
            xpcall(M.OnEnable, Report, M)
        end
    end
    if TM.OnLogin then TM.OnLogin() end
    -- Some data (currencies, saved instances) is only right a moment after login.
    C_Timer.After(3, function() TM:CollectAll() end)
end)

TM:Register("PLAYER_LEVEL_UP", TM, function(_, _, level)
    if TM.thisToon then TM.thisToon.level = level end
    TM:RequestRefresh()
end)

TM:Register("PLAYER_LOGOUT", TM, function()
    TM.loggingOut = true
    TM:UpdatePlayer()
end)

-- Hourly sweep: expired lockouts and quests drop off while you play through a reset.
C_Timer.NewTicker(60, function()
    if not TM.loggedIn then return end
    TM:PruneAll()
    TM:RequestRefresh()
end)

--------------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------------
SLASH_TALLYMARK1 = "/tally"
SLASH_TALLYMARK2 = "/tallymark"
SlashCmdList.TALLYMARK = function(msg)
    msg = strtrim((msg or ""):lower())
    if msg == "options" or msg == "config" or msg == "opt" then
        return TM.OpenOptions()
    elseif msg == "reset" then
        if TM.board then TM.board:ResetPosition() end
        return TM.Say("Board position reset.")
    elseif msg == "refresh" then
        TM:CollectAll()
        return TM.Say("Refreshed.")
    elseif msg ~= "" then
        return TM.Say("/tally toggles the board, /tally options opens settings, /tally reset recentres it.")
    end
    if TM.board then TM.board:Toggle() end
end

-- Options/Window.lua sets TM.optionsWindow. pageKey: "display", "characters", "launcher" or a module key.
function TM.OpenOptions(pageKey)
    if TM.optionsWindow then TM.optionsWindow:Open(pageKey) end
end

-- Keybinding (Bindings.xml)
BINDING_HEADER_TALLYMARK = "Tallymark"
BINDING_NAME_TALLYMARK_TOGGLE = "Toggle the board"
function Tallymark_Toggle()
    if TM.board then TM.board:Toggle() end
end
