
-- Common.lua

-- Implements functions that are commonly used throughout the code





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




