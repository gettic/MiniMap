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

function Square:InstallHooks()
	if self.hooked then return end
	self.hooked = true
	if MinimapCluster and MinimapCluster.UpdateMinimapConfig then
		hooksecurefunc(MinimapCluster, "UpdateMinimapConfig", function() Square:Reapply() end)
	end
end

function Square:Setup()
	if not (Minimap and Container()) then return end
	self.active = true
	self:ApplyMask()
	self:HideRoundArt()
	self:CreateBorder()
	self:PlaceCoords()
	self:InstallHooks()
	-- Tell other addons (LibDBIcon, HereBeDragons...) the map is square. Core only gets
	-- here when no other addon has defined it.
	if not GetMinimapShape then
		function GetMinimapShape() return "SQUARE" end
	end
end
