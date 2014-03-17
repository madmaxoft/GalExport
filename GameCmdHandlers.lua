
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





function HandleCmdApprove(a_Split, a_Player)
	-- Check the params:
	if (a_Split[3] == nil) then
		a_Player:SendMessage(cCompositeChat():SetMessageType(mtFailure)
			:AddTextPart("Usage: ")
			:AddSuggestCommandPart(g_Config.CommandPrefix .. " approve ", g_Config.CommandPrefix .. " approve ")
			:AddTextPart("GroupName", "@2")
		)
		return true
	end
	local GroupName = a_Split[3]
	
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
	IsSuccess, ret2, ret3, ret4 = g_DB:ApproveArea(Area.ID, a_Player:GetName(), GroupName, SelCuboid)
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




