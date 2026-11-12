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

-- Square mask on the minimap and, when it is loaded, on the hybrid minimap.
function Square:ApplyMask()
	if Minimap and Minimap.SetMaskTexture then
		Minimap:SetMaskTexture(T.mask)
	end
	local hybrid = HybridMinimap
	if hybrid and hybrid.CircleMask and hybrid.CircleMask.SetTexture then
		hybrid.CircleMask:SetTexture(T.mask, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	end
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
	b:SetPoint("TOPLEFT", Minimap, "TOPLEFT", -T.borderOutset, T.borderOutset)
	b:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", T.borderOutset, -T.borderOutset)
	b:EnableMouse(false)
	T.ApplyBorder(b)
	self.border = b
end

-- Player coordinates go inside the map's bottom edge so they don't sit on the icon bar.
function Square:PlaceCoords()
	local c = Container()
	local coords = c and c.PlayerCoords
	if not (coords and coords.ClearAllPoints) then return end
	coords:ClearAllPoints()
	coords:SetPoint("BOTTOM", Minimap, "BOTTOM", 0, T.coordsOffsetY)
	coords:SetFrameLevel(Minimap:GetFrameLevel() + 5)
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

-- Our strip behind the header: a child of our border (hides with the map), same look as the bar.
function Square:CreateHeader()
	if self.header or not self.border then return end
	local h = CreateFrame("Frame", "MiniMapForeverHeader", self.border, T.backdropTemplate)
	h:EnableMouse(false)
	T.ApplyBorder(h)
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
	local mapWidth = Minimap:GetWidth() + 2 * T.borderOutset
	h:SetSize(math.max(mapWidth / s, T.headerMinWidth), T.headerHeight)
	h:SetFrameStrata(T.layer)
	h:SetFrameLevel(math.max(0, MinimapCluster:GetFrameLevel()))
	local gap = T.headerPad / s -- map pixels -> strip units
	h:ClearAllPoints()
	zone:ClearAllPoints()
	if under then
		h:SetPoint("TOP", b, "BOTTOM", 0, -gap)
		zone:SetPoint("TOP", h, "TOP", T.headerOffsetX, -T.headerTextY)
	else
		h:SetPoint("BOTTOM", b, "TOP", 0, gap)
		zone:SetPoint("BOTTOM", h, "BOTTOM", T.headerOffsetX, T.headerTextY)
	end
	h:Show()
end

-- Mail (IndicatorFrame) top-left inside the map (bottom-left with Header Underneath: the
-- day/night disc then takes the top-left). The addon compartment always goes top-right:
-- Blizzard's zoom buttons sit in the bottom-right corner and must stay clickable.
local function PutInCorner(f, point)
	if not Usable(f) then return end
	local fs = f:GetEffectiveScale()
	local k = (fs and fs > 0) and Minimap:GetEffectiveScale() / fs or 1 -- map pixels -> own units
	local x = (point:find("LEFT") and 1 or -1) * T.cornerInset * k
	local y = (point:find("TOP") and -1 or 1) * T.cornerInset * k
	f:ClearAllPoints()
	f:SetPoint(point, Minimap, point, x, y)
	if f:GetFrameLevel() <= Minimap:GetFrameLevel() + 5 then
		f:SetFrameLevel(Minimap:GetFrameLevel() + 6)
	end
end

function Square:PlaceCorners(under)
	PutInCorner(MinimapCluster and MinimapCluster.IndicatorFrame, under and "BOTTOMLEFT" or "TOPLEFT")
	PutInCorner(AddonCompartmentFrame, "TOPRIGHT")
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
	local i = T.ArtInset and T.ArtInset(f) or 0 -- see-through art margin: hug the visible line
	return (l + i) * s, (r - i) * s, (t - i) * s, (b + i) * s
end

function Square:FitSelection()
	if not self.active then return end
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
	self:ApplyClamp()
end

-- Our last box and clamp, right now (no rect reads). Runs straight after Blizzard re-anchors
-- the cluster or its box, so the screen clamp never works with Blizzard's full-size insets
-- (that pushed the map left once at every load).
function Square:ApplyClamp()
	local fit = self.fit
	if not (self.active and fit) or InCombatLockdown() then return end
	local c = MinimapCluster
	local sel = c and c.Selection
	if not (Usable(c) and Usable(sel) and sel.SetPoint) then return end
	local p = fit.sel
	sel:ClearAllPoints()
	sel:SetPoint("TOPLEFT", c, "TOPLEFT", p[1], p[3])
	sel:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", p[2], p[4])
	if c.SetClampRectInsets then
		c:SetClampRectInsets(fit.clamp[1], fit.clamp[2], fit.clamp[3], fit.clamp[4])
	end
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
function Square:PlacePieces(under)
	if not self.active then return end
	if under ~= nil then self.under = under and true or false end
	ns.RunOutOfCombat("square-pieces", function()
		local u = self.under
		if u == nil then u = Square.HeaderIsUnderneath() end
		ns.SafeRun("Header", self.PlaceHeader, self, u)
		ns.SafeRun("Corners", self.PlaceCorners, self, u)
		ns.SafeRun("DayNight", self.PlaceDiel, self, u)
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
	}
end

function Square:ApplyLayer()
	if not self.active then return end
	ns.RunOutOfCombat("layer", function()
		self.layering = true
		local list = LayerFrames()
		for i = 1, 15 do -- fixed length: the list may hold nils
			local f = list[i]
			if Usable(f) and f.SetFrameStrata and f:GetFrameStrata() ~= T.layer then
				f:SetFrameStrata(T.layer)
			end
		end
		-- Blizzard's zoom hover box (Minimap.ZoomHitArea) is only checked with IsMouseOver,
		-- so it never needs clicks: turn them off so it can't block clicks or pings on the map.
		local hit = Minimap and Minimap.ZoomHitArea
		if Usable(hit) then
			if hit.SetMouseClickEnabled then
				hit:SetMouseClickEnabled(false)
			elseif hit.EnableMouse then
				hit:EnableMouse(false)
			end
		end
		self.layering = false
	end)
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
			Square:PlacePieces()
		end)
	end
	if MinimapCluster.SetHeaderUnderneath then
		hooksecurefunc(MinimapCluster, "SetHeaderUnderneath", function(_, under) Square:PlacePieces(under) end)
	end
	if MinimapCluster.SetEditModeScale then
		hooksecurefunc(MinimapCluster, "SetEditModeScale", function() Square:PlacePieces() end)
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
	self:CreateHeader()
	self:InstallHooks()
	self:PlacePieces(Square.HeaderIsUnderneath())
	-- Box and clamp now, not next frame, so they are set before Edit Mode places the cluster.
	ns.RunOutOfCombat("edit-fit", function()
		ns.SafeRun("EditModeBox", Square.FitSelection, Square)
	end)
	-- Tell other addons (LibDBIcon, HereBeDragons...) the map is square. Core only gets
	-- here when no other addon has defined it.
	if not GetMinimapShape then
		function GetMinimapShape() return "SQUARE" end
	end
end
