
-- PlayerState.lua

-- Implements the cPlayerState class representing a complete state information for a single player
-- The state is remembered based on the player's EntityID (so that two players of the same name don't share state)
-- Use the GetPlayerState global function to retrieve a state for a player




--- The class used to store a complete state information for a single player
cPlayerState = {}





--- The dict-table of player states.
-- Each player has an entry in this dictionary, indexed by the player's EntityID.
local g_PlayerStates =
{
	--- Function called whenever the player enters a new gallery area
	-- Params: cPlayer, NewArea
	-- AutoActionEnter

	--- Function called whenever the player leaves a gallery area
	-- Params: cPlayer, OldArea
	-- AutoActionLeave

	--- The last Area where the player has been (according to UpdatePos())
	-- LastArea

	--- The last position of the player when the LastArea was evaluated (performance optimization in UpdatePos())
	-- LastAreaCheckPos
}





function cPlayerState:new(a_Player)
	local res = {}
	setmetatable(res, cPlayerState)
	self.__index = self

	-- Initialize the object members to their defaults:
	res.PlayerEntityID = a_Player:GetUniqueID()
	-- Intentionally use a far-away position so that the UpdatePos() updates everything for us:
	res.LastAreaCheckPos = a_Player:GetPosition() + Vector3d(10, 0, 0)
	res:UpdatePos(a_Player)


	return res
end






--- Called when the player's position has been updated
-- Checks if the current area has changed, if so, updates LastArea and calls AutoAction functions
function cPlayerState:UpdatePos(a_Player)
	-- Check params:
	assert(self ~= nil)
	assert(tolua.type(a_Player) == "cPlayer")

	local Pos = a_Player:GetPosition()
	if self.LastArea then
		-- The player has been in a specific area, check if they are still within:
		if (
			(Pos.x < self.LastArea.MinX) or (Pos.x > self.LastArea.MaxX) or  -- X coord outside the area
			(Pos.z < self.LastArea.MinZ) or (Pos.z > self.LastArea.MaxZ)     -- Z coord outside the area
		) then
			-- The player is outside the area, call the hook and update area:
			if (self.AutoActionLeave) then
				self.AutoActionLeave(a_Player, self.LastArea)
			end
			self.LastArea = g_DB:GetAreaByCoords(a_Player:GetWorld():GetName(), Pos.x, Pos.z)
			if (self.LastArea and self.AutoActionEnter) then
				self.AutoActionEnter(a_Player, self.LastArea)
			end
			self.LastAreaCheckPos = Pos
		end
	else
		-- The player hasn't been in any area
		-- In order to refrain from querying the DB too often, query only if the position has changed significantly:
		if ((self.LastAreaCheckPos - Pos):Length() > 2) then
			self.LastArea = g_DB:GetAreaByCoords(a_Player:GetWorld():GetName(), Pos.x, Pos.z)
			if (self.LastArea and self.AutoActionEnter) then
				self.AutoActionEnter(a_Player, self.LastArea)
			end
			self.LastAreaCheckPos = Pos
		end
	end
end





function GetPlayerState(a_Player)
	-- Check params:
	assert(tolua.type(a_Player) == "cPlayer")

	local res = g_PlayerStates[a_Player:GetUniqueID()]

	-- If there's no such state, create one:
	if not(res) then
		res = cPlayerState:new(a_Player)
		g_PlayerStates[a_Player:GetUniqueID()] = res
	end

	return res;
end





local function OnPlayerDestroyed(a_Player)
	-- Remove the player state from the global list:
	g_PlayerStates[a_Player:GetUniqueID()] = nil
	return false
end





local function OnPlayerMoving(a_Player)
	GetPlayerState(a_Player):UpdatePos(a_Player)
end





cPluginManager.AddHook(cPluginManager.HOOK_PLAYER_DESTROYED, OnPlayerDestroyed)
cPluginManager.AddHook(cPluginManager.HOOK_PLAYER_MOVING,    OnPlayerMoving)




