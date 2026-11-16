-- No Accidental Falls in-game test (pzt TEST_FILES only, not shipped). One client, every scenario.
-- Movement uses real key presses (tests/tools/keys.ps1 via tests/tools/livetest.sh).
-- NAFTest.start() runs the scenarios as coroutines on one top-level OnTick; NAFTest.poll() re-queues
-- itself until done. Results: "[NAFTest] PASS/FAIL"; failures also "[PZTest] FAIL". No error().
--
-- World built next to the save's player (O = origin):
--   level 1: floor platform O+0..4 x O+0..4.
--     east  (x = 5): no squares at all (open air)
--     north (y = -1): squares without floor (open air)
--     south (y = 5): squares without floor, a low stick fence (HoppableN) on their north edge = railing
--   level 0: a stick fence on the north edge of (O+9, O+4) for a normal ground vault.

NAFTest = NAFTest or {}
local T = NAFTest
local M = function() return NoAccidentalFalls end

local function log(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
	print("[NAFTest] " .. table.concat(parts, " "))
end

T.pass, T.fail = 0, 0
local function check(ok, label, extra)
	if ok then T.pass = T.pass + 1 else T.fail = T.fail + 1 end
	log(ok and "PASS" or "FAIL", T.scenario or "", label, extra ~= nil and tostring(extra) or "")
	if not ok and PZTest and PZTest.fail then PZTest.fail("NAFTest " .. tostring(T.scenario) .. " " .. label .. " " .. tostring(extra or "")) end
	return ok
end

local function p() return getPlayer() end
local function yield() coroutine.yield() end
local function waitTicks(n) for _ = 1, n do yield() end end
local function waitUntil(fn, ticks, label)
	for _ = 1, ticks do
		local ok, res = pcall(fn)
		if ok and res then return true end
		yield()
	end
	if label then log("timeout:", label, ticks) end
	return false
end

local function protect()
	local pl = p()
	if not pl then return end
	pl:setGodMod(true)
	pl:setInvisible(true)
	pl:setZombiesDontAttack(true)
	pl:setGhostMode(true)
end
local function unprotect()
	local pl = p()
	pl:setGodMod(false); pl:setInvisible(false); pl:setZombiesDontAttack(false); pl:setGhostMode(false)
end
local function clearZombies()
	local list = getCell():getZombieList()
	for i = list:size() - 1, 0, -1 do
		local z = list:get(i)
		if z and z:DistTo(p()) < 80 then z:removeFromSquare(); z:removeFromWorld() end
	end
end

local function setOpt(name, value)
	SandboxVars.NoAccidentalFalls = SandboxVars.NoAccidentalFalls or {}
	SandboxVars.NoAccidentalFalls[name] = value
end
local function defaults()
	setOpt("EdgeGuard", true); setOpt("ClimbGuard", true); setOpt("AllowManualClimb", true)
end

------------------------------------------------------------------ world

local FENCE_N = "crafted_04_123"   -- low stick fence, north edge (entity StickFence, face N)
local FLOOR = "carpentry_02_58"    -- wooden floor lvl1

local function sq(x, y, z) return getCell():getGridSquare(T.ox + x, T.oy + y, z) end
local function mk(x, y, z) return getCell():getOrCreateGridSquare(T.ox + x, T.oy + y, z) end

local function clearSquare(s, keepFloor)
	local objs = s:getObjects()
	for i = objs:size() - 1, 0, -1 do
		local o = objs:get(i)
		if not (keepFloor and o == s:getFloor()) then s:transmitRemoveItemFromSquare(o) end
	end
end

local function addFence(s)
	local o = IsoObject.new(getCell(), s, getSprite(FENCE_N))
	s:AddTileObject(o)
	return o
end

local function build()
	local pl = p()
	T.ox, T.oy = math.floor(pl:getX()) + 4, math.floor(pl:getY()) + 4
	-- level 0 under and around: nothing but the ground
	for x = -2, 12 do
		for y = -2, 8 do
			local g = mk(x, y, 0)
			clearSquare(g, true)
			if not g:getFloor() then g:addFloor("blends_natural_01_64") end
		end
	end
	-- level 1
	for x = -2, 12 do
		for y = -2, 8 do
			local s = sq(x, y, 1)
			if s then clearSquare(s, false) end
		end
	end
	for x = 0, 4 do
		for y = 0, 4 do mk(x, y, 1):addFloor(FLOOR) end
		mk(x, -1, 1)
		T.rail = T.rail or {}
		T.rail[x] = addFence(mk(x, 5, 1))
	end
	T.groundFence = addFence(mk(9, 4, 0))
	for x = -2, 12 do
		for y = -2, 8 do
			for z = 0, 1 do
				local s = sq(x, y, z)
				if s then s:RecalcAllWithNeighbours(true) end
			end
		end
	end
	check(sq(2, 2, 1) and sq(2, 2, 1):TreatAsSolidFloor(), "platform floor")
	check(sq(5, 2, 1) == nil or not sq(5, 2, 1):TreatAsSolidFloor(), "east is open air", sq(5, 2, 1))
	check(sq(2, -1, 1) and not sq(2, -1, 1):TreatAsSolidFloor(), "north is open air")
	check(sq(2, 5, 1) and sq(2, 5, 1):has(IsoFlagType.HoppableN), "railing is hoppable")
	check(sq(9, 4, 0):has(IsoFlagType.HoppableN), "ground fence is hoppable")
end

local function teleport(x, y, z, dir)
	local pl = p()
	local ax, ay = T.ox + x, T.oy + y
	pl:setX(ax); pl:setY(ay); pl:setZ(z)
	pl:setLastX(ax); pl:setLastY(ay); pl:setLastZ(z)
	pl:setNextX(ax); pl:setNextY(ay)
	pl:setCurrentSquareFromPosition()
	pl:setFallTime(0)
	if dir then pl:setDir(dir) end
	waitTicks(20)
end

------------------------------------------------------------------ real keys

local keyId = (getTimestampMs and getTimestampMs() or 0) % 1000000
local function requestKeys(keys, ms)
	keyId = keyId + 1
	local w = getFileWriter("naf_key_req.txt", true, false)
	w:write(keyId .. " " .. keys .. " " .. ms .. "\n")
	w:close()
	return keyId
end
local function keysDone(id)
	local r = getFileReader("naf_key_done.txt", false)
	if not r then return nil end
	local line = r:readLine()
	r:close()
	if not line then return nil end
	local doneId, rest = line:match("^(%d+)%s+(.*)$")
	if tonumber(doneId) ~= id then return nil end
	return rest
end

-- holds keys and samples the player every tick; returns the samples summary
local function press(keys, ms)
	local pl = p()
	local s = { minZ = pl:getZ(), states = {}, x0 = pl:getX(), y0 = pl:getY() }
	local id = requestKeys(keys, ms)
	local res
	local function sample()
		local z = pl:getZ()
		if z < s.minZ then s.minZ = z end
		local st = pl:getCurrentState()
		if st == ClimbOverFenceState.instance() then s.states.fence = true end
		if pl:isRunning() then s.states.run = true end
		if pl:isSprinting() then s.states.sprint = true end
	end
	waitUntil(function() sample(); res = keysDone(id); return res ~= nil end, 1200, "keys " .. keys)
	-- let the animation finish (a climb or a fall)
	for _ = 1, 150 do sample(); yield() end
	s.res = res
	s.ok = res and string.sub(res, 1, 2) == "ok"
	s.dx, s.dy = pl:getX() - s.x0, pl:getY() - s.y0
	s.x, s.y, s.z = pl:getX() - T.ox, pl:getY() - T.oy, pl:getZ()
	log("keys", keys, ms, "->", res, string.format("moved %.2f,%.2f now %.2f,%.2f,%.2f minZ %.3f", s.dx, s.dy, s.x, s.y, s.z, s.minZ),
		"fence", tostring(s.states.fence), "run", tostring(s.states.run), "sprint", tostring(s.states.sprint))
	return s
end

-- screen directions with the default keys: S+D = east (+x), S+A = south (+y), W+D = north (-y), W+A = west (-x)

------------------------------------------------------------------ scenarios

local function scSetup()
	defaults()
	clearZombies()
	build()
	teleport(2.5, 2.5, 1)
	check(math.abs(p():getZ() - 1) < 0.01 and p():getCurrentSquare() == sq(2, 2, 1), "player on platform", p():getZ())
	M().edgeBlocks, M().climbBlocks, M().clamps = 0, 0, 0
end

-- control: guard off, walking east falls (the drop is real)
local function scControl()
	setOpt("EdgeGuard", false)
	teleport(3.5, 2.5, 1)
	local s = press("S,D", 1500)
	check(s.ok, "keys sent", s.res)
	check(s.dx > 0.5, "moved east", s.dx)
	check(s.z < 0.5, "guard off: fell to the ground", s.z)
	setOpt("EdgeGuard", true)
end

local function scWalkEast()
	teleport(3.5, 2.5, 1)
	local before, beforeC = M().edgeBlocks, M().clamps
	local s = press("S,D", 2000)
	check(s.ok, "keys sent", s.res)
	check(s.dx > 0.5, "moved east", s.dx)
	check(s.minZ > 0.9, "never dropped", s.minZ)
	check(s.x < 5 and s.z > 0.99, "stopped on the platform", string.format("%.2f %.2f", s.x, s.z))
	check(M().clamps > beforeC, "kept off the edge (clamp)", M().clamps - beforeC)
	log("rollbacks during walkEast", M().edgeBlocks - before, "(0 = the clamp alone was enough)")
end

local function scRunNorth()
	teleport(2.5, 2.5, 1)
	local s = press("LSHIFT,W,D", 4000)
	check(s.ok, "keys sent", s.res)
	check(s.states.run, "was running")
	check(s.dy < -0.5, "moved north", s.dy)
	check(s.minZ > 0.9 and s.y >= 0 and s.z > 0.99, "stopped on the platform", string.format("y %.2f z %.2f minZ %.3f", s.y, s.z, s.minZ))
end

-- diagonal into the north-east corner: slides along the edge, still stays up
local function scDiagonal()
	teleport(2.5, 2.5, 1)
	local s = press("LSHIFT,D", 2000) -- D alone = north-east on screen right
	check(s.ok, "keys sent", s.res)
	check(s.minZ > 0.9 and s.z > 0.99, "stayed up", string.format("%.2f,%.2f z %.2f", s.x, s.y, s.z))
end

local function scSprintRailing()
	teleport(2.5, 2.5, 1)
	local s = press("LALT,S,A", 2000)
	check(s.ok, "keys sent", s.res)
	check(s.states.sprint or s.states.run, "was sprinting", tostring(s.states.sprint))
	check(s.dy > 0.5, "moved south", s.dy)
	check(not s.states.fence, "no vault over the railing")
	check(s.minZ > 0.9 and s.y < 5 and s.z > 0.99, "stayed on the platform", string.format("y %.2f z %.2f", s.y, s.z))
end

-- ground floor: a normal running vault still happens
local function scGroundVault()
	teleport(9.5, 2.0, 0)
	local s = press("LALT,S,A", 1500)
	check(s.ok, "keys sent", s.res)
	check(s.states.fence, "vaulted the ground fence")
	check(s.y > 4, "on the far side", s.y)
end

-- long E at the railing with deliberate climbs allowed: climbs over and falls (god mode)
local function scManualAllowed()
	setOpt("AllowManualClimb", true)
	teleport(2.5, 4.6, 1, IsoDirections.S)
	local s = press("E", 1200)
	check(s.ok, "keys sent", s.res)
	check(s.states.fence, "climbed the railing")
	check(s.z < 0.5, "and fell (allowed)", s.z)
end

local function scManualRefused()
	setOpt("AllowManualClimb", false)
	teleport(2.5, 4.6, 1, IsoDirections.S)
	local before = M().climbBlocks
	local s = press("E", 1200)
	check(s.ok, "keys sent", s.res)
	check(not s.states.fence, "no climb")
	check(s.z > 0.99, "still on the platform", s.z)
	check(M().climbBlocks > before, "climb guard refused it", M().climbBlocks - before)
	-- the same action from the right-click menu path
	local a = ISClimbOverFence:new(p(), T.rail[2], IsoDirections.S)
	check(a:isValid() == false, "menu climb action refused")
	setOpt("AllowManualClimb", true)
	check(a:isValid() == true, "allowed again with the option on")
end

-- window logic (no real upper-floor window here): fake action objects
local function scWindowLogic()
	setOpt("AllowManualClimb", false)
	local pl = p()
	teleport(2.5, 4.5, 1)
	local function fake(wx, wy, north, rope)
		local wsq = mk(wx, wy, 1)
		return { character = pl, item = {
			getSquare = function() return wsq end,
			getNorth = function() return north end,
			haveSheetRope = function() return rope end,
		} }
	end
	-- window on the north edge of (2,5): player at y 4.5 is north of it, lands on (2,5) = air
	check(M().blockClimb("window", fake(2, 5, true, false)) == true, "window onto air refused")
	check(M().blockClimb("window", fake(2, 5, true, true)) == false, "window with sheet rope allowed")
	-- window on the north edge of (2,4): player on (2,4) lands on (2,3) = floor
	check(M().blockClimb("window", fake(2, 4, true, false)) == false, "window onto floor allowed")
	setOpt("AllowManualClimb", true)
	check(M().blockClimb("window", fake(2, 5, true, false)) == false, "option on: allowed")
end

local function scStairsLogic()
	-- isDrop rules: missing ground square is not a drop, missing upper square is
	check(M().isDrop(nil, 0) == false, "missing ground square is not a drop")
	check(M().isDrop(nil, 1) == true, "missing upper square is a drop")
	check(M().isDrop(sq(2, 2, 1), 1) == false, "platform is not a drop")
	check(M().isDrop(sq(2, -1, 1), 1) == true, "floorless square is a drop")
end

local function cleanup()
	defaults()
	teleport(2.5, 2.5, 1)
	unprotect()
	log("cleanup done")
end


------------------------------------------------------------------ more single-player scenarios
-- ladder (real ladder tile), floor collapse, sheet rope on the railing, a real house (stairs and
-- an upper-floor window, with and without a sheet rope).

local LADDER_W = "carpentry_02_84" -- wooden ladder, ladderW (against the west side of its square)

local function placeAt(x, y, z)
	local pl = p()
	pl:setX(x); pl:setY(y); pl:setZ(z)
	pl:setLastX(x); pl:setLastY(y); pl:setLastZ(z)
	pl:setNextX(x); pl:setNextY(y)
	pl:setCurrentSquareFromPosition()
	pl:setFallTime(0)
	waitTicks(20)
end

local function stateName(pl)
	local st = pl:getCurrentState()
	local n = st and tostring(st) or "nil"
	return (n:match("%.([%w_]+)@") or n)
end

-- runs until the action queue is empty and the player is idle (or ticks run out)
local function runQueue(ticks)
	local pl = p()
	local seen, minZ = {}, pl:getZ()
	local quiet = 0
	for _ = 1, ticks do
		local z = pl:getZ()
		if z < minZ then minZ = z end
		seen[stateName(pl)] = true
		if #ISTimedActionQueue.getTimedActionQueue(pl).queue == 0 and stateName(pl) == "IdleState" then quiet = quiet + 1 else quiet = 0 end
		if quiet > 60 then break end
		yield()
	end
	local names = {}
	for k in pairs(seen) do names[#names + 1] = k end
	table.sort(names)
	return minZ, table.concat(names, ",")
end

local function clearQueue()
	ISTimedActionQueue.clear(p())
end

local function relPos(pl)
	return string.format("%.2f,%.2f,%.2f", pl:getX() - T.ox, pl:getY() - T.oy, pl:getZ())
end

local function scLadder()
	-- ladder at ground (5,2,0) against the platform's east edge; its top square is the air at (5,2,1)
	local g = mk(5, 2, 0)
	clearSquare(g, true)
	T.ladder = IsoObject.new(getCell(), g, getSprite(LADDER_W))
	g:AddTileObject(T.ladder)
	g:RecalcAllWithNeighbours(true)
	local roof = sq(4, 2, 1)
	local pl = p()
	check(roof:getLadderUnder() == T.ladder, "ladder found from the roof square", tostring(roof:getLadderUnder()))
	for _, guard in ipairs({ false, true }) do
		setOpt("EdgeGuard", guard)
		clearQueue()
		placeAt(T.ox + 2.5, T.oy + 2.5, 1)
		ISWorldObjectContextMenu.onClimbLadder(roof, true, pl, pl:getClimbLadderDown(roof) or T.ladder)
		local minZ, states = runQueue(900)
		log("ladder down guard=" .. tostring(guard), "now " .. relPos(pl), states)
		check(pl:getZ() < 0.1 and string.find(states, "ClimbDown", 1, true) ~= nil, "guard " .. tostring(guard) .. ": climbed down the ladder", relPos(pl) .. " " .. states)
		clearQueue()
		placeAt(T.ox + 6.5, T.oy + 2.5, 0)
		ISWorldObjectContextMenu.onClimbLadder(g, false, pl, pl:getClimbLadder(g) or T.ladder)
		minZ, states = runQueue(900)
		log("ladder up guard=" .. tostring(guard), "now " .. relPos(pl), states)
		local here = getCell():getGridSquare(math.floor(pl:getX()), math.floor(pl:getY()), 1)
		check(pl:getZ() > 0.99 and here ~= nil and here:TreatAsSolidFloor(), "guard " .. tostring(guard) .. ": climbed up onto the roof", relPos(pl) .. " " .. states)
	end
	defaults()
	clearQueue()
	g:transmitRemoveItemFromSquare(T.ladder)
	T.ladder = nil
end

local function scCollapse()
	-- the floor under the player goes away (StructuralCollapse, a sledgehammer): the player must fall
	placeAt(T.ox + 1.5, T.oy + 2.5, 1)
	local s = sq(1, 2, 1)
	local f = s:getFloor()
	check(f ~= nil, "floor to remove")
	if f then s:transmitRemoveItemFromSquare(f) end
	s:RecalcAllWithNeighbours(true)
	local pl = p()
	for _ = 1, 200 do yield() end
	log("collapse now", relPos(pl))
	check(pl:getZ() < 0.1, "fell through the removed floor", pl:getZ())
	s:addFloor(FLOOR)
	s:RecalcAllWithNeighbours(true)
end

local function scFenceRope()
	setOpt("AllowManualClimb", false)
	local fence = T.rail[1]
	local ok, can = pcall(function() return fence:canAddSheetRope() end)
	log("fence canAddSheetRope", ok, can)
	if ok and can then
		p():getInventory():AddItems("Base.SheetRope", 6)
		p():getInventory():AddItems("Base.Nails", 10)
		local ok2, err = pcall(function() return fence:addSheetRope(p(), "SheetRope") end)
		local ok3, have = pcall(function() return fence:haveSheetRope() end)
		log("fence addSheetRope", ok2, err, "have", ok3, have)
		placeAt(T.ox + 1.5, T.oy + 4.6, 1)
		local a = ISClimbOverFence:new(p(), fence, IsoDirections.S)
		check(M().blockClimb("fence", a) == false, "railing with a sheet rope: climb allowed")
		pcall(function() fence:removeSheetRope(p()) end)
	else
		log("this railing takes no sheet rope; skipped")
	end
	setOpt("AllowManualClimb", true)
end

-- a real house nearby: stairs from level 0 and a level-1 window over a drop
local function findStairs()
	if T.stairsAt then return getCell():getGridSquare(T.stairsAt[1], T.stairsAt[2], 0) end
	local pl = p()
	local px, py = math.floor(pl:getX()), math.floor(pl:getY())
	for r = 0, 70 do
		for x = px - r, px + r do
			for y = py - r, py + r do
				if math.abs(x - px) == r or math.abs(y - py) == r then
					local s = getCell():getGridSquare(x, y, 0)
					if s and s:HasStairs() and s:getBuilding() then return s end
				end
			end
		end
	end
end

local function findWindow(building)
	local def = building:getDef()
	for x = def:getX() - 1, def:getX2() + 1 do
		for y = def:getY() - 1, def:getY2() + 1 do
			local s = getCell():getGridSquare(x, y, 1)
			if s then
				local objs = s:getObjects()
				for i = 0, objs:size() - 1 do
					local o = objs:get(i)
					if instanceof(o, "IsoWindow") then
						local b = o:getNorth() and getCell():getGridSquare(x, y - 1, 1) or getCell():getGridSquare(x - 1, y, 1)
						if s:TreatAsSolidFloor() and M().isDrop(b, 1) then return o, s, b end
						if b and b:TreatAsSolidFloor() and M().isDrop(s, 1) then return o, b, s end
					end
				end
			end
		end
	end
end

local function scHouse(stairsOnly)
	local stairs = findStairs()
	if not check(stairs ~= nil, "a house with stairs nearby") then return end
	local b = stairs:getBuilding()
	log("house stairs at", stairs:getX(), stairs:getY())
	local pl = p()
	local def = b:getDef()
	local top
	for x = def:getX(), def:getX2() do
		for y = def:getY(), def:getY2() do
			local s = getCell():getGridSquare(x, y, 1)
			if not top and s and s:TreatAsSolidFloor() and not s:HasStairs() and s:getBuilding() == b and s:isFree(false) then top = s end
		end
	end
	local bottom
	for _, d in ipairs({ { 0, 1 }, { 1, 0 }, { 0, -1 }, { -1, 0 }, { 0, 2 }, { 2, 0 }, { 0, -2 }, { -2, 0 } }) do
		local s = getCell():getGridSquare(stairs:getX() + d[1], stairs:getY() + d[2], 0)
		if not bottom and s and s:TreatAsSolidFloor() and not s:HasStairs() and s:isFree(false) then bottom = s end
	end
	if check(top ~= nil and bottom ~= nil, "stairs walk squares") then
		for _, guard in ipairs({ false, true }) do
			setOpt("EdgeGuard", guard)
			clearQueue()
			placeAt(bottom:getX() + 0.5, bottom:getY() + 0.5, 0)
			local c0 = M().clamps or 0
			ISTimedActionQueue.add(ISWalkToTimedAction:new(pl, top))
			local minZ, states = runQueue(1500)
			log("stairs up guard=" .. tostring(guard), "now", math.floor(pl:getX()), math.floor(pl:getY()), string.format("%.2f", pl:getZ()), "clamps", (M().clamps or 0) - c0, states)
			check(pl:getCurrentSquare() == top, "guard " .. tostring(guard) .. ": walked up the stairs", string.format("z %.2f", pl:getZ()))
			check(not string.find(states, "KnockedDown", 1, true), "guard " .. tostring(guard) .. ": not knocked down going up", states)
			ISTimedActionQueue.add(ISWalkToTimedAction:new(pl, bottom))
			minZ, states = runQueue(1500)
			log("stairs down guard=" .. tostring(guard), "clamps", (M().clamps or 0) - c0, states)
			check(pl:getCurrentSquare() == bottom, "guard " .. tostring(guard) .. ": walked down the stairs", string.format("z %.2f", pl:getZ()))
			check(not string.find(states, "KnockedDown", 1, true), "guard " .. tostring(guard) .. ": not knocked down going down", states)
		end
		defaults()
	end
	if stairsOnly then return end
	local w, inside, outside = findWindow(b)
	if not check(w ~= nil, "a level-1 window over a drop") then return end
	log("window at", w:getSquare():getX(), w:getSquare():getY(), "north", tostring(w:getNorth()), "inside", inside:getX(), inside:getY())
	local function stand()
		clearQueue()
		placeAt(inside:getX() + 0.5, inside:getY() + 0.5, 1)
		pcall(function() w:setIsLocked(false) end)
		pcall(function() w:setPermaLocked(false) end)
		pcall(function() if not w:IsOpen() and not w:isSmashed() then w:ToggleWindow(pl) end end)
		waitTicks(10)
	end
	setOpt("AllowManualClimb", false)
	stand()
	ISTimedActionQueue.add(ISClimbThroughWindow:new(pl, w, 0))
	local minZ, states = runQueue(400)
	check(pl:getZ() > 0.99 and not string.find(states, "ClimbThroughWindow", 1, true), "window onto a drop refused (option off)", string.format("z %.2f %s", pl:getZ(), states))
	setOpt("AllowManualClimb", true)
	stand()
	ISTimedActionQueue.add(ISClimbThroughWindow:new(pl, w, 0))
	minZ, states = runQueue(600)
	log("window default now", relPos(pl), states)
	check(string.find(states, "ClimbThroughWindow", 1, true) ~= nil and pl:getZ() < 0.1, "window default: climbed out and fell", string.format("z %.2f %s", pl:getZ(), states))
	setOpt("AllowManualClimb", false)
	stand()
	pl:getInventory():AddItems("Base.SheetRope", 6)
	pl:getInventory():AddItems("Base.Nails", 10)
	local ok, err = pcall(function() return w:addSheetRope(pl, "SheetRope") end)
	log("window addSheetRope", ok, err, "have", tostring(w:haveSheetRope()))
	if check(w:haveSheetRope(), "sheet rope tied") then
		ISTimedActionQueue.add(ISClimbThroughWindow:new(pl, w, 0))
		minZ, states = runQueue(1500)
		log("window rope now", relPos(pl), states)
		check(string.find(states, "ClimbThroughWindow", 1, true) ~= nil, "rope window: climbed through", states)
		check(pl:getZ() < 0.1, "rope window: down at the ground", string.format("z %.2f %s", pl:getZ(), states))
		clearQueue()
		local okc = pcall(function() pl:climb() end)
		minZ, states = runQueue(1500)
		log("rope up", okc, "now", math.floor(pl:getX()), math.floor(pl:getY()), string.format("%.2f", pl:getZ()), states)
		check(pl:getZ() > 0.99, "rope: climbed back up", string.format("z %.2f %s", pl:getZ(), states))
		pcall(function() w:removeSheetRope(pl) end)
	end
	defaults()
	clearQueue()
end

local SCENARIOS = {
	{ "setup", scSetup },
	{ "control", scControl },
	{ "walkEast", scWalkEast },
	{ "runNorth", scRunNorth },
	{ "diagonal", scDiagonal },
	{ "sprintRailing", scSprintRailing },
	{ "groundVault", scGroundVault },
	{ "manualAllowed", scManualAllowed },
	{ "manualRefused", scManualRefused },
	{ "windowLogic", scWindowLogic },
	{ "stairsLogic", scStairsLogic },
	{ "ladder", scLadder },
	{ "collapse", scCollapse },
	{ "fenceRope", scFenceRope },
	{ "stairs", function() scHouse(true) end },
	{ "house", scHouse },
	{ "cleanup", cleanup },
}

local function onTick()
	local r = T.run
	if not r or r.finished then return end
	if r.idx < #SCENARIOS then protect() end
	if not r.co then
		r.idx = r.idx + 1
		local sc = SCENARIOS[r.idx]
		while sc and r.only and sc[1] ~= "setup" and sc[1] ~= "cleanup" and not string.find("," .. r.only .. ",", "," .. sc[1] .. ",", 1, true) do
			r.idx = r.idx + 1; sc = SCENARIOS[r.idx]
		end
		if not sc then
			T.scenario = "summary"
			log("SUMMARY pass=" .. T.pass .. " fail=" .. T.fail)
			r.finished = true
			return
		end
		T.scenario = sc[1]
		log("scenario", sc[1])
		r.co = coroutine.create(sc[2])
	end
	local ok, err = coroutine.resume(r.co)
	if not ok then check(false, "scenario error", err) end
	if not ok or coroutine.status(r.co) == "dead" then r.co = nil end
end
Events.OnTick.Add(onTick)

function T.start(only)
	T.pass, T.fail = 0, 0
	T.rail = nil
	T.run = { idx = 0, startedAt = getTimestamp(), only = only }
	if NoAccidentalFalls then NoAccidentalFalls.verbose = true end
	log("started", "protect: god invisible zombiesDontAttack ghost")
end

function T.poll()
	local r = T.run
	if not r then return end
	if r.finished then
		log("done pass=" .. T.pass .. " fail=" .. T.fail)
		return
	end
	if getTimestamp() - r.startedAt > 900 then
		check(false, "overall timeout")
		r.finished = true
		return
	end
	log("running", T.scenario, "pass=" .. T.pass, "fail=" .. T.fail)
	PZTest.step("wait 60")
	PZTest.step("lua NAFTest.poll()")
end

------------------------------------------------------------------ probe (debug): how a fall runs here
-- NAFTest.probe(guard): put the player half a square into the north air at level 1 and log the fall
T.probeRun = nil
function T.probe(guard)
	T.probeRun = { guard = guard, tick = 0 }
end
local function probeTick()
	local r = T.probeRun
	if not r then return end
	local pl = p()
	protect()
	if r.tick == 0 then
		setOpt("EdgeGuard", r.guard and true or false)
		local ax, ay = T.ox + 2.5, T.oy + 0.1
		pl:setX(ax); pl:setY(ay); pl:setZ(1)
		pl:setLastX(ax); pl:setLastY(ay); pl:setLastZ(1)
		pl:setNextX(ax); pl:setNextY(ay)
		pl:setCurrentSquareFromPosition()
		r.u0, r.c0, r.b0 = M().updates or 0, M().clamps or 0, M().edgeBlocks or 0
	elseif r.tick == 5 then
		-- step over the edge
		local ax, ay = T.ox + 2.5, T.oy - 0.3
		pl:setX(ax); pl:setY(ay); pl:setNextX(ax); pl:setNextY(ay)
	end
	r.tick = r.tick + 1
	if r.tick <= 12 or r.tick % 10 == 0 then
		local s = pl:getCurrentSquare()
		log(string.format("probe g=%s t=%d pos %.2f,%.2f,%.3f fallTime %.3f bFalling %s sq %s floor %s hAbove %.3f upd %d clamp %d roll %d state %s",
			tostring(r.guard), r.tick, pl:getX() - T.ox, pl:getY() - T.oy, pl:getZ(), pl:getFallTime(), tostring(pl:isbFalling()),
			s and (s:getX() - T.ox .. "," .. s:getY() - T.oy .. "," .. s:getZ()) or "nil", s and tostring(s:TreatAsSolidFloor()) or "-",
			pl:getHeightAboveFloor(), (M().updates or 0) - r.u0, (M().clamps or 0) - r.c0, (M().edgeBlocks or 0) - r.b0,
			tostring(pl:getCurrentState())))
	end
	if r.tick >= 120 then T.probeRun = nil; defaults(); log("probe end") end
end
Events.OnTick.Add(probeTick)

------------------------------------------------------------------ manual check (user plays)
-- NAFTest.manual(): builds the test platform, puts the character on it with the default options
-- and keeps the character protected (god mode, invisible, zombies leave it alone) until NAFTest.manualOff().
T.manualOn = T.manualOn or false
function T.manual()
	T.run = nil
	defaults()
	clearZombies()
	T.rail = nil
	build()
	local pl = p()
	local ax, ay = T.ox + 2.5, T.oy + 2.5
	pl:setX(ax); pl:setY(ay); pl:setZ(1)
	pl:setLastX(ax); pl:setLastY(ay); pl:setLastZ(1)
	pl:setNextX(ax); pl:setNextY(ay)
	pl:setCurrentSquareFromPosition()
	T.manualOn = true
	if NoAccidentalFalls then NoAccidentalFalls.verbose = false end
	log("manual: platform at", T.ox, T.oy, "level 1; east/north edges open, railing on the south edge, ground fence at", T.ox + 9, T.oy + 4)
end
function T.manualOff()
	T.manualOn = false
	unprotect()
	log("manual off")
end
local function manualTick()
	if not T.manualOn then return end
	protect()
	if ZombRand(60) == 0 then clearZombies() end
end
Events.OnTick.Add(manualTick)
