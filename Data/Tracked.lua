-- Tallymark: what is tracked out of the box.
--
-- This is the file to edit when you find something worth remembering. Everything here can also be added, edited and
-- removed in game (/tally options > Tracking), and those changes are saved apart from this file, so updating this file
-- never undoes them. An entry you add here with the same id as one added in game is replaced by the in-game one.
--
-- Every entry needs an `id`. `name` is optional (the game's own name is used when it is known), and `group` puts it
-- under a sub-heading of its own on the board.
local _, TM = ...

TM.Tracked = {
    -- Instances pinned to the board: a row even when nobody is saved, so you can see who is free.
    -- id = the name exactly as the Raid Info panel shows it. Instances anyone is saved to show up without pinning.
    lockouts = {
        -- { id = "Molten Core" },
        -- { id = "Onyxia's Lair" },
    },

    -- Quests: reset = "daily" | "weekly" | "once" (one-time: attunements, unlocks, chains you only do once).
    -- The id is the quest ID (shift-click a quest into the options box to get it).
    -- A pool (`any`) is one row over several quest IDs, done when any of them is. `npc`: weeklies (or dailies, per
    -- `reset`) turned in to that NPC join the pool by themselves. Add IDs seen in the wild to `any`.
    quests = {
        { id = "pix", name = "Weekly Pix", reset = "weekly", any = { 96075, 96076 }, npc = "Pix Xizzix" },
        -- { id = 12345, name = "Some Daily", reset = "daily", group = "Dailies" },
        -- { id = 7848, name = "Attunement to the Core", reset = "once", group = "Attunements" },
    },

    -- Currencies by currency ID. Options > Tracking > Currencies lists everything in your currency tab with a + button.
    currencies = {
        -- { id = 1234 },
    },

    -- Items counted in bags and bank, by item ID (keys, tokens, reagents you farm for).
    items = {
        -- { id = 12345, name = "Some Token" },
    },

    -- Reputations by faction ID. Options > Tracking > Reputation lists your reputation panel with a + button.
    reputation = {
        -- { id = 529 }, -- Argent Dawn
    },

    -- World bosses whose kills are recorded (Lockouts), by the encounter name the game reports. A kill shows until the
    -- weekly reset; a world boss save in the Raid Info panel, if Forever gives one, takes its place.
    worldBosses = { "Azuregos", "Lord Kazzak", "Ysondre", "Lethon", "Emeriss", "Taerar" },

    -- Cooldowns: "spell:<spellID>" or "item:<itemID>". A character only gets a cell once it has the spell or item.
    cooldowns = {
        { id = "item:6948", name = "Hearthstone" },
        { id = "spell:17187", name = "Transmute: Arcanite", group = "Professions" },
        { id = "spell:18560", name = "Mooncloth", group = "Professions" },
        { id = "item:15846", name = "Salt Shaker", group = "Professions" },
    },
}
