-- Tallymark board: one window, a column per character, a section per module, a row per tracked thing.
-- Rows come from each enabled module's Rows(); the board only lays them out, so it never knows what a lockout or a
-- currency is. Built on first show; Refresh() while hidden only marks it stale.
local _, TM = ...
local T = TM.Theme

local Board = {}
TM.board = Board

local HEADER_H, PAD, INDENT = 34, 10, 14
local frame, scroll, content, colHeader, footer, thumb, colGlow, headGlow, emptyText
local titleText, timerText, lockBtn
local measurer
local rowPool, sectionPool, groupPool, colPool, footPool = {}, {}, {}, {}, {}
local layoutCache -- what the last Refresh drew, for hover lookups

local function S() return TM.db.settings.board end

local function Report(err)
    local h = geterrorhandler()
    if h then h(err) end
end

--------------------------------------------------------------------------------
-- Position
--------------------------------------------------------------------------------
local function SavePosition()
    local p, _, rp, x, y = frame:GetPoint(1)
    S().pos = { p, rp, x, y }
end

local function RestorePosition()
    frame:ClearAllPoints()
    local pos = S().pos
    if pos then
        frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    end
end

function Board:ResetPosition()
    S().pos = nil
    if frame then RestorePosition() end
end

--------------------------------------------------------------------------------
-- Pools
--------------------------------------------------------------------------------
local function ShowTip(owner, fn, anchor)
    if not fn then return end
    GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
    local ok = xpcall(fn, Report, GameTooltip)
    if ok and GameTooltip:NumLines() > 0 then GameTooltip:Show() else GameTooltip:Hide() end
end

local function RowHover(row, on)
    row.hl:SetShown(on)
end

local function NewCell(row)
    local c = CreateFrame("Frame", nil, row)
    c.text = T.Font(c, 12)
    c.text:SetPoint("LEFT", 3, 0)
    c.text:SetPoint("RIGHT", -3, 0)
    c.text:SetJustifyH("CENTER")
    c:SetScript("OnEnter", function(self)
        RowHover(row, true)
        ShowTip(self, self.tip)
    end)
    c:SetScript("OnLeave", function()
        RowHover(row, false)
        GameTooltip:Hide()
    end)
    return c
end

local function GetRow(i)
    local row = rowPool[i]
    if row then return row end
    row = CreateFrame("Button", nil, content)
    row.stripe = T.Fill(row, 1, 1, 1, 0.025, "BACKGROUND", 1)
    row.stripe:SetAllPoints()
    row.hl = T.Fill(row, 1, 1, 1, 0.06, "BACKGROUND", 2)
    row.hl:SetAllPoints()
    row.hl:Hide()
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.label = T.Font(row, 12)
    row.label:SetJustifyH("LEFT")
    row.cells = {}
    row:SetScript("OnEnter", function(self)
        RowHover(self, true)
        if self.tip then ShowTip(self.label, self.tip, "ANCHOR_LEFT") end
    end)
    row:SetScript("OnLeave", function(self)
        RowHover(self, false)
        GameTooltip:Hide()
    end)
    rowPool[i] = row
    return row
end

local function GetSection(i)
    local sec = sectionPool[i]
    if sec then return sec end
    sec = CreateFrame("Button", nil, content)
    sec.arrow = T.Glyph(sec, "chevron", 9, "down")
    sec.arrow:SetPoint("LEFT", PAD, 0)
    sec.text = T.Font(sec, 11)
    sec.text:SetPoint("LEFT", sec.arrow, "RIGHT", 6, 0)
    sec.count = T.Font(sec, 10)
    sec.count:SetPoint("LEFT", sec.text, "RIGHT", 6, 0)
    sec.count:SetTextColor(1, 1, 1, 0.3)
    sec.line = T.Line(sec, "BOTTOM", 1, 1, 1, 0.06)
    sec:SetScript("OnClick", function(self)
        local collapsed = TM.db.collapsed
        collapsed[self.moduleKey] = not collapsed[self.moduleKey] or nil
        Board:Refresh()
    end)
    sec:SetScript("OnEnter", function(self) self.text:SetAlpha(1) end)
    sec:SetScript("OnLeave", function(self) self.text:SetAlpha(0.85) end)
    sectionPool[i] = sec
    return sec
end

local function GetGroup(i)
    local g = groupPool[i]
    if g then return g end
    g = CreateFrame("Frame", nil, content)
    g.text = T.Font(g, 10)
    g.text:SetPoint("BOTTOMLEFT", PAD + INDENT, 2)
    g.text:SetTextColor(1, 1, 1, 0.4)
    groupPool[i] = g
    return g
end

local function GetCol(i)
    local col = colPool[i]
    if col then return col end
    col = CreateFrame("Button", nil, colHeader)
    -- First name, surname, level: each on its own line, placed in Refresh.
    col.name = T.Font(col, 13)
    col.name:SetJustifyH("CENTER")
    col.last = T.Font(col, 13)
    col.last:SetJustifyH("CENTER")
    col.sub = T.Font(col, 10)
    col.sub:SetJustifyH("CENTER")
    col.sub:SetTextColor(1, 1, 1, 0.4)
    col:SetScript("OnEnter", function(self) ShowTip(self, self.tip, "ANCHOR_BOTTOM") end)
    col:SetScript("OnLeave", function() GameTooltip:Hide() end)
    colPool[i] = col
    return col
end

local function GetFoot(i)
    local f = footPool[i]
    if f then return f end
    f = T.Font(footer, 11)
    f:SetJustifyH("LEFT")
    f:SetTextColor(1, 1, 1, 0.55)
    footPool[i] = f
    return f
end

local function HideFrom(pool, n)
    for i = n, #pool do pool[i]:Hide() end
end

--------------------------------------------------------------------------------
-- Header
--------------------------------------------------------------------------------
local function UpdateTimers()
    if not timerText then return end
    local parts = {}
    local d, w = TM.NextReset("daily"), TM.NextReset("weekly")
    if d then parts[#parts + 1] = "Daily " .. TM.Paint(TM.Duration(d - time()), TM.C.text) end
    if w then parts[#parts + 1] = "Weekly " .. TM.Paint(TM.Duration(w - time()), TM.C.text) end
    for _, M in ipairs(TM.moduleList) do
        if M:IsEnabled() and M.Header then
            xpcall(M.Header, Report, M, function(text) parts[#parts + 1] = text end)
        end
    end
    timerText:SetText(table.concat(parts, "   "))
end

-- Width the title bar needs: title, timers and the three buttons on the right.
local function HeaderWidth()
    return PAD + 2 + titleText:GetStringWidth() + 14 + timerText:GetStringWidth() + 80
end

-- The pin: a solid accent dot while the board is locked in place, a faint one while it can be dragged.
local function UpdateLockIcon()
    if not lockBtn then return end
    if S().locked then
        local r, g, b = TM.Accent()
        lockBtn.glyph:SetColor(r, g, b, 1)
        lockBtn.alpha = 1
    else
        lockBtn.glyph:SetColor(1, 1, 1, 0.3)
        lockBtn.alpha = 0.3
    end
end

local function UpdateTitle()
    local r, g, b = TM.Accent()
    titleText:SetText(TM.Paint("Tally", r, g, b) .. "mark")
end

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------
local function Build()
    frame = CreateFrame("Frame", "TallymarkBoard", UIParent)
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if not S().locked and not Board.peeking then self:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if not Board.peeking then SavePosition() end
    end)
    frame:Hide()

    frame.bg = T.Fill(frame, T.BG[1], T.BG[2], T.BG[3], 0.94, "BACKGROUND", -8)
    frame.bg:SetAllPoints()
    T.Border(frame, 1, 1, 1, 0.08)

    -- Header: title, reset timers, buttons.
    titleText = T.Font(frame, 16)
    titleText:SetPoint("TOPLEFT", PAD + 2, -10)
    timerText = T.Font(frame, 11)
    timerText:SetPoint("LEFT", titleText, "RIGHT", 14, -1)
    timerText:SetTextColor(1, 1, 1, 0.45)

    local close = T.GlyphButton(frame, "close", 10, "Close", function() Board:Hide() end)
    close:SetPoint("TOPRIGHT", -PAD + 4, -7)
    local opts = T.GlyphButton(frame, "menu", 11, "Options", function()
        Board:Hide()
        TM.OpenOptions()
    end)
    opts:SetPoint("RIGHT", close, "LEFT", -4, 0)
    lockBtn = T.GlyphButton(frame, "dot", 7, function(tt)
        tt:SetText(S().locked and "Locked in place (click to unlock)" or "Click to lock in place", 1, 1, 1)
    end, function()
        S().locked = not S().locked
        UpdateLockIcon()
    end)
    lockBtn:SetPoint("RIGHT", opts, "LEFT", -4, 0)
    lockBtn:HookScript("OnLeave", UpdateLockIcon)

    local headLine = T.Line(frame, "TOP", 1, 1, 1, 0.06)
    headLine:ClearAllPoints()
    headLine:SetPoint("TOPLEFT", 1, -HEADER_H)
    headLine:SetPoint("TOPRIGHT", -1, -HEADER_H)

    -- Character columns, fixed above the scrolling rows.
    colHeader = CreateFrame("Frame", nil, frame)
    colHeader:SetPoint("TOPLEFT", 0, -HEADER_H)
    colHeader:SetPoint("TOPRIGHT", 0, -HEADER_H)
    headGlow = T.Fill(colHeader, 1, 1, 1, 0.04, "BACKGROUND", 0)
    local colLine = T.Line(colHeader, "BOTTOM", 1, 1, 1, 0.06)
    colLine:SetPoint("BOTTOMLEFT", 1, 0)
    colLine:SetPoint("BOTTOMRIGHT", -1, 0)

    scroll = CreateFrame("ScrollFrame", nil, frame)
    scroll:SetPoint("TOPLEFT", colHeader, "BOTTOMLEFT", 0, 0)
    scroll:SetPoint("TOPRIGHT", colHeader, "BOTTOMRIGHT", 0, 0)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    colGlow = T.Fill(content, 1, 1, 1, 0.04, "BACKGROUND", 0)
    emptyText = T.Font(content, 12)
    emptyText:SetPoint("TOPLEFT", PAD + 4, -12)
    emptyText:SetTextColor(1, 1, 1, 0.5)
    emptyText:SetText("Nothing to show yet. Track something in /tally options, or log in another character.")
    emptyText:Hide()

    thumb = T.Fill(frame, 1, 1, 1, 0.18, "OVERLAY")
    thumb:SetWidth(2)
    thumb:Hide()

    local function UpdateThumb()
        local range = scroll:GetVerticalScrollRange()
        if range <= 0 then return thumb:Hide() end
        local h = scroll:GetHeight()
        local th = math.max(h * h / (h + range), 20)
        thumb:SetHeight(th)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", -2, -((h - th) * scroll:GetVerticalScroll() / range))
        thumb:Show()
    end
    Board.UpdateThumb = UpdateThumb
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange()
        local v = math.min(math.max(self:GetVerticalScroll() - delta * S().rowHeight * 3, 0), range)
        self:SetVerticalScroll(v)
        UpdateThumb()
    end)

    footer = CreateFrame("Frame", nil, frame)
    footer:SetPoint("BOTTOMLEFT", 0, 0)
    footer:SetPoint("BOTTOMRIGHT", 0, 0)
    footer.line = T.Line(footer, "TOP", 1, 1, 1, 0.06)

    local elapsed = 0
    frame:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 1 then return end
        elapsed = 0
        UpdateTimers()
    end)
    frame:SetScript("OnShow", function()
        UpdateTimers()
        UpdateTitle()
        if Board.dirty or not layoutCache then Board:Refresh() end
    end)
    Board.timerUpdate = frame:GetScript("OnUpdate")
    frame:SetScript("OnHide", function(self)
        if Board.peeking then
            Board.peeking = false
            RestorePosition()
        end
        self:SetScript("OnUpdate", Board.timerUpdate)
    end)

    measurer = T.Font(frame, 12)
    measurer:Hide()

    UpdateTitle()
    UpdateLockIcon()
    RestorePosition()
    Board:ApplySettings()
end

--------------------------------------------------------------------------------
-- Settings that are not part of the layout
--------------------------------------------------------------------------------
function Board:ApplySettings()
    if not frame then return end
    local s = S()
    frame:SetScale(s.scale)
    frame.bg:SetAlpha(s.alpha)
    if TM.Launcher then TM.Launcher:Paint() end
    local found
    for i, name in ipairs(UISpecialFrames) do
        if name == "TallymarkBoard" then found = i break end
    end
    if s.escapeCloses and not found then
        tinsert(UISpecialFrames, "TallymarkBoard")
    elseif not s.escapeCloses and found then
        table.remove(UISpecialFrames, found)
    end
    -- Fixed header text takes the font and accent too.
    T.SetFont(titleText, 16)
    T.SetFont(timerText, 11)
    UpdateTitle()
    UpdateLockIcon()
    -- Sliders call this on every step of a drag, so the layout pass is coalesced.
    TM.Debounce("boardApply", 0.05, function() self:Refresh() end)
end

--------------------------------------------------------------------------------
-- Refresh: gather rows from the modules, then lay everything out.
--------------------------------------------------------------------------------
local function Gather(toons)
    local s = S()
    local sections = {}
    for _, M in ipairs(TM.moduleList) do
        if M:IsEnabled() and M.Rows then
            local rows = {}
            xpcall(M.Rows, Report, M, function(r) rows[#rows + 1] = r end, toons)
            local kept = {}
            for _, r in ipairs(rows) do
                local cells, any = {}, false
                for i, e in ipairs(toons) do
                    local ok, text, tip = xpcall(r.cell, Report, e.toon, e.guid, e.current)
                    if ok and text ~= nil then
                        any = any or text ~= ""
                        cells[i] = { text = tostring(text), tip = tip }
                    else
                        cells[i] = false
                    end
                end
                r.cells = cells
                if any or r.keep or not s.hideEmptyRows then kept[#kept + 1] = r end
            end
            if #kept > 0 then sections[#sections + 1] = { M = M, rows = kept } end
        end
    end
    local lines = {}
    if s.showFooter then
        for _, M in ipairs(TM.moduleList) do
            if M:IsEnabled() and M.Footer then
                xpcall(M.Footer, Report, M, function(text) lines[#lines + 1] = text end, toons)
            end
        end
    end
    return sections, lines
end

local function LabelWidth(sections, size, iconSize)
    local s = S()
    if s.labelWidth and s.labelWidth > 0 then return s.labelWidth end
    T.SetFont(measurer, size)
    local w = 120
    for _, sec in ipairs(sections) do
        for _, r in ipairs(sec.rows) do
            measurer:SetText(r.label or "")
            local lw = measurer:GetStringWidth() + INDENT + (r.icon and (iconSize + 6) or 0) + 12
            if lw > w then w = lw end
        end
    end
    return math.min(math.ceil(w), 300)
end

local function ToonTip(e)
    return function(tt)
        local t = e.toon
        tt:AddLine(TM.ToonName(t), 1, 1, 1)
        local where = t.realm and t.realm ~= "" and (" · " .. t.realm) or ""
        tt:AddLine(("Level %s %s%s"):format(tostring(t.level or "?"),
            (t.class and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[t.class]) or t.class or "", where), 0.7, 0.7, 0.7)
        if not e.current then tt:AddLine("Last played " .. TM.Ago(t.lastSeen), 0.7, 0.7, 0.7) end
    end
end

function Board:Refresh()
    if not frame or not frame:IsShown() then
        self.dirty = true
        return
    end
    self.dirty = false
    local s = S()
    local size, rowH, colW = s.fontSize, s.rowHeight, s.colWidth
    local iconSize = rowH - 6
    local toons = TM:Toons()
    local sections, lines = Gather(toons)
    local labelW = LabelWidth(sections, size, iconSize)
    UpdateTimers()
    local width = math.ceil(math.max(PAD + labelW + #toons * colW + PAD, 360, HeaderWidth()))
    local colX = function(i) return PAD + labelW + (i - 1) * colW end
    layoutCache = sections

    -- Columns
    local surnames = false
    for _, e in ipairs(toons) do
        if e.toon.surname and e.toon.surname ~= "" then surnames = true break end
    end
    local nameLine = size + 3
    local subY = -4 - nameLine * (surnames and 2 or 1)
    local colH = -subY + (s.showLevel and (size + 3) or 5)
    colHeader:SetHeight(colH)
    local currentIndex
    for i, e in ipairs(toons) do
        local col = GetCol(i)
        col:ClearAllPoints()
        col:SetPoint("TOPLEFT", colX(i), 0)
        col:SetSize(colW, colH)
        T.SetFont(col.name, size + 1)
        T.SetFont(col.last, size + 1)
        T.SetFont(col.sub, size - 2)
        col.name:SetPoint("TOPLEFT", 2, -4)
        col.name:SetPoint("TOPRIGHT", -2, -4)
        col.last:SetPoint("TOPLEFT", 2, -4 - nameLine)
        col.last:SetPoint("TOPRIGHT", -2, -4 - nameLine)
        col.sub:SetPoint("TOPLEFT", 2, subY)
        col.sub:SetPoint("TOPRIGHT", -2, subY)
        col.name:SetText(TM.ToonPaint(e.toon.name or UNKNOWN or "?", e.toon))
        col.last:SetText(TM.ToonPaint(e.toon.surname or "", e.toon))
        col.last:SetShown(surnames)
        col.sub:SetText(s.showLevel and ("Lv " .. tostring(e.toon.level or "?")) or "")
        col.sub:SetShown(s.showLevel)
        col.tip = ToonTip(e)
        col:Show()
        if e.current then currentIndex = i end
    end
    HideFrom(colPool, #toons + 1)

    -- Rows
    local y, ri, si, gi = 0, 0, 0, 0
    for _, sec in ipairs(sections) do
        si = si + 1
        local head = GetSection(si)
        local collapsed = TM.db.collapsed[sec.M.key]
        head.moduleKey = sec.M.key
        head:ClearAllPoints()
        head:SetPoint("TOPLEFT", 0, -y)
        head:SetSize(width, rowH + 4)
        T.SetFont(head.text, size - 1)
        local r, g, b = TM.Accent()
        head.text:SetTextColor(r, g, b, 1)
        head.text:SetAlpha(0.85)
        head.text:SetText(sec.M.title:upper())
        head.count:SetText(collapsed and ("(" .. #sec.rows .. ")") or "")
        head.arrow:SetDir(collapsed and "right" or "down")
        head.arrow:SetColor(r, g, b, 0.8)
        head:Show()
        y = y + rowH + 4
        if not collapsed then
            local lastGroup, stripe = nil, 0
            for _, row in ipairs(sec.rows) do
                if row.group and row.group ~= lastGroup then
                    gi = gi + 1
                    local g = GetGroup(gi)
                    g:ClearAllPoints()
                    g:SetPoint("TOPLEFT", 0, -y)
                    g:SetSize(width, rowH)
                    T.SetFont(g.text, size - 2)
                    g.text:SetText(row.group:upper())
                    g:Show()
                    y = y + rowH
                    stripe = 0
                end
                lastGroup = row.group
                ri = ri + 1
                stripe = stripe + 1
                -- A row marked `wrap` grows to two lines when any of its cells is too wide for one.
                local h, wrap = rowH, false
                if row.wrap then
                    T.SetFont(measurer, size)
                    for i = 1, #toons do
                        local cell = row.cells[i]
                        if cell then
                            measurer:SetText(cell.text)
                            if measurer:GetStringWidth() > colW - 6 then wrap = true break end
                        end
                    end
                    if wrap then h = math.max(rowH, math.ceil(measurer:GetStringHeight() * 2) + 8) end
                end
                local f = GetRow(ri)
                f:ClearAllPoints()
                f:SetPoint("TOPLEFT", 0, -y)
                f:SetSize(width, h)
                f.stripe:SetShown(s.stripes and stripe % 2 == 0)
                f.hl:Hide()
                f.tip = row.tip
                local x = PAD + INDENT
                if row.icon then
                    f.icon:SetTexture(row.icon)
                    f.icon:SetSize(iconSize, iconSize)
                    f.icon:ClearAllPoints()
                    f.icon:SetPoint("LEFT", x, 0)
                    f.icon:Show()
                    x = x + iconSize + 6
                else
                    f.icon:Hide()
                end
                T.SetFont(f.label, size)
                f.label:ClearAllPoints()
                f.label:SetPoint("LEFT", x, 0)
                f.label:SetText(row.label or "")
                f.label:SetWidth(labelW - x + PAD - 4)
                for i = 1, #toons do
                    local c = f.cells[i]
                    if not c then
                        c = NewCell(f)
                        f.cells[i] = c
                    end
                    c:ClearAllPoints()
                    c:SetPoint("TOPLEFT", colX(i), 0)
                    c:SetSize(colW, h)
                    T.SetFont(c.text, size)
                    c.text:SetWordWrap(wrap)
                    c.text:SetMaxLines(wrap and 2 or 1)
                    local cell = row.cells[i]
                    if cell then
                        c.text:SetText(cell.text)
                        c.text:SetAlpha(1)
                        c.tip = cell.tip
                    else
                        c.text:SetText("-")
                        c.text:SetAlpha(0.2)
                        c.tip = nil
                    end
                    c:EnableMouse(c.tip ~= nil)
                    c:Show()
                end
                for i = #toons + 1, #f.cells do f.cells[i]:Hide() end
                f:Show()
                y = y + h
            end
        end
    end
    HideFrom(sectionPool, si + 1)
    HideFrom(groupPool, gi + 1)
    HideFrom(rowPool, ri + 1)
    emptyText:SetShown(si == 0)
    if si == 0 then y = 40 end

    -- The current character's column, behind everything.
    if currentIndex and s.highlightCurrent then
        colGlow:ClearAllPoints()
        colGlow:SetPoint("TOPLEFT", colX(currentIndex), 0)
        colGlow:SetSize(colW, math.max(y, 1))
        colGlow:Show()
        headGlow:ClearAllPoints()
        headGlow:SetPoint("TOPLEFT", colX(currentIndex), 0)
        headGlow:SetSize(colW, colH)
        headGlow:Show()
    else
        colGlow:Hide()
        headGlow:Hide()
    end

    -- Footer
    local footH = 0
    for i, text in ipairs(lines) do
        local fs = GetFoot(i)
        T.SetFont(fs, size - 1)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", PAD + 2, -8 - (i - 1) * (size + 5))
        fs:SetPoint("RIGHT", -PAD, 0)
        fs:SetText(text)
        fs:Show()
        footH = 8 + i * (size + 5) + 4
    end
    for i = #lines + 1, #footPool do footPool[i]:Hide() end
    footer:SetHeight(math.max(footH, 1))
    footer:SetShown(footH > 0)

    -- Size
    local visible = math.min(y, s.maxHeight)
    content:SetSize(width, math.max(y, 1))
    scroll:SetHeight(math.max(visible, 1))
    frame:SetSize(width, HEADER_H + colH + visible + 4 + footH)
    scroll:SetVerticalScroll(math.min(scroll:GetVerticalScroll(), math.max(y - visible, 0)))
    if Board.UpdateThumb then C_Timer.After(0, Board.UpdateThumb) end
end

--------------------------------------------------------------------------------
-- Showing
--------------------------------------------------------------------------------
function Board:IsShown()
    return frame and frame:IsShown() or false
end

function Board:Show()
    if not frame then Build() end
    if self.peeking then
        self.peeking = false
        frame:SetScript("OnUpdate", self.timerUpdate)
        RestorePosition()
    end
    frame:Show()
end

function Board:Hide()
    if frame then frame:Hide() end
end

function Board:Toggle()
    if self:IsShown() and not self.peeking then self:Hide() else self:Show() end
end

-- Shown next to `anchor` while the mouse is over it or the board; gone shortly after it leaves both.
function Board:Peek(anchor)
    if not frame then Build() end
    if frame:IsShown() and not self.peeking then return end
    self.peeking = true
    self.timerUpdate = self.timerUpdate or frame:GetScript("OnUpdate")
    frame:ClearAllPoints()
    local x, y = anchor:GetCenter()
    local sw, sh = UIParent:GetSize()
    local v = (y or 0) > sh / 2 and "TOP" or "BOTTOM"
    local h = (x or 0) > sw / 2 and "RIGHT" or "LEFT"
    local av = v == "TOP" and "BOTTOM" or "TOP"
    frame:SetPoint(v .. h, anchor, av .. h, 0, 0)
    frame:Show()
    local away, tick = 0, 0
    local base = self.timerUpdate
    frame:SetScript("OnUpdate", function(f, dt)
        if base then base(f, dt) end
        tick = tick + dt
        if tick < 0.1 then return end
        if frame:IsMouseOver() or anchor:IsMouseOver() then
            away = 0
        else
            away = away + tick
            if away > 0.35 then
                frame:SetScript("OnUpdate", base)
                self.peeking = false
                frame:Hide()
                RestorePosition()
            end
        end
        tick = 0
    end)
end

TM.OnLogin = function()
    if TM.Launcher then TM.Launcher:Init() end
end
