
-- Common.lua

-- Implements functions that are commonly used throughout the code





local s_DirectionToString =
{
	[BLOCK_FACE_XM] = "x-",
	[BLOCK_FACE_XP] = "x+",
	[BLOCK_FACE_YM] = "y-",
	[BLOCK_FACE_YP] = "y+",
	[BLOCK_FACE_ZM] = "z-",
	[BLOCK_FACE_ZP] = "z+",
}

--- Returns a string representation of the direction
-- Converts from numbers to strings, keeps strings as-is
function DirectionToString(a_Direction)
	if (tonumber(a_Direction)) then
		return s_DirectionToString[a_Direction]
	else
		return a_Direction
	end
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





--- Map of lowercased string to direction values, used when translating user input of connector direction
local s_DirectionStr =
{
	[tostring(BLOCK_FACE_XM)] = "x-",
	[tostring(BLOCK_FACE_XP)] = "x+",
	[tostring(BLOCK_FACE_YM)] = "y-",
	[tostring(BLOCK_FACE_YP)] = "y+",
	[tostring(BLOCK_FACE_ZM)] = "z-",
	[tostring(BLOCK_FACE_ZP)] = "z+",
	["x-"] = "x-",
	["x+"] = "x+",
	["y-"] = "y-",
	["y+"] = "y+",
	["z-"] = "z-",
	["z+"] = "z+",

	-- Rotational vertical connectors:
	["y-x-z-"] = "y-x-z-",
	["y-x-z+"] = "y-x-z+",
	["y-x+z-"] = "y-x+z-",
	["y-x+z+"] = "y-x+z+",
	["y+x-z-"] = "y+x-z-",
	["y+x-z+"] = "y+x-z+",
	["y+x+z-"] = "y+x+z-",
	["y+x+z+"] = "y+x+z+",

	-- Rotational vertical connectors, non-canon forms:
	["y-z-x-"] = "y-x-z-",
	["y-z+x-"] = "y-x-z+",
	["y-z-x+"] = "y-x+z-",
	["y-z+x+"] = "y-x+z+",
	["y+z-x-"] = "y+x-z-",
	["y+z+x-"] = "y+x-z+",
	["y+z-x+"] = "y+x+z-",
	["y+z+x+"] = "y+x+z+",
	["x-y-z-"] = "y-x-z-",
	["x-y-z+"] = "y-x-z+",
	["x+y-z-"] = "y-x+z-",
	["x+y-z+"] = "y-x+z+",
	["x-y+z-"] = "y+x-z-",
	["x-y+z+"] = "y+x-z+",
	["x+y+z-"] = "y+x+z-",
	["x+y+z+"] = "y+x+z+",
}




--- Returns the canon direction based on the user input
-- Returns nil if no match
function NormalizeDirection(a_DirectionStr)
	local key = string.lower(tostring(a_DirectionStr)):gsub("m", "-"):gsub("p", "+")  -- Lowercase, replace m/p with -/+
	return s_DirectionStr[key]
end





--- Returns the direction, represented as a string, based on the player's pitch and yaw
-- Uses only "y+" and "y-" for vertical directions, doesn't use the rotational "y+x+z+"
function GetDirectionFromPlayerRotation(a_PlayerPitch, a_PlayerYaw)
	-- Check params:
	local PlayerPitch = tonumber(a_PlayerPitch)
	local PlayerYaw = tonumber(a_PlayerYaw)
	assert(PlayerPitch ~= nil)
	assert(PlayerYaw ~= nil)

	-- Decide on the direction:
	if (PlayerPitch > 70) then
		return "y-"
	elseif (PlayerPitch < -70) then
		return "y+"
	else
		if ((PlayerYaw < -135) or (PlayerYaw >= 135)) then
			return "z-"
		elseif (PlayerYaw < -45) then
			return "x+"
		elseif (PlayerYaw < 45) then
			return "z+"
		else
			return "x-"
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





--- Parses the user's command input of "[<Distance>] [<Direction>]".
-- Distance defaults to 1, if not given.
-- Direction defaults to "me", if not given.
-- If direction evaluates to "me", the cPlayer object is used to provide the direction using the GetPitch()
-- and GetYaw() functions.
-- Returns the X, Y, and Z block differences for the direction, and the number of params consumed.
-- If the direction specifier is invalid, returns nil and error message.
-- Note that if Distance is not a number, it is parsed as Direction, which may yield confusion about the
-- error message.
function ParseDistanceDirection(a_Player, a_Split, a_BeginParam)
	-- Check params:
	assert(tolua.type(a_Player) == "cPlayer")
	assert(type(a_Split) == "table")
	assert(type(a_BeginParam) == "number")

	-- Decide which params are present:
	local NumParamsUsed = 0
	local Direction
	local Distance = tonumber(a_Split[a_BeginParam])
	if (Distance == nil) then
		-- The Distance param is not present, parse as direction:
		Distance = 1
		Direction = a_Split[a_BeginParam]
	else
		-- Distance has been given, direction is in the next arg
		NumParamsUsed = 1
		Direction = a_Split[a_BeginParam + 1]
	end
	if (Direction == nil) then
		-- The direction was not given, use "me":
		Direction = "me"
	else
		-- The direction was given, increment the param count:
		NumParamsUsed = NumParamsUsed + 1
	end
	Direction = string.lower(Direction)

	-- Get the player's look direction:
	local PlayerDirection
	local Pitch = a_Player:GetPitch()
	if (Pitch > 70) then
		PlayerDirection = "up"
	elseif (Pitch < -70) then
		PlayerDirection = "down"
	else
		local Yaw = math.floor((a_Player:GetYaw() + 225) / 90)
		if ((Yaw == 0) or (Yaw == 4)) then
			-- yaw between -180 and -135, or between +135 and +180
			PlayerDirection = "zm"
		elseif (Yaw == 1) then
			-- yaw between -135 and -45
			PlayerDirection = "xp"
		elseif (Yaw == 2) then
			-- yaw between -45 and +45
			PlayerDirection = "zp"
		else
			-- yaw between +45 and +135
			PlayerDirection = "xm"
		end
	end

	-- If the player specified "me" as the direction, use their look direction instead of the given direction:
	if ((Direction == "me") or (Direction == "self") or (Direction == "look")) then
		Direction = PlayerDirection
	end

	-- If the player specified "left" or "right", translate to cardinal direction based on PlayerDirection:
	if (Direction == "left") then
		if (PlayerDirection == "xm") then
			Direction = "zp"
		elseif (PlayerDirection == "xp") then
			Direction = "zm"
		elseif (PlayerDirection == "zm") then
			Direction = "xm"
		elseif (PlayerDirection == "zp") then
			Direction = "xp"
		end
	elseif (Direction == "right") then
		if (PlayerDirection == "xm") then
			Direction = "zm"
		elseif (PlayerDirection == "xp") then
			Direction = "zp"
		elseif (PlayerDirection == "zm") then
			Direction = "xp"
		elseif (PlayerDirection == "zp") then
			Direction = "xm"
		end
	end

	-- Based on Direction, decide what to return:
	if (Direction == "up") then
		return 0, Distance, 0, NumParamsUsed
	elseif (Direction == "down") then
		return 0, -Distance, 0, NumParamsUsed
	elseif ((Direction == "xm") or (Direction == "x-") or (Direction == "west") or (Direction == "w")) then
		return -Distance, 0, 0, NumParamsUsed
	elseif ((Direction == "xp") or (Direction == "x+") or (Direction == "east") or (Direction == "e")) then
		return Distance, 0, 0, NumParamsUsed
	elseif ((Direction == "zm") or (Direction == "z-") or (Direction == "north") or (Direction == "n")) then
		return 0, 0, -Distance, NumParamsUsed
	elseif ((Direction == "zp") or (Direction == "z+") or (Direction == "south") or (Direction == "s")) then
		return 0, 0, Distance, NumParamsUsed
	end

	-- The direction is not handled:
	return nil, "Unknown direction: " .. (Direction or "<unspecified>")
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

	SendPlayerMessage(a_PlayerName, cCompositeChat("Exporting group " .. a_GroupName, mtInfo))

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
	Exporter.ExportGroup(g_Config.ExportFolder, Areas, a_SuccessCallback or ReportSuccess, a_FailureCallback or ReportFailure)
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
	local function SuccessCallback()
		-- Move to the next group to export:
		CurrGroup = CurrGroup + 1
		if (a_GroupNames[CurrGroup] == nil) then
			-- No more groups to export, report success and bail out:
			a_SuccessCallback()
			return
		else
			-- Unload chunks, so that there aren't too many:
			cRoot:Get():ForEachWorld(
				function(a_CBWorld)
					a_CBWorld:QueueUnloadUnusedChunks()
				end
			)

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
	return QueueExportAreaGroups(GroupNames, a_Format, a_PlayerName, a_SuccessCallback, a_FailureCallback)
end




