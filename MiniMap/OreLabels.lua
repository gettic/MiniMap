-- Mini Map: ore labels. When the mouse is over a mining node on the minimap, its tooltip line
-- shows the ore's own item icon and a short name, coloured by the player's Mining skill
-- (orange/yellow/green/grey, like the trade skill window). Off unless `ns.db.oreLabels`.
-- Only post-hooks GameTooltip:SetMinimapMouseover (hooksecurefunc); never touches the map.
local ADDON, ns = ...
local L, T = ns.L, ns.Theme

local Ore = {}
ns.OreLabels = Ore

local MINING_SKILL_LINE = 186
local SKILL_CACHE_SECONDS = 5

-- [node name as the tooltip shows it] = { short name, ore item ID, Mining skill needed }.
-- Classic node names (English) and levels; WoW Forever's own levels are not checked yet.
local NODES = {
	["Copper Vein"] = { "Copper", 2770, 1 },
	["Tin Vein"] = { "Tin", 2771, 65 },
	["Incendicite Mineral Vein"] = { "Incendicite", 3340, 65 },
	["Silver Vein"] = { "Silver", 2775, 75 },
	["Ooze Covered Silver Vein"] = { "Silver", 2775, 75 },
	["Lesser Bloodstone Deposit"] = { "Bloodstone", 4278, 75 },
	["Iron Deposit"] = { "Iron", 2772, 125 },
	["Indurium Mineral Vein"] = { "Indurium", 5833, 150 },
	["Gold Vein"] = { "Gold", 2776, 155 },
	["Ooze Covered Gold Vein"] = { "Gold", 2776, 155 },
	["Mithril Deposit"] = { "Mithril", 3858, 175 },
	["Ooze Covered Mithril Deposit"] = { "Mithril", 3858, 175 },
	["Truesilver Deposit"] = { "Truesilver", 7911, 230 },
	["Ooze Covered Truesilver Deposit"] = { "Truesilver", 7911, 230 },
	["Dark Iron Deposit"] = { "Dark Iron", 11370, 230 },
	["Small Thorium Vein"] = { "Thorium", 10620, 245 },
	["Ooze Covered Thorium Vein"] = { "Thorium", 10620, 245 },
	["Rich Thorium Vein"] = { "Rich Thorium", 10620, 275 },
	["Ooze Covered Rich Thorium Vein"] = { "Rich Thorium", 10620, 275 },
	["Hakkari Thorium Vein"] = { "Thorium", 10620, 275 },
}
Ore.NODES = NODES

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
-- False for a secret value (Midnight-style restricted data): such values are skipped.
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

-- Player's Mining skill, or nil (no Mining, or unreadable). Cached a few seconds, since the
-- tooltip is rebuilt every frame while the mouse is on the map.
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

function Ore.MiningSkill()
	local now = GetTime and GetTime() or 0
	if now - skillTime >= SKILL_CACHE_SECONDS then
		skillTime = now
		skillValue = ReadSkillFromProfessions() or ReadSkillFromSkillLines()
	end
	return skillValue
end

-- Hex colour code for a node: red under the needed skill, then orange (< +25),
-- yellow (< +50), green (< +100), grey. Blizzard's colours, Theme's numbers as fallback.
local function ColorCode(key)
	local c = QuestDifficultyColors and QuestDifficultyColors[key]
	local r, g, b
	if type(c) == "table" and type(c.r) == "number" then
		r, g, b = c.r, c.g, c.b
	else
		local f = (key and T.ore.colors[key]) or T.ore.neutral
		r, g, b = f[1], f[2], f[3]
	end
	return ("|cff%02x%02x%02x"):format(r * 255 + 0.5, g * 255 + 0.5, b * 255 + 0.5)
end

function Ore.ColorKey(need, skill)
	if not skill then return nil end
	if skill < need then return "impossible" end
	if skill < need + 25 then return "verydifficult" end
	if skill < need + 50 then return "difficult" end
	if skill < need + 100 then return "standard" end
	return "trivial"
end

-- Item icons by ID (Blizzard's own art). Only cached once found (uncached items may give nil).
local icons = {}

local function Icon(itemID)
	local icon = icons[itemID]
	if icon then return icon end
	local get = C_Item and (C_Item.GetItemIconByID or C_Item.GetItemIcon) or GetItemIcon
	if get then
		local ok, res = pcall(get, itemID)
		if ok and Plain(res) and (type(res) == "number" or type(res) == "string") then
			icons[itemID] = res
			return res
		end
	end
	return T.ore.fallbackIcon
end

local function Label(node)
	local short, itemID, need = node[1], node[2], node[3]
	local key = Ore.ColorKey(need, Ore.MiningSkill())
	return ("|T%s:%d|t %s%s|r"):format(tostring(Icon(itemID)), T.ore.iconSize, ColorCode(key), short)
end

-- One tooltip line may hold several names (one per row). Returns the new text, or nil when
-- no known node is in it.
function Ore.Relabel(text)
	local out, hit = {}, false
	for piece in (text .. "\n"):gmatch("(.-)\n") do
		local name = piece:gsub("|c%x%x%x%x%x%x%x%x", "")
		name = name:gsub("|r", "")
		name = name:match("^%s*(.-)%s*$")
		local node = NODES[name]
		if node then
			hit = true
			out[#out + 1] = Label(node)
		else
			out[#out + 1] = piece
		end
	end
	return hit and table.concat(out, "\n") or nil
end

---------------------------------------------------------------------------
-- Tooltip hook
---------------------------------------------------------------------------
local function OnMinimapMouseover(tip)
	if not (ns.db and ns.db.oreLabels) then return end
	local ok, count = pcall(tip.NumLines, tip)
	count = ok and Num(count)
	if not count or count == 0 then return end
	local prefix = tip:GetName()
	if not prefix then return end
	local changed = false
	for i = 1, count do
		local fs = _G[prefix .. "TextLeft" .. i]
		if fs then
			local okText, text = pcall(fs.GetText, fs)
			if okText and Plain(text) and type(text) == "string" and text ~= "" then
				local new = Ore.Relabel(text)
				if new then
					fs:SetText(new)
					changed = true
				end
			end
		end
	end
	if changed then tip:Show() end -- re-size to the new text
end

Ore.hooked = false

-- Hooks once; the hook does nothing while the setting is off. False if the client lacks it.
function Ore:Hook()
	if self.hooked then return true end
	if not (GameTooltip and type(GameTooltip.SetMinimapMouseover) == "function") then return false end
	-- Runs every frame while the mouse is on the map: errors are reported once, then skipped quietly.
	local reported = false
	hooksecurefunc(GameTooltip, "SetMinimapMouseover", function(tip)
		local ok, err = pcall(OnMinimapMouseover, tip)
		if not ok and not reported then
			reported = true
			local handler = geterrorhandler and geterrorhandler()
			if handler then handler(err) end
		end
	end)
	self.hooked = true
	return true
end

function Ore:Setup()
	if ns.db and ns.db.oreLabels then self:Hook() end
end

-- `/mmap ore`: on/off, saved.
function Ore:Toggle()
	local on = not ns.db.oreLabels
	if on and not self:Hook() then
		ns.Print(L.ORE_MISSING)
		return
	end
	ns.db.oreLabels = on
	ns.Print(on and L.ORE_ON or L.ORE_OFF)
end
