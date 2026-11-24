-- Tallymark look ("Ledger"): warm charcoal panels, hairline rules, one accent colour used sparingly.
-- Nothing here comes from another addon. Media/ holds our own copies: Manrope and IBM Plex Mono (SIL OFL, licences
-- beside them), Tabler outline icons (MIT) rasterised to white TGAs, and a few drawn textures (circle, tally mark).
local _, TM = ...

local T = {}
TM.Theme = T

T.BG = { 0.067, 0.071, 0.082 }     -- board window
T.SIDEBAR = { 0.051, 0.055, 0.063 } -- board drop menus
T.CARD = { 1, 1, 1, 0.028 }         -- board rows
T.DISC = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask" -- a white disc

local MEDIA = "Interface\\AddOns\\Tallymark\\Media\\"
T.MEDIA = MEDIA
T.CIRCLE = MEDIA .. "Textures\\Circle32"   -- antialiased white disc: corners, knobs
T.TALLY = MEDIA .. "Textures\\Tally64"     -- the logo mark
T.TALLY_BIG = MEDIA .. "Textures\\Tally256" -- the header watermark

--------------------------------------------------------------------------------
-- Ledger tokens (the options window). Hex values match the mockup's kit sheet.
--------------------------------------------------------------------------------
local function Hex(h, a)
    return { tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255, a or 1 }
end

T.C = {
    sidebar = Hex("0F0F0E"), inset = Hex("121110"), window = Hex("151413"), header = Hex("171615"),
    card = Hex("1A1918"), field = Hex("1B1A18"), control = Hex("201F1D"), controlHover = Hex("292725"),
    text = Hex("ECE8E1"), label = Hex("E2DDD4"), quiet = Hex("A39E95"), dim = Hex("8A857B"), disabled = Hex("6B665E"),
    bone = Hex("D9D2C3"), boneFill = Hex("CFC8BA"), track = Hex("34322F"), toggleOff = Hex("2E2C29"),
    line = { 1, 1, 1, 0.07 }, rowLine = { 1, 1, 1, 0.045 }, cardBorder = { 1, 1, 1, 0.06 },
    border = { 1, 1, 1, 0.10 }, borderHover = { 1, 1, 1, 0.18 }, borderStrong = { 1, 1, 1, 0.30 },
}

-- r, g, b, a from a token (alpha overridable).
function T.RGBA(c, a) return c[1], c[2], c[3], a or c[4] or 1 end

-- The options window's own type. It does not follow the board's font setting.
T.UI = {
    medium = MEDIA .. "Fonts\\Manrope-Medium.ttf",
    semibold = MEDIA .. "Fonts\\Manrope-SemiBold.ttf",
    bold = MEDIA .. "Fonts\\Manrope-Bold.ttf",
    heavy = MEDIA .. "Fonts\\Manrope-ExtraBold.ttf",
    caps = MEDIA .. "Fonts\\Manrope-BoldTracked.ttf", -- letter-spaced, for small all-caps labels
    mono = MEDIA .. "Fonts\\IBMPlexMono-Medium.ttf",
}

-- A flat font string in one of the T.UI faces. Left-aligned, single line, no shadow.
function T.Text(parent, face, size, color, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    fs:SetFont(T.UI[face] or T.UI.medium, size, "")
    fs:SetTextColor(T.RGBA(color or T.C.text))
    fs:SetShadowOffset(0, 0)
    fs:SetWordWrap(false)
    fs:SetJustifyH("LEFT")
    return fs
end

-- One physical pixel, in the frame's units.
function T.Px(frame)
    if PixelUtil and PixelUtil.GetNearestPixelSize then
        return PixelUtil.GetNearestPixelSize(1, frame:GetEffectiveScale(), 1)
    end
    return 1
end

-- A white Tabler icon from Media/Icons, tinted.
function T.Icon(parent, name, size, color, layer)
    local t = parent:CreateTexture(nil, layer or "ARTWORK")
    t:SetTexture(MEDIA .. "Icons\\" .. name, nil, nil, "TRILINEAR")
    t:SetSize(size, size)
    t:SetVertexColor(T.RGBA(color or T.C.quiet))
    return t
end

--------------------------------------------------------------------------------
-- Rounded rectangles. WoW has no corner radius, so a shape is seven textures: four corners cut from the circle
-- texture plus three plain bands. The pieces never overlap, so translucent colours stay even.
-- corners: nil for all four, or a set like { TOPLEFT = true } (the others stay square).
--------------------------------------------------------------------------------
local Shape = {}
Shape.__index = Shape

function Shape:SetColor(r, g, b, a)
    for _, t in ipairs(self.round) do t:SetVertexColor(r, g, b, a or 1) end
    for _, t in ipairs(self.flat) do t:SetColorTexture(r, g, b, a or 1) end
end

function Shape:SetShown(on)
    for _, t in ipairs(self.round) do t:SetShown(on) end
    for _, t in ipairs(self.flat) do t:SetShown(on) end
end
function Shape:Show() self:SetShown(true) end
function Shape:Hide() self:SetShown(false) end

local CORNERS = {
    { "TOPLEFT", 1, -1, 0, 0.5, 0, 0.5 },
    { "TOPRIGHT", -1, -1, 0.5, 1, 0, 0.5 },
    { "BOTTOMLEFT", 1, 1, 0, 0.5, 0.5, 1 },
    { "BOTTOMRIGHT", -1, 1, 0.5, 1, 0.5, 1 },
}

function T.Round(parent, radius, color, layer, sub, inset, corners)
    inset, layer, sub = inset or 0, layer or "BACKGROUND", sub or 0
    local r = radius
    local s = setmetatable({ round = {}, flat = {} }, Shape)
    for _, c in ipairs(CORNERS) do
        local t = parent:CreateTexture(nil, layer, nil, sub)
        t:SetSize(r, r)
        t:SetPoint(c[1], parent, c[1], c[2] * inset, c[3] * inset)
        if not corners or corners[c[1]] then
            t:SetTexture(T.CIRCLE, nil, nil, "TRILINEAR")
            t:SetTexCoord(c[4], c[5], c[6], c[7])
            s.round[#s.round + 1] = t
        else
            s.flat[#s.flat + 1] = t
        end
    end
    local function Band(p1, x1, y1, p2, x2, y2)
        local t = parent:CreateTexture(nil, layer, nil, sub)
        t:SetPoint("TOPLEFT", parent, p1, x1, y1)
        t:SetPoint("BOTTOMRIGHT", parent, p2, x2, y2)
        s.flat[#s.flat + 1] = t
    end
    Band("TOPLEFT", inset + r, -inset, "BOTTOMRIGHT", -inset - r, inset)          -- middle, full height
    Band("TOPLEFT", inset, -inset - r, "BOTTOMLEFT", inset + r, inset + r)        -- left edge
    Band("TOPRIGHT", -inset - r, -inset - r, "BOTTOMRIGHT", -inset, inset + r)    -- right edge
    s:SetColor(T.RGBA(color))
    return s
end

-- A rounded box with a one-pixel border: the border shape, then the fill one pixel inside it.
-- The fill must be opaque, it is what hides the border shape's middle.
local Box = {}
Box.__index = Box
function Box:SetFill(c) self.fill:SetColor(T.RGBA(c)) end
function Box:SetBorder(c) self.edge:SetColor(T.RGBA(c)) end
function Box:SetShown(on) self.fill:SetShown(on); self.edge:SetShown(on) end

function T.Box(parent, radius, fill, border, layer, sub, corners)
    local px = T.Px(parent)
    sub = sub or 0
    return setmetatable({
        edge = T.Round(parent, radius, border or T.C.border, layer, sub, 0, corners),
        fill = T.Round(parent, math.max(radius - px, 1), fill, layer, sub + 1, px, corners),
    }, Box)
end

--------------------------------------------------------------------------------
-- Board fonts (Board > Display > Font)
--------------------------------------------------------------------------------
T.FONTS = {
    manrope = { "Manrope", MEDIA .. "Fonts\\Manrope-SemiBold.ttf" },
    plexmono = { "IBM Plex Mono", MEDIA .. "Fonts\\IBMPlexMono-Medium.ttf" },
    arialn = { "Arial Narrow", "Fonts\\ARIALN.TTF" },
    friz = { "Friz Quadrata", "Fonts\\FRIZQT__.TTF" },
    morpheus = { "Morpheus", "Fonts\\MORPHEUS.TTF" },
    skurri = { "Skurri", "Fonts\\SKURRI.TTF" },
}
T.FONT_ORDER = { "manrope", "plexmono", "arialn", "friz", "morpheus", "skurri" }
T.FONT_VALUES = {}
for k, f in pairs(T.FONTS) do T.FONT_VALUES[k] = f[1] end

T.ACCENTS = {
    amber = { "Amber", 0.93, 0.64, 0.28 },
    ember = { "Ember", 0.94, 0.38, 0.30 },
    teal = { "Teal", 0.25, 0.78, 0.80 },
    violet = { "Violet", 0.62, 0.50, 0.95 },
    lime = { "Lime", 0.62, 0.86, 0.32 },
    bone = { "Bone", 0.86, 0.83, 0.76 },
}
T.ACCENT_ORDER = { "amber", "ember", "teal", "violet", "lime", "bone" }
T.ACCENT_VALUES = {}
for k, a in pairs(T.ACCENTS) do T.ACCENT_VALUES[k] = a[1] end

function T.FontPath()
    local key = TM.db and TM.db.settings.board.font
    local f = T.FONTS[key] or T.FONTS.manrope
    return f[2]
end

-- Arial Narrow sits small; the others are nudged down to match it.
local SIZE_SCALE = { manrope = 0.98, plexmono = 0.94, arialn = 1.08, friz = 0.92, morpheus = 1.0, skurri = 0.95 }

function T.SetFont(fs, size)
    local key = TM.db and TM.db.settings.board.font or "manrope"
    fs:SetFont(T.FontPath(), math.floor(size * (SIZE_SCALE[key] or 1) + 0.5), "")
end

function T.Font(parent, size, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    T.SetFont(fs, size)
    fs:SetTextColor(1, 1, 1, 0.92)
    fs:SetShadowColor(0, 0, 0, 0.6)
    fs:SetShadowOffset(1, -1)
    fs:SetWordWrap(false)
    return fs
end

function T.Fill(frame, r, g, b, a, layer, sub)
    local tex = frame:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 0)
    tex:SetColorTexture(r, g, b, a or 1)
    return tex
end

local function OnePixel(tex, horizontal)
    if PixelUtil and PixelUtil.SetHeight then
        if horizontal then PixelUtil.SetHeight(tex, 1, 1) else PixelUtil.SetWidth(tex, 1, 1) end
    elseif horizontal then
        tex:SetHeight(1)
    else
        tex:SetWidth(1)
    end
end

-- A 1-pixel rule along one edge of frame.
function T.Line(frame, edge, r, g, b, a, layer)
    local tex = frame:CreateTexture(nil, layer or "BORDER")
    tex:SetColorTexture(r, g, b, a)
    if edge == "TOP" or edge == "BOTTOM" then
        tex:SetPoint(edge .. "LEFT")
        tex:SetPoint(edge .. "RIGHT")
        OnePixel(tex, true)
    else
        tex:SetPoint("TOP" .. edge)
        tex:SetPoint("BOTTOM" .. edge)
        OnePixel(tex, false)
    end
    return tex
end

function T.Border(frame, r, g, b, a)
    local lines = {}
    for i, edge in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do lines[i] = T.Line(frame, edge, r, g, b, a) end
    return lines
end

--------------------------------------------------------------------------------
-- Glyphs: small icons built from rotated line textures, so they take any colour and stay crisp at any scale.
--------------------------------------------------------------------------------
local function Bar(host, len, thick, cx, cy, deg)
    local t = host:CreateTexture(nil, "ARTWORK")
    t:SetColorTexture(1, 1, 1, 1)
    t:SetSize(len, thick)
    t:SetPoint("CENTER", host, "CENTER", cx, cy)
    if deg ~= 0 then t:SetRotation(math.rad(deg)) end
    host.bars[#host.bars + 1] = t
    return t
end

local DIR = { down = 0, right = 90, up = 180, left = -90 }

local function PlaceChevron(g, dir)
    local th = math.rad(DIR[dir] or 0)
    local h = g.size * 0.22
    local arms = { { -h, 0, -45 }, { h, 0, 45 } }
    for i, a in ipairs(arms) do
        local x, y = a[1], a[2]
        local rx, ry = x * math.cos(th) - y * math.sin(th), x * math.sin(th) + y * math.cos(th)
        local bar = g.bars[i]
        bar:ClearAllPoints()
        bar:SetPoint("CENTER", g, "CENTER", rx, ry)
        bar:SetRotation(math.rad(a[3] + (DIR[dir] or 0)))
    end
    g.dir = dir
end

-- kind: "close" (x), "menu" (three lines), "plus", "chevron" (dir: down|up|left|right), "dot".
function T.Glyph(parent, kind, size, dir)
    local g = CreateFrame("Frame", nil, parent)
    g:SetSize(size, size)
    g.size, g.bars = size, {}
    local thick = math.max(size / 9, 1.4)
    if kind == "close" then
        Bar(g, size * 1.1, thick, 0, 0, 45)
        Bar(g, size * 1.1, thick, 0, 0, -45)
    elseif kind == "menu" then
        for i = -1, 1 do Bar(g, size * 0.9, thick, 0, i * size * 0.3, 0) end
    elseif kind == "plus" then
        Bar(g, size * 0.8, thick, 0, 0, 0)
        Bar(g, size * 0.8, thick, 0, 0, 90)
    elseif kind == "chevron" then
        Bar(g, size * 0.62, thick, 0, 0, 0)
        Bar(g, size * 0.62, thick, 0, 0, 0)
        PlaceChevron(g, dir or "down")
        g.SetDir = PlaceChevron
    elseif kind == "dot" then
        local t = g:CreateTexture(nil, "ARTWORK")
        t:SetTexture(T.DISC)
        t:SetAllPoints()
        g.bars[1] = t
    end
    function g:SetColor(r, gg, b, a)
        for _, bar in ipairs(self.bars) do bar:SetVertexColor(r, gg, b, a or 1) end
    end
    g:SetColor(1, 1, 1, 0.55)
    return g
end

-- A glyph button that brightens on hover. tip: string or function(tooltip).
function T.GlyphButton(parent, kind, size, tip, onClick, dir)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size + 8, size + 8)
    b.glyph = T.Glyph(b, kind, size, dir)
    b.glyph:SetPoint("CENTER")
    b.glyph:EnableMouse(false)
    b.alpha = 0.55
    b:SetScript("OnEnter", function(self)
        local r, g, bl = TM.Accent()
        self.glyph:SetColor(r, g, bl, 1)
        if tip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            if type(tip) == "function" then tip(GameTooltip) else GameTooltip:SetText(tip, 1, 1, 1) end
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function(self)
        self.glyph:SetColor(1, 1, 1, self.alpha)
        GameTooltip:Hide()
    end)
    b:SetScript("OnClick", onClick)
    return b
end
