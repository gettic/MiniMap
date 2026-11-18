-- Mini Map: compatibility with Zygor Guides (WoW Forever), "Solid lines" path style.
-- Zygor cuts its solid minimap path line where it meets a circle inside the minimap. On our
-- square map that leaves the line short of the edge. Right after Zygor draws its minimap lines,
-- this moves each cut end outward along the line's own direction, up to the real end point or
-- the square's edge (whichever is nearer), and keeps the dashes the same size.
-- Only Zygor's own unprotected line regions are changed (end points and texture coords); no
-- function is replaced. Path pieces that never come inside Zygor's circle (they only pass
-- through a corner) get no line from Zygor; we draw those with our own lines (Blizzard's line
-- art from Theme.lua, in the path's colour, not animated).
-- Plans: plans\_old\zygor-solid-line\plan.md, plans\zygor-corners\plan.md
local ADDON, ns = ...

local Zygor = {}
ns.Zygor = Zygor

local ZYGOR_ADDON = "ZygorGuidesViewerForever" -- folder name
local CIRCLE = 0.95     -- radius (in half map widths) where Zygor cuts its minimap lines
local CUT_TOL = 0.006   -- how close to that circle a line end must be to count as cut
local ON_LINE = 0.004   -- max distance (half map widths) of a line end from its path piece
local EDGE_PAD = 2      -- px kept free inside the square edge (plus half the line's thickness)
local SETS = { "route", "path", "farm" } -- Zygor's point sets that get solid lines

local abs, sqrt, max, type, pcall, ipairs = math.abs, math.sqrt, math.max, type, pcall, ipairs

local hooked, failed, dirty = false, false, false

-- Path pieces of this draw, in reused arrays (no tables made per draw).
local segAx, segAy, segBx, segBy = {}, {}, {}, {}
local segSet = {}  -- [k] = index in SETS (neighbours are looked for in the same set only)
local segFill = {} -- [k] = Zygor's line texture drawn for this piece, or false
local nSeg = 0

-- Texture u range per line texture: Zygor's (base) and ours (written).
local texState = setmetatable({}, { __mode = "k" }) -- [Fill] = { bu1, bu2, wu1, wu2 }

---------------------------------------------------------------------------
-- Maths (own code)
---------------------------------------------------------------------------

-- Liang-Barsky: part of A->B inside the box [-q, q]^2 as params t0, t1 (0..1), or nil.
-- One box side: narrows (t0, t1); returns nil when nothing is left.
local function ClipSide(p, r, t0, t1)
	if p == 0 then
		if r < 0 then return nil end
		return t0, t1
	end
	local t = r / p
	if p < 0 then
		if t > t1 then return nil end
		if t > t0 then t0 = t end
	else
		if t < t0 then return nil end
		if t < t1 then t1 = t end
	end
	return t0, t1
end

function Zygor.ClipToBox(ax, ay, bx, by, q)
	local dx, dy = bx - ax, by - ay
	local t0, t1 = ClipSide(-dx, ax + q, 0, 1)
	if t0 then t0, t1 = ClipSide(dx, q - ax, t0, t1) end
	if t0 then t0, t1 = ClipSide(-dy, ay + q, t0, t1) end
	if t0 then t0, t1 = ClipSide(dy, q - ay, t0, t1) end
	return t0, t1
end

local function IsCut(x, y)
	return abs(sqrt(x * x + y * y) - CIRCLE) < CUT_TOL
end

-- Param of point (px, py) along A->B, or nil when it isn't on that piece.
local function ParamOn(k, px, py)
	local ax, ay = segAx[k], segAy[k]
	local dx, dy = segBx[k] - ax, segBy[k] - ay
	local l2 = dx * dx + dy * dy
	if l2 < 1e-10 then return nil end
	local off = abs(dx * (py - ay) - dy * (px - ax)) / sqrt(l2)
	if off > ON_LINE then return nil end
	local t = ((px - ax) * dx + (py - ay) * dy) / l2
	if t < -0.01 or t > 1.01 then return nil end
	return t
end

-- The one path piece both ends lie on (identical copies count as one), or nil.
local function FindSegment(sx, sy, ex, ey)
	local found, ts, te
	for k = 1, nSeg do
		local a = ParamOn(k, sx, sy)
		local b = a and ParamOn(k, ex, ey)
		if b then
			if not found then
				found, ts, te = k, a, b
			elseif abs(segAx[k] - segAx[found]) > 1e-6 or abs(segAy[k] - segAy[found]) > 1e-6
				or abs(segBx[k] - segBx[found]) > 1e-6 or abs(segBy[k] - segBy[found]) > 1e-6 then
				return nil -- two different pieces fit: leave the line alone
			end
		end
	end
	return found, ts, te
end

---------------------------------------------------------------------------
-- Reading Zygor's path (every lookup checked)
---------------------------------------------------------------------------

local function PointXY(p)
	if type(p) ~= "table" then return nil end
	local f = p.frame_minimapfar
	if type(f) ~= "table" or type(f.IsShown) ~= "function" or not f:IsShown() then return nil end
	local x, y = f.minimap_x, f.minimap_y
	if type(x) ~= "number" or type(y) ~= "number" then return nil end
	return x, y
end

local function AddSeg(ax, ay, bx, by, setIndex)
	nSeg = nSeg + 1
	segAx[nSeg], segAy[nSeg], segBx[nSeg], segBy[nSeg] = ax, ay, bx, by
	segSet[nSeg], segFill[nSeg] = setIndex, false
end

local function BuildSegments(sets)
	nSeg = 0
	for setIndex, name in ipairs(SETS) do
		local set = sets[name]
		local points = type(set) == "table" and set.points
		if type(points) == "table" then
			local n = #points
			local px, py
			local last = (set.loop and n > 1) and n + 1 or n
			for i = 1, last do
				local x, y = PointXY(points[i > n and 1 or i])
				if x and px then AddSeg(px, py, x, y, setIndex) end
				px, py = x, y
			end
		end
	end
end

---------------------------------------------------------------------------
-- Changing a line
---------------------------------------------------------------------------

local function ProfileValue(key)
	local zgv = _G.ZygorGuidesViewer
	local db = type(zgv) == "table" and zgv.db
	local profile = type(db) == "table" and db.profile
	if type(profile) ~= "table" then return nil end
	return profile[key]
end

-- Texture coords: keep the dash size. Zygor sometimes skips setting them again when nothing
-- changed for it, so coords that still have our span are ours: use Zygor's stored ones.
local function Rescale(fill, addStart, addEnd)
	local c1, c2, c3, c4, c5, c6, c7, c8 = fill:GetTexCoord()
	if type(c1) ~= "number" or type(c5) ~= "number" then return end
	local st = texState[fill]
	local bu1, bu2
	if st and st[3] and abs((c5 - c1) - (st[4] - st[3])) < 1e-4 then
		local shift = c1 - st[3] -- texture scrolling may have moved them
		bu1, bu2 = st[1] + shift, st[2] + shift
	else
		bu1, bu2 = c1, c5
		if not st then st = {}; texState[fill] = st end
		st[1], st[2] = bu1, bu2
	end
	local du = bu2 - bu1
	local u1, u2 = bu1 - du * addStart, bu2 + du * addEnd
	fill:SetTexCoord(u1, c2, u1, c4, u2, c6, u2, c8)
	st[3], st[4] = u1, u2
	dirty = true
end

-- Puts Zygor's own coords back on a line we changed earlier but don't change now.
local function Unscale(fill)
	local st = texState[fill]
	if not st or not st[3] then return end
	local c1, c2, c3, c4, c5, c6, c7, c8 = fill:GetTexCoord()
	if type(c1) == "number" and type(c5) == "number" and abs((c5 - c1) - (st[4] - st[3])) < 1e-4 then
		local shift = c1 - st[3]
		fill:SetTexCoord(st[1] + shift, c2, st[1] + shift, c4, st[2] + shift, c6, st[2] + shift, c8)
	end
	st[3], st[4] = nil, nil
end

-- One line: returns true if it was stretched.
local function StretchLine(fill, hw, hh, rescale)
	local sp, srel, sx, sy = fill:GetStartPoint()
	local ep, erel, ex, ey = fill:GetEndPoint()
	if type(sx) ~= "number" or type(sy) ~= "number" or type(ex) ~= "number" or type(ey) ~= "number" then
		return false
	end
	-- to map units (Zygor's: x right, y down, 1 = half the map)
	local ux, uy, vx, vy = sx / hw, -sy / hh, ex / hw, -ey / hh
	local sCut, eCut = IsCut(ux, uy), IsCut(vx, vy)
	if not sCut and not eCut then return false end

	local k, ts, te = FindSegment(ux, uy, vx, vy)
	if not k or abs(te - ts) < 1e-6 then return false end

	local thick = (fill.GetThickness and fill:GetThickness()) or 5
	if type(thick) ~= "number" then thick = 5 end
	local q = 1 - (thick / 2 + EDGE_PAD) / hw
	local t0, t1 = Zygor.ClipToBox(segAx[k], segAy[k], segBx[k], segBy[k], q)
	if not t0 then return false end

	-- the end with the lower param goes toward t0, the other toward t1; only ever outward
	local nts, nte = ts, te
	if ts <= te then
		if sCut and t0 < ts then nts = t0 end
		if eCut and t1 > te then nte = t1 end
	else
		if sCut and t1 > ts then nts = t1 end
		if eCut and t0 < te then nte = t0 end
	end
	if nts == ts and nte == te then return false end

	local ax, ay = segAx[k], segAy[k]
	local dx, dy = segBx[k] - ax, segBy[k] - ay
	if nts ~= ts then
		fill:SetStartPoint(sp, srel, (ax + dx * nts) * hw, -(ay + dy * nts) * hh)
	end
	if nte ~= te then
		fill:SetEndPoint(ep, erel, (ax + dx * nte) * hw, -(ay + dy * nte) * hh)
	end
	if rescale then
		local span = abs(te - ts)
		Rescale(fill, abs(nts - ts) / span, abs(nte - te) / span)
	end
	return true
end

local function ShapeIsSquare()
	return ns.Square.active and GetMinimapShape and GetMinimapShape() == "SQUARE"
end

-- Every active minimap line of Zygor's; work(fill) for each.
local function EachFill(pointer, work)
	local pool = pointer.mapLinePoolMini
	if type(pool) ~= "table" or type(pool.EnumerateActive) ~= "function" then return end
	for line in pool:EnumerateActive() do
		local fill = type(line) == "table" and line.Fill
		if type(fill) == "table" and type(fill.GetStartPoint) == "function" then
			work(fill)
		end
	end
end

local function Restore(pointer)
	EachFill(pointer, Unscale)
	dirty = false
end

local hw, hh, rescaleNow
local function WorkOne(fill)
	if not StretchLine(fill, hw, hh, rescaleNow) then Unscale(fill) end
end

---------------------------------------------------------------------------
-- Corner pieces: our own lines (plain frame + Line regions on Minimap)
---------------------------------------------------------------------------

local MAX_LINES = 32  -- never more of our own lines than this
local MIN_PX = 2      -- skip slivers shorter than this
local holder          -- our unnamed frame over the minimap, made on first use
local lines = {}      -- our Line regions, reused
local used = 0        -- how many are shown now
local lastDraw, timeout = 0, 1

local function HideCorners()
	for i = 1, #lines do lines[i]:Hide() end
	used = 0
	if holder then holder:SetScript("OnUpdate", nil) end
end
Zygor.HideCorners = HideCorners

-- Hides our lines when Zygor stops redrawing (another waypoint addon, path gone...).
local function Watchdog()
	if GetTime() - lastDraw > timeout then HideCorners() end
end

local function NewLine()
	if not holder then
		holder = CreateFrame("Frame", nil, Minimap)
		holder:SetAllPoints(Minimap)
		holder:EnableMouse(false)
	end
	local line = holder:CreateLine(nil, "BACKGROUND")
	local art = ns.Theme.pathLine
	ns.Theme.SetAtlasOr(line, art.atlas, art.file)
	lines[#lines + 1] = line
	return line
end

-- Closest distance of piece k to the map centre (map units).
local function SegDist(k)
	local ax, ay = segAx[k], segAy[k]
	local dx, dy = segBx[k] - ax, segBy[k] - ay
	local l2 = dx * dx + dy * dy
	local t = 0
	if l2 > 1e-12 then
		t = -(ax * dx + ay * dy) / l2
		if t < 0 then t = 0 elseif t > 1 then t = 1 end
	end
	local px, py = ax + dx * t, ay + dy * t
	return sqrt(px * px + py * py)
end

-- Notes which piece each of Zygor's lines belongs to (for colours).
local function MatchFill(fill)
	local _, _, sx, sy = fill:GetStartPoint()
	local _, _, ex, ey = fill:GetEndPoint()
	if type(sx) ~= "number" or type(sy) ~= "number" or type(ex) ~= "number" or type(ey) ~= "number" then return end
	local k = FindSegment(sx / hw, -sy / hh, ex / hw, -ey / hh)
	if k then segFill[k] = fill end
end

local function Num(v, fallback)
	if type(v) == "number" then return v end
	return fallback
end

-- Colour, alpha and thickness of piece k: from the nearest Zygor line in the same set,
-- else Zygor's default path colour and settings.
local function NeighbourFill(k, j)
	return j >= 1 and j <= nSeg and segSet[j] == segSet[k] and segFill[j] or nil
end

local function StyleFor(pointer, k)
	for step = 1, nSeg do
		local fill = NeighbourFill(k, k - step) or NeighbourFill(k, k + step)
		if fill then
			local r, g, b = fill:GetVertexColor()
			local parent = fill.GetParent and fill:GetParent()
			local a = parent and parent.GetAlpha and parent:GetAlpha()
			local th = fill.GetThickness and fill:GetThickness()
			return Num(r, 1), Num(g, 1), Num(b, 1), Num(a, 1), Num(th, 5)
		end
	end
	local r, g, b = 1, 1, 1
	local icons = type(pointer.Icons) == "table" and pointer.Icons
	local icon = icons and type(icons.ant_default) == "table" and icons.ant_default
	if icon then
		local tex = type(icon.tex) == "table" and icon.tex
		r = Num(icon.r, tex and Num(tex.r, 1) or 1)
		g = Num(icon.g, tex and Num(tex.g, 1) or 1)
		b = Num(icon.b, tex and Num(tex.b, 1) or 1)
	end
	return r, g, b, Num(ProfileValue("minimap_maplines_opacity"), 1), Num(ProfileValue("maplines_thickness"), 5)
end

-- Frame level of Zygor's minimap lines (first one found).
local zygorLevel
local function ReadLevel(fill)
	if zygorLevel then return end
	local parent = fill.GetParent and fill:GetParent()
	if parent and parent.GetFrameLevel then zygorLevel = parent:GetFrameLevel() end
end

local function DrawCorners(pointer)
	local matched = false
	for k = 1, nSeg do
		if used >= MAX_LINES then break end
		if SegDist(k) >= CIRCLE - CUT_TOL then
			if not matched then EachFill(pointer, MatchFill); matched = true end
			local r, g, b, a, thick = StyleFor(pointer, k)
			local art = ns.Theme.pathLine
			thick = thick * (art.thicknessScale or 1)
			local q = 1 - (thick / 2 + EDGE_PAD) / hw
			local t0, t1 = Zygor.ClipToBox(segAx[k], segAy[k], segBx[k], segBy[k], q)
			if t0 then
				local ax, ay = segAx[k], segAy[k]
				local dx, dy = segBx[k] - ax, segBy[k] - ay
				local x0, y0 = (ax + dx * t0) * hw, -(ay + dy * t0) * hh
				local x1, y1 = (ax + dx * t1) * hw, -(ay + dy * t1) * hh
				if (x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0) >= MIN_PX * MIN_PX then
					used = used + 1
					local line = lines[used] or NewLine()
					line:SetStartPoint("CENTER", holder, x0, y0)
					line:SetEndPoint("CENTER", holder, x1, y1)
					line:SetThickness(thick)
					line:SetVertexColor(r, g, b, 1)
					line:SetAlpha(a * (art.alpha or 1))
					line:Show()
				end
			end
		end
	end
	if used > 0 then
		-- same depth as Zygor's lines
		zygorLevel = nil
		EachFill(pointer, ReadLevel)
		local level = zygorLevel or (Minimap:GetFrameLevel() + 1)
		if holder:GetFrameLevel() ~= level then holder:SetFrameLevel(level) end
		local strata = Minimap:GetFrameStrata()
		if holder:GetFrameStrata() ~= strata then holder:SetFrameStrata(strata) end
		local speed = Num(ProfileValue("antspeed"), 30)
		timeout = (speed > 0) and max(0.5, 2 / speed) or 2
		lastDraw = GetTime()
		holder:SetScript("OnUpdate", Watchdog)
	end
	for i = used + 1, #lines do lines[i]:Hide() end
	if used == 0 and holder then holder:SetScript("OnUpdate", nil) end
end

local function Stretch(pointer)
	if type(pointer) ~= "table" then return end
	if not Zygor.enabled or not ShapeIsSquare()
		or ProfileValue("maplines_enabled") == false or ProfileValue("maplines") ~= 2 then
		if used > 0 then HideCorners() end
		if dirty then Restore(pointer) end
		return
	end
	used = 0
	if type(pointer.pointsets) ~= "table" then HideCorners() return end
	hw, hh = Minimap:GetWidth() / 2, Minimap:GetHeight() / 2
	if not (hw > 0 and hh > 0) then HideCorners() return end
	BuildSegments(pointer.pointsets)
	if nSeg == 0 then HideCorners() return end
	-- with Zygor's "repeat" off the texture is stretched once along the line: don't rescale
	rescaleNow = ProfileValue("maplines_repeat") ~= false
	EachFill(pointer, WorkOne)
	DrawCorners(pointer)
end

-- Runs right after Zygor's own UpdateMapLines. Never lets an error reach Zygor's code: the
-- first error switches this off (until /reload) with one short chat line.
local function AfterDraw(pointer)
	if failed then return end
	local ok, err = pcall(Stretch, pointer)
	if not ok then
		failed = true
		Zygor.enabled = false
		Zygor.lastError = err
		pcall(HideCorners)
		ns.Print(ns.L.ZYGOR_BROKEN)
	end
end

-- Zygor cleared its lines without drawing new ones: ours go too.
local function AfterClear()
	pcall(HideCorners)
end
Zygor.AfterDraw = AfterDraw -- for tests

---------------------------------------------------------------------------
-- Set-up and /mmap zygoron | zygoroff
---------------------------------------------------------------------------

function Zygor.IsZygorLoaded()
	return ns.IsLoaded(ZYGOR_ADDON) and true or false
end

function Zygor.ShouldRun()
	return ns.db and ns.db.zygorLines ~= false and ns.Square.active and not failed
		and Zygor.IsZygorLoaded() and true or false
end

local function InstallHook()
	if hooked then return true end
	local zgv = _G.ZygorGuidesViewer
	local pointer = type(zgv) == "table" and zgv.Pointer
	if type(pointer) ~= "table" or type(pointer.UpdateMapLines) ~= "function" then return false end
	hooksecurefunc(pointer, "UpdateMapLines", AfterDraw)
	for _, name in ipairs({ "ClearMapLines", "ClearAntsAndLines" }) do
		if type(pointer[name]) == "function" then hooksecurefunc(pointer, name, AfterClear) end
	end
	hooked = true
	return true
end

-- /mmap selftest: hook installed, fix running, switched off after an error. Read only.
function Zygor.State()
	return hooked, Zygor.enabled and true or false, failed
end

-- Safe to call again (PLAYER_LOGIN, Zygor's ADDON_LOADED, /mmap zygoron|zygoroff).
function Zygor:Setup()
	self.enabled = Zygor.ShouldRun()
	if self.enabled and not InstallHook() then self.enabled = false end
	if not self.enabled then HideCorners() end
	-- when off, the hook stays but only puts Zygor's own texture coords back once
end

function Zygor:SetOn(on)
	if ns.db then ns.db.zygorLines = on and true or false end
	self:Setup()
	if not on then
		ns.Print(ns.L.ZYGOR_OFF)
	elseif self.enabled then
		ns.Print(ns.L.ZYGOR_ON)
	else
		ns.Print(ns.L.ZYGOR_ON_IDLE)
	end
end
