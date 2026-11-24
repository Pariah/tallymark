-- Tallymark option pages.
--   Board     Display, Characters, Launcher
--   Tracking  a page per module that has BuildOptions, in board order
-- Loaded last so every module exists.
local _, TM = ...
local O = TM.Options
local T = TM.Theme
local Win = TM.optionsWindow

local function Apply() TM.board:ApplySettings() end

-- Puts a settings table back to its defaults in place (built pages hold the table).
local function ResetTable(tbl, defaults)
    wipe(tbl)
    TM.Merge(tbl, defaults)
end

--------------------------------------------------------------------------------
-- Board
--------------------------------------------------------------------------------
Win:AddPage({
    key = "display", title = "Display", group = "Board", icon = "Display",
    subtitle = "How the board looks, where it sits and what it shows.",
    build = function(parent, y)
        local s = TM.db.settings.board
        local R = O.Rows(s, Apply)
        y = O.Header(nil, parent, y, "LOOK")
        y = O.Pair(nil, parent, y, R.Dropdown("accent", "Accent colour", T.ACCENT_VALUES, T.ACCENT_ORDER, {
                refreshPage = true,
                swatch = function(key) local a = T.ACCENTS[key] or T.ACCENTS.amber; return a[2], a[3], a[4], 1 end,
            }),
            R.Dropdown("font", "Font", T.FONT_VALUES, T.FONT_ORDER, { refreshPage = true }))
        y = O.Pair(nil, parent, y, R.Slider("scale", "Scale", 0.6, 1.6, 0.05), R.Slider("alpha", "Background opacity", 0.3, 1, 0.02))

        y = O.Header(nil, parent, y, "WINDOW")
        y = O.Pair(nil, parent, y, R.Toggle("locked", "Lock position"), R.Toggle("escapeCloses", "Close with Escape"))
        y = O.Pair(nil, parent, y, R.Slider("maxHeight", "Height before scrolling", 240, 1200, 20),
            { type = "button", label = "Preview", text = "Show the board", onClick = function() TM.board:Show() end })

        y = O.Header(nil, parent, y, "LAYOUT")
        y = O.Pair(nil, parent, y, R.Slider("fontSize", "Font size", 9, 16, 1), R.Slider("rowHeight", "Row height", 16, 30, 1))
        y = O.Pair(nil, parent, y, R.Slider("colWidth", "Character column width", 60, 180, 2),
            R.Slider("labelWidth", "Label column (0 = fit)", 0, 320, 10))

        y = O.Header(nil, parent, y, "CONTENT")
        y = O.Pair(nil, parent, y,
            R.Toggle("hideEmptyRows", "Hide rows nobody has", { tooltip = "A row with nothing for any shown character is left out. Pinned instances and tracked quests always show." }),
            R.Toggle("showFooter", "Footer lines", { tooltip = "Gold total, next lockout reset, instance cap." }))
        y = O.Pair(nil, parent, y, R.Toggle("stripes", "Alternate row shading"), R.Toggle("highlightCurrent", "Highlight this character"))
        y = O.Pair(nil, parent, y, R.Toggle("classColors", "Class-coloured names"), R.Toggle("showLevel", "Level under names"))
        y = O.Pair(nil, parent, y, R.Toggle("compactNumbers", "Compact numbers (12.3k)"),
            { type = "button", label = "Position", text = "Recentre the board", onClick = function() TM.board:ResetPosition() end })
        return y
    end,
    reset = function()
        local pos = TM.db.settings.board.pos
        ResetTable(TM.db.settings.board, TM.defaults.board)
        TM.db.settings.board.pos = pos
        Apply()
    end,
})

Win:AddPage({
    key = "characters", title = "Characters", group = "Board", icon = "Characters",
    subtitle = "Who gets a column, in what order, and who to forget.",
    build = function(parent, y)
        local cs = TM.db.settings.characters
        local R = O.Rows(cs, Apply)
        y = O.Header(nil, parent, y, "ON THE BOARD")
        y = O.Pair(nil, parent, y, R.Dropdown("sort", "Order", TM.SORT_VALUES, TM.SORT_ORDER, { refreshPage = true }),
            R.Toggle("currentFirst", "This character first"))
        y = O.Pair(nil, parent, y, R.Slider("minLevel", "Minimum level", 1, 80, 1), R.Slider("maxColumns", "Most characters shown", 1, 24, 1))
        y = O.Pair(nil, parent, y, R.Toggle("thisRealmOnly", "Only this realm"))

        y = O.Header(nil, parent, y, "CHARACTERS")
        y = O.Note(parent, y, cs.sort == "custom"
            and "Arrows set the custom order. Hide keeps a character off the board; the x forgets them and their data."
            or "Hide keeps a character off the board; the x forgets them and their data. Pick Custom order to rearrange.")
        local items = {}
        for _, e in ipairs(TM:Toons(true)) do
            local t, guid = e.toon, e.guid
            local actions = {}
            if cs.sort == "custom" then
                actions[#actions + 1] = { glyph = "chevron", dir = "up", tip = "Move left", onClick = function() TM:MoveToon(guid, -1); O.Rebuild() end }
                actions[#actions + 1] = { glyph = "chevron", dir = "down", tip = "Move right", onClick = function() TM:MoveToon(guid, 1); O.Rebuild() end }
            end
            if not e.current then
                actions[#actions + 1] = {
                    text = t.hidden and "Show" or "Hide",
                    onClick = function() t.hidden = not t.hidden or nil; TM:RequestRefresh(); O.Rebuild() end,
                }
                actions[#actions + 1] = {
                    glyph = "close", tip = "Forget this character (deletes their saved data)",
                    onClick = function() TM:DeleteToon(guid); O.Rebuild() end,
                }
            end
            local where = t.realm and t.realm ~= "" and (" · " .. t.realm) or ""
            items[#items + 1] = {
                text = TM.ToonName(t) .. (t.hidden and TM.Paint("  hidden", TM.C.dim) or ""),
                sub = ("Lv %s%s · %s"):format(tostring(t.level or "?"), where, e.current and "playing now" or TM.Ago(t.lastSeen)),
                actions = actions,
            }
        end
        return O.List(parent, y, items, "No characters yet.")
    end,
    reset = function()
        ResetTable(TM.db.settings.characters, TM.defaults.characters)
        Apply()
    end,
})

Win:AddPage({
    key = "launcher", title = "Launcher", group = "Board", icon = "Launcher",
    subtitle = "Ways to open the board: minimap button, data brokers, slash commands.",
    build = function(parent, y)
        local R = O.Rows(TM.db.settings.launcher, function() TM.Launcher:Apply() end)
        y = O.Header(nil, parent, y, "OPENING THE BOARD")
        y = O.Pair(nil, parent, y, R.Toggle("minimap", "Minimap button", { tooltip = "Drag it around the minimap edge." }),
            R.Toggle("hoverPeek", "Peek on hover", { tooltip = "Hovering the minimap button or a data broker shows the board until the mouse leaves." }))
        y = O.Note(parent, y, "/tally toggles the board, /tally options opens this window, /tally reset recentres the board. "
            .. "Key Bindings > AddOns > Tallymark has a toggle key, and any LibDataBroker display shows a Tallymark launcher.")
        return y
    end,
    reset = function()
        ResetTable(TM.db.settings.launcher, TM.defaults.launcher)
        TM.Launcher:Apply()
    end,
})

--------------------------------------------------------------------------------
-- Tracking: one page per module
--------------------------------------------------------------------------------
for _, M in ipairs(TM.moduleList) do
    if M.BuildOptions then
        Win:AddPage({
            key = M.key, title = M.title, group = "Tracking", icon = M.icon, subtitle = M.subtitle,
            resetNote = M.list and "Reset keeps your tracked list." or nil,
            isOff = function() return not M:IsEnabled() end,
            build = function(parent, y)
                y = O.Master(parent, y, M)
                return M:BuildOptions(nil, parent, y, O)
            end,
            reset = function()
                -- Settings only: the tracked list is kept.
                local enabled = M.db.enabled
                ResetTable(M.db, M.defaults or {})
                M.db.enabled = enabled
                if M:IsEnabled() and M.Collect then M:Collect() end
                TM:RequestRefresh()
            end,
        })
    end
end
