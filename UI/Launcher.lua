-- Tallymark launchers: a minimap button, and a LibDataBroker launcher when some other addon has loaded that library.
-- Both: left-click toggles the board, right-click opens the options, hover peeks at the board.
local _, TM = ...
local T = TM.Theme

local L = {}
TM.Launcher = L

local ICON = T.TALLY -- the options header's tally mark, tinted with the accent
local button

local function LS() return TM.db.settings.launcher end

local function Click(_, mouse)
    if mouse == "RightButton" then
        TM.board:Hide()
        TM.OpenOptions()
    else
        TM.board:Toggle()
    end
end

local function Enter(anchor)
    if LS().hoverPeek and not TM.board:IsShown() then
        TM.board:Peek(anchor)
    elseif not TM.board:IsShown() then
        GameTooltip:SetOwner(anchor, "ANCHOR_LEFT")
        GameTooltip:AddLine("Tallymark", 1, 1, 1)
        GameTooltip:AddLine("Left-click: board   Right-click: options", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end
end

local function PlaceButton()
    local angle = math.rad(LS().angle or 205)
    local r = Minimap:GetWidth() / 2 + 8
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
end

-- Built to the stock minimap-button anatomy (31px button, .icon, tracking-border ring, dark disc, zoom highlight)
-- because minimap managers key on exactly that: they find the icon through button.icon, strip the ring and disc by
-- file, and size the row from it. A hand-rolled button with its own fill and edge border got its fill mistaken
-- for the icon and sat out of step with every other button in a managed row.
local function BuildButton()
    button = CreateFrame("Button", "TallymarkMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture(136477) -- Interface\Minimap\UI-Minimap-ZoomButton-Highlight

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture(136430) -- Interface\Minimap\MiniMap-TrackingBorder
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    button.border = border

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetTexture(136467) -- Interface\Minimap\UI-Minimap-Background
    background:SetSize(20, 20)
    background:SetPoint("TOPLEFT", 7, -5)
    button.background = background

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ICON, nil, nil, "TRILINEAR")
    icon:SetSize(17, 17)
    icon:SetPoint("TOPLEFT", 7, -6)
    button.icon = icon

    button:SetScript("OnClick", Click)
    button:SetScript("OnEnter", Enter)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            LS().angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx)) % 360
            PlaceButton()
        end)
    end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    PlaceButton()
end

-- Tints the mark with the accent. Colour only: never re-anchors, so a minimap manager's placement survives.
function L:Paint()
    local r, g, b = TM.Accent()
    if button then button.icon:SetVertexColor(r, g, b, 1) end
    if self.broker then self.broker.iconR, self.broker.iconG, self.broker.iconB = r, g, b end
end

-- Placed once at build; drags move it after that. Re-placing on every toggle would pull the button out of a
-- minimap manager's row.
function L:Apply()
    if LS().minimap then
        if not button then
            BuildButton()
            self:Paint()
        end
        button:Show()
    elseif button then
        button:Hide()
    end
end

function L:Init()
    self:Apply()
    local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
    if LDB and not self.broker then
        self.broker = LDB:NewDataObject("Tallymark", {
            type = "launcher",
            label = "Tallymark",
            icon = ICON,
            iconR = 1, iconG = 1, iconB = 1,
            OnClick = Click,
            OnEnter = Enter,
            OnTooltipShow = function(tt)
                tt:AddLine("Tallymark", 1, 1, 1)
                tt:AddLine("Left-click: board   Right-click: options", 0.7, 0.7, 0.7)
            end,
        })
        self:Paint()
    end
end
