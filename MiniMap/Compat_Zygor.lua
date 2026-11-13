-- Mini Map: compatibility with Zygor Guides (WoW Forever), "Solid lines" path style.
-- Zygor cuts its solid minimap path line where it meets a circle inside the minimap. On our
-- square map that leaves the line short of the edge. Right after Zygor draws its minimap lines,
-- this moves each cut end outward along the line's own direction, up to the real end point or
-- the square's edge (whichever is nearer), and keeps the dashes the same size.
-- Only Zygor's own unprotected line regions are changed (end points and texture coords); no
-- function is replaced. Path pieces that never come inside Zygor's circle aren't drawn (v1).
-- Plan: plans\zygor-solid-line\plan.md
local ADDON, ns = ...

local Zygor = {}
ns.Zygor = Zygor

local ZYGOR_ADDON = "ZygorGuidesViewerForever" -- folder name
local CIRCLE = 0.95     -- radius (in half map widths) where Zygor cuts its minimap lines
local CUT_TOL = 0.006   -- how close to that circle a line end must be to count as cut
local ON_LINE = 0.004   -- max distance (half map widths) of a line end from its path piece
local EDGE_PAD = 2      -- px kept free inside the square edge (plus half the line's thickness)
local SETS = { "route", "path", "farm" } -- Zygor's point sets that get solid lines

local abs, sqrt, type, pcall, ipairs = math.abs, math.sqrt, type, pcall, ipairs

local hooked, failed, dirty = false, false, false

-- Path pieces of this draw, in reused arrays (no tables made per draw).
local segAx, segAy, segBx, segBy = {}, {}, {}, {}
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

local function AddSeg(ax, ay, bx, by)
	nSeg = nSeg + 1
	segAx[nSeg], segAy[nSeg], segBx[nSeg], segBy[nSeg] = ax, ay, bx, by
end

local function BuildSegments(sets)
	nSeg = 0
	for _, name in ipairs(SETS) do
		local set = sets[name]
		local points = type(set) == "table" and set.points
		if type(points) == "table" then
			local n = #points
			local px, py
			local last = (set.loop and n > 1) and n + 1 or n
			for i = 1, last do
				local x, y = PointXY(points[i > n and 1 or i])
				if x and px then AddSeg(px, py, x, y) end
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

local function Stretch(pointer)
	if type(pointer) ~= "table" then return end
	if not Zygor.enabled or not ShapeIsSquare()
		or ProfileValue("maplines_enabled") == false or ProfileValue("maplines") ~= 2 then
		if dirty then Restore(pointer) end
		return
	end
	if type(pointer.pointsets) ~= "table" then return end
	hw, hh = Minimap:GetWidth() / 2, Minimap:GetHeight() / 2
	if not (hw > 0 and hh > 0) then return end
	BuildSegments(pointer.pointsets)
	if nSeg == 0 then return end
	-- with Zygor's "repeat" off the texture is stretched once along the line: don't rescale
	rescaleNow = ProfileValue("maplines_repeat") ~= false
	EachFill(pointer, WorkOne)
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
		ns.Print(ns.L.ZYGOR_BROKEN)
	end
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
	hooked = true
	return true
end

-- Safe to call again (PLAYER_LOGIN, Zygor's ADDON_LOADED, /mmap zygoron|zygoroff).
function Zygor:Setup()
	self.enabled = Zygor.ShouldRun()
	if self.enabled and not InstallHook() then self.enabled = false end
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
