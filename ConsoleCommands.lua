
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
	
	-- Export (using code common with the game command handler):
	-- The default callbacks are okay for us (writing message to console)
	QueueExportAllGroups(Format, nil)
	
	return true
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

	-- Export (using code common with the game command handler):
	-- The default callbacks are okay for us (writing message to console)
	QueueExportAreaGroup(GroupName, Format, nil)

	return true
end




