-- Mini Map: start-up, saved settings, combat queue, other-addon check and /mmap.
local ADDON, ns = ...
local L = ns.L

local DEFAULTS = {
	dbVersion = 1,
}

-- Addons that change the minimap's shape or move it (folder names; best guesses, keep up to date).
local SHAPE_ADDONS = {
	"SexyMap", "BasicMinimap", "ElvUI", "AeonUI", "ForeverUI", "ThiccUI", "EllesmereUI",
	"ClassicUI", "ClassicUI_Forever", "ClassicUIForever",
}
-- Addons that collect minimap buttons themselves.
local BAR_ADDONS = {
	"MinimapButtonButton", "MBB", "MinimapButtonBag", "MinimapButtonFrame", "HidingBar",
}

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
function ns.Print(fmt, ...)
	local text = (select("#", ...) > 0) and fmt:format(...) or fmt
	print(L.PREFIX .. " " .. text)
end

function ns.IsLoaded(name)
	if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded(name) end
	if IsAddOnLoaded then return IsAddOnLoaded(name) end
	return false
end

local function FirstLoaded(list)
	for _, name in ipairs(list) do
		if ns.IsLoaded(name) then return name end
	end
end

-- Runs fn and keeps going if it fails: the error goes to the game's error window
-- (or BugSack) and one chat line says which part failed.
local function OnError(err)
	local handler = geterrorhandler and geterrorhandler()
	if handler then handler(err) end
	return err
end

function ns.SafeRun(label, fn, ...)
	local ok = xpcall(fn, OnError, ...)
	if not ok then ns.Print(L.PART_FAILED, label) end
	return ok
end

---------------------------------------------------------------------------
-- Combat queue: work asked for in combat waits for PLAYER_REGEN_ENABLED.
---------------------------------------------------------------------------
local queue, queued = {}, {}

function ns.RunOutOfCombat(key, fn)
	if not InCombatLockdown() then
		fn()
		return true
	end
	if not queued[key] then
		queued[key] = true
		queue[#queue + 1] = { key = key, fn = fn }
	end
	return false
end

local function FlushQueue()
	local list = queue
	queue, queued = {}, {}
	for _, job in ipairs(list) do
		ns.SafeRun(job.key, job.fn)
	end
end

---------------------------------------------------------------------------
-- Saved settings (account-wide). Fill missing keys only; never drop unknown ones.
---------------------------------------------------------------------------
local function InitDB()
	if type(MiniMapForeverDB) ~= "table" then MiniMapForeverDB = {} end
	for k, v in pairs(DEFAULTS) do
		if MiniMapForeverDB[k] == nil then MiniMapForeverDB[k] = v end
	end
	ns.db = MiniMapForeverDB
end

---------------------------------------------------------------------------
-- Other-addon check: decides which parts run.
---------------------------------------------------------------------------
local function CheckOtherAddons()
	local container = MinimapCluster and MinimapCluster.MinimapContainer
	local shapeBy = FirstLoaded(SHAPE_ADDONS)
	if not shapeBy and Minimap and container and Minimap:GetParent() ~= container then
		shapeBy = L.OTHER_ADDON -- someone already moved the minimap out of Blizzard's frame
	end
	if not shapeBy and GetMinimapShape and not issecurevariable("GetMinimapShape") then
		shapeBy = L.OTHER_ADDON -- another addon already says what shape the minimap is
	end
	ns.shapeConflict = shapeBy
	ns.barConflict = FirstLoaded(BAR_ADDONS)
end

---------------------------------------------------------------------------
-- Set-up
---------------------------------------------------------------------------
local function Setup()
	if ns.setupDone then return end
	ns.setupDone = true
	CheckOtherAddons()

	if ns.shapeConflict then
		ns.Print(L.SHAPE_CONFLICT, ns.shapeConflict)
	else
		ns.SafeRun("Square", ns.Square.Setup, ns.Square)
	end

	if ns.barConflict then
		ns.Print(L.BAR_CONFLICT, ns.barConflict)
	else
		ns.SafeRun("IconBar", ns.IconBar.Setup, ns.IconBar)
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_ENABLED")

events:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 == ADDON then
			InitDB()
		elseif ns.setupDone then
			if arg1 == "Blizzard_HybridMinimap" and ns.Square.active then
				ns.SafeRun("Square", ns.Square.ApplyMask, ns.Square)
			end
			if arg1 == "Blizzard_TimeManager" and ns.Square.active then
				ns.SafeRun("Layer", ns.Square.ApplyLayer, ns.Square) -- clock button loads late
			end
			if ns.IconBar.active then ns.IconBar:RequestScan() end
		end
	elseif event == "PLAYER_LOGIN" then
		if not ns.RunOutOfCombat("setup", Setup) then
			ns.Print(L.SETUP_COMBAT)
		end
	elseif event == "PLAYER_ENTERING_WORLD" then
		if ns.IconBar.active then ns.IconBar:RequestScan() end
	elseif event == "PLAYER_REGEN_ENABLED" then
		FlushQueue()
	end
end)

---------------------------------------------------------------------------
-- /mmap
---------------------------------------------------------------------------
-- Prints the frame under the mouse and its parents (name, type, size), so a player can tell
-- us the name of a minimap button the bar doesn't pick up.
local function FrameUnderMouse()
	if GetMouseFoci then
		local foci = GetMouseFoci()
		return foci and foci[1]
	end
	return GetMouseFocus and GetMouseFocus()
end

-- Lists the textures of a frame (layer, size, atlas or file, crop, shown, alpha), so a
-- button's art can be looked into without other tools.
local function PrintTextures(f)
	if not f.GetRegions then return end
	local n = 0
	for _, r in ipairs({ f:GetRegions() }) do
		if r.GetObjectType and r:GetObjectType() == "Texture" then
			n = n + 1
			local layer = r.GetDrawLayer and r:GetDrawLayer() or "?"
			local w, h = r:GetSize()
			local atlas = r.GetAtlas and r:GetAtlas()
			local art
			if type(atlas) == "string" and atlas ~= "" then
				art = "atlas " .. atlas
			else
				art = tostring((r.GetTextureFileID and r:GetTextureFileID()) or r:GetTexture() or L.NAMES_NOART)
			end
			local left, right, top, bottom = 0, 1, 0, 1
			if r.GetTexCoord then
				local ulx, uly, _, lly, urx = r:GetTexCoord()
				left, right, top, bottom = ulx or 0, urx or 1, uly or 0, lly or 1
			end
			ns.Print(L.NAMES_TEXTURE, tostring(r:GetName() or L.NAMES_UNNAMED), tostring(layer), w or 0, h or 0,
				art, left, right, top, bottom, r:IsShown() and L.NAMES_SHOWN or L.NAMES_HIDDEN, r:GetAlpha() or 0)
		end
	end
	if n == 0 then ns.Print(L.NAMES_NOTEX) end
end

local function PrintNames()
	local f = FrameUnderMouse()
	if not f or f == WorldFrame then
		ns.Print(L.NAMES_NONE)
		return
	end
	if not (f.IsForbidden and f:IsForbidden()) then
		ns.Print(L.NAMES_TEXHEAD)
		PrintTextures(f)
	end
	for _ = 1, 3 do
		if not f or f == UIParent or f == WorldFrame then break end
		if f.IsForbidden and f:IsForbidden() then break end
		local w, h = 0, 0
		if f.GetSize then w, h = f:GetSize() end
		local name = f.GetName and f:GetName() or nil
		local ftype = f.GetObjectType and f:GetObjectType() or "?"
		ns.Print(L.NAMES_LINE, tostring(name or L.NAMES_UNNAMED), ftype, w or 0, h or 0)
		f = f.GetParent and f:GetParent() or nil
	end
end

SLASH_MINIMAPFOREVER1 = "/mmap"
SlashCmdList.MINIMAPFOREVER = function(msg)
	msg = strtrim(msg or ""):lower()
	if msg == "names" then
		PrintNames()
	elseif msg == "rescan" and ns.IconBar.active then
		if InCombatLockdown() then
			ns.Print(L.RESCAN_COMBAT)
			ns.RunOutOfCombat("scan", function() ns.IconBar:Scan() end)
		else
			ns.Print(L.RESCANNED, ns.IconBar:Scan())
		end
	else
		ns.Print(L.HELP_1)
		ns.Print(L.HELP_2)
		ns.Print(L.HELP_3)
	end
end
