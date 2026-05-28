local ADDON_NAME, NS = ...

NS.Minimap = {}
local M = NS.Minimap

-- Self-contained minimap button. No LibDBIcon dependency — just a button
-- parented to Minimap, positioned by an angle (degrees) saved in
-- uiSettings.minimap = { angle = X, hidden = bool }. Drag to reposition,
-- click to toggle the main grid.

local DEFAULT_ANGLE = 225  -- bottom-left of the minimap by default
local RADIUS = 80          -- distance from minimap center to button center

local function settings()
    local s = NS.DB.GetUISetting("minimap", nil)
    if not s then
        s = { angle = DEFAULT_ANGLE, hidden = false }
        NS.DB.SetUISetting("minimap", s)
    end
    return s
end

local function setPositionFromAngle(button, angle)
    local rad = math.rad(angle)
    local x = math.cos(rad) * RADIUS
    local y = math.sin(rad) * RADIUS
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function angleFromCursor()
    -- Compute angle (degrees) from minimap center to the current cursor
    -- position. Used while the user drags the button around the ring.
    local mx, my = Minimap:GetCenter()
    local scale = Minimap:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    cx, cy = cx / scale, cy / scale
    local dx, dy = cx - mx, cy - my
    if dx == 0 and dy == 0 then return DEFAULT_ANGLE end
    return math.deg(math.atan2(dy, dx))
end

local button
local function build()
    if button then return button end

    local b = CreateFrame("Button", "SeasonalGoalsMinimapButton", Minimap)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:SetSize(32, 32)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")

    -- visual: a class-icon-style circular border with our checkmark glyph
    local icon = b:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture("Interface\\AddOns\\SeasonalGoals\\textures\\checkmark")
    icon:SetSize(18, 18)
    icon:SetPoint("CENTER", b, "CENTER", 0, 1)

    local ring = b:CreateTexture(nil, "OVERLAY")
    ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    ring:SetSize(54, 54)
    ring:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)

    local bg = b:CreateTexture(nil, "BACKGROUND", nil, -1)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetSize(20, 20)
    bg:SetPoint("CENTER", b, "CENTER", 1, 1)

    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    b:GetHighlightTexture():SetSize(32, 32)

    -- Click → toggle main grid (left). Right click → open config.
    b:SetScript("OnClick", function(_, mouseBtn)
        if mouseBtn == "RightButton" then
            NS.UI.ToggleConfig()
        else
            NS.UI.Toggle()
        end
    end)

    -- Drag → reposition around the ring.
    b:SetScript("OnDragStart", function(self)
        self:LockHighlight()
        self:SetScript("OnUpdate", function()
            local a = angleFromCursor()
            settings().angle = a
            setPositionFromAngle(self, a)
        end)
    end)
    b:SetScript("OnDragStop", function(self)
        self:UnlockHighlight()
        self:SetScript("OnUpdate", nil)
    end)

    NS.UI.AttachTooltip(b, function(_, tt)
        tt:SetText("Seasonal Goals")
        tt:AddLine("|cffeda55fLeft-click|r toggle grid", 1, 1, 1)
        tt:AddLine("|cffeda55fRight-click|r open config", 1, 1, 1)
        tt:AddLine("|cffeda55fDrag|r reposition", 1, 1, 1)
    end, "ANCHOR_LEFT")

    button = b
    return b
end

function M.Update()
    local s = settings()
    if s.hidden then
        if button then button:Hide() end
        return
    end
    local b = build()
    setPositionFromAngle(b, s.angle or DEFAULT_ANGLE)
    b:Show()
end

function M.SetHidden(hidden)
    settings().hidden = hidden and true or false
    M.Update()
end

function M.IsHidden()
    return settings().hidden == true
end
