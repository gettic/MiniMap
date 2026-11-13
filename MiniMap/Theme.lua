-- Mini Map: all art, sizes and colours in one place, so a theme can swap them later.
-- Blizzard art is used by name only; every atlas is checked before use, with a fallback.
local ADDON, ns = ...

local Theme = {
	-- Square mask for the minimap (a plain white square file that exists in every client).
	mask = "Interface\\BUTTONS\\WHITE8X8",

	-- Border of the map, header strip and icon bar. A theme swaps this whole table.
	-- 1st choice ("sliced"): Blizzard's main action bar frame atlas, cut into 4 corners + 4
	--   edges from its own atlas info (file, texcoords, slice margins read live from
	--   C_Texture.GetAtlasInfo); no centre piece, so nothing covers the map.
	-- 2nd ("nineslice"): the thin tooltip NineSlice layout (centre hidden).
	-- 3rd ("backdrop"): the tooltip border file via BackdropTemplate.
	-- Sides in the tables below are in the order Left, Top, Right, Bottom.
	border = {
		atlas = "UI-HUD-ActionBar-Frame",
		margins = { 20, 25, 20, 25 }, -- atlas px; only used when the client has no sliceData
		shadow = { 2, 2, 6, 5 },      -- see-through shadow per side, atlas px (Blizzard draws the
		                              -- bar art 4/4 px past top-left, 8/7 px past bottom-right)
		scale = 0.5,                  -- map border: margins drawn at this size (the file is 2x)
		stripScale = 0.35,            -- header strip and icon bar (only 31-40 px tall)
		overlap = 2,                  -- map px the inner edge of the frame reaches over the map
		gap = 2,                      -- visible gap between the map's frame and a strip's frame
		headerHeight = 31,            -- header strip height with this frame
		barPadding = 8,               -- icon bar padding with this frame
		drawLayer = "BORDER",
		-- Fallback 1: tooltip layout, checked by one of its atlases; 3 px outside the map,
		-- 2 px see-through margin (Edit Mode's box is pulled in by it).
		layout = "TooltipDefaultLayout",
		checkAtlas = "Tooltip-NineSlice-CornerTopLeft",
		layoutOutset = 3,
		layoutInset = 2,
		-- Fallback 2: backdrop edge file.
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 8,
		edgeColor = { 0.8, 0.8, 0.8, 1 },
		edgeOutset = 3,
	},

	-- Backgrounds (icon bar only; the map fills its own square).
	bgTexture = "Interface\\BUTTONS\\WHITE8X8",
	bgColor = { 0, 0, 0, 0.6 },
	bgInset = 3,

	-- Icon bar.
	iconSize = 24,
	iconGap = 2,
	barPadding = 5,
	barGap = 2, -- space between the map border and the bar (fallback borders)

	-- Player coordinates, moved inside the map's bottom edge.
	coordsOffsetY = 4,
	-- Frame levels above Minimap's: coordinates over their box, both over map pins (Library
	-- Books pins sit at +5 once Compat_LibraryBooks moves them into `layer`).
	coordsLevel = 7,
	coordsBoxLevel = 6,
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
	headerPad = 2,        -- gap between the map border and the strip (fallback borders)
	headerHeight = 27,    -- fallback borders; border.headerHeight with the action bar frame
	headerMinWidth = 196, -- the header pieces need about 188 px
	headerOffsetX = -1,   -- centres tracking + zone text + clock in the strip
	headerTextY = 2,      -- zone button (23 px) inside the 27 px strip

	-- Mail and addon compartment: in the map's corners, this far in (map pixels).
	cornerInset = 5,
	-- Addon compartment (addon counter): top-right corner. compartmentRaise: extra map px in from
	-- the corner's top/bottom side (e.g. 39 with "BOTTOMRIGHT" clears the zoom buttons' hover box).
	compartmentPoint = "TOPRIGHT",
	compartmentRaise = 0,

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
	local layout = NineSliceUtil.GetLayout and NineSliceUtil.GetLayout(Theme.border.layout)
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

local function IsNum(v) return type(v) == "number" and v == v end

-- The border atlas's live info: file, size, texcoords and slice margins (L, T, R, B). Margins
-- come from the atlas's sliceData, else from Theme.border.margins. nil when the client has no
-- such atlas or its info is unusable (then the fallbacks are used).
function Theme.SliceInfo()
	local b = Theme.border
	if not (b and b.atlas and C_Texture and C_Texture.GetAtlasInfo) then return end
	local ok, info = pcall(C_Texture.GetAtlasInfo, b.atlas)
	if not ok or type(info) ~= "table" then return end
	local file = info.file or info.filename
	local w, h = info.width, info.height
	local L, R, T, B = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
	if not (file and IsNum(w) and IsNum(h) and w > 0 and h > 0
		and IsNum(L) and IsNum(R) and IsNum(T) and IsNum(B)) then return end
	local s, m, from = info.sliceData, nil, "theme"
	if type(s) == "table" and IsNum(s.marginLeft) and IsNum(s.marginTop)
		and IsNum(s.marginRight) and IsNum(s.marginBottom) then
		m, from = { s.marginLeft, s.marginTop, s.marginRight, s.marginBottom }, "atlas"
	else
		m = b.margins
	end
	if type(m) ~= "table" then return end
	for i = 1, 4 do
		if not (IsNum(m[i]) and m[i] > 0) then return end
	end
	if m[1] + m[3] >= w or m[2] + m[4] >= h then return end
	return {
		file = file, w = w, h = h, L = L, R = R, T = T, B = B, m = m, from = from,
		mode = type(s) == "table" and s.sliceMode or nil,
	}
end

-- 4 corners + 4 edges (no centre) cut from the atlas's own texcoords, each piece's size
-- margin * scale (own units). Corners fixed at the frame's corners, edges between them.
-- Made textures go into `made` so a failure can hide them again.
local PIECES = {
	-- key, column, row
	{ "TopLeftCorner", 1, 1 }, { "TopEdge", 2, 1 }, { "TopRightCorner", 3, 1 },
	{ "LeftEdge", 1, 2 }, { "RightEdge", 3, 2 },
	{ "BottomLeftCorner", 1, 3 }, { "BottomEdge", 2, 3 }, { "BottomRightCorner", 3, 3 },
}
Theme.slicePieces = PIECES

local function MakeSliced(frame, si, scale, made)
	local mL, mT, mR, mB = si.m[1], si.m[2], si.m[3], si.m[4]
	local du, dv = (si.R - si.L) / si.w, (si.B - si.T) / si.h
	local us = { si.L, si.L + mL * du, si.R - mR * du, si.R }
	local vs = { si.T, si.T + mT * dv, si.B - mB * dv, si.B }
	local layer = Theme.border.drawLayer or "BORDER"
	local p = {}
	for _, d in ipairs(PIECES) do
		local key, c, r = d[1], d[2], d[3]
		local tex = frame:CreateTexture(nil, layer)
		made[#made + 1] = tex
		tex:SetTexture(si.file)
		tex:SetTexCoord(us[c], us[c + 1], vs[r], vs[r + 1])
		p[key] = tex
	end
	local wL, wR, hT, hB = mL * scale, mR * scale, mT * scale, mB * scale
	p.TopLeftCorner:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	p.TopLeftCorner:SetSize(wL, hT)
	p.TopRightCorner:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
	p.TopRightCorner:SetSize(wR, hT)
	p.BottomLeftCorner:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
	p.BottomLeftCorner:SetSize(wL, hB)
	p.BottomRightCorner:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
	p.BottomRightCorner:SetSize(wR, hB)
	p.TopEdge:SetPoint("TOPLEFT", p.TopLeftCorner, "TOPRIGHT", 0, 0)
	p.TopEdge:SetPoint("BOTTOMRIGHT", p.TopRightCorner, "BOTTOMLEFT", 0, 0)
	p.BottomEdge:SetPoint("TOPLEFT", p.BottomLeftCorner, "TOPRIGHT", 0, 0)
	p.BottomEdge:SetPoint("BOTTOMRIGHT", p.BottomRightCorner, "BOTTOMLEFT", 0, 0)
	p.LeftEdge:SetPoint("TOPLEFT", p.TopLeftCorner, "BOTTOMLEFT", 0, 0)
	p.LeftEdge:SetPoint("BOTTOMRIGHT", p.BottomLeftCorner, "TOPRIGHT", 0, 0)
	p.RightEdge:SetPoint("TOPLEFT", p.TopRightCorner, "BOTTOMLEFT", 0, 0)
	p.RightEdge:SetPoint("BOTTOMRIGHT", p.BottomRightCorner, "TOPRIGHT", 0, 0)
	return p
end

-- Gives `frame` a Blizzard border: the sliced action bar frame (map: border.scale, strip:
-- border.stripScale), else the tooltip NineSlice, else the backdrop file. The frame should be
-- made with BackdropTemplate so the last fallback works. Returns the kind used, or nil.
local borderKind = setmetatable({}, { __mode = "k" })   -- [our frame] = "sliced"/"nineslice"/"backdrop"
local borderScale = setmetatable({}, { __mode = "k" })  -- [our frame] = scale of the sliced pieces
local borderMargins = setmetatable({}, { __mode = "k" }) -- [our frame] = margins used (L, T, R, B)
Theme.borderPieces = setmetatable({}, { __mode = "k" }) -- [our frame] = sliced pieces by key

function Theme.ApplyBorder(frame, strip)
	local b = Theme.border
	local si = frame.CreateTexture and Theme.SliceInfo()
	if si then
		local scale = strip and b.stripScale or b.scale
		local made = {}
		local ok, pieces = pcall(MakeSliced, frame, si, scale, made)
		if ok and pieces then
			borderKind[frame], borderScale[frame], borderMargins[frame] = "sliced", scale, si.m
			Theme.borderPieces[frame] = pieces
			return "sliced"
		end
		for _, tex in ipairs(made) do
			if tex.Hide then tex:Hide() end
		end
	end
	if NineSliceUtil and NineSliceUtil.ApplyLayoutByName and Theme.HasAtlas(b.checkAtlas) then
		local ok = pcall(NineSliceUtil.ApplyLayoutByName, frame, b.layout)
		if ok then
			HideFill(frame)
			borderKind[frame] = "nineslice"
			return "nineslice"
		end
	end
	if frame.SetBackdrop then
		borderKind[frame] = "backdrop"
		frame:SetBackdrop({ edgeFile = b.edgeFile, edgeSize = b.edgeSize })
		if frame.SetBackdropBorderColor then
			frame:SetBackdropBorderColor(unpack(b.edgeColor))
		end
		return "backdrop"
	end
end

function Theme.BorderKind(frame)
	return frame and borderKind[frame] or nil
end

-- How far `frame`'s visible border sits inside its edge per side (own units), returned as
-- left, right, top, bottom: the shadow for the sliced frame, layoutInset for the tooltip
-- layout, 0 for the backdrop or no border.
function Theme.ArtInset(frame)
	local kind = borderKind[frame]
	if kind == "sliced" then
		local s, k = Theme.border.shadow, borderScale[frame] or 1
		return s[1] * k, s[3] * k, s[2] * k, s[4] * k
	elseif kind == "nineslice" then
		local i = Theme.border.layoutInset or 0
		return i, i, i, i
	end
	return 0, 0, 0, 0
end

-- How far the map's border frame sits outside the map per side (map units), returned as
-- left, right, top, bottom. Sliced: the frame's inner edge reaches `overlap` px over the map.
function Theme.BorderOutset(frame)
	local b = Theme.border
	local kind = borderKind[frame]
	if kind == "sliced" then
		local m, k, o = borderMargins[frame], borderScale[frame] or 1, b.overlap or 0
		local function side(i) return math.max(0, m[i] * k - o) end
		return side(1), side(3), side(2), side(4)
	elseif kind == "nineslice" then
		local o = b.layoutOutset or 0
		return o, o, o, o
	end
	local o = b.edgeOutset or 0
	return o, o, o, o
end

local SIDE = { LEFT = 1, RIGHT = 2, TOP = 3, BOTTOM = 4 }

-- Gap (map px) between the map's border `a` (side aSide) and a strip `b` (side bSide; `k` =
-- strip units -> map px). Sliced frames: border.gap between the visible edges, so their
-- see-through shadows may overlap. Other kinds: `base` as before.
function Theme.StripGap(base, a, aSide, b, bSide, k)
	if borderKind[a] ~= "sliced" and borderKind[b] ~= "sliced" then return base end
	local ia = select(SIDE[aSide], Theme.ArtInset(a))
	local ib = select(SIDE[bSide], Theme.ArtInset(b)) * (k or 1)
	return (Theme.border.gap or 0) - ia - ib
end

-- Header strip height and icon bar padding for `frame`'s border kind.
function Theme.HeaderHeight(frame)
	return borderKind[frame] == "sliced" and Theme.border.headerHeight or Theme.headerHeight
end

function Theme.BarPadding(frame)
	return borderKind[frame] == "sliced" and Theme.border.barPadding or Theme.barPadding
end

-- Dark see-through background inside `frame` (sliced: inside the shadow, + 1 px).
function Theme.AddBackground(frame)
	local tex = frame:CreateTexture(nil, "BACKGROUND")
	tex:SetTexture(Theme.bgTexture)
	tex:SetVertexColor(unpack(Theme.bgColor))
	local l, r, t, b
	if borderKind[frame] == "sliced" then
		l, r, t, b = Theme.ArtInset(frame)
		l, r, t, b = l + 1, r + 1, t + 1, b + 1
	else
		l, r, t, b = Theme.bgInset, Theme.bgInset, Theme.bgInset, Theme.bgInset
	end
	tex:SetPoint("TOPLEFT", l, -t)
	tex:SetPoint("BOTTOMRIGHT", -r, b)
	return tex
end

-- One line for /mmap debug: atlas found or not, size, slice margins + mode and where they
-- came from, and the kind in use on `frame`.
function Theme.BorderDebug(frame)
	local L = ns.L or {}
	local si = Theme.SliceInfo()
	local art
	if si then
		local m = si.m
		art = ("%s %sx%s, slice %s,%s,%s,%s mode %s (%s)"):format(Theme.border.atlas, tostring(si.w), tostring(si.h),
			tostring(m[1]), tostring(m[2]), tostring(m[3]), tostring(m[4]), tostring(si.mode or "-"),
			si.from == "atlas" and (L.DEBUG_FROM_ATLAS or "atlas") or (L.DEBUG_FROM_THEME or "theme"))
	else
		art = (L.DEBUG_NO_ATLAS or "NO ATLAS") .. " " .. tostring(Theme.border.atlas)
	end
	return art, (frame and borderKind[frame]) or "-"
end

-- Template name for frames that may need the backdrop fallback.
Theme.backdropTemplate = BackdropTemplateMixin and "BackdropTemplate" or nil
