local ADDON_NAME, NS = ...

NS.Scanner = {}
local S = NS.Scanner

-- ===========================================================================
-- Per-character bag + equipment scan.
--
-- For every catalyst-eligible item (one whose inventory slot is a tier slot
-- and which can be parsed as belonging to a current-track item like
-- Veteran/Champion/Hero/Myth), we record:
--   items[itemGUID] = { itemID, slot, track, rank, excluded }
--
-- The map lives at SeasonalGoalsDB.characters[CharKey].items.
--
-- Only the *currently logged-in character* writes to its own slot. Other
-- characters' data persists from when they were last logged in.
-- ===========================================================================

local INVTYPE_TO_SLOT = NS.Const.INVTYPE_TO_SLOT
local EQUIP_SLOT_IDS  = NS.Const.EQUIP_SLOT_IDS

-- Stub kept for backward-compat. Cache refresh is owned by the coalesced
-- refreshVisualsAndUI in core.lua now, so this is a no-op — calling it
-- doesn't hurt, but core.lua no longer needs to.
function S.RefreshCollectedAppearances()
end

-- Tooltip-parse cache. Track/rank parsing via C_TooltipInfo is the most
-- expensive part of a scan; the same itemLink can be re-seen many times
-- per session (rescan on every bag update). Keyed by itemLink — since the
-- link includes upgrade bonus IDs, the key invalidates automatically when
-- the item is upgraded.
local parseCache = {}

-- Convert one ItemLocation into an items-map entry, or nil if the item isn't
-- tier-eligible (wrong slot, no track info, etc.). Returns (entry, key).
local function buildItemEntry(itemLocation)
    if not (itemLocation and C_Item.DoesItemExist(itemLocation)) then return nil end
    local itemLink = C_Item.GetItemLink(itemLocation)
    if not itemLink then return nil end
    local _, _, _, _, _, _, _, _, equipLoc = C_Item.GetItemInfo(itemLink)
    local slot = INVTYPE_TO_SLOT[equipLoc or ""]
    if not slot then return nil end

    local track = parseCache[itemLink]
    if track == nil then
        track = NS.Catalyst.ParseTrack(itemLink) or false  -- false = parsed-and-nil
        parseCache[itemLink] = track
    end
    if not track then return nil end

    local itemID = C_Item.GetItemID and C_Item.GetItemID(itemLocation) or nil
    local guid   = C_Item.GetItemGUID and C_Item.GetItemGUID(itemLocation) or itemLink

    -- Store the full itemLink so the detail panel can render the proper
    -- icon, quality-colored name, and full tooltip (with enchants/gems)
    -- even from characters that aren't currently logged in.
    return {
        itemID   = itemID,
        itemLink = itemLink,
        slot     = slot,
        track    = track.track,
        rank     = track.rank,
        maxRank  = track.maxRank,
        excluded = false,
    }, guid
end

-- Walk equipped slots + every bag, build the up-to-date items table.
function S.RescanCurrentCharacter()
    if not (NS.DB and NS.DB.CurrentCharacter) then return end
    local entry = NS.DB.CurrentCharacter()
    if not entry then return end
    entry.lastSeen = time()

    -- Preserve per-item user state (excluded flag) across rescans by keying
    -- off GUID and copying the flag forward when we re-see the same item.
    local prev = entry.items or {}
    local fresh = {}

    local function ingest(itemLocation)
        local built, key = buildItemEntry(itemLocation)
        if not built then return end
        local before = prev[key]
        if before then built.excluded = before.excluded end
        fresh[key] = built
    end

    for _, slotID in ipairs(EQUIP_SLOT_IDS) do
        ingest(ItemLocation:CreateFromEquipmentSlot(slotID))
    end

    local lastBag = (NUM_BAG_SLOTS or 4)
    for bag = 0, lastBag do
        local size = C_Container.GetContainerNumSlots(bag) or 0
        for s = 1, size do
            ingest(ItemLocation:CreateFromBagAndSlot(bag, s))
        end
    end

    entry.items = fresh

    -- Snapshot the player's catalyst charge count too, so the grid can show
    -- the right yellow/orange state for this character even when a different
    -- alt is logged in. nil = unknown (treat as "have it" upstream).
    local cid = NS.Season and NS.Season.catalystCurrency
    if cid and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        local info = C_CurrencyInfo.GetCurrencyInfo(cid)
        entry.catalystCharges = info and info.quantity or 0
    end
end

-- /sg debug items: rich diagnostic walk. Logs every item link in equipped
-- slots + bags, what equipLoc was returned, what (if any) track was parsed,
-- and why each item was accepted/rejected. Result is rendered to the shared
-- popup AND written to SeasonalGoalsDB._debugItems so it can be read off
-- disk after /reload.
function S.DumpDiagnostics()
    local lines = {}
    table.insert(lines, ("character: %s  class: %s"):format(
        UnitName("player") or "?", select(2, UnitClass("player")) or "?"))
    table.insert(lines, "")
    table.insert(lines, "EQUIPPED")
    table.insert(lines, "------")
    local function describe(itemLocation, where)
        if not (itemLocation and C_Item.DoesItemExist(itemLocation)) then
            return  -- skip empty slots silently
        end
        local itemLink = C_Item.GetItemLink(itemLocation)
        if not itemLink then return end
        local name, _, _, _, _, _, _, _, equipLoc = C_Item.GetItemInfo(itemLink)
        local slot = INVTYPE_TO_SLOT[equipLoc or ""]
        local track = NS.Catalyst.ParseTrack(itemLink)
        local fate
        if not slot then
            fate = "skip: not a tier slot (equipLoc=" .. tostring(equipLoc) .. ")"
        elseif not track then
            fate = "skip: no track parsed"
        else
            fate = ("ACCEPT slot=%s track=%s rank=%d/%d"):format(
                slot, track.track, track.rank or 0, track.maxRank or 0)
        end
        table.insert(lines, ("  %s: %s   [%s]"):format(where, name or itemLink, fate))
    end
    for _, slotID in ipairs(EQUIP_SLOT_IDS) do
        describe(ItemLocation:CreateFromEquipmentSlot(slotID), "slot" .. slotID)
    end
    table.insert(lines, "")
    table.insert(lines, "BAGS")
    table.insert(lines, "----")
    local lastBag = (NUM_BAG_SLOTS or 4)
    for bag = 0, lastBag do
        local size = C_Container.GetContainerNumSlots(bag) or 0
        for slotIdx = 1, size do
            describe(ItemLocation:CreateFromBagAndSlot(bag, slotIdx),
                ("bag%d.%d"):format(bag, slotIdx))
        end
    end
    table.insert(lines, "")
    table.insert(lines, "CAPTURED ITEMS (after rescan)")
    table.insert(lines, "----------------------------")
    S.RescanCurrentCharacter()
    local entry = NS.DB.CurrentCharacter()
    local count = 0
    for guid, item in pairs(entry and entry.items or {}) do
        count = count + 1
        table.insert(lines, ("  %s  %s %d/%d  itemID=%s  guid=%s%s"):format(
            item.slot, item.track or "?", item.rank or 0, item.maxRank or 6,
            tostring(item.itemID), tostring(guid),
            item.excluded and "  [excluded]" or ""))
    end
    if count == 0 then
        table.insert(lines, "  (none)")
    end

    local out = table.concat(lines, "\n")
    SeasonalGoalsDB._debugItems = out  -- written to disk on /reload or logout
    if NS.UI and NS.UI.ShowDump then
        NS.UI.ShowDump("debug items", out)
    end
end
