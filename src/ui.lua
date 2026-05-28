local ADDON_NAME, NS = ...

NS.UI = {}
local UI = NS.UI

local CLASS_ORDER = NS.Const.CLASS_ORDER
local CLASS_LABEL = NS.Const.CLASS_LABEL
local SLOT_LABEL  = NS.Const.SLOT_LABEL

-- ===========================================================================
-- State -> color/label. Centralized so a colorblind palette swap later is a
-- single-table change. (a11y placeholder: SeasonalGoalsDB.uiSettings.palette
-- can override these tables in future.)
-- ===========================================================================
-- ---------------------------------------------------------------------------
-- Palette presets. Each palette maps state -> RGB. Picked via the config
-- dropdown; persisted as uiSettings.palette. The "default" entry is the
-- standard green/yellow/orange/red. The others are tuned for the common
-- color-vision-deficiency types based on published colorblind-safe palettes.
--
-- A useful invariant: the textures (white-with-black-outline) already carry
-- the state distinction, so palettes only need to be "different enough to
-- read at a glance", not perfectly disambiguated by hue alone.
-- ---------------------------------------------------------------------------
local PALETTES = {
    default = {
        green   = { 0.20, 0.80, 0.20 },
        yellow  = { 0.95, 0.80, 0.20 },
        orange  = { 0.95, 0.50, 0.10 },
        red     = { 0.75, 0.20, 0.20 },
        none    = { 0.20, 0.20, 0.20 },
    },
    -- Deuteranopia (most common red-green CVD): swap reds/greens for blues
    -- and oranges. Blue = collected, orange = catalyzable now, etc.
    deuteranopia = {
        green   = { 0.20, 0.55, 0.85 },
        yellow  = { 0.95, 0.90, 0.25 },
        orange  = { 0.95, 0.55, 0.10 },
        red     = { 0.50, 0.20, 0.55 },
        none    = { 0.20, 0.20, 0.20 },
    },
    -- Protanopia (red-cone-deficient): similar palette to deuteranopia but
    -- with a different brightness curve so green-like hues stay readable.
    protanopia = {
        green   = { 0.10, 0.50, 0.90 },
        yellow  = { 0.95, 0.90, 0.20 },
        orange  = { 0.95, 0.60, 0.20 },
        red     = { 0.45, 0.10, 0.60 },
        none    = { 0.20, 0.20, 0.20 },
    },
    -- Tritanopia (blue-yellow CVD, rare): keeps reds vs greens but shifts
    -- yellows toward magenta so the yellow/orange band is still distinct.
    tritanopia = {
        green   = { 0.20, 0.80, 0.20 },
        yellow  = { 0.85, 0.45, 0.55 },
        orange  = { 0.95, 0.30, 0.20 },
        red     = { 0.70, 0.10, 0.10 },
        none    = { 0.20, 0.20, 0.20 },
    },
    -- High-contrast monochrome (e.g. printouts, very-low-vision users).
    -- Lean on the texture glyphs for state distinction.
    monochrome = {
        green   = { 0.85, 0.85, 0.85 },
        yellow  = { 0.60, 0.60, 0.60 },
        orange  = { 0.40, 0.40, 0.40 },
        red     = { 0.20, 0.20, 0.20 },
        none    = { 0.10, 0.10, 0.10 },
    },
}
local PALETTE_LABELS = {
    default      = "Default",
    deuteranopia = "Deuteranopia",
    protanopia   = "Protanopia",
    tritanopia   = "Tritanopia",
    monochrome   = "Monochrome",
}
local PALETTE_ORDER = { "default", "deuteranopia", "protanopia", "tritanopia", "monochrome" }

-- STATE_COLOR is read live through this proxy; reassigning state[X] would
-- break the legend's existing references, so we mutate the table in-place
-- whenever the palette changes.
local STATE_COLOR = {}
for k, v in pairs(PALETTES.default) do STATE_COLOR[k] = v end
local STATE_LABEL = {
    green   = "Collected",
    yellow  = "Have item — can catalyze now",
    orange  = "Have item — no catalyst charges",
    red     = "Missing",
    none    = "No data",
}
-- Per-state glyph. All four ship as 32×32 white-with-black-outline TGAs so
-- they share an identical visual treatment.
local STATE_TEXTURE = {
    green  = "Interface\\AddOns\\SeasonalGoals\\textures\\checkmark",
    yellow = "Interface\\AddOns\\SeasonalGoals\\textures\\bang",
    orange = "Interface\\AddOns\\SeasonalGoals\\textures\\bullet",
    red    = "Interface\\AddOns\\SeasonalGoals\\textures\\cross",
}
local LEGEND_ORDER = { "green", "yellow", "orange", "red", "none" }

-- ===========================================================================
-- Layout schema. One place to look up "how big are things, how much padding,
-- which limits the slider obeys" — every pixel constant the UI uses lives
-- here. Per-cell size is read live (LAYOUT.cell.default + user override
-- via slider/resize-grip); everything else is fixed.
-- ===========================================================================
local LAYOUT = {
    cell = {
        default = 32,
        min     = 20,
        max     = 64,
        pad     = 3,        -- gap between grid cells
    },
    grid = {
        rowLabelW  = 80,    -- left strip showing slot names
        colLabelH  = 36,    -- top strip showing class icons
        topPad     = 48,    -- room above the column-header strip
        bottomPad  = 24,    -- room below the bottom row (charges)
    },
    legend = {
        width     = 240,    -- right-side legend column width
        rowGap    = 6,      -- extra gap between legend rows beyond cell pad
        labelPad  = 8,      -- gap between swatch and its label text
    },
}

-- SavedVariables access is owned by NS.DB; ui.lua never touches the raw
-- SeasonalGoalsDB table directly. Local aliases keep call sites short.
local DB = NS.DB
local function getCellSize() return DB.GetUISetting("cellSize", LAYOUT.cell.default) end
local function setCellSize(v) DB.SetUISetting("cellSize", v) end

-- Palette is set by the config dropdown; mutate STATE_COLOR in place so all
-- existing references (legend swatches, cell paint, charges row tooltip text)
-- pick up new colors on the next refresh.
local function applyPalette(name)
    local p = PALETTES[name] or PALETTES.default
    for k, rgb in pairs(p) do STATE_COLOR[k] = rgb end
end
applyPalette(DB.GetUISetting("palette", "default"))

-- ===========================================================================
-- Cell-state computation
-- ===========================================================================
local function GetTargetDifficulty(classFile)
    return DB.GetTargetDifficulty(classFile)
end

local function HasVisual(sourceID)
    return NS.VisualCache and NS.VisualCache.HasVisual(sourceID) or false
end

-- Does this character hold at least one non-excluded item whose contribution
-- set includes (slot, difficulty)?
local function charHasItem(charEntry, slotKey, difficulty)
    for _, item in pairs(charEntry.items or {}) do
        if item.slot == slotKey
            and item.excluded ~= true
            and NS.Catalyst.ContributesTo(item.track, item.rank, difficulty) then
            return true
        end
    end
    return false
end

-- Live currency value for the logged-in character. nil if unavailable.
local function liveCatalystCharges()
    local id = NS.Season and NS.Season.catalystCurrency
    if not id or not (C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo) then return nil end
    local info = C_CurrencyInfo.GetCurrencyInfo(id)
    return info and (info.quantity or 0) or nil
end

-- Use the live value for the currently-logged-in char so we react to spend/
-- earn in real time; use the cached snapshot for everyone else.
local function charHasCharges(charEntry, currentKey, liveCharges)
    if currentKey and charEntry == DB.Characters()[currentKey] and liveCharges then
        return liveCharges > 0
    end
    return (charEntry.catalystCharges or 0) > 0
end

-- Yellow = some char of the class has BOTH an eligible item AND charges.
-- Orange = some char has the item but lacks charges.
-- Both checks are per-character so a different alt's charge count doesn't
-- contaminate the result.
local function ClassCatalyzeState(classFile, slotKey, difficulty)
    if not NS.Catalyst then return "none" end
    local currentKey = DB.CharKey and DB.CharKey() or nil
    local liveCharges = liveCatalystCharges()
    local sawItemNoCharges = false
    for _, charEntry in pairs(DB.Characters()) do
        if charEntry.class == classFile and DB.IsCharacterEnabled(charEntry) then
            if charHasItem(charEntry, slotKey, difficulty) then
                if charHasCharges(charEntry, currentKey, liveCharges) then
                    return "yellow"
                end
                sawItemNoCharges = true
            end
        end
    end
    return sawItemNoCharges and "orange" or "none"
end

local function CellState(classFile, slotKey)
    local target = GetTargetDifficulty(classFile)
    local sourceID = NS.Season and NS.Season.GetAppearance
        and NS.Season.GetAppearance(classFile, slotKey, target)
    if not sourceID then return "none", target, nil end
    if HasVisual(sourceID) then return "green", target, sourceID end
    local cs = ClassCatalyzeState(classFile, slotKey, target)
    if cs == "yellow" then return "yellow", target, sourceID end
    if cs == "orange" then return "orange", target, sourceID end
    return "red", target, sourceID
end

-- ===========================================================================
-- Common helpers
-- ===========================================================================
local CLASS_ICON_TEX = "Interface\\TargetingFrame\\UI-Classes-Circles"
local function classIconCoords(classFile)
    local t = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]
    return t and t[1] or 0, t and t[2] or 1, t and t[3] or 0, t and t[4] or 1
end

local function classEnabled(classFile)
    return DB.IsClassEnabled(classFile)
end

-- Column sort modes. Each key is a UI-selectable option; value is a
-- comparator over classFile strings.
local SORT_LABELS = {
    default      = "Default",
    name_asc     = "Name A→Z",
    name_desc    = "Name Z→A",
    armor_heavy  = "Armor: Plate→Cloth",
    armor_light  = "Armor: Cloth→Plate",
}
local SORT_ORDER_LIST = { "default", "name_asc", "name_desc", "armor_heavy", "armor_light" }
local CLASS_ORDER_INDEX = {}
for i, c in ipairs(CLASS_ORDER) do CLASS_ORDER_INDEX[c] = i end

local SORT_COMPARATORS = {
    default = function(a, b)
        return CLASS_ORDER_INDEX[a] < CLASS_ORDER_INDEX[b]
    end,
    name_asc = function(a, b)
        return CLASS_LABEL[a] < CLASS_LABEL[b]
    end,
    name_desc = function(a, b)
        return CLASS_LABEL[a] > CLASS_LABEL[b]
    end,
    armor_heavy = function(a, b)
        local ar = NS.Const.ARMOR_RANK
        local at = NS.Const.CLASS_ARMOR
        if ar[at[a]] ~= ar[at[b]] then return ar[at[a]] < ar[at[b]] end
        return CLASS_LABEL[a] < CLASS_LABEL[b]
    end,
    armor_light = function(a, b)
        local ar = NS.Const.ARMOR_RANK
        local at = NS.Const.CLASS_ARMOR
        if ar[at[a]] ~= ar[at[b]] then return ar[at[a]] > ar[at[b]] end
        return CLASS_LABEL[a] < CLASS_LABEL[b]
    end,
}

local function getSortMode() return DB.GetUISetting("sortMode", "default") end
local function setSortMode(v) DB.SetUISetting("sortMode", v) end

local function visibleClasses()
    local out = {}
    for _, classFile in ipairs(CLASS_ORDER) do
        if classEnabled(classFile) then table.insert(out, classFile) end
    end
    local cmp = SORT_COMPARATORS[getSortMode()] or SORT_COMPARATORS.default
    table.sort(out, cmp)
    return out
end

-- ===========================================================================
-- StateSwatch: shared component used by both grid cells and legend rows.
-- A swatch is a Button with a colored backdrop, plus two prebuilt overlays
-- (a texture and a fontstring) that get shown one-at-a-time depending on
-- which state is being rendered. Centralizes the visual definition of a
-- "state-colored tile" so grid + legend stay identical.
-- ===========================================================================
local StateSwatch = {}

function StateSwatch.New(parent)
    local sw = CreateFrame("Button", nil, parent, "BackdropTemplate")
    sw:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    sw:SetBackdropBorderColor(0, 0, 0, 0.5)

    local tex = sw:CreateTexture(nil, "OVERLAY")
    tex:SetPoint("CENTER", sw, "CENTER", 0, 0)
    tex:Hide()
    sw.glyphTex = tex
    return sw
end

function StateSwatch.Paint(sw, state)
    local rgb = STATE_COLOR[state] or STATE_COLOR.none
    sw:SetBackdropColor(rgb[1], rgb[2], rgb[3], 0.9)
    local tex = STATE_TEXTURE[state]
    if tex then
        sw.glyphTex:SetTexture(tex)
        sw.glyphTex:Show()
    else
        sw.glyphTex:Hide()
    end
end

function StateSwatch.Resize(sw, size)
    sw:SetSize(size, size)
    sw.glyphTex:SetSize(math.floor(size * 0.75), math.floor(size * 0.75))
end

-- ===========================================================================
-- AttachTooltip: bind an OnEnter/OnLeave pair to a frame that pops the
-- standard GameTooltip. buildFn(self, tt) is called inside OnEnter to fill
-- in title/lines. Centralizes anchor convention + leave-to-hide wiring so
-- every hover in the addon behaves the same.
-- ===========================================================================
function UI.AttachTooltip(frame, buildFn, anchor)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, anchor or "ANCHOR_RIGHT")
        buildFn(self, GameTooltip)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", GameTooltip_Hide)
end

-- ===========================================================================
-- MakeLabel: a positioned FontString. Cuts the
-- `CreateFontString + SetPoint + SetText` 3-line pattern that's repeated
-- ~20 times in the config / detail / grid layouts.
-- ===========================================================================
function UI.MakeLabel(parent, text, template)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormal")
    fs:SetText(text)
    fs:SetJustifyH("LEFT")
    return fs
end

-- ===========================================================================
-- MakeCheckboxRow: standard checkbox + label on one row. Returns the
-- checkbox; the label sits to its right. Useful for config toggles like
-- "Show minimap button" and the per-class enable rows.
-- ===========================================================================
function UI.MakeCheckboxRow(parent, labelText, getter, setter)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    cb:SetChecked(getter())
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    label:SetText(labelText)
    cb.label = label
    cb:SetScript("OnClick", function(self) setter(self:GetChecked() and true or false) end)
    return cb
end

-- ===========================================================================
-- MakeDropdown: standard-styled dropdown menu. `opts` is an array of
-- {value, label} tables; `currentFn` returns the currently-selected value;
-- `onSelect(value)` fires when the user picks. The label of the current
-- entry is highlighted in gold so the user can see the active selection
-- without an empty checkbox column.
-- ===========================================================================
local DROPDOWN_HIGHLIGHT = "|cffffd200"
function UI.MakeDropdown(parent, opts, currentFn, onSelect, width, name)
    local dd = CreateFrame("Frame", name, parent, "UIDropDownMenuTemplate")
    UIDropDownMenu_SetWidth(dd, width or 160)

    local function currentLabel()
        local cv = currentFn()
        for _, o in ipairs(opts) do
            if o.value == cv then return o.label end
        end
        return tostring(cv)
    end
    UIDropDownMenu_SetText(dd, currentLabel())

    UIDropDownMenu_Initialize(dd, function(self, level)
        local cv = currentFn()
        for _, o in ipairs(opts) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = o.label
            info.notCheckable = true
            if o.value == cv then info.colorCode = DROPDOWN_HIGHLIGHT end
            info.func = function()
                onSelect(o.value)
                UIDropDownMenu_SetText(dd, currentLabel())
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    -- expose a refresh hook so callers can sync the visible text after a
    -- programmatic change to the underlying value (e.g. settings imported).
    dd.SeasonalGoalsRefresh = function() UIDropDownMenu_SetText(dd, currentLabel()) end
    return dd
end

-- ===========================================================================
-- Main grid frame
-- ===========================================================================
local frame
local configFrame  -- forward refs
local detailFrame
local relayoutLegend  -- forward decl; defined alongside buildLegend below

-- Window positions persist under uiSettings.windowPositions[name] = {point, x, y, w, h}.
local function savedPosFor(name)
    local all = DB.GetUISetting("windowPositions", nil)
    return all and all[name] or nil
end
local function persistPos(name, point, x, y, w, h)
    local all = DB.GetUISetting("windowPositions", nil) or {}
    all[name] = { point = point, x = x, y = y, w = w, h = h }
    DB.SetUISetting("windowPositions", all)
end

local function makeStandardWindow(name, w, h)
    local f = CreateFrame("Frame", name, UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(w, h)
    -- restore last position/size if we have one
    local saved = name and savedPosFor(name)
    if saved and saved.point then
        f:ClearAllPoints()
        f:SetPoint(saved.point, UIParent, saved.point, saved.x or 0, saved.y or 0)
        if saved.w and saved.h then f:SetSize(saved.w, saved.h) end
    else
        f:SetPoint("CENTER")
    end
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:EnableKeyboard(true)
    f:SetPropagateKeyboardInput(true)
    f:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            self:Hide()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if name then
            local point, _, _, x, y = self:GetPoint()
            persistPos(name, point, x, y, self:GetWidth(), self:GetHeight())
        end
    end)
    f:SetClampedToScreen(true)
    return f
end

-- Layout grid cells from current cell-size + visible class set.
local function relayoutGrid()
    if not frame or not frame.cells then return end
    local CELL = getCellSize()
    local slots = NS.Season.slotKeys
    local classes = visibleClasses()

    -- Column header height scales with cell so big icons aren't cropped.
    local colLabelH = math.max(LAYOUT.grid.colLabelH, CELL + 4)
    local iconSize  = math.max(20, CELL - 4)

    local gridWidth = LAYOUT.grid.rowLabelW + #classes * (CELL + LAYOUT.cell.pad)
    -- Charges row sits flush with the grid using the same row gap (LAYOUT.cell.pad).
    local width  = gridWidth + LAYOUT.legend.width + 24
    local height = LAYOUT.grid.topPad + colLabelH + (#slots + 1) * (CELL + LAYOUT.cell.pad) + 24
    frame:SetSize(width, height)

    -- column headers (class icons), centered above each column at icon size.
    for i, hdr in ipairs(frame.headerIcons or {}) do
        local classFile = classes[i]
        if classFile then
            hdr:Show()
            hdr:ClearAllPoints()
            hdr:SetPoint("TOPLEFT", frame, "TOPLEFT",
                LAYOUT.grid.rowLabelW + (i - 1) * (CELL + LAYOUT.cell.pad) + (CELL - iconSize) / 2,
                -LAYOUT.grid.topPad + 2)
            hdr:SetSize(iconSize, iconSize)
            local l, r, t, b = classIconCoords(classFile)
            hdr.texture:SetTexCoord(l, r, t, b)
            hdr.classFile = classFile
        else
            hdr:Hide()
        end
    end

    -- row labels — same vertical extent as the cell, MIDDLE-justified so
    -- the text centers vertically against the cell regardless of cell size.
    for rIdx, lbl in ipairs(frame.rowLabels or {}) do
        local yTop = -(LAYOUT.grid.topPad + colLabelH + (rIdx - 1) * (CELL + LAYOUT.cell.pad))
        lbl:ClearAllPoints()
        lbl:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, yTop)
        lbl:SetSize(LAYOUT.grid.rowLabelW - 16, CELL)
        lbl:SetJustifyH("LEFT")
        lbl:SetJustifyV("MIDDLE")
    end


    -- cells
    for _, cell in ipairs(frame.cells) do
        local classIdx
        for i, c in ipairs(classes) do
            if c == cell.classFile then classIdx = i; break end
        end
        if classIdx then
            local slotIdx
            for i, s in ipairs(slots) do
                if s == cell.slotKey then slotIdx = i; break end
            end
            local yTop = -(LAYOUT.grid.topPad + colLabelH + (slotIdx - 1) * (CELL + LAYOUT.cell.pad))
            cell:Show()
            cell:ClearAllPoints()
            cell:SetPoint("TOPLEFT", frame, "TOPLEFT",
                LAYOUT.grid.rowLabelW + (classIdx - 1) * (CELL + LAYOUT.cell.pad), yTop)
            StateSwatch.Resize(cell, CELL)
        else
            cell:Hide()
        end
    end

    -- charges row: label on the left, one cell per visible class column.
    -- Numeric values are refreshed by refreshChargesRow() below, which is
    -- also invoked separately on currency events without a full relayout.
    if frame.chargesLabel and frame.chargesCells then
        local chargesY = -(LAYOUT.grid.topPad + colLabelH + #slots * (CELL + LAYOUT.cell.pad))
        frame.chargesLabel:ClearAllPoints()
        frame.chargesLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, chargesY)
        frame.chargesLabel:SetSize(LAYOUT.grid.rowLabelW - 16, CELL)
        frame.chargesLabel:SetJustifyV("MIDDLE")

        for _, btn in ipairs(frame.chargesCells) do
            local classIdx
            for i, c in ipairs(classes) do
                if c == btn.classFile then classIdx = i; break end
            end
            if classIdx then
                btn:Show()
                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", frame, "TOPLEFT",
                    LAYOUT.grid.rowLabelW + (classIdx - 1) * (CELL + LAYOUT.cell.pad), chargesY)
                btn:SetSize(CELL, CELL)
            else
                btn:Hide()
            end
        end
    end

    -- legend on the right side of the grid, swatches sized to match CELL
    if frame.legend then
        frame.legend:ClearAllPoints()
        frame.legend:SetPoint("TOPLEFT", frame, "TOPLEFT", gridWidth + 16, -LAYOUT.grid.topPad)
        relayoutLegend(CELL)
    end
end

-- Update the numeric values + colors of the bottom charges row. Cheap;
-- safe to call on currency ticks without doing a full grid relayout.
local function refreshChargesRow()
    if not frame or not frame.chargesCells then return end
    local currentKey = NS.DB and NS.DB.CharKey and NS.DB.CharKey() or nil
    local liveCharges = liveCatalystCharges()
    local slots = NS.Season.slotKeys
    for _, btn in ipairs(frame.chargesCells) do
        if btn:IsShown() then
            -- If every slot for this class at the current target is already
            -- collected, the charge count is irrelevant — show "—".
            local allOwned = true
            for _, slotKey in ipairs(slots) do
                if CellState(btn.classFile, slotKey) ~= "green" then
                    allOwned = false; break
                end
            end

            if allOwned then
                btn.text:SetText("—")
                btn.text:SetTextColor(0.3, 0.8, 0.3)  -- soft green = nothing to spend on
            else
                local maxN, anyEnabled = 0, false
                for charKey, charEntry in pairs(DB.Characters()) do
                    if charEntry.class == btn.classFile and charEntry.enabled ~= false then
                        anyEnabled = true
                        local n
                        if charKey == currentKey and liveCharges then
                            n = liveCharges
                        else
                            n = charEntry.catalystCharges or 0
                        end
                        if n > maxN then maxN = n end
                    end
                end
                btn.text:SetText(anyEnabled and tostring(maxN) or "—")
                if not anyEnabled then
                    btn.text:SetTextColor(0.5, 0.5, 0.5)
                elseif maxN == 0 then
                    btn.text:SetTextColor(1, 0.5, 0.3)
                else
                    btn.text:SetTextColor(1, 1, 1)
                end
            end
        end
    end
end

local function refreshAllCellColors()
    if not frame or not frame.cells then return end
    if NS.VisualCache and NS.VisualCache.RecomputeMissing then
        NS.VisualCache.RecomputeMissing()
    end
    for _, cell in ipairs(frame.cells) do
        local state = CellState(cell.classFile, cell.slotKey)
        StateSwatch.Paint(cell, state)
    end
    refreshChargesRow()
end

local function buildLegend(parent)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(LAYOUT.legend.width, 200)

    local header = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
    header:SetText("Legend")
    container.header = header

    -- Each legend row reuses the StateSwatch component (same widget that
    -- backs the grid cells), so the legend visuals are guaranteed to match
    -- whatever the grid is showing.
    container.rows = {}
    for _, key in ipairs(LEGEND_ORDER) do
        local sw = StateSwatch.New(container)
        StateSwatch.Paint(sw, key)

        local label = container:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetJustifyH("LEFT")
        label:SetWordWrap(true)
        label:SetText(STATE_LABEL[key])

        table.insert(container.rows, { key = key, sw = sw, label = label })
    end
    return container
end

-- Resize/reposition legend swatches to match the current grid cell size.
-- (Forward-declared near the top of the file so relayoutGrid can call it.)
function relayoutLegend(CELL)
    if not (frame and frame.legend and frame.legend.rows) then return end
    local container = frame.legend
    local rowH = CELL + LAYOUT.legend.rowGap
    container:SetSize(LAYOUT.legend.width, #container.rows * rowH + 32)

    local y = -28  -- header takes up the first 28px
    for _, row in ipairs(container.rows) do
        row.sw:ClearAllPoints()
        row.sw:SetPoint("TOPLEFT", container, "TOPLEFT", 2, y)
        StateSwatch.Resize(row.sw, CELL)

        row.label:ClearAllPoints()
        row.label:SetPoint("LEFT", row.sw, "RIGHT", LAYOUT.legend.labelPad, 0)
        row.label:SetWidth(LAYOUT.legend.width - CELL - LAYOUT.legend.labelPad - 6)

        y = y - rowH
    end
end

-- ===========================================================================
-- Toolbar (top of main frame): Config button.
-- ===========================================================================
local function buildToolbar(parent)
    -- Pin Config button to the inner top-right of the content area, well
    -- above where the class-icon row sits (LAYOUT.grid.topPad).
    local cfg = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    cfg:SetSize(70, 22)
    cfg:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -28, -8)
    cfg:SetText("Config")
    cfg:SetScript("OnClick", function() UI.ToggleConfig() end)
end

-- ===========================================================================
-- Build main grid frame (once).
-- ===========================================================================
local function BuildFrame()
    if frame then return frame end

    local slots = NS.Season.slotKeys
    frame = makeStandardWindow("SeasonalGoalsFrame", 800, 500)
    frame:SetResizable(true)
    if frame.SetResizeBounds then
        frame:SetResizeBounds(420, 280, 1600, 1100)
    end

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.title:SetPoint("TOP", frame.TitleBg, "TOP", 0, -5)
    frame.title:SetText("Seasonal Goals")

    local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    subtitle:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -28)
    local raid = NS.Discover and NS.Discover.CurrentRaidName()
    local seasonName = NS.Season.name or "?"
    -- "<Expansion> Season N — <Raid name>", e.g. "Midnight Season 1 — March on Quel'Danas"
    subtitle:SetText(raid and (seasonName .. " — " .. raid) or seasonName)
    frame.subtitle = subtitle

    buildToolbar(frame)

    -- pre-create header icons for every class slot (toggle hide/show as
    -- visibleClasses changes). Each is a Button so it can be tooltip'd.
    frame.headerIcons = {}
    for i = 1, #CLASS_ORDER do
        local btn = CreateFrame("Button", nil, frame)
        btn:SetSize(28, 28)
        local tex = btn:CreateTexture(nil, "ARTWORK")
        tex:SetTexture(CLASS_ICON_TEX)
        tex:SetAllPoints()
        btn.texture = tex
        UI.AttachTooltip(btn, function(self, tt)
            if not self.classFile then return end
            tt:SetText(CLASS_LABEL[self.classFile])
            local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[self.classFile]
            local target = GetTargetDifficulty(self.classFile)
            if color then
                tt:AddLine(("target: %s"):format(target), color.r, color.g, color.b)
            end
            -- progress summary at target difficulty
            local g, y, o, r = 0, 0, 0, 0
            for _, slotKey in ipairs(NS.Season.slotKeys) do
                local s = CellState(self.classFile, slotKey)
                if s == "green"  then g = g + 1
                elseif s == "yellow" then y = y + 1
                elseif s == "orange" then o = o + 1
                else r = r + 1 end
            end
            local total = #NS.Season.slotKeys
            tt:AddLine(" ")
            tt:AddDoubleLine("Collected",     ("%d / %d"):format(g, total),
                0.7, 0.7, 0.7, 0.3, 1, 0.3)
            if y > 0 then
                tt:AddDoubleLine("Catalyzable now", tostring(y),
                    0.7, 0.7, 0.7, 1, 0.85, 0.3)
            end
            if o > 0 then
                tt:AddDoubleLine("Have item, no charges", tostring(o),
                    0.7, 0.7, 0.7, 1, 0.6, 0.2)
            end
            if r > 0 then
                tt:AddDoubleLine("Missing", tostring(r),
                    0.7, 0.7, 0.7, 1, 0.4, 0.4)
            end
        end, "ANCHOR_BOTTOM")
        frame.headerIcons[i] = btn
    end

    -- row labels
    frame.rowLabels = {}
    for rIdx, slotKey in ipairs(slots) do
        local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetJustifyH("LEFT")
        label:SetText(SLOT_LABEL[slotKey])
        frame.rowLabels[rIdx] = label
    end

    -- "Charges" row label (sits just below the last slot row)
    frame.chargesLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.chargesLabel:SetJustifyH("LEFT")
    frame.chargesLabel:SetText("Charges")

    -- One cell per class showing the catalyst charge count for that class.
    -- Tooltip on hover lists per-character breakdown.
    frame.chargesCells = {}
    for _, classFile in ipairs(CLASS_ORDER) do
        local btn = CreateFrame("Button", nil, frame, "BackdropTemplate")
        btn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        btn:SetBackdropColor(0.10, 0.10, 0.12, 0.7)
        btn:SetBackdropBorderColor(0, 0, 0, 0.5)
        local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        fs:SetAllPoints()
        fs:SetJustifyH("CENTER")
        fs:SetJustifyV("MIDDLE")
        btn.text = fs
        btn.classFile = classFile

        UI.AttachTooltip(btn, function(self, tt)
            tt:SetText(CLASS_LABEL[self.classFile] .. " — catalyst charges")
            local anyChar = false
            local currentKey = DB.CharKey and DB.CharKey() or nil
            local liveCharges = liveCatalystCharges()
            for charKey, charEntry in pairs(DB.Characters()) do
                if charEntry.class == self.classFile then
                    anyChar = true
                    local n
                    if charKey == currentKey and liveCharges then
                        n = liveCharges
                    else
                        n = charEntry.catalystCharges or 0
                    end
                    local label = charKey ..
                        (DB.IsCharacterEnabled(charEntry) and "" or " [disabled]")
                    local r, g, b = 1, 1, 1
                    if n == 0 then r, g, b = 1, 0.5, 0.3 end
                    tt:AddDoubleLine(label, tostring(n), 1, 1, 1, r, g, b)
                end
            end
            if not anyChar then
                tt:AddLine("(no characters tracked)", 0.6, 0.6, 0.6)
            end
        end, "ANCHOR_TOP")
        table.insert(frame.chargesCells, btn)
    end

    -- cells (always create the full 13x9 grid; visibility toggles via relayout)
    frame.cells = {}
    for _, slotKey in ipairs(slots) do
        for _, classFile in ipairs(CLASS_ORDER) do
            local cell = StateSwatch.New(frame)
            cell.classFile = classFile
            cell.slotKey   = slotKey

            UI.AttachTooltip(cell, function(self, tt)
                local s, t, sid = CellState(self.classFile, self.slotKey)
                tt:SetText(CLASS_LABEL[self.classFile])
                tt:AddLine(("%s  (target: %s)"):format(SLOT_LABEL[self.slotKey], t),
                    1, 1, 1)
                local rgb = STATE_COLOR[s]
                tt:AddLine(STATE_LABEL[s] or "?", rgb[1], rgb[2], rgb[3])
                if sid then
                    tt:AddLine(("sourceID: %d"):format(sid), 0.5, 0.5, 0.5)
                end
                if s == "yellow" or s == "orange" then
                    tt:AddLine("Click for details.", 0.6, 0.6, 0.6)
                end
            end)
            cell:SetScript("OnClick", function(self)
                -- Only yellow/orange cells have items worth detailing.
                local s = CellState(self.classFile, self.slotKey)
                if s == "yellow" or s == "orange" then
                    UI.ShowDetail(self.classFile, self.slotKey)
                end
            end)
            table.insert(frame.cells, cell)
        end
    end

    -- legend
    frame.legend = buildLegend(frame)

    -- bottom-right resize grip
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -4, 4)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        -- recompute cell size from available area
        local slots = NS.Season.slotKeys
        local classes = visibleClasses()
        if #classes == 0 or #slots == 0 then return end
        local availW = frame:GetWidth() - LAYOUT.grid.rowLabelW - LAYOUT.legend.width - 24
        -- #slots grid rows + 1 charges row, separated by LAYOUT.cell.pad throughout.
        local availH = frame:GetHeight() - LAYOUT.grid.topPad - LAYOUT.grid.colLabelH - 24
        local newCell = math.floor(math.min(
            (availW - (#classes - 1) * LAYOUT.cell.pad) / #classes,
            (availH - #slots * LAYOUT.cell.pad) / (#slots + 1)
        ))
        newCell = math.max(LAYOUT.cell.min, math.min(LAYOUT.cell.max, newCell))
        setCellSize(newCell)
        relayoutGrid()
        refreshAllCellColors()
        local point, _, _, x, y = frame:GetPoint()
        persistPos("SeasonalGoalsFrame", point, x, y, frame:GetWidth(), frame:GetHeight())
    end)

    relayoutGrid()
    refreshAllCellColors()
    frame:Hide()
    return frame
end

function UI.Refresh()
    refreshAllCellColors()
    -- If the detail panel is open, re-render it so item rows reflect the
    -- latest ranks/inclusion/etc. without the user having to reopen.
    if detailFrame and detailFrame:IsShown()
        and detailFrame.classFile and detailFrame.slotKey then
        UI.ShowDetail(detailFrame.classFile, detailFrame.slotKey)
    end
end

function UI.Relayout()
    if not frame then return end
    relayoutGrid()
    refreshAllCellColors()
end

function UI.Toggle()
    local f = BuildFrame()
    if f:IsShown() then f:Hide() else UI.Refresh(); f:Show() end
end

-- ===========================================================================
-- Scrollable, copyable popup (shared by discover dumps + debug commands).
-- ===========================================================================
local dumpFrame
function UI.ShowDump(title, text)
    if not dumpFrame then
        local f = makeStandardWindow("SeasonalGoalsDumpFrame", 700, 500)
        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        f.title:SetPoint("TOP", f.TitleBg, "TOP", 0, -5)
        local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 10, -30)
        sf:SetPoint("BOTTOMRIGHT", -30, 10)
        local eb = CreateFrame("EditBox", nil, sf)
        eb:SetMultiLine(true)
        eb:SetFontObject(ChatFontNormal)
        eb:SetWidth(640)
        eb:SetAutoFocus(false)
        eb:SetScript("OnEscapePressed", function() f:Hide() end)
        sf:SetScrollChild(eb)
        f.editBox = eb
        dumpFrame = f
    end
    dumpFrame.title:SetText("Seasonal Goals — " .. title)
    dumpFrame.editBox:SetText(text)
    dumpFrame.editBox:HighlightText()
    dumpFrame.editBox:SetFocus()
    dumpFrame:Show()
    dumpFrame:Raise()
end

-- ===========================================================================
-- Config window — per-class enable, per-class target difficulty, cell size.
-- Stub for now; checkboxes wired but layout is minimal.
-- ===========================================================================
local DIFF_CHOICES = { "lfr", "normal", "heroic", "myth" }

local function buildConfig()
    if configFrame then return configFrame end
    local f = makeStandardWindow("SeasonalGoalsConfigFrame", 460, 600)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.title:SetPoint("TOP", f.TitleBg, "TOP", 0, -5)
    f.title:SetText("Seasonal Goals — Config")

    -- Cell size slider
    local slider = CreateFrame("Slider", "SeasonalGoalsCellSizeSlider", f,
        "OptionsSliderTemplate")
    slider:SetPoint("TOP", f, "TOP", 0, -44)
    slider:SetWidth(360)
    slider:SetMinMaxValues(LAYOUT.cell.min, LAYOUT.cell.max)
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)
    slider:SetValue(getCellSize())
    _G[slider:GetName() .. "Low"]:SetText(tostring(LAYOUT.cell.min))
    _G[slider:GetName() .. "High"]:SetText(tostring(LAYOUT.cell.max))
    _G[slider:GetName() .. "Text"]:SetText("Cell size: " .. getCellSize())
    slider:SetScript("OnValueChanged", function(self, v)
        local sz = math.floor(v + 0.5)
        setCellSize(sz)
        _G[self:GetName() .. "Text"]:SetText("Cell size: " .. sz)
        if frame then relayoutGrid(); refreshAllCellColors() end
    end)

    -- Palette dropdown (a11y / colorblind presets)
    local paletteLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    paletteLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -96)
    paletteLabel:SetText("Palette")

    local paletteOpts = {}
    for _, p in ipairs(PALETTE_ORDER) do
        table.insert(paletteOpts, { value = p, label = PALETTE_LABELS[p] })
    end
    local paletteDD = UI.MakeDropdown(f, paletteOpts,
        function() return DB.GetUISetting("palette", "default") end,
        function(p)
            DB.SetUISetting("palette", p)
            applyPalette(p)
            if frame then refreshAllCellColors() end
        end, 160, "SeasonalGoalsPaletteDropDown")
    paletteDD:SetPoint("TOPLEFT", paletteLabel, "BOTTOMLEFT", -22, -2)

    -- Minimap button visibility
    local mmCB = UI.MakeCheckboxRow(f, "Show minimap button",
        function() return NS.Minimap and not NS.Minimap.IsHidden() end,
        function(on) if NS.Minimap then NS.Minimap.SetHidden(not on) end end)
    mmCB:SetPoint("TOPLEFT", f, "TOPLEFT", 220, -88)

    -- Column sort dropdown
    local sortLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sortLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -158)
    sortLabel:SetText("Column order")

    local sortOpts = {}
    for _, mode in ipairs(SORT_ORDER_LIST) do
        table.insert(sortOpts, { value = mode, label = SORT_LABELS[mode] })
    end
    local sortDD = UI.MakeDropdown(f, sortOpts, getSortMode, function(mode)
        setSortMode(mode)
        if frame then relayoutGrid(); refreshAllCellColors() end
    end, 160, "SeasonalGoalsSortDropDown")
    sortDD:SetPoint("TOPLEFT", sortLabel, "BOTTOMLEFT", -22, -2)

    -- Per-class enable + target difficulty rows. The label sits to the
    -- right of the icon; the standard MakeCheckboxRow helper handles the
    -- checkbox+text pair, so we insert the icon between them manually.
    local diffOpts = {}
    for _, diff in ipairs(DIFF_CHOICES) do
        table.insert(diffOpts, { value = diff, label = diff })
    end
    local rowY = -222
    for _, classFile in ipairs(CLASS_ORDER) do
        local cb = UI.MakeCheckboxRow(f, "",
            function() return classEnabled(classFile) end,
            function(on)
                DB.SetClassEnabled(classFile, on)
                if frame then relayoutGrid(); refreshAllCellColors() end
            end)
        cb:SetPoint("TOPLEFT", f, "TOPLEFT", 16, rowY)

        local icon = f:CreateTexture(nil, "ARTWORK")
        icon:SetTexture(CLASS_ICON_TEX)
        local l, r, t, b = classIconCoords(classFile)
        icon:SetTexCoord(l, r, t, b)
        icon:SetSize(20, 20)
        icon:SetPoint("LEFT", cb, "RIGHT", 6, 0)

        cb.label:ClearAllPoints()
        cb.label:SetPoint("LEFT", icon, "RIGHT", 6, 0)
        cb.label:SetText(CLASS_LABEL[classFile])
        local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
        if color then cb.label:SetTextColor(color.r, color.g, color.b) end

        local dd = UI.MakeDropdown(f, diffOpts,
            function() return GetTargetDifficulty(classFile) end,
            function(diff)
                DB.SetTargetDifficulty(classFile, diff)
                refreshAllCellColors()
            end, 80)
        dd:SetPoint("LEFT", cb.label, "LEFT", 130, -3)

        rowY = rowY - 26
    end

    configFrame = f
    f:Hide()
    return f
end

function UI.ToggleConfig()
    local f = buildConfig()
    if f:IsShown() then f:Hide() else f:Show(); f:Raise() end
end

-- ===========================================================================
-- Detail panel — per-character item breakdown on cell click.
-- Lists each enabled char of the class, their items in this slot, what diff
-- each item could catalyze to, and an exclude/include toggle.
-- ===========================================================================
local function buildDetail()
    if detailFrame then return detailFrame end
    local f = makeStandardWindow("SeasonalGoalsDetailFrame", 520, 440)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.title:SetPoint("TOP", f.TitleBg, "TOP", 0, -5)

    local subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    subtitle:SetPoint("TOPLEFT", 14, -28)
    f.subtitle = subtitle

    local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 10, -54)
    sf:SetPoint("BOTTOMRIGHT", -30, 10)
    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(480, 400)
    sf:SetScrollChild(content)
    f.scrollChild = content
    detailFrame = f
    f:Hide()
    return f
end

-- Layout constants for the detail panel rows.
local DETAIL_ROW_H    = 38
local DETAIL_ICON_W   = 32
local DETAIL_HDR_H    = 22
local DETAIL_BTN_W    = 78

local function makeItemRow(parent, item, target, onToggle)
    local row = CreateFrame("Frame", nil, parent)
    -- Width leaves clearance for the scroll-frame's scrollbar so the
    -- include-checkbox on the right edge doesn't get clipped/overlapped.
    row:SetSize(440, DETAIL_ROW_H)

    -- Icon button with full-tooltip on hover.
    local iconBtn = CreateFrame("Button", nil, row)
    iconBtn:SetPoint("LEFT", row, "LEFT", 0, 0)
    iconBtn:SetSize(DETAIL_ICON_W, DETAIL_ICON_W)
    local tex = iconBtn:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)  -- crop icon border
    iconBtn:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    iconBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    local border = iconBtn:CreateTexture(nil, "OVERLAY")
    border:SetPoint("CENTER")
    border:SetSize(DETAIL_ICON_W + 4, DETAIL_ICON_W + 4)
    border:SetTexture("Interface\\Buttons\\UI-Quickslot2")

    -- Pull name + icon + quality from itemLink. May trickle in async if the
    -- item isn't cached yet; the row will look bare for a frame in that case.
    local link = item.itemLink
    local name, _, quality, _, _, _, _, _, _, icon
    if link then
        name, _, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(link)
    end
    if not icon and item.itemID then
        icon = C_Item.GetItemIconByID and C_Item.GetItemIconByID(item.itemID) or nil
    end
    tex:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")

    UI.AttachTooltip(iconBtn, function(self, tt)
        if link then
            tt:SetHyperlink(link)
        elseif item.itemID then
            tt:SetItemByID(item.itemID)
        end
    end)
    iconBtn:SetScript("OnClick", function()
        if link and IsShiftKeyDown() and ChatEdit_InsertLink then
            ChatEdit_InsertLink(link)
        end
    end)

    -- Name (quality-colored)
    local nameFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    nameFS:SetPoint("TOPLEFT", iconBtn, "TOPRIGHT", 8, -2)
    nameFS:SetJustifyH("LEFT")
    nameFS:SetWidth(240)  -- shorter to leave room for the checkbox column
    nameFS:SetText(name or ("itemID " .. tostring(item.itemID)))
    if quality then
        local r, g, b = GetItemQualityColor(quality)
        if r then nameFS:SetTextColor(r, g, b) end
    end

    -- Track + rank, plus reach hint
    local ranksNeeded = NS.Catalyst.RanksToReach(item.track, item.rank, target)
    local reach
    if ranksNeeded == 0 then
        reach = "would catalyze to " .. target
    elseif ranksNeeded then
        reach = ("needs +%d ranks for %s"):format(ranksNeeded, target)
    else
        reach = "track tops out below " .. target
    end
    local subFS = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    subFS:SetPoint("TOPLEFT", nameFS, "BOTTOMLEFT", 0, -2)
    subFS:SetText(("%s %d/%d  —  %s"):format(
        item.track or "?", item.rank or 0, item.maxRank or 6, reach))

    -- "Included" checkbox — checked = counts toward catalyze state,
    -- unchecked = excluded. The whole row dims when excluded so it reads
    -- as inactive at a glance.
    local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    cb:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    cb:SetSize(24, 24)
    local cbLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cbLabel:SetPoint("RIGHT", cb, "LEFT", -2, 0)
    cbLabel:SetText("Include")

    local function syncRow()
        cb:SetChecked(not item.excluded)
        local a = item.excluded and 0.4 or 1.0
        nameFS:SetAlpha(a)
        subFS:SetAlpha(a)
        tex:SetAlpha(a)
        cbLabel:SetAlpha(item.excluded and 0.6 or 1.0)
    end
    syncRow()
    cb:SetScript("OnClick", function(self)
        item.excluded = not self:GetChecked()
        syncRow()
        if onToggle then onToggle() end
    end)

    return row
end

function UI.ShowDetail(classFile, slotKey)
    local f = buildDetail()
    -- Remember what's being viewed so refresh events can re-render the same
    -- detail in place (e.g. after a rank-up changes a row's "needs +N").
    f.classFile = classFile
    f.slotKey   = slotKey
    f.title:SetText(("%s — %s"):format(CLASS_LABEL[classFile], SLOT_LABEL[slotKey]))
    local target = GetTargetDifficulty(classFile)
    local state, _, sid = CellState(classFile, slotKey)
    f.subtitle:SetText(("Target: %s    State: %s    sourceID: %s"):format(
        target, STATE_LABEL[state], tostring(sid)))

    -- Wipe previous children. Recreating per show keeps the layout code
    -- simple — the detail panel isn't reopened rapidly enough to need pooling.
    if f.scrollChild.kids then
        for _, k in ipairs(f.scrollChild.kids) do k:Hide(); k:SetParent(nil) end
    end
    f.scrollChild.kids = {}

    local y = -4
    local function place(child, height)
        child:ClearAllPoints()
        child:SetPoint("TOPLEFT", f.scrollChild, "TOPLEFT", 8, y)
        table.insert(f.scrollChild.kids, child)
        y = y - (height or 16)
    end
    local function header(text, color)
        local fs = f.scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetText(text)
        if color then fs:SetTextColor(color[1], color[2], color[3]) end
        place(fs, DETAIL_HDR_H)
        return fs
    end
    local function note(text, color)
        local fs = f.scrollChild:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        fs:SetText(text)
        if color then fs:SetTextColor(color[1], color[2], color[3]) end
        place(fs, 16)
        return fs
    end

    local foundClass = false
    for charKey, charEntry in pairs(DB.Characters()) do
        if charEntry.class == classFile then
            foundClass = true
            local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
            local enabledLabel = (charEntry.enabled == false) and "  [disabled]" or ""
            header(charKey .. enabledLabel,
                color and { color.r, color.g, color.b } or nil)

            local anyItems = false
            for _, item in pairs(charEntry.items or {}) do
                -- only items that can actually contribute to the target
                -- difficulty (either via direct catalysis or same-track
                -- upgrades). Items on tracks that top out below target are
                -- not actionable, so don't clutter the list with them.
                if item.slot == slotKey
                    and NS.Catalyst.ContributesTo(item.track, item.rank, target) then
                    anyItems = true
                    local row = makeItemRow(f.scrollChild, item, target,
                        refreshAllCellColors)
                    place(row, DETAIL_ROW_H + 2)
                end
            end
            if not anyItems then
                note("    (no items in this slot)", { 0.5, 0.5, 0.5 })
            end
            y = y - 6
        end
    end
    if not foundClass then
        note("No characters tracked for this class yet. Log in on one to populate.",
            { 0.7, 0.7, 0.7 })
    end

    f.scrollChild:SetHeight(math.max(400, -y + 16))
    -- Show + Raise: forces the detail frame to the top of its strata even
    -- when it was already visible behind the main grid (clicking the main
    -- grid raises it above same-strata siblings; we need to undo that).
    f:Show()
    f:Raise()
end
