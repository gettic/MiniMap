-- Mini Map: start-up, saved settings, combat queue, other-addon check and /mmap.
local ADDON, ns = ...
local L = ns.L

local DEFAULTS = {
	dbVersion = 2,
	booksNudge = true, -- Library Books pins onto the square edge (Compat_LibraryBooks.lua)
	zygorLines = true, -- Zygor's solid minimap path line to the square edge (Compat_Zygor.lua)
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
-- Minimap shape for other addons (LibDBIcon, HereBeDragons...): set as soon as this file
-- loads, so addons that ask early see "SQUARE" too. Only if nobody defined it; never
-- overwrites another addon's. Taken back in Setup if the square map doesn't run.
---------------------------------------------------------------------------
function ns.ShapeFn() return "SQUARE" end
if not GetMinimapShape then GetMinimapShape = ns.ShapeFn end

local function ReleaseShape()
	if GetMinimapShape == ns.ShapeFn then GetMinimapShape = nil end
end

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
-- Saved settings (account-wide). Fill missing keys only; never drop unknown ones, except the
-- one-time clean-up below.
---------------------------------------------------------------------------
local function InitDB()
	if type(MiniMapForeverDB) ~= "table" then MiniMapForeverDB = {} end
	local db = MiniMapForeverDB
	-- Version 2: the ore pins (v0.1.1-beta.3 to beta.7) were removed; their setting and saved
	-- node spots are cleared once.
	if db.dbVersion ~= nil and (tonumber(db.dbVersion) or 1) < 2 then
		db.oreLabels, db.orePins = nil, nil
		db.dbVersion = 2
	end
	for k, v in pairs(DEFAULTS) do
		if db[k] == nil then db[k] = v end
	end
	ns.db = db
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
	if not shapeBy and GetMinimapShape and GetMinimapShape ~= ns.ShapeFn
		and not issecurevariable("GetMinimapShape") then
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
		ns.SafeRun("EditModeBox", ns.Square.UndoSaved, ns.Square)
	else
		ns.SafeRun("Square", ns.Square.Setup, ns.Square)
	end
	if not ns.Square.active then ReleaseShape() end -- map stays round: don't say square

	if ns.barConflict then
		ns.Print(L.BAR_CONFLICT, ns.barConflict)
	else
		ns.SafeRun("IconBar", ns.IconBar.Setup, ns.IconBar)
	end

	ns.SafeRun("LibraryBooks", ns.Books.Setup, ns.Books)
	ns.SafeRun("Zygor", ns.Zygor.Setup, ns.Zygor)
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
-- Moments Blizzard may re-lay or re-clamp the UI (another addon's blocked action included):
-- put the map back on Edit Mode's saved spot if a screen-clamp push moved it.
local PLACE_EVENTS = {
	ADDON_ACTION_BLOCKED = true, ADDON_ACTION_FORBIDDEN = true,
	UI_SCALE_CHANGED = true, DISPLAY_SIZE_CHANGED = true, EDIT_MODE_LAYOUTS_UPDATED = true,
}
for e in pairs(PLACE_EVENTS) do pcall(events.RegisterEvent, events, e) end

events:SetScript("OnEvent", function(_, event, arg1)
	if PLACE_EVENTS[event] or event == "PLAYER_ENTERING_WORLD" then
		if ns.setupDone and ns.Square.active then ns.Square:KeepPlaceSoon(event) end
		if event ~= "PLAYER_ENTERING_WORLD" then return end
	end
	if event == "ADDON_LOADED" then
		if arg1 == ADDON then
			InitDB()
			ns.SafeRun("EditModeBox", ns.Square.ApplySaved, ns.Square)
		elseif ns.setupDone then
			if arg1 == "Blizzard_HybridMinimap" and ns.Square.active then
				ns.SafeRun("Square", ns.Square.ApplyMask, ns.Square)
			end
			if arg1 == "Blizzard_TimeManager" and ns.Square.active then
				ns.SafeRun("Layer", ns.Square.ApplyLayer, ns.Square) -- clock button loads late
			end
			if arg1 == "Library Books" then
				ns.SafeRun("LibraryBooks", ns.Books.Setup, ns.Books) -- loaded after us
			end
			if arg1 == "ZygorGuidesViewerForever" then
				ns.SafeRun("Zygor", ns.Zygor.Setup, ns.Zygor) -- loaded after us
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

-- `/mmap pos`: where Edit Mode's minimap frame (MinimapCluster) is, in its own units, and
-- the screen's size in the same units, plus the clamp insets. Read-only.
local function PrintPos()
	local c = MinimapCluster
	if not (c and c.GetPoint and c:GetLeft()) or (c.IsForbidden and c:IsForbidden()) then
		ns.Print(L.POS_NONE)
		return
	end
	local point, rel, relPoint, x, y = c:GetPoint(1)
	local relName = rel and rel.GetName and rel:GetName() or (rel and "?" or "UIParent")
	ns.Print(L.POS_POINT, tostring(point), tostring(relName), tostring(relPoint), x or 0, y or 0, c:GetScale() or 1)
	local k = (UIParent:GetEffectiveScale() or 1) / (c:GetEffectiveScale() or 1)
	ns.Print(L.POS_EDGES, c:GetLeft(), c:GetRight(), c:GetTop(), c:GetBottom(),
		UIParent:GetRight() * k, UIParent:GetTop() * k)
	if c.GetClampRectInsets then
		local l, r, t, b = c:GetClampRectInsets()
		ns.Print(L.POS_CLAMP, l or 0, r or 0, t or 0, b or 0)
	end
end

-- `/mmap debug`: tooltip owner and raw lines (| shown as ||) and the minimap shape.
-- Read-only; every read in pcall, secret values skipped.
local function IsSecret(v)
	if not issecretvalue then return false end
	local ok, secret = pcall(issecretvalue, v)
	return not ok or secret
end

local function Readable(v)
	if IsSecret(v) then return L.DEBUG_SECRET end
	local ok, s = pcall(function() return (tostring(v):gsub("|", "||")) end)
	return ok and s or L.DEBUG_UNREADABLE
end

-- One value from a frame method, readable or "?" (pcall; secret values shown as such).
local function Ask(f, method)
	if not (f and f[method]) then return "?" end
	local ok, v = pcall(f[method], f)
	if not ok then return "?" end
	return Readable(v)
end

local function NameOf(f)
	if not f then return "nil" end
	local ok, name = pcall(f.GetName, f)
	if ok and name then return Readable(name) end
	return L.NAMES_UNNAMED .. " " .. Ask(f, "GetObjectType")
end

-- Cursor and Minimap geometry in UI units (UIParent), one text line: cursor x,y; Minimap
-- left,bottom,width,height; its effective scale; hit rect insets; shown/visible.
local function MapGeometry()
	local m = Minimap
	if not (m and UIParent) then return end
	local ui = UIParent:GetEffectiveScale() or 1
	local cx, cy = GetCursorPosition()
	cx, cy = (cx or 0) / ui, (cy or 0) / ui
	local es = m:GetEffectiveScale() or 1
	local l, b, w, h = m:GetRect()
	local k = es / ui
	local rect = l and string.format("%.0f,%.0f %.0fx%.0f", l * k, b * k, w * k, h * k) or "none"
	local hl, hr, ht, hb = 0, 0, 0, 0
	if m.GetHitRectInsets then hl, hr, ht, hb = m:GetHitRectInsets() end
	return string.format(L.GEO_FMT, cx, cy, rect, es, hl or 0, hr or 0, ht or 0, hb or 0,
		tostring(m:IsShown()), tostring(m:IsVisible()))
end

-- The frames under the mouse (what takes the mouse there) and the Minimap's own state: if the
-- Minimap isn't first, that frame stops Blizzard's minimap tooltips at this spot.
local function PrintMouse()
	local foci
	if GetMouseFoci then
		local ok, t = pcall(GetMouseFoci)
		foci = ok and type(t) == "table" and t or {}
	else
		foci = { GetMouseFocus and GetMouseFocus() }
	end
	local n = 0
	for i = 1, math.min(#foci, 5) do
		local f = foci[i]
		if f and f ~= WorldFrame then
			n = n + 1
			local forbidden = f.IsForbidden and f:IsForbidden()
			local parent = (not forbidden and f.GetParent) and f:GetParent() or nil
			ns.Print(L.DEBUG_MOUSE, i, forbidden and "(forbidden)" or NameOf(f), NameOf(parent),
				Ask(f, "GetFrameStrata"), Ask(f, "GetFrameLevel"), Ask(f, "IsMouseEnabled"))
		end
	end
	if n == 0 then ns.Print(L.DEBUG_MOUSE_NONE) end
	local m = Minimap
	if m then
		local okS, script = pcall(m.GetScript, m, "OnUpdate")
		ns.Print(L.DEBUG_MAP, Ask(m, "GetFrameStrata"), Ask(m, "GetFrameLevel"), Ask(m, "IsMouseEnabled"),
			Ask(m, "IsMouseClickEnabled"), Ask(m, "IsMouseMotionEnabled"),
			Ask(m, "IsMouseOver"), okS and tostring(script ~= nil) or "?")
	end
	local okG, geo = pcall(MapGeometry)
	if okG and geo then ns.Print(L.DEBUG_GEO, geo) end
	local names = {}
	for k in pairs(ns.Square and ns.Square.mouseFixes or {}) do names[#names + 1] = k end
	table.sort(names)
	ns.Print(L.DEBUG_FIXES, #names > 0 and table.concat(names, "; ") or L.DEBUG_FIXES_NONE)
end

---------------------------------------------------------------------------
-- `/mmap mouse`: live check (toggle). Every 0.5 s prints, only when it changes, the frame under
-- the cursor and whether the Minimap sees the cursor, with the cursor and the Minimap's rect
-- in UI units. Off by itself after 30 s. Read-only, all in pcall.
---------------------------------------------------------------------------
local mouseWatch, watchLeft, watchWait, watchLast

local function FocusName()
	local foci
	if GetMouseFoci then
		local ok, t = pcall(GetMouseFoci)
		foci = ok and type(t) == "table" and t or {}
	else
		foci = { GetMouseFocus and GetMouseFocus() }
	end
	for i = 1, #foci do
		local f = foci[i]
		if f and f ~= WorldFrame then
			if f.IsForbidden and f:IsForbidden() then return "(forbidden)" end
			return NameOf(f)
		end
	end
	return L.MOUSE_WORLD
end

local function WatchTick(_, elapsed)
	watchLeft = watchLeft - elapsed
	if watchLeft <= 0 then
		mouseWatch:SetScript("OnUpdate", nil)
		mouseWatch.on = false
		ns.Print(L.MOUSE_OFF)
		return
	end
	watchWait = watchWait - elapsed
	if watchWait > 0 then return end
	watchWait = 0.5
	local ok, focus, over = pcall(function() return FocusName(), Ask(Minimap, "IsMouseOver") end)
	if not ok then return end
	local key = focus .. "|" .. over
	if key == watchLast then return end
	watchLast = key
	local okG, geo = pcall(MapGeometry)
	ns.Print(L.MOUSE_LINE, focus, over, okG and geo or "?")
end

local function ToggleMouseWatch()
	if not mouseWatch then mouseWatch = CreateFrame("Frame") end
	if mouseWatch.on then
		mouseWatch:SetScript("OnUpdate", nil)
		mouseWatch.on = false
		ns.Print(L.MOUSE_OFF)
		return
	end
	mouseWatch.on = true
	watchLeft, watchWait, watchLast = 30, 0, nil
	ns.Print(L.MOUSE_ON)
	mouseWatch:SetScript("OnUpdate", WatchTick)
end

local function PrintDebug()
	local tip = GameTooltip
	local owner, shown, count = "-", "-", "-"
	if tip then
		local ok, o = pcall(tip.GetOwner, tip)
		if ok and o and not IsSecret(o) then
			local okN, name = pcall(o.GetName, o)
			if okN and name then
				owner = Readable(name)
			else
				local okT, kind = pcall(o.GetObjectType, o)
				owner = L.NAMES_UNNAMED .. " " .. ((okT and Readable(kind)) or "?")
			end
		elseif ok then
			owner = o and L.DEBUG_SECRET or "nil"
		end
		local okS, s = pcall(tip.IsShown, tip)
		if okS then shown = Readable(s) end
		local okC, c = pcall(tip.NumLines, tip)
		if okC and type(c) == "number" and not IsSecret(c) then count = c end
	end
	ns.Print(L.DEBUG_OWNER, owner, shown, tostring(count))
	if type(count) == "number" then
		for i = 1, math.min(count, 30) do
			local fs = _G["GameTooltipTextLeft" .. i]
			local text = "nil"
			if fs then
				local ok, t = pcall(fs.GetText, fs)
				text = ok and Readable(t) or L.DEBUG_UNREADABLE
			end
			ns.Print(L.DEBUG_LINE, i, text)
		end
	end
	local shape, whose = L.DEBUG_SHAPE_NONE, "-"
	if GetMinimapShape then
		local ok, s = pcall(GetMinimapShape)
		shape = ok and Readable(s) or L.DEBUG_UNREADABLE
		whose = (GetMinimapShape == ns.ShapeFn) and L.DEBUG_SHAPE_OURS or L.DEBUG_SHAPE_OTHER
	end
	ns.Print(L.DEBUG_SHAPE, shape, whose)
	if ns.Theme and ns.Theme.BorderDebug then
		local ok, art, kind = pcall(ns.Theme.BorderDebug, ns.Square and ns.Square.border)
		if ok then ns.Print(L.DEBUG_BORDER, art, kind) else ns.Print(L.DEBUG_BORDER, L.DEBUG_UNREADABLE, "-") end
	end
	if ns.Square and ns.Square.HeaderDebug then
		local ok, s, t, z, c, gl, gr = pcall(ns.Square.HeaderDebug)
		if ok then ns.Print(L.DEBUG_HEADER, s, t, z, c, gl, gr) end
	end
	if ns.Square and ns.Square.PlaceDebug then
		local ok, map, saved, clamp, buffs, n, last = pcall(ns.Square.PlaceDebug)
		if ok then ns.Print(L.DEBUG_PLACE, map, saved, clamp, buffs, n, last) end
	end
	if ns.Square and ns.Square.TopDebug then
		local ok, under, hooked, kept, last = pcall(ns.Square.TopDebug)
		if ok then ns.Print(L.DEBUG_TOP, under, hooked, kept, last) end
	end
	if not pcall(PrintMouse) then ns.Print(L.DEBUG_MOUSE_NONE) end
end

-- /mmap art: which border atlases this client has (read only, pcall).
local function PrintArt()
	local ok, lines = pcall(ns.Theme.ArtReport, ns.Square and ns.Square.border)
	if not (ok and type(lines) == "table") then
		ns.Print(L.DEBUG_UNREADABLE)
		return
	end
	for _, line in ipairs(lines) do ns.Print("%s", line) end
end

-- Returns the command word and up to two argument words (lower case, "" when missing).
local function ParseSlash(msg)
	msg = (strtrim(tostring(msg or "")):lower():gsub("[%-_:=]", " "):gsub("%s+", " "))
	local cmd, arg, arg2 = msg:match("^(%S*)%s*(%S*)%s*(%S*)")
	return cmd or "", arg or "", arg2 or "", msg
end
ns.ParseSlash = ParseSlash

SLASH_MINIMAPFOREVER1 = "/mmap"
SlashCmdList.MINIMAPFOREVER = function(msg)
	local cmd = ParseSlash(msg)
	if cmd == "names" then
		PrintNames()
	elseif cmd == "pos" then
		PrintPos()
	elseif cmd == "debug" then
		local ok = pcall(PrintDebug)
		if not ok then ns.Print(L.DEBUG_UNREADABLE) end
	elseif cmd == "art" then
		PrintArt()
	elseif cmd == "selftest" and ns.SelfTest then
		local ok = pcall(ns.SelfTest.Start, ns.SelfTest)
		if not ok then ns.Print(L.DEBUG_UNREADABLE) end
	elseif cmd == "rescan" and ns.IconBar.active then
		if InCombatLockdown() then
			ns.Print(L.RESCAN_COMBAT)
			ns.RunOutOfCombat("scan", function() ns.IconBar:Scan() end)
		else
			ns.Print(L.RESCANNED, ns.IconBar:Scan())
		end
	elseif cmd == "bookson" then
		ns.Books:SetOn(true)
	elseif cmd == "mouse" then
		ToggleMouseWatch()
	elseif cmd == "booksoff" then
		ns.Books:SetOn(false)
	elseif cmd == "zygoron" then
		ns.Zygor:SetOn(true)
	elseif cmd == "zygoroff" then
		ns.Zygor:SetOn(false)
	else
		ns.Print(L.HELP_1)
		ns.Print(L.HELP_2)
		ns.Print(L.HELP_3)
		ns.Print(L.HELP_4)
		ns.Print(L.HELP_5)
		ns.Print(L.HELP_ART)
		ns.Print(L.HELP_MOUSE)
		ns.Print(L.HELP_SELFTEST)
		ns.Print(L.HELP_6)
		if ns.Zygor.IsZygorLoaded() then ns.Print(L.HELP_7) end
	end
end
