-- Mini Map: the bar under the map that collects minimap buttons.
-- Addon buttons are moved into the bar. Blizzard frames are never reparented: the only
-- Blizzard button handled here (the event button) is just anchored into a bar slot.
local ADDON, ns = ...
local T = ns.Theme

local Bar = {}
ns.IconBar = Bar

local bar               -- the bar frame
local collected = {}    -- list of addon buttons in the bar
local isCollected = {}  -- [frame] = true
local slotOf = {}       -- [frame] = slot index in the current layout
local placing = false   -- true while we move a button ourselves (stops hook loops)
local snapping = false  -- true while we size/scale a button ourselves (stops hook loops)
local slotArt = {}      -- [button] = our slot overlay frame (child of the bar)
local hiddenArt = {}    -- [texture] = true: foreign art we set to alpha 0
local cropped = {}      -- [texture] = true: edge already cropped (never twice)
local PlaceOne          -- defined below (used by Snap first)
local headerUnder = false
local layoutPending, scanPending = false, false
local perRow, rowsUsed = 1, 1
Bar.shownCount = 0

-- Bar width = the map border's width (worked out from the map's own size, so it is right
-- even before the game has laid the frames out).
local function BarWidth()
	local w = Minimap:GetWidth()
	if ns.Square.border then w = w + 2 * T.borderOutset end
	return w
end

-- Names that are never buttons to collect (map pins and our own frames).
local SKIP_PATTERNS = { "Pin", "HereBeDragons", "GatherMate", "TomTom", "Questie", "HandyNotes", "^MiniMapForever" }
-- Names that look like minimap buttons.
local BUTTON_PATTERNS = {
	"[Mm]ini[Mm]ap.*[Bb]utton", "[Bb]utton.*[Mm]ini[Mm]ap", "[Mm]ini[Mm]ap[Ii]con", "[Mm]ini[Mm]ap[Bb]tn",
	"[Mm]ap[Ii]con$", "^LibDBIcon10_",
}
-- Buttons of addons that make their own (non-LibDBIcon) minimap button, found by global
-- name wherever they are parented. Use /mmap names over a button to learn its name.
local KNOWN_BUTTONS = { "ZygorGuidesViewerMapIcon", "AllTheThings-Minimap" }

local function MatchesAny(name, patterns)
	for _, p in ipairs(patterns) do
		if name:find(p) then return true end
	end
	return false
end

local function EventButton()
	return MinimapBackdrop and MinimapBackdrop.ExternalEventURLButton
end

local function LibDBIcon()
	return LibStub and LibStub("LibDBIcon-1.0", true)
end

---------------------------------------------------------------------------
-- Which frames get collected
---------------------------------------------------------------------------
-- force = true for buttons LibDBIcon reports and KNOWN_BUTTONS (no name/size guessing needed).
local function IsCollectable(f, force)
	if not f or isCollected[f] or f == bar then return false end
	if type(f) ~= "table" or not (f.GetObjectType and f.GetName) then return false end
	if f.IsForbidden and f:IsForbidden() then return false end
	if f.IsProtected and f:IsProtected() then return false end
	local name = f:GetName()
	if type(name) ~= "string" then return false end
	if _G[name] == f and issecurevariable(name) then return false end -- a Blizzard frame
	-- LibDBIcon buttons are always minimap buttons, even when the addon's name is on the skip
	-- list (LibDBIcon10_Questie, LibDBIcon10_TomTom...), so check them before the skip list.
	if force or name:find("^LibDBIcon10_") then return true end
	if MatchesAny(name, SKIP_PATTERNS) then return false end
	if f:GetObjectType() ~= "Button" then return false end
	local w, h = f:GetSize()
	local big = math.max(w or 0, h or 0)
	if big < 16 or big > 40 then return false end
	return MatchesAny(name, BUTTON_PATTERNS)
end

---------------------------------------------------------------------------
-- Placing buttons
---------------------------------------------------------------------------
local function ScaleFor(f)
	local w, h = f:GetSize()
	local big = math.max(w or 0, h or 0)
	if big <= 0 then return 1 end
	return T.iconSize / big
end

---------------------------------------------------------------------------
-- Uniform slots: every collected button is a 24 px square with its icon cropped to fill,
-- the owner's round-minimap art hidden, and our slot art (Blizzard action-button frame,
-- hover, pressed) on a frame of our own over it.
---------------------------------------------------------------------------
local function IsTexture(r)
	return type(r) == "table" and r.GetObjectType and r:GetObjectType() == "Texture"
end

-- Is this texture one of the known round-minimap pieces (by file ID or path)?
local function IsForeign(tex)
	local fa = T.foreignArt
	local id = tex.GetTextureFileID and tex:GetTextureFileID()
	if id and fa.ids[id] then return true end
	local p = tex.GetTexture and tex:GetTexture()
	if type(p) == "number" then return fa.ids[p] == true end
	if type(p) == "string" then
		p = p:lower():gsub("/", "\\"):gsub("%.blp$", ""):gsub("%.tga$", "")
		return fa.paths[p] == true
	end
	return false
end

-- The texture's atlas name, or nil.
local function AtlasOf(tex)
	local a = tex.GetAtlas and tex:GetAtlas()
	if type(a) == "string" and a ~= "" then return a end
	return nil
end

-- Does the texture show a file or an atlas (not empty, not just a colour)?
local function HasArt(tex)
	if AtlasOf(tex) then return true end
	local id = tex.GetTextureFileID and tex:GetTextureFileID()
	if type(id) == "number" and id > 0 then return true end
	local p = tex.GetTexture and tex:GetTexture()
	return (type(p) == "number" and p > 0) or (type(p) == "string" and p ~= "")
end

local function IsVisible(tex)
	return tex:IsShown() and (tex:GetAlpha() or 0) > 0
end

-- The button's icon: its `icon`/`Icon` texture, else its NormalTexture (own-made buttons keep
-- their logo there), else its largest shown texture with art that isn't foreign art or its
-- highlight, preferring ones no bigger than the button was (rings stick out of it).
-- Never a hidden or empty texture. Sizes are read before the button is resized.
local function FindIcon(f, maxSize, sizes)
	local icon = f.icon or f.Icon
	if IsTexture(icon) then return icon end
	local hl = f.GetHighlightTexture and f:GetHighlightTexture()
	local normal = f.GetNormalTexture and f:GetNormalTexture()
	if IsTexture(normal) and normal ~= hl and HasArt(normal) and not IsForeign(normal)
		and (normal:GetAlpha() or 0) > 0 then
		return normal
	end
	local best, bestArea, fit, fitArea = nil, -1, nil, -1
	for _, r in ipairs({ f:GetRegions() }) do
		if IsTexture(r) and r ~= hl and not IsForeign(r) and IsVisible(r) and HasArt(r) then
			local s = sizes and sizes[r]
			local w, h
			if s then w, h = s[1], s[2] else w, h = r:GetSize() end
			w, h = w or 0, h or 0
			local area = w * h
			if area > bestArea then best, bestArea = r, area end
			if w <= maxSize + 0.5 and h <= maxSize + 0.5 and area > fitArea then fit, fitArea = r, area end
		end
	end
	return fit or best
end

-- Crops the edge off a texture inside the owner's own crop (so a sheet holding several
-- images keeps showing its part). Atlases and rotated coords are left alone. Once per texture.
local function CropInside(tex)
	if cropped[tex] or AtlasOf(tex) or not tex.GetTexCoord then return end
	local ulx, uly, llx, lly, urx, ury, lrx, lry = tex:GetTexCoord()
	if not (ulx and lry) then return end
	local e = 0.0001
	if math.abs(ulx - llx) > e or math.abs(urx - lrx) > e or math.abs(uly - ury) > e or math.abs(lly - lry) > e then
		return -- rotated or skewed: not ours to change
	end
	local c = T.slot.iconCoords -- left, right, top, bottom as fractions of the owner's rect
	local w, h = urx - ulx, lly - uly
	tex:SetTexCoord(ulx + c[1] * w, ulx + c[2] * w, uly + c[3] * h, uly + c[4] * h)
	cropped[tex] = true
end

-- Puts a texture into the slot: inset from the button's edges and cropped.
local function FitInSlot(tex, f)
	local inset = T.slot.iconInset
	tex:ClearAllPoints()
	tex:SetPoint("TOPLEFT", f, "TOPLEFT", inset, -inset)
	tex:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -inset, inset)
	CropInside(tex)
end

local function MakeArt(parent, layer, spec)
	local tex = parent:CreateTexture(nil, layer)
	local usedAtlas = T.SetAtlasOr(tex, spec.atlas, spec.file)
	if not usedAtlas and spec.fileScale then
		local size = T.iconSize * spec.fileScale
		tex:SetSize(size, size)
		tex:SetPoint("CENTER", parent, "CENTER", 0, 0)
	else
		tex:SetAllPoints(parent)
	end
	if spec.blend then tex:SetBlendMode(spec.blend) end
	return tex
end

-- Our slot art over a button. interactive = also hover and pressed art (not for Blizzard's
-- event button, which keeps its own).
local function AddSlot(f, interactive)
	if slotArt[f] or not bar then return end
	local o = CreateFrame("Frame", nil, bar)
	o:SetAllPoints(f)
	o:EnableMouse(false)
	o:SetFrameStrata(f:GetFrameStrata()) -- same strata as its button, so it draws over it
	o:SetFrameLevel(f:GetFrameLevel() + 1)
	MakeArt(o, "OVERLAY", T.slot.frame)
	slotArt[f] = o
	if not interactive then return end
	local hover = MakeArt(o, "ARTWORK", T.slot.hover)
	local down = MakeArt(o, "ARTWORK", T.slot.down)
	hover:Hide()
	down:Hide()
	f:HookScript("OnEnter", function() hover:Show() end)
	f:HookScript("OnLeave", function() hover:Hide(); down:Hide() end)
	f:HookScript("OnMouseDown", function() down:Show() end)
	f:HookScript("OnMouseUp", function() down:Hide() end)
end

-- Hides a texture (alpha 0) and keeps it hidden: if its owner raises the alpha again (Sonah's
-- LibDBIcon ring did), it goes straight back to 0 while hiddenArt[tex] is true. Hooked once.
local hookedAlpha = {}  -- [texture] = true: SetAlpha hook in place
local settingAlpha = false
local function KeepHidden(tex, a)
	if settingAlpha or not hiddenArt[tex] or not a or a <= 0 then return end
	settingAlpha = true
	tex:SetAlpha(0)
	settingAlpha = false
end
local function HideArt(tex)
	hiddenArt[tex] = true
	settingAlpha = true
	tex:SetAlpha(0)
	settingAlpha = false
	if not hookedAlpha[tex] then
		hookedAlpha[tex] = true
		hooksecurefunc(tex, "SetAlpha", KeepHidden)
	end
end

-- Popups a button opens (Zygor's setup box...): a child frame of a collected button that is
-- bigger than the slot or reaches outside the button. They inherit the bar's strata and level,
-- so neighbour buttons could draw over them; they are raised to bar level + T.popupLevel
-- (same strata). Small children inside the slot (glows, counters) are left alone.
local popupHooked = {}  -- [child frame] = true: OnShow hook in place

local function Usable(c)
	return not ((c.IsForbidden and c:IsForbidden()) or (c.IsProtected and c:IsProtected()))
end

local function IsPopup(c, f)
	local slot = T.iconSize + 0.5
	local w, h = c:GetSize()
	if (w or 0) > slot or (h or 0) > slot then return true end
	local cl, cb, cw, ch = c:GetRect()
	local fl, fb, fw, fh = f:GetRect()
	if not (cl and cw and fl and fw) then return false end
	local cs, fs = c:GetEffectiveScale(), f:GetEffectiveScale()
	cl, cb, cw, ch = cl * cs, cb * cs, cw * cs, ch * cs
	fl, fb, fw, fh = fl * fs, fb * fs, fw * fs, fh * fs
	local e = 1
	return cl < fl - e or cb < fb - e or cl + cw > fl + fw + e or cb + ch > fb + fh + e
end

local function RaisePopup(c, f)
	if not bar or InCombatLockdown() or not Usable(c) or not IsPopup(c, f) then return end
	local level = bar:GetFrameLevel() + T.popupLevel
	if c:GetFrameLevel() < level then c:SetFrameLevel(level) end
end

-- Hooks OnShow (once) on every child frame of a collected button and raises the shown popups.
local function WatchChildren(f)
	if not (f.GetChildren and Usable(f)) then return end
	for _, c in ipairs({ f:GetChildren() }) do
		if Usable(c) then
			if not popupHooked[c] and c.HookScript then
				popupHooked[c] = true
				c:HookScript("OnShow", function(self)
					-- Shown in combat: raised once combat ends (if still shown).
					ns.RunOutOfCombat("popup:" .. tostring(self), function()
						if self:IsShown() then RaisePopup(self, f) end
					end)
				end)
			end
			if c:IsShown() then RaisePopup(c, f) end
		end
	end
end

-- Makes an addon button a uniform slot. Out of combat only; never protected/forbidden frames.
local function Normalize(f)
	if not bar or InCombatLockdown() then return end
	if (f.IsForbidden and f:IsForbidden()) or (f.IsProtected and f:IsProtected()) then return end
	local size = T.iconSize
	local ow, oh = f:GetSize()
	local oldSize = math.max(ow or 0, oh or 0, size)
	-- Texture sizes as the owner made them (before the button is resized).
	local sizes = {}
	for _, r in ipairs({ f:GetRegions() }) do
		if IsTexture(r) then sizes[r] = { r:GetSize() } end
	end
	snapping = true
	f:SetScale(1)
	f:SetSize(size, size)
	f:SetFrameStrata(bar:GetFrameStrata())
	f:SetFrameLevel(bar:GetFrameLevel() + 2)
	snapping = false

	local icon = FindIcon(f, oldSize, sizes)
	local normal = f.GetNormalTexture and f:GetNormalTexture()
	local pushed = f.GetPushedTexture and f:GetPushedTexture()
	if icon then FitInSlot(icon, f) end
	if IsTexture(pushed) and pushed ~= icon and HasArt(pushed) and not IsForeign(pushed) then
		FitInSlot(pushed, f)
	end
	-- Hide the owner's ring, background and highlight always; anything else bigger than the
	-- slot only when a visible icon was found (never the normal/pushed state textures).
	local iconShows = icon and IsVisible(icon)
	local hl = f.GetHighlightTexture and f:GetHighlightTexture()
	for _, r in ipairs({ f:GetRegions() }) do
		if IsTexture(r) and r ~= icon then
			local hide = r == hl or IsForeign(r)
			if not hide and iconShows and r ~= normal and r ~= pushed then
				local w, h = r:GetSize()
				hide = (w or 0) > size or (h or 0) > size
			end
			if hide then HideArt(r) end
		end
	end
	AddSlot(f, true)
	WatchChildren(f)
end

-- The owner changed the button's size or scale (a LibDBIcon refresh...): back to the slot.
local function Snap(f)
	ns.RunOutOfCombat("snap:" .. tostring(f:GetName()), function()
		snapping = true
		f:SetScale(1)
		f:SetSize(T.iconSize, T.iconSize)
		snapping = false
		PlaceOne(f)
	end)
end

-- Puts one button into its slot. Offsets are converted into the button's own scale.
function PlaceOne(f)
	local i = slotOf[f]
	if not (i and bar) then return end
	local size, gap, pad = T.iconSize, T.iconGap, T.barPadding
	local row = math.floor((i - 1) / perRow)
	local col = (i - 1) % perRow
	local inRow = math.min(perRow, Bar.shownCount - row * perRow)
	local rowWidth = inRow * size + (inRow - 1) * gap
	local x = (BarWidth() - rowWidth) / 2 + col * (size + gap) + size / 2
	local y = pad + row * (size + gap) + size / 2

	local ratio = f:GetEffectiveScale() / bar:GetEffectiveScale()
	if ratio <= 0 then ratio = 1 end
	placing = true
	f:ClearAllPoints()
	if headerUnder then
		-- Bar above the map: first row at the bottom, next rows go up.
		f:SetPoint("CENTER", bar, "BOTTOMLEFT", x / ratio, y / ratio)
	else
		f:SetPoint("CENTER", bar, "TOPLEFT", x / ratio, -y / ratio)
	end
	placing = false
end

function Bar:Layout()
	layoutPending = false
	if not bar then return end
	local shown = {}
	for _, f in ipairs(collected) do
		if f:IsShown() then shown[#shown + 1] = f end
	end
	table.sort(shown, function(a, b) return (a:GetName() or "") < (b:GetName() or "") end)
	local ev = Bar.eventButton
	if ev and ev:IsShown() then shown[#shown + 1] = ev end

	wipe(slotOf)
	Bar.shownCount = #shown
	if #shown == 0 then
		bar:Hide()
		ns.Square:QueueFit()
		return
	end

	local size, gap, pad = T.iconSize, T.iconGap, T.barPadding
	perRow = math.max(1, math.floor((BarWidth() - 2 * pad + gap) / (size + gap)))
	rowsUsed = math.ceil(#shown / perRow)
	bar:SetHeight(rowsUsed * size + (rowsUsed - 1) * gap + 2 * pad)
	bar:Show()
	for i, f in ipairs(shown) do
		slotOf[f] = i
		PlaceOne(f)
	end
	for f, o in pairs(slotArt) do
		o:SetShown(slotOf[f] ~= nil)
	end
	if not InCombatLockdown() then
		for _, f in ipairs(collected) do WatchChildren(f) end
	end
	ns.Square:QueueFit() -- bar height or side changed: Edit Mode box follows
end

-- Layout on the next frame, once, however many times it is asked for.
function Bar:QueueLayout()
	if layoutPending then return end
	layoutPending = true
	C_Timer.After(0, function() Bar:Layout() end)
end

---------------------------------------------------------------------------
-- Collecting
---------------------------------------------------------------------------
local function Collect(f)
	isCollected[f] = true
	collected[#collected + 1] = f
	placing = true
	f:SetParent(bar)
	placing = false
	Normalize(f)
	-- No dragging in the bar: without this, LibDBIcon's (and similar) drag code moves the
	-- button around the old round map every frame while the hooks below move it back.
	-- Only this frame's drag is turned off; the owner's saved settings are left alone.
	if f.RegisterForDrag then f:RegisterForDrag() end

	-- If the owner moves its button (a LibDBIcon refresh, a drag around the old round map),
	-- put it straight back into its slot.
	hooksecurefunc(f, "SetPoint", function(self)
		if not placing then PlaceOne(self) end
	end)
	hooksecurefunc(f, "SetParent", function(self, parent)
		if not placing and parent ~= bar then
			placing = true
			self:SetParent(bar)
			placing = false
			Bar:QueueLayout()
		end
	end)
	-- Size and scale are the slot's: snap back if the owner changes them.
	hooksecurefunc(f, "SetScale", function(self, s)
		if not snapping and s ~= 1 then Snap(self) end
	end)
	hooksecurefunc(f, "SetSize", function(self, w, h)
		if not snapping and (w ~= T.iconSize or h ~= T.iconSize) then Snap(self) end
	end)
	-- Strata is the bar's (T.layer, under other addons): back if the owner raises it.
	hooksecurefunc(f, "SetFrameStrata", function(self, strata)
		if snapping or strata == T.layer then return end
		ns.RunOutOfCombat("strata:" .. tostring(self:GetName()), function()
			snapping = true
			self:SetFrameStrata(T.layer)
			self:SetFrameLevel(bar:GetFrameLevel() + 2)
			snapping = false
			WatchChildren(self) -- the owner likely raised it for a popup: keep that one on top
		end)
	end)
	-- A popup made on the first click or hover isn't watched yet: look once the click/hover is done.
	local function WatchSoon() C_Timer.After(0, function() WatchChildren(f) end) end
	f:HookScript("OnMouseUp", WatchSoon)
	f:HookScript("OnEnter", WatchSoon)
	f:HookScript("OnShow", function() Bar:QueueLayout() end)
	f:HookScript("OnHide", function() Bar:QueueLayout() end)
end

local function ScanChildren(parent)
	if not (parent and parent.GetChildren) then return end
	for _, child in ipairs({ parent:GetChildren() }) do
		if IsCollectable(child) then Collect(child) end
	end
end

-- A button LibDBIcon has just made: collect it straight away (after combat if needed).
local function OnIconCreated(_, button, name)
	ns.RunOutOfCombat("ldbi:" .. tostring(name), function()
		if IsCollectable(button, true) then
			Collect(button)
			Bar:QueueLayout()
		end
	end)
end

local function ScanLibDBIcon()
	local lib = LibDBIcon()
	if not lib then return 0 end
	if not Bar.ldbiHooked and lib.RegisterCallback then
		Bar.ldbiHooked = pcall(lib.RegisterCallback, Bar, "LibDBIcon_IconCreated", OnIconCreated)
	end
	if not lib.GetButtonList then return 0 end
	local list = lib:GetButtonList()
	for _, name in ipairs(list) do
		local f = (lib.GetMinimapButton and lib:GetMinimapButton(name)) or _G["LibDBIcon10_" .. name]
		if IsCollectable(f, true) then Collect(f) end
	end
	return #list
end

local function ScanKnown()
	for _, name in ipairs(KNOWN_BUTTONS) do
		local f = _G[name]
		if IsCollectable(f, true) then Collect(f) end
	end
end

-- A cheap fingerprint of where new buttons could appear; a rescan only runs when it changes.
local lastSignature
local function NumChildren(f)
	return (f and f.GetNumChildren) and f:GetNumChildren() or 0
end
local function Signature()
	local known = 0
	for i, name in ipairs(KNOWN_BUTTONS) do
		if _G[name] then known = known + 2 ^ (i - 1) end
	end
	local lib = LibDBIcon()
	local ldbi = (lib and lib.GetButtonList) and #lib:GetButtonList() or 0
	return table.concat({ NumChildren(Minimap), NumChildren(MinimapBackdrop), NumChildren(MinimapCluster), ldbi, known }, ":")
end

-- Blizzard's event button: anchored into a slot while shown, never reparented. It keeps its
-- own art and only gets our slot frame over it.
local function HookEventButton()
	local ev = EventButton()
	if not ev or Bar.eventButton or (ev.IsProtected and ev:IsProtected()) then return end
	if ev.IsForbidden and ev:IsForbidden() then return end
	Bar.eventButton = ev
	ev:SetScale(ScaleFor(ev))
	ev:SetFrameLevel(bar:GetFrameLevel() + 2)
	AddSlot(ev, false)
	ev:HookScript("OnShow", function() Bar:QueueLayout() end)
	ev:HookScript("OnHide", function() Bar:QueueLayout() end)
	if MinimapCluster and MinimapCluster.ApplyExternalEventURLButtonAnchor then
		hooksecurefunc(MinimapCluster, "ApplyExternalEventURLButtonAnchor", function() Bar:QueueLayout() end)
	end
end

-- Looks for new buttons now. Returns how many buttons are in the bar.
function Bar:Scan()
	if not bar then return 0 end
	ScanLibDBIcon()
	ScanKnown()
	ScanChildren(Minimap)
	ScanChildren(MinimapBackdrop)
	ScanChildren(MinimapCluster)
	self:Layout()
	lastSignature = Signature()
	return #collected + ((self.eventButton and self.eventButton:IsShown()) and 1 or 0)
end

-- Rescans only if something changed since the last scan (for the late timed checks).
function Bar:ScanIfChanged()
	if not bar or Signature() == lastSignature then return end
	self:RequestScan()
end

-- Looks for new buttons soon (at most once per half second, never in combat).
function Bar:RequestScan()
	if not bar or scanPending then return end
	scanPending = true
	C_Timer.After(0.5, function()
		scanPending = false
		ns.RunOutOfCombat("scan", function() Bar:Scan() end)
	end)
end

---------------------------------------------------------------------------
-- Which side of the map the bar is on (Edit Mode "Header Underneath")
---------------------------------------------------------------------------
local function HeaderIsUnderneath()
	return ns.Square.HeaderIsUnderneath()
end

function Bar:SetSide(under)
	headerUnder = under and true or false
	if not bar then return end
	local anchor = (ns.Square.border) or Minimap
	bar:ClearAllPoints()
	if headerUnder then
		bar:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, T.barGap)
		bar:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, T.barGap)
	else
		bar:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -T.barGap)
		bar:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -T.barGap)
	end
	self:QueueLayout()
	ns.Square:QueueFit()
end

---------------------------------------------------------------------------
-- Set-up
---------------------------------------------------------------------------
function Bar:Setup()
	if not Minimap or bar then return end
	-- A child of Minimap: follows Edit Mode position and size, and hides with the map.
	bar = CreateFrame("Frame", "MiniMapForeverIconBar", Minimap, T.backdropTemplate)
	bar:SetFrameStrata(T.layer) -- under other addons' frames; buttons follow in Normalize
	bar:SetHeight(T.iconSize + 2 * T.barPadding)
	bar:EnableMouse(false)
	T.ApplyBorder(bar)
	T.AddBackground(bar)
	bar:Hide()
	self.frame = bar
	self.active = true

	if MinimapCluster and MinimapCluster.SetHeaderUnderneath then
		hooksecurefunc(MinimapCluster, "SetHeaderUnderneath", function(_, under) Bar:SetSide(under) end)
	end
	self:SetSide(HeaderIsUnderneath())
	HookEventButton()

	self:Scan()
	-- Slow addons make their buttons a little after login.
	C_Timer.After(2, function() Bar:RequestScan() end)
	C_Timer.After(10, function() Bar:RequestScan() end)
	-- Some (Zygor...) are even later: look again, but only scan if something changed.
	C_Timer.After(30, function() Bar:ScanIfChanged() end)
	C_Timer.After(60, function() Bar:ScanIfChanged() end)
end
