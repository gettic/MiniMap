-- Mini Map: /mmap selftest. The addon checks itself in the running game and prints one line per
-- check (PASS / FAIL / SKIP) and one RESULT line; the same text, as one line, goes into a small
-- copy box the player copies by hand (Ctrl+C) to send back.
-- Safety: reads only. Nothing is moved, shown, hidden or switched on/off (except our own copy
-- box); no Blizzard function is replaced or hooked; nothing protected is called. In combat it
-- waits for PLAYER_REGEN_ENABLED (one queued run). Every value read from a frame is checked with
-- issecretvalue; a secret value makes that check SKIP, never FAIL. Never writes the saved data.
-- The text holds frame names and numbers only: no player, realm, guild or zone names, no links.
-- Output stays local (chat frame and the copy box). Based on the kit's SelfTest.template.lua.
local ADDON, ns = ...
local L = ns.L
local T = ns.Theme

local ST = {}
ns.SelfTest = ST

local TOL = 1          -- screen units allowed between where a piece is and where it should be
local TOL_CLAMP = 0.1  -- Edit Mode clamp insets (cluster units)
local COPY_MAX = 4000  -- copy box text length

local SECRET = {}      -- error value: a secret was read, the check is skipped

---------------------------------------------------------------------------
-- Safe reads
---------------------------------------------------------------------------
local function IsSecret(v)
	local f = issecretvalue
	if type(f) ~= "function" then return false end
	local ok, s = pcall(f, v)
	return ok and s and true or false
end

-- obj:method(...) -> its results, or nil when the method is missing or errors.
-- A secret result stops the check (error SECRET -> SKIP "hidden by the game").
local function Get(obj, method, ...)
	if type(obj) ~= "table" then return nil end
	local f = obj[method]
	if type(f) ~= "function" then return nil end
	local r = { n = 0 }
	local function Pack(ok, ...)
		r.ok, r.n = ok, select("#", ...)
		for i = 1, r.n do r[i] = select(i, ...) end
	end
	Pack(pcall(f, obj, ...))
	if not r.ok then return nil end
	for i = 1, r.n do
		if IsSecret(r[i]) then error(SECRET, 0) end
	end
	return unpack(r, 1, r.n)
end

-- Screen rect l, r, t, b (left * effective scale ...), or nil.
local function Rect(f)
	local l, r, t, b = Get(f, "GetLeft"), Get(f, "GetRight"), Get(f, "GetTop"), Get(f, "GetBottom")
	if type(l) ~= "number" or type(r) ~= "number" or type(t) ~= "number" or type(b) ~= "number" then return end
	local s = Get(f, "GetEffectiveScale")
	if type(s) ~= "number" or s <= 0 then s = 1 end
	return l * s, r * s, t * s, b * s
end

local function NameOf(f)
	if type(f) ~= "table" then return "?" end
	if Get(f, "IsForbidden") then return "(forbidden)" end
	local n = Get(f, "GetName")
	if type(n) == "string" then return (n:gsub("|", "||")) end
	return L.NAMES_UNNAMED
end

local function Under()
	local u = ns.Square.under
	if u == nil then u = ns.Square.HeaderIsUnderneath() end
	return u and true or false
end

local function InEditMode()
	local em = EditModeManagerFrame
	return em and type(em.IsEditModeActive) == "function" and em:IsEditModeActive() and true or false
end

---------------------------------------------------------------------------
-- The checks. Each returns status ("PASS" / "FAIL" / "SKIP"), the detail text and, when the
-- name depends on the state, the name; nil status = no line (e.g. the other addon isn't loaded).
---------------------------------------------------------------------------
local function CheckSpot()
	local state, moved, off, held = ns.Square.PlaceCheck()
	if state == "default" then return "SKIP", L.ST_SPOT_DEFAULT end
	if state == "other" then return "SKIP", L.ST_SPOT_OTHER end
	if state ~= "same" and state ~= "pushed" then return "SKIP", L.ST_SPOT_NONE end
	if state == "pushed" or (off and off > TOL) then
		return "FAIL", L.ST_SPOT_FAR:format(off or moved or 0)
	end
	-- The screen clamp keeps the map + bar on screen: by design, not a move.
	if held and held > TOL then return "PASS", L.ST_SPOT_HELD:format(held) end
	return "PASS", L.ST_SPOT_OK
end

-- Header Underneath: the block's top edge stays where it is with the header on top.
local function CheckTop()
	if not Under() then return "SKIP", L.ST_TOP_OFF end
	local d = ns.Square.ContainerCheck()
	if not d then return "SKIP", L.ST_TOP_NONE end
	if d > TOL then return "FAIL", L.ST_TOP_BAD:format(d) end
	return "PASS", L.ST_TOP_OK
end

local function CheckBox()
	local fit = ns.Square.fit
	if not (type(fit) == "table" and type(fit.clamp) == "table") then return "SKIP", L.ST_BOX_NONE end
	local l, r, t, b = Get(MinimapCluster, "GetClampRectInsets")
	if type(l) ~= "number" then return "SKIP", L.ST_BOX_NONE end
	local d = 0
	for i, v in ipairs({ l, r or 0, t or 0, b or 0 }) do
		d = math.max(d, math.abs(v - (fit.clamp[i] or 0)))
	end
	if d > TOL_CLAMP then return "FAIL", L.ST_BOX_BAD:format(d) end
	return "PASS", L.ST_BOX_OK
end

local function CheckHeader()
	local name = Under() and L.ST_N_HEADER_UNDER or L.ST_N_HEADER_ABOVE
	local Sq = ns.Square
	local h, b = Sq.header, Sq.border
	if not (h and b and Get(h, "IsVisible")) then return "SKIP", L.ST_HEADER_NONE, name end
	local _, _, _, _, gl, gr = Sq.HeaderDebug()
	gl, gr = tonumber(gl), tonumber(gr)
	if not (gl and gr) then return "SKIP", L.ST_HEADER_NONE, name end
	if gl < -TOL or gr < -TOL then return "FAIL", L.ST_HEADER_OUT:format(gl, gr), name end
	if math.abs(gl - gr) > TOL then return "FAIL", L.ST_HEADER_BAD:format(gl, gr), name end
	local hl, hr = Rect(h)
	local bl, br = Rect(b)
	if hl and bl then
		local d = math.abs((hl + hr) / 2 - (bl + br) / 2)
		if d > TOL then return "FAIL", L.ST_HEADER_OFF:format(d), name end
	end
	return "PASS", L.ST_HEADER_OK:format((gl + gr) / 2), name
end

local function CheckSide()
	local Sq = ns.Square
	local _, _, ht, hb = Rect(Sq.header)
	local _, _, bt, bb = Rect(Sq.border)
	if not (ht and bt and Get(Sq.header, "IsVisible")) then return "SKIP", L.ST_HEADER_NONE end
	local ok
	if Under() then ok = ht <= bb + 0.5 else ok = hb >= bt - 0.5 end
	if ok then return "PASS", L.ST_SIDE_OK end
	return "FAIL", L.ST_SIDE_BAD
end

local function CheckMouse()
	local m = Minimap
	local off = {}
	if Get(m, "IsMouseEnabled") == false then off[#off + 1] = "mouse" end
	if Get(m, "IsMouseClickEnabled") == false then off[#off + 1] = "clicks" end
	if Get(m, "IsMouseMotionEnabled") == false then off[#off + 1] = "hover" end
	if #off > 0 then return "FAIL", L.ST_MOUSE_BAD:format(table.concat(off, ", ")) end
	local l, r, t, b = Get(m, "GetHitRectInsets")
	if (l or 0) > 0 or (r or 0) > 0 or (t or 0) > 0 or (b or 0) > 0 then return "FAIL", L.ST_MOUSE_INSETS end
	return "PASS", L.ST_MOUSE_OK
end

local function CheckCover()
	local list = ns.Square.MouseBlockers()
	if #list == 0 then return "PASS", L.ST_COVER_OK end
	local names = {}
	for i = 1, math.min(#list, 3) do
		names[i] = (tostring(list[i].key):gsub("^mouse off: ", ""):gsub("|", "||"))
	end
	return "FAIL", L.ST_COVER_BAD:format(table.concat(names, ", "))
end

-- Only when the cursor happens to be on the map: the map (or a small piece on it, a pin or a
-- zoom button) must be the first frame under it.
local function IsInside(f, root)
	local depth = 0
	while f and depth < 20 do
		if f == root then return true end
		f = Get(f, "GetParent")
		depth = depth + 1
	end
	return false
end

local function CheckHover()
	local m = Minimap
	if not Get(m, "IsMouseOver") then return "SKIP", L.ST_HOVER_AWAY end
	local foci
	if GetMouseFoci then
		local ok, t = pcall(GetMouseFoci)
		foci = ok and type(t) == "table" and t or {}
	else
		foci = { GetMouseFocus and GetMouseFocus() }
	end
	local first
	for i = 1, #foci do
		if foci[i] and foci[i] ~= WorldFrame then first = foci[i] break end
	end
	if not first then return "FAIL", L.ST_HOVER_BAD:format(L.MOUSE_WORLD) end
	if first == m then return "PASS", L.ST_HOVER_OK end
	if not Get(first, "IsForbidden") and IsInside(first, m) then
		local fl, fr, ft, fb = Rect(first)
		local ml, mr, mt, mb = Rect(m)
		if fl and ml and (fr - fl) * (ft - fb) < 0.5 * (mr - ml) * (mt - mb) then
			return "PASS", L.ST_HOVER_OK
		end
	end
	return "FAIL", L.ST_HOVER_BAD:format(NameOf(first))
end

local function CheckZoom()
	local m = Minimap
	local zin, zout, hit = m.ZoomIn, m.ZoomOut, m.ZoomHitArea
	local ml, mr, mt, mb = Rect(m)
	if not (zin and zout and ml) then return "SKIP", L.ST_ZOOM_NONE end
	local point = (T.zoom and T.zoom.point) or "TOPRIGHT"
	local mx, my = (ml + mr) / 2, (mt + mb) / 2
	local centres = {}
	for _, z in ipairs({ { zin, L.ST_ZOOM_IN }, { zout, L.ST_ZOOM_OUTB } }) do
		local l, r, t, b = Rect(z[1])
		if not l then return "SKIP", L.ST_ZOOM_NONE end
		if l < ml - TOL or r > mr + TOL or t > mt + TOL or b < mb - TOL then
			return "FAIL", L.ST_ZOOM_OUT:format(z[2])
		end
		local cx, cy = (l + r) / 2, (t + b) / 2
		local okX = (point:find("RIGHT") and cx > mx) or (point:find("LEFT") and cx < mx) or not (point:find("RIGHT") or point:find("LEFT"))
		local okY = (point:find("TOP") and cy > my) or (point:find("BOTTOM") and cy < my) or not (point:find("TOP") or point:find("BOTTOM"))
		if not (okX and okY) then return "FAIL", L.ST_ZOOM_CORNER:format(z[2]) end
		centres[#centres + 1] = { cx, cy }
	end
	if math.abs(centres[1][1] - centres[2][1]) <= TOL and math.abs(centres[1][2] - centres[2][2]) <= TOL then
		return "FAIL", L.ST_ZOOM_STACK
	end
	if hit and Get(hit, "IsMouseEnabled") then return "FAIL", L.ST_ZOOM_HIT end
	return "PASS", L.ST_ZOOM_OK
end

local function CheckBorder()
	local border = ns.Square.border
	if not (border and Get(border, "IsShown")) then return "FAIL", L.ST_BORDER_NONE end
	local kind = T.BorderKind and T.BorderKind(border)
	local want = (T.border and T.border.useSliced) and "sliced" or "nineslice"
	if kind == want then return "PASS", L.ST_BORDER_OK:format(tostring(kind)) end
	return "FAIL", L.ST_BORDER_FALLBACK:format(tostring(kind))
end

local function CheckPlate()
	if not (T.zonePlate and T.zonePlate.on) then return "SKIP", L.ST_PLATE_OFF end
	local plate = ns.Square.zonePlate
	if plate == false then return "FAIL", L.ST_PLATE_BAD end
	if plate == nil then return "SKIP", L.ST_HEADER_NONE end
	return "PASS", L.ST_PLATE_OK
end

local function CheckCoords()
	local broken, box, coords = ns.Square.CoordsState()
	if broken then return "FAIL", L.ST_COORDS_BROKEN end
	local text = coords and coords.CoordText
	if not (box and text) then return "SKIP", L.ST_COORDS_AWAY end
	local s = Get(text, "GetText")
	if not (Get(coords, "IsVisible") and type(s) == "string" and s ~= "") then return "SKIP", L.ST_COORDS_AWAY end
	if not Get(box, "IsShown") then return "FAIL", L.ST_COORDS_HIDDEN end
	local bl, cl = Get(box, "GetFrameLevel"), Get(coords, "GetFrameLevel")
	if type(bl) == "number" and type(cl) == "number" and bl >= cl then return "FAIL", L.ST_COORDS_LEVEL end
	-- Box at least as big as the numbers (both in screen units).
	local sw, sh = Get(text, "GetStringWidth"), Get(text, "GetStringHeight")
	local ts, bs = Get(text, "GetEffectiveScale"), Get(box, "GetEffectiveScale")
	local bw, bh = Get(box, "GetWidth"), Get(box, "GetHeight")
	if type(sw) == "number" and type(sh) == "number" and type(ts) == "number" and type(bs) == "number"
		and type(bw) == "number" and type(bh) == "number" then
		if bw * bs < sw * ts - TOL or bh * bs < sh * ts - TOL then return "FAIL", L.ST_COORDS_SMALL end
	end
	return "PASS", L.ST_COORDS_OK
end

local function CheckBar()
	local Bar = ns.IconBar
	if not (Bar and Bar.active and Bar.frame) then return "SKIP", L.ST_BAR_OFF end
	local n = Bar.State()
	if not Get(Bar.frame, "IsShown") then
		if n == 0 then return "PASS", L.ST_BAR_EMPTY end
		return "SKIP", L.ST_BAR_HIDDEN:format(n)
	end
	local under = Under()
	local border = ns.Square.active and ns.Square.border
	local fl, fr, ft, fb = Rect(Bar.frame)
	local bl, br, bt, bb = Rect(border)
	if fl and bl then
		local d = math.max(math.abs(fl - bl), math.abs(fr - br))
		if d > TOL then return "FAIL", L.ST_BAR_WIDTH:format(d) end
		local ok
		if under then ok = fb >= bt - 0.5 else ok = ft <= bb + 0.5 end
		if not ok then return "FAIL", L.ST_BAR_SIDE end
	end
	return "PASS", L.ST_BAR_OK:format(n, under and L.ST_BAR_ABOVE or L.ST_BAR_UNDER)
end

local function CheckZygor()
	local Z = ns.Zygor
	if not (Z and Z.IsZygorLoaded and Z.IsZygorLoaded()) then return nil end
	if ns.db and ns.db.zygorLines == false then return "PASS", L.ST_ON_OFF end
	local hooked, enabled, failed = Z.State()
	if failed then return "FAIL", L.ST_ON_BROKEN end
	if hooked and enabled then return "PASS", L.ST_ON_OK end
	return "FAIL", L.ST_ON_IDLE
end

local function CheckBooks()
	if not ns.IsLoaded("Library Books") then return nil end
	if ns.db and ns.db.booksNudge == false then return "PASS", L.ST_ON_OFF end
	local running, n, failed = ns.Books.State()
	if failed then return "FAIL", L.ST_ON_BROKEN end
	if running then return "PASS", L.ST_BOOKS_OK:format(n) end
	return "FAIL", L.ST_ON_IDLE
end

local function CheckShape()
	local fn = GetMinimapShape
	local shape = type(fn) == "function" and fn() or nil
	if IsSecret(shape) then error(SECRET, 0) end
	if fn == ns.ShapeFn and shape == "SQUARE" then return "PASS", L.ST_SHAPE_OK end
	return "FAIL", L.ST_SHAPE_BAD:format(tostring(shape))
end

local function CheckDB()
	local db = ns.db
	if type(db) ~= "table" then return "FAIL", L.ST_DB_BAD:format("MiniMapForeverDB") end
	for _, key in ipairs({ "booksNudge", "zygorLines" }) do
		if db[key] ~= nil and type(db[key]) ~= "boolean" then return "FAIL", L.ST_DB_BAD:format(key) end
	end
	if db.editFit ~= nil and type(db.editFit) ~= "table" then return "FAIL", L.ST_DB_BAD:format("editFit") end
	if db.topEdge ~= nil and type(db.topEdge) ~= "table" then return "FAIL", L.ST_DB_BAD:format("topEdge") end
	if db.topShift ~= nil and type(db.topShift) ~= "table" then return "FAIL", L.ST_DB_BAD:format("topShift") end
	if db.dbVersion ~= nil and type(db.dbVersion) ~= "number" then return "FAIL", L.ST_DB_BAD:format("dbVersion") end
	return "PASS", L.ST_DB_OK
end

-- In order; `map` = only while the square map is ours.
local CHECKS = {
	{ L.ST_N_SPOT, CheckSpot, map = true },
	{ L.ST_N_BOX, CheckBox, map = true },
	{ L.ST_N_TOP, CheckTop, map = true },
	{ L.ST_N_HEADER_ABOVE, CheckHeader, map = true },
	{ L.ST_N_SIDE, CheckSide, map = true },
	{ L.ST_N_MOUSE, CheckMouse, map = true },
	{ L.ST_N_COVER, CheckCover, map = true },
	{ L.ST_N_HOVER, CheckHover, map = true },
	{ L.ST_N_ZOOM, CheckZoom, map = true },
	{ L.ST_N_BORDER, CheckBorder, map = true },
	{ L.ST_N_PLATE, CheckPlate, map = true },
	{ L.ST_N_COORDS, CheckCoords, map = true },
	{ L.ST_N_BAR, CheckBar },
	{ L.ST_N_ZYGOR, CheckZygor, map = true },
	{ L.ST_N_BOOKS, CheckBooks, map = true },
	{ L.ST_N_SHAPE, CheckShape, map = true },
	{ L.ST_N_DB, CheckDB },
}
ST.CHECKS = CHECKS

local function Short(err)
	return (tostring(err):gsub("^.-:%d+: ", ""):sub(1, 60))
end

-- One check in pcall: a secret value -> SKIP, an error -> FAIL "could not check".
local function RunOne(r, name, fn)
	local ok, status, text, name2 = pcall(fn)
	if not ok then
		local err = status
		if err == SECRET or (type(err) == "string" and err:find("secret")) then
			status, text = "SKIP", L.ST_SECRET
		else
			status, text = "FAIL", L.ST_ERROR:format(Short(err))
		end
	end
	if not status then return end
	r.list[#r.list + 1] = { status = status, name = name2 or name, text = text or "" }
	r[status] = r[status] + 1
end

---------------------------------------------------------------------------
-- Output: chat lines, and one line for the copy box.
---------------------------------------------------------------------------
local function Version()
	local meta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
	if meta then
		local ok, v = pcall(meta, ADDON, "Version")
		if ok and type(v) == "string" then return v end
	end
	return "?"
end

local function Plain(s)
	return (tostring(s):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

function ST.Text(r)
	local okB, ver, build = false, nil, nil
	if GetBuildInfo then okB, ver, build = pcall(GetBuildInfo) end
	local parts = {
		("%s selftest %s | game %s (%s) | %s | %d pass, %d fail, %d skip"):format(ADDON, r.version,
			okB and tostring(ver) or "?", okB and tostring(build) or "?", r.under and "header under" or "header above",
			r.PASS, r.FAIL, r.SKIP),
	}
	if r.squareOff then parts[#parts + 1] = "square map off" end
	local passed = {}
	for _, c in ipairs(r.list) do
		if c.status == "PASS" then
			passed[#passed + 1] = c.name
		else
			parts[#parts + 1] = c.status .. " " .. c.name .. ": " .. Plain(c.text)
		end
	end
	if #passed > 0 then parts[#parts + 1] = "PASS: " .. table.concat(passed, ", ") end
	local text = table.concat(parts, " | ")
	if #text > COPY_MAX then text = text:sub(1, COPY_MAX - 3) .. "..." end
	return text
end

-- Our own small box with a one-line edit box; the player copies by hand (Ctrl+C).
local box
local function ShowCopyBox(text)
	if not box then
		local ok, f = pcall(CreateFrame, "Frame", "MiniMapForeverSelfTestBox", UIParent, "BasicFrameTemplateWithInset")
		if not (ok and f) then f = CreateFrame("Frame", "MiniMapForeverSelfTestBox", UIParent, T.backdropTemplate) end
		f:SetSize(520, 80)
		f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
		f:SetFrameStrata("DIALOG")
		f:SetClampedToScreen(true)
		f:EnableMouse(true)
		f:SetMovable(true)
		f:RegisterForDrag("LeftButton")
		f:SetScript("OnDragStart", f.StartMoving)
		f:SetScript("OnDragStop", f.StopMovingOrSizing)
		local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		title:SetPoint("TOP", f, "TOP", 0, -6)
		title:SetText(L.ST_COPY_TITLE)
		local eb = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
		eb:SetAutoFocus(false)
		eb:SetSize(480, 24)
		eb:SetPoint("CENTER", f, "CENTER", 0, -8)
		if eb.SetMaxLetters then eb:SetMaxLetters(0) end
		eb:SetScript("OnEscapePressed", function() f:Hide() end)
		-- Typing doesn't change the text: it goes back and is selected again.
		eb:SetScript("OnTextChanged", function(self, byUser)
			if byUser then
				self:SetText(f.text or "")
				self:HighlightText()
			end
		end)
		f.edit = eb
		box = f
	end
	box.text = text
	box.edit:SetText(text)
	box:Show()
	box.edit:SetFocus()
	box.edit:HighlightText()
end

---------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------
local waiter

local function WaitForCombatEnd()
	if not waiter then waiter = CreateFrame("Frame") end
	waiter:SetScript("OnEvent", function(self)
		self:UnregisterEvent("PLAYER_REGEN_ENABLED")
		self:SetScript("OnEvent", nil)
		ST:Start()
	end)
	waiter:RegisterEvent("PLAYER_REGEN_ENABLED") -- one queued run, however often asked
end

function ST:Start()
	if InCombatLockdown() then
		ns.Print(L.ST_COMBAT)
		return WaitForCombatEnd()
	end
	if InEditMode() then
		ns.Print(L.ST_EDITMODE)
		return
	end
	local r = { list = {}, PASS = 0, FAIL = 0, SKIP = 0, version = Version() }
	local okU, under = pcall(Under)
	r.under = okU and under
	r.squareOff = not ns.Square.active
	ns.Print(L.ST_START)
	if r.squareOff then ns.Print(L.ST_SQUARE_OFF) end
	for _, c in ipairs(CHECKS) do
		if ns.Square.active or not c.map then RunOne(r, c[1], c[2]) end
	end
	local word = { PASS = L.ST_PASS, FAIL = L.ST_FAIL, SKIP = L.ST_SKIP }
	for _, c in ipairs(r.list) do
		ns.Print(L.ST_LINE, word[c.status], c.name, c.text)
	end
	r.result = r.FAIL == 0 and "PASS" or "FAIL"
	ns.Print(L.ST_RESULT .. (r.FAIL > 0 and L.ST_RESULT_FAIL or ""), r.FAIL == 0 and L.ST_PASS or L.ST_FAIL,
		r.PASS, r.FAIL, r.SKIP, r.version)
	r.text = ST.Text(r)
	ST.last = r
	pcall(ShowCopyBox, r.text)
	return r
end
