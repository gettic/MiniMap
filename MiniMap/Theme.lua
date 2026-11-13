-- Mini Map: all art, sizes and colours in one place, so a theme can swap them later.
-- Blizzard art is used by name only; every atlas is checked before use, with a fallback.
local ADDON, ns = ...

local Theme = {
	-- Square mask for the minimap (a plain white square file that exists in every client).
	mask = "Interface\\BUTTONS\\WHITE8X8",

	-- Border of the map, header strip and icon bar. A theme swaps this whole table.
	-- Only with useSliced (off by default): 1st choice ("sliced"): the first usable atlas of `candidates` (main action bar frame,
	--   then the action button frame), cut into 4 corners + 4 edges from its own atlas info
	--   (file, texcoords, slice margins read live from C_Texture.GetAtlasInfo); no centre
	--   piece, so nothing covers the map.
	-- 2nd ("nineslice"): the thin tooltip NineSlice layout (centre hidden).
	-- 3rd ("backdrop"): the tooltip border file via BackdropTemplate.
	-- Sides in the tables below are in the order Left, Top, Right, Bottom.
	border = {
		-- Off: the thin tooltip border (the user's choice). On: the cut atlases below first
		-- (kept for a later theme; `/mmap art` still lists them).
		useSliced = false,
		-- Cut atlases, tried in this order. margins (atlas px) only when the atlas has no
		-- sliceData; share = part of the atlas per side used as corner/edge when it has none
		-- (button frames). shadow = see-through shadow per side, atlas px.
		candidates = {
			-- Main action bar frame (Forever's MainActionBar.xml BorderArt; Blizzard draws it
			-- a few px past the bar on every side, more at the bottom-right in retail).
			{ atlas = "UI-HUD-ActionBar-Frame", margins = { 20, 25, 20, 25 }, shadow = { 2, 2, 6, 5 } },
			-- Action button frame (the extra bars' look; our slots use the same art).
			{ atlas = "UI-HUD-ActionBar-IconFrame-Border", share = 0.3, shadow = { 1, 1, 1, 1 } },
			{ atlas = "UI-HUD-ActionBar-IconFrame", share = 0.3, shadow = { 1, 1, 1, 1 } },
		},
		-- Extra atlases `/mmap art` reports (read only, never drawn from this list).
		reportAtlases = { "ui-hud-actionbar-iconframe-slot", "!ui-hud-actionbar-frame-divider-threeslice-center" },
		scale = 0.5,                -- map border: margins drawn at this size (the file is 2x)
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
	-- Addon compartment (addon counter): bottom-right corner (the zoom buttons moved to the
	-- top-right). compartmentRaise: extra map px in from the corner's top/bottom side.
	compartmentPoint = "BOTTOMRIGHT",
	compartmentRaise = 0,
	-- Blizzard's zoom buttons + their 40 px hover box, moved into this corner (map px):
	-- ZoomIn's outer corner `inset` px in, ZoomOut `step` px further in on both axes (Blizzard's
	-- own spacing), hover box centred `hitCenter` px in.
	zoom = { point = "TOPRIGHT", inset = 4, step = 16, hitCenter = 22 },

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

-- Raw atlas info, read only and safe: the table, or nil.
function Theme.AtlasInfo(name)
	if not (name and C_Texture and C_Texture.GetAtlasInfo) then return end
	local ok, info = pcall(C_Texture.GetAtlasInfo, name)
	if ok and type(info) == "table" then return info end
end

-- Pixel size of the atlas region (GetAtlasInfo `rawSize`, a vector with x/y), or nil.
local function RawSize(info)
	local r = info.rawSize
	if type(r) == "table" and IsNum(r.x) and IsNum(r.y) and r.x > 0 and r.y > 0 then return r.x, r.y end
end

local function SliceMargins(info)
	local s = info.sliceData
	if type(s) == "table" and IsNum(s.marginLeft) and IsNum(s.marginTop)
		and IsNum(s.marginRight) and IsNum(s.marginBottom) then
		return { s.marginLeft, s.marginTop, s.marginRight, s.marginBottom }, s.sliceMode
	end
end

local function Fits(m, w, h) return m[1] + m[3] < w and m[2] + m[4] < h end

-- One candidate atlas's live info for cutting: file, size, texcoords and margins (L, T, R, B)
-- in atlas units. Margins: the atlas's sliceData (converted from file pixels via rawSize when
-- they don't fit the atlas size), else `cand.share` of the atlas per side, else
-- `cand.margins`. Returns the info, or nil + a reason code (missing, nofile, badsize,
-- badcoords, nomargins, nofit) when unusable (then the next candidate / fallback is used).
function Theme.SliceInfo(cand)
	if type(cand) ~= "table" then return nil, "missing" end
	local info = Theme.AtlasInfo(cand.atlas)
	if not info then return nil, "missing" end
	local file = info.file or info.filename
	if not file then return nil, "nofile" end
	local w, h = info.width, info.height
	if not (IsNum(w) and IsNum(h) and w > 0 and h > 0) then return nil, "badsize" end
	local L, R, T, B = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
	if not (IsNum(L) and IsNum(R) and IsNum(T) and IsNum(B)) then return nil, "badcoords" end
	local m, mode = SliceMargins(info)
	local from = "atlas"
	if m and not Fits(m, w, h) then
		local rw, rh = RawSize(info)
		if rw then
			m = { m[1] * w / rw, m[2] * h / rh, m[3] * w / rw, m[4] * h / rh }
			from = "atlaspx"
		end
	elseif not m then
		if IsNum(cand.share) and cand.share > 0 and cand.share < 0.5 then
			m, from = { w * cand.share, h * cand.share, w * cand.share, h * cand.share }, "share"
		else
			m, from = cand.margins, "theme"
		end
	end
	if type(m) ~= "table" then return nil, "nomargins" end
	local any = false
	for i = 1, 4 do
		if not (IsNum(m[i]) and m[i] >= 0) then return nil, "nomargins" end
		if m[i] > 0 then any = true end
	end
	if not any then return nil, "nomargins" end
	if not Fits(m, w, h) then return nil, "nofit" end
	return {
		atlas = cand.atlas, file = file, w = w, h = h, L = L, R = R, T = T, B = B, m = m,
		from = from, mode = mode,
	}
end

-- The first usable candidate: its info + the candidate, and the reasons earlier candidates
-- were skipped (list of { atlas, reason }).
function Theme.PickSliced()
	local skipped = {}
	for _, cand in ipairs(Theme.border.candidates or {}) do
		local si, why = Theme.SliceInfo(cand)
		if si then return si, cand, skipped end
		skipped[#skipped + 1] = { cand.atlas, why }
	end
	return nil, nil, skipped
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

-- Gives `frame` a Blizzard border: the first usable cut candidate (map: border.scale, strip:
-- border.stripScale), else the tooltip NineSlice, else the backdrop file. The frame should be
-- made with BackdropTemplate so the last fallback works. Returns the kind used, or nil.
local borderKind = setmetatable({}, { __mode = "k" })   -- [our frame] = "sliced"/"nineslice"/"backdrop"
local borderScale = setmetatable({}, { __mode = "k" })  -- [our frame] = scale of the sliced pieces
local borderMargins = setmetatable({}, { __mode = "k" }) -- [our frame] = margins used (L, T, R, B)
local borderShadow = setmetatable({}, { __mode = "k" })  -- [our frame] = candidate's shadow (L, T, R, B)
local borderAtlas = setmetatable({}, { __mode = "k" })   -- [our frame] = candidate atlas name
Theme.borderPieces = setmetatable({}, { __mode = "k" }) -- [our frame] = sliced pieces by key

function Theme.ApplyBorder(frame, strip)
	local b = Theme.border
	if b.useSliced and frame.CreateTexture then
		local scale = strip and b.stripScale or b.scale
		for _, cand in ipairs(b.candidates or {}) do
			local si = Theme.SliceInfo(cand)
			if si then
				local made = {}
				local ok, pieces = pcall(MakeSliced, frame, si, scale, made)
				if ok and pieces then
					borderKind[frame], borderScale[frame], borderMargins[frame] = "sliced", scale, si.m
					borderShadow[frame] = type(cand.shadow) == "table" and cand.shadow or { 0, 0, 0, 0 }
					borderAtlas[frame] = cand.atlas
					Theme.borderPieces[frame] = pieces
					return "sliced"
				end
				for _, tex in ipairs(made) do
					if tex.Hide then tex:Hide() end
				end
			end
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

function Theme.BorderAtlas(frame)
	return frame and borderAtlas[frame] or nil
end

-- How far `frame`'s visible border sits inside its edge per side (own units), returned as
-- left, right, top, bottom: the shadow for the sliced frame, layoutInset for the tooltip
-- layout, 0 for the backdrop or no border.
function Theme.ArtInset(frame)
	local kind = borderKind[frame]
	if kind == "sliced" then
		local s, k = borderShadow[frame] or { 0, 0, 0, 0 }, borderScale[frame] or 1
		return (s[1] or 0) * k, (s[3] or 0) * k, (s[2] or 0) * k, (s[4] or 0) * k
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

-- Short number for chat lines (2 decimals at most).
local function Num(v)
	if not IsNum(v) then return tostring(v) end
	local s = ("%.2f"):format(v):gsub("0+$", ""):gsub("%.$", "")
	return s
end

local function Reason(code)
	local r = ns.L and ns.L.REASON
	return (r and r[code]) or tostring(code)
end

-- What the map's border is, for chat: the kind in use (+ atlas when cut) and, when the
-- first candidate (the main action bar frame) wasn't used, which candidates were skipped
-- and why. Returns kind text, skipped text (or nil).
function Theme.BorderUse(frame)
	local kind = (frame and borderKind[frame]) or "-"
	if kind == "sliced" and borderAtlas[frame] then kind = kind .. " " .. borderAtlas[frame] end
	if not Theme.border.useSliced then
		local r = ns.L and ns.L.ART_SLICED_OFF
		return kind, r
	end
	local _, _, skipped = Theme.PickSliced()
	if #skipped == 0 then return kind end
	local parts = {}
	for _, s in ipairs(skipped) do parts[#parts + 1] = tostring(s[1]) .. ": " .. Reason(s[2]) end
	return kind, table.concat(parts, "; ")
end

-- One line for /mmap debug: the atlas used (size, margins + mode + source) or NO ATLAS,
-- and the kind in use on `frame` with the skipped candidates' reasons.
function Theme.BorderDebug(frame)
	local L = ns.L or {}
	local si = Theme.PickSliced()
	local art
	if si then
		local m = si.m
		art = ("%s %sx%s, slice %s,%s,%s,%s mode %s (%s)"):format(tostring(si.atlas), Num(si.w), Num(si.h),
			Num(m[1]), Num(m[2]), Num(m[3]), Num(m[4]), tostring(si.mode or "-"),
			(L.FROM and L.FROM[si.from]) or si.from)
	else
		art = L.DEBUG_NO_ATLAS or "NO ATLAS"
	end
	local kind, why = Theme.BorderUse(frame)
	if why then kind = kind .. " (" .. why .. ")" end
	return art, kind
end

-- Lines for /mmap art: one per candidate and report atlas (found with size, raw size, file,
-- slice margins + mode; or missing), then the border in use and why candidates were skipped.
-- Read only.
function Theme.ArtReport(frame)
	local L = ns.L or {}
	local lines, seen, names = {}, {}, {}
	for _, cand in ipairs(Theme.border.candidates or {}) do names[#names + 1] = cand.atlas end
	for _, n in ipairs(Theme.border.reportAtlases or {}) do names[#names + 1] = n end
	names[#names + 1] = Theme.border.checkAtlas
	for _, name in ipairs(names) do
		if name and not seen[name] then
			seen[name] = true
			local info = Theme.AtlasInfo(name)
			if info then
				local rw, rh = RawSize(info)
				local m, mode = SliceMargins(info)
				local slice = m and ("%s,%s,%s,%s mode %s"):format(Num(m[1]), Num(m[2]), Num(m[3]), Num(m[4]), tostring(mode))
					or (L.ART_NO_SLICE or "none")
				lines[#lines + 1] = (L.ART_FOUND or "%s: found %sx%s, raw %s, file %s, slice %s"):format(name,
					Num(info.width), Num(info.height), rw and (Num(rw) .. "x" .. Num(rh)) or "-",
					tostring(info.file or info.filename), slice)
			else
				lines[#lines + 1] = (L.ART_MISSING or "%s: missing"):format(name)
			end
		end
	end
	local kind, why = Theme.BorderUse(frame)
	lines[#lines + 1] = (L.ART_IN_USE or "Border in use: %s"):format(kind)
	if why then lines[#lines + 1] = (L.ART_SKIPPED or "Not used: %s"):format(why) end
	return lines
end

-- Template name for frames that may need the backdrop fallback.
Theme.backdropTemplate = BackdropTemplateMixin and "BackdropTemplate" or nil
