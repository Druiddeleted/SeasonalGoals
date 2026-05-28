local ADDON_NAME, NS = ...

NS.Discover = {}
local D = NS.Discover

-- Sub-commands:
--   /sg discover            -- shorthand for `sets`
--   /sg discover sets       -- list candidate tier sets for current class
--   /sg discover set <id>   -- dump every source on that setID
--   /sg discover variants <id>  -- dump appearance variants for that setID
--   /sg discover season     -- auto-detect + compile current-season tier
--                              set for the player's class
--   /sg discover all        -- like `season`, but for every class in one go
--   /sg discover compile lfr=<id> normal=<id> heroic=<id> myth=<id>
--                           -- manual fallback when auto-detect picks wrong.
--   /sg discover currency <id>  -- print info for a currency ID (catalyst)

local DIFF_BY_DESCRIPTION = NS.Const.DIFF_BY_DESCRIPTION

local INVTYPE_TO_SLOT   = NS.Const.INVTYPE_TO_SLOT
local INVTYPE_NAME      = NS.Const.INVTYPE_NAME
local CATEGORY_TO_SLOT  = NS.Const.CATEGORY_TO_SLOT
local CATEGORY_NAME     = NS.Const.CATEGORY_NAME
local CLASS_FILE_BY_ID  = NS.Const.CLASS_FILE_BY_ID

local function PlayerClassID()
    return select(3, UnitClass("player"))
end

local function PlayerClassMaskBit()
    local id = PlayerClassID()
    if not id then return 0 end
    return bit.lshift(1, id - 1)
end

local function CurrentExpansionID()
    if GetExpansionLevel then return GetExpansionLevel() end
    return nil
end

-- Encounter Journal lookup for the most recent raid name (e.g. "The Voidspire").
-- Returns nil if EJ data isn't available yet. Cached into SeasonalGoalsDB so
-- the UI can show it on fresh logins before any /sg discover is run.
function D.CurrentRaidName()
    if not (EJ_GetNumTiers and EJ_SelectTier and EJ_GetInstanceByIndex) then
        return SeasonalGoalsDB and SeasonalGoalsDB.detectedRaidName
    end
    local prevTier = (EJ_GetCurrentTier and EJ_GetCurrentTier()) or nil
    local tierCount = EJ_GetNumTiers()
    EJ_SelectTier(tierCount)
    local lastName
    local i = 1
    while true do
        local instanceID, name = EJ_GetInstanceByIndex(i, true)
        if not instanceID then break end
        lastName = name
        i = i + 1
    end
    if prevTier then EJ_SelectTier(prevTier) end
    if lastName and SeasonalGoalsDB then
        SeasonalGoalsDB.detectedRaidName = lastName
    end
    return lastName or (SeasonalGoalsDB and SeasonalGoalsDB.detectedRaidName)
end

-- Shared dialog lives in ui.lua so /sg debug commands can use it too.
local function ShowDump(title, text)
    if NS.UI and NS.UI.ShowDump then
        NS.UI.ShowDump(title, text)
    end
end

local function escapeStr(s)
    if not s then return "nil" end
    return ("%q"):format(s):gsub("\\\n", "\\n")
end

-------------------------------------------------------------------------------
-- /sg discover sets
-------------------------------------------------------------------------------
local function DiscoverSets()
    if not C_TransmogSets or not C_TransmogSets.GetAllSets then
        print("|cffff5555[SeasonalGoals]|r C_TransmogSets.GetAllSets is unavailable.")
        return
    end
    local sets = C_TransmogSets.GetAllSets() or {}
    local classBit = PlayerClassMaskBit()
    local currentExp = CurrentExpansionID()

    -- Match by class first; then sort by expansionID desc so the current
    -- season's set shows at the top. We don't filter strictly to current
    -- expansion because the data model might surprise us.
    local matches = {}
    for _, s in ipairs(sets) do
        if s.classMask and bit.band(s.classMask, classBit) ~= 0 then
            table.insert(matches, s)
        end
    end
    table.sort(matches, function(a, b)
        if (a.expansionID or 0) ~= (b.expansionID or 0) then
            return (a.expansionID or 0) > (b.expansionID or 0)
        end
        if (a.patchID or 0) ~= (b.patchID or 0) then
            return (a.patchID or 0) > (b.patchID or 0)
        end
        return (a.setID or 0) > (b.setID or 0)
    end)

    local lines = {}
    table.insert(lines, ("-- player class: %s   current expansion: %s")
        :format(CLASS_FILE_BY_ID[PlayerClassID()] or "?", tostring(currentExp)))
    table.insert(lines, ("-- %d transmog sets match this class"):format(#matches))
    table.insert(lines, "")
    table.insert(lines, "setID  | exp | patch | name (description)")
    table.insert(lines, "-------+-----+-------+--------------------")
    for _, s in ipairs(matches) do
        table.insert(lines, ("%-6d | %3s | %-5s | %s%s"):format(
            s.setID or 0,
            tostring(s.expansionID or "?"),
            tostring(s.patchID or "?"),
            s.name or "?",
            s.description and ("  (" .. s.description .. ")") or ""))
    end
    table.insert(lines, "")
    table.insert(lines, "Next step:")
    table.insert(lines, "  /sg discover set <setID>      -- show sources for one set")
    table.insert(lines, "  /sg discover variants <setID> -- show other-difficulty variants")
    table.insert(lines, "  /sg discover compile lfr=A normal=B heroic=C myth=D")

    ShowDump("transmog sets for your class", table.concat(lines, "\n"))
end

-------------------------------------------------------------------------------
-- /sg discover set <id>
-------------------------------------------------------------------------------
local function DiscoverSet(setIDStr)
    local setID = tonumber(setIDStr)
    if not setID then
        print("|cffff5555[SeasonalGoals]|r usage: /sg discover set <setID>")
        return
    end

    -- collect sources via every API path we know about so we can compare
    local fromAll   = C_TransmogSets.GetAllSourceIDs       and C_TransmogSets.GetAllSourceIDs(setID) or {}
    local fromMap   = C_TransmogSets.GetSetSources         and C_TransmogSets.GetSetSources(setID) or {}
    local fromPrim  = C_TransmogSets.GetSetPrimaryAppearances and C_TransmogSets.GetSetPrimaryAppearances(setID) or {}

    local seen = {}
    local function add(id) if id and not seen[id] then seen[id] = true end end
    for _, id in ipairs(fromAll) do add(id) end
    for id in pairs(fromMap) do add(id) end
    for _, e in ipairs(fromPrim) do add(e.appearanceID or e.sourceID) end

    local lines = {}
    table.insert(lines, ("-- setID %d"):format(setID))
    table.insert(lines, ("  GetAllSourceIDs:        %d entries"):format(#fromAll))
    local mapCount = 0; for _ in pairs(fromMap) do mapCount = mapCount + 1 end
    table.insert(lines, ("  GetSetSources:          %d entries"):format(mapCount))
    table.insert(lines, ("  GetSetPrimaryAppearances: %d entries"):format(#fromPrim))
    table.insert(lines, "")
    table.insert(lines, "sourceID | itemID  | invType (#) | slot   | have? | name")
    table.insert(lines, "---------+---------+-------------+--------+-------+----------------")
    for sourceID in pairs(seen) do
        local info = C_TransmogCollection.GetSourceInfo(sourceID)
        if info then
            local iv = info.invType
            local ivName = (type(iv) == "number" and INVTYPE_NAME[iv]) or tostring(iv)
            local slotKey = INVTYPE_TO_SLOT[iv or ""] or "-"
            local have = C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance
                and C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance(sourceID)
            table.insert(lines, ("%-8d | %-7s | %-11s | %-6s | %-5s | %s"):format(
                sourceID,
                tostring(info.itemID or "?"),
                ("%s (%s)"):format(ivName, tostring(iv)),
                slotKey,
                have and "YES" or "no",
                info.name or "?"))
        else
            table.insert(lines, ("%-8d | (no GetSourceInfo data)"):format(sourceID))
        end
    end

    -- raw dump of a single GetSourceInfo result so we can see ALL field
    -- names this client returns (we want to know if "invType" is really
    -- Enum.InventoryType, or some transmog-category enum, etc.)
    local firstSeen
    for id in pairs(seen) do firstSeen = id; break end
    if firstSeen then
        local info = C_TransmogCollection.GetSourceInfo(firstSeen)
        table.insert(lines, "")
        table.insert(lines, ("GetSourceInfo(%d) raw fields:"):format(firstSeen))
        if type(info) == "table" then
            local keys = {}
            for k in pairs(info) do table.insert(keys, k) end
            table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
            for _, k in ipairs(keys) do
                table.insert(lines, ("  %s = %s"):format(tostring(k), tostring(info[k])))
            end
        else
            table.insert(lines, "  (nil)")
        end
    end

    -- raw dump of GetSetPrimaryAppearances entries so we can see the field
    -- names Blizzard actually uses on this client
    table.insert(lines, "")
    table.insert(lines, ("GetSetPrimaryAppearances(%d) raw (%d entries):"):format(setID, #fromPrim))
    for i, e in ipairs(fromPrim) do
        local parts = {}
        if type(e) == "table" then
            for k, v in pairs(e) do
                table.insert(parts, ("%s=%s"):format(tostring(k), tostring(v)))
            end
            table.sort(parts)
        else
            table.insert(parts, tostring(e))
        end
        table.insert(lines, ("  [%d] {%s}"):format(i, table.concat(parts, ", ")))
    end

    -- and try variants too, since this might be a variant whose primary
    -- holds the real tier pieces
    if C_TransmogSets.GetVariantSets then
        local variants = C_TransmogSets.GetVariantSets(setID) or {}
        table.insert(lines, "")
        table.insert(lines, ("GetVariantSets(%d) -> %d entries:"):format(setID, #variants))
        for _, v in ipairs(variants) do
            table.insert(lines, ("  setID=%d  name=%s  description=%s"):format(
                v.setID or 0, tostring(v.name), tostring(v.description)))
        end
    end
    if C_TransmogSets.GetBaseSetID then
        local base = C_TransmogSets.GetBaseSetID(setID)
        table.insert(lines, ("GetBaseSetID(%d) -> %s"):format(setID, tostring(base)))
    end

    ShowDump(("setID %d sources"):format(setID), table.concat(lines, "\n"))
end

-------------------------------------------------------------------------------
-- /sg discover variants <id>
-- C_TransmogSets.GetVariantSets returns sets that are appearance variants of
-- the given set (typically the 4 difficulty versions of a tier set).
-------------------------------------------------------------------------------
local function DiscoverVariants(setIDStr)
    local setID = tonumber(setIDStr)
    if not setID then
        print("|cffff5555[SeasonalGoals]|r usage: /sg discover variants <setID>")
        return
    end
    local lines = {}
    table.insert(lines, ("-- variants for setID %d"):format(setID))
    if C_TransmogSets.GetVariantSets then
        local variants = C_TransmogSets.GetVariantSets(setID) or {}
        table.insert(lines, ("GetVariantSets returned %d entries"):format(#variants))
        for _, v in ipairs(variants) do
            table.insert(lines, ("  setID=%d  name=%s  desc=%s  exp=%s  patch=%s")
                :format(v.setID or 0, tostring(v.name), tostring(v.description),
                    tostring(v.expansionID), tostring(v.patchID)))
        end
    else
        table.insert(lines, "(C_TransmogSets.GetVariantSets not available on this client)")
    end
    ShowDump(("variants of setID %d"):format(setID), table.concat(lines, "\n"))
end

-------------------------------------------------------------------------------
-- /sg discover compile lfr=X normal=Y heroic=Z myth=W
-------------------------------------------------------------------------------
local function ParseCompileArgs(rest)
    local out = {}
    for k, v in rest:gmatch("(%w+)%s*=%s*(%d+)") do
        out[k:lower()] = tonumber(v)
    end
    return out
end

local DIFF_ORDER = NS.Const.DIFF_ORDER

local function GetPrimariesFor(setID)
    if not C_TransmogSets.GetSetPrimaryAppearances then return {} end
    local out = {}
    for _, e in ipairs(C_TransmogSets.GetSetPrimaryAppearances(setID) or {}) do
        local id = (type(e) == "table") and (e.appearanceID or e.sourceID) or e
        if id then table.insert(out, id) end
    end
    return out
end

-- Pull primaries per difficulty, look up each sourceID's categoryID, and
-- build the fully resolved bySlot table (slot -> {lfr,normal,heroic,myth}).
-- Resolution happens here, while GetSourceInfo data is fresh in the client
-- cache, so the runtime never has to call GetSourceInfo (which would return
-- nil for sources the player hasn't browsed in the wardrobe yet).
local function BuildClassData(setIDs)
    local primaries = {}
    local nameInfo = {}
    local bySlot = {}  -- slot -> { lfr, normal, heroic, myth }
    for _, diff in ipairs(DIFF_ORDER) do
        local ids = GetPrimariesFor(setIDs[diff])
        primaries[diff] = ids
        for _, sourceID in ipairs(ids) do
            local info = C_TransmogCollection.GetSourceInfo(sourceID)
            if info then
                local slot = (type(info.categoryID) == "number")
                    and CATEGORY_TO_SLOT[info.categoryID]
                if slot then
                    bySlot[slot] = bySlot[slot] or {}
                    bySlot[slot][diff] = sourceID
                end
                local name = info.name
                if name and not nameInfo[name] then
                    nameInfo[name] = {
                        sourceID = sourceID,
                        invType = info.invType,
                        categoryID = info.categoryID,
                    }
                end
            end
        end
    end
    local slotByName = {}
    for name, entry in pairs(nameInfo) do
        local slot = (type(entry.categoryID) == "number") and CATEGORY_TO_SLOT[entry.categoryID]
        slotByName[name] = slot or "?"
    end
    return {
        primaries = primaries,
        slotByName = slotByName,
        bySlot = bySlot,
        nameInfo = nameInfo,
    }
end

-- Emit the `["CLASSFILE"] = { ... }` block as text lines.
local function EmitClassBlock(classFile, data, setIDs)
    local lines = {}
    table.insert(lines, "-- diagnostics:")
    for _, diff in ipairs(DIFF_ORDER) do
        table.insert(lines, ("  %s setID=%d primaries=%d")
            :format(diff, setIDs[diff], #data.primaries[diff]))
    end
    local nameCount = 0; for _ in pairs(data.nameInfo) do nameCount = nameCount + 1 end
    table.insert(lines, ("  unique item names across difficulties: %d"):format(nameCount))
    table.insert(lines, "")
    table.insert(lines, ("[%q] = {"):format(classFile))
    table.insert(lines, "    primaries = {")
    for _, diff in ipairs(DIFF_ORDER) do
        local ids = {}
        for _, id in ipairs(data.primaries[diff]) do table.insert(ids, tostring(id)) end
        table.insert(lines, ("        %-7s = { %s },"):format(diff, table.concat(ids, ", ")))
    end
    table.insert(lines, "    },")
    -- emit pre-resolved bySlot table (this is what the runtime reads)
    table.insert(lines, "    bySlot = {")
    local SLOT_ORDER = NS.Const.SLOT_KEYS
    for _, slot in ipairs(SLOT_ORDER) do
        local row = data.bySlot[slot]
        if row then
            local parts = {}
            for _, diff in ipairs(DIFF_ORDER) do
                table.insert(parts, ("%s=%s"):format(diff, tostring(row[diff] or "nil")))
            end
            table.insert(lines, ("        %-8s = { %s },"):format(slot, table.concat(parts, ", ")))
        else
            table.insert(lines, ("        -- %s: not resolved"):format(slot))
        end
    end
    table.insert(lines, "    },")
    table.insert(lines, "    -- slotByName kept for debugging; runtime uses bySlot above.")
    table.insert(lines, "    slotByName = {")
    local nameList = {}
    for n in pairs(data.nameInfo) do table.insert(nameList, n) end
    table.sort(nameList)
    for _, name in ipairs(nameList) do
        local entry = data.nameInfo[name]
        local ivName = (type(entry.invType) == "number" and INVTYPE_NAME[entry.invType])
            or tostring(entry.invType)
        local catName = (type(entry.categoryID) == "number" and CATEGORY_NAME[entry.categoryID])
            or tostring(entry.categoryID)
        table.insert(lines,
            ("        [%q] = %q,  -- categoryID=%s (%s), invType=%s"):format(
                name, data.slotByName[name], tostring(entry.categoryID), catName, ivName))
    end
    table.insert(lines, "    },")
    table.insert(lines, "},")
    return lines
end

-- Write to a dev-scratch slot in SavedVariables. This is read offline by the
-- addon author (the file lives on disk after /reload) and converted into the
-- shipped src/data_season.lua. It does NOT affect what end users see in the
-- grid — the runtime lookup only reads from data_season.lua. This buffer is
-- effectively write-only from the game's perspective.
local function WriteDevDump(classFile, data)
    SeasonalGoalsDB._devDump = SeasonalGoalsDB._devDump or {}
    SeasonalGoalsDB._devDump[classFile] = {
        primaries  = data.primaries,
        slotByName = data.slotByName,
        bySlot     = data.bySlot,
    }
end

-- Wrapper kept for the manual `compile lfr=A normal=B heroic=C myth=D` form;
-- uses the player's current class.
local function CompileFromSetIDs(setIDs)
    local classFile = CLASS_FILE_BY_ID[PlayerClassID()]
    if not classFile then
        print("|cffff5555[SeasonalGoals]|r could not detect class")
        return
    end
    local data = BuildClassData(setIDs)
    local lines = EmitClassBlock(classFile, data, setIDs)
    table.insert(lines, 1, "-- dev-only: this dump does NOT affect the grid.")
    table.insert(lines, 2, "-- publish by adding/updating the block in src/data_season.lua.")
    table.insert(lines, 3, ("-- target: NS.Season.appearances[%q]"):format(classFile))
    table.insert(lines, 4, "")
    WriteDevDump(classFile, data)
    ShowDump(("class block: %s"):format(classFile), table.concat(lines, "\n"))
end

-- /sg discover compile lfr=X normal=Y heroic=Z myth=W
local function CompileFromArgs(args)
    local needed = { "lfr", "normal", "heroic", "myth" }
    for _, d in ipairs(needed) do
        if not args[d] then
            print(("|cffff5555[SeasonalGoals]|r missing %s=<setID>"):format(d))
            return
        end
    end
    CompileFromSetIDs(args)
end

-- Find the newest 4-difficulty tier set for a given class bit. Returns
-- { setIDs = {lfr,normal,heroic,myth}, name = "..." } or nil.
-- Second return is a small diagnostics table for the caller.
local function FindSeasonForClassBit(classBit)
    local sets = C_TransmogSets.GetAllSets() or {}
    local diag = { totalSets = #sets, classMatch = 0, withDiffDesc = 0, completeGroups = 0 }
    local byName = {}
    for _, s in ipairs(sets) do
        if s.classMask and bit.band(s.classMask, classBit) ~= 0 then
            diag.classMatch = diag.classMatch + 1
            local diff = DIFF_BY_DESCRIPTION[s.description or ""]
            if diff then
                diag.withDiffDesc = diag.withDiffDesc + 1
                byName[s.name] = byName[s.name] or {
                    name = s.name, byDiff = {},
                    expansionID = s.expansionID, patchID = s.patchID,
                }
                byName[s.name].byDiff[diff] = s.setID
                if (s.expansionID or 0) > (byName[s.name].expansionID or 0) then
                    byName[s.name].expansionID = s.expansionID
                    byName[s.name].patchID = s.patchID
                end
            end
        end
    end
    local complete = {}
    for _, g in pairs(byName) do
        if g.byDiff.lfr and g.byDiff.normal and g.byDiff.heroic and g.byDiff.myth then
            table.insert(complete, g)
        end
    end
    diag.completeGroups = #complete
    if #complete == 0 then return nil, diag end
    table.sort(complete, function(a, b)
        if (a.expansionID or 0) ~= (b.expansionID or 0) then
            return (a.expansionID or 0) > (b.expansionID or 0)
        end
        return (a.patchID or 0) > (b.patchID or 0)
    end)
    return { setIDs = complete[1].byDiff, name = complete[1].name }, diag
end

-------------------------------------------------------------------------------
-- /sg discover all  — compile every class in one dump
-------------------------------------------------------------------------------
local function DiscoverAll()
    local allLines = {}
    local raid = D.CurrentRaidName()
    if raid then
        table.insert(allLines, ("-- raid: %s"):format(raid))
    end
    table.insert(allLines, "-- dev-only: this dump does NOT affect the grid for end users.")
    table.insert(allLines, "-- publish by replacing the NS.Season.appearances table in src/data_season.lua.")
    table.insert(allLines, "")

    local order = {
        "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT",
        "SHAMAN", "MAGE", "WARLOCK", "MONK", "DRUID", "DEMONHUNTER", "EVOKER",
    }
    local nameToBit = {}
    for id, file in pairs(CLASS_FILE_BY_ID) do nameToBit[file] = bit.lshift(1, id - 1) end

    local found, missing = 0, {}
    for _, classFile in ipairs(order) do
        local season, diag = FindSeasonForClassBit(nameToBit[classFile])
        if not season then
            table.insert(missing, classFile)
            table.insert(allLines,
                ("-- %s: no tier set found  (sets=%d, class-match=%d, with-diff-desc=%d, complete-groups=%d)")
                :format(classFile, diag.totalSets, diag.classMatch, diag.withDiffDesc, diag.completeGroups))
            table.insert(allLines, "")
        else
            found = found + 1
            local data = BuildClassData(season.setIDs)
            WriteDevDump(classFile, data)
            local lines = EmitClassBlock(classFile, data, season.setIDs)
            table.insert(allLines, ("-- %s: %s"):format(classFile, season.name))
            for _, l in ipairs(lines) do table.insert(allLines, l) end
            table.insert(allLines, "")
        end
    end
    print(("|cff33ff99[SeasonalGoals]|r discover all: %d classes compiled, %d missing"):format(
        found, #missing))
    if #missing > 0 then
        print("  missing: " .. table.concat(missing, ", "))
        print("  (likely a class whose tier set this account hasn't browsed yet)")
    end
    ShowDump("all classes", table.concat(allLines, "\n"))
end

-------------------------------------------------------------------------------
-- /sg discover season [name]
-- Auto-detect the 4 difficulty setIDs for the current class and compile.
-- If `name` is given, restrict to sets with that exact name (handy when the
-- heuristic picks the wrong tier set).
-------------------------------------------------------------------------------
local function DiscoverSeason(nameFilter)
    nameFilter = nameFilter and nameFilter:gsub("^%s+", ""):gsub("%s+$", "") or ""
    -- accept "Reign of the Abyssal Immolator" with or without surrounding quotes
    nameFilter = nameFilter:gsub('^"(.+)"$', "%1")
    if nameFilter == "" then nameFilter = nil end

    local sets = C_TransmogSets.GetAllSets() or {}
    local classBit = PlayerClassMaskBit()

    -- Group candidate sets by name. A candidate is class-matched, has a
    -- difficulty-mapping description, and (if nameFilter given) matches it.
    local byName = {}
    for _, s in ipairs(sets) do
        if s.classMask and bit.band(s.classMask, classBit) ~= 0 then
            local diff = DIFF_BY_DESCRIPTION[s.description or ""]
            if diff and (not nameFilter or s.name == nameFilter) then
                byName[s.name] = byName[s.name] or { name = s.name, byDiff = {}, expansionID = s.expansionID, patchID = s.patchID }
                byName[s.name].byDiff[diff] = s.setID
                -- record the highest expansionID/patchID seen for this group
                if (s.expansionID or 0) > (byName[s.name].expansionID or 0) then
                    byName[s.name].expansionID = s.expansionID
                    byName[s.name].patchID = s.patchID
                end
            end
        end
    end

    -- Keep only groups that have all 4 difficulties. Pick the newest by
    -- (expansionID, patchID).
    local complete = {}
    for _, g in pairs(byName) do
        if g.byDiff.lfr and g.byDiff.normal and g.byDiff.heroic and g.byDiff.myth then
            table.insert(complete, g)
        end
    end
    if #complete == 0 then
        print("|cffff5555[SeasonalGoals]|r no complete tier-set match (need 4 difficulties).")
        if nameFilter then
            print(("  filter was: %q -- check spelling or try /sg discover"):format(nameFilter))
        else
            print("  try /sg discover and then /sg discover season \"<name>\"")
        end
        return
    end
    table.sort(complete, function(a, b)
        if (a.expansionID or 0) ~= (b.expansionID or 0) then
            return (a.expansionID or 0) > (b.expansionID or 0)
        end
        return (a.patchID or 0) > (b.patchID or 0)
    end)

    local pick = complete[1]
    if #complete > 1 then
        print(("|cff33ff99[SeasonalGoals]|r %d complete tier sets matched; picking newest: %q"):format(
            #complete, pick.name))
        for i = 2, #complete do
            print(("  also matched: %q (exp=%s patch=%s)"):format(
                complete[i].name, tostring(complete[i].expansionID), tostring(complete[i].patchID)))
        end
    else
        print(("|cff33ff99[SeasonalGoals]|r matched %q (setIDs %d/%d/%d/%d)"):format(
            pick.name, pick.byDiff.lfr, pick.byDiff.normal, pick.byDiff.heroic, pick.byDiff.myth))
    end

    -- Auto-remember the season name on first discover so the UI can show it.
    SeasonalGoalsDB.detectedSeasonName = pick.name
    local raidName = D.CurrentRaidName()
    if raidName then
        print(("|cff33ff99[SeasonalGoals]|r current raid: %s"):format(raidName))
    end
    CompileFromSetIDs(pick.byDiff)
end

-------------------------------------------------------------------------------
-- /sg discover currency <id>
-------------------------------------------------------------------------------
local function DiscoverCurrency(idStr)
    local id = tonumber(idStr)
    if not id then
        print("|cffff5555[SeasonalGoals]|r usage: /sg discover currency <currencyID>")
        return
    end
    local info = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo
        and C_CurrencyInfo.GetCurrencyInfo(id)
    if not info then
        print(("|cffff5555[SeasonalGoals]|r currency %d not found"):format(id))
        return
    end
    print(("|cff33ff99[SeasonalGoals]|r currency %d  name=%q  qty=%s  max=%s")
        :format(id, info.name or "?", tostring(info.quantity), tostring(info.maxQuantity)))
end

-------------------------------------------------------------------------------
-- entrypoint dispatch (called from core.lua slash handler)
-------------------------------------------------------------------------------
function D.Run(rest)
    rest = (rest or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if rest == "" or rest == "sets" then
        DiscoverSets()
        return
    end

    local cmd, args = rest:match("^(%S+)%s*(.*)$")
    cmd = (cmd or ""):lower()
    if cmd == "set" then
        DiscoverSet(args)
    elseif cmd == "variants" then
        DiscoverVariants(args)
    elseif cmd == "compile" then
        CompileFromArgs(ParseCompileArgs(args))
    elseif cmd == "season" then
        DiscoverSeason(args)
    elseif cmd == "all" then
        DiscoverAll()
    elseif cmd == "currency" then
        DiscoverCurrency(args)
    else
        print("|cffff5555[SeasonalGoals]|r unknown subcommand: " .. cmd)
        print("  /sg discover [sets|set <id>|variants <id>|season [name]|all|compile ...|currency <id>]")
    end
end
