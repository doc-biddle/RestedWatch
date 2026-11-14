-- Rested Watch in a fake game: logging in, the logout warning (inn, city, sleeping bag), and the /rested list.

local BAG_SPELL = 429959

-- A level 30 character with some rested XP, in a fake game with Rested Watch loaded and logged in.
-- `state` can be changed by a test: resting (the game's own flag) and bagBuff (seconds left on the bag's buff).
local function World(state)
	state = state or {}
	local game, h = FakeWoW.New()
	local timers = {}
	game.C_Timer = {
		After = function(_, fn) table.insert(timers, fn) end,
		NewTicker = function() return { Cancel = function() end } end,
	}
	game.UnitName = function() return "Shaan" end
	game.GetUnitName = function() return "Shaan" end
	game.GetRealmName = function() return "Forever" end
	game.UnitClass = function() return "Priest", "PRIEST" end
	game.UnitFactionGroup = function() return "Horde" end
	game.UnitLevel = function() return state.level or 30 end
	game.UnitXP = function() return 2000 end
	game.UnitXPMax = function() return 10000 end
	game.GetXPExhaustion = function() return state.rested or 1000 end
	game.IsResting = function() return state.resting or false end
	game.GetMaxPlayerLevel = function() return 60 end
	game.IsInInstance = function() return false, "none" end
	game.UnitAffectingCombat = function() return false end
	game.C_UnitAuras = { GetPlayerAuraBySpellID = function(id)
		if id == BAG_SPELL and state.bagBuff then return { expirationTime = 1000 + state.bagBuff } end
	end }
	game.RaidWarningFrame = game.CreateFrame("Frame", "RaidWarningFrame")
	game.RaidNotice_AddMessage = function(_, msg) state.raidWarning = msg end
	game.ChatTypeInfo = { RAID_WARNING = { r = 1, g = 0.5, b = 0 } }
	game.RAID_CLASS_COLORS = { PRIEST = { r = 1, g = 1, b = 1, colorStr = "ffffffff" } }

	h.Load("RestedWatch.lua", "RestedWatch")
	h.Fire("ADDON_LOADED", "RestedWatch")
	h.Fire("PLAYER_ENTERING_WORLD", true, false)
	for _, fn in ipairs(timers) do fn() end   -- the delayed login work
	return game, h, state
end

local function Warned(h, state)
	for _, line in ipairs(h.Printed()) do
		if line:find("quarter of the speed", 1, true) then return true end
	end
	return state.raidWarning ~= nil
end

local cases = {}

function cases.logging_in_records_the_character()
	local game, h = World()
	local chars = h.Env().RestedWatchDB.chars
	local key = "Shaan-Forever"
	T.ok(chars[key], "character recorded")
	T.eq(chars[key].level, 30, "level")
	T.clean(h)
end

function cases.logout_outside_warns()
	local _, h, state = World({ resting = false })
	h.Fire("PLAYER_CAMPING")
	T.ok(Warned(h, state), "warning outside an inn")
	T.clean(h)
end

function cases.logout_in_an_inn_does_not_warn()
	local _, h, state = World({ resting = true })
	h.Fire("PLAYER_CAMPING")
	T.ok(not Warned(h, state), "no warning in an inn")
	T.clean(h)
end

function cases.logout_with_sleeping_bag_does_not_warn()
	-- The bag counts as an inn even if the game doesn't report the character as resting.
	local _, h, state = World({ resting = false, bagBuff = 1800 })
	h.Fire("PLAYER_CAMPING")
	T.ok(not Warned(h, state), "no warning with the sleeping bag")
	T.clean(h)
end

function cases.logout_with_sleeping_bag_is_recorded_as_resting()
	local _, h = World({ resting = false, bagBuff = 1800 })
	h.Fire("PLAYER_LOGOUT")
	T.eq(h.Env().RestedWatchDB.chars["Shaan-Forever"].resting, true, "recorded as resting")
end

function cases.no_warning_at_max_level()
	local _, h, state = World({ resting = false, level = 60 })
	h.Fire("PLAYER_CAMPING")
	T.ok(not Warned(h, state), "no warning at 60")
	T.clean(h)
end

function cases.slash_command_lists_characters()
	local _, h = World()
	h.ClearPrinted()
	h.Slash("RESTEDWATCH", "")
	T.ok(#h.Printed() > 0, "something printed")
	T.clean(h)
end

return cases
