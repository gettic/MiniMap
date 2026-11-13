-- Mini Map: all art, sizes and colours in one place, so a theme can swap them later.
-- Blizzard art is used by name only; every atlas is checked before use, with a fallback.
local ADDON, ns = ...

local Theme = {
	-- Square mask for the minimap (a plain white square file that exists in every client).
	mask = "Interface\\BUTTONS\\WHITE8X8",

	-- Border: Blizzard's thin tooltip NineSlice layout, checked by one of its atlases. Its
	-- pieces sit inside the frame (nothing sticks out), and its background piece is hidden.
	borderLayout = "TooltipDefaultLayout",
	borderCheckAtlas = "Tooltip-NineSlice-CornerTopLeft",
	borderOutset = 3, -- how far the border frame sits outside the map
	-- See-through art pixels between a bordered frame's edge and its visible line (tooltip
	-- layout only; 0 for the fallback). Edit Mode's box is pulled in by this much per side.
	selectionInset = 2,

	-- Fallback border when the layout or its atlas is missing.
	fallbackEdgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	fallbackEdgeSize = 8,
	fallbackEdgeColor = { 0.8, 0.8, 0.8, 1 },

	-- Backgrounds (icon bar only; the map fills its own square).
	bgTexture = "Interface\\BUTTONS\\WHITE8X8",
	bgColor = { 0, 0, 0, 0.6 },
	bgInset = 3,

	-- Icon bar.
	iconSize = 24,
	iconGap = 2,
	barPadding = 5,
	barGap = 2, -- space between the map border and the bar

	-- Player coordinates, moved inside the map's bottom edge.
	coordsOffsetY = 4,
	-- Dark box behind them: Blizzard's tooltip background file tinted black (fallback: plain
	-- white square, same tint). `atlas` (checked first) is free for a theme. padX/padY: map px
	-- around the text; throttle: seconds between size checks.
	coordsBox = {
		atlas = nil,
		file = "Interface\\Tooltips\\UI-Tooltip-Background",
		fallback = "Interface\\BUTTONS\\WHITE8X8",
		color = { 0, 0, 0, 0.6 },
		padX = 4,
		padY = 2,
		throttle = 0.1,
	},

	-- Bar slots: every button gets the same square slot (iconSize), its icon inset and
	-- cropped, and Blizzard's action-button frame, hover and pressed art over it.
	-- `file` is the fallback when the atlas is missing; `fileScale` sizes a fallback file
	-- whose art is bigger than its button (UI-Quickslot2: 66 px around a 36 px button).
	slot = {
		iconInset = 2,
		iconCoords = { 0.08, 0.92, 0.08, 0.92 },
		frame = { atlas = "UI-HUD-ActionBar-IconFrame", file = "Interface\\Buttons\\UI-Quickslot2", fileScale = 66 / 36 },
		hover = { atlas = "UI-HUD-ActionBar-IconFrame-Mouseover", file = "Interface\\Buttons\\ButtonHilight-Square", blend = "ADD" },
		down = { atlas = "UI-HUD-ActionBar-IconFrame-Down", file = "Interface\\Buttons\\UI-Quickslot-Depress" },
	},

	-- Round-minimap art other addons put on their buttons (LibDBIcon ring, background,
	-- highlight). Hidden (alpha 0) in the bar. Paths: lower case, no extension.
	foreignArt = {
		ids = { [136430] = true, [136467] = true, [136477] = true },
		paths = {
			["interface\\minimap\\minimap-trackingborder"] = true,
			["interface\\minimap\\ui-minimap-background"] = true,
			["interface\\minimap\\ui-minimap-zoombutton-highlight"] = true,
		},
	},

	-- Header strip behind Blizzard's zone/clock header (same border and background as the bar).
	headerPad = 2,        -- gap between the map border and the strip (same as barGap)
	headerHeight = 27,
	headerMinWidth = 196, -- the header pieces need about 188 px
	headerOffsetX = -1,   -- centres tracking + zone text + clock in the strip
	headerTextY = 2,      -- zone button (23 px) inside the 27 px strip

	-- Mail and addon compartment: in the map's corners, this far in (map pixels).
	cornerInset = 5,
	-- Addon compartment (addon counter): bottom-right, raised this many map px more so it sits
	-- above Blizzard's zoom buttons and their 40 px hover box (which reaches 42 px up).
	compartmentPoint = "BOTTOMRIGHT",
	compartmentRaise = 39, -- 5 + 39 = 44 px up

	-- Day/night disc: in the map's bottom-left corner (top-left with Header Underneath).
	dielAtlas = "UI-HUD-Minimap-Frame-Cycle",
	dielSize = 38,
	dielInset = 4,

	-- Frame strata for the whole map (map, border, header, bar, buttons, corner pieces), so
	-- other addons' frames draw over it. The only place this is set.
	layer = "BACKGROUND",
	-- Popups a bar button opens (a child frame bigger than its slot or reaching outside it) sit
	-- this many levels above the bar, over every slot (+2) and slot overlay (+3). Same strata.
	popupLevel = 20,

	-- Path pieces we draw for another addon's minimap path (Compat_Zygor.lua corner pieces):
	-- Blizzard's flight-path line atlas, else a plain white square file tinted in the path's
	-- colour. Thickness and alpha are multiplied onto the path's own.
	pathLine = { atlas = "_UI-Taxi-Line-horizontal", file = "Interface\\BUTTONS\\WHITE8X8", thicknessScale = 1, alpha = 1 },
}
ns.Theme = Theme

function Theme.HasAtlas(name)
	if not (name and C_Texture and C_Texture.GetAtlasInfo) then return false end
	return C_Texture.GetAtlasInfo(name) ~= nil
end

-- Sets `atlas` on `tex` when the client has it, otherwise the fallback `file`.
-- Returns true when the atlas was used.
function Theme.SetAtlasOr(tex, atlas, file)
	if atlas and tex.SetAtlas and Theme.HasAtlas(atlas) then
		tex:SetAtlas(atlas)
		return true
	end
	if file then tex:SetTexture(file) end
	return false
end

-- Border only: hides every NineSlice piece that isn't an edge or a corner (the tooltip
-- layout's "Center" background would otherwise cover the map).
local function HideFill(frame)
	local layout = NineSliceUtil.GetLayout and NineSliceUtil.GetLayout(Theme.borderLayout)
	local names = { Center = true }
	if type(layout) == "table" then
		for key, piece in pairs(layout) do
			if type(piece) == "table" then names[key] = true end
		end
	end
	for key in pairs(names) do
		local tex = frame[key]
		if type(key) == "string" and not (key:find("Corner") or key:find("Edge"))
			and type(tex) == "table" and tex.Hide then
			tex:Hide()
		end
	end
end

-- Gives `frame` a Blizzard border. The frame should be made with BackdropTemplate so the
-- fallback works. Returns "nineslice", "backdrop" or nil.
local borderKind = setmetatable({}, { __mode = "k" }) -- [our frame] = "nineslice" / "backdrop"

function Theme.ApplyBorder(frame)
	if NineSliceUtil and NineSliceUtil.ApplyLayoutByName and Theme.HasAtlas(Theme.borderCheckAtlas) then
		local ok = pcall(NineSliceUtil.ApplyLayoutByName, frame, Theme.borderLayout)
		if ok then
			HideFill(frame)
			borderKind[frame] = "nineslice"
			return "nineslice"
		end
	end
	if frame.SetBackdrop then
		borderKind[frame] = "backdrop"
		frame:SetBackdrop({ edgeFile = Theme.fallbackEdgeFile, edgeSize = Theme.fallbackEdgeSize })
		if frame.SetBackdropBorderColor then
			frame:SetBackdropBorderColor(unpack(Theme.fallbackEdgeColor))
		end
		return "backdrop"
	end
end

-- How far `frame`'s visible border sits inside its edge (own units): selectionInset for the
-- tooltip layout, 0 for the fallback or no border.
function Theme.ArtInset(frame)
	return borderKind[frame] == "nineslice" and (Theme.selectionInset or 0) or 0
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
