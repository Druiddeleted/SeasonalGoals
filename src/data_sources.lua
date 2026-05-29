local ADDON_NAME, NS = ...

-- Per-season "where does this drop" data. Maps (class, slot) -> the raid
-- boss(es) whose loot table contains the tier appearance piece for that slot.
--
-- Regenerate via `/sg discover sources` (or it's folded into `/sg discover
-- all`), then paste the emitted `byClass` blocks below. The runtime UI reads
-- ONLY this file; the discover dev tooling cannot affect what end users see.
--
-- Boss sources are intentionally difficulty-INDEPENDENT: a boss drops its loot
-- table at every difficulty it can be killed on, and difficulty only swaps the
-- appearance variant of the same item. The UI qualifies each source with the
-- cell's target difficulty at display time, so we only store class+slot here.
--
-- Shape per class:
--   byClass[classFile][slotKey] = { "Boss Name", "Boss Name 2", ... }
-- Slot keys: head, shoulder, back, chest, wrist, hands, waist, legs, feet
--
-- The catalyst path ("convert any same-slot piece at the season Catalyst") is
-- generic and always correct, so it's built at runtime from NS.Season rather
-- than stored here — every cell gets it whether or not a boss source is known.
NS.Sources = {
    -- Display label for the raid these bosses live in. When nil, the UI falls
    -- back to NS.Discover.CurrentRaidName() (the EJ-detected raid name).
    raidName = nil,

    -- Populate via the discover tooling. Left empty on a fresh ship so the
    -- feature degrades to the catalyst note alone until sources are captured.
    -- Per-class accessory sources (back/wrist/waist/feet) confirmed by hand:
    -- the raid drops a piece sharing one class's tier look per armor type.
    byClass = {
        MONK   = { waist = { "Chimaerus — The Dreamrift" } },  -- leather belt
        HUNTER = { waist = { "Chimaerus — The Dreamrift" } },  -- mail belt
    },

    -- Tier-token raid sources, keyed by slot and shared by ALL classes. In
    -- Midnight the 5 set slots drop as armor-type tokens, but the boss for a
    -- given slot is the same for every armor type / class, so this is a single
    -- universal slot -> boss map. Hand-maintained from Wowhead — the token
    -- model isn't derivable from the Encounter Journal (tokens carry no
    -- appearance or class-piece itemID to match against).
    --
    -- Boss strings include their raid because tokens span multiple raids (the
    -- chest token is in a different raid from the rest). GetBosses merges this
    -- with any class-specific byClass entries.
    --
    -- The 4 non-set slots (back/wrist/waist/feet) drop as regular per-armor loot
    -- from assorted bosses; map them in byArmor below. Until then they fall back
    -- to the catalyst note.
    -- One token boss per tier slot (universal across armor types).
    tierTokens = {
        head     = "Lightblinded Vanguard — The Voidspire",
        shoulder = "Fallen-King Salhadaar — The Voidspire",
        hands    = "Vorasius — The Voidspire",
        legs     = "Vaelgor & Ezzorak — The Voidspire",
        chest    = "Chimaerus — The Dreamrift",
    },

    -- The Chiming Void Curio converts into ANY of the 5 tier slots, so it's
    -- added as an extra source on each. Its own itemID gives it an icon/tooltip.
    curio = { itemID = 249367, source = "Midnight Falls — March on Quel'Danas" },

    -- The actual item the boss drops for each tier slot is the armor-type token
    -- (a "…Nullcore"), which turns into the class tier piece. Shown instead of
    -- the resolved tier piece so the row matches the literal raid drop. Token
    -- name prefix → armor type: Voidwoven=cloth, Voidcured=leather,
    -- Voidcast=mail, Voidforged=plate. tierTokenItems[armor][slot] = itemID.
    tierTokenItems = {
        cloth   = { head = 249355, shoulder = 249363, chest = 249347, hands = 249351, legs = 249359 },
        leather = { head = 249356, shoulder = 249364, chest = 249348, hands = 249352, legs = 249360 },
        mail    = { head = 249357, shoulder = 249365, chest = 249349, hands = 249353, legs = 249361 },
        plate   = { head = 249358, shoulder = 249366, chest = 249350, hands = 249354, legs = 249362 },
    },

    -- Per-armor-type sources for the NON-token slots (back/wrist/waist/feet).
    -- These drop as regular gear that varies by armor type, so they're keyed by
    -- armor type. Hand-maintained from the in-game Adventure Guide / Wowhead.
    -- Shape: byArmor[armorType][slotKey] = { "Boss — Raid", ... }
    --   armorType in: "plate", "mail", "leather", "cloth" (see NS.Const.CLASS_ARMOR)
    byArmor = {
        plate   = {},
        mail    = {},
        leather = {},
        cloth   = {},
    },

    -- Convertible feeder sources: specific bosses/dungeons that drop a same-slot
    -- piece you can run through the catalyst to get the tier appearance. Unlike
    -- byArmor (which is about the tier look itself), this is "where do I farm a
    -- catalyzable <slot> piece". Captured from the Encounter Journal's current-
    -- season pool (raids + all M+ dungeons incl. legacy) via /sg discover feeders.
    --
    -- Keyed by armor type for the 8 armor-typed slots; back (cloak) is universal
    -- (any class can catalyze any cloak), so it lives in feeders.back.
    -- Shape:
    --   feeders[armorType][slotKey] = { { source = "Boss — Instance", itemID = N, dungeon = bool }, ... }
    --   feeders.back               = { { source = ..., itemID = N, dungeon = bool }, ... }
    feeders = {
        plate = {}, mail = {}, leather = {}, cloth = {}, back = {},
    },
}

-- Return the direct tier-look sources for this class+slot as a list of
-- { source = "Boss — Raid", itemID = N }, or nil if none. Merges class-specific
-- accessory bosses (byClass / byArmor), the universal tier token, and the curio.
-- `itemID` drives an icon + tooltip in the panel: the tier piece for token /
-- accessory rows (resolved at runtime from the shipped appearance — may be nil
-- if the client hasn't cached the source, in which case the caller shows a plain
-- line), and the curio's own item for the curio row.
function NS.Sources.GetBosses(classFile, slotKey, difficulty)
    -- Resolve the tier piece's itemID (for the icon/tooltip) from the appearance.
    local tierItemID
    if NS.Season and NS.Season.GetAppearance and C_TransmogCollection
        and C_TransmogCollection.GetSourceInfo then
        local sid = NS.Season.GetAppearance(classFile, slotKey, difficulty or "normal")
        local info = sid and C_TransmogCollection.GetSourceInfo(sid)
        tierItemID = info and info.itemID or nil
    end

    local out, seen = {}, {}
    local function add(source, itemID)
        if not source or seen[source] then return end
        seen[source] = true
        table.insert(out, { source = source, itemID = itemID })
    end

    local armor = NS.Const and NS.Const.CLASS_ARMOR and NS.Const.CLASS_ARMOR[classFile]
    local cls = NS.Sources.byClass[classFile]
    if cls and cls[slotKey] then for _, b in ipairs(cls[slotKey]) do add(b, tierItemID) end end
    local arm = armor and NS.Sources.byArmor[armor]
    if arm and arm[slotKey] then for _, b in ipairs(arm[slotKey]) do add(b, tierItemID) end end
    -- Tier token: show the armor-type token the boss actually drops (the item
    -- that converts into the tier piece), falling back to the tier piece itemID.
    local tokenID = armor and NS.Sources.tierTokenItems[armor]
        and NS.Sources.tierTokenItems[armor][slotKey]
    add(NS.Sources.tierTokens[slotKey], tokenID or tierItemID)
    if NS.Sources.tierTokens[slotKey] and NS.Sources.curio then
        add(NS.Sources.curio.source .. " (any tier slot)", NS.Sources.curio.itemID)
    end
    if #out == 0 then return nil end
    return out
end

-- Return the convertible-feeder list for this class+slot (specific bosses /
-- dungeons that drop a catalyzable same-slot piece), or nil if none. Back
-- (cloak) is universal; the other slots resolve through the class's armor type.
function NS.Sources.GetFeeders(classFile, slotKey)
    local list
    if slotKey == "back" then
        list = NS.Sources.feeders.back
    else
        local armor = NS.Const and NS.Const.CLASS_ARMOR and NS.Const.CLASS_ARMOR[classFile]
        local byArmor = armor and NS.Sources.feeders[armor]
        list = byArmor and byArmor[slotKey]
    end
    if not list or #list == 0 then return nil end
    return list
end
