
-- ConsoleCommands.lua

-- Implements the handlers for the console commands implemented by this plugin





-- Fixes various issues that have evolved during GalExport's lifetime,
-- such as converting ShouldExpandFloor metadata to ExpandFloorStrategy metadata
function HandleConEvolve()
	-- ge evolve

	-- Convert ShouldExpandFloor metadata to ExpandFloorStrategy metadata:
	local isSuccess, msg
	isSuccess, msg = g_DB:ExecuteStatement("UPDATE Metadata SET Name = 'ExpandFloorStrategy', Value = 'None' WHERE Name = 'ShouldExpandFloor' AND Value = '0'")
	if not(isSuccess) then
		return true, "Failed to evolve ShouldExpandFloor(0), DB failure: " .. (msg or "<no message>")
	end
	isSuccess, msg = g_DB:ExecuteStatement("UPDATE Metadata SET Name = 'ExpandFloorStrategy', Value = 'RepeatBottomTillNonAir' WHERE Name = 'ShouldExpandFloor' AND Value = '1'")
	if not(isSuccess) then
		return true, "Failed to evolve ShouldExpandFloor(1), DB failure: " .. (msg or "<no message>")
	end

	return true, "Evolving complete"
end





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





function HandleConMetaList(a_Split, _, a_EntireCommand)
	-- Check params:
	if not(a_Split[4]) then
		return true, "Usage: ge meta list <groupname>"
	end

	-- Get the metas:
	local metas, msg = g_DB:GetMetadataForGroup(a_Split[4])
	if not(metas) then
		return true, "Error while retrieving metadata: " .. (msg or "<unknown error>")
	end

	-- Format the metas and sort:
	local out = {}
	for k, v in pairs(metas) do
		table.insert(out, string.format("%s = %s", k, v))
	end
	table.sort(out)

	-- Output:
	if (#out == 0) then
		return true, "There are no metadata values for this group"
	end
	return true, "There are " .. #out .. " values: \n" .. table.concat(out, "\n")
end





function HandleConMetaSet(a_Split, _, a_EntireCommand)
	-- Check params:
	local split = StringSplitWithQuotes(a_EntireCommand, " ")
	if not(split[6]) then
		return true, "Usage: ge meta set <groupname> <name> <value>"
	end

	local IsSuccess, msg = g_DB:SetGroupMetadata(split[4], split[5], split[6])
	if (IsSuccess) then
		return true, "Metadata has been set"
	end
	return true, "Error while setting metadata: " .. (msg or "<unknown error>")
end




