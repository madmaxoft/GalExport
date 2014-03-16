
-- GameCmdHandlers.lua

-- Implements the handlers for the in-game commands





--- Returns the player's position in integral blocks
function GetPlayerPos(a_Player)
	return
		math.floor(a_Player:GetPosX()),
		math.floor(a_Player:GetPosY()),
		math.floor(a_Player:GetPosZ())
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




