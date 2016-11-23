
-- GameCmdHandlers.lua

-- Implements the handlers for the in-game commands





--- A dictionary of metadata names that are understood by the system
-- Any metadata value can be set, but these are actually understood by the server
-- Maps the metadata name to true for easy checking
local g_UnderstoodMetadataNames =
{
	-- Whether the area is the starting area for the generator (1) or not (0):
	["IsStarting"] = true,

	-- Number of allowed CCW rotations, expressed as a bitmask-ed number
	-- E. g. 0 = no rotations allowed, 1 = 1 CCW rotation allowed, 5 = 1 or 3 CCW rotations allowed
	["AllowedRotations"] = true,

	-- The name of the merge strategy to use for the blockarea
	-- Must be a valid MergeStrategy name in the cBlockArea class, such as "msSpongePrint"
	["MergeStrategy"] = true,

	-- How to handle the space between the bottom of the piece and the terrain
	-- Possible values: "None", "RepeatBottomTillNonAir", "RepeatBottomTillSolid"
	["ExpandFloorStrategy"] = "None",

	-- The weight to use for this prefab, unless there's any other modifier active
	["DefaultWeight"] = true,

	-- String specifying the weighted chance for this area's occurrence per tree-depth, such as "1:100|2:50|3:40|4:1|5:0"
	-- Depth that isn't specified will get the DefaultWeight weight
	["DepthWeight"] = true,

	-- The weight to add to this piece's base per-depth chance if the previous piece is the same. Can be positive or negative.
	["AddWeightIfSame"] = true,

	-- The prefab should move Y-wise so that its first connector is on the ground level (TerrainHeightGen); 0 or 1
	-- Used for the houses in the village generator
	["MoveToGround"] = true,

	-- For starting pieces, specifies the vertical placement strategy and parameters
	-- For example, "Range|100|150"
	["VerticalStrategy"] = true,
}





--- Returns the player's position in integral blocks
local function GetPlayerPos(a_Player)
	return
		math.floor(a_Player:GetPosX()),
		math.floor(a_Player:GetPosY()),
		math.floor(a_Player:GetPosZ())
end





--- Returns the conn ident for the connector of the specified local index in the area
-- Returns nil and optional msg if no such connector exists or another (DB) error occurs
local function GetConnFromLocalIndex(a_AreaID, a_LocalIndex)
	-- Check the params:
	local AreaID = tonumber(a_AreaID)
	local LocalIndex = tonumber(a_LocalIndex)
	assert(AreaID ~= nil)
	assert(LocalIndex ~= nil)

	-- Retrieve all the connectors from the DB:
	local Connectors, Msg = g_DB:GetAreaConnectors(a_AreaID)
	if (Connectors == nil) then
		return nil, Msg
	end
	table.sort(Connectors,
		function (a_Conn1, a_Conn2)
			return (a_Conn1.ID < a_Conn2.ID)
		end
	)

	-- Return the connector by index:
	local res = Connectors[LocalIndex]
	if (res == nil) then
		return nil, "No such connector"
	end
	return res
end





--- Sends a list of the available metadata names to the player
local function ListUnderstoodMetadata(a_Player)
	-- Sort the metadata names:
	local Names = {}
	for k, v in pairs(g_UnderstoodMetadataNames) do
		table.insert(Names, k)
	end
	table.sort(Names)

	-- Send to player:
	a_Player:SendMessage(cCompositeChat("The following metadata names are understood: ", mtInfo))
	for _, name in ipairs(Names) do
		a_Player:SendMessage(cCompositeChat("  ", mtInfo):AddSuggestCommandPart(name, g_Config.CommandPrefix .. " set " .. name .. " ", "u@b"))
	end
end





--- Sends the list of all assigned metadata values for the current area to the player
-- If the player is not in a gallery area, nothing is output, not even an error message
-- Returns true if the metadata was sent, false and message if not
local function ListMetadataForArea(a_Player)
	-- Get the area ident:
	local BlockX, _, BlockZ = GetPlayerPos(a_Player)
	local Area = g_DB:GetAreaByCoords(a_Player:GetWorld():GetName(), BlockX, BlockZ)
	if not(Area) then
		-- No gallery area
		return false, "There's no gallery area here."
	end

	-- Get the metadata values (without the defaults):
	local MetaValues, Msg = g_DB:GetMetadataForArea(Area.ID, false)
	if not(MetaValues) then
		return false, Msg
	end

	-- Convert the dict into an array, so that it can be counted and sorted:
	local OutValues = {}
	for k, v in pairs(MetaValues) do
		table.insert(OutValues, k .. ": \"" .. v .. "\"")
	end

	-- Report the metadata count:
	local Count = #OutValues
	if (Count == 0) then
		a_Player:SendMessage(cCompositeChat("There are no metadata defined for this area.", mtInfo))
		return true
	elseif (Count == 1) then
		a_Player:SendMessage(cCompositeChat("There is one metadata value for this area:", mtInfo))
	else
		a_Player:SendMessage(cCompositeChat("There are " .. #OutValues .. " metadata values for this area:", mtInfo))
	end

	-- List all the values:
	table.sort(OutValues)
	for _, v in ipairs(OutValues) do
		a_Player:SendMessage(cCompositeChat("  " .. v, mtInfo))
	end
	return true
end





function HandleCmdApprove(a_Split, a_Player)
	-- Check the params:
	if (a_Split[3] == nil) then
		a_Player:SendMessage(cCompositeChat("Usage: ", mtFailure)
			:AddSuggestCommandPart(g_Config.CommandPrefix .. " approve ", g_Config.CommandPrefix .. " approve ")
			:AddTextPart("GroupName [AreaName]", "@2")
		)
		return true
	end
	local GroupName = a_Split[3]
	local AreaName = a_Split[4]

	-- Get the area ident:
	local BlockX, _, BlockZ = GetPlayerPos(a_Player)
	local Area = g_DB:GetAreaByCoords(a_Player:GetWorld():GetName(), BlockX, BlockZ)
	if not(Area) then
		a_Player:SendMessage(cCompositeChat("Cannot approve, there is no gallery area here.", mtFailure))
		return true
	end

	-- Get the WE selection (will be used as the export bounds):
	local SelCuboid = cCuboid()
	local IsSuccess = cPluginManager:CallPlugin("WorldEdit", "GetPlayerCuboidSelection", a_Player, SelCuboid)
	if not(IsSuccess) then
		a_Player:SendMessage(cCompositeChat("Cannot approve, WorldEdit not installed or has no cuboid selection.", mtFailure))
		return true
	end
	SelCuboid:Sort()

	-- Check if the selection is all outside:
	local AreaCuboid = cCuboid(Area.MinX, 0, Area.MinZ, Area.MaxX - 1, 255, Area.MaxZ - 1)
	if not(AreaCuboid:DoesIntersect(SelCuboid)) then
		a_Player:SendMessage(cCompositeChat("Cannot approve, your WE selection is not in this area. You need to select the export-bounds.", mtFailure))
		return true
	end

	-- Clamp the selection cuboid to the area, send back to WE:
	SelCuboid:ClampX(Area.MinX, Area.MaxX - 1)
	SelCuboid:ClampZ(Area.MinZ, Area.MaxZ - 1)
	cPluginManager:CallPlugin("WorldEdit", "SetPlayerCuboidSelection", a_Player, SelCuboid)

	-- Write the approval in the DB:
	local ret2, ret3, ret4
	IsSuccess, ret2, ret3, ret4 = g_DB:ApproveArea(Area.ID, a_Player:GetName(), GroupName, SelCuboid, AreaName)
	if (IsSuccess == nil) then
		a_Player:SendMessage(cCompositeChat("Cannot approve, " .. (ret2 or "DB failure"), mtFailure))
		return true
	elseif (IsSuccess == false) then
		ret2 = ret2 or "<unknown>"
		ret3 = ret3 or "<unknown>"
		ret4 = ret4 or "<unknown>"
		a_Player:SendMessage(cCompositeChat("Cannot approve, the area has been already approved by " .. ret2 .. " on " .. ret3 .. " in group " .. ret4, mtFailure))
		return true
	end

	-- If configured to, lock the area after approval:
	if (g_Config.LockApproved) then
		local IsSuccess, ErrorCode, Msg = cPluginManager:CallPlugin("Gallery", "LockAreaByID", Area.ID, a_Player:GetName())
		if (not(IsSuccess) and (ErrorCode ~= "AlreadyLocked")) then
			-- Notify the player but keep going:
			a_Player:SendMessage(cCompositeChat("Cannot lock approved area: " .. (Msg or "<Unknown error (" .. (ErrorCode or "<unknown code>") .. ")>"), mtFailure))
		end
	end

	a_Player:SendMessage(cCompositeChat("Area successfully approved.", mtInformation))
	return true
end





function HandleCmdAutoSelect(a_Split, a_Player)
	-- /ge autoselect <what>

	-- Set the AutoActionEnter in player state, based on the What param:
	local What = string.lower(a_Split[3] or "")
	if ((What == "bb") or (What == "bbox") or (What == "boundingbox")) then
		-- Auto-select boundingboxes:
		GetPlayerState(a_Player).AutoActionEnter = function(a_CBPlayer, a_Area)
			if (tonumber(a_Area.IsApproved) ~= 1) then
				-- Area not approved, no selection change
				return
			end
			-- Select the bounding-box:
			local SelCuboid = cCuboid(
				a_Area.ExportMinX, a_Area.ExportMinY, a_Area.ExportMinZ,
				a_Area.ExportMaxX, a_Area.ExportMaxY, a_Area.ExportMaxZ
			)
			cPluginManager:CallPlugin("WorldEdit", "SetPlayerCuboidSelection", a_CBPlayer, SelCuboid)
		end
		a_Player:SendMessage(cCompositeChat("BoundingBoxes will be selected automatically", mtInfo))
		return true
	elseif ((What == "hb") or (What == "hbox") or (What == "hitbox")) then
		-- Auto-select hitboxes:
		GetPlayerState(a_Player).AutoActionEnter = function(a_CBPlayer, a_Area)
			if (tonumber(a_Area.IsApproved) ~= 1) then
				-- Area not approved, no selection change
				return
			end
			-- Select the hitbox:
			local SelCuboid = cCuboid(
				a_Area.HitboxMinX or a_Area.ExportMinX, a_Area.HitboxMinY or a_Area.ExportMinY, a_Area.HitboxMinZ or a_Area.ExportMinZ,
				a_Area.HitboxMaxX or a_Area.ExportMaxX, a_Area.HitboxMaxY or a_Area.ExportMaxY, a_Area.HitboxMaxZ or a_Area.ExportMaxZ
			)
			cPluginManager:CallPlugin("WorldEdit", "SetPlayerCuboidSelection", a_CBPlayer, SelCuboid)
		end
		a_Player:SendMessage(cCompositeChat("Hitboxes will be selected automatically", mtInfo))
		return true
	elseif ((What == "") or (What == "no") or (What == "none") or (What == "nothing")) then
		-- Turn auto-select off:
		GetPlayerState(a_Player).AutoActionEnter = nil
		a_Player:SendMessage(cCompositeChat("Auto-select turned off", mtInfo))
		return true
	end
	return true
end





function HandleCmdBboxChange(a_Split, a_Player)
	-- /ge bbox change

	-- Get the area ident:
	local BlockX, _, BlockZ = GetPlayerPos(a_Player)
	local Area = g_DB:GetAreaByCoords(a_Player:GetWorld():GetName(), BlockX, BlockZ)
	if not(Area) then
		a_Player:SendMessage(cCompositeChat("Cannot change boundingbox, there is no gallery area here.", mtFailure))
		return true
	end

	-- Get the selection from WE:
	local SelCuboid = cCuboid()
	local IsSuccess = cPluginManager:CallPlugin("WorldEdit", "GetPlayerCuboidSelection", a_Player, SelCuboid)
	if not(IsSuccess) then
		a_Player:SendMessage(cCompositeChat("Cannot get WorldEdit selection", mtFailure))
		return true
	end
	SelCuboid:Sort()

	-- Clamp the selection to the area:
	SelCuboid:ClampX(Area.StartX, Area.EndX)
	SelCuboid:ClampZ(Area.StartZ, Area.EndZ)

	-- Set the selection back to area in DB:
	local Msg
	IsSuccess, Msg = g_DB:UpdateAreaBBox(Area.ID,
		SelCuboid.p1.x, SelCuboid.p1.y, SelCuboid.p1.z,
		SelCuboid.p2.x, SelCuboid.p2.y, SelCuboid.p2.z
	)

	-- Send success report:
	if (IsSuccess) then
		a_Player:SendMessage(cCompositeChat("Boundingbox changed", mtInformation))
	else
		a_Player:SendMessage(cCompositeChat("Cannot change boundingbox: " .. Msg, mtFailure))
	end
	return true
end





function HandleCmdBboxShow(a_Split, a_Player)
	-- /ge bbox show

	-- Get the area ident:
	local BlockX, _, BlockZ = GetPlayerPos(a_Player)
	local Area = g_DB:GetAreaByCoords(a_Player:GetWorld():GetName(), BlockX, BlockZ)
	if not(Area) then
		a_Player:SendMessage(cCompositeChat("Cannot show boundingbox, there is no gallery area here.", mtFailure))
		return true
	end

	-- Check if the area is approved:
	if (tonumber(Area.IsApproved) ~= 1) then
		a_Player:SendMessage(cCompositeChat("Cannot show boundingbox, this area is not approved.", mtFailure))
		return true
	end

	-- Send the selection to WE:
	local SelCuboid = cCuboid(
		Area.ExportMinX, Area.ExportMinY, Area.ExportMinZ,
		Area.ExportMaxX, Area.ExportMaxY, Area.ExportMaxZ
	)
	local IsSuccess = cPluginManager:CallPlugin("WorldEdit", "SetPlayerCuboidSelection", a_Player, SelCuboid)
	if not(IsSuccess) then
		a_Player:SendMessage(cCompositeChat("Cannot set WorldEdit selection to the boundingbox", mtFailure))
	else
		a_Player:SendMessage(cCompositeChat("WorldEdit selection set to the boundingbox", mtInformation))
	end
	return true
end





function HandleCmdHboxChange(a_Split, a_Player)
	-- /ge hbox change

	-- Get the area ident:
	local BlockX, _, BlockZ = GetPlayerPos(a_Player)
	local Area = g_DB:GetAreaByCoords(a_Player:GetWorld():GetName(), BlockX, BlockZ)
	if not(Area) then
		a_Player:SendMessage(cCompositeChat("Cannot change hitbox, there is no gallery area here.", mtFailure))
		return true
	end

	-- Get the selection from WE:
	local SelCuboid = cCuboid()
	local IsSuccess = cPluginManager:CallPlugin("WorldEdit", "GetPlayerCuboidSelection", a_Player, SelCuboid)
	if not(IsSuccess) then
		a_Player:SendMessage(cCompositeChat("Cannot get WorldEdit selection", mtFailure))
		return true
	end
	SelCuboid:Sort()

	-- Set the selection back to area in DB:
	local Msg
	IsSuccess, Msg = g_DB:UpdateAreaHBox(Area.ID,
		SelCuboid.p1.x, SelCuboid.p1.y, SelCuboid.p1.z,
		SelCuboid.p2.x, SelCuboid.p2.y, SelCuboid.p2.z
	)

	-- Send success report:
	if (IsSuccess) then
		a_Player:SendMessage(cCompositeChat("Hitbox changed", mtInformation))
	else
		a_Player:SendMessage(cCompositeChat("Cannot change hitbox: " .. Msg, mtFailure))
	end
	return true
end





function HandleCmdHboxShow(a_Split, a_Player)
	-- /ge hbox show

	-- Get the area ident:
	local BlockX, _, BlockZ = GetPlayerPos(a_Player)
	local Area = g_DB:GetAreaByCoords(a_Player:GetWorld():GetName(), BlockX, BlockZ)
	if not(Area) then
		a_Player:SendMessage(cCompositeChat("Cannot show hitbox, there is no gallery area here.", mtFailure))
		return true
	end

	-- Check if the area is approved:
	if (tonumber(Area.IsApproved) ~= 1) then
		a_Player:SendMessage(cCompositeChat("Cannot show hitbox, this area is not approved.", mtFailure))
		return true
	end

	-- Send the selection to WE:
	local SelCuboid = cCuboid(
		Area.HitboxMinX or Area.ExportMinX, Area.HitboxMinY or Area.ExportMinY, Area.HitboxMinZ or Area.ExportMinZ,
		Area.HitboxMaxX or Area.ExportMaxX, Area.HitboxMaxY or Area.ExportMaxY, Area.HitboxMaxZ or Area.ExportMaxZ
	)
	local IsSuccess = cPluginManager:CallPlugin("WorldEdit", "SetPlayerCuboidSelection", a_Player, SelCuboid)
	if not(IsSuccess) then
		a_Player:SendMessage(cCompositeChat("Cannot set WorldEdit selection to the hitbox", mtFailure))
	else
		a_Player:SendMessage(cCompositeChat("WorldEdit selection set to the hitbox", mtInformation))
	end
	return true
end





function HandleCmdConnAdd(a_Split, a_Player)
	-- /ge conn add <type>

	-- Check the params:
	local Type = tonumber(a_Split[4])
	if (Type == nil) then
		a_Player:SendMessage(cCompositeChat("Usage: ", mtFailure)
			:AddSuggestCommandPart(g_Config.CommandPrefix .. " conn add ", g_Config.CommandPrefix .. " conn add ")
			:AddTextPart("Type", "@2")
		)
		return true
	end

	-- Get the area ident:
	local BlockX, BlockY, BlockZ = GetPlayerPos(a_Player)
	local Area = g_DB:GetAreaByCoords(a_Player:GetWorld():GetName(), BlockX, BlockZ)
	if not(Area) then
		a_Player:SendMessage(cCompositeChat("Cannot add connector, there is no gallery area here.", mtFailure))
		return true
	end

	-- Calc the connector's direction:
	local Direction = GetDirectionFromPlayerRotation(a_Player:GetPitch(), a_Player:GetYaw())

	-- Add the connector:
	local Conn, Msg = g_DB:AddConnector(Area.ID, BlockX, BlockY, BlockZ, Direction, Type)
	if not(Conn) then
		a_Player:SendMessage(cCompositeChat("Cannot add connector: " .. (Msg or "<no message>"), mtFailure))
		return true
	end

	a_Player:SendMessage(cCompositeChat("Connector added, ID " .. Conn.ID, mtInfo))
	return true
end





function HandleCmdConnDel(a_Split, a_Player)
	-- /ge conn del <ID>

	-- Check the params:
	local ConnID = tonumber(a_Split[4])
	if (ConnID == nil) then
		a_Player:SendMessage(cCompositeChat("Usage: ", mtFailure)
			:AddSuggestCommandPart(g_Config.CommandPrefix .. " conn goto ", g_Config.CommandPrefix .. " conn goto ")
			:AddTextPart("LocalIndex", "@2")
		)
		return true
	end

	-- Get the area ident:
	local BlockX, BlockY, BlockZ = GetPlayerPos(a_Player)
	local Area = g_DB:GetAreaByCoords(a_Player:GetWorld():GetName(), BlockX, BlockZ)
	if not(Area) then
		a_Player:SendMessage(cCompositeChat("Cannot delete the connector, there is no gallery area here.", mtFailure))
		return true
	end

	-- Check that the connector exists and is in the same area:
	-- We won't allow deleting connectors in other areas to avoid deletion-by-accident of a different connector
	-- because the deletion usually will be done from the list and the list won't update when moving to another area.
	local Conn = g_DB:GetConnectorByID(ConnID)
	if (Conn == nil) then
		a_Player:SendMessage(cCompositeChat("Cannot delete connector, there is no such connector.", mtFailure))
		return true
	end
	if (tonumber(Conn.AreaID) ~= tonumber(Area.ID)) then
		a_Player:SendMessage(cCompositeChat("This connector is in a different area, deleting is disallowed for security reasons.", mtFailure))
		return true
	end

	-- Remove the connector from the DB:
	local IsSuccess, Msg = g_DB:DeleteConnector(ConnID)
	if not(IsSuccess) then
		a_Player:SendMessage(cCompositeChat("Cannot delete connector: " .. (Msg or "<no details>"), mtFailure))
		return true
	end

	a_Player:SendMessage(cCompositeChat("Connector deleted.", mtInfo))
	return true
end





function HandleCmdConnGoto(a_Split, a_Player)
	-- /ge conn goto <ID>

	-- Check the params:
	local ConnID = tonumber(a_Split[4])
	if (ConnID == nil) then
		a_Player:SendMessage(cCompositeChat("Usage: ", mtFailure)
			:AddSuggestCommandPart(g_Config.CommandPrefix .. " conn goto ", g_Config.CommandPrefix .. " conn goto ")
			:AddTextPart("LocalIndex", "@2")
		)
		return true
	end

	-- Get the connector ident:
	local Conn, Msg = g_DB:GetConnectorByID(ConnID)
	if (Conn == nil) then
		a_Player:SendMessage(cCompositeChat("Cannot go to connector, there is no such connector. " .. (Msg or ""), mtFailure))
		return true
	end

	-- Teleport the player:
	local Yaw = 0
	local Pitch = 0
	local Direction = tonumber(Conn.Direction)
	if (Direction == BLOCK_FACE_YP) then
		Pitch = -90
	elseif (Direction == BLOCK_FACE_YM) then
		Pitch = 90
	elseif (Direction == BLOCK_FACE_XM) then
		Yaw = 90
	elseif (Direction == BLOCK_FACE_XP) then
		Yaw = -90
	elseif (Direction == BLOCK_FACE_ZM) then
		Yaw = -180
	elseif (Direction == BLOCK_FACE_ZP) then
		Yaw = 0
	end
	a_Player:TeleportToCoords(Conn.X + 0.5, Conn.Y, Conn.Z + 0.5)
	a_Player:SendRotation(Yaw, Pitch)
	return true
end





function HandleCmdConnList(a_Split, a_Player)
	-- /ge conn list

	-- Get the area ident:
	local BlockX, BlockY, BlockZ = GetPlayerPos(a_Player)
	local Area = g_DB:GetAreaByCoords(a_Player:GetWorld():GetName(), BlockX, BlockZ)
	if not(Area) then
		a_Player:SendMessage(cCompositeChat("Cannot go to connector, there is no gallery area here.", mtFailure))
		return true
	end

	-- Get all the connectors for this area:
	local Connectors = g_DB:GetAreaConnectors(Area.ID)
	if ((Connectors == nil) or (Connectors[1] == nil)) then
		a_Player:SendMessage(cCompositeChat("There are no connectors for this area.", mtInfo))
		return true
	end
	table.sort(Connectors,
		function (a_Conn1, a_Conn2)
			return (a_Conn1.ID < a_Conn2.ID)
		end
	)

	-- List the connectors, together with mgmt links:
	local MinX = Area.ExportMinX or 0
	local MinY = Area.ExportMinY or 0
	local MinZ = Area.ExportMinZ or 0
	a_Player:SendMessage(cCompositeChat("These connectors have been defined for this area:", mtInfo))
	for idx, conn in ipairs(Connectors) do
		a_Player:SendMessage(cCompositeChat(
			string.format(
				"  %d: ID %d, type %d, {%d, %d, %d}, dir %s (",
				idx, conn.ID, conn.TypeNum, conn.X - MinX, conn.Y - MinY, conn.Z - MinZ,
				(DirectionToString(conn.Direction) or "<unknown>")
			), mtInfo)
			:AddRunCommandPart("goto", g_Config.CommandPrefix .. " conn goto " .. conn.ID, "@bu")
			:AddTextPart(", ")
			:AddSuggestCommandPart("del", g_Config.CommandPrefix .. " conn del " .. conn.ID, "@bu")
			:AddTextPart(", ")
			:AddSuggestCommandPart("type", g_Config.CommandPrefix .. " conn retype " .. conn.ID .. " ", "@bu")
			:AddTextPart(", ")
			:AddSuggestCommandPart("pos", g_Config.CommandPrefix .. " conn repos " .. conn.ID, "@bu")
			:AddTextPart(", ")
			:AddSuggestCommandPart("shift", g_Config.CommandPrefix .. " conn shift " .. conn.ID .. " ", "@bu")
			:AddTextPart(")")
		)
	end

	return true
end





function HandleCmdConnReposition(a_Split, a_Player)
	-- /ge conn reposition <ConnID>

	-- Check params:
	local ConnID = tonumber(a_Split[4])
	if not(ConnID) then
		a_Player:SendMessage(cCompositeChat("Usage: ", mtFailure)
			:AddSuggestCommandPart(g_Config.CommandPrefix .. " conn reposition ", g_Config.CommandPrefix .. " conn reposition ")
			:AddTextPart("<ConnectorID>", "@2")
		)
		return true
	end

	-- Check that the connector exists:
	local Connector = g_DB:GetConnectorByID(ConnID)
	if not(Connector) then
		a_Player:SendMessage(cCompositeChat("There's no connector with ID " .. ConnID, mtFailure))
		return true
	end

	-- Check that the connector is in the current area:
	local BlockX, BlockY, BlockZ = GetPlayerPos(a_Player)
	local Area = g_DB:GetAreaByCoords(a_Player:GetWorld():GetName(), BlockX, BlockZ)
	if (not(Area) or (Area.ID ~= Connector.AreaID)) then
		a_Player:SendMessage(cCompositeChat("The connector is not in the current area, the operation has been disabled for security reasons", mtFailure))
		return true
	end

	-- Change the connector position in the DB:
	local Direction = GetDirectionFromPlayerRotation(a_Player:GetPitch(), a_Player:GetYaw())
	local IsSuccess, Msg = g_DB:ChangeConnectorPos(ConnID, BlockX, BlockY, BlockZ, Direction)
	if not(IsSuccess) then
		a_Player:SendMessage(cCompositeChat("Cannot change connector " .. ConnID .. "'s position: " .. (Msg or "<no details>"), mtFailure))
		return true
	end

	-- Send success notification:
	a_Player:SendMessage(cCompositeChat("Connector " .. ConnID .. "'s position has been changed to your position", mtInfo))
	return true
end





function HandleCmdConnRetype(a_Split, a_Player)
	-- /ge conn retype <ConnID> <NewType>

	-- Check params:
	local ConnID = tonumber(a_Split[4])
	local NewType = tonumber(a_Split[5])
	if (not(ConnID) or not(NewType)) then
		a_Player:SendMessage(cCompositeChat("Usage: ", mtFailure)
			:AddSuggestCommandPart(g_Config.CommandPrefix .. " conn retype ", g_Config.CommandPrefix .. " conn retype ")
			:AddTextPart("<ConnectorID> <NewType>", "@2")
		)
		return true
	end

	-- Check that the connector exists:
	local Connector = g_DB:GetConnectorByID(ConnID)
	if not(Connector) then
		a_Player:SendMessage(cCompositeChat("There's no connector with ID " .. ConnID, mtFailure))
		return true
	end

	-- Check that the connector is in the current area:
	local BlockX, BlockY, BlockZ = GetPlayerPos(a_Player)
	local Area = g_DB:GetAreaByCoords(a_Player:GetWorld():GetName(), BlockX, BlockZ)
	if (not(Area) or (Area.ID ~= Connector.AreaID)) then
		a_Player:SendMessage(cCompositeChat("The connector is not in the current area, the operation has been disabled for security reasons", mtFailure))
		return true
	end

	-- Change the connector type in the DB:
	local IsSuccess, Msg = g_DB:ChangeConnectorType(ConnID, NewType)
	if not(IsSuccess) then
		a_Player:SendMessage(cCompositeChat("Cannot change connector " .. ConnID .. "'s type: " .. (Msg or "<no details>"), mtFailure))
		return true
	end

	-- Send success notification:
	a_Player:SendMessage(cCompositeChat("Connector " .. ConnID .. "'s type has been changed to " .. NewType, mtInfo))
	return true
end





function HandleCmdConnShift(a_Split, a_Player)
	-- /ge conn shift <ConnID> [<Distance>] [<Direction>]

	-- Check params:
	local ConnID = tonumber(a_Split[4])
	if not(ConnID) then
		a_Player:SendMessage(cCompositeChat("Usage: ", mtFailure)
			:AddSuggestCommandPart(g_Config.CommandPrefix .. " conn shift ", g_Config.CommandPrefix .. " conn shift ")
			:AddTextPart("<ConnectorID> [<Distance>] [<Direction>]", "@2")
		)
		return true
	end

	-- Translate distance + Direction into coord differences:
	local DiffX, DiffY, DiffZ = ParseDistanceDirection(a_Player, a_Split, 5)
	if not(DiffX) then
		-- An error occurred while parsing, the detailed message is in DiffY
		a_Player:SendMessage(cCompositeChat("Cannot parse shift command: " .. (DiffY or "<no details>"), mtFailure))
		return true
	end

	-- Check that the connector exists:
	local Connector = g_DB:GetConnectorByID(ConnID)
	if not(Connector) then
		a_Player:SendMessage(cCompositeChat("There's no connector with ID " .. ConnID, mtFailure))
		return true
	end

	-- Check that the connector is in the current area:
	local BlockX, BlockY, BlockZ = GetPlayerPos(a_Player)
	local Area = g_DB:GetAreaByCoords(a_Player:GetWorld():GetName(), BlockX, BlockZ)
	if (not(Area) or (Area.ID ~= Connector.AreaID)) then
		a_Player:SendMessage(cCompositeChat("The connector is not in the current area, the operation has been disabled for security reasons", mtFailure))
		return true
	end

	-- Shift the connector in the DB:
	local IsSuccess, Msg = g_DB:SetConnectorPos(ConnID, Connector.X + DiffX, Connector.Y + DiffY, Connector.Z + DiffZ)
	if not(IsSuccess) then
		a_Player:SendMessage(cCompositeChat("Cannot shift connector " .. ConnID .. ": " .. (Msg or "<no details>"), mtFailure))
		return true
	end

	-- Send success nofitication:
	a_Player:SendMessage(
		cCompositeChat(string.format(
			"Connector %d shifted by {%d, %d, %d}.",
			ConnID, DiffX, DiffY, DiffZ
		), mtInfo)
	)
	return true
end





function HandleCmdDisapprove(a_Split, a_Player)
	-- /ge disapprove [<AreaID>]

	-- Check params:
	local AreaID = tonumber(a_Split[3])
	local Area
	if (AreaID == nil) then
		if (a_Split[3] ~= nil) then
			-- An ID was given that couldn't be parsed:
			a_Player:SendMessage(cCompositeChat("Usage: ", mtFailure)
				:AddSuggestCommandPart(g_Config.CommandPrefix .. " disapprove ", g_Config.CommandPrefix .. " disapprove ")
				:AddTextPart("[<AreaID>]", "@2")
			)
			return true
		end
		-- No ID was given, use current area:
		local BlockX, _, BlockZ = GetPlayerPos(a_Player)
		Area = g_DB:GetAreaByCoords(a_Player:GetWorld():GetName(), BlockX, BlockZ)
		if (Area == nil) then
			a_Player:SendMessage(cCompositeChat("Cannot disapprove, there is no gallery area here.", mtFailure))
			return true
		end
	else
		-- Load the area ident by AreaID:
		Area = g_DB:GetAreaByID(AreaID)
	end

	-- If the area is not approved, bail out:
	if (tonumber(Area.IsApproved) ~= 1) then
		a_Player:SendMessage(cCompositeChat("The area is not approved, nothing to do.", mtInfo))
		return true
	end

	-- Disapprove the area in the DB:
	local IsSuccess, Msg = g_DB:DisapproveArea(Area.ID)
	if not(IsSuccess) then
		a_Player:SendMessage(cCompositeChat("Cannot disapprove, DB failure: " .. (Msg or "<no details>"), mtFailure))
		return true
	end

	-- If configured to lock areas upon approval, unlock the area:
	if (g_Config.LockApproved) then
		local IsSuccess, ErrorCode, Msg = cPluginManager:CallPlugin("Gallery", "UnlockAreaByID", Area.ID, a_Player:GetName())
		if (not(IsSuccess) and (ErrorCode ~= "NotLocked")) then
			a_Player:SendMessage(cCompositeChat("Cannot unlock area: " .. (Msg or "<Unknown error (" .. (ErrorCode or "<unknown code>") .. ")>"), mtFailure))
		end
	end

	-- Notify the player:
	a_Player:SendMessage(cCompositeChat("Area disapproved. (", mtInfo)
		:AddSuggestCommandPart("re-approve", g_Config.CommandPrefix .. " approve " .. Area.ExportGroupName .. " " .. Area.ExportName, "@bu")
		:AddTextPart(")")
	)
	return true
end





function HandleCmdExportAll(a_Split, a_Player)
	-- /ge export all <format>

	-- Check the params:
	if (a_Split[4] == nil) then
		a_Player:SendMessage(cCompositeChat("Usage: ", mtFailure)
			:AddSuggestCommandPart(g_Config.CommandPrefix .. " export this ", g_Config.CommandPrefix .. " export this ")
			:AddTextPart("Format", "@2")
		)
		SendAvailableFormats(a_Player)
		return true
	end
	local Format = a_Split[4]

	-- Queue the export. The default callbacks are fine for us (a message to the player)
	a_Player:SendMessage(cCompositeChat("Exporting all areas...", mtInfo))
	QueueExportAllGroups(Format, a_Player:GetName())
end





function HandleCmdExportGroup(a_Split, a_Player)
	-- /ge export group <groupname> <format>
	-- Check the params:
	if ((a_Split[4] == nil) or (a_Split[5] == nil)) then
		a_Player:SendMessage(cCompositeChat("Usage: ", mtFailure)
			:AddSuggestCommandPart(g_Config.CommandPrefix .. " export group ", g_Config.CommandPrefix .. " export group ")
			:AddTextPart("GroupName Format", "@2")
		)
		SendAvailableFormats(a_Player)
		return true
	end
	local GroupName = a_Split[4]
	local Format = a_Split[5]

	-- Export (using code common with the console handler):
	a_Player:SendMessage(cCompositeChat("Exporting group...", mtInfo))
	QueueExportAreaGroup(GroupName, Format, a_Player:GetName())

	return true
end





function HandleCmdExportThis(a_Split, a_Player)
	-- /ge export this <format>
	-- Check the params:
	if (a_Split[4] == nil) then
		a_Player:SendMessage(cCompositeChat("Usage: ", mtFailure)
			:AddSuggestCommandPart(g_Config.CommandPrefix .. " export this ", g_Config.CommandPrefix .. " export this ")
			:AddTextPart("Format", "@2")
		)
		SendAvailableFormats(a_Player)
		return true
	end
	local Format = a_Split[4]

	-- Check if the format is supported:
	if not(g_Exporters[Format]) then
		a_Player:SendMessage(cCompositeChat("Cannot export, there is no such format.", mtFailure))
		SendAvailableFormats(a_Player)
		return true
	end

	-- Get the area ident:
	local BlockX, _, BlockZ = GetPlayerPos(a_Player)
	local Area = g_DB:GetAreaByCoords(a_Player:GetWorld():GetName(), BlockX, BlockZ)
	if not(Area) then
		a_Player:SendMessage(cCompositeChat("Cannot export, there is no gallery area here.", mtFailure))
		return true
	end

	-- A callback function to notify the player that the export has finished
	-- Note that the player may have logged off in the meantime, need to go through name-lookup
	local PlayerName = a_Player:GetName()
	local Notifier = function (a_IsSuccess)
		cRoot:Get():FindAndDoWithPlayer(PlayerName,
			function (a_Player)
				if (a_IsSuccess) then
					a_Player:SendMessage(cCompositeChat("Area export finished successfully.", mtInformation))
				else
					a_Player:SendMessage(cCompositeChat("Area export failed.", mtFailure))
				end
			end
		)
	end

	-- Export the area using the specified exporter:
	local IsSuccess, Msg = g_Exporters[Format].ExportArea(g_Config.ExportFolder, Area, Notifier)
	if not(IsSuccess) then
		a_Player:SendMessage(cCompositeChat("Cannot export: " .. (Msg or "<Unknown error>"), mtFailure))
		return true
	end

	return true
end





function HandleCmdGroupList(a_Split, a_Player)
	-- /ge group list

	-- Get the groups from the DB:
	local Groups = g_DB:GetAllGroupNames()
	if (not(Groups) or (Groups[1] == nil)) then
		a_Player:SendMessage(cCompositeChat("There are no export groups.", mtFailure))
		return true
	end

	-- Send to the player:
	table.sort(Groups)
	a_Player:SendMessage(cCompositeChat("Defined export groups: " .. table.concat(Groups, ", "), mtInformation))

	return true
end





function HandleCmdGroupRename(a_Split, a_Player)
	-- /ge group rename <OldName> <NewName>

	-- Check params:
	if ((a_Split[4] == nil) or (a_Split[5] == nil)) then
		a_Player:SendMessage(cCompositeChat("Usage: ", mtFailure)
			:AddSuggestCommandPart(g_Config.CommandPrefix .. " group rename ", g_Config.CommandPrefix .. " group rename ")
			:AddTextPart("FromName ToName", "@2")
		)
		return true
	end

	-- Rename the group in the DB:
	local IsSuccess, Msg = g_DB:RenameGroup(a_Split[4], a_Split[5])
	if not(IsSuccess) then
		a_Player:SendMessage(cCompositeChat("Failed to rename group: " .. Msg, mtFailure))
		return true
	end

	-- Send success:
	a_Player:SendMessage(cCompositeChat("Group renamed", mtInformation))
	return true
end





function HandleCmdGroupSet(a_Split, a_Player)
	-- /ge group set <NewGroupName>

	-- Check params:
	if ((a_Split[4] == nil) or (a_Split[5] ~= nil)) then
		a_Player:SendMessage(cCompositeChat("Usage: ", mtFailure)
			:AddSuggestCommandPart(g_Config.CommandPrefix .. " group set ", g_Config.CommandPrefix .. " group set ")
			:AddTextPart("NewGroupName", "@2")
		)
		return true
	end
	local NewGroupName = a_Split[4]

	-- Get the area ident:
	local BlockX, _, BlockZ = GetPlayerPos(a_Player)
	local Area = g_DB:GetAreaByCoords(a_Player:GetWorld():GetName(), BlockX, BlockZ)
	if not(Area) then
		a_Player:SendMessage(cCompositeChat("Cannot show information, there is no gallery area here.", mtFailure))
		return true
	end

	-- Set the group in the DB:
	local IsSuccess, Msg = g_DB:SetAreaExportGroup(Area.ID, NewGroupName)
	if not(IsSuccess) then
		a_Player:SendMessage(cCompositeChat("Failed to set area's export group name in DB: " .. (Msg or "<no details>"), mtFailure))
		return true
	end

	a_Player:SendMessage(cCompositeChat("Area's export group name changed.", mtInfo))
	return true
end





function HandleCmdInfo(a_Split, a_Player)
	-- /ge info

	-- Get the area ident:
	local BlockX, _, BlockZ = GetPlayerPos(a_Player)
	local Area = g_DB:GetAreaByCoords(a_Player:GetWorld():GetName(), BlockX, BlockZ)
	if not(Area) then
		a_Player:SendMessage(cCompositeChat("Cannot show information, there is no gallery area here.", mtFailure))
		return true
	end

	-- Basic info: area identification, author, approval state:
	a_Player:SendMessage(cCompositeChat(string.format(
		"This is area #%d in gallery %s, claimed by %s.",
		Area.GalleryIndex, Area.GalleryName, Area.PlayerName), mtInfo)
	)
	local IsApproved = Area.IsApproved and (Area.IsApproved ~= 0)
	if not(IsApproved) then
		a_Player:SendMessage(cCompositeChat("The area hasn't been approved for export.", mtInfo))
		-- Non-approved areas don't have a BBox, don't print anything
	else
		a_Player:SendMessage(cCompositeChat(string.format(
			"Approved by %s on %s.",
			Area.ApprovedBy, Area.DateApproved), mtInfo)
		)
		a_Player:SendMessage(cCompositeChat(string.format(
			"Export name: %s in group %s",
			(Area.ExportName or "<no name>"), Area.ExportGroupName), mtInfo)
		)

		-- Print the BBox:
		a_Player:SendMessage(cCompositeChat(string.format(
			"Export bounds: {%d, %d, %d} - {%d, %d, %d}",
			Area.ExportMinX, Area.ExportMinY, Area.ExportMinZ,
			Area.ExportMaxX, Area.ExportMaxY, Area.ExportMaxZ), mtInfo)
		)

		-- Print the export size and volume:
		a_Player:SendMessage(cCompositeChat(string.format(
			"Export size: %d * %d * %d blocks, volume %d blocks",
			Area.ExportMaxX - Area.ExportMinX + 1,
			Area.ExportMaxY - Area.ExportMinY + 1,
			Area.ExportMaxZ - Area.ExportMinZ + 1,
			(Area.ExportMaxX - Area.ExportMinX + 1) * (Area.ExportMaxY - Area.ExportMinY + 1) * (Area.ExportMaxZ - Area.ExportMinZ + 1)
			), mtInfo)
		)
	end

	-- Connectors:
	local ConnCount, Msg = g_DB:GetAreaConnectorCount(Area.ID)
	if (ConnCount) then
		a_Player:SendMessage(cCompositeChat("There are ", mtInfo)
			:AddRunCommandPart(ConnCount .. " connectors", g_Config.CommandPrefix .. " conn list", "@bu")
			:AddTextPart(" for this area.")
		)
	else
		a_Player:SendMessage(cCompositeChat("Cannot evaluate connectors for this area: " .. (Msg or "<no details>"), mtFailure))
	end

	-- Sponges:
	local HasSponge
	HasSponge, Msg = g_DB:HasSponge(Area.ID)
	if (HasSponge == true) then
		a_Player:SendMessage(cCompositeChat("The area has been sponged.", mtInfo))
	elseif (HasSponge == false) then
		a_Player:SendMessage(cCompositeChat("The area has NOT been sponged yet.", mtInfo))
	else
		a_Player:SendMessage(cCompositeChat("Cannot determine area's sponge status: " .. (Msg or "<no details>"), mtFailure))
	end

	-- Metadata:
	local Metadata
	Metadata, Msg = g_DB:GetMetadataForArea(Area.ID)
	if (Metadata) then
		-- Sort the metadata:
		local MetadataArr = {}
		for k, v in pairs(Metadata) do
			table.insert(MetadataArr, k .. ": " .. v)
		end
		table.sort(MetadataArr)

		-- Send count to player:
		local NumMetadata = #MetadataArr
		if (NumMetadata == 0) then
			a_Player:SendMessage(cCompositeChat("There is no metadata value.", mtInfo))
		elseif (NumMetadata == 1) then
			a_Player:SendMessage(cCompositeChat("There is one metadata value:", mtInfo))
		else
			a_Player:SendMessage(cCompositeChat(string.format(
				"There are %d metadata values:", #MetadataArr), mtInfo)
			)
		end

		-- Send values to player:
		for _, m in ipairs(MetadataArr) do
			a_Player:SendMessage(cCompositeChat("  " .. m, mtInfo))
		end
	else
		a_Player:SendMessage(cCompositeChat("Area's metadata query failed: " .. (Msg or "<no details>"), mtFailure))
	end

	return true
end





-- Shows a list of all the approved areas.
function HandleCmdListApproved(a_Split, a_Player)
	-- /ge list [GroupName]

	local Areas = nil
	if (a_Split[3] ~= nil) then
		local GroupName = table.concat(a_Split, " ", 3)

		-- Get all the approved areas in the given group.
		Areas = g_DB:GetApprovedAreasInGroup(GroupName)

		-- Check if the group actualy exists.
		if ((Areas == nil) or (Areas[1] == nil)) then
			a_Player:SendMessage("There are no approved areas in group \"" .. GroupName .. "\".")
			return true
		end
	else
		-- Get all the approved areas from all the groups.
		Areas = g_DB:GetAllApprovedAreas()
	end

	-- Send a message with the list of approved areas.
	a_Player:SendMessage("There are " .. #Areas .. " approved areas:")

	-- Sort by ExportGroupName:
	table.sort(Areas,
		function(a_Area1, a_Area2)
			-- If the ExportGroupName is the same, compare the ID:
			if (a_Area1.ExportGroupName == a_Area2.ExportGroupName) then
				return (a_Area1.ID < a_Area2.ID)
			end

			-- The GalleryName is different, use that
			return (a_Area1.ExportGroupName < a_Area2.ExportGroupName)
		end
	)

	-- Show the list of areas.
	for _, Area in ipairs(Areas) do
		a_Player:SendMessage(Area.Name)
	end

	return true
end





function HandleCmdName(a_Split, a_Player)
	-- /ge name <AreaName>

	-- Check params:
	if (a_Split[3] == nil) then
		a_Player:SendMessage(cCompositeChat("Usage: ", mtFailure)
			:AddSuggestCommandPart(g_Config.CommandPrefix .. " group rename ", g_Config.CommandPrefix .. " group rename ")
			:AddTextPart("FromName ToName", "@2")
		)
		return true
	end
	local AreaName = a_Split[3]

	-- Get the area ident:
	local BlockX, _, BlockZ = GetPlayerPos(a_Player)
	local Area = g_DB:GetAreaByCoords(a_Player:GetWorld():GetName(), BlockX, BlockZ)
	if (not(Area) or not(Area.IsApproved) or (Area.IsApproved == 0)) then
		a_Player:SendMessage(cCompositeChat("Cannot name, there is no approved area here.", mtFailure))
		return true
	end

	-- Rename the area:
	g_DB:SetAreaExportName(Area.ID, AreaName)
	a_Player:SendMessage(cCompositeChat("Area renamed to " .. AreaName, mtInfo))
	return true
end





function HandleCmdSet(a_Split, a_Player)
	-- /ge set [<Name> <Value>]

	-- If without params, it's a "list" request
	if (a_Split[3] == nil) then
		ListUnderstoodMetadata(a_Player)
		ListMetadataForArea(a_Player)
		return true
	end

	-- If the metadata name is not understood, warn (but still set):
	if not(g_UnderstoodMetadataNames[a_Split[3]]) then
		a_Player:SendMessage(cCompositeChat(
			"Metadata name ", mtInfo)
			:AddTextPart(a_Split[3], "@2")
			:AddTextPart(" is not understood. Saving as an unknown metadata.")
		)
	end

	-- Get the area ident:
	local BlockX, _, BlockZ = GetPlayerPos(a_Player)
	local Area = g_DB:GetAreaByCoords(a_Player:GetWorld():GetName(), BlockX, BlockZ)
	if (not(Area) or not(Area.IsApproved) or (Area.IsApproved == 0)) then
		a_Player:SendMessage(cCompositeChat("Cannot set metadata, there is no approved area here.", mtFailure))
		return true
	end

	-- Set the metadata value into the DB:
	local Name = a_Split[3]
	local Value = table.concat(a_Split, " ", 4)
	local Operation = (Value == "") and {"remove", "removed"} or {"set", "set"}
	local IsSuccess, Msg = g_DB:SetAreaMetadata(Area.ID, Name, Value)
	if not(IsSuccess) then
		a_Player:SendMessage(cCompositeChat("Cannot " .. Operation[1] .. " metadata: " .. (Msg or "<no details>"), mtFailure))
		return true
	end

	a_Player:SendMessage(cCompositeChat("Metadata has been " .. Operation[2] .. ".", mtInfo))
	return true
end





function HandleCmdSpongeHide(a_Split, a_Player)
	-- /ge sponge hide

	-- Store the value for the ChunkStay callback, when this function is already out of scope:
	local PlayerName = a_Player:GetName()

	-- Get the area ident:
	local BlockX, _, BlockZ = GetPlayerPos(a_Player)
	local Area = g_DB:GetAreaByCoords(a_Player:GetWorld():GetName(), BlockX, BlockZ)
	if not(Area) then
		a_Player:SendMessage(cCompositeChat("Cannot hide sponge, there is no gallery area here.", mtFailure))
		return true
	end

	-- Create a cuboid for the area coords:
	local Bounds = cCuboid(
		Area.MinX, 0,   Area.MinZ,
		Area.MaxX, 255, Area.MaxZ
	)

	-- Read the area's blocks:
	local Chunks = GetChunksForRect(Area.MinX, Area.MinZ, Area.MaxX, Area.MaxZ)
	assert(Chunks[1] ~= nil)  -- At least one chunk needs to be there
	local World = cRoot:Get():GetWorld(Area.WorldName)
	a_Player:SendMessage(cCompositeChat("Hiding sponge, please stand by...", mtInfo))
	World:ChunkStay(Chunks,
		function (a_ChunkX, a_ChunkZ)
			-- OnChunkAvailable, not needed
		end,
		function ()
			-- OnAllChunksAvailable

			-- Push a WE undo:
			-- We don't have a valid cPlayer object anymore, need to search for it:
			local ShouldAbort = false
			World:DoWithPlayer(PlayerName,
				function (a_Player)
					local IsSuccess, Msg = cPluginManager:CallPlugin("WorldEdit", "WEPushUndo", a_Player, World, Bounds, "GalExport: Sponge hide")
					if (IsSuccess == false) then
						-- Pushing the undo failed, let the player know and don't hide the sponge:
						a_Player:SendMessage(cCompositeChat("Cannot store an undo point in WorldEdit, aborting the sponge hide (" .. (Msg or "<no details>") .. ")", mtFailure))
						ShouldAbort = true
					end
				end
			)
			if (ShouldAbort) then
				return
			end

			-- Read the area:
			local BA = cBlockArea()
			BA:Read(World, Bounds, cBlockArea.baTypes + cBlockArea.baMetas)

			-- Remove the sponge blocks, by merging them using the msSpongePrint strategy:
			local BA2 = cBlockArea()
			local SizeX, SizeY, SizeZ = BA:GetSize()
			BA2:Create(SizeX, SizeY, SizeZ, cBlockArea.baTypes + cBlockArea.baMetas)
			BA2:Merge(BA, 0, 0, 0, cBlockArea.msSpongePrint)
			BA2:Write(World, Bounds.p1)
			SendPlayerMessage(PlayerName, cCompositeChat("Sponge hidden", mtInfo))

			-- Remove the block areas' data from RAM, not to wait for Lua's GC:
			BA:Clear()
			BA2: Clear()
		end
	)
	return true
end





function HandleCmdSpongeSave(a_Split, a_Player)
	-- /ge sponge save

	-- Store the value for the ChunkStay callback, when this function is already out of scope:
	local PlayerName = a_Player:GetName()

	-- Get the area ident:
	local BlockX, _, BlockZ = GetPlayerPos(a_Player)
	local Area = g_DB:GetAreaByCoords(a_Player:GetWorld():GetName(), BlockX, BlockZ)
	if not(Area) then
		a_Player:SendMessage(cCompositeChat("Cannot save sponge, there is no gallery area here.", mtFailure))
		return true
	end
	local AreaID = Area.ID

	-- Create a cuboid for the area coords:
	local Bounds = cCuboid(
		Area.MinX, 0,   Area.MinZ,
		Area.MaxX, 255, Area.MaxZ
	)

	-- Read the area's blocks:
	local Chunks = GetChunksForRect(Area.MinX, Area.MinZ, Area.MaxX, Area.MaxZ)
	assert(Chunks[1] ~= nil)  -- At least one chunk needs to be there
	local World = cRoot:Get():GetWorld(Area.WorldName)
	a_Player:SendMessage(cCompositeChat("Saving sponge, please stand by...", mtInfo))
	World:ChunkStay(Chunks,
		function (a_ChunkX, a_ChunkZ)
			-- OnChunkAvailable, not needed
		end,
		function ()
			-- OnAllChunksAvailable
			-- Read the area:
			local BA = cBlockArea()
			BA:Read(World, Bounds, cBlockArea.baTypes + cBlockArea.baMetas)

			-- Save sponges to DB:
			local IsSuccess, Msg = g_DB:UpdateAreaSponges(AreaID, BA)
			BA:Clear()  -- Remove the area's data from the RAM, not to wait for Lua's GC
			if not(IsSuccess) then
				SendPlayerMessage(PlayerName, cCompositeChat("Cannot save sponge: " .. Msg, mtFailure))
				return;
			end
			SendPlayerMessage(PlayerName, cCompositeChat("Sponge saved.", mtInfo))
		end
	)
	return true
end





function HandleCmdSpongeShow(a_Split, a_Player)
	-- /ge sponge show

	-- Store the value for the ChunkStay callback, when this function is already out of scope:
	local PlayerName = a_Player:GetName()

	-- Get the area ident:
	local BlockX, _, BlockZ = GetPlayerPos(a_Player)
	local Area = g_DB:GetAreaByCoords(a_Player:GetWorld():GetName(), BlockX, BlockZ)
	if not(Area) then
		a_Player:SendMessage(cCompositeChat("Cannot show sponge, there is no gallery area here.", mtFailure))
		return true
	end
	local AreaID = Area.ID

	-- Create a cuboid for the area coords:
	local Bounds = cCuboid(
		Area.MinX, 0,   Area.MinZ,
		Area.MaxX, 255, Area.MaxZ
	)

	-- Load the sponges from the DB:
	local Sponges, Msg = g_DB:GetSpongesForArea(AreaID)
	if (Sponges == nil) then
		a_Player:SendMessage(cCompositeChat("Cannot show sponge, " .. Msg, mtFailure))
		return true
	end

	-- Load all the chunks for the area::
	local Chunks = GetChunksForRect(Area.MinX, Area.MinZ, Area.MaxX, Area.MaxZ)
	assert(Chunks[1] ~= nil)  -- At least one chunk needs to be there
	local World = cRoot:Get():GetWorld(Area.WorldName)
	a_Player:SendMessage(cCompositeChat("Showing sponge, please stand by...", mtInfo))
	World:ChunkStay(Chunks,
		function (a_ChunkX, a_ChunkZ)
			-- OnChunkAvailable, not needed
		end,
		function ()
			-- OnAllChunksAvailable

			-- Push a WE undo:
			-- We don't have a valid cPlayer object anymore, need to search for it:
			local ShouldAbort = false
			World:DoWithPlayer(PlayerName,
				function (a_Player)
					local IsSuccess, Msg = cPluginManager:CallPlugin("WorldEdit", "WEPushUndo", a_Player, World, Bounds, "GalExport: Sponge show")
					if (IsSuccess == false) then
						-- Pushing the undo failed, let the player know and don't show the sponge:
						a_Player:SendMessage(cCompositeChat("Cannot store an undo point in WorldEdit, aborting the sponge show (" .. (Msg or "<no details>") .. ")", mtFailure))
						ShouldAbort = true
					end
				end
			)
			if (ShouldAbort) then
				return
			end

			-- Read the current area:
			local BA = cBlockArea();
			BA:Read(World, Bounds, cBlockArea.baTypes + cBlockArea.baMetas)

			-- Merge the sponges in:
			BA:Merge(Sponges, 0, 0, 0, cBlockArea.msFillAir)

			-- Write the area:
			BA:Write(World, Bounds.p1.x, 0, Bounds.p1.z, cBlockArea.baTypes + cBlockArea.baMetas)
			SendPlayerMessage(PlayerName, cCompositeChat("Sponge shown.", mtInfo))

			-- Remove the areas' data from RAM, not to wait for Lua's GC
			BA:Clear()
			Sponges:Clear()
		end
	)
	return true
end





function HandleCmdUnset(a_Split, a_Player)
	-- /ge unset <Name>

	-- Check params:
	if not(a_Split[3]) then
		a_Player:SendMessage(cCompositeChat("Usage: ", mtFailure)
			:AddSuggestCommandPart(g_Config.CommandPrefix .. " unset ", g_Config.CommandPrefix .. " unset ")
			:AddTextPart("Name", "@2")
		)
		return true
	end

	-- Get the area ident:
	local BlockX, _, BlockZ = GetPlayerPos(a_Player)
	local Area = g_DB:GetAreaByCoords(a_Player:GetWorld():GetName(), BlockX, BlockZ)
	if not(Area) then
		a_Player:SendMessage(cCompositeChat("Cannot unset metadata, there is no gallery area here.", mtFailure))
		return true
	end

	-- Unset in the DB:
	local IsSuccess, Msg = g_DB:UnsetAreaMetadata(Area.ID, a_Split[3])
	if not(IsSuccess) then
		a_Player:SendMessage(cCompositeChat("Failed to unset metadata: " .. (Msg or "<unknown error>"), mtFailure))
	end

	-- Report success:
	a_Player:SendMessage(cCompositeChat("Metadata has been unset", mtInformation))
	return true
end




