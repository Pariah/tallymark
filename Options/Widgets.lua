-- Tallymark option widgets, Ledger style: numbered sections, rows grouped into rounded cards, bone switches,
-- neutral sliders with value boxes, bordered drop menus. Amber only marks focus and the current choice.
-- A page is built top-down: every helper takes the running y offset (negative) and returns the next one.
--   O.Header(_, parent, y, "TEXT")            numbered section heading (01, 02 ... per page)
--   O.Pair(_, parent, y, left, right)         a row of one or two controls; back-to-back rows share one card. cfg.type:
--       toggle | slider (min, max, step) | dropdown (values, order, swatch) | button (onClick, label) | input (placeholder) | label
--       all: text, tooltip; value types: getValue(), setValue(v); refreshPage = true rebuilds the page after a change.
--       A trailing "(...)" in text shows as a dim suffix: "Label column (0 = fit)".
--   O.Master(parent, y, M)                    a module's on/off card
--   O.Note(parent, y, text)                   quiet help text
--   O.AddBar(parent, y, placeholder, onSubmit, tooltip, buttonText)   input box with a button
--   O.List(parent, y, items, emptyText)       a card of rows { text, icon, sub, tooltip(tt), actions = { {glyph|text, dir, tip, onClick} } }
--   O.TrackedList(M, _, parent, y, spec)      a module's add bar, tracked entries and discoverable extras
-- O.BeginPage() restarts section numbering; the window calls it before each build.
-- The unused second argument keeps the module pages' BuildOptions(W, parent, y, O) signature.
local _, TM = ...
local T = TM.Theme
local C = T.C

local O = {}
TM.Options = O

local PAD_L, PAD_R = 32, 34 -- page side margins
local ROW_H, LIST_H = 48, 50
local CTRL_W = 176          -- dropdowns, and the default control width
local SLIDER_W = 160        -- rail + value box; narrower so long labels fit beside it
local GAP = 12              -- between blocks that are not a heading and what follows it

function O.Width(parent) return parent:GetWidth() - PAD_L - PAD_R end

-- Rebuilds the open page on the next frame (never from inside the control that asked).
function O.Rebuild()
    C_Timer.After(0, function() if TM.optionsWindow then TM.optionsWindow:Rebuild() end end)
end

local function Accent(a)
    local r, g, b = TM.Accent()
    return { r, g, b, a or 1 }
end

local function Tip(owner, text)
    if not text then return end
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    GameTooltip:SetText(text, 1, 1, 1, 1, true)
    GameTooltip:Show()
end

local function Changed(cfg)
    if cfg.refreshPage then O.Rebuild() end
end

--------------------------------------------------------------------------------
-- Page flow: section numbers and which card the next row joins
--------------------------------------------------------------------------------
local flow = {}
function O.BeginPage() flow.section, flow.group, flow.last = 0, nil, nil end
O.BeginPage()

-- Starts a new block: no space under a heading or at the top, GAP otherwise.
local function Open(y, kind)
    local gap = (flow.last == nil or flow.last == "header") and 0 or GAP
    flow.last, flow.group = kind, nil
    return y - gap
end

local function HLine(frame, color, top)
    local t = frame:CreateTexture(nil, "ARTWORK")
    t:SetColorTexture(T.RGBA(color))
    t:SetHeight(T.Px(frame))
    t:SetPoint(top and "TOPLEFT" or "BOTTOMLEFT", 1, 0)
    t:SetPoint(top and "TOPRIGHT" or "BOTTOMRIGHT", -1, 0)
    return t
end

--------------------------------------------------------------------------------
-- Headings and notes
--------------------------------------------------------------------------------
function O.Header(_, parent, y, text)
    flow.group = nil
    flow.section = flow.section + 1
    y = y - 22
    local num = T.Text(parent, "mono", 11, C.dim)
    num:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD_L, y)
    num:SetText(("%02d"):format(flow.section))
    local fs = T.Text(parent, "caps", 11, C.quiet)
    fs:SetPoint("LEFT", num, "RIGHT", 10, 0)
    fs:SetText((text or ""):upper())
    local rule = parent:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(T.RGBA(C.line))
    rule:SetHeight(T.Px(parent))
    rule:SetPoint("LEFT", fs, "RIGHT", 8, 0)
    rule:SetPoint("RIGHT", parent, "RIGHT", -PAD_R, 0)
    flow.last = "header"
    return y - 25
end

function O.Note(parent, y, text, opt)
    y = Open(y, "note")
    local fs = T.Text(parent, "medium", 12.5, C.quiet)
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD_L, y)
    fs:SetWidth(O.Width(parent))
    fs:SetWordWrap(true)
    fs:SetSpacing(3)
    fs:SetText(text or "")
    return y - math.max(opt and opt.height or 0, math.ceil(fs:GetStringHeight()) + 2)
end

--------------------------------------------------------------------------------
-- Small parts shared by several controls
--------------------------------------------------------------------------------
-- A pill switch. sw:SetOn(bool) paints it.
local function Switch(parent)
    local sw = CreateFrame("Frame", nil, parent)
    sw:SetSize(34, 18)
    sw.track = T.Round(sw, 9, C.toggleOff, "ARTWORK")
    sw.knob = sw:CreateTexture(nil, "OVERLAY")
    sw.knob:SetTexture(T.CIRCLE, nil, nil, "TRILINEAR")
    sw.knob:SetSize(12, 12)
    function sw:SetOn(on)
        self.knob:ClearAllPoints()
        self.knob:SetPoint("LEFT", self, "LEFT", on and 19 or 3, 0)
        self.track:SetColor(T.RGBA(on and C.bone or C.toggleOff))
        self.knob:SetVertexColor(T.RGBA(on and C.window or C.dim))
    end
    return sw
end

-- Row label: main text, an optional dim "(suffix)", and an info mark when the row has a tooltip.
-- It shrinks (and truncates) only if it would reach the control.
local function Label(half, cfg, controlW)
    local text = cfg.text or ""
    local main, suffix = text:match("^(.-)%s*%(([^()]*)%)%s*$")
    main = main or text
    local label = T.Text(half, "semibold", 13, C.label)
    label:SetPoint("LEFT", half, "LEFT", 18, 0)
    label:SetText(main)
    local extra, last = 0, label
    if suffix and suffix ~= "" then
        local s = T.Text(half, "medium", 11, C.dim)
        s:SetPoint("LEFT", label, "RIGHT", 6, 0)
        s:SetText(suffix)
        extra, last = extra + 6 + s:GetStringWidth(), s
    end
    if cfg.tooltip then
        local i = T.Icon(half, "Info", 14, C.disabled)
        i:SetPoint("LEFT", last, "RIGHT", 6, 0)
        extra = extra + 20
    end
    -- Re-run when the control beside it changes width (dropdowns size to their longest option).
    function label:Fit(cw)
        local room = half:GetWidth() - 18 - 18 - cw - 16 - extra
        local natural = self.GetUnboundedStringWidth and self:GetUnboundedStringWidth() or self:GetStringWidth()
        if natural > room then
            self:SetWidth(math.max(room, 40))
            self.squeezed = true
        elseif self.squeezed then
            self:SetWidth(math.ceil(natural) + 2)
            self.squeezed = nil
        end
    end
    label:Fit(controlW)
    return label
end

-- An editable box: rounded inset field, optional leading icon, placeholder, accent border while focused.
-- fill / border: colour tokens (default: the inset field with a standard hairline).
local linkBoxes = setmetatable({}, { __mode = "k" })
local function Field(box, placeholder, icon, onEnter, fill, border)
    box:SetAutoFocus(false)
    box:SetMaxLetters(2000)
    box:SetFont(T.UI.medium, 12.5, "")
    box:SetTextColor(T.RGBA(C.text))
    box:SetShadowOffset(0, 0)
    border = border or C.border
    local frame = T.Box(box, 6, fill or C.inset, border)
    local x = 12
    if icon then
        local i = T.Icon(box, icon, 14, C.dim)
        i:SetPoint("LEFT", 12, 0)
        x = 34
    end
    box:SetTextInsets(x, 10, 0, 0)
    local ph = T.Text(box, "medium", 12.5, C.dim)
    ph:SetPoint("LEFT", x, 0)
    ph:SetText(placeholder or "")
    linkBoxes[box] = true
    box:SetScript("OnTextChanged", function(self) ph:SetShown((self:GetText() or "") == "") end)
    box:SetScript("OnEditFocusGained", function() frame:SetBorder(Accent(0.8)) end)
    box:SetScript("OnEditFocusLost", function() frame:SetBorder(border) end)
    box:SetScript("OnEnterPressed", function() onEnter() end)
    box:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)
    return frame
end
O.Field = Field

-- Shift-clicked links go into whichever of our input boxes has focus.
local function InsertLink(link)
    if type(link) ~= "string" then return end
    local box = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
    if not (box and linkBoxes[box] and box:IsVisible()) then return end
    local text = box:GetText() or ""
    if text:match("%S") and not text:match(",%s*$") then box:Insert(", ") end
    box:Insert(link)
end
if ChatFrameUtil and ChatFrameUtil.InsertLink then
    hooksecurefunc(ChatFrameUtil, "InsertLink", InsertLink)
elseif ChatEdit_InsertLink then
    hooksecurefunc("ChatEdit_InsertLink", InsertLink)
end

--------------------------------------------------------------------------------
-- Buttons
--------------------------------------------------------------------------------
-- style: "default" (filled, hairline), "ghost" (text only, wash on hover),
--        "strong" (bright border, wider, accent border and icon on hover).
-- icon: a Media/Icons name shown before the text.
function O.Button(parent, text, width, onClick, tip, style, icon)
    style = style or "default"
    local ghost, strong = style == "ghost", style == "strong"
    local rest = ghost and C.quiet or C.text
    local b = CreateFrame("Button", nil, parent)
    b.label = T.Text(b, "semibold", 12.5, rest)
    b.label:SetText(text or "")
    if icon then
        b.icon = T.Icon(b, icon, 14, rest)
        b.label:SetPoint("LEFT", b.icon, "RIGHT", 8, 0)
    else
        b.label:SetPoint("CENTER")
    end
    -- Sized from the text. A custom font can measure 0 until it has loaded, so this runs again once shown.
    local function Fit()
        local tw = b.label:GetStringWidth()
        if not width then b:SetWidth(math.ceil(tw + (icon and 22 or 0) + (strong and 44 or 28))) end
        if b.icon then b.icon:SetPoint("CENTER", b, "CENTER", -(tw + 8) / 2, 0) end
    end
    b:SetHeight(30)
    Fit()
    b:HookScript("OnShow", function()
        Fit()
        C_Timer.After(0, Fit)
    end)
    local box, wash
    if ghost then
        wash = T.Round(b, 5, { 1, 1, 1, 0.045 })
        wash:Hide()
    else
        box = T.Box(b, 5, C.control, strong and C.borderStrong or { 1, 1, 1, 0.12 })
    end
    b:SetScript("OnEnter", function(self)
        if box then box:SetFill(C.controlHover) else wash:Show() end
        self.label:SetTextColor(T.RGBA(C.text))
        if self.icon then self.icon:SetVertexColor(T.RGBA(strong and Accent() or C.text)) end
        if strong then box:SetBorder(Accent(0.9)) end
        Tip(self, tip)
    end)
    b:SetScript("OnLeave", function(self)
        if box then box:SetFill(C.control) else wash:Hide() end
        if strong then box:SetBorder(C.borderStrong) end
        self.label:SetTextColor(T.RGBA(rest))
        if self.icon then self.icon:SetVertexColor(T.RGBA(rest)) end
        GameTooltip:Hide()
    end)
    b:SetScript("OnClick", onClick)
    return b
end

-- A square icon-only button (list actions).
local function IconButton(parent, icon, tip, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(30, 30)
    b.bg = T.Round(b, 5, C.controlHover)
    b.bg:Hide()
    b.icon = T.Icon(b, icon, 14, C.dim)
    b.icon:SetPoint("CENTER")
    b:SetScript("OnEnter", function(self)
        self.bg:Show()
        self.icon:SetVertexColor(T.RGBA(C.text))
        Tip(self, tip)
    end)
    b:SetScript("OnLeave", function(self)
        self.bg:Hide()
        self.icon:SetVertexColor(T.RGBA(C.dim))
        GameTooltip:Hide()
    end)
    b:SetScript("OnClick", onClick)
    return b
end

--------------------------------------------------------------------------------
-- Controls. Each Build* puts its control at the right of `half` and returns a refresh function.
--------------------------------------------------------------------------------
local function BuildToggle(half, cfg)
    local sw = Switch(half)
    sw:SetPoint("RIGHT", half, "RIGHT", -18, 0)
    local function Refresh() sw:SetOn(cfg.getValue() and true or false) end
    -- The whole half is the hit area.
    half:SetScript("OnClick", function()
        cfg.setValue(not cfg.getValue())
        Refresh()
        Changed(cfg)
    end)
    Refresh()
    return Refresh
end

local function StepFormat(step)
    if step >= 1 then return "%d" end
    if step >= 0.1 then return "%.1f" end
    return "%.2f"
end

local function BuildSlider(half, cfg)
    local fmt = StepFormat(cfg.step or 1)
    local box = CreateFrame("Frame", nil, half)
    box:SetSize(46, 26)
    box:SetPoint("RIGHT", half, "RIGHT", -18, 0)
    T.Box(box, 4, C.inset, { 1, 1, 1, 0.09 })
    local value = T.Text(box, "mono", 11.5, C.text)
    value:SetPoint("CENTER", 0, 0)
    value:SetJustifyH("CENTER")

    local s = CreateFrame("Slider", nil, half)
    s:SetOrientation("HORIZONTAL")
    s:SetSize(SLIDER_W - 46 - 12, 18)
    s:SetPoint("RIGHT", box, "LEFT", -12, 0)
    s:SetMinMaxValues(cfg.min, cfg.max)
    s:SetValueStep(cfg.step or 1)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    -- The thumb travels between its own half-widths, so the rail starts and ends at its centre.
    local rail = s:CreateTexture(nil, "BACKGROUND")
    rail:SetColorTexture(T.RGBA(C.track))
    rail:SetHeight(3)
    rail:SetPoint("LEFT", 6, 0)
    rail:SetPoint("RIGHT", -6, 0)
    local thumb = s:CreateTexture(nil, "OVERLAY")
    thumb:SetTexture(T.CIRCLE, nil, nil, "TRILINEAR")
    thumb:SetSize(12, 12)
    thumb:SetVertexColor(T.RGBA(C.text))
    s:SetThumbTexture(thumb)
    local ring = s:CreateTexture(nil, "ARTWORK", nil, 2) -- a card-coloured halo that cuts the rail around the knob
    ring:SetTexture(T.CIRCLE, nil, nil, "TRILINEAR")
    ring:SetSize(18, 18)
    ring:SetVertexColor(T.RGBA(C.card))
    ring:SetPoint("CENTER", thumb, "CENTER")
    local fill = s:CreateTexture(nil, "ARTWORK", nil, 1)
    fill:SetColorTexture(T.RGBA(C.boneFill))
    fill:SetHeight(3)
    fill:SetPoint("LEFT", rail, "LEFT")
    fill:SetPoint("RIGHT", thumb, "CENTER")

    local step = cfg.step or 1
    local function Snap(v)
        v = math.floor(v / step + 0.5) * step
        return math.min(math.max(v, cfg.min), cfg.max)
    end
    local function Show(v) value:SetText(fmt:format(v)) end
    s:SetScript("OnValueChanged", function(_, v, userInput)
        v = Snap(v)
        Show(v)
        if userInput then cfg.setValue(v) end
    end)
    s:SetScript("OnMouseUp", function() Changed(cfg) end)
    local function Refresh()
        local v = cfg.getValue() or cfg.min
        s:SetValue(v)
        Show(Snap(v))
    end
    Refresh()
    return Refresh
end

-- One drop menu for every dropdown; a screen-wide catcher closes it on any outside click.
local menu, catcher
local function CloseMenu()
    if menu then
        menu:Hide()
        if menu.owner and menu.owner.Unfocus then menu.owner:Unfocus() end
        menu.owner = nil
    end
    if catcher then catcher:Hide() end
end
O.CloseMenu = CloseMenu

local MENU_ROW = 28

local function OpenMenu(anchor, cfg, onPick)
    if not menu then
        catcher = CreateFrame("Button", nil, UIParent)
        catcher:SetAllPoints(UIParent)
        catcher:SetFrameStrata("FULLSCREEN_DIALOG")
        catcher:SetScript("OnClick", CloseMenu)
        menu = CreateFrame("Frame", nil, catcher)
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:SetFrameLevel(catcher:GetFrameLevel() + 5)
        menu:EnableMouse(true)
        T.Box(menu, 6, C.field, C.borderStrong)
        menu.items = {}
    end
    local order = cfg.order or {}
    if #order == 0 then
        for k in pairs(cfg.values or {}) do order[#order + 1] = k end
        table.sort(order, function(a, b) return tostring(cfg.values[a]) < tostring(cfg.values[b]) end)
    end
    local cur = cfg.getValue()
    local accent = Accent()
    for i, key in ipairs(order) do
        local it = menu.items[i]
        if not it then
            it = CreateFrame("Button", nil, menu)
            it:SetHeight(MENU_ROW)
            it.hl = T.Round(it, 4, C.controlHover)
            it.hl:Hide()
            it.sw = CreateFrame("Frame", nil, it)
            it.sw:SetSize(10, 10)
            it.sw:SetPoint("LEFT", 10, 0)
            it.sw.shape = T.Round(it.sw, 2, C.text, "ARTWORK")
            it.text = T.Text(it, "semibold", 12.5, C.text)
            it.text:SetPoint("RIGHT", -28, 0)
            it.check = T.Icon(it, "Check", 14, accent)
            it.check:SetPoint("RIGHT", -8, 0)
            it:SetScript("OnEnter", function(self) self.hl:Show() end)
            it:SetScript("OnLeave", function(self) self.hl:Hide() end)
            menu.items[i] = it
        end
        it:ClearAllPoints()
        it:SetPoint("TOPLEFT", 4, -4 - (i - 1) * MENU_ROW)
        it:SetPoint("TOPRIGHT", -4, -4 - (i - 1) * MENU_ROW)
        it.sw:SetShown(cfg.swatch ~= nil)
        if cfg.swatch then it.sw.shape:SetColor(cfg.swatch(key)) end
        it.text:SetPoint("LEFT", cfg.swatch and 28 or 10, 0)
        it.text:SetText(tostring(cfg.values[key] or key))
        local on = key == cur
        it.text:SetTextColor(T.RGBA(on and accent or C.text))
        it.check:SetVertexColor(T.RGBA(accent))
        it.check:SetShown(on)
        it:SetScript("OnClick", function()
            CloseMenu()
            onPick(key)
        end)
        it:Show()
    end
    for i = #order + 1, #menu.items do menu.items[i]:Hide() end
    -- At least as wide as the button, wider if an option needs it; grows leftward, away from the window edge.
    local width = anchor:GetWidth()
    for i = 1, #order do
        local fs = menu.items[i].text
        local tw = fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth() or fs:GetStringWidth()
        width = math.max(width, math.ceil(tw + (cfg.swatch and 28 or 10) + 28 + 8))
    end
    menu:SetSize(width, #order * MENU_ROW + 8)
    menu:ClearAllPoints()
    menu:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -4)
    menu:SetScale(anchor:GetEffectiveScale() / UIParent:GetEffectiveScale())
    menu.owner = anchor
    catcher:Show()
    menu:Show()
end

local function BuildDropdown(half, cfg, label)
    local b = CreateFrame("Button", nil, half)
    b:SetSize(cfg.width or CTRL_W, 30)
    b:SetPoint("RIGHT", half, "RIGHT", -18, 0)
    local box = T.Box(b, 5, C.control, C.border)
    local x, sw = 12, nil
    if cfg.swatch then
        sw = CreateFrame("Frame", nil, b)
        sw:SetSize(10, 10)
        sw:SetPoint("LEFT", 12, 0)
        sw.shape = T.Round(sw, 2, C.text, "ARTWORK")
        x = 30
    end
    b.text = T.Text(b, "semibold", 12.5, C.text)
    b.text:SetPoint("LEFT", x, 0)
    b.text:SetPoint("RIGHT", -30, 0)
    local chev = T.Icon(b, "ChevronDown", 14, C.dim)
    chev:SetPoint("RIGHT", -10, 0)
    -- Wide enough for the longest option, never narrower than the set width. A custom font can
    -- measure 0 until it has loaded, so this runs again once shown.
    local measure = T.Text(b, "semibold", 12.5, C.text)
    measure:Hide()
    local function Fit()
        local widest = 0
        for _, v in pairs(cfg.values or {}) do
            measure:SetText(tostring(v))
            widest = math.max(widest, measure:GetStringWidth())
        end
        local maxW = math.max(cfg.width or CTRL_W, half:GetWidth() - 18 - 18 - 16 - 120)
        local w = math.min(math.max(cfg.width or CTRL_W, math.ceil(widest + x + 30)), maxW)
        if math.abs(b:GetWidth() - w) < 0.5 then return end
        b:SetWidth(w)
        if label then label:Fit(w) end
    end
    Fit()
    b:HookScript("OnShow", function()
        Fit()
        C_Timer.After(0, Fit)
    end)
    local open = false
    function b:Unfocus()
        open = false
        box:SetBorder(self:IsMouseOver() and C.borderHover or C.border)
    end
    local function Refresh()
        local v = cfg.getValue()
        b.text:SetText(tostring(cfg.values[v] or v or ""))
        if sw then sw.shape:SetColor(cfg.swatch(v)) end
    end
    b:SetScript("OnEnter", function() if not open then box:SetBorder(C.borderHover) end end)
    b:SetScript("OnLeave", function() if not open then box:SetBorder(C.border) end end)
    b:SetScript("OnClick", function(self)
        OpenMenu(self, cfg, function(key)
            cfg.setValue(key)
            Refresh()
            Changed(cfg)
        end)
        open = true
        box:SetBorder(Accent(0.9))
    end)
    Refresh()
    return Refresh
end

local function BuildInput(half, cfg)
    local box = CreateFrame("EditBox", nil, half)
    box:SetSize(cfg.width or 280, 30)
    box:SetPoint("RIGHT", half, "RIGHT", -18, 0)
    Field(box, cfg.placeholder, nil, function()
        local text = box:GetText() or ""
        box:SetText("")
        box:ClearFocus()
        if text:match("%S") then cfg.setValue(text) end
    end)
    return function() end
end

local BUILDERS = { toggle = BuildToggle, slider = BuildSlider, dropdown = BuildDropdown, input = BuildInput }

local function BuildHalf(half, cfg)
    if not cfg then return end
    if cfg.type == "button" then
        local b = O.Button(half, cfg.text, cfg.width, cfg.onClick, cfg.tooltip)
        b:SetPoint("RIGHT", half, "RIGHT", -18, 0)
        if cfg.label then Label(half, { text = cfg.label }, b:GetWidth()) end
        return
    end
    local controlW = cfg.type == "toggle" and 34 or cfg.type == "slider" and SLIDER_W
        or (cfg.width or (cfg.type == "input" and 280 or CTRL_W))
    local label = Label(half, cfg, BUILDERS[cfg.type] and controlW or 0)
    local build = BUILDERS[cfg.type]
    if build then build(half, cfg, label) end
    half:SetScript("OnEnter", function(self)
        label:SetTextColor(T.RGBA(C.text))
        Tip(self, cfg.tooltip)
    end)
    half:SetScript("OnLeave", function()
        label:SetTextColor(T.RGBA(C.label))
        GameTooltip:Hide()
    end)
end

-- Back-to-back rows join the same card; anything else in between starts a new one.
function O.Pair(_, parent, y, left, right)
    local g = flow.group
    if not (g and g.parent == parent and g.bottom == y) then
        y = Open(y, "group")
        g = CreateFrame("Frame", nil, parent)
        g:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD_L, y)
        g:SetSize(O.Width(parent), ROW_H)
        T.Box(g, 8, C.card, C.cardBorder)
        g.parent, g.top, g.rows = parent, y, 0
        flow.group = g
    end
    local width = g:GetWidth()
    local row = CreateFrame("Frame", nil, g)
    row:SetPoint("TOPLEFT", g, "TOPLEFT", 0, y - g.top)
    row:SetSize(width, ROW_H)
    if g.rows > 0 then HLine(row, C.rowLine, true) end
    g.rows = g.rows + 1

    local full = not right or (right.type == "label" and (right.text or "") == "")
    local split = math.floor(width / 2)
    local leftHalf = CreateFrame("Button", nil, row)
    leftHalf:SetPoint("TOPLEFT")
    leftHalf:SetSize(full and width or split, ROW_H)
    BuildHalf(leftHalf, left)
    if not full then
        local rightHalf = CreateFrame("Button", nil, row)
        rightHalf:SetPoint("TOPRIGHT")
        rightHalf:SetSize(width - split, ROW_H)
        BuildHalf(rightHalf, right)
        local div = row:CreateTexture(nil, "ARTWORK")
        div:SetColorTexture(T.RGBA(C.cardBorder))
        div:SetWidth(T.Px(row))
        div:SetPoint("TOPLEFT", row, "TOPLEFT", split, 0)
        div:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", split, 0)
    end
    g.bottom = y - ROW_H
    g:SetHeight(g.top - g.bottom)
    flow.last = "group"
    return g.bottom, row
end

-- A module's on/off switch, as the card that opens its page.
function O.Master(parent, y, M)
    y = Open(y, "master") - 18
    local card = CreateFrame("Button", nil, parent)
    card:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD_L, y)
    card:SetSize(O.Width(parent), 64)
    T.Box(card, 8, C.card, C.cardBorder)
    local chip = CreateFrame("Frame", nil, card)
    chip:SetSize(34, 34)
    chip:SetPoint("LEFT", 16, 0)
    T.Round(chip, 7, Accent(0.12), "ARTWORK")
    local icon = T.Icon(chip, M.icon or "Character", 18, Accent(), "OVERLAY")
    icon:SetPoint("CENTER")
    local title = T.Text(card, "bold", 14, C.text)
    title:SetPoint("BOTTOMLEFT", chip, "RIGHT", 14, 1)
    title:SetText("Track " .. M.title:lower())
    local sub = T.Text(card, "medium", 12, C.quiet)
    sub:SetPoint("TOPLEFT", chip, "RIGHT", 14, -3)
    sub:SetText(("Adds a %s section to the board."):format(M.title))
    local sw = Switch(card)
    sw:SetPoint("RIGHT", card, "RIGHT", -18, 0)
    sw:SetOn(M:IsEnabled())
    card:SetScript("OnClick", function()
        M:SetEnabled(not M:IsEnabled())
        sw:SetOn(M:IsEnabled())
        O.Rebuild() -- the sidebar's OFF tag follows
    end)
    flow.last = "master"
    return y - 64
end

-- Settings-table bound configs. onChange runs after every write (default: re-apply the board).
function O.Rows(tbl, onChange)
    local R = {}
    local function Base(key, kind, text, opt)
        opt = opt or {}
        return {
            type = kind, text = text, tooltip = opt.tooltip, refreshPage = opt.refreshPage, width = opt.width,
            swatch = opt.swatch,
            getValue = function()
                local v = tbl[key]
                if kind == "toggle" then return v and true or false end
                return v
            end,
            setValue = function(v)
                tbl[key] = v
                if onChange then onChange() else TM.board:ApplySettings() end
            end,
        }
    end
    function R.Toggle(key, text, opt) return Base(key, "toggle", text, opt) end
    function R.Slider(key, text, min, max, step, opt)
        local cfg = Base(key, "slider", text, opt)
        cfg.min, cfg.max, cfg.step = min, max, step
        return cfg
    end
    function R.Dropdown(key, text, values, order, opt)
        local cfg = Base(key, "dropdown", text, opt)
        cfg.values, cfg.order = values, order
        return cfg
    end
    return R
end

function O.EnableToggle(M, text)
    return {
        type = "toggle", text = text or "Show on the board", refreshPage = true,
        getValue = function() return M:IsEnabled() end,
        setValue = function(v) M:SetEnabled(v) end,
    }
end

function O.AddBar(parent, y, placeholder, onSubmit, tooltip, buttonText)
    y = Open(y, "bar")
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD_L, y)
    bar:SetSize(O.Width(parent), 34)
    local box = CreateFrame("EditBox", nil, bar)
    local function Submit()
        local text = box:GetText() or ""
        box:SetText("")
        box:ClearFocus()
        if text:match("%S") then onSubmit(text) end
    end
    local btn = O.Button(bar, buttonText or "Add", nil, Submit, tooltip)
    btn:SetHeight(34)
    btn:SetPoint("RIGHT")
    box:SetPoint("TOPLEFT")
    box:SetPoint("BOTTOMRIGHT", btn, "BOTTOMLEFT", -10, 0)
    Field(box, placeholder, "Plus", Submit)
    return y - 34
end

-- Older call shape: an add box whose button reads `text`.
function O.Input(_, parent, y, text, placeholder, onSubmit, tooltip)
    return O.AddBar(parent, y, placeholder, onSubmit, tooltip, text)
end

--------------------------------------------------------------------------------
-- Lists
--------------------------------------------------------------------------------
local GLYPH_ICONS = {
    close = "Close", plus = "Plus",
    chevron = { up = "ArrowUp", left = "ArrowUp", down = "ArrowDown", right = "ArrowDown" },
}

local function ActionButton(row, a, anchor)
    local b
    if a.glyph then
        local icon = GLYPH_ICONS[a.glyph]
        if type(icon) == "table" then icon = icon[a.dir or "down"] end
        b = IconButton(row, icon or "Plus", a.tip, a.onClick)
    else
        b = O.Button(row, a.text, nil, a.onClick, a.tip, "ghost")
        b:SetHeight(28)
    end
    b:SetPoint("RIGHT", anchor, anchor == row and "RIGHT" or "LEFT", anchor == row and -10 or -4, 0)
    b:HookScript("OnEnter", function() row.hl:Show() end)
    b:HookScript("OnLeave", function() if not row:IsMouseOver() then row.hl:Hide() end end)
    return b
end

-- Every second row of a list gets a faint band so long lists read across.
local STRIPE = { 1, 1, 1, 0.022 }

local function ListRow(card, offset, width, item, first, last, striped)
    local row = CreateFrame("Frame", nil, card)
    row:SetPoint("TOPLEFT", card, "TOPLEFT", 0, -offset)
    row:SetSize(width, LIST_H)
    row:EnableMouse(true)
    if striped then
        -- Inside the card's border; rounded only where the row meets the card's rounded bottom.
        local px = T.Px(card)
        T.Round(row, 8 - px, STRIPE, "BACKGROUND", -1, px,
            last and { BOTTOMLEFT = true, BOTTOMRIGHT = true } or {})
    end
    row.hl = T.Round(row, 6, { 1, 1, 1, 0.03 }, "BACKGROUND", 0, 4)
    row.hl:Hide()
    if not first then HLine(row, C.rowLine, true) end

    local x = 18
    if item.icon then
        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(22, 22)
        icon:SetPoint("LEFT", row, "LEFT", x, 0)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon:SetTexture(item.icon)
        x = x + 22 + 12
    end

    local anchor = row
    local actions = item.actions or {}
    for i = #actions, 1, -1 do anchor = ActionButton(row, actions[i], anchor) end

    local sub = T.Text(row, "mono", 11, C.dim)
    sub:SetPoint("RIGHT", anchor, anchor == row and "RIGHT" or "LEFT", anchor == row and -18 or -12, 0)
    sub:SetJustifyH("RIGHT")
    sub:SetText(item.sub or "")

    local name = T.Text(row, "semibold", 13, C.label)
    name:SetPoint("LEFT", row, "LEFT", x, 0)
    name:SetPoint("RIGHT", sub, "LEFT", -12, 0)
    name:SetText(item.text or "")

    row:SetScript("OnEnter", function(self)
        self.hl:Show()
        if item.tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local ok = pcall(item.tooltip, GameTooltip)
            if ok and GameTooltip:NumLines() > 0 then GameTooltip:Show() else GameTooltip:Hide() end
        end
    end)
    row:SetScript("OnLeave", function(self)
        if not self:IsMouseOver() then self.hl:Hide() end
        GameTooltip:Hide()
    end)
end

function O.List(parent, y, items, emptyText)
    y = Open(y, "list")
    local width = O.Width(parent)
    local card = CreateFrame("Frame", nil, parent)
    card:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD_L, y)
    T.Box(card, 8, C.card, C.cardBorder)
    if #items == 0 then
        card:SetSize(width, 46)
        local none = T.Text(card, "medium", 12.5, C.dim)
        none:SetPoint("LEFT", 18, 0)
        none:SetText(emptyText or "Nothing here yet.")
        return y - 46
    end
    card:SetSize(width, #items * LIST_H)
    for i, item in ipairs(items) do
        ListRow(card, (i - 1) * LIST_H, width, item, i == 1, i == #items, i % 2 == 0)
    end
    return y - #items * LIST_H
end

-- spec: placeholder, parse(text) -> entries, describe(entry) -> name, icon, sub, tooltip(entry, tt), actions(entry),
--       discover() -> { { entry, text, icon, sub } }, discoverTitle, emptyDiscover
function O.TrackedList(M, _, parent, y, spec)
    y = O.AddBar(parent, y, spec.placeholder, function(text)
        local added = 0
        for _, e in ipairs(spec.parse(text)) do
            if M:AddEntry(e) then added = added + 1 end
        end
        if added > 0 then O.Rebuild() else TM.Say("Nothing new to add from \"" .. text .. "\".") end
    end, "Press Enter or click to add. Shift-click links into the box while it has focus.", "Add")

    local items = {}
    for _, e in ipairs(M:Entries()) do
        local name, icon, sub = spec.describe(e)
        if M:IsDefault(e.id) then sub = (sub and sub ~= "" and (sub .. " · ") or "") .. "default" end
        local actions = spec.actions and spec.actions(e) or {}
        for _, a in ipairs(actions) do
            local click = a.onClick
            a.onClick = function() click(); O.Rebuild() end
        end
        actions[#actions + 1] = {
            glyph = "close", tip = "Stop tracking",
            onClick = function() M:RemoveEntry(e.id); O.Rebuild() end,
        }
        items[#items + 1] = {
            text = name, icon = icon, sub = sub, actions = actions,
            tooltip = spec.tooltip and function(tt) spec.tooltip(e, tt) end or nil,
        }
    end
    y = O.List(parent, y, items, "Nothing tracked yet.")

    local removed = M:RemovedDefaults()
    if removed > 0 then
        y = O.Pair(nil, parent, y, {
            type = "button", text = "Restore",
            label = ("%d removed default%s"):format(removed, removed == 1 and "" or "s"),
            onClick = function() M:RestoreDefaults(); O.Rebuild() end,
        })
    end

    if spec.discover then
        y = O.Header(nil, parent, y, spec.discoverTitle or "DISCOVER")
        local found = {}
        for _, c in ipairs(spec.discover()) do
            found[#found + 1] = {
                text = c.text, icon = c.icon, sub = c.sub,
                actions = { {
                    glyph = "plus", tip = "Track this",
                    onClick = function() M:AddEntry(c.entry); O.Rebuild() end,
                } },
            }
        end
        y = O.List(parent, y, found, spec.emptyDiscover or "Nothing new to add on this character.")
    end
    return y
end
