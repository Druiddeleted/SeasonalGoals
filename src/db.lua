local ADDON_NAME, NS = ...

NS.DB = {}
local DB = NS.DB

-- Everything is account-wide so the grid can read every character's state
-- regardless of which alt is currently logged in. Per-character data lives
-- under SeasonalGoalsDB.characters[charKey].
local ACCOUNT_DEFAULTS = {
    schemaVersion = 1,
    debug = false,
    -- account-wide cache of collected modified appearance IDs.
    -- the scanner refreshes these on each login; the grid reads them so alts
    -- show green without needing to log into them.
    collectedAppearances = {},
    -- per-class enable: "WARRIOR"/"DEMONHUNTER"/etc. -> bool. nil = enabled.
    classEnabled = {},
    -- which difficulty columns to show in the grid.
    showDifficulties = { lfr = false, normal = false, heroic = false, myth = true },
    -- per-character state. key = "Name-Realm".
    -- entry = {
    --   class, level, lastSeen, enabled, targetDifficulty,
    --   items = { [itemGUID] = { itemID, slot, track, rank, excluded } },
    -- }
    characters = {},
}

local CHAR_ENTRY_DEFAULTS = {
    class = nil,
    level = 0,
    lastSeen = 0,
    enabled = true,
    targetDifficulty = "myth",
    items = {},
}

local function deepMerge(dst, src)
    for k, v in pairs(src) do
        if dst[k] == nil then
            if type(v) == "table" then
                dst[k] = {}
                deepMerge(dst[k], v)
            else
                dst[k] = v
            end
        elseif type(v) == "table" and type(dst[k]) == "table" then
            deepMerge(dst[k], v)
        end
    end
end

function DB.CharKey()
    return GetRealmName() .. "-" .. UnitName("player")
end

function DB.Init()
    SeasonalGoalsDB = SeasonalGoalsDB or {}
    deepMerge(SeasonalGoalsDB, ACCOUNT_DEFAULTS)

    local key = DB.CharKey()
    local entry = SeasonalGoalsDB.characters[key]
    if not entry then
        entry = {}
        SeasonalGoalsDB.characters[key] = entry
    end
    deepMerge(entry, CHAR_ENTRY_DEFAULTS)
    entry.class = select(2, UnitClass("player"))
    entry.level = UnitLevel("player") or 0
    entry.lastSeen = time()
end

function DB.CurrentCharacter()
    return SeasonalGoalsDB.characters[DB.CharKey()]
end

-- ===========================================================================
-- Account-wide settings accessors. All UI / scanner / event code reads &
-- writes through these so the SavedVariables schema is owned in one place.
-- ===========================================================================

-- The user-tweakable UI preferences (cell size, sort mode, window
-- positions, future palette/colorblind toggle, etc.).
function DB.UISettings()
    SeasonalGoalsDB = SeasonalGoalsDB or {}
    SeasonalGoalsDB.uiSettings = SeasonalGoalsDB.uiSettings or {}
    return SeasonalGoalsDB.uiSettings
end

function DB.GetUISetting(key, default)
    local v = DB.UISettings()[key]
    if v == nil then return default end
    return v
end

function DB.SetUISetting(key, value)
    DB.UISettings()[key] = value
end

-- ----- per-class enable (column visibility) ---------------------------------

function DB.IsClassEnabled(classFile)
    SeasonalGoalsDB = SeasonalGoalsDB or {}
    local map = SeasonalGoalsDB.classEnabled
    if not map then return true end
    return map[classFile] ~= false
end

function DB.SetClassEnabled(classFile, enabled)
    SeasonalGoalsDB.classEnabled = SeasonalGoalsDB.classEnabled or {}
    SeasonalGoalsDB.classEnabled[classFile] = enabled and true or false
end

-- ----- per-class target difficulty (which diff the grid scores against) -----

function DB.GetTargetDifficulty(classFile)
    SeasonalGoalsDB = SeasonalGoalsDB or {}
    local map = SeasonalGoalsDB.targetByClass
    return (map and map[classFile]) or "myth"
end

function DB.SetTargetDifficulty(classFile, difficulty)
    SeasonalGoalsDB.targetByClass = SeasonalGoalsDB.targetByClass or {}
    SeasonalGoalsDB.targetByClass[classFile] = difficulty
end

-- ----- per-character state --------------------------------------------------

function DB.Characters()
    SeasonalGoalsDB = SeasonalGoalsDB or {}
    SeasonalGoalsDB.characters = SeasonalGoalsDB.characters or {}
    return SeasonalGoalsDB.characters
end

function DB.IsCharacterEnabled(charEntry)
    return charEntry and charEntry.enabled ~= false
end

-- Dev mode is a local-only flag (lives in SavedVariables, which is per-account
-- on disk and never shipped via the addon package). Gates the discover/debug
-- slash commands so end users don't see them in /sg help.
function DB.IsDevMode()
    return SeasonalGoalsDB and SeasonalGoalsDB.devMode == true
end

function DB.SetDevMode(on)
    SeasonalGoalsDB = SeasonalGoalsDB or {}
    SeasonalGoalsDB.devMode = on and true or false
    if not SeasonalGoalsDB.devMode then
        -- Don't leave stale discover output / debug dumps lingering in
        -- SavedVariables when the user leaves dev mode. The runtime grid
        -- never reads these, so dropping them is safe.
        SeasonalGoalsDB._devDump = nil
        SeasonalGoalsDB._debugItems = nil
    end
end

function DB.IsDebug()
    return SeasonalGoalsDB and SeasonalGoalsDB.debug == true
end

function DB.SetDebug(on)
    SeasonalGoalsDB = SeasonalGoalsDB or {}
    SeasonalGoalsDB.debug = on and true or false
end
