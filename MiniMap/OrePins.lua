-- Mini Map: ore pins. After the player mines a node, Mini Map remembers where it was and shows
-- the ore's own item icon there on the minimap, with a short name coloured by the player's
-- Mining skill (orange/yellow/green/grey, like the trade skill window). Off unless
-- `ns.db.oreLabels`. Only nodes the player mined (own loot window from a game object);
-- no scanning, no node database, no sharing. Pins are display only (no clicks).
-- Every game value is read in pcall and checked with `issecretvalue`; a secret or missing
-- value means nothing is recorded or drawn.
local ADDON, ns = ...
local L, T = ns.L, ns.Theme

local Pins = {}
ns.OrePins = Pins

local MINING_SKILL_LINE = 186
local SKILL_CACHE_SECONDS = 5
local SAME_NODE = 0.003      -- map units: closer than this = the same node
local MAX_PER_MAP = 300      -- saved pins per map; the oldest go first
local POOL_SIZE = 40         -- pin frames at most (made outside the ticker)
local TICK = 0.1             -- seconds between pin updates

-- Ore item ID -> { short name, Mining skill needed } (Classic levels, not checked on Forever).
-- Rich and small Thorium give the same ore, so they share one entry (the lower level).
local ORES = {
	[2770] = { "Copper", 1 },
	[2771] = { "Tin", 65 },
	[3340] = { "Incendicite", 65 },
	[2775] = { "Silver", 75 },
	[4278] = { "Bloodstone", 75 },
	[2772] = { "Iron", 125 },
	[5833] = { "Indurium", 150 },
	[2776] = { "Gold", 155 },
	[3858] = { "Mithril", 175 },
	[7911] = { "Truesilver", 230 },
	[11370] = { "Dark Iron", 230 },
	[10620] = { "Thorium", 245 },
}
Pins.ORES = ORES

-- Minimap diameter in yards per zoom level (0 = farthest out), outdoors and indoors.
-- Measured game values (the game has no call that returns them).
local VIEW = {
	outdoor = { [0] = 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 },
	indoor = { [0] = 300, 240, 180, 120, 80, 50 },
}
Pins.VIEW = VIEW

-- Gathering addons that draw their own minimap pins: ours stay hidden (still recorded).
local GATHER_ADDONS = { "GatherMate2", "Gatherer", "GatherLite" }

---------------------------------------------------------------------------
-- Safe reads
---------------------------------------------------------------------------
-- False for a secret value (restricted data): such values are never used.
local function Plain(v)
	if issecretvalue then
		local ok, secret = pcall(issecretvalue, v)
		if not ok or secret then return false end
	end
	return true
end

local function Num(v)
	return Plain(v) and type(v) == "number" and v or nil
end

local function Str(v)
	return Plain(v) and type(v) == "string" and v or nil
end

-- Calls fn(...) in pcall; returns its results only if the call worked.
local function Try(fn, ...)
	if type(fn) ~= "function" then return false end
	return pcall(fn, ...)
end

local function Now()
	local ok, t = Try(GetTime)
	return ok and Num(t) or 0
end

local function On()
	return ns.db and ns.db.oreLabels and true or false
end

---------------------------------------------------------------------------
-- Mining skill and colours
---------------------------------------------------------------------------
local skillValue, skillTime = nil, -SKILL_CACHE_SECONDS

local function ReadSkillFromProfessions()
	if not (GetProfessions and GetProfessionInfo) then return end
	local ok, p1, p2 = pcall(GetProfessions)
	if not ok then return end
	for _, index in pairs({ p1, p2 }) do
		if Num(index) then
			local ok2, _, _, rank, _, _, _, line = pcall(GetProfessionInfo, index)
			if ok2 and Num(line) == MINING_SKILL_LINE then return Num(rank) end
		end
	end
end

-- Fallback for clients with the old skills list (name match, English).
local function ReadSkillFromSkillLines()
	if not (GetNumSkillLines and GetSkillLineInfo) then return end
	local ok, count = pcall(GetNumSkillLines)
	count = ok and Num(count)
	if not count then return end
	for i = 1, count do
		local ok2, name, header, _, rank = pcall(GetSkillLineInfo, i)
		if ok2 and not header and Plain(name) and name == L.ORE_MINING then return Num(rank) end
	end
end

function Pins.MiningSkill()
	local now = Now()
	if now - skillTime >= SKILL_CACHE_SECONDS then
		skillTime = now
		skillValue = ReadSkillFromProfessions() or ReadSkillFromSkillLines()
	end
	return skillValue
end

-- Red under the needed skill, then orange (< +25), yellow (< +50), green (< +100), grey.
function Pins.ColorKey(need, skill)
	if not skill then return nil end
	if skill < need then return "impossible" end
	if skill < need + 25 then return "verydifficult" end
	if skill < need + 50 then return "difficult" end
	if skill < need + 100 then return "standard" end
	return "trivial"
end

-- Blizzard's colours (`QuestDifficultyColors`), Theme's numbers as fallback.
function Pins.Color(key)
	local c = key and QuestDifficultyColors and QuestDifficultyColors[key]
	if type(c) == "table" and type(c.r) == "number" then return c.r, c.g, c.b end
	local f = (key and T.ore.colors[key]) or T.ore.neutral
	return f[1], f[2], f[3]
end

-- Item icons by ID (Blizzard's own art), cached once found.
local icons = {}

function Pins.Icon(itemID)
	local icon = icons[itemID]
	if icon then return icon end
	local get = C_Item and (C_Item.GetItemIconByID or C_Item.GetItemIcon) or GetItemIcon
	local ok, res = Try(get, itemID)
	if ok and Plain(res) and (type(res) == "number" or type(res) == "string") then
		icons[itemID] = res
		return res
	end
	return T.ore.fallbackIcon
end

---------------------------------------------------------------------------
-- Saved pins: ns.db.orePins[mapID] = { { x, y, itemID }, ... }
---------------------------------------------------------------------------
local function ValidPin(p)
	return type(p) == "table" and type(p[1]) == "number" and type(p[2]) == "number"
		and type(p[3]) == "number"
end

local function Store()
	if not ns.db then return nil end
	if type(ns.db.orePins) ~= "table" then ns.db.orePins = {} end
	return ns.db.orePins
end

local function Round(v)
	return math.floor(v * 10000 + 0.5) / 10000
end

-- Adds or updates a pin; returns "new" or "same".
function Pins.Record(mapID, x, y, itemID)
	local store = Store()
	if not store then return nil end
	local list = store[mapID]
	if type(list) ~= "table" then
		list = {}
		store[mapID] = list
	end
	x, y = Round(x), Round(y)
	for _, p in ipairs(list) do
		if ValidPin(p) then
			local dx, dy = p[1] - x, p[2] - y
			if dx * dx + dy * dy < SAME_NODE * SAME_NODE then
				p[3] = itemID
				return "same"
			end
		end
	end
	list[#list + 1] = { x, y, itemID }
	while #list > MAX_PER_MAP do table.remove(list, 1) end
	return "new"
end

function Pins.Count(mapID)
	local store = Store()
	local list = store and mapID and store[mapID]
	return type(list) == "table" and #list or 0
end

function Pins.CountAll()
	local store, maps, total = Store(), 0, 0
	for _, list in pairs(store or {}) do
		if type(list) == "table" and #list > 0 then
			maps = maps + 1
			total = total + #list
		end
	end
	return total, maps
end

---------------------------------------------------------------------------
-- Where the player is
---------------------------------------------------------------------------
local function PlayerMap()
	if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
	local ok, mapID = Try(C_Map.GetBestMapForUnit, "player")
	return ok and Num(mapID) or nil
end

-- Player's map position (0-1), or nil (instance, secret, missing).
local function PlayerPos(mapID)
	if not (mapID and C_Map and C_Map.GetPlayerMapPosition) then return nil end
	local ok, pos = Try(C_Map.GetPlayerMapPosition, mapID, "player")
	if not ok or not pos or not Plain(pos) then return nil end
	local okXY, x, y = pcall(function() return pos.x, pos.y end)
	x, y = okXY and Num(x), okXY and Num(y)
	if not (x and y) or (x == 0 and y == 0) then return nil end
	return x, y
end

local function InInstance()
	local ok, inside = Try(IsInInstance)
	return ok and Plain(inside) and inside == true
end

---------------------------------------------------------------------------
-- Learning: the player's own loot window, from a game object (a node), holding an ore from
-- ORES. No cast is needed (the player's last cast is only shown in /mmap debug). Every step
-- leaves a reason in `Pins.lastLearn`, so /mmap debug shows where it stopped.
---------------------------------------------------------------------------
local lastCast = nil -- GetTime() of the player's last cast (info for /mmap debug)
local lastLoot, lastLootTime = nil, nil -- last loot event name and time (info)
local looted = nil -- GetTime() when this loot window was read (LOOT_READY and LOOT_OPENED both fire)
Pins.lastLearn = nil -- text for /mmap debug
Pins.listenCount = 0 -- learn/refresh events registered (for /mmap debug)

local function Learned(event, fmt, ...)
	local text = (select("#", ...) > 0) and fmt:format(...) or fmt
	Pins.lastLearn = ("%s: %s"):format(tostring(event or "?"), text)
end

-- Item ID in `slot`; nil for an empty slot or money, false when the link is hidden.
local function ItemOfSlot(slot)
	local ok, link = Try(GetLootSlotLink, slot)
	if not ok then return false end
	if link == nil then return nil end
	link = Str(link)
	if not link then return false end
	return tonumber(link:match("item:(%d+)"))
end

-- Kind of thing the loot in `slot` comes from: the GUID's type word ("GameObject" for a vein,
-- "Creature", "Item"...). Never the GUID itself. nil when hidden or missing.
local function SourceKind(slot)
	local ok, guid = Try(GetLootSourceInfo, slot)
	guid = ok and Str(guid)
	return guid and guid:match("^(%a+)%-") or nil
end

local function CastInfo()
	if not lastCast then return L.LEARN_NO_CAST end
	return L.LEARN_CAST_AGO:format(Now() - lastCast)
end

function Pins.Learn(event)
	if looted and Now() - looted < 2 then return end -- this loot window was already read
	local okN, rawCount = Try(GetNumLootItems)
	if not okN or not Plain(rawCount) then
		return Learned(event, L.LEARN_SECRET, L.LEARN_WHAT_COUNT)
	end
	local count = Num(rawCount) or 0
	if count == 0 then return Learned(event, L.LEARN_EMPTY) end -- LOOT_OPENED may still read it
	local ids, best, bestNeed, otherKind, hiddenLink = {}, nil, nil, nil, false
	for slot = 1, count do
		local id = ItemOfSlot(slot)
		if id == false then
			hiddenLink = true
		elseif id then
			ids[#ids + 1] = id
			local ore = ORES[id]
			if ore then
				local kind = SourceKind(slot)
				if not kind then
					looted = Now()
					return Learned(event, L.LEARN_SECRET, L.LEARN_WHAT_SOURCE)
				end
				if kind ~= "GameObject" then
					otherKind = kind
				elseif not bestNeed or ore[2] > bestNeed then
					best, bestNeed = id, ore[2]
				end
			end
		end
	end
	if #ids == 0 then -- nothing readable yet: LOOT_OPENED may still read it
		return Learned(event, hiddenLink and L.LEARN_SECRET or L.LEARN_EMPTY, L.LEARN_WHAT_LINK)
	end
	looted = Now()
	if not best then
		if otherKind then return Learned(event, L.LEARN_NOT_NODE, otherKind) end
		local shown = {}
		for i = 1, math.min(#ids, 8) do shown[i] = tostring(ids[i]) end
		return Learned(event, L.LEARN_NO_ORE, table.concat(shown, ", "))
	end
	local mapID = PlayerMap()
	local x, y = PlayerPos(mapID)
	if not (mapID and x) then
		return Learned(event, L.LEARN_NO_POS, tostring(mapID or "-"))
	end
	local result = Pins.Record(mapID, x, y, best)
	if not result then return Learned(event, L.LEARN_NO_SAVE) end
	Learned(event, result == "new" and L.LEARN_NEW or L.LEARN_SAME, ORES[best][1], mapID,
		x * 100, y * 100, CastInfo())
	if On() then Pins:Refresh() end
end

-- `/mmap debug`: registered events, last loot event and last cast.
function Pins.DebugEvents()
	local function Ago(name, t)
		if not t then return L.DEBUG_NEVER end
		return L.DEBUG_AGO:format(name, Now() - t)
	end
	return Pins.listenCount, Pins.listenTotal or 0, Ago(lastLoot, lastLootTime), Ago(L.DEBUG_CAST, lastCast)
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
local pool, shownCount = {}, 0
local ticker
local current = { mapID = nil, list = nil, w = nil, h = nil }

local function OtherGatherAddon()
	for _, name in ipairs(GATHER_ADDONS) do
		if ns.IsLoaded(name) then return name end
	end
end

local function ShowName(pin, show)
	if show then pin.name:Show() else pin.name:Hide() end
end

local function MakePin()
	local o = T.ore
	local pin = CreateFrame("Frame", nil, Minimap)
	pin:SetSize(o.pinSize, o.pinSize)
	pin:SetFrameStrata(Minimap:GetFrameStrata())
	pin:SetFrameLevel(Minimap:GetFrameLevel() + o.pinLevel)
	pin.icon = pin:CreateTexture(nil, "ARTWORK")
	pin.icon:SetAllPoints()
	pin.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	pin.name = pin:CreateFontString(nil, "OVERLAY", _G[o.pinFont] and o.pinFont or "GameFontHighlightSmall")
	pin.name:SetPoint("LEFT", pin, "RIGHT", 1, 0)
	pin.name:Hide()
	-- Mouse-over only: shows our own name text; clicks go through to the map where the client
	-- allows it (display only, no click actions).
	if pin.SetMouseClickEnabled and pin.SetMouseMotionEnabled then
		pin:SetMouseMotionEnabled(true)
		pin:SetMouseClickEnabled(false)
	else
		pin:EnableMouse(true)
	end
	pin:SetScript("OnEnter", function(self) ShowName(self, true) end)
	pin:SetScript("OnLeave", function(self) ShowName(self, self.always) end)
	pin:Hide()
	return pin
end

local function HideAll()
	for _, pin in ipairs(pool) do pin:Hide() end
	shownCount = 0
end

-- Yards per map unit (width, height) for a map, or nil.
local function MapSize(mapID)
	if not (C_Map and C_Map.GetMapWorldSize) then return nil end
	local ok, w, h = Try(C_Map.GetMapWorldSize, mapID)
	w, h = ok and Num(w), ok and Num(h)
	if not (w and h) or w <= 0 or h <= 0 then return nil end
	return w, h
end

-- Minimap radius in yards for the current zoom (indoors or out), or nil.
local function ViewRadius()
	local ok, zoom = Try(Minimap.GetZoom, Minimap)
	zoom = ok and Num(zoom) or 0
	local okI, indoors = Try(IsIndoors)
	local tbl = (okI and Plain(indoors) and indoors == true) and VIEW.indoor or VIEW.outdoor
	local d = tbl[zoom] or tbl[0]
	return d / 2
end

local function Rotating()
	local ok, v = Try(GetCVar, "rotateMinimap")
	return ok and Plain(v) and v == "1"
end

-- Pin offset from the map's centre in pixels (right/up), for a pin `east`/`south` yards from
-- the player. `facing` = radians (0 north, counter-clockwise) when the map rotates, else nil.
function Pins.Offset(east, south, pxPerYard, facing)
	local dx, dy = east * pxPerYard, -south * pxPerYard
	if facing then
		local c, s = math.cos(facing), math.sin(facing)
		dx, dy = dx * c + dy * s, -dx * s + dy * c
	end
	return dx, dy
end

-- Inside the square map (corners included), allowing for the pin's own half size.
function Pins.Inside(dx, dy, halfW, halfH, pinHalf)
	return math.abs(dx) <= halfW - pinHalf and math.abs(dy) <= halfH - pinHalf
end

-- Runs every TICK seconds while on, outside instances, and the current map has pins.
-- Never makes frames: only places the pool's pins.
local function Update()
	local list, mapID = current.list, current.mapID
	if not list then return HideAll() end
	local now = PlayerMap()
	if now ~= mapID then
		HideAll()
		if C_Timer then C_Timer.After(0, function() Pins:Refresh() end) end
		return
	end
	local px, py = PlayerPos(mapID)
	if not px then return HideAll() end
	local okW, mw = Try(Minimap.GetWidth, Minimap)
	local okH, mh = Try(Minimap.GetHeight, Minimap)
	mw, mh = okW and Num(mw), okH and Num(mh)
	if not (mw and mh) or mw <= 0 then return HideAll() end
	local halfW, halfH = mw / 2, mh / 2
	local pxPerYard = halfW / ViewRadius()
	local facing
	if Rotating() then
		local ok, f = Try(GetPlayerFacing)
		facing = ok and Num(f)
		if not facing then return HideAll() end
	end
	local pinHalf = T.ore.pinSize / 2
	local skill = Pins.MiningSkill()
	local used = 0
	for _, p in ipairs(list) do
		if used >= #pool then break end
		if ValidPin(p) then
			local dx, dy = Pins.Offset((p[1] - px) * current.w, (p[2] - py) * current.h, pxPerYard, facing)
			if Pins.Inside(dx, dy, halfW, halfH, pinHalf) then
				used = used + 1
				local pin, ore = pool[used], ORES[p[3]]
				pin:ClearAllPoints()
				pin:SetPoint("CENTER", Minimap, "CENTER", dx, dy)
				-- Name on the side towards the map's middle, so it stays on the map.
				local side = dx > 0 and "left" or "right"
				if pin.side ~= side then
					pin.side = side
					pin.name:ClearAllPoints()
					if side == "left" then
						pin.name:SetPoint("RIGHT", pin, "LEFT", -1, 0)
					else
						pin.name:SetPoint("LEFT", pin, "RIGHT", 1, 0)
					end
				end
				if pin.itemID ~= p[3] then
					pin.itemID = p[3]
					pin.icon:SetTexture(Pins.Icon(p[3]))
					pin.name:SetText(ore and ore[1] or "?")
				end
				pin.name:SetTextColor(Pins.Color(ore and Pins.ColorKey(ore[2], skill)))
				pin:Show()
			end
		end
	end
	for i = used + 1, #pool do pool[i]:Hide() end
	-- Names next to the icons only when few are on the map; otherwise on mouse-over.
	local always = used <= T.ore.namesWhenAtMost
	for i = 1, used do
		local pin = pool[i]
		pin.always = always
		ShowName(pin, always or pin:IsMouseOver())
	end
	shownCount = used
end

local function StopTicker()
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
	HideAll()
end

-- Picks up the current map's pins, makes pool frames if needed (here, never in the ticker),
-- and starts or stops the ticker.
function Pins:Refresh()
	current.mapID, current.list = nil, nil
	if not On() or OtherGatherAddon() or InInstance() or not Minimap then return StopTicker() end
	local mapID = PlayerMap()
	local store = Store()
	local list = mapID and store and store[mapID]
	if type(list) ~= "table" or #list == 0 then return StopTicker() end
	local w, h = MapSize(mapID)
	if not w then return StopTicker() end
	current.mapID, current.list, current.w, current.h = mapID, list, w, h
	local want = math.min(POOL_SIZE, #list)
	while #pool < want do pool[#pool + 1] = MakePin() end
	if not ticker and C_Timer and C_Timer.NewTicker then
		ticker = C_Timer.NewTicker(TICK, function()
			local ok, err = pcall(Update)
			if not ok then
				StopTicker()
				local handler = geterrorhandler and geterrorhandler()
				if handler then handler(err) end
			end
		end)
	end
end

function Pins.TickerRunning()
	return ticker ~= nil
end

function Pins.ShownCount()
	return shownCount
end

---------------------------------------------------------------------------
-- Events, settings
---------------------------------------------------------------------------
local events = CreateFrame("Frame")

local function OnEvent(_, event, unit)
	if event == "UNIT_SPELLCAST_SENT" or event == "UNIT_SPELLCAST_SUCCEEDED" then
		if Str(unit) == "player" then lastCast = Now() end -- info for /mmap debug only
	elseif event == "LOOT_READY" or event == "LOOT_OPENED" then
		lastLoot, lastLootTime = event, Now()
		Pins.Learn(event)
	elseif event == "LOOT_CLOSED" then
		looted = nil
	else -- zone changes, entering the world
		Pins:Refresh()
	end
end

-- Listens only while on (nothing is learned or drawn while off).
local LISTEN = {
	"UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED", "LOOT_READY", "LOOT_OPENED", "LOOT_CLOSED",
	"ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD",
}

Pins.listenTotal = #LISTEN

-- Player-only unit event where it works, else a plain event (OnEvent checks the unit).
local function Register(e)
	if e:find("^UNIT_") and events.RegisterUnitEvent
		and pcall(events.RegisterUnitEvent, events, e, "player") then
		return true
	end
	return (pcall(events.RegisterEvent, events, e))
end

local function Listen(on)
	local count = 0
	for _, e in ipairs(LISTEN) do
		if on then
			if Register(e) then count = count + 1 end
		else
			pcall(events.UnregisterEvent, events, e)
		end
	end
	Pins.listenCount = count
end

events:SetScript("OnEvent", function(...)
	local ok, err = pcall(OnEvent, ...)
	if not ok then
		local handler = geterrorhandler and geterrorhandler()
		if handler then handler(err) end
	end
end)

function Pins:Setup()
	Store()
	Listen(On())
	self:Refresh()
end

-- `/mmap oreon|oreoff` (saved).
function Pins:Set(on)
	ns.db.oreLabels = on and true or false
	Listen(on)
	self:Refresh()
	ns.Print(on and L.ORE_ON or L.ORE_OFF)
	local other = on and OtherGatherAddon()
	if other then ns.Print(L.ORE_OTHER, other) end
end

-- `/mmap ore`: state and counts.
function Pins:Status()
	local total, maps = Pins.CountAll()
	ns.Print(On() and L.ORE_STATUS_ON or L.ORE_STATUS_OFF)
	ns.Print(L.ORE_COUNT, Pins.Count(PlayerMap()), total, maps)
	local other = On() and OtherGatherAddon()
	if other then ns.Print(L.ORE_OTHER, other) end
end

-- `/mmap oreclear` (this map) and `/mmap oreclearall`: only on the player's own command.
function Pins:Clear(all)
	local store = Store()
	if not store then return end
	if all then
		local total = Pins.CountAll()
		for k in pairs(store) do store[k] = nil end
		ns.Print(L.ORE_CLEARED_ALL, total)
	else
		local mapID = PlayerMap()
		local n = Pins.Count(mapID)
		if mapID then store[mapID] = nil end
		ns.Print(L.ORE_CLEARED, n)
	end
	self:Refresh()
end
