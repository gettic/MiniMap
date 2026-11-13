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
	return rel ~= nil and (rel == Minimap or rel == Square.header or rel == Square.border)
end

-- OnShow/OnHide of the Blizzard child: touches only our stand-in.
local function MirrorShown(f)
	local s = standIns[f]
	if s then s:SetShown(f:IsShown()) end
end

-- Call before moving f. ownScale: we rescale f ourselves, so keep Blizzard's scale.
local function StandIn(f, ownScale)
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
	s:SetSize(f:GetSize())
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

-- The strip goes on the side away from the icon bar, 2 px from the border; Blizzard's zone
-- button (with tracking and clock anchored to it) is centred in it.
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
	StandIn(zone)
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
		zin:SetPoint(point, Minimap, point, sx * z.inset, sy * z.inset)
	end
	if Usable(zout) then
		-- ZoomIn is 17x17: its centre is inset + 8.5 in; ZoomOut sits `step` further in.
		local c = z.inset + 8.5 + z.step
		zout:ClearAllPoints()
		zout:SetPoint("CENTER", Minimap, point, sx * c, sy * c)
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

local function Reanchor()
	if InCombatLockdown() then return end
	local c = MinimapCluster
	if not Usable(c) then return end
	local em = EditModeManagerFrame
	if not (em and type(em.IsEditModeActive) == "function" and em:IsEditModeActive()) then return end
	if c.isDragging then return end
	local info = c.systemInfo
	local a = type(info) == "table" and info.anchorInfo
	if not ValidAnchor(a) then return end
	local a2 = info.anchorInfo2
	if a2 ~= nil and not ValidAnchor(a2) then return end
	local scale = c:GetScale()
	if not (scale and scale > 0) then return end
	c:ClearAllPoints()
	c:SetPoint(a.point, a.relativeTo or "UIParent", a.relativePoint, a.offsetX / scale, a.offsetY / scale)
	if a2 then
		c:SetPoint(a2.point, a2.relativeTo or "UIParent", a2.relativePoint, a2.offsetX / scale, a2.offsetY / scale)
	end
end

local function ClampChanged(old, new)
	if not (old and new) then return old ~= new end
	for i = 1, 4 do
		if math.abs((old[i] or 0) - (new[i] or 0)) > 0.05 then return true end
	end
	return false
end

function Square:FitSelection()
	if not self.active then return end
	local oldClamp = self.fit and self.fit.clamp
	local c = MinimapCluster
	local sel = c and c.Selection
	if not (Usable(c) and Usable(sel) and sel.SetPoint and sel.SetAllPoints) then return end
	local cl, cr, ct, cb = ScreenRect(c)
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
	if not (uL and cl) then
		-- Nothing of ours shows: Blizzard's own box and clamp.
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
	-- New insets in Edit Mode: undo a stale clamp push (only inside Edit Mode, out of combat).
	if ClampChanged(oldClamp, self.fit.clamp) then Reanchor() end
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
		ns.SafeRun("Header", self.PlaceHeader, self, u)
		ns.SafeRun("Corners", self.PlaceCorners, self, u)
		ns.SafeRun("Zoom", self.PlaceZoom, self)
		ns.SafeRun("DayNight", self.PlaceDiel, self, u)
		self.copying = false
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
-- 1. the Minimap's own mouse (and click / motion) is on;
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
	local ml, mr, mt, mb = Rect(m)
	if not (ml and mr > ml and mt > mb) then return end
	local mStrata = STRATA_ORDER[m:GetFrameStrata()] or 1
	-- 2. Frames the Minimap sits in: keep it above them.
	local p, depth = m:GetParent(), 0
	while p and p ~= UIParent and depth < 5 do
		if Usable(p) and p.GetFrameLevel and MouseOn(p)
			and (STRATA_ORDER[p:GetFrameStrata()] or 1) == mStrata
			and p:GetFrameLevel() >= m:GetFrameLevel() then
			m:SetFrameLevel(p:GetFrameLevel() + 1)
			fixes["Minimap raised over " .. (p:GetName() or "its holder")] = true
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
		if f and f ~= m and f ~= sel and f ~= HybridMinimap and not IsUnder(m, f) and Usable(f) and f.EnableMouse
			and f.IsVisible and f:IsVisible() and MouseOn(f)
			and not (bar and IsUnder(f, bar))
			and CoverShare(f, ml, mr, mt, mb) >= 0.5 then
			local fs = STRATA_ORDER[f:GetFrameStrata()] or 1
			if fs > mStrata or (fs == mStrata and f:GetFrameLevel() >= m:GetFrameLevel()) then
				f:EnableMouse(false)
				fixes["mouse off: " .. (f:GetName() or ((f.GetObjectType and f:GetObjectType() or "frame") .. " in " .. ((f:GetParent() and f:GetParent():GetName()) or "?")))] = true
			end
		end
	end
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
			end)
		end
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
