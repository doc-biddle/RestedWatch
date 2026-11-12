-- Titan Panel plugin for Rested Watch, built the same way as Titan's own Gold and XP plugins.
local ADDON, ns = ...
if not (Titan_G and Titan_G.plugins and Titan_Menu) then return end

local ID = "RestedWatch"
local BUTTON = "TitanPanel" .. ID .. "Button"

local function ButtonText()
	if ns.DB().buttonMode == "next" then
		local nxt, lv = ns.PlayNext()
		if nxt then return "Next: ", ns.ClassName(nxt) .. (" %.1f"):format(lv) end
		return "Next: ", "-"
	end
	local rows = ns.Rows()
	local full = 0
	for _, r in ipairs(rows) do if r.left == 0 and not r.me then full = full + 1 end end
	if full > 0 then return "Rested: ", "|cff40ff40" .. full .. " full|r" end
	for _, r in ipairs(rows) do
		if not r.me then return "Rested: ", "next in " .. ns.Duration(r.left) end
	end
	return "Rested: ", "-"
end

local function TooltipText()
	local rows = ns.Rows()
	if #rows == 0 then return "Log each character in and out once to record it." end
	local lines, outside = {}, false
	local nxt, lv = ns.PlayNext()
	if nxt then
		lines[#lines + 1] = "|cffffd100Play next:|r " .. ns.ClassName(nxt) .. ("\t%.1f levels rested"):format(lv)
		lines[#lines + 1] = " "
	end
	for _, r in ipairs(rows) do
		lines[#lines + 1] = r.name .. " |cffaaaaaa" .. r.detail .. "|r\t" .. r.status
		if not r.inn then outside = true end
	end
	if outside then
		lines[#lines + 1] = " "
		lines[#lines + 1] = "|cffff8040*|r |cffaaaaaaLogged out outside an inn: fills at a quarter of the speed.|r"
	end
	lines[#lines + 1] = " "
	local target = ns.DB().target
	if target then lines[#lines + 1] = "|cffaaaaaaShowing characters below level " .. target .. ".|r" end
	lines[#lines + 1] = "|cffaaaaaaWR = Well Rested rank. Left-click: list in chat.|r"
	return table.concat(lines, "\n")
end

-- Aligned table tooltip, using the LibQTip library that ships with Titan.
local QTip = LibStub and LibStub("LibQTip-1.0", true)
local GRAY = "|cffaaaaaa"

local function ShowTable(owner)
	local target = ns.DB().target
	local N = 11
	local tip = QTip:Acquire("RestedWatchTip", N, "CENTER", "CENTER", "LEFT", "RIGHT", "RIGHT", "LEFT", "RIGHT", "LEFT", "LEFT", "RIGHT", "RIGHT")
	tip:Clear()
	tip:SetCellMarginH(4)
	local line = tip:AddHeader()
	tip:SetCell(line, 1, "Rested XP", nil, "LEFT", N)

	local nxt, lv, cover = ns.PlayNext()
	if nxt then
		local f, c, n = ns.NameParts(nxt)
		line = tip:AddLine()
		tip:SetCell(line, 1, "|cffffd100Play next|r", nil, "LEFT", 2)
		tip:SetCell(line, 3, f .. " " .. c .. " " .. n, nil, "LEFT", 3)
		local why = ("%.1f levels rested"):format(lv)
		if cover then why = why .. (", %d%% of the way to %d"):format(math.floor(cover * 100), target) end
		tip:SetCell(line, 6, "|cffffd100" .. why .. "|r", nil, "LEFT", N - 5)
	end
	tip:AddSeparator(6, 0, 0, 0, 0)

	tip:AddLine("", "", GRAY .. "Character|r", GRAY .. "Lvl|r", GRAY .. "WR|r", GRAY .. "Rested|r", "", "", GRAY .. "Full at|r",
		target and (GRAY .. "To " .. target .. "|r") or "", GRAY .. "Wasted|r")
	tip:AddSeparator(1, 0.4, 0.4, 0.4, 0.8)

	local rows, outside = ns.Rows(), false
	if #rows == 0 then
		line = tip:AddLine()
		tip:SetCell(line, 1, "Log each character in and out once to record it.", nil, "LEFT", N)
	end
	for _, r in ipairs(rows) do
		local name = r.cname .. (r.me and (GRAY .. " (you)|r") or "")
		local when = r.timeText .. (r.inn and "" or " |cffff8040*|r")
		tip:AddLine(r.fIcon, r.cIcon, name, r.level, GRAY .. r.wr .. "|r", r.bar, r.pctText, GRAY .. when .. "|r",
			r.clockText, r.goalText, r.wastedText ~= "" and ("|cffff8040" .. r.wastedText .. "|r") or "")
		if not r.inn then outside = true end
	end

	tip:AddSeparator(6, 0, 0, 0, 0)
	local function note(text)
		line = tip:AddLine()
		tip:SetCell(line, 1, text, nil, "LEFT", N)
	end
	if outside then note("|cffff8040*|r " .. GRAY .. "Logged out outside an inn: fills at a quarter of the speed.|r") end
	if target then note(GRAY .. "Showing characters below level " .. target .. ". \"To " .. target .. "\" = share of the way there that rested XP covers.|r") end
	note(GRAY .. "Wasted = total time spent sitting on full rested XP.|r")
	local sess, bag = ns.SessionText(), ns.BagText()
	if sess or bag then
		tip:AddSeparator(6, 0, 0, 0, 0)
		if sess then note("|cffffd100" .. sess .. "|r") end
		if bag then note("|cffffd100" .. bag .. "|r") end
		tip:AddSeparator(6, 0, 0, 0, 0)
	end
	note(GRAY .. "WR = Well Rested rank. Left-click: list in chat. Right-click: options.|r")

	tip:SmartAnchorTo(owner)
	tip:SetAutoHideDelay(0.15, owner)
	tip:Show()
end

local function Menu(owner, root)
	local d = ns.DB()
	local function refresh() ns.Refresh() end
	Titan_Menu.AddCommand(root, ID, "List in chat", function() ns.PrintAll() end)

	-- Target level: characters at or above it are left out.
	local target = Titan_Menu.AddButton(root, "Target level")
	for _, lvl in ipairs({ 0, 10, 20, 25, 30, 40, 50, 60 }) do
		target:CreateRadio(lvl == 0 and "Off (show every level)" or ("Below " .. lvl),
			function() return (d.target or 0) == lvl end,
			function() ns.SetTarget(lvl > 0 and lvl or nil) end)
	end

	-- Which characters to show.
	local chars = Titan_Menu.AddButton(root, "Characters")
	local list = ns.Characters()
	if #list == 0 then Titan_Menu.AddText(chars, "None recorded yet") end
	for _, c in ipairs(list) do
		Titan_Menu.AddSelectorGeneric(chars, c.label,
			function() return not d.hidden[c.key] end,
			function() ns.SetHidden(c.key, not d.hidden[c.key]) end)
	end
	if #list > 15 then Titan_Menu.SetScroll(chars, 400) end

	-- What the button shows.
	local show = Titan_Menu.AddButton(root, "Button shows")
	show:CreateRadio("How many are full",
		function() return d.buttonMode ~= "next" end,
		function() d.buttonMode = nil; refresh() end)
	show:CreateRadio("Who to play next",
		function() return d.buttonMode == "next" end,
		function() d.buttonMode = "next"; refresh() end)

	-- Sort order.
	local sort = Titan_Menu.AddButton(root, "Sort by")
	for _, o in ipairs({ { "fullness", "How full" }, { "name", "Name" }, { "level", "Level" }, { "faction", "Faction" } }) do
		sort:CreateRadio(o[2],
			function() return (d.sortMode or "fullness") == o[1] end,
			function() d.sortMode = (o[1] ~= "fullness") and o[1] or nil; refresh() end)
	end

	-- How to announce an alt filling up while you play.
	-- Alerts: how they're shown, and which ones you want.
	local alert = Titan_Menu.AddButton(root, "Alerts")
	for _, o in ipairs({ { "toast", "Show as a toast" }, { "raid", "Show as a raid warning" }, { "chat", "Chat message only" }, { "off", "No alerts" } }) do
		alert:CreateRadio(o[2],
			function() return (d.alertMode or "toast") == o[1] end,
			function() d.alertMode = (o[1] ~= "toast") and o[1] or nil end)
	end
	alert:CreateButton("Test it", function() ns.TestAlert() end)
	Titan_Menu.AddDivider(alert)
	for _, o in ipairs({ { "fillAlert", "An alt fills up" }, { "outAlert", "Rested XP runs out" }, { "bagRemind", "Sleeping bag is ready" } }) do
		Titan_Menu.AddSelectorGeneric(alert, o[2],
			function() return d[o[1]] ~= false end,
			function() d[o[1]] = (d[o[1]] == false) and nil or false end)
	end

	Titan_Menu.AddDivider(root)
	Titan_Menu.AddSelectorGeneric(root, "Warn when logging out outside an inn",
		function() return d.warn ~= false end,
		function() d.warn = (d.warn == false) and nil or false end)
	Titan_Menu.AddSelectorGeneric(root, "Messages at login",
		function() return d.loginMsg ~= false end,
		function() d.loginMsg = (d.loginMsg == false) and nil or false end)
end

local function Create()
	if _G[BUTTON] then return end
	local f = CreateFrame("Frame", nil, UIParent)
	local window = CreateFrame("Button", BUTTON, f, "TitanPanelComboTemplate")
	window:SetFrameStrata("FULLSCREEN")
	window.registry = {
		id = ID,
		category = "Information",
		version = ((C_AddOns and C_AddOns.GetAddOnMetadata) and C_AddOns.GetAddOnMetadata(ADDON, "Version"))
			or (GetAddOnMetadata and GetAddOnMetadata(ADDON, "Version")) or "?",
		menuText = "Rested Watch",
		menuContextFunction = Menu,
		buttonTextFunction = ButtonText,
		tooltipTitle = "Rested XP",
		tooltipTextFunction = TooltipText,
		icon = "Interface\\Icons\\Spell_Nature_Sleep",
		iconWidth = 16,
		notes = "Shows how full each character's rested XP is and when it fills, including the Well Rested Legacy perk.",
		controlVariables = { ShowIcon = true, ShowLabelText = true, ShowColoredText = false, DisplayOnRightSide = true },
		savedVariables = { ShowIcon = true, ShowLabelText = true, DisplayOnRightSide = false },
	}
	window:SetScript("OnShow", function(self) Titan_G.plugins.OnShow(self) end)
	if QTip then
		window:SetScript("OnEnter", function(self) ShowTable(self) end)
		window:SetScript("OnLeave", function() end)   -- the table hides itself shortly after the mouse leaves
	end
	window:SetScript("OnClick", function(self, button)
		if QTip and QTip:IsAcquired("RestedWatchTip") then QTip:Release(QTip:Acquire("RestedWatchTip")) end
		if button == "LeftButton" then ns.PrintAll() end
		Titan_G.plugins.OnClick(self, button)
	end)
end
Create()

ns.UpdateTitan = function()
	if Titan_G.plugins.UpdateButton then pcall(Titan_G.plugins.UpdateButton, ID) end
end
