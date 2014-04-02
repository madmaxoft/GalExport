
-- GameCmdHandlers.lua

-- Implements the handlers for the in-game commands





--- Returns the player's position in integral blocks
function GetPlayerPos(a_Player)
	return
		math.floor(a_Player:GetPosX()),
		math.floor(a_Player:GetPosY()),
		math.floor(a_Player:GetPosZ())
end





--- Sends the list of available export formats to the specified player
local function SendAvailableFormats(a_Player)
	-- Check params:
	assert(tolua.type(a_Player) == "cPlayer")
	
	-- Get a sorted list of export formats:
	local Formats = {}
	for k, v in pairs(g_Exporters) do
		table.insert(Formats, k)
	end
	table.sort(Formats)
	
	-- Send to the player:
	a_Player:SendMessage(cCompositeChat("Available formats: " .. table.concat(Formats, ", ")):SetMessageType(mtInfo))
end





--- Exports all the areas in a_Areas into the specified format
-- a_Areas contains an array of area idents (DB row contents)
-- a_Format is the string specifying the format
-- a_Player is the player who asked for the export, they will get the completion message
-- a_MsgSuccess is the message to send on success
-- a_MsgFail is the message to send on failure, with possibly the reason appended to it
-- Function is used from ConsoleCommands as well, with a_Player being set to nil
function ExportAreas(a_Areas, a_Format, a_Player, a_MsgSuccess, a_MsgFail)
	-- Check params:
	assert(type(a_Areas) == "table")
	assert(type(a_Format) == "string")
	assert((a_Player == nil) or (tolua.type(a_Player) == "cPlayer"))
	assert(type(a_MsgSuccess) == "string")
	assert(type(a_MsgFail) == "string")
	
	-- Get the exporter for the format:
	local Exporter = g_Exporters[a_Format]
	assert(Exporter ~= nil)
	
	-- Remember the player name, so that we can get to them later on:
	local PlayerName
	if (a_Player ~= nil) then
		PlayerName = a_Player:GetName()
		a_Player:SendMessage(cCompositeChat("Exporting " .. #a_Areas .. " areas..."):SetMessageType(mtInformation))
	else
		LOGINFO("Exporting " .. #a_Areas .. " areas...")
	end
	
	-- Create a closure that queues one area for export and leaves the rest for after the export finishes:
	local function QueueExport(a_Areas)
		-- If there's no more areas to export, bail out:
		if (a_Areas[1] == nil) then
			-- Send the success message to the player / console:
			SendPlayerMessage(PlayerName, cCompositeChat(a_MsgSuccess):SetMessageType(mtInformation))
			return
		end
		
		-- Queue and remove the last area from the table:
		local Area = table.remove(a_Areas)
		Exporter.ExportArea(Area,
			function (a_IsSuccess)
				-- The area has been exported
				if (a_IsSuccess) then
					-- Queue another area for export:
					QueueExport(a_Areas)
				else
					-- Send the failure msg to the player / console:
					SendPlayerMessage(cCompositeChat(a_MsgFail):SetMessageType(mtFailure))
				end
			end
		)
	end
	
	-- Queue all the areas:
	QueueExport(a_Areas)
	
	return true
end





--- Removes each sponge block in the block area, replacing it with air
function HideSponge(a_BlockArea)
	assert(tolua.type(a_BlockArea) == "cBlockArea")

	local SizeX, SizeY, SizeZ = a_BlockArea:GetSize()
	-- TODO
end





function HandleCmdApprove(a_Split, a_Player)
	-- Check the params:
	if (a_Split[3] == nil) then
		a_Player:SendMessage(cCompositeChat():SetMessageType(mtFailure)
			:AddTextPart("Usage: ")
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
		a_Player:SendMessage(cCompositeChat():SetMessageType(mtFailure):AddTextPart("Cannot approve, there is no gallery area here."))
		return true
	end
	
	-- Get the WE selection (will be used as the export bounds):
	local SelCuboid = cCuboid()
	local IsSuccess = cPluginManager:CallPlugin("WorldEdit", "GetPlayerCuboidSelection", a_Player, SelCuboid)
	if not(IsSuccess) then
		a_Player:SendMessage(cCompositeChat():SetMessageType(mtFailure):AddTextPart("Cannot approve, WorldEdit not installed or has no cuboid selection."))
		return true
	end
	SelCuboid:Sort()
	
	-- Check if the selection is all outside:
	local AreaCuboid = cCuboid(Area.MinX, 0, Area.MinZ, Area.MaxX - 1, 255, Area.MaxZ - 1)
	if not(AreaCuboid:DoesIntersect(SelCuboid)) then
		a_Player:SendMessage(cCompositeChat():SetMessageType(mtFailure):AddTextPart("Cannot approve, your WE selection is not in this area. You need to select the export-bounds."))
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
		a_Player:SendMessage(cCompositeChat():SetMessageType(mtFailure):AddTextPart("Cannot approve, " .. (ret2 or "DB failure")))
		return true
	elseif (IsSuccess == false) then
		ret2 = ret2 or "<unknown>"
		ret3 = ret3 or "<unknown>"
		ret4 = ret4 or "<unknown>"
		a_Player:SendMessage(cCompositeChat():SetMessageType(mtFailure):AddTextPart("Cannot approve, the area has been already approved by " .. ret2 .. " on " .. ret3 .. " in group " .. ret4))
		return true
	end
	
	a_Player:SendMessage(cCompositeChat():SetMessageType(mtInformation):AddTextPart("Area successfully approved."))
	return true
end





function HandleCmdBboxChange(a_Split, a_Player)
	-- /ge bbox change

	-- Get the area ident:
	local BlockX, _, BlockZ = GetPlayerPos(a_Player)
	local Area = g_DB:GetAreaByCoords(a_Player:GetWorld():GetName(), BlockX, BlockZ)
	if not(Area) then
		a_Player:SendMessage(cCompositeChat("Cannot export, there is no gallery area here."):SetMessageType(mtFailure))
		return true
	end
	
	-- Get the selection from WE:
	local SelCuboid = cCuboid()
	local IsSuccess = cPluginManager:CallPlugin("WorldEdit", "GetPlayerCuboidSelection", a_Player, SelCuboid)
	if not(IsSuccess) then
		a_Player:SendMessage(cCompositeChat("Cannot get WorldEdit selection"):SetMessageType(mtFailure))
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
		a_Player:SendMessage(cCompositeChat("Boundingbox changed"):SetMessageType(mtInformation))
	else
		a_Player:SendMessage(cCompositeChat("Cannot change boundingbox: " .. Msg):SetMessageType(mtFailure))
	end
	return true
end





function HandleCmdBboxShow(a_Split, a_Player)
	-- /ge bbox show
	
	-- Get the area ident:
	local BlockX, _, BlockZ = GetPlayerPos(a_Player)
	local Area = g_DB:GetAreaByCoords(a_Player:GetWorld():GetName(), BlockX, BlockZ)
	if not(Area) then
		a_Player:SendMessage(cCompositeChat("Cannot show boundingbox, there is no gallery area here."):SetMessageType(mtFailure))
		return true
	end
	
	-- Check if the area is approved:
	if not(Area.IsApproved == 1) then
		a_Player:SendMessage(cCompositeChat("Cannot show boundingbox, this area is not approved."):SetMessageType(mtFailure))
		return true
	end
	
	-- Send the selection to WE:
	local SelCuboid = cCuboid(Area.ExportMinX, Area.ExportMinY, Area.ExportMinZ, Area.ExportMaxX, Area.ExportMaxY, Area.ExportMaxZ)
	local IsSuccess = cPluginManager:CallPlugin("WorldEdit", "SetPlayerCuboidSelection", a_Player, SelCuboid)
	if not(IsSuccess) then
		a_Player:SendMessage(cCompositeChat("Cannot set WorldEdit selection to the boundingbox"):SetMessageType(mtFailure))
	else
		a_Player:SendMessage(cCompositeChat("WorldEdit selection set to the boundingbox"):SetMessageType(mtInformation))
	end
	return true
end





function HandleCmdExportAll(a_Split, a_Player)
	-- /ge export all <format>

	-- Check the params:
	if (a_Split[4] == nil) then
		a_Player:SendMessage(cCompositeChat():SetMessageType(mtFailure)
			:AddTextPart("Usage: ")
			:AddSuggestCommandPart(g_Config.CommandPrefix .. " export this ", g_Config.CommandPrefix .. " export this ")
			:AddTextPart("Format", "@2")
		)
		SendAvailableFormats(a_Player)
		return true
	end
	local Format = a_Split[4]
	
	-- Check if the format is supported:
	if not(g_Exporters[Format]) then
		a_Player:SendMessage(cCompositeChat("Cannot export, there is no such format."):SetMessageType(mtFailure))
		SendAvailableFormats(a_Player)
		return true
	end
	
	-- Get the areas:
	local Areas = g_DB:GetAllApprovedAreas()
	if (not(Areas) or (Areas[1] == nil)) then
		a_Player:SendMessage(cCompositeChat("Cannot export, there is no gallery area approved."):SetMessageType(mtFailure))
		return true
	end
	
	-- Export the areas:
	return ExportAreas(Areas, Format, a_Player, "Areas exported", "Cannot export areas")
end





function HandleCmdExportGroup(a_Split, a_Player)
	-- /ge export group <groupname> <format>
	-- Check the params:
	if ((a_Split[4] == nil) or (a_Split[5] == nil)) then
		a_Player:SendMessage(cCompositeChat():SetMessageType(mtFailure)
			:AddTextPart("Usage: ")
			:AddSuggestCommandPart(g_Config.CommandPrefix .. " export group ", g_Config.CommandPrefix .. " export group ")
			:AddTextPart("GroupName Format", "@2")
		)
		SendAvailableFormats(a_Player)
		return true
	end
	local GroupName = a_Split[4]
	local Format = a_Split[5]
	
	-- Check if the format is supported:
	if not(g_Exporters[Format]) then
		a_Player:SendMessage(cCompositeChat("Cannot export, there is no such format."):SetMessageType(mtFailure))
		SendAvailableFormats(a_Player)
		return true
	end
	
	-- Get the area ident for each area in the group:
	local Areas = g_DB:GetApprovedAreasInGroup(GroupName)
	if (not(Areas) or (Areas[1] == nil)) then
		a_Player:SendMessage(cCompositeChat("Cannot export, there is no gallery area in the group."):SetMessageType(mtFailure))
		return true
	end
	
	-- Export the areas:
	return ExportAreas(Areas, Format, a_Player, "Group exported", "Cannot export group")
end





function HandleCmdExportThis(a_Split, a_Player)
	-- /ge export this <format>
	-- Check the params:
	if (a_Split[4] == nil) then
		a_Player:SendMessage(cCompositeChat():SetMessageType(mtFailure)
			:AddTextPart("Usage: ")
			:AddSuggestCommandPart(g_Config.CommandPrefix .. " export this ", g_Config.CommandPrefix .. " export this ")
			:AddTextPart("Format", "@2")
		)
		SendAvailableFormats(a_Player)
		return true
	end
	local Format = a_Split[4]
	
	-- Check if the format is supported:
	if not(g_Exporters[Format]) then
		a_Player:SendMessage(cCompositeChat("Cannot export, there is no such format."):SetMessageType(mtFailure))
		SendAvailableFormats(a_Player)
		return true
	end
	
	-- Get the area ident:
	local BlockX, _, BlockZ = GetPlayerPos(a_Player)
	local Area = g_DB:GetAreaByCoords(a_Player:GetWorld():GetName(), BlockX, BlockZ)
	if not(Area) then
		a_Player:SendMessage(cCompositeChat("Cannot export, there is no gallery area here."):SetMessageType(mtFailure))
		return true
	end
	
	-- A callback function to notify the player that the export has finished
	-- Note that the player may have logged off in the meantime, need to go through name-lookup
	local PlayerName = a_Player:GetName()
	local Notifier = function (a_IsSuccess)
		cRoot:Get():FindAndDoWithPlayer(PlayerName,
			function (a_Player)
				if (a_IsSuccess) then
					a_Player:SendMessage(cCompositeChat("Area export finished successfully."):SetMessageType(mtInformation))
				else
					a_Player:SendMessage(cCompositeChat("Area export failed."):SetMessageType(mtFailure))
				end
			end
		)
	end
	
	-- Export the area using the specified exporter:
	local IsSuccess, Msg = g_Exporters[Format].ExportArea(Area, Notifier)
	if not(IsSuccess) then
		a_Player:SendMessage(cCompositeChat("Cannot export: " .. (Msg or "<Unknown error>")):SetMessageType(mtFailure))
		return true
	end
	
	return true
end





function HandleCmdGroupList(a_Split, a_Player)
	-- /ge group list
	
	-- Get the groups from the DB:
	local Groups = g_DB:GetAllGroups()
	if (not(Groups) or (Groups[1] == nil)) then
		a_Player:SendMessage(cCompositeChat("There are no export groups."):SetMessageType(mtFailure))
		return true
	end
	
	-- Send to the player:
	table.sort(Groups)
	a_Player:SendMessage(cCompositeChat("Defined export groups: " .. table.concat(Groups, ", ")):SetMessageType(mtInformation))
	
	return true
end





function HandleCmdGroupRename(a_Split, a_Player)
	-- /ge group rename <OldName> <NewName>
	
	-- Check params:
	if ((a_Split[4] == nil) or (a_Split[5] == nil)) then
		a_Player:SendMessage(cCompositeChat():SetMessageType(mtFailure)
			:AddTextPart("Usage: ")
			:AddSuggestCommandPart(g_Config.CommandPrefix .. " group rename ", g_Config.CommandPrefix .. " group rename ")
			:AddTextPart("FromName ToName", "@2")
		)
		return true
	end
	
	-- Rename the group in the DB:
	local IsSuccess, Msg = g_DB:RenameGroup(a_Split[4], a_Split[5])
	if not(IsSuccess) then
		a_Player:SendMessage(cCompositeChat("Failed to rename group: " .. Msg):SetMessageType(mtFailure))
		return true
	end
	
	-- Send success:
	a_Player:SendMessage(cCompositeChat("Group renamed"):SetMessageType(mtInformation))
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
		a_Player:SendMessage(cCompositeChat():SetMessageType(mtFailure)
			:AddTextPart("Usage: ")
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
		a_Player:SendMessage(cCompositeChat("Cannot name, there is no approved area here."):SetMessageType(mtFailure))
		return true
	end
	
	-- Rename the area:
	g_DB:SetAreaExportName(Area.ID, AreaName)
	a_Player:SendMessage(cCompositeChat("Area renamed to " .. AreaName):SetMessageType(mtInfo))
	return true
end





function HandleCmdSpongeHide(a_Split, a_Player)
	-- /ge sponge hide
	
	-- Store the value for the ChunkStay callback, when this function is already out of scope:
	local PlayerName = a_Player:GetName()
	
	-- Get the area ident:
	local BlockX, _, BlockZ = GetPlayerPos(a_Player)
	local Area = g_DB:GetAreaByCoords(a_Player:GetWorld():GetName(), BlockX, BlockZ)
	if (not(Area) or not(Area.IsApproved) or (Area.IsApproved == 0)) then
		a_Player:SendMessage(cCompositeChat("Cannot hide sponge, there is no gallery area here."):SetMessageType(mtFailure))
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
	if (not(Area) or not(Area.IsApproved) or (Area.IsApproved == 0)) then
		a_Player:SendMessage(cCompositeChat("Cannot save sponge, there is no gallery area here."):SetMessageType(mtFailure))
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
	if (not(Area) or not(Area.IsApproved) or (Area.IsApproved == 0)) then
		a_Player:SendMessage(cCompositeChat("Cannot show sponge, there is no gallery area here."):SetMessageType(mtFailure))
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
		a_Player:SendMessage(cCompositeChat("Cannot show sponge, " .. Msg):SetMessageType(mtFailure))
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




