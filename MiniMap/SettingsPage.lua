-- Mini Map: our page in Esc > Options > AddOns ("Mini Map"), built only from Blizzard's own
-- settings controls (vertical layout): section headers, buttons and two checkboxes. Registered
-- once at login through the documented Settings API (each function checked first); nothing of
-- Blizzard's settings panel is hooked or written. Every action is safe in combat: frame work goes
-- through ns.RunOutOfCombat, and "Arrange icons..." only shows our own window (on UIParent).
local _, ns = ...
local L = ns.L

local P = {}
ns.SettingsPage = P

local done = false -- registered (or tried) once
P.settings = {}     -- [db key] = the proxy setting Blizzard gave us (tests, read only)

local function Has(t, key) return type(t) == "table" and type(t[key]) == "function" end

-- Button actions (also called by the offline tests).
function P.Arrange()
	local W = ns.OrderWindow
	if not (W and W.State and W.Toggle) then return end
	local _, shown = W.State()
	if not shown then W:Toggle() end
end

function P.SortAZ()
	if not (ns.IconBar and ns.IconBar.ResetOrder) then return end
	if ns.IconBar:ResetOrder() then ns.Print(L.ORDER_RESET) else ns.Print(L.ORDER_AFTER_COMBAT) end
end

function P.Rescan()
	local Bar = ns.IconBar
	if not (Bar and Bar.active) then
		ns.Print(L.OW_BAR_OFF)
		return
	end
	if not ns.RunOutOfCombat("scan", function() ns.Print(L.RESCANNED, Bar:Scan()) end) then
		ns.Print(L.RESCAN_COMBAT)
	end
end

function P.SelfTest()
	if ns.SelfTest and ns.SelfTest.Start then
		local ok = pcall(ns.SelfTest.Start, ns.SelfTest)
		if not ok then ns.Print(L.DEBUG_UNREADABLE) end
	end
end

-- Checkbox setters: the saved value now, the compat module's own switch (which may touch other
-- addons' frames) out of combat.
local function SetBooks(v)
	if not ns.db then return end
	ns.db.booksNudge = v and true or false
	ns.RunOutOfCombat("settings-books", function() ns.Books:SetOn(ns.db.booksNudge) end)
end

local function SetZygor(v)
	if not ns.db then return end
	ns.db.zygorLines = v and true or false
	ns.RunOutOfCombat("settings-zygor", function() ns.Zygor:SetOn(ns.db.zygorLines) end)
end

local function Checkbox(category, var, name, tooltip, key, setter)
	if not (Has(Settings, "RegisterProxySetting") and Has(Settings, "CreateCheckbox")) then return end
	local vtype = (type(Settings.VarType) == "table" and Settings.VarType.Boolean) or "boolean"
	local setting = Settings.RegisterProxySetting(category, var, vtype, name, true,
		function() return not (ns.db and ns.db[key] == false) end,
		function(v) setter(v) end)
	if setting then
		Settings.CreateCheckbox(category, setting, tooltip)
		P.settings[key] = setting
	end
	return setting
end

local function Add(layout, init)
	if init and layout and type(layout.AddInitializer) == "function" then layout:AddInitializer(init) end
end

local function Header(layout, name, tooltip)
	if type(CreateSettingsListSectionHeaderInitializer) ~= "function" then return end
	Add(layout, CreateSettingsListSectionHeaderInitializer(name, tooltip))
end

local function Button(layout, name, text, click, tooltip)
	if type(CreateSettingsButtonInitializer) ~= "function" then return end
	Add(layout, CreateSettingsButtonInitializer(name, text, function() ns.SafeRun("SettingsPage", click) end, tooltip, true))
end

function P.Register()
	if done then return P.category ~= nil end
	done = true
	if not (Has(Settings, "RegisterVerticalLayoutCategory") and Has(Settings, "RegisterAddOnCategory")) then
		return false -- this client has no such settings API: skip quietly
	end
	local category, layout = Settings.RegisterVerticalLayoutCategory(L.SET_TITLE)
	if not category then return false end

	Header(layout, L.SET_H_ICONS, L.SET_EDITMODE_NOTE)
	Button(layout, L.SET_ARRANGE, L.SET_ARRANGE_BTN, P.Arrange, L.SET_ARRANGE_TIP)
	Button(layout, L.SET_SORT, L.OW_RESET, P.SortAZ, L.SET_SORT_TIP)
	Button(layout, L.SET_RESCAN, L.SET_RESCAN_BTN, P.Rescan, L.SET_RESCAN_TIP)

	Header(layout, L.SET_H_OTHER)
	Checkbox(category, "MiniMapForever_booksNudge", L.SET_BOOKS, L.SET_BOOKS_TIP, "booksNudge", SetBooks)
	Checkbox(category, "MiniMapForever_zygorLines", L.SET_ZYGOR, L.SET_ZYGOR_TIP, "zygorLines", SetZygor)

	Header(layout, L.SET_H_HELP)
	Button(layout, L.SET_SELFTEST, L.SET_SELFTEST_BTN, P.SelfTest, L.SET_SELFTEST_TIP)

	Settings.RegisterAddOnCategory(category)
	P.category = category
	return true
end

-- The category's id for Settings.OpenToCategory, or nil.
function P.CategoryID()
	local c = P.category
	if c and type(c.GetID) == "function" then return c:GetID() end
end

-- /mmap options: opens our page (not in combat).
function P.Open()
	if InCombatLockdown() then
		ns.Print(L.SET_COMBAT)
		return false
	end
	local id = P.CategoryID()
	if not (id and Has(Settings, "OpenToCategory")) then
		ns.Print(L.SET_NONE)
		return false
	end
	Settings.OpenToCategory(id)
	return true
end

local loginWatch = CreateFrame("Frame")
loginWatch:RegisterEvent("PLAYER_LOGIN")
loginWatch:SetScript("OnEvent", function(self)
	self:UnregisterEvent("PLAYER_LOGIN")
	ns.SafeRun("SettingsPage", P.Register)
end)
