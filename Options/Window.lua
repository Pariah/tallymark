-- Tallymark options window, Ledger style.
--   Sidebar  logo, search box (visual only for now), pages under group headings with icons, version footer
--   Header   ruled lines, a double margin rule, a ghost tally mark, eyebrow / title / subtitle, close button
--   Page     the open page in a scroll frame
--   Footer   Reset page, a hint, Close
-- Pages register with Win:AddPage{ key, title, group, icon, subtitle, resetNote, isOff(), build(parent, y) -> y, reset() };
-- Options/Pages.lua adds them all. A page is built fresh each time it opens, so it always shows current data.
local _, TM = ...
local T = TM.Theme
local C = T.C
local O = TM.Options

local Win = { pages = {} }
TM.optionsWindow = Win

-- Sized like other big addon option windows. Every page layout follows W (content width = W - SIDE_W - 1).
local W, H, SIDE_W, HEAD_H, FOOT_H, RADIUS = 1240, 860, 232, 112, 60, 10
local frame, scroll, content, navItems, thumb, track
local chrome = {} -- parts painted in the accent colour
local head = {}   -- per-page text in the header and footer
local current

function Win:AddPage(spec)
    self.pages[#self.pages + 1] = spec
end

local function PageByKey(key)
    for _, p in ipairs(Win.pages) do
        if p.key == key then return p end
    end
end

local function PageIndex(page)
    for i, p in ipairs(Win.pages) do
        if p == page then return i end
    end
    return 0
end

local function Line(parent, color, edge, layer)
    local t = parent:CreateTexture(nil, layer or "BORDER")
    t:SetColorTexture(T.RGBA(color))
    if edge == "TOP" or edge == "BOTTOM" then
        t:SetHeight(T.Px(parent))
        t:SetPoint(edge .. "LEFT")
        t:SetPoint(edge .. "RIGHT")
    else
        t:SetWidth(T.Px(parent))
        t:SetPoint("TOP" .. edge)
        t:SetPoint("BOTTOM" .. edge)
    end
    return t
end

--------------------------------------------------------------------------------
-- Sidebar
--------------------------------------------------------------------------------
local function PaintNav()
    local r, g, b = TM.Accent()
    chrome.logo:SetVertexColor(r, g, b, 1)
    chrome.ghost:SetVertexColor(r, g, b, 0.07)
    for _, l in ipairs(chrome.margin) do l:SetColorTexture(r, g, b, 0.30) end
    for _, item in ipairs(navItems) do
        if not item.isGroup then
            local on = current and item.page.key == current.key
            local off = item.page.isOff and item.page.isOff() or false
            item.bg:SetColor(r, g, b, 0.10)
            item.bg:SetShown(on)
            item.hover:Hide()
            item.text:SetTextColor(T.RGBA(on and C.text or off and C.disabled or C.quiet))
            if on then
                item.icon:SetVertexColor(r, g, b, 1)
            else
                item.icon:SetVertexColor(T.RGBA(off and C.disabled or C.quiet))
            end
            item.tag:SetShown(off)
        end
    end
end

local function BuildNav(side)
    navItems = {}
    local y = -HEAD_H
    local lastGroup
    for _, page in ipairs(Win.pages) do
        if page.group ~= lastGroup then
            lastGroup = page.group
            local g = { isGroup = true }
            g.text = T.Text(side, "caps", 10.5, C.dim)
            g.text:SetPoint("TOPLEFT", side, "TOPLEFT", 22, y - 18)
            g.text:SetText((page.group or ""):upper())
            navItems[#navItems + 1] = g
            y = y - 40
        end
        local item = CreateFrame("Button", nil, side)
        item.page = page
        item:SetPoint("TOPLEFT", side, "TOPLEFT", 10, y)
        item:SetSize(SIDE_W - 20, 34)
        item.hover = T.Round(item, 6, { 1, 1, 1, 0.035 })
        item.bg = T.Round(item, 6, { 1, 1, 1, 0 }, "BACKGROUND", 1)
        item.icon = T.Icon(item, page.icon or "Display", 18, C.quiet)
        item.icon:SetPoint("LEFT", 12, 0)
        item.text = T.Text(item, "semibold", 13, C.quiet)
        item.text:SetPoint("LEFT", item.icon, "RIGHT", 12, 0)
        item.text:SetText(page.title)
        item.tag = CreateFrame("Frame", nil, item)
        item.tag:SetSize(30, 15)
        item.tag:SetPoint("RIGHT", -10, 0)
        T.Border(item.tag, 1, 1, 1, 0.08)
        local tagText = T.Text(item.tag, "mono", 9.5, C.disabled)
        tagText:SetPoint("CENTER", 0, 0)
        tagText:SetText("OFF")
        item:SetScript("OnEnter", function(self)
            if current and self.page.key == current.key then return end
            self.hover:Show()
            self.text:SetTextColor(T.RGBA(C.text))
        end)
        item:SetScript("OnLeave", function() PaintNav() end)
        item:SetScript("OnClick", function(self) Win:Select(self.page.key) end)
        navItems[#navItems + 1] = item
        y = y - 34
    end
end

local function BuildSidebar(px)
    local side = CreateFrame("Frame", nil, frame)
    side:SetPoint("TOPLEFT", px, -px)
    side:SetPoint("BOTTOMLEFT", px, px)
    side:SetWidth(SIDE_W - px)
    T.Round(side, RADIUS - px, C.sidebar, "BACKGROUND", 0, 0, { TOPLEFT = true, BOTTOMLEFT = true })
    Line(side, C.line, "RIGHT")

    -- Brand block, the same height as the header so their bottom rules meet.
    chrome.logo = side:CreateTexture(nil, "ARTWORK")
    chrome.logo:SetTexture(T.TALLY, nil, nil, "TRILINEAR")
    chrome.logo:SetSize(28, 28)
    chrome.logo:SetPoint("TOPLEFT", 18, -22)
    local word = T.Text(side, "heavy", 20, C.text)
    word:SetPoint("LEFT", chrome.logo, "RIGHT", 10, 0)
    word:SetText("Tallymark")

    -- Search: looks the part, does nothing yet.
    local search = CreateFrame("EditBox", nil, side)
    search:SetPoint("TOPLEFT", 16, -64)
    search:SetSize(SIDE_W - 32 - px, 30)
    O.Field(search, "Search settings", "Search", function() search:ClearFocus() end, C.field, { 1, 1, 1, 0.08 })

    local rule = side:CreateTexture(nil, "BORDER")
    rule:SetColorTexture(T.RGBA(C.line))
    rule:SetHeight(px)
    rule:SetPoint("TOPLEFT", 0, -(HEAD_H - px))
    rule:SetPoint("TOPRIGHT", 0, -(HEAD_H - px))

    BuildNav(side)

    local foot = CreateFrame("Frame", nil, side)
    foot:SetPoint("BOTTOMLEFT")
    foot:SetPoint("BOTTOMRIGHT")
    foot:SetHeight(FOOT_H - px)
    Line(foot, C.line, "TOP")
    local version = T.Text(foot, "mono", 11, C.dim)
    version:SetPoint("LEFT", 22, 0)
    version:SetText("v" .. TM.version)
    local slash = T.Text(foot, "mono", 11, C.dim)
    slash:SetPoint("RIGHT", -22, 0)
    slash:SetText("/tally")
    return side
end

--------------------------------------------------------------------------------
-- Header and footer
--------------------------------------------------------------------------------
local function BuildHeader(side, px)
    local hf = CreateFrame("Frame", nil, frame)
    hf:SetPoint("TOPLEFT", side, "TOPRIGHT", 0, 0)
    hf:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -px, -px)
    hf:SetHeight(HEAD_H - px)
    T.Round(hf, RADIUS - px, C.header, "BACKGROUND", 0, 0, { TOPRIGHT = true })
    Line(hf, C.line, "BOTTOM")

    -- Ledger paper: ruled lines that fade out towards the left.
    local lineStart = (W - SIDE_W) * 0.2
    for i = 1, 5 do
        local l = hf:CreateTexture(nil, "BORDER")
        l:SetColorTexture(1, 1, 1, 1)
        l:SetGradient("HORIZONTAL", CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, 0.035))
        l:SetHeight(px)
        l:SetPoint("TOPLEFT", hf, "TOPLEFT", lineStart, -(i * 22 - 1))
        l:SetPoint("TOPRIGHT", hf, "TOPRIGHT", 0, -(i * 22 - 1))
    end
    -- The double margin rule down the left edge.
    chrome.margin = {}
    for i, x in ipairs({ 14, 16 }) do
        local l = hf:CreateTexture(nil, "BORDER", nil, 1)
        l:SetWidth(px)
        l:SetPoint("TOPLEFT", x, 0)
        l:SetPoint("BOTTOMLEFT", x, 0)
        chrome.margin[i] = l
    end
    -- A big faint tally mark, cropped by the top edge.
    chrome.ghost = hf:CreateTexture(nil, "BORDER", nil, 2)
    chrome.ghost:SetTexture(T.TALLY_BIG, nil, nil, "TRILINEAR")
    chrome.ghost:SetSize(150, 132)
    chrome.ghost:SetTexCoord(0, 1, 18 / 150, 1)
    chrome.ghost:SetPoint("TOPRIGHT", -64, 0)

    head.eyebrow = T.Text(hf, "mono", 11, C.dim)
    head.eyebrow:SetPoint("TOPLEFT", 36, -24)
    head.title = T.Text(hf, "heavy", 30, C.text)
    head.title:SetPoint("TOPLEFT", head.eyebrow, "BOTTOMLEFT", 0, -5)
    head.subtitle = T.Text(hf, "medium", 13, C.quiet)
    head.subtitle:SetPoint("TOPLEFT", head.title, "BOTTOMLEFT", 0, -5)

    local close = CreateFrame("Button", nil, hf)
    close:SetSize(32, 32)
    close:SetPoint("TOPRIGHT", -20, -20)
    local box = T.Box(close, 6, C.field, C.borderStrong)
    local icon = T.Icon(close, "Close", 14, C.text)
    icon:SetPoint("CENTER")
    close:SetScript("OnEnter", function()
        local r, g, b = TM.Accent()
        box:SetBorder({ r, g, b, 0.9 })
        icon:SetVertexColor(r, g, b, 1)
    end)
    close:SetScript("OnLeave", function()
        box:SetBorder(C.borderStrong)
        icon:SetVertexColor(T.RGBA(C.text))
    end)
    close:SetScript("OnClick", function() frame:Hide() end)
    return hf
end

local function BuildFooter(side, px)
    local ff = CreateFrame("Frame", nil, frame)
    ff:SetPoint("BOTTOMLEFT", side, "BOTTOMRIGHT", 0, 0)
    ff:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -px, px)
    ff:SetHeight(FOOT_H - px)
    T.Round(ff, RADIUS - px, C.inset, "BACKGROUND", 0, 0, { BOTTOMRIGHT = true })
    Line(ff, C.line, "TOP")

    -- The page's hint on the left, its one action on the right. Closing is the header's X (or Escape).
    head.note = T.Text(ff, "medium", 12, C.dim)
    head.note:SetPoint("LEFT", 24, 0)
    head.reset = O.Button(ff, "Reset page", nil, function()
        if current and current.reset then
            current.reset()
            Win:Rebuild()
        end
    end, "Puts this page's settings back to their defaults. Tracked lists are kept.", "strong", "Reset")
    head.reset:SetPoint("RIGHT", -20, 0)
    head.note:SetPoint("RIGHT", head.reset, "LEFT", -16, 0)
    return ff
end

--------------------------------------------------------------------------------
-- Frame
--------------------------------------------------------------------------------
local function UpdateThumb()
    local range = scroll:GetVerticalScrollRange()
    if range <= 0 then
        thumb:Hide()
        track:Hide()
        return
    end
    local h = track:GetHeight()
    local th = math.max(h * h / (h + range), 24)
    thumb:SetHeight(th)
    thumb:ClearAllPoints()
    thumb:SetPoint("TOP", track, "TOP", 0, -((h - th) * scroll:GetVerticalScroll() / range))
    track:Show()
    thumb:Show()
end

local function Build()
    frame = CreateFrame("Frame", "TallymarkOptions", UIParent)
    frame:SetSize(W, H)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetScript("OnHide", function() O.CloseMenu() end)
    tinsert(UISpecialFrames, "TallymarkOptions")
    frame:Hide()

    -- Opaque body with a hairline edge; the sidebar, header and footer round only their outer corners.
    local px = T.Px(frame)
    T.Box(frame, RADIUS, C.window, C.border, "BACKGROUND", -8)

    local side = BuildSidebar(px)
    local hf = BuildHeader(side, px)
    local ff = BuildFooter(side, px)

    scroll = CreateFrame("ScrollFrame", nil, frame)
    scroll:SetPoint("TOPLEFT", hf, "BOTTOMLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", ff, "TOPRIGHT", 0, 0)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local v = math.min(math.max(self:GetVerticalScroll() - delta * 60, 0), self:GetVerticalScrollRange())
        self:SetVerticalScroll(v)
        UpdateThumb()
    end)
    track = frame:CreateTexture(nil, "OVERLAY")
    track:SetColorTexture(1, 1, 1, 0.04)
    track:SetWidth(3)
    track:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", -10, -14)
    track:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", -10, 14)
    track:Hide()
    thumb = frame:CreateTexture(nil, "OVERLAY", nil, 1)
    thumb:SetColorTexture(1, 1, 1, 0.20)
    thumb:SetWidth(3)
    thumb:Hide()
end

--------------------------------------------------------------------------------
-- Pages
--------------------------------------------------------------------------------
local function BuildPage(keepScroll)
    if not current then return end
    O.CloseMenu()
    local offset = keepScroll and scroll:GetVerticalScroll() or 0
    if content then content:Hide() end
    content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(W - SIDE_W - 1)
    content:SetHeight(1)
    scroll:SetScrollChild(content)

    head.eyebrow:SetText(("%s · %02d"):format((current.group or ""):upper(), PageIndex(current)))
    head.title:SetText(current.title)
    head.subtitle:SetText(current.subtitle or "")
    head.reset:SetShown(current.reset ~= nil)
    head.note:SetText(current.resetNote or "Changes apply as you make them.")

    O.BeginPage()
    local ok, y = xpcall(current.build, geterrorhandler(), content, -2)
    content:SetHeight(math.abs(ok and y or -40) + 28)
    PaintNav()
    C_Timer.After(0, function()
        scroll:SetVerticalScroll(math.min(offset, scroll:GetVerticalScrollRange()))
        UpdateThumb()
    end)
end

function Win:Select(key)
    current = PageByKey(key) or current or self.pages[1]
    self.lastKey = current and current.key
    BuildPage(false)
end

function Win:Rebuild()
    if frame and frame:IsShown() then BuildPage(true) end
end

function Win:Open(key)
    if not frame then Build() end
    -- Big UI scales on small screens: shrink the whole window to fit rather than run off the edges.
    local fit = math.min(1, UIParent:GetHeight() * 0.95 / H, UIParent:GetWidth() * 0.95 / W)
    if fit > 0 then frame:SetScale(fit) end
    frame:Show()
    self:Select(key or self.lastKey)
end

function Win:Toggle()
    if frame and frame:IsShown() then frame:Hide() else self:Open() end
end
