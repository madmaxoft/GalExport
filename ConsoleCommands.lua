
-- ConsoleCommands.lua

-- Implements the handlers for the console commands implemented by this plugin





function HandleConExportAll(a_Split)
	-- ge all <Format>

	-- Check the params:
	if (a_Split[3] == nil) then
		LOGWARNING("Usage: ge all <Format>")
		return true
	end
	local Format = a_Split[3]
	
	-- Check if the format is supported:
	if not(g_Exporters[Format]) then
		LOGWARNING("Cannot export, there is no such format.")
		return true
	end
	
	-- Get the areas:
	local Areas = g_DB:GetAllApprovedAreas()
	if (not(Areas) or (Areas[1] == nil)) then
		LOGWARNING("Cannot export, there is no approved gallery area.")
		return true
	end
	
	-- Export the areas:
	return ExportAreas(Areas, Format, nil, "Areas exported", "Cannot export areas")
end





function HandleConExportGroup(a_Split)
	-- ge group <GroupName> <Format>

	-- Check the params:
	if ((a_Split[3] == nil) or (a_Split[4] == nil)) then
		LOGWARNING("Usage: ge group <GroupName> <Format>")
		return true
	end
	local GroupName = a_Split[3]
	local Format = a_Split[4]
	
	-- Check if the format is supported:
	if not(g_Exporters[Format]) then
		LOGWARNING("Cannot export, there is no such format.")
		return true
	end
	
	-- Get the areas:
	local Areas = g_DB:GetApprovedAreasInGroup(GroupName)
	if (not(Areas) or (Areas[1] == nil)) then
		LOGWARNING("Cannot export, there is no approved gallery area in the group.")
		return true
	end
	
	-- Export the areas:
	-- Export the areas:
	local function ReportSuccess()
		LOGINFO("Group exported")
	end
	local function ReportFailure(a_Message)
		LOGINFO("Cannot export group: " .. (a_Message or "<no details>"))
	end
	g_Exporters[Format].ExportGroup(Areas, ReportSuccess, ReportFailure)
	return true
end




