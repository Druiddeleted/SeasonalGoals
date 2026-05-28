local ADDON_NAME, NS = ...

-- Per-season data. Regenerate via `/sg discover all` + /reload, then convert
-- the SavedVariables `_devDump.bySlot` tables into the appearances table
-- below (one block per class). The runtime grid reads ONLY this file; the
-- discover dev tools cannot affect what end users see.
--
-- Shape per class:
--   bySlot[slotKey][difficulty] = modifiedAppearanceID
-- Slot keys: head, shoulder, back, chest, wrist, hands, waist, legs, feet
-- Difficulties: lfr, normal, heroic, myth
NS.Season = {
    -- Displayed in the main window subtitle alongside the EJ-detected raid
    -- name. Format: "<Expansion> Season <N>".
    name = "Midnight Season 1",
    catalystCurrency = 3378,
    slotKeys = NS.Const.SLOT_KEYS,
    appearances = {
        WARRIOR = {
            bySlot = {
                head     = { lfr=296443, normal=296438, heroic=296444, myth=296445 },
                shoulder = { lfr=296419, normal=296414, heroic=296420, myth=296421 },
                back     = { lfr=296383, normal=296378, heroic=296384, myth=296385 },
                chest    = { lfr=296479, normal=296474, heroic=296480, myth=296481 },
                wrist    = { lfr=296395, normal=296390, heroic=296396, myth=296397 },
                hands    = { lfr=296455, normal=296450, heroic=296456, myth=296457 },
                waist    = { lfr=296407, normal=296402, heroic=296408, myth=296409 },
                legs     = { lfr=296431, normal=296426, heroic=296432, myth=296433 },
                feet     = { lfr=296467, normal=296462, heroic=296468, myth=296469 },
            },
        },
        PALADIN = {
            bySlot = {
                head     = { lfr=296551, normal=296546, heroic=296552, myth=296553 },
                shoulder = { lfr=296527, normal=296522, heroic=296528, myth=296529 },
                back     = { lfr=296491, normal=296486, heroic=296492, myth=296493 },
                chest    = { lfr=296587, normal=296582, heroic=296588, myth=296589 },
                wrist    = { lfr=296503, normal=296498, heroic=296504, myth=296505 },
                hands    = { lfr=296563, normal=296558, heroic=296564, myth=296565 },
                waist    = { lfr=296515, normal=296510, heroic=296516, myth=296517 },
                legs     = { lfr=296539, normal=296534, heroic=296540, myth=296541 },
                feet     = { lfr=296575, normal=296570, heroic=296576, myth=296577 },
            },
        },
        HUNTER = {
            bySlot = {
                head     = { lfr=296875, normal=296870, heroic=296876, myth=296877 },
                shoulder = { lfr=296851, normal=296846, heroic=296852, myth=296853 },
                back     = { lfr=296815, normal=296810, heroic=296816, myth=296817 },
                chest    = { lfr=296911, normal=296906, heroic=296912, myth=296913 },
                wrist    = { lfr=296827, normal=296822, heroic=296828, myth=296829 },
                hands    = { lfr=296887, normal=296882, heroic=296888, myth=296889 },
                waist    = { lfr=296839, normal=296834, heroic=296840, myth=296841 },
                legs     = { lfr=296863, normal=296858, heroic=296864, myth=296865 },
                feet     = { lfr=296899, normal=296894, heroic=296900, myth=296901 },
            },
        },
        ROGUE = {
            bySlot = {
                head     = { lfr=297091, normal=297086, heroic=297092, myth=297093 },
                shoulder = { lfr=297067, normal=297062, heroic=297068, myth=297069 },
                back     = { lfr=297031, normal=297026, heroic=297032, myth=297033 },
                chest    = { lfr=297127, normal=297122, heroic=297128, myth=297129 },
                wrist    = { lfr=297043, normal=297038, heroic=297044, myth=297045 },
                hands    = { lfr=297103, normal=297098, heroic=297104, myth=297105 },
                waist    = { lfr=297055, normal=297050, heroic=297056, myth=297057 },
                legs     = { lfr=297079, normal=297074, heroic=297080, myth=297081 },
                feet     = { lfr=297115, normal=297110, heroic=297116, myth=297117 },
            },
        },
        PRIEST = {
            bySlot = {
                head     = { lfr=297631, normal=297626, heroic=297632, myth=297633 },
                shoulder = { lfr=297607, normal=297602, heroic=297608, myth=297609 },
                back     = { lfr=297571, normal=297566, heroic=297572, myth=297573 },
                chest    = { lfr=297667, normal=297662, heroic=297668, myth=297669 },
                wrist    = { lfr=297583, normal=297578, heroic=297584, myth=297585 },
                hands    = { lfr=297643, normal=297638, heroic=297644, myth=297645 },
                waist    = { lfr=297595, normal=297590, heroic=297596, myth=297597 },
                legs     = { lfr=297619, normal=297614, heroic=297620, myth=297621 },
                feet     = { lfr=297655, normal=297650, heroic=297656, myth=297657 },
            },
        },
        DEATHKNIGHT = {
            bySlot = {
                head     = { lfr=296659, normal=296654, heroic=296660, myth=296661 },
                shoulder = { lfr=296635, normal=296630, heroic=296636, myth=296637 },
                back     = { lfr=296599, normal=296594, heroic=296600, myth=296601 },
                chest    = { lfr=296695, normal=296690, heroic=296696, myth=296697 },
                wrist    = { lfr=296611, normal=296606, heroic=296612, myth=296613 },
                hands    = { lfr=296671, normal=296666, heroic=296672, myth=296673 },
                waist    = { lfr=296623, normal=296618, heroic=296624, myth=296625 },
                legs     = { lfr=296647, normal=296642, heroic=296648, myth=296649 },
                feet     = { lfr=296683, normal=296678, heroic=296684, myth=296685 },
            },
        },
        SHAMAN = {
            -- NOTE: chest and legs come from sourceIDs ...801/...803 and
            -- ...753/...755 (not the usual +5 / +1 pattern). Verify against
            -- in-game wardrobe if anything looks off for shaman.
            bySlot = {
                head     = { lfr=296767, normal=296762, heroic=296768, myth=296769 },
                shoulder = { lfr=296743, normal=296738, heroic=296744, myth=296745 },
                back     = { lfr=296707, normal=296702, heroic=296708, myth=296709 },
                chest    = { lfr=296800, normal=296801, heroic=296802, myth=296803 },
                wrist    = { lfr=296719, normal=296714, heroic=296720, myth=296721 },
                hands    = { lfr=296779, normal=296774, heroic=296780, myth=296781 },
                waist    = { lfr=296731, normal=296726, heroic=296732, myth=296733 },
                legs     = { lfr=296752, normal=296753, heroic=296754, myth=296755 },
                feet     = { lfr=296791, normal=296786, heroic=296792, myth=296793 },
            },
        },
        MAGE = {
            bySlot = {
                head     = { lfr=297739, normal=297734, heroic=297740, myth=297741 },
                shoulder = { lfr=297715, normal=297710, heroic=297716, myth=297717 },
                back     = { lfr=297679, normal=297674, heroic=297680, myth=297681 },
                chest    = { lfr=297775, normal=297770, heroic=297776, myth=297777 },
                wrist    = { lfr=297691, normal=297686, heroic=297692, myth=297693 },
                hands    = { lfr=297751, normal=297746, heroic=297752, myth=297753 },
                waist    = { lfr=297703, normal=297698, heroic=297704, myth=297705 },
                legs     = { lfr=297727, normal=297722, heroic=297728, myth=297729 },
                feet     = { lfr=297763, normal=297758, heroic=297764, myth=297765 },
            },
        },
        WARLOCK = {
            bySlot = {
                head     = { lfr=297523, normal=297518, heroic=297524, myth=297525 },
                shoulder = { lfr=297499, normal=297494, heroic=297500, myth=297501 },
                back     = { lfr=297463, normal=297458, heroic=297464, myth=297465 },
                chest    = { lfr=297559, normal=297554, heroic=297560, myth=297561 },
                wrist    = { lfr=297475, normal=297470, heroic=297476, myth=297477 },
                hands    = { lfr=297535, normal=297530, heroic=297536, myth=297537 },
                waist    = { lfr=297487, normal=297482, heroic=297488, myth=297489 },
                legs     = { lfr=297511, normal=297506, heroic=297512, myth=297513 },
                feet     = { lfr=297547, normal=297542, heroic=297548, myth=297549 },
            },
        },
        MONK = {
            -- NOTE: monk heroic legs is 302120 instead of 297188. This is
            -- intentional per the discover dump — likely a per-difficulty
            -- variant. Verify in-game if monk legs look wrong.
            bySlot = {
                head     = { lfr=297199, normal=297194, heroic=297200, myth=297201 },
                shoulder = { lfr=297175, normal=297170, heroic=297176, myth=297177 },
                back     = { lfr=297139, normal=297134, heroic=297140, myth=297141 },
                chest    = { lfr=297235, normal=297230, heroic=297236, myth=297237 },
                wrist    = { lfr=297151, normal=297146, heroic=297152, myth=297153 },
                hands    = { lfr=297211, normal=297206, heroic=297212, myth=297213 },
                waist    = { lfr=297163, normal=297158, heroic=297164, myth=297165 },
                legs     = { lfr=297187, normal=297182, heroic=302120, myth=297189 },
                feet     = { lfr=297223, normal=297218, heroic=297224, myth=297225 },
            },
        },
        DRUID = {
            bySlot = {
                head     = { lfr=297307, normal=297302, heroic=297308, myth=297309 },
                shoulder = { lfr=297283, normal=297278, heroic=297284, myth=297285 },
                back     = { lfr=297247, normal=297242, heroic=297248, myth=297249 },
                chest    = { lfr=297343, normal=297338, heroic=297344, myth=297345 },
                wrist    = { lfr=297259, normal=297254, heroic=297260, myth=297261 },
                hands    = { lfr=297319, normal=297314, heroic=297320, myth=297321 },
                waist    = { lfr=297271, normal=297266, heroic=297272, myth=297273 },
                legs     = { lfr=297295, normal=297290, heroic=297296, myth=297297 },
                feet     = { lfr=297331, normal=297326, heroic=297332, myth=297333 },
            },
        },
        DEMONHUNTER = {
            bySlot = {
                head     = { lfr=297415, normal=297410, heroic=297416, myth=297417 },
                shoulder = { lfr=297391, normal=297386, heroic=297392, myth=297393 },
                back     = { lfr=297355, normal=297350, heroic=297356, myth=297357 },
                chest    = { lfr=297451, normal=297446, heroic=297452, myth=297453 },
                wrist    = { lfr=297367, normal=297362, heroic=297368, myth=297369 },
                hands    = { lfr=297427, normal=297422, heroic=297428, myth=297429 },
                waist    = { lfr=297379, normal=297374, heroic=297380, myth=297381 },
                legs     = { lfr=297403, normal=297398, heroic=297404, myth=297405 },
                feet     = { lfr=297439, normal=297434, heroic=297440, myth=297441 },
            },
        },
        EVOKER = {
            bySlot = {
                head     = { lfr=296983, normal=296978, heroic=296984, myth=296985 },
                shoulder = { lfr=296959, normal=296954, heroic=296960, myth=296961 },
                back     = { lfr=296923, normal=296918, heroic=296924, myth=296925 },
                chest    = { lfr=297019, normal=297014, heroic=297020, myth=297021 },
                wrist    = { lfr=296935, normal=296930, heroic=296936, myth=296937 },
                hands    = { lfr=296995, normal=296990, heroic=296996, myth=296997 },
                waist    = { lfr=296947, normal=296942, heroic=296948, myth=296949 },
                legs     = { lfr=296971, normal=296966, heroic=296972, myth=296973 },
                feet     = { lfr=297007, normal=297002, heroic=297008, myth=297009 },
            },
        },
    },
}

-- Direct lookup against the pre-resolved bySlot table.
function NS.Season.Invalidate() end  -- no-op, kept for backward compat

function NS.Season.GetAppearance(classFile, slotKey, difficulty)
    local entry = NS.Season.appearances[classFile]
    if not entry or not entry.bySlot then return nil end
    local row = entry.bySlot[slotKey]
    if not row then return nil end
    return row[difficulty]
end
