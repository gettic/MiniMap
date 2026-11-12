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
local BUTTON_PATTERNS = { "[Mm]ini[Mm]ap.*[Bb]utton", "[Bb]utton.*[Mm]ini[Mm]ap", "[Mm]ini[Mm]ap[Ii]con", "^LibDBIcon10_" }

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
-- force = true for buttons LibDBIcon itself reports (no name/size guessing needed).
local function IsCollectable(f, force)
	if not f or isCollected[f] or f == bar then return false end
	if not (f.GetObjectType and f.GetName) then return false end
	if f.IsForbidden and f:IsForbidden() then return false end
	if f.IsProtected and f:IsProtected() then return false end
	local name = f:GetName()
	if type(name) ~= "string" then return false end
	if _G[name] == f and issecurevariable(name) then return false end -- a Blizzard frame
	if MatchesAny(name, SKIP_PATTERNS) then return false end
	if force then return true end
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

-- Puts one button into its slot. Offsets are converted into the button's own scale.
local function PlaceOne(f)
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
	f:SetScale(ScaleFor(f))
	f:SetFrameLevel(bar:GetFrameLevel() + 2)
	placing = false

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
	f:HookScript("OnShow", function() Bar:QueueLayout() end)
	f:HookScript("OnHide", function() Bar:QueueLayout() end)
end

local function ScanChildren(parent)
	if not (parent and parent.GetChildren) then return end
	for _, child in ipairs({ parent:GetChildren() }) do
		if IsCollectable(child) then Collect(child) end
	end
end

local function ScanLibDBIcon()
	local lib = LibDBIcon()
	if not lib then return end
	if not Bar.ldbiHooked and lib.RegisterCallback then
		Bar.ldbiHooked = pcall(lib.RegisterCallback, Bar, "LibDBIcon_IconCreated", function() Bar:RequestScan() end)
	end
	if not lib.GetButtonList then return end
	for _, name in ipairs(lib:GetButtonList()) do
		local f = (lib.GetMinimapButton and lib:GetMinimapButton(name)) or _G["LibDBIcon10_" .. name]
		if IsCollectable(f, true) then Collect(f) end
	end
end

-- Blizzard's event button: anchored into a slot while shown, never reparented.
local function HookEventButton()
	local ev = EventButton()
	if not ev or Bar.eventButton or (ev.IsProtected and ev:IsProtected()) then return end
	Bar.eventButton = ev
	ev:SetScale(ScaleFor(ev))
	ev:SetFrameLevel(bar:GetFrameLevel() + 2)
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
	ScanChildren(Minimap)
	ScanChildren(MinimapBackdrop)
	ScanChildren(MinimapCluster)
	self:Layout()
	return #collected + ((self.eventButton and self.eventButton:IsShown()) and 1 or 0)
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
	if MinimapCluster and MinimapCluster.GetSettingValueBool and Enum and Enum.EditModeMinimapSetting then
		local ok, value = pcall(MinimapCluster.GetSettingValueBool, MinimapCluster, Enum.EditModeMinimapSetting.HeaderUnderneath)
		if ok then return value and true or false end
	end
	return false
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
end

---------------------------------------------------------------------------
-- Set-up
---------------------------------------------------------------------------
function Bar:Setup()
	if not Minimap or bar then return end
	-- A child of Minimap: follows Edit Mode position and size, and hides with the map.
	bar = CreateFrame("Frame", "MiniMapForeverIconBar", Minimap, T.backdropTemplate)
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
end
