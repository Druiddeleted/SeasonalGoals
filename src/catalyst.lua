local ADDON_NAME, NS = ...

NS.Catalyst = {}
local C = NS.Catalyst

-- ===========================================================================
-- Blizzard rule (not seasonal): which catalyst-input track+rank can produce
-- which difficulty appearances.
--
-- Direct conversion at current rank:
--   Veteran 1-4               -> LFR
--   Veteran 5-6, Champion 1-4 -> Normal
--   Champion 5-6, Hero 1-4    -> Heroic
--   Hero 5-6,    Myth 1-6     -> Mythic
--
-- Upgrade headroom: an item at rank R on track T can be upgraded up to
-- rank 6 on the same track. Items cannot change tracks — a Champion item
-- caps at Champion 6 (Heroic appearance), it does not become a Hero item.
--
-- A given item therefore "contributes" to the union of difficulties it can
-- produce now plus what it could produce after same-track upgrades. The
-- ContributionSet table below is the precomputed answer for every (track,
-- rank) pair — 4 tracks * 6 ranks = 24 entries.
-- ===========================================================================

local TRACK_ORDER = { veteran = 1, champion = 2, hero = 3, myth = 4 }
C.TRACK_ORDER = TRACK_ORDER

local DIFFICULTY_ORDER = { lfr = 1, normal = 2, heroic = 3, myth = 4 }
C.DIFFICULTY_ORDER = DIFFICULTY_ORDER

-- ContributionSet[track][rank] = { lfr=true|nil, normal=..., heroic=..., myth=... }
C.ContributionSet = {
    veteran = {
        [1] = { lfr = true, normal = true },
        [2] = { lfr = true, normal = true },
        [3] = { lfr = true, normal = true },
        [4] = { lfr = true, normal = true },
        [5] = { normal = true },
        [6] = { normal = true },
    },
    champion = {
        [1] = { normal = true, heroic = true },
        [2] = { normal = true, heroic = true },
        [3] = { normal = true, heroic = true },
        [4] = { normal = true, heroic = true },
        [5] = { heroic = true },
        [6] = { heroic = true },
    },
    hero = {
        [1] = { heroic = true, myth = true },
        [2] = { heroic = true, myth = true },
        [3] = { heroic = true, myth = true },
        [4] = { heroic = true, myth = true },
        [5] = { myth = true },
        [6] = { myth = true },
    },
    myth = {
        [1] = { myth = true }, [2] = { myth = true }, [3] = { myth = true },
        [4] = { myth = true }, [5] = { myth = true }, [6] = { myth = true },
    },
}

-- Returns the difficulty (string) an item would catalyze into RIGHT NOW
-- at the given track+rank. Distinct from ContributionSet, which includes
-- same-track upgrade headroom.
function C.DifficultyFor(track, rank)
    if not track or not rank then return nil end
    local t = TRACK_ORDER[track]
    if not t then return nil end
    if t == 1 then return (rank <= 4) and "lfr" or "normal" end
    if t == 2 then return (rank <= 4) and "normal" or "heroic" end
    if t == 3 then return (rank <= 4) and "heroic" or "myth" end
    return "myth"
end

-- Predicate: does this (track, rank) contribute to producing the given
-- difficulty appearance (now or after a same-track upgrade)?
function C.ContributesTo(track, rank, difficulty)
    local row = C.ContributionSet[track]
    if not row then return false end
    local set = row[rank]
    if not set then return false end
    return set[difficulty] == true
end

-- How many ranks short is this item from producing target difficulty on the
-- same track? 0 if already-or-better, nil if track tops out below target.
function C.RanksToReach(track, rank, targetDifficulty)
    local current = C.DifficultyFor(track, rank)
    if not current then return nil end
    if DIFFICULTY_ORDER[current] >= DIFFICULTY_ORDER[targetDifficulty] then
        return 0
    end
    for r = rank + 1, 6 do
        if DIFFICULTY_ORDER[C.DifficultyFor(track, r)] >= DIFFICULTY_ORDER[targetDifficulty] then
            return r - rank
        end
    end
    return nil
end

-- Returns true if every difficulty this (track, rank) could produce for `slot`
-- is already covered by `collectedFor(slot, diff)`. Used to decide whether an
-- item can be pruned from a character's items map.
function C.IsItemRedundant(track, rank, slot, collectedFor)
    local set = C.ContributionSet[track] and C.ContributionSet[track][rank]
    if not set then return true end  -- unknown rank => can't help; safe to drop
    for diff in pairs(set) do
        if not collectedFor(slot, diff) then return false end
    end
    return true
end

-- Walk an items map and drop entries whose contribution set is fully covered
-- by the provided collected-checker. Returns the count of dropped entries.
function C.PruneItems(itemsByGUID, collectedFor)
    if not itemsByGUID then return 0 end
    local dropped = 0
    for guid, item in pairs(itemsByGUID) do
        if item.track and item.rank and item.slot
            and C.IsItemRedundant(item.track, item.rank, item.slot, collectedFor) then
            itemsByGUID[guid] = nil
            dropped = dropped + 1
        end
    end
    return dropped
end

-- ===========================================================================
-- Track + rank parsing from an itemLink. Best-effort tooltip read.
--
-- WoW does not expose track/rank via a typed API. The canonical source is the
-- localized tooltip line that says e.g. "Upgrade Level: Hero 3/6". We read
-- the tooltip via C_TooltipInfo (modern data API; no rendered tooltip needed)
-- and pattern-match against the four track names.
--
-- This works in English locales. For non-EN locales we'd need localized
-- strings; flagging here but not handled yet.
-- ===========================================================================

local TRACK_NAME_TO_KEY = {
    ["Veteran"]  = "veteran",
    ["Champion"] = "champion",
    ["Hero"]     = "hero",
    ["Myth"]     = "myth",
    ["Mythic"]   = "myth",  -- some tooltips
}

function C.ParseTrack(itemLink)
    if not (itemLink and C_TooltipInfo and C_TooltipInfo.GetHyperlink) then
        return nil
    end
    local data = C_TooltipInfo.GetHyperlink(itemLink)
    if not (data and data.lines) then return nil end
    -- C_TooltipInfo returns lazy data; SurfaceArgs populates leftText etc.
    -- Without this, line.leftText is nil and our pattern match never fires.
    if TooltipUtil and TooltipUtil.SurfaceArgs then
        TooltipUtil.SurfaceArgs(data)
    end
    for _, line in ipairs(data.lines) do
        if TooltipUtil and TooltipUtil.SurfaceArgs then
            TooltipUtil.SurfaceArgs(line)
        end
        local text = line.leftText or ""
        -- Match e.g. "Upgrade Level: Hero 3/6", "Track: Champion 2/6", etc.
        local trackName, rank, maxRank = text:match("(%a+)%s+(%d+)%s*/%s*(%d+)")
        if trackName then
            local key = TRACK_NAME_TO_KEY[trackName]
            if key then
                return { track = key, rank = tonumber(rank), maxRank = tonumber(maxRank) }
            end
        end
    end
    return nil
end
