-- Rested Watch: shows how full every character's rested XP is, and when each one fills up.
-- The game only reports rested XP for the character you're logged in on, so this records each
-- character at logout and projects from there: 5% of a level per 8 hours in an inn or city
-- (a quarter of that outside one), capped at 1.5 levels, both raised 4% per rank of the Legacy
-- perk Well Rested. Legacy points are spent per character, so each character's own rank is read
-- and stored. Each login compares the projection with the real value and corrects itself.

local ADDON, ns = ...
local BASE_RATE = 0.05 / (8 * 3600)   -- levels of rested XP per second while resting
local BASE_CAP = 1.5                  -- levels of rested XP at the cap
local OUTSIDE = 0.25                  -- logged out away from an inn or city

local function DB()
	RestedWatchDB = RestedWatchDB or {}
	local d = RestedWatchDB
	d.chars = d.chars or {}
	d.calib = d.calib or {}
	d.ranks, d.rankRead, d.calib.cap = nil, nil, nil   -- from earlier versions: rank is now per character
	d.hidden = d.hidden or {}
	for key, c in pairs(d.chars) do if not c.xpMax or c.xpMax <= 0 then d.chars[key] = nil end end
	return d
end

-- The Legacy trees are a talent tree on the game's trait system (system 45). Find "Well Rested"
-- in it and read its current rank, so new points are picked up automatically.
local LEGACY_SYSTEM = 45
local function ReadWellRested()
	if not (C_Traits and C_Traits.GetConfigIDBySystemID) then return nil end
	local ok, configID = pcall(C_Traits.GetConfigIDBySystemID, LEGACY_SYSTEM)
	if not ok or not configID or configID == 0 then return nil end
	local seen = { "config " .. tostring(configID) }
	local cfg = C_Traits.GetConfigInfo(configID)
	local trees = (cfg and cfg.treeIDs) or {}
	if #trees == 0 then trees = { 1186, 1187, 1188, 1189, 1190 } end   -- the Adventure tree is 1188
	for _, treeID in ipairs(trees) do
		for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
			local node = C_Traits.GetNodeInfo(configID, nodeID)
			local ids = {}
			if node and node.activeEntry and node.activeEntry.entryID then ids[#ids + 1] = node.activeEntry.entryID end
			for _, e in ipairs(node and node.entryIDs or {}) do ids[#ids + 1] = e end
			for _, entryID in ipairs(ids) do
				local entry = C_Traits.GetEntryInfo(configID, entryID)
				local def = entry and entry.definitionID and C_Traits.GetDefinitionInfo(entry.definitionID)
				local name = def and def.overrideName
				if (not name or name == "") and def then
					local spell = def.spellID or def.overriddenSpellID
					name = spell and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spell)
					if (not name or name == "") and spell and GetSpellInfo then name = GetSpellInfo(spell) end
				end
				seen[#seen + 1] = treeID .. "/" .. nodeID .. " " .. tostring(name) .. " rank " .. tostring(node.activeRank or node.currentRank)
				if name and name:lower():gsub("[^a-z]", "") == "wellrested" then
					return node.activeRank or node.currentRank or 0
				end
			end
		end
	end
	DB().lastRead = seen   -- kept so a failed read can be diagnosed
	return nil
end

local function Key() return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "") end
-- Read the logged-in character's Well Rested rank and store it on that character.
local function UpdateRank(announce)
	local c = DB().chars[Key()]
	if not c then return end
	local ok, rank = pcall(ReadWellRested)
	if not ok or rank == nil then return end
	if c.ranks ~= nil and rank ~= c.ranks and announce then
		print("|cff80c0ffRested Watch|r: Well Rested on " .. c.name .. " is now rank " .. rank .. ".")
	end
	c.ranks = rank
	c.rankRead = true
end

local function Rank(c) return c.ranks or 0 end
local function RankLabel(c)
	if c.ranks == nil then return "Well Rested ?" end
	return "Well Rested " .. c.ranks
end
-- Corrections are stored as multipliers, so they carry across characters with different ranks.
local function RateMul(d, c) return (1 + 0.04 * Rank(c)) * (d.calib.rate or 1) end
local function Cap(d, c) return BASE_CAP * (1 + 0.04 * Rank(c)) * (d.calib.capMul or 1) end

local function AtMaxLevel()
	local maxLevel = (GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion())
		or (GetMaxPlayerLevel and GetMaxPlayerLevel()) or 60
	return UnitLevel("player") >= maxLevel
end

-- Where a character's rested XP stands now: fraction of the cap, levels of rested XP,
-- and seconds until full (0 if full, nil if it can't fill).
local function Project(c, now)
	local d = DB()
	if c.atMax or not c.t or not c.xpMax or c.xpMax <= 0 then return nil end
	local cap = Cap(d, c)
	local rate = BASE_RATE * RateMul(d, c) * (c.resting and 1 or OUTSIDE)
	local levels = (c.rested or 0) / c.xpMax + rate * math.max(0, now - c.t)
	if levels >= cap then
		local fullSince = c.t + (cap - (c.rested or 0) / c.xpMax) / rate
		return 1, cap, 0, fullSince
	end
	return levels / cap, levels, (cap - levels) / rate
end

local function Snapshot(online)
	local d = DB()
	local c = d.chars[Key()] or {}
	local xpMax = UnitXPMax("player")
	if not xpMax or xpMax <= 0 then
		-- During logout the game has already cleared XP data: keep the last good reading and
		-- only note that the character is now offline from this moment.
		if c.xpMax and c.xpMax > 0 then c.t = time(); c.online = online end
		return
	end
	c.name = UnitName("player")
	c.full = (GetUnitName and GetUnitName("player")) or c.name
	c.faction = UnitFactionGroup and UnitFactionGroup("player") or c.faction
	c.class = select(2, UnitClass("player"))
	c.level = UnitLevel("player")
	c.xpMax = xpMax
	c.xp = UnitXP("player") or 0
	d.xpTable = d.xpTable or {}
	d.xpTable[c.level] = xpMax
	c.rested = GetXPExhaustion() or 0
	c.resting = IsResting() and true or false
	c.atMax = AtMaxLevel()
	c.t = time()
	c.online = online
	d.chars[Key()] = c
end

-- At login, compare the projection for this character with what the game now reports, and
-- nudge the rate or cap so the other characters' projections improve.
local function Calibrate()
	local d = DB()
	local c = d.chars[Key()]
	if not c or not c.t or c.atMax or c.online or c.level ~= UnitLevel("player") or not c.xpMax or c.xpMax <= 0 then return end
	local elapsed = time() - c.t
	if elapsed < 2 * 3600 then return end
	local ok, rankNow = pcall(ReadWellRested)
	if ok and rankNow ~= nil and c.ranks ~= nil and rankNow ~= c.ranks then return end   -- rank changed while away
	local start = (c.rested or 0) / c.xpMax
	local actual = (GetXPExhaustion() or 0) / UnitXPMax("player")
	local gained = actual - start
	local expectedNoCap = start + BASE_RATE * RateMul(d, c) * (c.resting and 1 or OUTSIDE) * elapsed
	local cap = Cap(d, c)
	local baseCap = cap / (d.calib.capMul or 1)
	if actual > cap + 0.01 then
		d.calib.capMul = actual / baseCap                      -- the real cap is higher
	elseif expectedNoCap < cap - 0.02 and gained > 0.005 then
		local ratio = gained / (expectedNoCap - start)          -- unfilled: learn the rate
		if ratio > 0.5 and ratio < 2 then d.calib.rate = (d.calib.rate or 1) * (0.5 + 0.5 * ratio) end
	elseif expectedNoCap > cap * 1.3 and actual < cap - 0.02 and actual > 0.5 then
		d.calib.capMul = actual / baseCap                      -- long enough to be full: this is the cap
	end
end

local function Duration(s)
	s = math.floor(s)
	local days, hours, mins = math.floor(s / 86400), math.floor(s % 86400 / 3600), math.floor(s % 3600 / 60)
	if days > 0 then return days .. "d " .. hours .. "h" end
	if hours > 0 then return hours .. "h " .. mins .. "m" end
	return mins .. "m"
end

-- A clock time for a moment in the future: "today 18:40", "tomorrow 09:15", "Fri 14:20".
local function Clock(ts)
	ts = math.floor(ts)
	local t, today, tmrw = date("*t", ts), date("*t"), date("*t", time() + 86400)
	local hm = ("%02d:%02d"):format(t.hour, t.min)
	if t.year == today.year and t.yday == today.yday then return "today " .. hm end
	if t.year == tmrw.year and t.yday == tmrw.yday then return "tomorrow " .. hm end
	if ts - time() < 6 * 86400 then return date("%a ", ts) .. hm end
	return date("%d %b ", ts) .. hm
end

local function Num(n)
	n = math.floor(n + 0.5)
	return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n)
end

local FACTION_ICON = {
	Horde = "|TInterface\\FriendsFrame\\PlusManz-Horde:14:14|t ",
	Alliance = "|TInterface\\FriendsFrame\\PlusManz-Alliance:14:14|t ",
}

-- Class crest from the character-creation sheet; falls back to the class atlas if needed.
local function ClassIcon(class)
	if not class then return "" end
	local t = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
	if t then
		return ("|TInterface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES:14:14:0:0:256:256:%d:%d:%d:%d|t "):format(
			t[1] * 256, t[2] * 256, t[3] * 256, t[4] * 256)
	end
	if CreateAtlasMarkup then
		local ok, m = pcall(CreateAtlasMarkup, "classicon-" .. class:lower(), 14, 14)
		if ok and m then return m .. " " end
	end
	return ""
end

-- The parts of a character's label, for column layouts.
local function NameParts(c)
	local col = c.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[c.class]
	local plain = c.full or c.name or "?"
	local f = (FACTION_ICON[c.faction or ""] or ""):gsub(" $", "")
	local ci = ClassIcon(c.class):gsub(" $", "")
	return f, ci, col and ("|c" .. col.colorStr .. plain .. "|r") or plain
end

local function ClassName(c)
	local name = (FACTION_ICON[c.faction or ""] or "") .. (c.full or c.name)
	local col = c.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[c.class]
	local icon = (FACTION_ICON[c.faction or ""] or "") .. ClassIcon(c.class)
	local plain = c.full or c.name
	return col and (icon .. "|c" .. col.colorStr .. plain .. "|r") or name
end

-- Sorted list of lines: full characters first, then nearest to full.
-- Characters to show: not hidden, and below the target level if one is set (/rested target 25).
local function Included(key, c)
	local d = DB()
	return not d.hidden[key] and not (d.target and c.level and c.level >= d.target)
end

-- A small coloured bar for the tooltip, drawn with inline textures.
local function Bar(pct)
	local W = 60
	local filled = math.floor(math.max(0, math.min(1, pct)) * W + 0.5)
	local r, g, b = 255, 150, 40
	if pct >= 1 then r, g, b = 64, 255, 64 elseif pct >= 0.5 then r, g, b = 210, 220, 60 end
	local tex = "|TInterface\\Buttons\\WHITE8X8:8:%d:0:0:8:8:0:8:0:8:%d:%d:%d|t"
	local out = ""
	if filled > 0 then out = out .. tex:format(filled, r, g, b) end
	if W - filled > 0 then out = out .. tex:format(W - filled, 60, 60, 60) end
	return out
end

-- XP needed per level: what your characters have actually seen, otherwise the Classic table
-- scaled by how far Forever's numbers differ from it.
local CLASSIC_XP = { 400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600, 8800, 10100, 11400, 12900, 14400,
	16000, 17700, 19400, 21300, 23200, 25200, 27300, 29400, 31700, 34000, 36400, 38900, 41400, 44300, 47400, 50800,
	54500, 58600, 62800, 67100, 71600, 76100, 80800, 85700, 90700, 95800, 101000, 106300, 111800, 117500, 123200,
	129100, 135100, 141200, 147500, 153900, 160400, 167100, 173900, 180800, 187900, 195000, 202300, 209800 }
local function XPFor(level)
	local t = DB().xpTable or {}
	if t[level] then return t[level] end
	local sum, n = 0, 0
	for l, v in pairs(t) do if CLASSIC_XP[l] then sum, n = sum + v / CLASSIC_XP[l], n + 1 end end
	return (CLASSIC_XP[level] or 0) * (n > 0 and sum / n or 1)
end

-- XP still needed to reach the target level, or nil without a target.
local function XPToTarget(c)
	local d = DB()
	if not d.target or not c.level or c.level >= d.target or not c.xpMax then return nil end
	local need = c.xpMax - (c.xp or 0)
	for l = c.level + 1, d.target - 1 do need = need + XPFor(l) end
	return need
end

-- How much of the remaining way to the target the rested XP covers (0 to 1), or nil.
local function Coverage(c, levels)
	local need = XPToTarget(c)
	if not need or need <= 0 or not levels then return nil end
	return math.min(1, levels * c.xpMax / need)
end

-- Total time this character has sat on full rested XP, including now.
local function Wasted(c, now, left, fullSince)
	return (c.wasted or 0) + ((left == 0 and fullSince) and math.max(0, now - fullSince) or 0)
end

-- Sorting for the lists: by fullness (default), name, level or faction.
local function SortRows(rows)
	local mode = DB().sortMode or "fullness"
	table.sort(rows, function(a, b)
		if mode == "name" then return (a.sortName or "") < (b.sortName or "") end
		if mode == "level" then
			if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
		elseif mode == "faction" then
			if (a.faction or "") ~= (b.faction or "") then return (a.faction or "") > (b.faction or "") end
		end
		if a.left ~= b.left then return a.left < b.left end
		return (a.sortName or "") < (b.sortName or "")
	end)
	return rows
end

-- Who to play next (not the one you're on). With a target level: whoever's rested XP covers the
-- biggest share of their way there. Without: whoever has the most rested XP.
local function PlayNext()
	local d, now, me = DB(), time(), Key()
	local best, bestLevels, bestCover, bestScore
	for key, c in pairs(d.chars) do
		if key ~= me and Included(key, c) then
			local pct, levels = Project(c, now)
			if pct then
				local cover = Coverage(c, levels)
				local score = cover or levels
				if not bestScore or score > bestScore then best, bestLevels, bestCover, bestScore = c, levels, cover, score end
			end
		end
	end
	return best, bestLevels, bestCover
end

local function Lines()
	local d, now, out = DB(), time(), {}
	local me = Key()
	for key, c in pairs(d.chars) do
		if key ~= me and Included(key, c) then
			local pct, levels, left, fullSince = Project(c, now)
			if pct then
				local where = c.resting and "" or " |cffff8040(not in an inn)|r"
				local text
				if left == 0 then
					text = ("%s %d (%s): |cff40ff40full|r for %s%s"):format(ClassName(c), c.level, RankLabel(c), Duration(now - fullSince), where)
				else
					text = ("%s %d (%s): %d%% (%.1f levels), full in %s (%s)%s"):format(ClassName(c), c.level, RankLabel(c), math.floor(pct * 100), levels, Duration(left), Clock(now + left), where)
				end
				local cover = Coverage(c, levels)
				if cover then text = text .. (", covers %d%% of the way to %d"):format(math.floor(cover * 100), d.target) end
				local wasted = Wasted(c, now, left, fullSince)
				if wasted >= 3600 then text = text .. ", |cffff8040" .. Duration(wasted) .. " wasted full|r" end
				out[#out + 1] = { left = left, text = text, sortName = c.full or c.name, level = c.level, faction = c.faction }
			end
		end
	end
	return SortRows(out)
end

-- Every character (including the one you're on) as rows for the Titan tooltip.
local function Rows()
	local d, now, out = DB(), time(), {}
	local me = Key()
	for key, c in pairs(d.chars) do
		if Included(key, c) then
			local pct, levels, left, fullSince = Project(c, now)
			if pct then
				local status
				if left == 0 then
					status = "|cff40ff40Full|r for " .. Duration(now - fullSince)
				else
					status = ("%d%%, full in %s"):format(math.floor(pct * 100), Duration(left))
				end
				status = Bar(pct) .. "  " .. status
				local fIcon, cIcon, cname = NameParts(c)
				local cover = Coverage(c, levels)
				local wasted = Wasted(c, now, left, fullSince)
				out[#out + 1] = {
					sortName = c.full or c.name, faction = c.faction,
					goalText = cover and (math.floor(cover * 100) .. "%") or "",
					wastedText = wasted >= 3600 and Duration(wasted) or "",
					fIcon = fIcon, cIcon = cIcon, cname = cname, level = c.level,
					wr = c.ranks ~= nil and tostring(c.ranks) or "?", bar = Bar(pct),
					pctText = left == 0 and "|cff40ff40Full|r" or (math.floor(pct * 100) .. "%"),
					clockText = left == 0 and "" or Clock(now + left),
					timeText = left == 0 and ("for " .. Duration(now - fullSince)) or ("full in " .. Duration(left)),
					left = left, me = (key == me), inn = c.resting,
					name = ClassName(c) .. ((key == me) and " |cffaaaaaa(you)|r" or ""),
					detail = ("%d, WR %s"):format(c.level, c.ranks ~= nil and tostring(c.ranks) or "?"),
					status = status .. (c.resting and "" or " |cffff8040*|r"),
				}
			end
		end
	end
	return SortRows(out)
end

local function CountFull()
	local n = 0
	for _, l in ipairs(Lines()) do if l.left == 0 then n = n + 1 end end
	return n
end

local function PrintAll()
	UpdateRank(true)
	local lines = Lines()
	local me = DB().chars[Key()]
	local mine = me and (RankLabel(me) .. (me.rankRead and ", read from the Legacy tree" or (me.ranks ~= nil and ", set by hand" or ""))) or "Well Rested ?"
	print("|cff80c0ffRested Watch|r: this character has " .. mine .. ". Other characters:")
	if #lines == 0 then print("  No other characters recorded yet. Log each one in and out once.") end
	for _, l in ipairs(lines) do print("  " .. l.text) end
	local nxt, lv, cover = PlayNext()
	if nxt then
		print(("  Play next: %s (%.1f levels of rested XP%s)"):format(ClassName(nxt), lv,
			cover and (", %d%% of the way to %d"):format(math.floor(cover * 100), DB().target) or ""))
	end
	if DB().target then print("  Showing characters below level " .. DB().target .. ".") end
	local sess, bag = ns.SessionText and ns.SessionText(), ns.BagText and ns.BagText()
	if sess then print("  " .. sess) end
	if bag then print("  " .. bag) end
end

-- Titan Panel or any other LibDataBroker display.
local broker
local function UpdateBroker()
	if broker then
		local n = CountFull()
		broker.text = n > 0 and ("|cff40ff40" .. n .. " full|r") or "none full"
	end
	if ns.UpdateTitan then ns.UpdateTitan() end
end
local ldb = LibStub and LibStub("LibDataBroker-1.1", true)
if ldb and not (Titan_G and Titan_G.plugins) then
	broker = ldb:NewDataObject("Rested Watch", {
		type = "data source", label = "Rested", text = "", icon = "Interface\\Icons\\Spell_Nature_Sleep",
		OnClick = function() PrintAll() end,
		OnTooltipShow = function(tt)
			tt:AddLine("Rested XP on your other characters")
			local lines = Lines()
			if #lines == 0 then tt:AddLine("None recorded yet: log each one in and out once.", 1, 1, 1) end
			for _, l in ipairs(lines) do tt:AddLine(l.text, 1, 1, 1) end
		end,
	})
end

local ready = false   -- no snapshots at login until the logout record has been checked

-- Warn when a logout or quit countdown starts outside an inn or city.
local function WarnIfOutside()
	if IsResting() or AtMaxLevel() then return end
	local d = DB()
	if d.warn == false then return end
	if d.target and UnitLevel("player") >= d.target then return end
	local xpMax = UnitXPMax("player")
	if not xpMax or xpMax <= 0 then return end
	local c = d.chars[Key()] or {}
	if (GetXPExhaustion() or 0) / xpMax >= Cap(d, c) - 0.005 then return end   -- already full
	local msg = "Not in an inn or city: rested XP will build at a quarter of the speed."
	if RaidNotice_AddMessage and RaidWarningFrame then
		RaidNotice_AddMessage(RaidWarningFrame, msg, ChatTypeInfo and ChatTypeInfo["RAID_WARNING"] or { r = 1, g = 0.5, b = 0 })
	end
	if PlaySound then pcall(PlaySound, (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959) end
	print("|cff80c0ffRested Watch|r: |cffff8040" .. msg .. "|r")
end

-- A small toast at the top of the screen (no other addon needed).
local toast
local function ShowToast(text)
	if not toast then
		toast = CreateFrame("Frame", "RestedWatchToast", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
		toast:SetSize(360, 46)
		toast:SetPoint("TOP", UIParent, "TOP", 0, -140)
		toast:SetFrameStrata("DIALOG")
		if toast.SetBackdrop then
			toast:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
				tile = true, tileSize = 16, edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
			toast:SetBackdropColor(0.05, 0.05, 0.08, 0.92)
			toast:SetBackdropBorderColor(0.4, 0.8, 0.4, 1)
		end
		toast.icon = toast:CreateTexture(nil, "ARTWORK")
		toast.icon:SetSize(28, 28)
		toast.icon:SetPoint("LEFT", 10, 0)
		toast.icon:SetTexture("Interface\\Icons\\Spell_Nature_Sleep")
		toast.text = toast:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		toast.text:SetPoint("LEFT", toast.icon, "RIGHT", 10, 0)
		toast.text:SetPoint("RIGHT", -10, 0)
		toast.text:SetJustifyH("LEFT")
		toast:SetScript("OnUpdate", function(self, elapsed)
			self.age = self.age + elapsed
			if self.age > 7 then self:Hide()
			elseif self.age > 6 then self:SetAlpha(7 - self.age)
			elseif self.age < 0.3 then self:SetAlpha(self.age / 0.3) end
		end)
		toast:EnableMouse(true)
		toast:SetScript("OnMouseUp", function(self) self:Hide() end)
	end
	toast.text:SetText(text)
	toast.age = 0
	toast:SetAlpha(0)
	toast:Show()
end

-- Show a message the way the alert setting says: toast, raid warning or chat (or not at all).
local function Notify(text)
	local d = DB()
	if d.alertMode == "off" then return end
	print("|cff80c0ffRested Watch|r: " .. text)
	if d.alertMode == "raid" then
		if RaidNotice_AddMessage and RaidWarningFrame then
			RaidNotice_AddMessage(RaidWarningFrame, text, ChatTypeInfo and ChatTypeInfo["RAID_WARNING"] or { r = 1, g = 1, b = 0 })
		end
		if PlaySound then pcall(PlaySound, (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959) end
	elseif d.alertMode ~= "chat" then
		ShowToast(text)
		if PlaySound then pcall(PlaySound, (SOUNDKIT and SOUNDKIT.TELL_MESSAGE) or 3081) end
	end
end

-- Tell you when another character's rested XP fills up while you're playing.
local function Alert(names)
	if #names == 0 or DB().fillAlert == false then return end
	Notify(table.concat(names, ", ") .. (#names == 1 and " is" or " are") .. " now full of rested XP.")
end

-- This session on the character you're playing: rested XP used, and roughly how many kills are
-- left at double XP. Rested XP only drops when a kill takes its bonus from it, so each drop is
-- one kill's bonus; the last 20 give the average.
local function SessionStart(fresh)
	local d = DB()
	local s = d.session
	if fresh or not s or s.key ~= Key() then
		s = { key = Key(), start = time(), used = 0, bonuses = {} }
		d.session = s
	end
	s.last = GetXPExhaustion() or 0
end

local function TrackRested(xpEvent)
	local s = DB().session
	if not s or s.key ~= Key() or s.last == nil then return end
	local xpMax = UnitXPMax("player")
	if not xpMax or xpMax <= 0 then return end
	local r = GetXPExhaustion() or 0
	if r < s.last then
		if not xpEvent then return end   -- drops are counted when the XP arrives
		local used = s.last - r
		s.used = s.used + used
		s.bonuses[#s.bonuses + 1] = used
		if #s.bonuses > 20 then table.remove(s.bonuses, 1) end
		if r == 0 and not AtMaxLevel() and DB().outAlert ~= false then
			Notify((UnitName("player") or "This character") .. " has used up the rested XP.")
		end
	end
	s.last = r
end

local function SessionText()
	local s = DB().session
	if not s or s.key ~= Key() then return nil end
	local xpMax = UnitXPMax("player")
	if not xpMax or xpMax <= 0 or AtMaxLevel() then return nil end
	local r = GetXPExhaustion() or 0
	local text = ("This session: %s rested XP used (%.1f levels). "):format(Num(s.used), s.used / xpMax)
	if r <= 0 then return text .. "None left." end
	local sum = 0
	for _, b in ipairs(s.bonuses) do sum = sum + b end
	if #s.bonuses == 0 or sum <= 0 then return text .. Num(r) .. " left." end
	return text .. ("%s left, about %d kills at double XP."):format(Num(r), math.ceil(r / (sum / #s.bonuses)))
end

-- The Cozy Sleeping Bag: found in your bags by name, its buff is spell 429959.
local BAG_SPELL = 429959
local function FindBag()
	local d = DB()
	local getID = (C_Container and C_Container.GetContainerItemID) or GetContainerItemID
	local numSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
	if getID and numSlots then
		for bag = 0, 4 do
			for slot = 1, numSlots(bag) or 0 do
				local id = getID(bag, slot)
				if id then
					local name = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or (GetItemInfo and GetItemInfo(id))
					if name and name:lower():find("sleeping bag", 1, true) then d.bagItem = id; return id end
				end
			end
		end
	end
	if d.bagItem and PlayerHasToy and PlayerHasToy(d.bagItem) then return d.bagItem end
	return nil
end

local function BagBuffLeft()
	if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
		local a = C_UnitAuras.GetPlayerAuraBySpellID(BAG_SPELL)
		if a then return math.max(0, (a.expirationTime or 0) - GetTime()) end
		return nil
	end
	for i = 1, 40 do
		local name, _, _, _, _, expires, _, _, _, spellID = UnitBuff("player", i)
		if not name then break end
		if spellID == BAG_SPELL then return math.max(0, (expires or 0) - GetTime()) end
	end
end

-- "ready", "active" (seconds left) or "cooldown" (seconds left); nil without a bag.
local function BagState()
	local id = FindBag()
	if not id then return nil end
	local buff = BagBuffLeft()
	local cdFn = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
	local cd = 0
	if cdFn then
		local start, dur = cdFn(id)
		if start and start > 0 and dur and dur > 1.5 then cd = math.max(0, start + dur - GetTime()) end
	end
	if buff and buff > 0 then return "active", buff, cd end
	if cd > 0 then return "cooldown", cd end
	return "ready"
end

local function BagText()
	local state, left, cd = BagState()
	if not state then return nil end
	if state == "ready" then return "Sleeping bag: |cff40ff40ready|r" end
	if state == "active" then
		return "Sleeping bag: buff active, " .. Duration(left) .. " left" .. ((cd and cd > 0) and (", usable again in " .. Duration(cd)) or "")
	end
	return "Sleeping bag: ready in " .. Duration(left)
end

-- Remind once each time the bag comes off cooldown, when it would actually help.
local function CheckBag()
	local d = DB()
	local state = BagState()
	if state ~= "ready" then d.bagReminded = nil; return end
	if d.bagReminded or d.bagRemind == false then return end
	if AtMaxLevel() or (d.target and UnitLevel("player") >= d.target) then return end
	if (UnitAffectingCombat and UnitAffectingCombat("player")) or (IsInInstance and IsInInstance()) then return end
	local xpMax = UnitXPMax("player")
	if not xpMax or xpMax <= 0 then return end
	if (GetXPExhaustion() or 0) / xpMax >= Cap(d, d.chars[Key()] or {}) - 0.005 then return end
	d.bagReminded = true
	Notify("Your sleeping bag is ready to use.")
end

-- Check for characters that just filled up. With quiet set, only marks them (used at login).
local function CheckFills(quiet)
	local d, now, me, names = DB(), time(), Key(), {}
	for key, c in pairs(d.chars) do
		if key ~= me and Included(key, c) then
			local pct, _, left, fullSince = Project(c, now)
			if pct and left == 0 and fullSince then
				local mark = math.floor(fullSince)
				if c.alertedFor ~= mark then
					c.alertedFor = mark
					if not quiet then names[#names + 1] = ClassName(c) end
				end
			end
		end
	end
	Alert(names)
end

-- Characters that became full since you last played (any character).
local function NewlyFull(since)
	local d, now, me, out = DB(), time(), Key(), {}
	if not since then return out end
	for key, c in pairs(d.chars) do
		if key ~= me and Included(key, c) then
			local pct, _, left, fullSince = Project(c, now)
			if pct and left == 0 and fullSince and fullSince > since then out[#out + 1] = ClassName(c) end
		end
	end
	return out
end
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("PLAYER_UPDATE_RESTING")
frame:RegisterEvent("UPDATE_EXHAUSTION")
frame:RegisterEvent("PLAYER_LEVEL_UP")
frame:RegisterEvent("PLAYER_XP_UPDATE")
frame:RegisterEvent("PLAYER_LEAVING_WORLD")
pcall(frame.RegisterEvent, frame, "PLAYER_CAMPING")
pcall(frame.RegisterEvent, frame, "PLAYER_QUITING")
pcall(frame.RegisterEvent, frame, "TRAIT_CONFIG_UPDATED")
frame:SetScript("OnEvent", function(_, event, isLogin, isReload)
	if event == "TRAIT_CONFIG_UPDATED" then
		UpdateRank(true)
		UpdateBroker()
		return
	end
	if event == "PLAYER_XP_UPDATE" or event == "UPDATE_EXHAUSTION" then
		if ready then TrackRested(event == "PLAYER_XP_UPDATE") end
	end
	if event == "PLAYER_CAMPING" or event == "PLAYER_QUITING" then
		WarnIfOutside()
		return
	end
	if event == "PLAYER_LOGOUT" or event == "PLAYER_LEAVING_WORLD" then
		if ready then Snapshot(false); DB().lastSeen = time() end
	elseif event == "PLAYER_ENTERING_WORLD" then
		if isLogin or isReload then
			C_Timer.After(3, function()
				-- Count the time this character sat full while logged out.
				local mine = DB().chars[Key()]
				if isLogin and mine and mine.t then
					local pct, _, left, fullSince = Project(mine, time())
					if pct and left == 0 and fullSince then mine.wasted = (mine.wasted or 0) + math.max(0, time() - fullSince) end
					mine.alertedFor = nil
				end
				Calibrate()
				ready = true
				Snapshot(true)
				SessionStart(isLogin)
				UpdateRank(true)
				C_Timer.After(15, function() UpdateRank(true) end)   -- the Legacy tree can load late
				UpdateBroker()
				local quiet = DB().loginMsg == false
				local newly = (isLogin and not quiet) and NewlyFull(DB().lastSeen) or {}
				local full = 0
				for _, l in ipairs(Lines()) do if l.left == 0 then full = full + 1 end end
				if #newly > 0 then
					print("|cff80c0ffRested Watch|r: filled up while you were away: " .. table.concat(newly, ", ") .. ".")
				end
				if full > #newly and not quiet then
					print("|cff80c0ffRested Watch|r: " .. full .. " character(s) have full rested XP. Type /rested for the list.")
				end
				CheckFills(true)   -- already reported above; only new fills from here on get an alert
				DB().bagReminded = nil
				CheckBag()
			end)
		elseif ready then
			Snapshot(true)
		end
	elseif ready then
		Snapshot(true)
	end
end)
C_Timer.NewTicker(60, function()
	if ready then
		Snapshot(true)   -- keeps the latest good reading in case logout data is gone
		CheckFills(false)
		CheckBag()
	end
	UpdateBroker()
end)

SLASH_RESTEDWATCH1 = "/rested"
SlashCmdList.RESTEDWATCH = function(msg)
	local cmd, arg = (msg or ""):match("^(%S*)%s*(.-)$")
	cmd = cmd:lower()
	local d = DB()
	if cmd == "ranks" and tonumber(arg) then
		local c = d.chars[Key()]
		if c then
			c.ranks = math.max(0, math.min(5, math.floor(tonumber(arg))))
			c.rankRead = false
			print("Rested Watch: Well Rested on " .. c.name .. " set to rank " .. c.ranks .. ".")
		end
	elseif cmd == "hide" or cmd == "show" then
		for key, c in pairs(d.chars) do
			local want = arg:lower()
			if (c.name and c.name:lower() == want) or (c.full and c.full:lower() == want) then
				d.hidden[key] = (cmd == "hide") or nil
				print("Rested Watch: " .. (c.full or c.name) .. (cmd == "hide" and " hidden." or " shown."))
			end
		end
	elseif cmd == "alert" and (arg == "toast" or arg == "raid" or arg == "chat" or arg == "off") then
		d.alertMode = (arg ~= "toast") and arg or nil
		print("Rested Watch: alerts set to " .. arg .. ".")
	elseif cmd == "sort" and (arg == "fullness" or arg == "name" or arg == "level" or arg == "faction") then
		d.sortMode = (arg ~= "fullness") and arg or nil
		print("Rested Watch: sorting by " .. arg .. ".")
	elseif cmd == "target" then
		local n = tonumber(arg)
		d.target = (n and n > 1) and math.floor(n) or nil
		print("Rested Watch: " .. (d.target and ("showing only characters below level " .. d.target .. ".") or "showing characters of any level."))
	elseif cmd == "help" then
		print("Rested Watch: /rested (list), /rested target <level|off>, /rested alert <toast|raid|chat|off>, /rested sort <fullness|name|level|faction>, /rested hide <name>, /rested show <name>, /rested ranks <0-5> (only if it can't be read)")
	else
		PrintAll()
	end
	UpdateBroker()
end

ns.Rows, ns.CountFull, ns.PrintAll, ns.Duration = Rows, CountFull, PrintAll, Duration
ns.PlayNext, ns.ClassName, ns.DB, ns.NameParts = PlayNext, ClassName, DB, NameParts

-- Settings used by the Titan menu.
ns.SetTarget = function(n) DB().target = n; UpdateBroker() end
ns.SetHidden = function(key, hidden) DB().hidden[key] = hidden or nil; UpdateBroker() end
ns.Characters = function()
	local list = {}
	for key, c in pairs(DB().chars) do list[#list + 1] = { key = key, label = ClassName(c) .. " |cffaaaaaa" .. (c.level or "?") .. "|r", sort = c.full or c.name or key } end
	table.sort(list, function(a, b) return a.sort < b.sort end)
	return list
end
ns.Refresh = UpdateBroker
ns.TestAlert = function() Notify("|cff3fc7ebTest Character|r is now full of rested XP.") end
ns.SessionText, ns.BagText = SessionText, BagText
