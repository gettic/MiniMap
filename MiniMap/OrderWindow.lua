-- Mini Map: the "Icon order" window, opened from our " Arrange minimap icons" line in the addon
-- compartment menu (the addon counter on the map; RegisterAddon, see the end) or /mmap order. Our own frame on a plain Blizzard
-- template: one row per icon in the bar (number, icon, name, up/down arrows); drag a row or use
-- its arrows; "Sort A-Z" goes back to sorting by name. Saves to ns.db.iconOrder through
-- IconBar (Bar.MoveName); the bar is re-laid now or after combat (Bar:ApplyOrder).
-- Blizzard's compartment menu (its rows, sort, counter clicks) is never hooked or changed.
local _, ns = ...
local L = ns.L
local T = ns.Theme

local W = {}
ns.OrderWindow = W

local win               -- the window (MiniMapForeverOrderWindow)
local rows = {}         -- our row buttons, reused
local offset = 0        -- first list entry shown (mouse wheel scrolls)
local drag              -- { key = button name, gap = insert-before index } while a row is dragged
local combatNoted = false
local HINT_TOP = 28      -- px from the window's top to the hint line (under the title)

local function Ordered()
	local Bar = ns.IconBar
	if not (Bar and Bar.active and Bar.OrderedButtons) then return {}, {} end
	return Bar.OrderedButtons()
end

local function SetIcon(tex, f)
	local atlas, file, coords = ns.IconBar.IconArt(f)
	tex:SetTexCoord(0, 1, 0, 1)
	if atlas and T.HasAtlas(atlas) then
		tex:SetAtlas(atlas)
	elseif file then
		tex:SetTexture(file)
		if type(coords) == "table" and #coords == 8 then tex:SetTexCoord(unpack(coords)) end
	else
		tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
	end
end

-- Saves one move and re-lays the bar (after combat when in combat: one chat line per fight).
local function Move(name, before)
	if not name then return end
	local _, names = Ordered()
	if not ns.IconBar.MoveName(name, before, names) then return end
	if not ns.IconBar:ApplyOrder() and not combatNoted then
		combatNoted = true
		ns.Print(L.ORDER_AFTER_COMBAT)
	end
end

local function Arrow(parent, art)
	local s = T.orderWindow
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(s.arrowSize, s.arrowSize)
	b:SetNormalTexture(art.up)
	b:SetPushedTexture(art.down)
	b:SetDisabledTexture(art.disabled)
	b:SetHighlightTexture(art.highlight, "ADD")
	return b
end

---------------------------------------------------------------------------
-- Dragging a row
---------------------------------------------------------------------------
local function EndDrag()
	if win then
		win:SetScript("OnUpdate", nil)
		win.marker:Hide()
	end
	drag = nil
end

-- Which gap the cursor is over: before visible row g (g = #shown + 1: after the last).
local function DragTick()
	if not (drag and win) then return EndDrag() end
	local s = T.orderWindow
	local _, cy = GetCursorPosition()
	cy = (cy or 0) / (win:GetEffectiveScale() or 1)
	local shown = 0
	for i, r in ipairs(rows) do if r:IsShown() then shown = i end end
	if shown == 0 then return end
	local g = shown + 1
	for i = 1, shown do
		local top, bottom = rows[i]:GetTop(), rows[i]:GetBottom()
		if top and bottom and cy > (top + bottom) / 2 then g = i break end
	end
	drag.gap = offset + g
	local m = win.marker
	m:ClearAllPoints()
	if g <= shown then
		m:SetPoint("LEFT", rows[g], "TOPLEFT", 0, s.rowGap / 2)
		m:SetPoint("RIGHT", rows[g], "TOPRIGHT", 0, s.rowGap / 2)
	else
		m:SetPoint("LEFT", rows[shown], "BOTTOMLEFT", 0, -s.rowGap / 2)
		m:SetPoint("RIGHT", rows[shown], "BOTTOMRIGHT", 0, -s.rowGap / 2)
	end
	m:Show()
end

local function StartDrag(row)
	if drag or not row.key then return end
	drag = { key = row.key }
	win:SetScript("OnUpdate", DragTick)
	DragTick()
	W:Refresh()
end

local function Drop()
	if not drag then return end
	local key, gap = drag.key, drag.gap
	EndDrag()
	local _, names = Ordered()
	if gap and names[gap] ~= key and names[gap - 1] ~= key then
		Move(key, names[gap]) -- names[gap] nil = to the end
	end
	W:Refresh()
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
local function MakeRow(i)
	local s = T.orderWindow
	local r = CreateFrame("Button", nil, win.list)
	r:SetHeight(s.rowHeight)
	r:SetPoint("TOPLEFT", win.list, "TOPLEFT", 0, -(i - 1) * (s.rowHeight + s.rowGap))
	r:SetPoint("TOPRIGHT", win.list, "TOPRIGHT", 0, -(i - 1) * (s.rowHeight + s.rowGap))
	local hl = r:CreateTexture(nil, "HIGHLIGHT")
	hl:SetTexture(s.highlight)
	hl:SetBlendMode("ADD")
	hl:SetAllPoints(r)
	r.num = r:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	r.num:SetPoint("LEFT", r, "LEFT", 2, 0)
	r.num:SetWidth(18)
	r.num:SetJustifyH("RIGHT")
	r.icon = r:CreateTexture(nil, "ARTWORK")
	r.icon:SetSize(s.iconSize, s.iconSize)
	r.icon:SetPoint("LEFT", r.num, "RIGHT", 6, 0)
	r.down = Arrow(r, s.downArrow)
	r.down:SetPoint("RIGHT", r, "RIGHT", 0, 0)
	r.up = Arrow(r, s.up)
	r.up:SetPoint("RIGHT", r.down, "LEFT", 2, 0)
	r.label = r:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	r.label:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
	r.label:SetPoint("RIGHT", r.up, "LEFT", -4, 0)
	r.label:SetJustifyH("LEFT")
	if r.label.SetWordWrap then r.label:SetWordWrap(false) end
	r:RegisterForDrag("LeftButton")
	r:SetScript("OnDragStart", StartDrag)
	r:SetScript("OnDragStop", Drop)
	r.up:SetScript("OnClick", function()
		local _, names = Ordered()
		local k = offset + i
		if names[k] and k > 1 then Move(names[k], names[k - 1]) end
	end)
	r.down:SetScript("OnClick", function()
		local _, names = Ordered()
		local k = offset + i
		if names[k + 1] then Move(names[k + 1], names[k]) end
	end)
	return r
end

function W:Refresh()
	if not (win and win:IsShown()) then return end
	local s = T.orderWindow
	local list, names = Ordered()
	local n = #list
	local visible = math.min(n, s.maxRows)
	offset = math.max(0, math.min(offset, n - visible))
	for i = 1, visible do
		rows[i] = rows[i] or MakeRow(i)
		local r, k = rows[i], offset + i
		r.key = names[k]
		r.num:SetText(k)
		SetIcon(r.icon, list[k])
		r.label:SetText(ns.IconBar.DisplayName(names[k]))
		r.up:SetEnabled(k > 1)
		r.down:SetEnabled(k < n)
		r:SetAlpha((drag and drag.key == names[k]) and s.picked or 1)
		r:Show()
	end
	for i = visible + 1, #rows do rows[i]:Hide() end
	local barOn = ns.IconBar and ns.IconBar.active
	win.empty:SetText(barOn and L.OW_EMPTY or L.OW_BAR_OFF)
	win.empty:SetShown(n == 0)
	if n > visible then
		win.more:SetText(L.OW_MORE:format(offset + 1, offset + visible, n))
		win.more:Show()
	else
		win.more:Hide()
	end
	local listH = math.max(1, visible) * (s.rowHeight + s.rowGap)
	-- rows start under the hint, however many lines it wraps to
	local top = math.max(s.top, HINT_TOP + (win.hint:GetStringHeight() or 0) + 8)
	win.list:ClearAllPoints()
	win.list:SetPoint("TOPLEFT", win, "TOPLEFT", s.side, -top)
	win.list:SetPoint("TOPRIGHT", win, "TOPRIGHT", -s.side, -top)
	win.list:SetHeight(listH)
	win:SetHeight(top + listH + s.bottom)
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local function Build()
	local s = T.orderWindow
	local ok, f = pcall(CreateFrame, "Frame", "MiniMapForeverOrderWindow", UIParent, s.template)
	if not (ok and f) then f = CreateFrame("Frame", "MiniMapForeverOrderWindow", UIParent, T.backdropTemplate) end
	win = f
	f:Hide()
	f:SetSize(s.width, s.top + s.rowHeight + s.bottom)
	f:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
	f:SetFrameStrata(s.strata)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	if f.SetDontSavePosition then f:SetDontSavePosition(true) end
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	if not f.CloseButton then
		local okC, close = pcall(CreateFrame, "Button", nil, f, "UIPanelCloseButton")
		if okC and close then close:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0) end
	end
	local title = f.TitleText
	if not title then
		title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		title:SetPoint("TOP", f, "TOP", 0, -6)
	end
	title:SetText(L.OW_TITLE)
	local hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	hint:SetPoint("TOPLEFT", f, "TOPLEFT", s.side, -HINT_TOP)
	hint:SetPoint("TOPRIGHT", f, "TOPRIGHT", -s.side, -HINT_TOP)
	hint:SetJustifyH("LEFT")
	hint:SetText(L.OW_HINT)
	f.hint = hint
	local list = CreateFrame("Frame", nil, f)
	list:SetPoint("TOPLEFT", f, "TOPLEFT", s.side, -s.top)
	list:SetPoint("TOPRIGHT", f, "TOPRIGHT", -s.side, -s.top)
	list:SetHeight(s.rowHeight)
	f.list = list
	local empty = list:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	empty:SetPoint("TOPLEFT", list, "TOPLEFT", 4, -6)
	empty:SetPoint("TOPRIGHT", list, "TOPRIGHT", -4, -6)
	empty:SetJustifyH("LEFT")
	f.empty = empty
	local more = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	more:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", s.side, 14)
	f.more = more
	local okB, reset = pcall(CreateFrame, "Button", nil, f, s.buttonTemplate)
	if not (okB and reset) then
		reset = CreateFrame("Button", nil, f)
		local fs = reset:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		fs:SetAllPoints(reset)
		reset:SetFontString(fs)
	end
	reset:SetSize(100, 22)
	reset:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -s.side, 10)
	reset:SetText(L.OW_RESET)
	reset:SetScript("OnClick", function()
		if not ns.IconBar:ResetOrder() and not combatNoted then
			combatNoted = true
			ns.Print(L.ORDER_AFTER_COMBAT)
		end
	end)
	f.reset = reset
	local m = f:CreateTexture(nil, "OVERLAY")
	local mk = s.marker
	if mk.atlas and T.HasAtlas(mk.atlas) then
		m:SetAtlas(mk.atlas)
		m:SetHeight(mk.height)
	else
		m:SetTexture(mk.file)
		m:SetVertexColor(mk.color[1], mk.color[2], mk.color[3], mk.color[4])
		m:SetHeight(mk.fileHeight)
	end
	m:Hide()
	f.marker = m
	f:EnableMouseWheel(true)
	f:SetScript("OnMouseWheel", function(_, delta)
		offset = offset - (delta or 0)
		W:Refresh()
	end)
	-- Open = the bar's icons can be dragged too (their clicks pause); every way of closing
	-- (Esc, X, /mmap order, the menu line) hides the frame, so OnHide clears our source.
	f:SetScript("OnShow", function()
		ns.SafeRun("IconBarSort", ns.IconBar.SetArrange, ns.IconBar, true, "window")
		W:Refresh()
	end)
	f:SetScript("OnHide", function()
		EndDrag()
		ns.SafeRun("IconBarSort", ns.IconBar.SetArrange, ns.IconBar, false, "window")
	end)
	f:RegisterEvent("PLAYER_REGEN_ENABLED")
	f:SetScript("OnEvent", function()
		combatNoted = false
		W:Refresh()
	end)
	tinsert(UISpecialFrames, "MiniMapForeverOrderWindow") -- Esc closes it
	W.frame = f
end

function W:Toggle()
	if not win then Build() end
	if win:IsShown() then
		win:Hide()
	else
		offset = 0
		win:Show()
		W:Refresh()
	end
end

-- Self-test / offline tests: built, shown, the visible rows' button names in order. Read only.
function W.State()
	local keys = {}
	for _, r in ipairs(rows) do
		if r:IsShown() then keys[#keys + 1] = r.key end
	end
	return win ~= nil, (win and win:IsShown()) and true or false, keys, offset
end
W.Rows = function() return rows end

---------------------------------------------------------------------------
-- Our line in Blizzard's addon menu (the addon counter on the map), added with the documented
-- AddonCompartmentFrame:RegisterAddon, once, at login. Its text starts with a space so
-- Blizzard's own A-Z sort puts it first; the menu's sort, generator and rows are never touched
-- and no field of that frame is written by us. The click only opens/closes the window (the
-- menu's arguments are ignored); the tooltip only uses GameTooltip.
---------------------------------------------------------------------------
local menuEntry -- the table we gave RegisterAddon (nil until registered)
local MENU_ICON = "Interface\\Icons\\INV_Misc_Map_01" -- a game icon by path (same as the .toc's IconTexture)

local function MenuClick()
	ns.SafeRun("OrderWindow", W.Toggle, W)
end

local function MenuEnter(btn)
	if not btn then return end
	GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
	GameTooltip:SetText(L.MENU_TIP, nil, nil, nil, nil, true)
	GameTooltip:Show()
end

local function MenuLeave(btn)
	if btn and GameTooltip:GetOwner() == btn then GameTooltip:Hide() end
end

function W.RegisterInMenu()
	if menuEntry then return true end
	local f = AddonCompartmentFrame
	if not (f and type(f.RegisterAddon) == "function") then return false end
	local entry = {
		text = L.MENU_TEXT,
		icon = MENU_ICON,
		func = function() MenuClick() end,
		funcOnEnter = function(btn) MenuEnter(btn) end,
		funcOnLeave = function(btn) MenuLeave(btn) end,
	}
	local ok = pcall(f.RegisterAddon, f, entry)
	if ok then menuEntry = entry end
	return ok
end

-- Self-test: the table we registered (compared by identity in the menu's list), or nil.
function W.MenuEntry() return menuEntry end

local loginWatch = CreateFrame("Frame")
loginWatch:RegisterEvent("PLAYER_LOGIN")
loginWatch:SetScript("OnEvent", function(self)
	self:UnregisterEvent("PLAYER_LOGIN")
	ns.SafeRun("AddonMenu", W.RegisterInMenu)
end)
