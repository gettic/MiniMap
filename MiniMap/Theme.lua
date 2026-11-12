-- Mini Map: all art, sizes and colours in one place, so a theme can swap them later.
-- Blizzard art is used by name only; every atlas is checked before use, with a fallback.
local ADDON, ns = ...

local Theme = {
	-- Square mask for the minimap (a plain white square file that exists in every client).
	mask = "Interface\\BUTTONS\\WHITE8X8",

	-- Border: Blizzard NineSlice layout, checked by one of its atlases.
	borderLayout = "GenericMetal",
	borderCheckAtlas = "UI-Frame-GenericMetal-Corner",
	borderOutset = 2, -- how far the border frame sits outside the map

	-- Fallback border when the layout or its atlas is missing.
	fallbackEdgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	fallbackEdgeSize = 12,
	fallbackEdgeColor = { 0.8, 0.8, 0.8, 1 },

	-- Backgrounds (icon bar only; the map fills its own square).
	bgTexture = "Interface\\BUTTONS\\WHITE8X8",
	bgColor = { 0, 0, 0, 0.6 },
	bgInset = 3,

	-- Icon bar.
	iconSize = 24,
	iconGap = 2,
	barPadding = 5,
	barGap = 6, -- space between the map border and the bar (room for the metal corners)

	-- Player coordinates, moved inside the map's bottom edge.
	coordsOffsetY = 4,
}
ns.Theme = Theme

function Theme.HasAtlas(name)
	if not (name and C_Texture and C_Texture.GetAtlasInfo) then return false end
	return C_Texture.GetAtlasInfo(name) ~= nil
end

-- Gives `frame` a Blizzard border. The frame should be made with BackdropTemplate so the
-- fallback works. Returns "nineslice", "backdrop" or nil.
function Theme.ApplyBorder(frame)
	if NineSliceUtil and NineSliceUtil.ApplyLayoutByName and Theme.HasAtlas(Theme.borderCheckAtlas) then
		local ok = pcall(NineSliceUtil.ApplyLayoutByName, frame, Theme.borderLayout)
		if ok then return "nineslice" end
	end
	if frame.SetBackdrop then
		frame:SetBackdrop({ edgeFile = Theme.fallbackEdgeFile, edgeSize = Theme.fallbackEdgeSize })
		if frame.SetBackdropBorderColor then
			frame:SetBackdropBorderColor(unpack(Theme.fallbackEdgeColor))
		end
		return "backdrop"
	end
end

-- Dark see-through background inside `frame`.
function Theme.AddBackground(frame)
	local tex = frame:CreateTexture(nil, "BACKGROUND")
	tex:SetTexture(Theme.bgTexture)
	tex:SetVertexColor(unpack(Theme.bgColor))
	tex:SetPoint("TOPLEFT", Theme.bgInset, -Theme.bgInset)
	tex:SetPoint("BOTTOMRIGHT", -Theme.bgInset, Theme.bgInset)
	return tex
end

-- Template name for frames that may need the backdrop fallback.
Theme.backdropTemplate = BackdropTemplateMixin and "BackdropTemplate" or nil
