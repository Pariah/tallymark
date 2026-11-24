-- Tallymark launchers: a minimap button, and a LibDataBroker launcher when some other addon has loaded that library.
-- Both: left-click toggles the board, right-click opens the options, hover peeks at the board.
local _, TM = ...
local T = TM.Theme

local L = {}
TM.Launcher = L

local ICON = "Interface\\Icons\\INV_Misc_PocketWatch_01"
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

local function BuildButton()
    button = CreateFrame("Button", "TallymarkMinimapButton", Minimap)
    button:SetSize(26, 26)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    local bg = T.Fill(button, T.BG[1], T.BG[2], T.BG[3], 0.95, "BACKGROUND")
    bg:SetAllPoints()
    T.Border(button, 1, 1, 1, 0.12)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 3, -3)
    icon:SetPoint("BOTTOMRIGHT", -3, 3)
    icon:SetTexture(ICON)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local glow = T.Fill(button, 1, 1, 1, 0.12, "HIGHLIGHT")
    glow:SetAllPoints()

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

function L:Apply()
    if LS().minimap then
        if not button then BuildButton() end
        PlaceButton()
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
            OnClick = Click,
            OnEnter = Enter,
            OnTooltipShow = function(tt)
                tt:AddLine("Tallymark", 1, 1, 1)
                tt:AddLine("Left-click: board   Right-click: options", 0.7, 0.7, 0.7)
            end,
        })
    end
end
