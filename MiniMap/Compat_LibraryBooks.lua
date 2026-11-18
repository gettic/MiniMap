-- Mini Map: compatibility with Library Books (by Taraezor).
-- Library Books puts its minimap pins on a circle the size of the minimap when they are far
-- away. On our square map that circle shows as a curve. After Library Books places a pin, this
-- moves it outward along the same direction: to its real spot if that is inside the square
-- (the corners), else onto the square's edge. Pins inside the circle are never touched.
-- Only Library Books' own pins (unprotected frames, recognised by their fields) are moved.
local ADDON, ns = ...
local T = ns.Theme

local Books = {}
ns.Books = Books

local BOOKS_ADDON = "Library Books" -- folder name
local INSET = 2                     -- px inside the edge (same as their circle)

local hooked = setmetatable({}, { __mode = "k" }) -- [pin] = true
local scanner, lastCount, sinceScan
local failed = false

local abs, max, sqrt, type = math.abs, math.max, math.sqrt, type

-- True only for a Library Books minimap pin: an unnamed plain Frame on the Minimap with their
-- pin method and data fields.
local function IsBooksPin(f)
	if type(f) ~= "table" or not f.GetObjectType then return false end
	if f:GetObjectType() ~= "Frame" or f:GetName() ~= nil then return false end
	if f.IsForbidden and f:IsForbidden() then return false end
	if f.IsProtected and f:IsProtected() then return false end
	if f:GetParent() ~= Minimap then return false end
	return type(f.UpdatePosition) == "function" and type(f.OnLoad) == "function"
		and type(f.dataX) == "number" and type(f.dataY) == "number"
		and type(f.index) == "number" and f.sourceMapID ~= nil and type(f.Texture) == "table"
end

-- The pin's new offset from the minimap's centre, or nil to leave it where it is.
-- x, y: where Library Books put it; d: its real distance (before their clamp); r: half width.
function Books.SquareSpot(x, y, d, r)
	local maxR = r - INSET
	if type(d) ~= "number" or d <= maxR then return nil end -- inside the circle: already right
	local len = sqrt(x * x + y * y)
	if len == 0 then return nil end
	local tx, ty = x / len * d, y / len * d -- real spot, same direction
	local m = max(abs(tx), abs(ty))
	local edge = r - INSET
	if m > edge then tx, ty = tx * edge / m, ty * edge / m end
	return tx, ty
end

local function Nudge(pin)
	if not Books.enabled or not pin:IsShown() or pin:GetNumPoints() ~= 1 then return end
	local point, rel, relPoint, x, y = pin:GetPoint(1)
	if point ~= "CENTER" or rel ~= Minimap or relPoint ~= "CENTER" then return end
	local nx, ny = Books.SquareSpot(x or 0, y or 0, pin.distance, Minimap:GetWidth() / 2)
	if nx then pin:SetPoint("CENTER", Minimap, "CENTER", nx, ny) end
end

-- Runs after Library Books' own UpdatePosition. Never lets an error reach their code:
-- the first error is shown once and the nudge switches itself off.
local function AfterUpdate(pin)
	if failed then return end
	local ok, err = pcall(Nudge, pin)
	if not ok then
		failed = true
		Books.enabled = false
		local handler = geterrorhandler and geterrorhandler()
		if handler then handler(err) end
	end
end

local function HookChildren(...)
	for i = 1, select("#", ...) do
		local f = select(i, ...)
		if not hooked[f] and IsBooksPin(f) then
			hooked[f] = true
			-- Library Books makes its pins MEDIUM once (at creation): bring them into the map's
			-- layer, so they sit under the coordinates and other addons' windows like the map.
			if f.SetFrameStrata and f:GetFrameStrata() ~= T.layer then f:SetFrameStrata(T.layer) end
			hooksecurefunc(f, "UpdatePosition", AfterUpdate)
			AfterUpdate(f)
		end
	end
end

function Books:Scan()
	HookChildren(Minimap:GetChildren())
end

-- Pins are only made when Library Books builds a zone, so we look again only when the number
-- of Minimap children changes (or every 0.5 s if the game hides that number).
local function OnUpdate(_, elapsed)
	local n = Minimap:GetNumChildren()
	if issecretvalue and issecretvalue(n) then
		sinceScan = (sinceScan or 0) + elapsed
		if sinceScan < 0.5 then return end
		sinceScan = 0
	elseif n == lastCount then
		return
	else
		lastCount = n
	end
	ns.SafeRun("LibraryBooks", Books.Scan, Books)
end

function Books.ShouldRun()
	return ns.db and ns.db.booksNudge ~= false and ns.Square.active and not failed
		and ns.IsLoaded(BOOKS_ADDON) and true or false
end

-- /mmap selftest: watcher running, number of hooked pins, switched off after an error. Read only.
function Books.State()
	local n = 0
	for _ in pairs(hooked) do n = n + 1 end
	local running = scanner and scanner:GetScript("OnUpdate") ~= nil or false
	return running, n, failed
end

-- Starts or stops the watcher to match the setting; safe to call again.
function Books:Setup()
	self.enabled = Books.ShouldRun()
	if self.enabled then
		if not scanner then scanner = CreateFrame("Frame") end
		lastCount = nil
		scanner:SetScript("OnUpdate", OnUpdate)
	elseif scanner then
		scanner:SetScript("OnUpdate", nil) -- hooks stay, but do nothing while off
	end
end

-- /mmap bookson | booksoff
function Books:SetOn(on)
	if ns.db then ns.db.booksNudge = on and true or false end
	self:Setup()
	if not on then
		ns.Print(ns.L.BOOKS_OFF)
	elseif self.enabled then
		ns.Print(ns.L.BOOKS_ON)
	else
		ns.Print(ns.L.BOOKS_ON_IDLE)
	end
end
