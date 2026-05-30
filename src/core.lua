local ADDON_NAME, NS = ...

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("BAG_UPDATE_DELAYED")
f:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
f:RegisterEvent("TRANSMOG_COLLECTION_UPDATED")
f:RegisterEvent("ITEM_UPGRADE_MASTER_UPDATE")
f:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
f:RegisterEvent("GET_ITEM_INFO_RECEIVED")

-- Has the addon collected the appearance (account-wide visual) for a given
-- class+slot+difficulty? Used by Catalyst.PruneItems to decide if an item
-- is redundant.
local function isCollected(classFile, slot, difficulty)
    if not (NS.Season and NS.VisualCache) then return false end
    local sid = NS.Season.GetAppearance(classFile, slot, difficulty)
    if not sid then return false end
    return NS.VisualCache.HasVisual(sid) and true or false
end

-- Walk every tracked character and drop items whose contribution set is
-- fully covered by the now-collected appearances. Storage stays bounded as
-- the season fills out.
local function pruneAllCharacters()
    if not NS.Catalyst then return end
    for _, charEntry in pairs(NS.DB.Characters()) do
        local classFile = charEntry.class
        if classFile then
            NS.Catalyst.PruneItems(charEntry.items, function(slot, diff)
                return isCollected(classFile, slot, diff)
            end)
        end
    end
end

-- Coalesce repeated refresh-trigger events into one update per frame.
-- A single in-game action can fire BAG_UPDATE_DELAYED, ITEM_UPGRADE_MASTER_UPDATE,
-- TRANSMOG_COLLECTION_UPDATED, and CURRENCY_DISPLAY_UPDATE within a single
-- frame; without this we'd redo the whole cache walk + grid recolor for each.
local refreshPending = false
local function refreshVisualsAndUI()
    if refreshPending then return end
    refreshPending = true
    C_Timer.After(0, function()
        refreshPending = false
        if NS.VisualCache and NS.VisualCache.RecomputeMissing then
            NS.VisualCache.RecomputeMissing()
        end
        if NS.UI and NS.UI.Refresh then NS.UI.Refresh() end
    end)
end

-- GET_ITEM_INFO_RECEIVED can fire many times in a single frame as a batch of
-- items resolves. Coalesce to one detail-panel re-render per frame; UI.Refresh
-- re-renders the open detail in place, which is all freshly-named items need.
local detailRefreshPending = false
local function refreshDetailSoon()
    if detailRefreshPending then return end
    detailRefreshPending = true
    C_Timer.After(0, function()
        detailRefreshPending = false
        if NS.UI and NS.UI.Refresh then NS.UI.Refresh() end
    end)
end

f:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        NS.DB.Init()
    elseif event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        NS.Scanner.RefreshCollectedAppearances()
        NS.Scanner.RescanCurrentCharacter()
        if NS.Discover and NS.Discover.CurrentRaidName then
            NS.Discover.CurrentRaidName()
        end
        if NS.Minimap and NS.Minimap.Update then NS.Minimap.Update() end
        refreshVisualsAndUI()
    elseif event == "BAG_UPDATE_DELAYED"
        or event == "PLAYER_EQUIPMENT_CHANGED" then
        NS.Scanner.RescanCurrentCharacter()
    elseif event == "ITEM_UPGRADE_MASTER_UPDATE" then
        NS.Scanner.RescanCurrentCharacter()
        refreshVisualsAndUI()
    elseif event == "TRANSMOG_COLLECTION_UPDATED" then
        NS.Scanner.RefreshCollectedAppearances()
        refreshVisualsAndUI()
        pruneAllCharacters()
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        -- Fires once per item whose data finishes loading client-side, often
        -- in bursts and for items we don't track. Item names in the detail
        -- panel fall back to "itemID N" until their data arrives, so re-render
        -- only that panel (and only while it's open) to fill the names in.
        if NS.UI and NS.UI.IsDetailShown and NS.UI.IsDetailShown() then
            refreshDetailSoon()
        end
    elseif event == "CURRENCY_DISPLAY_UPDATE" then
        -- Fires for every currency the game updates (gold, honor, marks…).
        -- Only react when it's our catalyst currency that changed; arg1 is
        -- the currencyID in modern WoW.
        if arg1 == (NS.Season and NS.Season.catalystCurrency) then
            NS.Scanner.RescanCurrentCharacter()
            refreshVisualsAndUI()
        end
    end
end)

-- Resolve a user-typed class identifier ("warlock", "Death Knight",
-- "deathknight") into the canonical classFile string ("WARLOCK",
-- "DEATHKNIGHT"). Accepts: classFile (any case), CLASS_LABEL (any case),
-- and CLASS_LABEL with spaces stripped.
local function resolveClass(input)
    if not input or input == "" then return nil end
    local CLASS_LABEL = NS.Const.CLASS_LABEL
    local upper = input:upper():gsub("%s+", "")
    if NS.Season.appearances[upper] then return upper end
    for classFile, label in pairs(CLASS_LABEL) do
        if label:upper():gsub("%s+", "") == upper then return classFile end
    end
    return nil
end

local PUBLIC_HELP = {
    { "/sg",                       "toggle the main grid" },
    { "/sg config",                "open the config window" },
    { "/sg refresh [class]",       "clear visual cache (all, or just one class)" },
    { "/sg help",                  "show this help" },
}
local DEV_HELP = {
    { "/sg discover ...",          "season-setup tooling" },
    { "/sg debug",                 "toggle internal debug flag" },
    { "/sg debug items",           "dump current character's scanned items" },
    { "/sg devmode off",           "leave dev mode" },
}
local function printHelp()
    print("|cff33ff99[SeasonalGoals]|r commands:")
    for _, row in ipairs(PUBLIC_HELP) do
        print(("  |cffffd200%s|r — %s"):format(row[1], row[2]))
    end
    if NS.DB.IsDevMode() then
        print("|cff33ff99[SeasonalGoals]|r dev commands:")
        for _, row in ipairs(DEV_HELP) do
            print(("  |cffffd200%s|r — %s"):format(row[1], row[2]))
        end
    end
end

SLASH_SEASONALGOALS1 = "/sg"
SLASH_SEASONALGOALS2 = "/seasonalgoals"
SlashCmdList.SEASONALGOALS = function(msg)
    msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, rest = msg:match("^(%S+)%s*(.*)$")
    cmd = (cmd or ""):lower()
    if cmd == "help" or cmd == "?" then
        printHelp()
    elseif cmd == "devmode" then
        -- The toggle itself is always available so a dev can enable it on
        -- a fresh install. It's intentionally obscure (not in /sg help)
        -- when off so end users don't stumble onto it.
        local arg = rest:lower()
        if arg == "on" then NS.DB.SetDevMode(true)
        elseif arg == "off" then NS.DB.SetDevMode(false)
        else NS.DB.SetDevMode(not NS.DB.IsDevMode()) end
        print(("|cff33ff99[SeasonalGoals]|r dev mode = %s"):format(
            tostring(NS.DB.IsDevMode())))
    elseif cmd == "discover" then
        if not NS.DB.IsDevMode() then
            print("|cffff5555[SeasonalGoals]|r unknown command. Type /sg help.")
            return
        end
        NS.Discover.Run(rest)
    elseif cmd == "config" then
        NS.UI.ToggleConfig()
    elseif cmd == "refresh" then
        if rest == "" then
            NS.VisualCache.InvalidateAll()
            print("|cff33ff99[SeasonalGoals]|r refresh: all visual-cache entries cleared.")
        else
            local target = resolveClass(rest)
            if target then
                NS.VisualCache.InvalidateClass(target)
                print(("|cff33ff99[SeasonalGoals]|r refresh: cleared cache for %s."):format(target))
            else
                print(("|cffff5555[SeasonalGoals]|r unknown class %q. Try `warlock`, `deathknight`, `Demon Hunter`, etc."):format(rest))
                return
            end
        end
        refreshVisualsAndUI()
    elseif cmd == "debug" then
        if not NS.DB.IsDevMode() then
            print("|cffff5555[SeasonalGoals]|r unknown command. Type /sg help.")
            return
        end
        local sub = rest:lower()
        if sub == "items" then
            NS.Scanner.DumpDiagnostics()
        else
            NS.DB.SetDebug(not NS.DB.IsDebug())
            print("|cff33ff99[SeasonalGoals]|r debug = " .. tostring(NS.DB.IsDebug()))
        end
    elseif cmd == "" then
        NS.UI.Toggle()
    else
        print(("|cffff5555[SeasonalGoals]|r unknown command %q. Type /sg help."):format(cmd))
    end
end
