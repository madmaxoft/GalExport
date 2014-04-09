
-- GameCmdHandlers.lua

-- Implements the handlers for the in-game commands





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
	
	a_Player:SendMessage(cCompositeChat("Area successfully approved.", mtInformation))
	return true
end





function HandleCmdBboxChange(a_Split, a_Player)
	-- /ge bbox change

	-- Get the area ident:
	local BlockX, _, BlockZ = GetPlayerPos(a_Player)
	local Area = g_DB:GetAreaByCoords(a_Player:GetWorld():GetName(), BlockX, BlockZ)
	if not(Area) then
		a_Player:SendMessage(cCompositeChat("Cannot export, there is no gallery area here.", mtFailure))
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
	if not(Area.IsApproved == 1) then
		a_Player:SendMessage(cCompositeChat("Cannot show boundingbox, this area is not approved.", mtFailure))
		return true
	end
	
	-- Send the selection to WE:
	local SelCuboid = cCuboid(Area.ExportMinX, Area.ExportMinY, Area.ExportMinZ, Area.ExportMaxX, Area.ExportMaxY, Area.ExportMaxZ)
	local IsSuccess = cPluginManager:CallPlugin("WorldEdit", "SetPlayerCuboidSelection", a_Player, SelCuboid)
	if not(IsSuccess) then
		a_Player:SendMessage(cCompositeChat("Cannot set WorldEdit selection to the boundingbox", mtFailure))
	else
		a_Player:SendMessage(cCompositeChat("WorldEdit selection set to the boundingbox", mtInformation))
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
	a_Player:SendMessage(cCompositeChat("These connectors have been defined for this area:", mtInfo))
	for idx, conn in ipairs(Connectors) do
		a_Player:SendMessage(cCompositeChat(
			string.format(
				"  %d: type %d, {%d, %d, %d}, dir %s (",
				idx, conn.TypeNum, conn.X - Area.ExportMinX, conn.Y - Area.ExportMinY, conn.Z - Area.ExportMinZ,
				(DirectionToString(conn.Direction) or "<unknown>")
			), mtInfo)
			:AddRunCommandPart("goto", g_Config.CommandPrefix .. " conn goto " .. conn.ID, "@bu")
			:AddTextPart(", ")
			:AddSuggestCommandPart("del", g_Config.CommandPrefix .. " conn del " .. conn.ID, "@bu")
			:AddTextPart(")")
		)
	end
	
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
	local IsSuccess, Msg = g_Exporters[Format].ExportArea(Area, Notifier)
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
		return
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
end




