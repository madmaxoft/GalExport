
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





--- Sends the list of available export formats to the specified player
-- a_Player may be a cPlayer instance, a string containing the player's name or nil
-- If it is a string, the player is looked up and sent the message
-- If it is nil, the message is logged into server console
function SendAvailableFormats(a_Player)
	-- Check params:
	local IsIndirect = (a_Player == nil) or (type(a_Player) == "string")
	assert(IsIndirect or (tolua.type(a_Player) == "cPlayer"))
	
	-- Get a sorted list of export formats:
	local Formats = {}
	for k, v in pairs(g_Exporters) do
		table.insert(Formats, k)
	end
	table.sort(Formats)
	
	-- Send to the player:
	local msg = cCompositeChat("Available formats: " .. table.concat(Formats, ", "), mtInfo)
	if (IsIndirect) then
		SendPlayerMessage(a_Player, msg)
	else
		a_Player:SendMessage(msg)
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





--- Exports the specified group of areas in the specified format
-- The operation is asynchronous - it executes on the background while this function has already finished executing
-- a_PlayerName is the player whom the default callbacks notify of success or failure; nil means log into server console instead
-- Returns false on immediate failure, true if queueing succeeded
-- Success is notified via the optional a_SuccessCallback; if not provided, a message is sent to the player (or console if a_PlayerName is nil)
-- Failure is notified via the optional a_FailureCallback; if not provided, a message is sent to the player (or console if a_PlayerName is nil)
-- The callbacks have the same signatures as g_Exporters[].ExportGroup() success / failure callbacks
function QueueExportAreaGroup(a_GroupName, a_Format, a_PlayerName, a_SuccessCallback, a_FailureCallback)
	-- Check params:
	assert(type(a_GroupName) == "string")
	assert(type(a_Format) == "string")
	assert((a_PlayerName == nil) or (type(a_PlayerName) == "string"))
	assert((a_SuccessCallback == nil) or (type(a_SuccessCallback) == "function"))
	assert((a_FailureCallback == nil) or (type(a_FailureCallback) == "function"))
	
	-- Check if the format is supported:
	local Exporter = g_Exporters[a_Format]
	if not(Exporter) then
		SendPlayerMessage(a_PlayerName, cCompositeChat("Cannot export, there is no such format.", mtFailure))
		SendAvailableFormats(a_PlayerName)
		return false
	end
	
	-- Get the area ident for each area in the group:
	local Areas = g_DB:GetApprovedAreasInGroup(a_GroupName)
	if (not(Areas) or (Areas[1] == nil)) then
		SendPlayerMessage(a_PlayerName, cCompositeChat("Cannot export, there is no gallery area in the group.", mtFailure))
		return false
	end
	
	-- Export the areas:
	local function ReportSuccess()
		SendPlayerMessage(a_PlayerName, cCompositeChat("Group exported", mtInfo))
	end
	local function ReportFailure(a_Message)
		SendPlayerMessage(a_PlayerName, cCompositeChat("Cannot export group: " .. (a_Message or "<no details>"), mtFailure))
	end
	Exporter.ExportGroup(Areas, a_SuccessCallback or ReportSuccess, a_FailureCallback or ReportFailure)
	return true
end





--- Exports the specified groups of areas in the specified format
-- The operation is asynchronous - it executes on the background while this function has already finished executing
-- a_PlayerName is the player whom the default callbacks notify of success or failure; nil means log into server console instead
-- Returns false on immediate failure, true if queueing succeeded
-- Success is notified via the optional a_SuccessCallback; if not provided, a message is sent to the player (or console if a_PlayerName is nil)
-- Failure is notified via the optional a_FailureCallback; if not provided, a message is sent to the player (or console if a_PlayerName is nil)
-- The callbacks have the same signatures as g_Exporters[].ExportGroup() success / failure callbacks
function QueueExportAreaGroups(a_GroupNames, a_Format, a_PlayerName, a_SuccessCallback, a_FailureCallback)
	-- Check params:
	assert(type(a_GroupNames) == "table")
	assert(type(a_Format) == "string")
	assert((a_PlayerName == nil) or (type(a_PlayerName) == "string"))
	assert((a_SuccessCallback == nil) or (type(a_SuccessCallback) == "function"))
	assert((a_FailureCallback == nil) or (type(a_FailureCallback) == "function"))
	
	-- Provide a default success and failure callbacks:
	a_SuccessCallback = a_SuccessCallback or function()
		SendPlayerMessage(a_PlayerName, cCompositeChat("Groups exported", mtInfo))
	end
	a_FailureCallback = a_FailureCallback or function(a_Message)
		SendPlayerMessage(a_PlayerName, cCompositeChat("Cannot export groups: " .. (a_Message or "<no details>"), mtFailure))
	end

	-- If there are no groups, bail out early (consider this success):
	if (a_GroupNames[1] == nil) then
		a_SuccessCallback()
		return true
	end
	
	-- Check if the format is supported:
	local Exporter = g_Exporters[a_Format]
	if not(Exporter) then
		SendPlayerMessage(a_PlayerName, cCompositeChat("Cannot export, there is no such format.", mtFailure))
		SendAvailableFormats(a_PlayerName)
		return false
	end
	
	-- Create a callback that queues the next group successively:
	local CurrGroup = 1
	local SuccessCallback = function()
		-- Move to the next group to export:
		CurrGroup = CurrGroup + 1
		if (a_GroupNames[CurrGroup] == nil) then
			-- No more groups to export, report success and bail out:
			a_SuccessCallback()
			return
		else
			-- Queue the next group:
			QueueExportAreaGroup(a_GroupNames[CurrGroup], a_Format, a_PlayerName, SuccessCallback, a_FailureCallback)
		end
	end
	
	-- Queue the first group:
	return QueueExportAreaGroup(a_GroupNames[1], a_Format, a_PlayerName, SuccessCallback, a_FailureCallback)
end





--- Exports all the export groups of areas in the specified format
-- The operation is asynchronous - it executes on the background while this function has already finished executing
-- a_PlayerName is the player whom the default callbacks notify of success or failure; nil means log into server console instead
-- Returns false on immediate failure, true if queueing succeeded
-- Success is notified via the optional a_SuccessCallback; if not provided, a message is sent to the player (or console if a_PlayerName is nil)
-- Failure is notified via the optional a_FailureCallback; if not provided, a message is sent to the player (or console if a_PlayerName is nil)
-- The callbacks have the same signatures as g_Exporters[].ExportGroup() success / failure callbacks
function QueueExportAllGroups(a_Format, a_PlayerName, a_SuccessCallback, a_FailureCallback)
	-- Check params:
	assert(type(a_Format) == "string")
	assert((a_PlayerName == nil) or (type(a_PlayerName) == "string"))
	assert((a_SuccessCallback == nil) or (type(a_SuccessCallback) == "function"))
	assert((a_FailureCallback == nil) or (type(a_FailureCallback) == "function"))
	
	
	-- Provide a default failure callback:
	-- We might use it before queueing the export
	a_FailureCallback = a_FailureCallback or function(a_Message)
		SendPlayerMessage(a_PlayerName, cCompositeChat("Cannot export areas: " .. (a_Message or "<no details>"), mtFailure))
	end

	-- Get the group names from the DB:
	local GroupNames = g_DB:GetAllGroupNames()
	if (not(GroupNames) or (GroupNames[1] == nil)) then
		a_FailureCallback("There is no export group defined.")
		return false
	end
	
	-- Queue the export:
	return QueueExportAreaGroups(GroupNames, a_Format, a_PlayerName, SuccessCallback, a_FailureCallback)
end




