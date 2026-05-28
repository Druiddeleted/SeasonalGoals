local ADDON_NAME, NS = ...

-- Season-scoped cache of "has this visual been collected by any source on the
-- account?" answers, keyed by sourceID.
--
-- Cache state per sourceID:
--   true   = collected; trusted forever within the season (no API call ever).
--   false  = known-missing as of last check; trusted between events.
--   nil    = never checked; will compute and store on next Get/HasVisual.
--
-- When NS.Season.name changes (new tier), the whole cache is wiped.
--
-- Public API:
--   NS.VisualCache.HasVisual(sourceID)        -- bool, may compute+store
--   NS.VisualCache.RecomputeMissing()         -- recheck all `false` entries
--   NS.VisualCache.InvalidateClass(classFile) -- drop entries for a class
--   NS.VisualCache.InvalidateAll()            -- drop everything
--
-- Recompute triggers (wired from core.lua):
--   PLAYER_LOGIN                  -- alt switch
--   TRANSMOG_COLLECTION_UPDATED   -- new appearance unlocked anywhere
--   ITEM_UPGRADE_MASTER_UPDATE    -- rank changed (catalyst input bracket may shift)

NS.VisualCache = {}
local VC = NS.VisualCache

local function ensureShape()
    if not SeasonalGoalsDB then return end
    local cache = SeasonalGoalsDB.visualCache
    local seasonID = NS.Season and NS.Season.name or "unknown"
    if not cache or cache.seasonID ~= seasonID then
        SeasonalGoalsDB.visualCache = { seasonID = seasonID, bySource = {} }
    end
end

-- The actual API call. Walks every source sharing the same visualID and ORs
-- their isCollected fields, matching in-game wardrobe behavior (e.g. a
-- non-tier item that happens to share a tier piece's model counts).
local function computeHasVisual(sourceID)
    if not (C_TransmogCollection and sourceID) then return false end
    local getInfo = C_TransmogCollection.GetAppearanceSourceInfo
    if not getInfo then
        if C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance then
            return C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance(sourceID) or false
        end
        return false
    end

    local primary = getInfo(sourceID)
    local visualID
    if type(primary) == "table" then
        if primary.isCollected then return true end
        visualID = primary.itemAppearanceID
    end
    if not visualID and C_TransmogCollection.GetSourceInfo then
        local s = C_TransmogCollection.GetSourceInfo(sourceID)
        if s then visualID = s.visualID end
    end

    if visualID and C_TransmogCollection.GetAllAppearanceSources then
        local allSources = C_TransmogCollection.GetAllAppearanceSources(visualID)
        if type(allSources) == "table" then
            for _, otherID in ipairs(allSources) do
                if otherID ~= sourceID then
                    local oi = getInfo(otherID)
                    if type(oi) == "table" and oi.isCollected then
                        return true
                    end
                end
            end
        end
    end

    if C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance
        and C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance(sourceID) then
        return true
    end
    return false
end
VC._compute = computeHasVisual  -- exposed for tests / debugging

function VC.HasVisual(sourceID)
    if not sourceID then return false end
    ensureShape()
    local bySource = SeasonalGoalsDB.visualCache.bySource
    local cached = bySource[sourceID]
    if cached ~= nil then return cached end
    local actual = computeHasVisual(sourceID)
    bySource[sourceID] = actual and true or false
    return actual
end

-- Recompute every cached `false` entry. Does NOT touch `true` entries — once
-- collected, always collected within this season. Does NOT touch absent
-- entries (they're populated lazily on read). Called on the invalidation
-- events listed at the top of this file.
function VC.RecomputeMissing()
    ensureShape()
    local bySource = SeasonalGoalsDB.visualCache.bySource
    for sourceID, v in pairs(bySource) do
        if v == false then
            bySource[sourceID] = computeHasVisual(sourceID) and true or false
        end
    end
end

-- Drop every cached entry for sourceIDs belonging to one class. Used by
-- `/sg refresh CLASS` when the user wants to force a clean re-read.
function VC.InvalidateClass(classFile)
    ensureShape()
    local entry = NS.Season and NS.Season.appearances and NS.Season.appearances[classFile]
    if not (entry and entry.bySlot) then return end
    local bySource = SeasonalGoalsDB.visualCache.bySource
    for _, row in pairs(entry.bySlot) do
        for _, sourceID in pairs(row) do
            bySource[sourceID] = nil
        end
    end
end

-- Drop everything. `/sg refresh` with no args.
function VC.InvalidateAll()
    ensureShape()
    SeasonalGoalsDB.visualCache.bySource = {}
end
