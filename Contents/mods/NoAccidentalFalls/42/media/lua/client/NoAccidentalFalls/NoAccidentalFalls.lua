-- No Accidental Falls (client).
-- 1) Edge guard: walking or running off a floor edge into open air puts the player back on the
--    floor they came from (sliding along the edge still works).
-- 2) Climb guard: climbing over a low fence/railing or through a window onto open air is
--    refused, unless the sandbox option allows deliberate climbs (long E press, right-click menu).
-- Vanilla already refuses running vaults and tall-wall climbs onto open air
-- (IsoPlayer.isSafeToClimbOver in checkVaultOver / doContextHopOverFence / canClimbOverWall).

NoAccidentalFalls = NoAccidentalFalls or {}
local M = NoAccidentalFalls

local function log(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
	print("[NoAccidentalFalls] " .. table.concat(parts, " "))
end
M.log = log

local function opt(name, default)
	local t = SandboxVars and SandboxVars.NoAccidentalFalls
	if t == nil or t[name] == nil then return default end
	return t[name]
end
function M.edgeGuardOn() return opt("EdgeGuard", true) end
function M.climbGuardOn() return opt("ClimbGuard", true) end
function M.allowManualClimb() return opt("AllowManualClimb", true) end

-- Open air: same rule as vanilla IsoPlayer.isSafeToClimbOver (no solid floor and no stairs
-- below), plus stairs squares themselves count as floor. A missing square above ground is air;
-- a missing square on the ground floor is an unloaded chunk, not a drop.
function M.isDrop(sq, z)
	if sq == nil then return (z or 0) > 0 end
	if sq:TreatAsSolidFloor() then return false end
	if sq:HasStairs() or sq:HasStairsBelow() then return false end
	return true
end

local function squareAt(x, y, z)
	return getCell():getGridSquare(math.floor(x), math.floor(y), z)
end

------------------------------------------------------------------ edge guard

-- per player index: last position on a floor
M.safe = M.safe or {}
M.edgeBlocks = M.edgeBlocks or 0

local function busy(pl)
	if pl:getVehicle() then return true end
	if pl:isClimbing() then return true end
	local st = pl:getCurrentState()
	if st == ClimbOverFenceState.instance() or st == ClimbThroughWindowState.instance()
		or st == ClimbOverWallState.instance() then return true end
	if pl:isNoClip() then return true end
	local n = st and tostring(st) or ""
	if n:find("ClimbState", 1, true) or n:find("ClimbDownState", 1, true) or n:find("SheetRope", 1, true) then return true end
	return false
end

local function putBack(pl, x, y, z)
	pl:setX(x); pl:setY(y); pl:setZ(z)
	pl:setLastX(x); pl:setLastY(y); pl:setLastZ(z)
	pl:setNextX(x); pl:setNextY(y)
	pl:setFallTime(0)
	pl:setbFalling(false)
	pl:setCurrentSquareFromPosition()
end

-- How close the player's centre may come to an open-air edge. Vanilla keeps 0.2 from the side
-- walls of stairs the same way (IsoMovingObject: setX(floor(x) + 0.2) after the move).
M.MARGIN = 0.25
M.LADDER_MARGIN = 0.1
M.clamps = M.clamps or 0

-- Pushes the player back inside the floor square when the centre is within MARGIN of an edge
-- whose neighbour is open air. Only on flat floor (whole-number z) over a floor square; stairs
-- are left alone. Uses the square under the position, not getCurrentSquare() (that one lags a
-- frame behind a setX).
function M.clampToEdges(pl, x, y, z)
	local level = math.floor(z + 0.001)
	if math.abs(z - level) > 0.01 then return false end
	local cur = squareAt(x, y, level)
	if cur == nil or M.isDrop(cur, level) or cur:HasStairs() then return false end
	local sx, sy = math.floor(x), math.floor(y)
	local fx, fy = x - sx, y - sy
	-- the top of a ladder: vanilla walks the player to 0.2 from the edge before climbing down
	-- (ISWorldObjectContextMenu.onClimbLadder), so keep a smaller margin there
	local m = cur:getLadderUnder() and M.LADDER_MARGIN or M.MARGIN
	local drop = function(dx, dy) return M.isDrop(getCell():getGridSquare(sx + dx, sy + dy, level), level) end
	local nx, ny = x, y
	local w, e, n, s = fx < m and drop(-1, 0), fx > 1 - m and drop(1, 0), fy < m and drop(0, -1), fy > 1 - m and drop(0, 1)
	if w then nx = sx + m elseif e then nx = sx + 1 - m end
	if n then ny = sy + m elseif s then ny = sy + 1 - m end
	-- an outside corner: both sides are floor but the diagonal is air; push out along the shallower side
	if not (w or e or n or s) then
		local cx = (fx < m and -1) or (fx > 1 - m and 1) or 0
		local cy = (fy < m and -1) or (fy > 1 - m and 1) or 0
		if cx ~= 0 and cy ~= 0 and drop(cx, cy) then
			local px = cx < 0 and (m - fx) or (fx - (1 - m))
			local py = cy < 0 and (m - fy) or (fy - (1 - m))
			if px < py then nx = cx < 0 and sx + m or sx + 1 - m
			else ny = cy < 0 and sy + m or sy + 1 - m end
		end
	end
	if nx == x and ny == y then return false end
	pl:setX(nx); pl:setY(ny)
	pl:setNextX(nx); pl:setNextY(ny)
	M.clamps = M.clamps + 1
	if M.verbose then log("clamp", string.format("%.3f,%.3f -> %.3f,%.3f", x, y, nx, ny)) end
	return true
end

function M.onPlayerUpdate(pl)
	M.updates = (M.updates or 0) + 1
	if not pl or not pl:isLocalPlayer() then return end
	local idx = pl:getPlayerNum()
	if not M.edgeGuardOn() or busy(pl) or pl:isDead() then
		M.safe[idx] = nil
		return
	end
	local x, y, z = pl:getX(), pl:getY(), pl:getZ()
	local s = M.safe[idx]
	local onFloor = pl:getFallTime() <= 0 and not pl:isbFalling()
	if onFloor then
		local level = math.floor(z + 0.001)
		if not M.isDrop(squareAt(x, y, level), level) then
			-- on a floor: keep a margin from open-air edges (like a wall), then remember the spot
			if M.clampToEdges(pl, x, y, z) then x, y = pl:getX(), pl:getY() end
			s = s or {}
			s.x, s.y, s.z, s.frames = x, y, z, 0
			M.safe[idx] = s
			return
		end
		-- over open air but the fall has not started yet: fall through to the put-back
	end
	-- (about to) fall: was it a step off the edge just now? Only from a spot recorded over floor.
	if not s then return end
	s.frames = s.frames + 1
	if s.frames > 30 or math.abs(x - s.x) > 1.5 or math.abs(y - s.y) > 1.5 or z < s.z - 0.75 then
		M.safe[idx] = nil -- a real fall we did not cause (floor destroyed, pushed, ...)
		return
	end
	local level = math.floor(s.z + 0.001)
	if not M.isDrop(squareAt(x, y, level), level) then return end
	if M.isDrop(squareAt(s.x, s.y, level), level) then
		M.safe[idx] = nil -- the floor we stood on is gone (collapse, sledgehammer): a real fall
		return
	end
	-- slide along the edge when one axis is still over floor
	local nx, ny = s.x, s.y
	if not M.isDrop(squareAt(x, s.y, level), level) then
		nx, ny = x, s.y
	elseif not M.isDrop(squareAt(s.x, y, level), level) then
		nx, ny = s.x, y
	end
	putBack(pl, nx, ny, s.z)
	s.x, s.y, s.frames = nx, ny, 0
	M.edgeBlocks = M.edgeBlocks + 1
	if M.verbose then log("put back", string.format("%.2f,%.2f,%.2f -> %.2f,%.2f", x, y, z, nx, ny)) end
end

------------------------------------------------------------------ climb guard

local function say(pl)
	if pl and pl.setHaloNote then
		pl:setHaloNote(getText("IGUI_NoAccidentalFalls_Blocked"), 255, 160, 80, 300)
	end
end

local function dirStep(dir)
	if dir == IsoDirections.N then return 0, -1 end
	if dir == IsoDirections.S then return 0, 1 end
	if dir == IsoDirections.W then return -1, 0 end
	if dir == IsoDirections.E then return 1, 0 end
	return 0, 0
end

-- where a fence climb lands: next to the player's square in the climb direction
function M.fenceTarget(action)
	local pl = action.character
	local ok, dir = pcall(function() return action:getFacingDirection() end)
	if not ok or not dir then return nil end
	local dx, dy = dirStep(dir)
	if dx == 0 and dy == 0 then return nil end
	local z = math.floor(pl:getZ() + 0.001)
	return getCell():getGridSquare(math.floor(pl:getX()) + dx, math.floor(pl:getY()) + dy, z), z
end

local function isNorth(obj)
	local ok, n = pcall(function() return obj:getNorth() end)
	if ok and n ~= nil then return n end
	local sq = obj:getSquare()
	return sq ~= nil and sq:has(IsoFlagType.WindowN)
end

-- where a window climb lands: the side of the window the player is not on
function M.windowTarget(action)
	local pl, w = action.character, action.item
	local sq = w and w:getSquare()
	if not sq then return nil end
	local z = sq:getZ()
	local other
	if isNorth(w) then
		other = getCell():getGridSquare(sq:getX(), sq:getY() - 1, z)
		if pl:getY() < sq:getY() then return sq, z end
	else
		other = getCell():getGridSquare(sq:getX() - 1, sq:getY(), z)
		if pl:getX() < sq:getX() then return sq, z end
	end
	return other, z
end

local function haveRope(obj)
	local ok, r = pcall(function() return obj:haveSheetRope() end)
	return ok and r == true
end

-- true when this climb must be refused
function M.blockClimb(kind, action)
	if not M.climbGuardOn() or M.allowManualClimb() then return false end
	local target, z
	if kind == "window" then
		if haveRope(action.item) then return false end
		target, z = M.windowTarget(action)
	else
		if haveRope(action.item) then return false end
		target, z = M.fenceTarget(action)
	end
	if z == nil then return false end
	return M.isDrop(target, z)
end

M.climbBlocks = M.climbBlocks or 0

local function wrapIsValid(cls, kind)
	if not cls or cls.__NoAccidentalFalls then return false end
	local orig = cls.isValid
	cls.isValid = function(self, ...)
		if M.blockClimb(kind, self) then
			if not self.__nafSaid then
				self.__nafSaid = true
				M.climbBlocks = M.climbBlocks + 1
				say(self.character)
				log("climb refused", kind)
			end
			return false
		end
		return orig(self, ...)
	end
	cls.__NoAccidentalFalls = true
	return true
end

function M.install()
	local a = wrapIsValid(ISClimbOverFence, "fence")
	local b = wrapIsValid(ISClimbThroughWindow, "window")
	log("installed", "fence=" .. tostring(a or (ISClimbOverFence and ISClimbOverFence.__NoAccidentalFalls)),
		"window=" .. tostring(b or (ISClimbThroughWindow and ISClimbThroughWindow.__NoAccidentalFalls)))
end

Events.OnGameStart.Add(M.install)
Events.OnPlayerUpdate.Add(function(pl) M.onPlayerUpdate(pl) end)
