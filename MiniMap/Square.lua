-- Mini Map: makes Blizzard's minimap square, in place.
-- Nothing is reparented: the map stays inside MinimapCluster so Edit Mode keeps moving and
-- sizing it. Blizzard code is only followed with hooksecurefunc, never replaced.
local ADDON, ns = ...
local T = ns.Theme

local Square = {}
ns.Square = Square

local function Container()
	return MinimapCluster and MinimapCluster.MinimapContainer
end

-- The client draws a round ring along the map edge around big quest / dig-site / task areas.
-- Hide those rings (the area fill stays), then let the client place its blips again.
-- Every call is checked first (the client may lack some) and wrapped in pcall; never in combat.
local RING_SETTERS = {
	"SetArchBlobRingScalar", "SetArchBlobRingAlpha",
	"SetQuestBlobRingScalar", "SetQuestBlobRingAlpha",
	"SetTaskBlobRingScalar", "SetTaskBlobRingAlpha",
}

local function HideBlobRings()
	if not Minimap or InCombatLockdown() then return end
	for _, method in ipairs(RING_SETTERS) do
		if type(Minimap[method]) == "function" then
			pcall(Minimap[method], Minimap, 0)
		end
	end
	if type(Minimap.UpdateBlips) == "function" then
		pcall(Minimap.UpdateBlips, Minimap)
	end
end

-- Square mask on the minimap and, when it is loaded, on the hybrid minimap.
function Square:ApplyMask()
	if Minimap and Minimap.SetMaskTexture then
		Minimap:SetMaskTexture(T.mask)
	end
	local hybrid = HybridMinimap
	if hybrid and hybrid.CircleMask and hybrid.CircleMask.SetTexture then
		hybrid.CircleMask:SetTexture(T.mask, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	end
	HideBlobRings()
end

local function Silence(tex)
	if tex then
		tex:SetAlpha(0)
		tex:Hide()
	end
end

-- Hides Blizzard's round frame and the rotate-mode ring underlay.
function Square:HideRoundArt()
	Silence(MinimapCompassTexture)
	Silence(MinimapCompassTextureUnderlay)
end

-- Run after Blizzard re-applies its round look (Rotate Minimap on/off).
function Square:Reapply()
	if not self.active then return end
	self:ApplyMask()
	self:HideRoundArt()
end

-- Our border around the map. A child of Minimap, so it follows Edit Mode position,
-- size and the map being hidden.
function Square:CreateBorder()
	if self.border then return end
	local b = CreateFrame("Frame", "MiniMapForeverBorder", Minimap, T.backdropTemplate)
	b:EnableMouse(false)
	T.ApplyBorder(b) -- first: the outsets depend on which border kind the client supports
	local oL, oR, oT, oB = T.BorderOutset(b)
	b:SetPoint("TOPLEFT", Minimap, "TOPLEFT", -oL, oT)
	b:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", oR, -oB)
	self.border = b
end

-- Player coordinates go inside the map's bottom edge so they don't sit on the icon bar.
function Square:PlaceCoords()
	local c = Container()
	local coords = c and c.PlayerCoords
	if not (coords and coords.ClearAllPoints) then return end
	coords:ClearAllPoints()
	coords:SetPoint("BOTTOM", Minimap, "BOTTOM", 0, T.coordsOffsetY)
	coords:SetFrameLevel(Minimap:GetFrameLevel() + T.coordsLevel)
end

-- Dark box behind Blizzard's coordinates (our own frame, under the text). Blizzard writes the
-- text every 0.1 s (or "" when off / no position) and never hides the frame itself, so the box
-- follows the text's size. Driven by HookScript on PlayerCoords (no fields on Blizzard frames),
-- with our own 0.1 s throttle; the first error turns the box off for good (one chat line).
local boxWait, boxW, boxH, boxBroken = 0, nil, nil, false

local function UpdateCoordsBox()
	local box, coords = Square.coordsBox, Square.coordsFrame
	local text = coords and coords.CoordText
	if not (box and text) then return end
	local s = text:GetText()
	if not s or s == "" or not coords:IsVisible() then
		box:Hide()
		return
	end
	local c = T.coordsBox
	local w = text:GetStringWidth() + 2 * c.padX
	local h = text:GetStringHeight() + 2 * c.padY
	if w ~= boxW or h ~= boxH then
		boxW, boxH = w, h
		box:SetSize(w, h)
	end
	box:Show()
end

local function CoordsTick(_, elapsed)
	if boxBroken then return end
	boxWait = boxWait - (elapsed or 0)
	if boxWait > 0 then return end
	boxWait = T.coordsBox.throttle
	-- SafeRun: error window + one chat line; then off until /reload (no error loop).
	if not ns.SafeRun("CoordsBox", UpdateCoordsBox) then
		boxBroken = true
		if Square.coordsBox then Square.coordsBox:Hide() end
	end
end

local function CoordsHidden()
	if Square.coordsBox then Square.coordsBox:Hide() end
end

function Square:CreateCoordsBox()
	if self.coordsBox then return end
	local c = Container()
	local coords = c and c.PlayerCoords
	local text = coords and coords.CoordText
	if not (text and coords.HookScript and text.GetStringWidth) then return end
	local box = CreateFrame("Frame", "MiniMapForeverCoordsBox", Minimap)
	box:EnableMouse(false)
	box:SetFrameLevel(Minimap:GetFrameLevel() + T.coordsBoxLevel) -- under PlayerCoords
	local tex = box:CreateTexture(nil, "BACKGROUND")
	tex:SetAllPoints(box)
	T.SetAtlasOr(tex, T.coordsBox.atlas, T.coordsBox.file or T.coordsBox.fallback)
	if not tex:GetTexture() and not (tex.GetAtlas and tex:GetAtlas()) then
		tex:SetTexture(T.coordsBox.fallback)
	end
	tex:SetVertexColor(unpack(T.coordsBox.color))
	box:SetPoint("CENTER", text, "CENTER", 0, 0)
	box:Hide()
	self.coordsBox, self.coordsFrame = box, coords
	coords:HookScript("OnUpdate", CoordsTick)
	coords:HookScript("OnHide", CoordsHidden)
end

-- /mmap selftest: whether the box switched itself off after an error, the box, the coords frame.
function Square.CoordsState()
	return boxBroken, Square.coordsBox, Square.coordsFrame
end

---------------------------------------------------------------------------
-- Header strip, mail/compartment corners, day/night disc
-- Only Blizzard's child pieces are moved (ZoneTextButton, IndicatorFrame,
-- AddonCompartmentFrame, DielFrame); MinimapCluster itself is never moved or scaled,
-- and nothing is written onto Blizzard frames: our state lives in `Square`.
---------------------------------------------------------------------------
-- Edit Mode's "Header Underneath" setting (header below the map, icon bar above it).
function Square.HeaderIsUnderneath()
	if MinimapCluster and MinimapCluster.GetSettingValueBool and Enum and Enum.EditModeMinimapSetting then
		local ok, value = pcall(MinimapCluster.GetSettingValueBool, MinimapCluster, Enum.EditModeMinimapSetting.HeaderUnderneath)
		if ok then return value and true or false end
	end
	return false
end

local function Usable(f)
	return f and f.ClearAllPoints and not (f.IsForbidden and f:IsForbidden()) and not (f.IsProtected and f:IsProtected())
end

-- Stand-ins: Blizzard sizes MinimapCluster (ResizeLayoutFrame) to its shown direct children.
-- Moving its children into the map shrank that box at the next re-layout (Header Underneath),
-- and the map jumped. Each moved child gets an invisible frame of ours at the child's own
-- Blizzard anchors, size and scale, shown when it is, so the box stays Blizzard's.
-- Copied only on the setup / UpdateMinimapConfig / SetHeaderUnderneath path (Square.copying),
-- never during a size change or Blizzard's layout. Plain frames: no layout fields, no templates.
local standIns = {}

local function OursOrMap(rel)
	return rel ~= nil and (rel == Minimap or rel == Square.header or rel == Square.border
		or (MinimapCluster and rel == standIns[Container()]))
end

-- OnShow/OnHide of the Blizzard child: touches only our stand-in.
local function MirrorShown(f)
	local s = standIns[f]
	if s then s:SetShown(f:IsShown()) end
end

-- Call before moving f. ownScale: we rescale f ourselves, so keep Blizzard's scale.
-- w, h: Blizzard's own size when we resize f ourselves (the zone button), else f's size.
local function StandIn(f, ownScale, w, h)
	if not Square.copying then return end
	if not (Usable(f) and MinimapCluster and f:GetParent() == MinimapCluster) then return end
	local s = standIns[f]
	if not s then
		s = CreateFrame("Frame", nil, MinimapCluster)
		s:EnableMouse(false)
		standIns[f] = s
		f:HookScript("OnShow", MirrorShown)
		f:HookScript("OnHide", MirrorShown)
	end
	local n = f:GetNumPoints()
	local _, rel = f:GetPoint(1)
	if n > 0 and not OursOrMap(rel) then -- still Blizzard's anchors: copy them
		s:ClearAllPoints()
		for i = 1, n do
			local p, r, rp, x, y = f:GetPoint(i)
			s:SetPoint(p, r, rp, x, y)
		end
		if ownScale then s:SetScale(f:GetScale()) end
	end
	if not ownScale then s:SetScale(f:GetScale()) end
	if w and h then s:SetSize(w, h) else s:SetSize(f:GetSize()) end
	s:SetShown(f:IsShown())
end

-- Our strip behind the header: a child of our border (hides with the map), same look as the bar.
function Square:CreateHeader()
	if self.header or not self.border then return end
	local h = CreateFrame("Frame", "MiniMapForeverHeader", self.border, T.backdropTemplate)
	h:EnableMouse(false)
	T.ApplyBorder(h, true)
	T.AddBackground(h)
	self.header = h
end

-- Blizzard's own zone button size and zone text width, read once (the first PlaceHeader runs
-- before we ever widen it). The stand-in keeps this size, so the cluster's layout never changes.
local zoneBase
local function ZoneBase(zone)
	if not zoneBase then
		local text = MinimapZoneText
		local tw = text and text.GetWidth and text:GetWidth()
		local w, h = zone:GetSize()
		zoneBase = { w = w, h = h, textW = (tw and tw > 0) and tw or nil }
	end
	return zoneBase
end

-- Our zone/clock plate: T.zonePlate's atlas cut in 3 (left end, stretched middle, right end)
-- on our own frame behind Blizzard's zone button, SetAllPoints on it. Made once; false when
-- the atlas can't be used (then the zone button keeps Blizzard's plate and width).
function Square:MakeZonePlate(zone, height)
	if self.zonePlate ~= nil then return self.zonePlate end
	local P = T.zonePlate
	local si = P and P.on and T.SliceInfo({ atlas = P.atlas, share = P.share })
	if not (si and self.header) then
		self.zonePlate = false
		return false
	end
	local f = CreateFrame("Frame", "MiniMapForeverZonePlate", self.header)
	f:EnableMouse(false)
	f:SetAllPoints(zone)
	local du = si.R - si.L
	local a, b = si.m[1] / si.w, 1 - si.m[3] / si.w -- end shares of the atlas width
	local k = height / si.h -- atlas units -> own units, keeps the ends' shape
	local function Piece(u1, u2)
		local t = f:CreateTexture(nil, "BACKGROUND")
		t:SetTexture(si.file)
		t:SetTexCoord(si.L + du * u1, si.L + du * u2, si.T, si.B)
		return t
	end
	local left, mid, right = Piece(0, a), Piece(a, b), Piece(b, 1)
	left:SetPoint("TOPLEFT")
	left:SetPoint("BOTTOMLEFT")
	left:SetWidth(math.max(1, si.m[1] * k))
	right:SetPoint("TOPRIGHT")
	right:SetPoint("BOTTOMRIGHT")
	right:SetWidth(math.max(1, si.m[3] * k))
	mid:SetPoint("TOPLEFT", left, "TOPRIGHT")
	mid:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT")
	self.zonePlate = f
	return f
end

-- Screen x of a frame's left and right edge (pcall), or nil when it has no rect.
local function ScreenLR(f)
	if not (f and f.GetLeft and f.GetEffectiveScale) then return end
	local ok, l, r, es = pcall(function() return f:GetLeft(), f:GetRight(), f:GetEffectiveScale() end)
	if ok and type(l) == "number" and type(r) == "number" and type(es) == "number" and es > 0 then
		return l * es, r * es
	end
end

-- Screen x span of the tracking button (its 17 px frame and the 23 px button in it).
local function TrackingLR()
	local tr = MinimapCluster and MinimapCluster.Tracking
	local l, r
	for _, f in ipairs({ tr or false, tr and tr.Button or false }) do
		local a, b = ScreenLR(f or nil)
		if a then
			l = (l and math.min(l, a)) or a
			r = (r and math.max(r, b)) or b
		end
	end
	return l, r
end

-- How far tracking (left) and the calendar (right) reach past the zone button, in zone units,
-- measured from their rects (Blizzard anchors them to the zone button, so this doesn't depend
-- on where the zone sits); `reserveL` / `reserveR` when a rect can't be read.
local function SideExtents(zone)
	local P = T.zonePlate
	local left, right = P.reserveL, P.reserveR
	local zl, zr = ScreenLR(zone)
	local zs = zone:GetEffectiveScale()
	if zl and zs and zs > 0 then
		local tl = TrackingLR()
		if tl then left = math.max(0, (zl - tl) / zs) end
		local _, cr = ScreenLR(GameTimeFrame)
		if cr then right = math.max(0, (cr - zr) / zs) end
	end
	return left, right
end

-- Zone button as wide as the strip allows (between tracking and calendar), never narrower
-- than Blizzard's; zone text grows by the same amount. Blizzard's own plate texture is made
-- invisible (ours is drawn instead), its hover glow covers the whole button. Then the whole
-- group (tracking, zone, calendar) is centred in the strip by the zone's LEFT edge, so the
-- space left and right is the same. Without our plate the width stays Blizzard's (only
-- centred). Only SetWidth / ClearAllPoints / SetPoint / SetAllPoints / SetAlpha, out of combat
-- (square-pieces job). The strip's units are the zone's units (same effective scale).
function Square:PlaceZone(zone, h, base, under, textY)
	local P = T.zonePlate
	local plate = self:MakeZonePlate(zone, base.h)
	local left, right = SideExtents(zone)
	local stripW = h:GetWidth()
	local w = base.w
	if plate then
		w = math.max(base.w, math.floor(stripW - 2 * P.sidePad - left - right))
		-- Over the strip's background, under the zone button's text and the clock.
		local hl, zl = h:GetFrameLevel(), zone:GetFrameLevel()
		plate:SetFrameLevel(math.max(hl, math.min(hl + 1, zl - 1)))
		if zone.StateTexture and zone.StateTexture.SetAlpha then zone.StateTexture:SetAlpha(0) end
		local add = zone.AddTexture
		if add and add.ClearAllPoints then
			add:ClearAllPoints()
			add:SetAllPoints(zone)
		end
		zone:SetWidth(w)
		local text = MinimapZoneText
		if text and text.SetWidth and base.textW then text:SetWidth(base.textW + (w - base.w)) end
	end
	local x = (stripW - (left + w + right)) / 2 + left
	zone:ClearAllPoints()
	if under then
		zone:SetPoint("TOPLEFT", h, "TOPLEFT", x, -textY)
	else
		zone:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", x, textY)
	end
	self.zoneWidth, self.zoneX, self.zoneExtents = w, x, { left, right }
end

-- `/mmap debug`: screen x of the strip, tracking, zone button and calendar (L-R), and the
-- empty space left and right of the group inside the strip.
function Square.HeaderDebug()
	local function Span(l, r) return l and string.format("%.1f-%.1f", l, r) or "-" end
	local hl, hr = ScreenLR(Square.header)
	local tl, tr = TrackingLR()
	local zl, zr = ScreenLR(MinimapCluster and MinimapCluster.ZoneTextButton)
	local cl, cr = ScreenLR(GameTimeFrame)
	local gl, gr = "-", "-"
	if hl and zl then
		gl = string.format("%.1f", math.min(tl or zl, zl) - hl)
		gr = string.format("%.1f", hr - math.max(cr or zr, zr))
	end
	return Span(hl, hr), Span(tl, tr), Span(zl, zr), Span(cl, cr), gl, gr
end

-- The strip goes on the side away from the icon bar, 2 px from the border; Blizzard's zone
-- button (with tracking and clock anchored to it) is put in it (first centred, so tracking
-- and calendar can be measured), then widened and the whole group centred (PlaceZone).
function Square:PlaceHeader(under)
	local zone = MinimapCluster and MinimapCluster.ZoneTextButton
	local h, b = self.header, self.border
	if not (h and b and Usable(zone)) then return end
	-- Same scale as the header pieces (they don't always scale with the map).
	local bs, zs = b:GetEffectiveScale(), zone:GetEffectiveScale()
	local s = (bs and bs > 0 and zs and zs > 0) and zs / bs or 1
	h:SetScale(s)
	local oL, oR = T.BorderOutset(b)
	local mapWidth = Minimap:GetWidth() + oL + oR
	local height = T.HeaderHeight(h)
	h:SetSize(math.max(mapWidth / s, T.headerMinWidth), height)
	h:SetFrameStrata(T.layer)
	h:SetFrameLevel(math.max(0, MinimapCluster:GetFrameLevel()))
	local gap = T.StripGap(T.headerPad, b, under and "BOTTOM" or "TOP", h, under and "TOP" or "BOTTOM", s) / s -- map px -> strip units
	local textY = T.headerTextY + (height - T.headerHeight) / 2 -- taller strip: zone stays centred
	local base = ZoneBase(zone)
	StandIn(zone, nil, base.w, base.h)
	h:ClearAllPoints()
	zone:ClearAllPoints()
	if under then
		h:SetPoint("TOP", b, "BOTTOM", 0, -gap)
		zone:SetPoint("TOP", h, "TOP", T.headerOffsetX, -textY)
	else
		h:SetPoint("BOTTOM", b, "TOP", 0, gap)
		zone:SetPoint("BOTTOM", h, "BOTTOM", T.headerOffsetX, textY)
	end
	h:Show()
	self:PlaceZone(zone, h, base, under, textY)
end

-- Mail (IndicatorFrame) top-left inside the map (bottom-left with Header Underneath: the
-- day/night disc then takes the top-left). The addon compartment goes to T.compartmentPoint
-- (bottom-right; Blizzard's zoom buttons are moved to the top-right by PlaceZoom).
-- Out of combat (square-pieces queue).
-- `inX`/`inY`: extra map pixels inward (beyond cornerInset) from the corner's sides.
local function PutInCorner(f, point, inX, inY)
	if not Usable(f) then return end
	StandIn(f)
	local fs = f:GetEffectiveScale()
	local k = (fs and fs > 0) and Minimap:GetEffectiveScale() / fs or 1 -- map pixels -> own units
	local x = (point:find("LEFT") and 1 or -1) * (T.cornerInset + (inX or 0)) * k
	local y = (point:find("TOP") and -1 or 1) * (T.cornerInset + (inY or 0)) * k
	f:ClearAllPoints()
	f:SetPoint(point, Minimap, point, x, y)
	if f:GetFrameLevel() <= Minimap:GetFrameLevel() + 5 then
		f:SetFrameLevel(Minimap:GetFrameLevel() + 6)
	end
end

function Square:PlaceCorners(under)
	PutInCorner(MinimapCluster and MinimapCluster.IndicatorFrame, under and "BOTTOMLEFT" or "TOPLEFT")
	PutInCorner(AddonCompartmentFrame, T.compartmentPoint, 0, T.compartmentRaise)
end

-- Blizzard's zoom buttons and their hover box (Minimap.ZoomIn / ZoomOut / ZoomHitArea) into
-- T.zoom.point. They are Minimap's children (units = map px), placed only in Blizzard's XML and
-- never re-anchored by its code; their hover show/hide (Minimap OnEnter/OnLeave + IsMouseOver)
-- moves with them. Only ClearAllPoints/SetPoint, out of combat (square-pieces queue).
function Square:PlaceZoom()
	local z = T.zoom
	if not (z and Minimap) then return end
	local point = z.point
	local sx = point:find("LEFT") and 1 or -1
	local sy = point:find("TOP") and -1 or 1
	local zin, zout, hit = Minimap.ZoomIn, Minimap.ZoomOut, Minimap.ZoomHitArea
	if Usable(zin) then
		zin:ClearAllPoints()
		zin:SetPoint(point, Minimap, point, sx * z.inX, sy * z.inY)
	end
	if Usable(zout) then
		zout:ClearAllPoints()
		zout:SetPoint("CENTER", Minimap, point, sx * z.outX, sy * z.outY)
	end
	if Usable(hit) then
		hit:ClearAllPoints()
		hit:SetPoint("CENTER", Minimap, point, sx * z.hitCenter, sy * z.hitCenter)
	end
end

-- Blizzard's day/night disc (Forever: MinimapCluster.DielFrame, sized by the atlas, on the old
-- round rim): T.dielSize map pixels, T.dielInset in from the bottom-left (top-left) corner.
function Square:PlaceDiel(under)
	local d = MinimapCluster and MinimapCluster.DielFrame
	if not Usable(d) or not (C_Texture and C_Texture.GetAtlasInfo) then return end
	local info = C_Texture.GetAtlasInfo(T.dielAtlas)
	local w = info and info.width
	if not (w and w > 0) then return end
	local parent = d:GetParent()
	local ps = parent and parent:GetEffectiveScale() or 1
	local k = (ps > 0) and Minimap:GetEffectiveScale() / ps or 1
	local s = T.dielSize / w
	StandIn(d, true)
	d:SetScale(s * k)
	local off = T.dielInset / s -- map pixels -> disc units
	local point = under and "TOPLEFT" or "BOTTOMLEFT"
	d:ClearAllPoints()
	d:SetPoint(point, Minimap, point, off, under and -off or off)
	d:SetFrameLevel(Minimap:GetFrameLevel() + 5)
end

---------------------------------------------------------------------------
-- Edit Mode box: MinimapCluster still has Blizzard's round-map margins, header area and
-- padding, and doesn't count our icon bar. Its Selection (the blue box Edit Mode drags and
-- snaps with) is anchored to hug what we draw: border + header strip + bar, TOPLEFT then
-- BOTTOMRIGHT on the cluster (the two points Edit Mode reads), and the screen clamp follows,
-- so the map can sit flush in a screen corner. Plain widget calls only, out of combat.
---------------------------------------------------------------------------
local function ScreenRect(f)
	if not (f and f.IsVisible and f:IsVisible()) then return end
	local l, r, t, b = f:GetLeft(), f:GetRight(), f:GetTop(), f:GetBottom()
	if not (l and r and t and b) then return end
	local s = f:GetEffectiveScale()
	-- See-through art margin per side: hug the visible line.
	local iL, iR, iT, iB
	if T.ArtInset then iL, iR, iT, iB = T.ArtInset(f) end
	iL = iL or 0
	iR, iT, iB = iR or iL, iT or iL, iB or iL
	return (l + iL) * s, (r - iR) * s, (t - iT) * s, (b + iB) * s
end

-- Edit Mode's live toggles (Header Underneath) re-lay the cluster but never re-anchor it, so a
-- screen-clamp push from the old insets stays until saving. While Edit Mode is open, put the
-- cluster back on Edit Mode's own anchor (systemInfo.anchorInfo, read only), like the anchor lines
-- of Blizzard's ApplySystemAnchor; plain ClearAllPoints/SetPoint, never Blizzard's functions.
local function ValidAnchor(a)
	return type(a) == "table" and type(a.point) == "string" and type(a.relativePoint) == "string"
		and type(a.offsetX) == "number" and type(a.offsetY) == "number"
		and (a.relativeTo == nil or type(a.relativeTo) == "string" or type(a.relativeTo) == "table")
end

local function InEditMode()
	local em = EditModeManagerFrame
	return em and type(em.IsEditModeActive) == "function" and em:IsEditModeActive()
end

-- Edit Mode's saved anchor(s) for the cluster (read only), or nil.
local function SavedAnchor(c)
	local info = c.systemInfo
	local a = type(info) == "table" and info.anchorInfo
	if not ValidAnchor(a) then return end
	local a2 = info.anchorInfo2
	if a2 ~= nil and not ValidAnchor(a2) then return end
	return a, a2
end

local function PutAnchor(c, a, a2, scale)
	c:ClearAllPoints()
	c:SetPoint(a.point, a.relativeTo or "UIParent", a.relativePoint, a.offsetX / scale, a.offsetY / scale)
	if a2 then
		c:SetPoint(a2.point, a2.relativeTo or "UIParent", a2.relativePoint, a2.offsetX / scale, a2.offsetY / scale)
	end
end

local function Reanchor()
	if InCombatLockdown() then return end
	local c = MinimapCluster
	if not Usable(c) then return end
	if not InEditMode() then return end
	if c.isDragging then return end
	local a, a2 = SavedAnchor(c)
	if not a then return end
	local scale = c:GetScale()
	if not (scale and scale > 0) then return end
	PutAnchor(c, a, a2, scale)
end

-- Keep the map where Edit Mode saved it, outside Edit Mode too. A screen-clamp push (the clamp
-- worked out with Blizzard's full-cluster insets for a moment, e.g. while the UI was hidden or
-- Blizzard re-laid the cluster) moves the cluster in from the screen edge and the push stays
-- after our insets come back; anything snapped to the cluster in Edit Mode (often the buffs)
-- moves with it. This puts the cluster back on Edit Mode's own anchor (read only), plain
-- ClearAllPoints/SetPoint, out of combat, never while Edit Mode is open or the cluster is in its
-- default (managed) place. Only when the cluster still hangs on the same points and frames as
-- the saved anchor: an addon that moved it elsewhere is left alone.
local function RelFrame(a)
	local r = a.relativeTo
	if r == nil then return UIParent end
	if type(r) == "string" then return _G[r] end
	return r
end

local MAX_PUSH = 200 -- cluster units; bigger offsets are someone's own move, not a clamp push

-- "same", "pushed" (same points, offsets moved; returns the biggest move) or "other".
local function CompareAnchor(c, a, a2, scale)
	local want = { a, a2 }
	local n = c:GetNumPoints()
	if n ~= #want then return "other" end
	local worst = 0
	for _, x in ipairs(want) do
		local found
		for i = 1, n do
			local p, rel, rp, ox, oy = c:GetPoint(i)
			if p == x.point then
				if rp ~= x.relativePoint or rel ~= RelFrame(x) then return "other" end
				if type(ox) ~= "number" or type(oy) ~= "number" then return "other" end
				local d = math.max(math.abs(ox - x.offsetX / scale), math.abs(oy - x.offsetY / scale))
				if d > worst then worst = d end
				found = true
				break
			end
		end
		if not found then return "other" end
	end
	if worst <= 0.5 then return "same", 0 end
	if worst > MAX_PUSH then return "other", worst end
	return "pushed", worst
end

-- `force`: re-set the anchor even when GetPoint already matches (a push the client keeps
-- outside the anchor values is undone too). `why` goes into /mmap debug.
function Square:KeepPlace(force, why)
	if not self.active or InCombatLockdown() or InEditMode() then return end
	local c = MinimapCluster
	if not Usable(c) or c.isDragging then return end
	local info = c.systemInfo
	if type(info) ~= "table" or info.isInDefaultPosition then return end
	local a, a2 = SavedAnchor(c)
	if not a then return end
	local scale = c:GetScale()
	if not (scale and scale > 0) then return end
	local ok, state, moved = pcall(CompareAnchor, c, a, a2, scale)
	if not ok or state == "other" then
		self.placeLast = (why or "?") .. ": " .. (ok and "left alone (other anchor)" or "unreadable")
		return
	end
	if state == "same" and not force then return end
	self:ApplyClamp()
	PutAnchor(c, a, a2, scale)
	if state == "pushed" then
		self.placeFixes = (self.placeFixes or 0) + 1
		self.placeLast = string.format("%s: moved back %.1f", why or "?", moved)
	end
end

-- Next frame and again 1 s later (a re-layout can settle late), once however often asked.
function Square:KeepPlaceSoon(why)
	if not self.active or self.keepPending then return end
	self.keepPending = true
	local function run()
		ns.RunOutOfCombat("keep-place", function()
			ns.SafeRun("KeepPlace", Square.KeepPlace, Square, true, why)
		end)
	end
	C_Timer.After(0, function()
		Square.keepPending = false
		run()
	end)
	-- Only one 1 s run waits at a time, however many events come in.
	if not self.keepLatePending then
		self.keepLatePending = true
		C_Timer.After(1, function()
			Square.keepLatePending = false
			run()
		end)
	end
end

-- /mmap debug: the cluster's anchor, Edit Mode's saved one, clamp insets, the buffs' anchor
-- and how often KeepPlace moved the map back. Read only.
local function PointText(f)
	if not (f and f.GetPoint and f.GetNumPoints) or (f.IsForbidden and f:IsForbidden()) then return "-" end
	if f:GetNumPoints() < 1 then return "-" end
	local p, rel, rp, x, y = f:GetPoint(1)
	local relName = rel and rel.GetName and rel:GetName() or (rel and "?" or "UIParent")
	return string.format("%s %s %s %.1f %.1f", tostring(p), tostring(relName), tostring(rp), x or 0, y or 0)
end

function Square.PlaceDebug()
	local c = MinimapCluster
	local map = PointText(c)
	local saved = "-"
	local a = c and SavedAnchor(c)
	if a then
		local s = c:GetScale() or 1
		local rel = type(a.relativeTo) == "table" and (a.relativeTo:GetName() or "?") or tostring(a.relativeTo or "UIParent")
		saved = string.format("%s %s %s %.1f %.1f", a.point, rel, a.relativePoint, a.offsetX / s, a.offsetY / s)
		if c.systemInfo.isInDefaultPosition then saved = saved .. " (default)" end
	end
	local clamp = "-"
	if c and c.GetClampRectInsets then
		local l, r, t, b = c:GetClampRectInsets()
		clamp = string.format("%.1f/%.1f/%.1f/%.1f", l or 0, r or 0, t or 0, b or 0)
	end
	return map, saved, clamp, PointText(BuffFrame), tostring(Square.placeFixes or 0), Square.placeLast or "-"
end

-- Screen x, y of one anchor point of a frame (LEFT/RIGHT/TOP/BOTTOM/CENTER combinations), or nil.
local function PointXY(f, point)
	if not (f and f.GetLeft and f.GetEffectiveScale) then return end
	local l, r, t, b = f:GetLeft(), f:GetRight(), f:GetTop(), f:GetBottom()
	if not (l and r and t and b) then return end
	local s = f:GetEffectiveScale() or 1
	local x = (point:find("LEFT") and l) or (point:find("RIGHT") and r) or (l + r) / 2
	local y = (point:find("TOP") and t) or (point:find("BOTTOM") and b) or (t + b) / 2
	return x * s, y * s
end

-- How far the game's screen clamp moves a cluster whose clamp rect (rect + insets, screen units)
-- is l, r, t, b: x, y (0, 0 when it fits or isn't clamped).
local function ClampPush(c, l, r, t, b)
	if c.IsClampedToScreen and not c:IsClampedToScreen() then return 0, 0 end
	local u = UIParent
	local ue = u and u.GetEffectiveScale and u:GetEffectiveScale()
	local W, H = u and u:GetRight(), u and u:GetTop()
	if not (ue and W and H) then return 0, 0 end
	W, H = W * ue, H * ue
	local px, py = 0, 0
	if r > W then px = W - r end
	if l + px < 0 then px = -l end
	if t > H then py = H - t end
	if b + py < 0 then py = -b end
	return px, py
end

-- /mmap selftest: is the cluster where Edit Mode saved it? Read only. Returns the state
-- ("same", "pushed", "other", "default", "none", "editmode"), how far the anchor's offsets moved
-- (cluster units), how far the real spot on screen is from the saved one after the screen clamp
-- (screen units, nil when a rect can't be read) and how far the clamp holds it in from the saved
-- spot (screen units; by design when the map + bar would stick out past the screen edge).
function Square.PlaceCheck()
	local c = MinimapCluster
	if not Usable(c) then return "none" end
	if InEditMode() then return "editmode" end
	local info = c.systemInfo
	if type(info) ~= "table" then return "none" end
	if info.isInDefaultPosition then return "default" end
	local a, a2 = SavedAnchor(c)
	if not a then return "none" end
	local scale = c:GetScale()
	if not (scale and scale > 0) then return "none" end
	local state, moved = CompareAnchor(c, a, a2, scale)
	if state == "other" then return "other", moved end
	local cs = c:GetEffectiveScale() or 1
	-- The saved spot (first anchor), then the clamp the game puts on it with today's insets.
	local cx, cy = PointXY(c, a.point)
	local rx, ry = PointXY(RelFrame(a), a.relativePoint)
	local l, r, t, b = c:GetLeft(), c:GetRight(), c:GetTop(), c:GetBottom()
	if not (cx and rx and l and r and t and b) then return state, moved or 0, nil end
	local dx = rx + a.offsetX / scale * cs - cx
	local dy = ry + a.offsetY / scale * cs - cy
	local iL, iR, iT, iB = 0, 0, 0, 0
	if c.GetClampRectInsets then iL, iR, iT, iB = c:GetClampRectInsets() end
	local px, py = ClampPush(c, l * cs + dx + (iL or 0) * cs, r * cs + dx + (iR or 0) * cs,
		t * cs + dy + (iT or 0) * cs, b * cs + dy + (iB or 0) * cs)
	local off = math.max(math.abs(dx + px), math.abs(dy + py))
	if a2 then
		local cx2, cy2 = PointXY(c, a2.point)
		local rx2, ry2 = PointXY(RelFrame(a2), a2.relativePoint)
		if not (cx2 and rx2) then return state, moved or 0, nil end
		off = math.max(off, math.abs(rx2 + a2.offsetX / scale * cs + px - cx2), math.abs(ry2 + a2.offsetY / scale * cs + py - cy2))
	end
	return state, moved or 0, off, math.max(math.abs(px), math.abs(py))
end

local function ClampChanged(old, new)
	if not (old and new) then return old ~= new end
	for i = 1, 4 do
		if math.abs((old[i] or 0) - (new[i] or 0)) > 0.05 then return true end
	end
	return false
end

---------------------------------------------------------------------------
-- Header Underneath keeps the block's top edge: Blizzard's SetHeaderUnderneath(true) moves
-- MinimapContainer from TOP 10,-30 to BOTTOM 10,30 (30 px up in the cluster) and our icon bar goes
-- above the map, so the top edge of the whole block rose and slid under bars at the screen top
-- (and the clamp held it in, the "Map spot 23 px" self-test FAIL). Blizzard also re-sizes the
-- cluster (ResizeLayoutFrame), so where the block ends up depends on Edit Mode's anchor point
-- (beta.13 assumed a TOP anchor and dropped a BOTTOM-anchored map too far). So it is measured:
-- with the header on top, the block's top edge is noted as a distance from the cluster's anchor
-- point (which Edit Mode keeps on the same screen spot in both settings; ns.db.topEdge, so it lasts
-- through /reload). With it on, the container is anchored to its stand-in (Blizzard's own spot,
-- which keeps the cluster's size Blizzard's) and shifted so the block's top edge (bar or map) is at
-- that same distance again. Plain ClearAllPoints/SetPoint on the container only, out of combat,
-- also while Edit Mode is open (so the kept top shows right after a toggle or Save) but never
-- while the map is dragged (isDragging, read only; re-fit on drag end); with it off Blizzard's own
-- spot stays (only our own move is undone). Edit Mode's anchor and the cluster are never touched.
---------------------------------------------------------------------------
-- Screen y of the cluster's anchor point (the point Edit Mode holds still), its kind, or nil.
local function AnchorY(c)
	local p = c:GetNumPoints() > 0 and c:GetPoint(1)
	local t, b = c:GetTop(), c:GetBottom()
	local ce = c:GetEffectiveScale()
	if not (type(p) == "string" and t and b and ce and ce > 0) then return end
	local kind = p:find("TOP") and "top" or p:find("BOTTOM") and "bottom" or "center"
	local y = (kind == "top" and t) or (kind == "bottom" and b) or (t + b) / 2
	return y * ce, kind, ce
end

-- What the top-edge distance depends on (map and header size, cluster units).
local function EdgeKey(ce)
	local mh, me = Minimap:GetHeight(), Minimap:GetEffectiveScale()
	local h = Square.header
	local hh, he = h and h:GetHeight(), h and h:GetEffectiveScale()
	if not (mh and me and hh and he) then return end
	return mh * me / ce, hh * he / ce
end

local function ValidEdge(e)
	if type(e) ~= "table" then return false end
	for _, k in ipairs({ "top", "bottom", "center", "map", "head" }) do
		local v = e[k]
		if type(v) ~= "number" or v ~= v or math.abs(v) > 2000 then return false end
	end
	return true
end

-- Header on top (Blizzard's spot): note the block's top edge from each possible anchor point.
local function NoteEdge(c)
	local _, _, bt = ScreenRect(Square.border)
	local _, _, ht = ScreenRect(Square.header)
	local t, b, ce = c:GetTop(), c:GetBottom(), c:GetEffectiveScale()
	if not (bt and ht and t and b and ce and ce > 0) or not ns.db then return end
	local map, head = EdgeKey(ce)
	if not map then return end
	local top = math.max(bt, ht) / ce
	local e = { top = top - t, bottom = top - b, center = top - (t + b) / 2, map = map, head = head }
	local old = ns.db.topEdge
	if ValidEdge(old) then
		local same = true
		for k, v in pairs(e) do if math.abs(v - old[k]) > 0.05 then same = false end end
		if same then return end
	end
	ns.db.topEdge = e
end

-- Header Underneath on: screen y the block's top edge should have, and its top now. Read only.
local function EdgeWant(c)
	local e = ns.db and ns.db.topEdge
	if not ValidEdge(e) then return end
	local y, kind, ce = AnchorY(c)
	if not y then return end
	local map, head = EdgeKey(ce)
	if not map or math.abs(map - e.map) > 0.5 or math.abs(head - e.head) > 0.5 then return end
	local _, _, bt = ScreenRect(Square.border)
	if not bt then return end
	local _, _, at = ScreenRect(ns.IconBar and ns.IconBar.frame)
	local now = (at and at > bt) and at or bt
	return y + e[kind] * ce, now
end

-- In the hooks (same frame as Blizzard's SetPoint / Layout) the screen rects of frames moved this
-- frame can still be last frame's: measuring there put the map one frame too high (beta.2 flicker).
-- So the hooks use the offset the last fresh measurement found for the same layout (anchor kind,
-- map / header / bar size, saved top edge: all read without rects), kept in ns.db.topShift.
local function ShiftKey(c)
	local e = ns.db and ns.db.topEdge
	if not ValidEdge(e) or c:GetNumPoints() < 1 then return end
	local p = c:GetPoint(1)
	local ce = c:GetEffectiveScale()
	if type(p) ~= "string" or not (ce and ce > 0) then return end
	local kind = p:find("TOP") and "top" or p:find("BOTTOM") and "bottom" or "center"
	local map, head = EdgeKey(ce)
	if not map then return end
	local bar = ns.IconBar and ns.IconBar.frame
	local bh = (bar and bar:IsShown() and bar:GetHeight()) and bar:GetHeight() * bar:GetEffectiveScale() / ce or 0
	return string.format("%s %.1f %.1f %.1f %.1f %.1f", kind, e[kind], map, head, bh, e.map)
end

local function ValidShift(t)
	return type(t) == "table" and type(t.key) == "string" and type(t.dy) == "number" and t.dy == t.dy and math.abs(t.dy) < 2000
end

-- `why`: nil = a fresh measurement (FitSelection, the frame after a change); otherwise the hook
-- name (same frame: only the kept offset, no rect reads). Last move kept for /mmap debug.
function Square:PlaceContainer(why)
	if not self.active or InCombatLockdown() then return end
	local c, cont = MinimapCluster, Container()
	if not (Usable(c) and Usable(cont) and cont:GetParent() == c) then return end
	local s = standIns[cont]
	local u = self.under
	if u == nil then u = Square.HeaderIsUnderneath() end
	local _, rel = cont:GetPoint(1)
	if not u then
		self.containerShift = nil
		if s and rel == s then -- our move is left over: back on Blizzard's spot
			if c.isDragging then return end
			cont:ClearAllPoints()
			cont:SetPoint("TOP", s, "TOP", 0, 0)
			self.topLast = (why or "fit") .. " back"
			return
		end
		-- Read only (also while Edit Mode is open: the spot before a toggle); fresh rects only.
		if not why then NoteEdge(c) end
		return
	end
	-- Also while Edit Mode is open (the kept top shows right after a toggle or Save), but never
	-- mid-drag (isDragging: read only); the drag-end hook re-fits.
	if c.isDragging or not s then return end
	local dy
	local key = ShiftKey(c)
	local kept = ns.db and ns.db.topShift
	if why then
		if not (key and ValidShift(kept) and kept.key == key) then
			self.topLast = why .. " waits (no kept offset)"
			return -- the next frame's FitSelection measures
		end
		dy = kept.dy
	else
		local want, now = EdgeWant(c)
		local ct, st = cont:GetTop(), s:GetTop()
		local ne, se = cont:GetEffectiveScale(), s:GetEffectiveScale()
		if want and ct and st and ne and ne > 0 then
			dy = (ct * ne + (want - now) - st * se) / ne
			if key and ns.db then ns.db.topShift = { key = key, dy = dy } end
		else
			dy = 0 -- not measured yet (or the map size changed): Blizzard's own spot
		end
	end
	local p, r2, rp, x, y = cont:GetPoint(1)
	if cont:GetNumPoints() == 1 and p == "TOP" and r2 == s and rp == "TOP" and x == 0 and y and math.abs(y - dy) < 0.05 then
		return
	end
	cont:ClearAllPoints()
	cont:SetPoint("TOP", s, "TOP", 0, dy)
	self.containerShift = dy
	self.topLast = string.format("%s %.1f", why or "fit", dy)
end

-- /mmap debug "Map top:" line: Header Underneath, is Layout hookable, kept offset, last move.
function Square.TopDebug()
	local kept = ns.db and ns.db.topShift
	return tostring(Square.under), tostring(Square.layoutHooked or false),
		ValidShift(kept) and string.format("%.1f", kept.dy) or "-", Square.topLast or "-"
end

-- Right now (same frame), out of combat: after Blizzard re-sizes (Layout) or re-anchors the cluster.
function Square:PlaceContainerNow(why)
	if not self.active then return end
	ns.RunOutOfCombat("square-container", function()
		ns.SafeRun("MapTop", Square.PlaceContainer, Square, why or "hook")
	end)
end

-- /mmap selftest: with Header Underneath on, how far the block's top edge is from where it is
-- with the header on top (screen units), or nil (off, Edit Mode open, not measured yet). Read only.
function Square.ContainerCheck()
	local c = MinimapCluster
	if not (Square.active and Usable(c)) or InEditMode() then return end
	local u = Square.under
	if u == nil then u = Square.HeaderIsUnderneath() end
	if not u then return end
	local want, now = EdgeWant(c)
	if not want then return end
	return math.abs(want - now)
end

function Square:FitSelection()
	if not self.active then return end
	ns.SafeRun("MapTop", self.PlaceContainer, self)
	local oldClamp = self.fit and self.fit.clamp
	local c = MinimapCluster
	local sel = c and c.Selection
	if not (Usable(c) and Usable(sel) and sel.SetPoint and sel.SetAllPoints) then return end
	local cl, cr, ct, cb = ScreenRect(c)
	-- The cluster itself isn't shown (UI hidden with Alt+Z, a cinematic, a loading moment): keep
	-- our last box and clamp. Dropping to Blizzard's 0 insets here let the screen clamp push the
	-- map in from the edge when it showed again (the "map jumped left" bug).
	if not cl then return end
	local bar = ns.IconBar and ns.IconBar.frame
	local uL, uR, uT, uB
	for _, f in ipairs({ self.border, self.header, bar }) do
		local l, r, t, b = ScreenRect(f)
		if l then
			uL = uL and math.min(uL, l) or l
			uR = uR and math.max(uR, r) or r
			uT = uT and math.max(uT, t) or t
			uB = uB and math.min(uB, b) or b
		end
	end
	if not uL then
		-- The cluster shows but nothing of ours does: Blizzard's own box and clamp.
		self.fit = nil
		if ns.db then ns.db.editFit = nil end
		sel:ClearAllPoints()
		sel:SetAllPoints(c)
		if c.SetClampRectInsets then c:SetClampRectInsets(0, 0, 0, 0) end
		return
	end
	local ss = sel:GetEffectiveScale()
	if not (ss and ss > 0) then ss = 1 end
	local cs = c:GetEffectiveScale()
	if not (cs and cs > 0) then cs = 1 end
	-- Kept so ApplyClamp can put them back at once, without reading any rects.
	self.fit = {
		sel = { (uL - cl) / ss, (uR - cr) / ss, (uT - ct) / ss, (uB - cb) / ss },
		clamp = { (uL - cl) / cs, (uR - cr) / cs, (uT - ct) / cs, (uB - cb) / cs },
	}
	-- Saved for the next load (ApplySaved), so Edit Mode's first layout pass uses them.
	if ns.db then
		ns.db.editFit = { sel = { unpack(self.fit.sel) }, clamp = { unpack(self.fit.clamp) } }
	end
	self:ApplyClamp()
	-- New insets: undo a stale clamp push (Edit Mode open: its live anchor; closed: KeepPlace).
	if ClampChanged(oldClamp, self.fit.clamp) then
		if InEditMode() then Reanchor() else self:KeepPlace(true, "clamp") end
	end
end

-- Puts a box + clamp set on the cluster (no rect reads, out of combat).
local function PutFit(fit)
	local c = MinimapCluster
	local sel = c and c.Selection
	if not (fit and Usable(c) and Usable(sel) and sel.SetPoint) or InCombatLockdown() then return end
	local p = fit.sel
	sel:ClearAllPoints()
	sel:SetPoint("TOPLEFT", c, "TOPLEFT", p[1], p[3])
	sel:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", p[2], p[4])
	if c.SetClampRectInsets then
		c:SetClampRectInsets(fit.clamp[1], fit.clamp[2], fit.clamp[3], fit.clamp[4])
	end
end

-- Our last box and clamp, right now. Runs straight after Blizzard re-anchors the cluster or its box.
function Square:ApplyClamp()
	if self.active then PutFit(self.fit) end
end

local function ValidSide(t)
	if type(t) ~= "table" then return false end
	for i = 1, 4 do
		local v = t[i]
		if type(v) ~= "number" or v ~= v or math.abs(v) > 500 then return false end
	end
	return true
end

-- At our ADDON_LOADED: last session's box + clamp, so Edit Mode's own layout pass (after
-- addons load) works out the clamp with our insets and the map stays in its corner.
-- The cluster's anchor is never touched.
function Square:ApplySaved()
	local s = ns.db and ns.db.editFit
	if not (type(s) == "table" and ValidSide(s.sel) and ValidSide(s.clamp)) then return end
	self.early = true
	PutFit(s)
end

-- A shape addon stopped us after ApplySaved: back to Blizzard's box and clamp.
function Square:UndoSaved()
	if not self.early or self.active or InCombatLockdown() then return end
	self.early = nil
	local c = MinimapCluster
	local sel = c and c.Selection
	if not (Usable(c) and Usable(sel)) then return end
	sel:ClearAllPoints()
	sel:SetAllPoints(c)
	if c.SetClampRectInsets then c:SetClampRectInsets(0, 0, 0, 0) end
end

-- Next frame (anchors settled), once however often asked, after combat if needed.
function Square:QueueFit()
	if not self.active or self.fitPending then return end
	self.fitPending = true
	C_Timer.After(0, function()
		Square.fitPending = false
		ns.RunOutOfCombat("edit-fit", function()
			ns.SafeRun("EditModeBox", Square.FitSelection, Square)
		end)
	end)
end

-- All three, after combat if needed. `under` = the value Blizzard just applied, if known.
-- `copy`: also refresh the stand-ins (setup, UpdateMinimapConfig, SetHeaderUnderneath only);
-- kept until the queued job runs, so a combat delay doesn't lose it.
function Square:PlacePieces(under, copy)
	if not self.active then return end
	if under ~= nil then self.under = under and true or false end
	if copy then self.copyPending = true end
	ns.RunOutOfCombat("square-pieces", function()
		local u = self.under
		if u == nil then u = Square.HeaderIsUnderneath() end
		self.copying = self.copyPending and true or false
		self.copyPending = false
		-- The container only moves in PlaceContainer (QueueFit), from this stand-in.
		ns.SafeRun("MapTop", StandIn, Container())
		ns.SafeRun("Header", self.PlaceHeader, self, u)
		ns.SafeRun("Corners", self.PlaceCorners, self, u)
		ns.SafeRun("Zoom", self.PlaceZoom, self)
		ns.SafeRun("DayNight", self.PlaceDiel, self, u)
		self.copying = false
		-- The container now, in the same frame as Blizzard's move (no one-frame jump); the bar's
		-- side first, so its top is measured where it will be. QueueFit stays as the backup.
		local Bar = ns.IconBar
		if Bar and Bar.SetSide then ns.SafeRun("BarSide", Bar.SetSide, Bar, u) end
		ns.SafeRun("MapTop", self.PlaceContainer, self, "toggle")
		ns.SafeRun("Layer", self.ApplyLayer, self)
		self:QueueFit()
	end)
end

---------------------------------------------------------------------------
-- Layer: the whole map in T.layer (BACKGROUND), so other addons draw over it.
-- Each frame is set by name (how strata passes to children isn't documented). The cluster
-- must move too: it takes the mouse, and in LOW it would sit over the map and eat clicks.
-- Levels are untouched, so the order on the map stays Blizzard's. Plain method calls,
-- out of combat; no fields on Blizzard frames.
---------------------------------------------------------------------------
local function LayerFrames()
	local c = MinimapCluster
	local backdrop = MinimapBackdrop
	return {
		c, Minimap,
		c and c.ZoneTextButton, c and c.Tracking, c and c.IndicatorFrame,
		c and c.InstanceDifficulty, c and c.DielFrame,
		AddonCompartmentFrame, GameTimeFrame, TimeManagerClockButton,
		backdrop, backdrop and backdrop.ExternalEventURLButton,
		Square.border, Square.header, ns.IconBar and ns.IconBar.frame,
		Square.coordsBox,
	}
end

function Square:ApplyLayer()
	if not self.active then return end
	ns.RunOutOfCombat("layer", function()
		self.layering = true
		local list = LayerFrames()
		for i = 1, 16 do -- fixed length: the list may hold nils
			local f = list[i]
			if Usable(f) and f.SetFrameStrata and f:GetFrameStrata() ~= T.layer then
				f:SetFrameStrata(T.layer)
			end
		end
		-- Blizzard's zoom hover box (Minimap.ZoomHitArea) is only checked with IsMouseOver (by
		-- position), so it never needs the mouse: turn it off completely, so it can't block
		-- clicks, pings or the minimap's own blip tooltips under it.
		local hit = Minimap and Minimap.ZoomHitArea
		if Usable(hit) and hit.EnableMouse and (not hit.IsMouseEnabled or hit:IsMouseEnabled()) then
			hit:EnableMouse(false)
		end
		self.layering = false
		ns.SafeRun("MouseGuard", Square.GuardMouse, Square)
	end)
end

---------------------------------------------------------------------------
-- Mouse guard: Blizzard's minimap pings (click) and blip tooltips (hover) only work while the
-- Minimap itself is the first frame taking the mouse under the cursor. Out of combat:
-- 1. the Minimap's own mouse (and click / motion) is on, and no hit rect insets shrink it;
-- 2. no frame it sits in (MinimapContainer, MinimapCluster) is at its level or above;
-- 3. any other shown, mouse-taking frame near the map (children of the cluster, container,
--    MinimapBackdrop and the Minimap, plus those three) that covers half the map or more gets
--    its mouse turned off. Small pieces (buttons, pins, the counter) are never touched, nor
--    the icon bar's buttons and their menus, nor anything while Edit Mode is open.
-- Plain widget calls only; what was changed is kept in Square.mouseFixes for /mmap debug.
---------------------------------------------------------------------------
local function MouseOn(f)
	if f.IsMouseEnabled and f:IsMouseEnabled() then return true end
	if f.IsMouseClickEnabled and f:IsMouseClickEnabled() then return true end
	if f.IsMouseMotionEnabled and f:IsMouseMotionEnabled() then return true end
	return false
end

local function Rect(f)
	local l, r, t, b = f:GetLeft(), f:GetRight(), f:GetTop(), f:GetBottom()
	if not (l and r and t and b) then return end
	local s = f:GetEffectiveScale() or 1
	return l * s, r * s, t * s, b * s
end

-- Share of the map's area that f covers (0..1).
local function CoverShare(f, ml, mr, mt, mb)
	local l, r, t, b = Rect(f)
	if not l then return 0 end
	local w = math.min(r, mr) - math.max(l, ml)
	local h = math.min(t, mt) - math.max(b, mb)
	if w <= 0 or h <= 0 then return 0 end
	return (w * h) / ((mr - ml) * (mt - mb))
end

local function IsUnder(f, root) -- f is root or one of its descendants
	local depth = 0
	while f and depth < 20 do
		if f == root then return true end
		f = f.GetParent and f:GetParent() or nil
		depth = depth + 1
	end
	return false
end

local STRATA_ORDER = { WORLD = 0, BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5,
	FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }

-- f is above the Minimap for the mouse: strata order first, then frame level.
local function Above(f, m)
	local fs = STRATA_ORDER[f:GetFrameStrata()] or 1
	local ms = STRATA_ORDER[m:GetFrameStrata()] or 1
	if fs ~= ms then return fs > ms end
	return f:GetFrameLevel() >= m:GetFrameLevel()
end
Square.Above = Above

-- Holders whose mouse we turned off (weak): given back while Edit Mode is open.
local holdersOff = setmetatable({}, { __mode = "k" })

function Square:RestoreHolders()
	if InCombatLockdown() then return end
	for p in pairs(holdersOff) do
		if p.EnableMouse and not (p.IsForbidden and p:IsForbidden()) then p:EnableMouse(true) end
	end
end

local function EditModeOpen()
	local em = EditModeManagerFrame
	return em and type(em.IsEditModeActive) == "function" and em:IsEditModeActive()
end

local function AddKids(list, parent)
	if not (parent and parent.GetChildren) then return end
	for _, c in ipairs({ parent:GetChildren() }) do list[#list + 1] = c end
end

function Square:GuardMouse()
	local m = Minimap
	if not self.active or InCombatLockdown() or not Usable(m) or EditModeOpen() then return end
	self.mouseFixes = self.mouseFixes or {}
	local fixes = self.mouseFixes
	-- 1. The Minimap's own mouse.
	if m.EnableMouse and m.IsMouseEnabled and not m:IsMouseEnabled() then
		m:EnableMouse(true)
		fixes["Minimap mouse on"] = true
	end
	if m.SetMouseClickEnabled and m.IsMouseClickEnabled and not m:IsMouseClickEnabled() then
		m:SetMouseClickEnabled(true)
		fixes["Minimap clicks on"] = true
	end
	if m.SetMouseMotionEnabled and m.IsMouseMotionEnabled and not m:IsMouseMotionEnabled() then
		m:SetMouseMotionEnabled(true)
		fixes["Minimap hover on"] = true
	end
	-- Hit area shrunk by insets (Blizzard sets none on the Minimap): back to the whole map.
	if m.GetHitRectInsets and m.SetHitRectInsets then
		local l, r, t, b = m:GetHitRectInsets()
		if (l or 0) > 0 or (r or 0) > 0 or (t or 0) > 0 or (b or 0) > 0 then
			m:SetHitRectInsets(0, 0, 0, 0)
			fixes["Minimap hit area reset"] = true
		end
	end
	-- 2. and 3.: the frames MouseBlockers lists lose the mouse.
	for _, b in ipairs(Square.MouseBlockers()) do
		b.frame:EnableMouse(false)
		if b.holder then holdersOff[b.frame] = true end
		fixes[b.key] = true
	end
end

-- The frames that catch the Minimap's mouse (what GuardMouse turns off), as a list of
-- { frame, key (text for /mmap debug), holder (true for a frame the map sits in) }.
-- Changes nothing (also used by /mmap selftest).
function Square.MouseBlockers()
	local found, seen = {}, {}
	local m = Minimap
	if not Usable(m) then return found end
	local ml, mr, mt, mb = Rect(m)
	if not (ml and mr > ml and mt > mb) then return found end
	-- 2. Frames the Minimap sits in (MinimapContainer, MinimapCluster): one that takes the mouse
	-- and is above the map (higher strata, or same strata at its level or higher) catches every
	-- click and hover on it. The layer keeps the map low on purpose, so the holder's mouse goes
	-- off instead (out of combat; allowed on protected frames too, so only forbidden ones are
	-- skipped). Edit Mode drags with its own Selection child; the mouse is given back while
	-- Edit Mode is open (RestoreHolders) and taken again when it closes.
	local p, depth = m:GetParent(), 0
	while p and p ~= UIParent and depth < 5 do
		if not (p.IsForbidden and p:IsForbidden()) and p.EnableMouse and p.GetFrameLevel
			and MouseOn(p) and Above(p, m) then
			seen[p] = true
			found[#found + 1] = { frame = p, holder = true, key = "mouse off: " .. (p:GetName() or "map holder") }
		end
		p, depth = p:GetParent(), depth + 1
	end
	-- 3. Big mouse-taking frames over the map.
	local c = MinimapCluster
	local list = { c, Container(), MinimapBackdrop }
	AddKids(list, c)
	AddKids(list, Container())
	AddKids(list, MinimapBackdrop)
	AddKids(list, m)
	local bar = ns.IconBar and ns.IconBar.frame
	local sel = c and c.Selection
	for i = 1, #list do
		local f = list[i]
		if f and not seen[f] and f ~= m and f ~= sel and f ~= HybridMinimap and not IsUnder(m, f) and Usable(f) and f.EnableMouse
			and f.IsVisible and f:IsVisible() and MouseOn(f)
			and not (bar and IsUnder(f, bar))
			and CoverShare(f, ml, mr, mt, mb) >= 0.5 then
			if Above(f, m) then
				seen[f] = true
				found[#found + 1] = { frame = f, key = "mouse off: " .. (f:GetName() or ((f.GetObjectType and f:GetObjectType() or "frame") .. " in " .. ((f:GetParent() and f:GetParent():GetName()) or "?"))) }
			end
		end
	end
	return found
end

-- Put the layer back if Blizzard or another addon changes it (once, not while we set it).
local function WatchLayer(f)
	if not (f and f.SetFrameStrata) then return end
	hooksecurefunc(f, "SetFrameStrata", function(_, strata)
		if Square.layering or strata == T.layer then return end
		Square:ApplyLayer()
	end)
end

function Square:InstallHooks()
	if self.hooked then return end
	self.hooked = true
	WatchLayer(Minimap)
	WatchLayer(MinimapCluster)
	-- Edit Mode open: the map holders get their mouse back; closed: the mouse guard again.
	local em = EditModeManagerFrame
	if em then
		if type(em.EnterEditMode) == "function" then
			hooksecurefunc(em, "EnterEditMode", function()
				ns.SafeRun("MouseGuard", Square.RestoreHolders, Square)
			end)
		end
		if type(em.ExitEditMode) == "function" then
			hooksecurefunc(em, "ExitEditMode", function()
				ns.RunOutOfCombat("mouse-guard", function() ns.SafeRun("MouseGuard", Square.GuardMouse, Square) end)
				Square:QueueFit() -- Header Underneath top edge (skipped while Edit Mode was open)
			end)
		end
	end
	if not MinimapCluster then return end
	if MinimapCluster.UpdateMinimapConfig then
		hooksecurefunc(MinimapCluster, "UpdateMinimapConfig", function()
			Square:Reapply()
			Square:PlacePieces(nil, true)
		end)
	end
	if MinimapCluster.SetHeaderUnderneath then
		hooksecurefunc(MinimapCluster, "SetHeaderUnderneath", function(_, under) Square:PlacePieces(under, true) end)
	end
	if MinimapCluster.SetEditModeScale then
		hooksecurefunc(MinimapCluster, "SetEditModeScale", function() Square:PlacePieces(nil, true) end)
	end
	-- Edit Mode drag ended: the container move skipped mid-drag (Header Underneath top edge).
	if type(MinimapCluster.OnDragStop) == "function" then
		hooksecurefunc(MinimapCluster, "OnDragStop", function() Square:QueueFit() end)
	elseif MinimapCluster.Selection and MinimapCluster.Selection.HookScript then
		MinimapCluster.Selection:HookScript("OnDragStop", function() Square:QueueFit() end)
	end
	-- Blizzard's re-layout (ResizeLayoutFrame:Layout, after a toggle or size change): the container
	-- right away, so the map doesn't show one frame out of place.
	if type(MinimapCluster.Layout) == "function" then
		hooksecurefunc(MinimapCluster, "Layout", function() Square:PlaceContainerNow("layout") end)
		self.layoutHooked = true
	end
	-- The cluster re-sizes itself (ResizeLayoutFrame): fit the Edit Mode box again.
	if MinimapCluster.HookScript then
		MinimapCluster:HookScript("OnSizeChanged", function() Square:QueueFit() end)
	end
	-- Edit Mode re-anchors the cluster / its box (load, layout change): our clamp at once.
	for _, method in ipairs({ "AnchorSelectionFrame", "ApplySystemAnchor" }) do
		if type(MinimapCluster[method]) == "function" then
			hooksecurefunc(MinimapCluster, method, function()
				ns.SafeRun("EditModeBox", Square.ApplyClamp, Square)
				Square:QueueFit()
				if method == "ApplySystemAnchor" then
					Square:PlaceContainerNow("anchor")
					Square:KeepPlaceSoon("re-anchor")
				end
			end)
		end
	end
	-- The UI or the map shows again (Alt+Z, cinematics, pet battles): undo a clamp push.
	MinimapCluster:HookScript("OnShow", function() Square:KeepPlaceSoon("map shown") end)
	if UIParent and UIParent.HookScript then
		UIParent:HookScript("OnShow", function() Square:KeepPlaceSoon("UI shown") end)
	end
end

function Square:Setup()
	if not (Minimap and Container()) then return end
	self.active = true
	self:ApplyMask()
	self:HideRoundArt()
	self:CreateBorder()
	self:PlaceCoords()
	ns.SafeRun("CoordsBox", self.CreateCoordsBox, self)
	self:CreateHeader()
	self:InstallHooks()
	self:PlacePieces(Square.HeaderIsUnderneath(), true)
	-- Box and clamp now, not next frame, so they are set before Edit Mode places the cluster.
	ns.RunOutOfCombat("edit-fit", function()
		ns.SafeRun("EditModeBox", Square.FitSelection, Square)
	end)
	-- Mouse guard again once other addons have made their frames.
	for _, delay in ipairs({ 3, 15 }) do
		C_Timer.After(delay, function()
			ns.RunOutOfCombat("mouse-guard", function() ns.SafeRun("MouseGuard", Square.GuardMouse, Square) end)
		end)
	end
	-- GetMinimapShape ("SQUARE") is set by Core.lua when it loads.
end
