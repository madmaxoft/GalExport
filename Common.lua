
-- Common.lua

-- Implements functions that are commonly used throughout the code





local s_DirectionToString =
{
	[BLOCK_FACE_XM] = "X-",
	[BLOCK_FACE_XP] = "X+",
	[BLOCK_FACE_YM] = "Y-",
	[BLOCK_FACE_YP] = "Y+",
	[BLOCK_FACE_ZM] = "Z-",
	[BLOCK_FACE_ZP] = "Z+",
}

--- Returns a string representation of the direction
function DirectionToString(a_Direction)
	return s_DirectionToString[tonumber(a_Direction)]
end





--- Returns an array-table containing the chunk coords for all chunks intersecting the specified rectangle
function GetChunksForRect(a_MinX, a_MinZ, a_MaxX, a_MaxZ)
	-- Check params:
	assert(tonumber(a_MinX) ~= nil)
	assert(tonumber(a_MinZ) ~= nil)
	assert(tonumber(a_MaxX) ~= nil)
	assert(tonumber(a_MaxZ) ~= nil)

	-- Calculate the chunk range needed:
	local MinChunkX = math.floor(a_MinX / 16)
	local MinChunkZ = math.floor(a_MinZ / 16)
	local MaxChunkX = math.floor((a_MaxX + 15) / 16)
	local MaxChunkZ = math.floor((a_MaxZ + 15) / 16)

	-- Make a list of the needed chunks:
	local Chunks = {}
	for x = MinChunkX, MaxChunkX do for z = MinChunkZ, MaxChunkZ do
		table.insert(Chunks, {x, z})
	end end
	
	return Chunks
end





--- Returns an array-table containing the chunk coords for all chunks intersecting the specified area's export rect
function GetChunksForAreaExport(a_AreaDef)
	return GetChunksForRect(a_AreaDef.ExportMinX, a_AreaDef.ExportMinZ, a_AreaDef.ExportMaxX, a_AreaDef.ExportMaxZ)
end





--- Returns the direction, represented as BLOCK_FACE_? constant, based on the player's pitch and yaw
function GetDirectionFromPlayerRotation(a_PlayerPitch, a_PlayerYaw)
	-- Check params:
	local PlayerPitch = tonumber(a_PlayerPitch)
	local PlayerYaw = tonumber(a_PlayerYaw)
	assert(PlayerPitch ~= nil)
	assert(PlayerYaw ~= nil)
	
	-- Decide on the direction:
	if (PlayerPitch > 70) then
		return BLOCK_FACE_YP
	elseif (PlayerPitch < -70) then
		return BLOCK_FACE_YM
	else
		if ((PlayerYaw < -135) or (PlayerYaw >= 135)) then
			return BLOCK_FACE_ZM
		elseif (PlayerYaw < -45) then
			return BLOCK_FACE_XP
		elseif (PlayerYaw < 45) then
			return BLOCK_FACE_ZP
		else
			return BLOCK_FACE_XM
		end
	end
end





--- Sends a message to the specified player.
-- Used for callbacks that no longer have the cPlayer object available
-- If a_PlayerName is nil, logs the message into the console log instead
-- a_Message may be a string or a cCompositeChat
function SendPlayerMessage(a_PlayerName, a_Message)
	-- Check params:
	assert((a_PlayerName == nil) or (type(a_PlayerName) == "string"))
	assert((type(a_Message) == "string") or (tolua.type(a_Message) == "cCompositeChat"))

	-- Log the message to console if no player specified:
	if (a_PlayerName == nil) then
		LOG(a_Message)
		return
	end
	
	-- Send the message to a player
	cRoot:Get():FindAndDoWithPlayer(a_PlayerName,
		function (a_Player)
			a_Player:SendMessage(a_Message)
		end
	)
end




