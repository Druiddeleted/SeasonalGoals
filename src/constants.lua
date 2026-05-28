local ADDON_NAME, NS = ...

-- Constants shared across modules. Avoid duplicating these tables in
-- discover.lua / scanner.lua / ui.lua / data_season.lua.
NS.Const = {}
local K = NS.Const

-- Canonical order of the 9 tier slots. UI rows and per-class slot loops
-- iterate this so output stays stable.
K.SLOT_KEYS = {
    "head", "shoulder", "back", "chest",
    "wrist", "hands", "waist", "legs", "feet",
}

-- Equipment inventory slot IDs corresponding to SLOT_KEYS (same order).
-- Used by scanner.lua to walk the equipped tier slots via GetInventoryItemLink.
K.EQUIP_SLOT_IDS = {
    1,   -- head
    3,   -- shoulder
    15,  -- back
    5,   -- chest
    9,   -- wrist
    10,  -- hands
    6,   -- waist
    7,   -- legs
    8,   -- feet
}

-- C_Item.GetItemInfo returns invType either as a numeric Enum.InventoryType
-- (current retail) or a legacy "INVTYPE_*" string. Map both forms.
K.INVTYPE_TO_SLOT = {
    [1]  = "head",  [3]  = "shoulder", [5]  = "chest", [6]  = "waist",
    [7]  = "legs", [8]  = "feet",     [9]  = "wrist", [10] = "hands",
    [16] = "back", [20] = "chest",  -- 20 = robe (chest)
    INVTYPE_HEAD     = "head",
    INVTYPE_SHOULDER = "shoulder",
    INVTYPE_CLOAK    = "back",
    INVTYPE_CHEST    = "chest",
    INVTYPE_ROBE     = "chest",
    INVTYPE_WRIST    = "wrist",
    INVTYPE_HAND     = "hands",
    INVTYPE_WAIST    = "waist",
    INVTYPE_LEGS     = "legs",
    INVTYPE_FEET     = "feet",
}

-- Debug-friendly name for an Enum.InventoryType numeric code.
K.INVTYPE_NAME = {
    [0]="NonEquip", [1]="Head", [2]="Neck", [3]="Shoulder", [4]="Body",
    [5]="Chest", [6]="Waist", [7]="Legs", [8]="Feet", [9]="Wrist",
    [10]="Hand", [11]="Finger", [12]="Trinket", [13]="Weapon", [14]="Shield",
    [15]="Ranged", [16]="Cloak", [17]="2HWeapon", [18]="Bag", [19]="Tabard",
    [20]="Robe", [21]="WeaponMainHand", [22]="WeaponOffHand", [23]="Holdable",
    [24]="Ammo", [25]="Thrown", [26]="RangedRight", [27]="Quiver", [28]="Relic",
}

-- C_TransmogCollection.GetSourceInfo's categoryID is Enum.TransmogCollectionType
-- (1-indexed, confirmed by mapping warlock tier appearances to slots).
K.CATEGORY_TO_SLOT = {
    [1]  = "head",
    [2]  = "shoulder",
    [3]  = "back",
    [4]  = "chest",
    [7]  = "wrist",
    [8]  = "hands",
    [9]  = "waist",
    [10] = "legs",
    [11] = "feet",
}

K.CATEGORY_NAME = {
    [1]="Head", [2]="Shoulder", [3]="Back", [4]="Chest", [5]="Shirt",
    [6]="Tabard", [7]="Wrist", [8]="Hands", [9]="Waist", [10]="Legs",
    [11]="Feet",
}

-- classID (1-based, as returned by select(3, UnitClass)) -> classFile string.
K.CLASS_FILE_BY_ID = {
    [1] = "WARRIOR",  [2] = "PALADIN", [3] = "HUNTER", [4] = "ROGUE",
    [5] = "PRIEST",   [6] = "DEATHKNIGHT", [7] = "SHAMAN", [8] = "MAGE",
    [9] = "WARLOCK",  [10] = "MONK", [11] = "DRUID", [12] = "DEMONHUNTER",
    [13] = "EVOKER",
}

-- UI display order for class columns. Distinct from CLASS_FILE_BY_ID because
-- we want a specific visual ordering, not the numeric class ID order.
K.CLASS_ORDER = {
    "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
    "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", "MONK",
    "DRUID", "DEMONHUNTER", "EVOKER",
}

K.CLASS_LABEL = {
    WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter",
    ROGUE = "Rogue", PRIEST = "Priest", DEATHKNIGHT = "Death Knight",
    SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", MONK = "Monk",
    DRUID = "Druid", DEMONHUNTER = "Demon Hunter", EVOKER = "Evoker",
}

K.CLASS_ABBR = {
    WARRIOR = "WAR", PALADIN = "PAL", HUNTER = "HUN", ROGUE = "ROG",
    PRIEST = "PRI", DEATHKNIGHT = "DK", SHAMAN = "SHA", MAGE = "MAG",
    WARLOCK = "WLK", MONK = "MNK", DRUID = "DRU", DEMONHUNTER = "DH",
    EVOKER = "EVK",
}

K.SLOT_LABEL = {
    head = "Head", shoulder = "Shoulder", back = "Back", chest = "Chest",
    wrist = "Wrist", hands = "Hands", waist = "Waist",
    legs = "Legs", feet = "Feet",
}

-- Armor type per class. Used by column-sort modes that group by armor.
K.CLASS_ARMOR = {
    WARRIOR     = "plate",
    PALADIN     = "plate",
    DEATHKNIGHT = "plate",
    HUNTER      = "mail",
    SHAMAN      = "mail",
    EVOKER      = "mail",
    ROGUE       = "leather",
    MONK        = "leather",
    DRUID       = "leather",
    DEMONHUNTER = "leather",
    PRIEST      = "cloth",
    MAGE        = "cloth",
    WARLOCK     = "cloth",
}

-- Heaviest-first ordering used by armor-asc sort. Cloth-first is the reverse.
K.ARMOR_RANK = { plate = 1, mail = 2, leather = 3, cloth = 4 }

-- Difficulty descriptor strings as they appear in C_TransmogSets.GetAllSets
-- entries' `description` field, mapped to our internal difficulty keys.
K.DIFF_BY_DESCRIPTION = {
    ["Raid Finder"] = "lfr",
    ["Normal"]      = "normal",
    ["Heroic"]      = "heroic",
    ["Mythic"]      = "myth",
}

K.DIFF_ORDER = { "lfr", "normal", "heroic", "myth" }
