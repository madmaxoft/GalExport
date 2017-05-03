
-- StorageSQLite.lua

-- Implements the SQLite-backed database storage for the export metadata

--[[
Usage: Call SQLite_CreateStorage() to get an object that has all the functions implemented below.

g_DB = SQLite_CreateStorage(config)
...
local areas = g_DB:GetAllApprovedAreas()


Note that the storage piggy-backs on the Gallery.sqlite file that the Gallery plugin uses for its data.
--]]





--- The SQLite backend namespace:
local StorageSQLite = {}





--- Default values for the metadata
-- Only the names listed here are allowed to get updated by the users
local g_MetadataDefaults =
{
	-- Whether the area is the starting area for the generator (1) or not (0):
	["IsStarting"] = 0,

	-- Number of allowed CCW rotations, expressed as a bitmask-ed number
	-- E. g. 0 = no rotations allowed, 1 = 1 CCW rotation allowed, 5 = 1 or 3 CCW rotations allowed
	["AllowedRotations"] = 7,

	-- The name of the merge strategy to use for the blockarea
	-- Must be a valid MergeStrategy name in the cBlockArea class
	["MergeStrategy"] = "msSpongePrint",

	-- How to handle the space between the bottom of the piece and the terrain
	-- Possible values: "None", "RepeatBottomTillNonAir", "RepeatBottomTillSolid"
	["ExpandFloorStrategy"] = "None",

	-- The weight to use for this prefab, unless there's any other modifier active
	["DefaultWeight"] = 100,

	-- String specifying the weighted chance for this area's occurrence per tree-depth, such as "1:100|2:50|3:40|4:1|5:0"
	-- Depth that isn't specified will get the DefaultWeight weight
	["DepthWeight"] = "",

	-- The weight to add to this piece's base per-depth chance if the previous piece is the same. Can be positive or negative.
	["AddWeightIfSame"] = 0,

	-- The prefab should move Y-wise so that its first connector is on the ground level (TerrainHeightGen); 0 or 1
	-- Used for the houses in the village generator
	["MoveToGround"] = 0,
}





--- Formats the datetime (as returned by os.time() ) into textual representation used in the DB
function FormatDateTime(a_DateTime)
	assert(type(a_DateTime) == "number")

	return os.date("%Y-%m-%dT%H:%M:%S", a_DateTime)
end





--- Adds the specified connector to the DB
-- Returns the connector ident on success, nil and message on failure
function StorageSQLite:AddConnector(a_AreaID, a_BlockX, a_BlockY, a_BlockZ, a_Direction, a_Type)
	-- Check params:
	assert(self)
	local AreaID = tonumber(a_AreaID)
	assert(AreaID)
	assert(type(a_BlockX) == "number")
	assert(type(a_BlockY) == "number")
	assert(type(a_BlockZ) == "number")
	assert(a_Direction)
	assert(type(a_Type) == "number")

	-- Save connector to DB:
	local RowID
	local IsSuccess, Msg = self:ExecuteStatement(
		"INSERT INTO Connectors (AreaID, X, Y, Z, Direction, TypeNum) VALUES (?, ?, ?, ?, ?, ?)",
		{
			AreaID,
			a_BlockX, a_BlockY, a_BlockZ,
			a_Direction, a_Type
		},
		nil,
		function (a_RowID)
			RowID = a_RowID
		end
	)
	if not(IsSuccess) or not(RowID) then
		return nil, Msg
	end

	-- Mark the area as changed:
	self:MarkAreaChangedNow(AreaID)

	-- Return the connector ident by loading it from the DB:
	return self:GetConnectorByID(RowID)
end





--- Sets the area as approved by the specified player in the specified group and with the specified export cuboid
-- If the area is already approved, returns false, the name of the approver, date approved and the group name
-- If any of the DB queries fail, returns nil.
-- Returns true on success
function StorageSQLite:ApproveArea(a_AreaID, a_PlayerName, a_GroupName, a_ExportCuboid, a_AreaName)
	-- Check params:
	assert(self)
	assert(tonumber(a_AreaID))
	assert(type(a_PlayerName) == "string")
	assert(type(a_GroupName) == "string")
	assert(tolua.type(a_ExportCuboid) == "cCuboid")
	assert((a_AreaName == nil) or (type(a_AreaName) == "string"))

	-- Check if the area is already approved:
	local Info = nil
	local IsSuccess = self:ExecuteStatement(
		"SELECT IsApproved, ApprovedBy, DateApproved, ExportGroupName FROM Areas WHERE ID = ?",
		{ a_AreaID },
		function (a_Values)
			if ((a_Values.IsApproved ~= nil) and (tonumber(a_Values.IsApproved) ~= 0)) then
				Info = a_Values
			end
		end
	)
	if not(IsSuccess) then
		return nil, "DB read failed"
	end
	if (Info) then
		return false, Info.ApprovedBy, Info.DateApproved, Info.ExportGroupName
	end

	-- Set as approved:
	IsSuccess = self:ExecuteStatement(
		"UPDATE Areas SET IsApproved = 1, ApprovedBy = ?, DateApproved = ?, ExportGroupName = ?, ExportName = ?, \
		ExportMinX = ?, ExportMinY = ?, ExportMinZ = ?, ExportMaxX = ?, ExportMaxY = ?, ExportMaxZ = ? \
		WHERE ID = ?",
		{
			a_PlayerName, FormatDateTime(os.time()), a_GroupName, a_AreaName or "",
			a_ExportCuboid.p1.x, a_ExportCuboid.p1.y, a_ExportCuboid.p1.z,
			a_ExportCuboid.p2.x, a_ExportCuboid.p2.y, a_ExportCuboid.p2.z,
			a_AreaID
		}
	)
	if not(IsSuccess) then
		return nil, "DB write failed"
	end

	-- Mark the area as changed:
	self:MarkAreaChangedNow(a_AreaID)

	-- Report success
	return true
end





--- Changes the complete information on the specified connector in the DB
-- Returns true on success, false and potentially a message on failure
function StorageSQLite:ChangeConnector(a_ConnID, a_NewX, a_NewY, a_NewZ, a_NewType, a_NewDir)
	-- Check params:
	assert(self)
	local ConnID = tonumber(a_ConnID)
	assert(ConnID)
	local NewX, NewY, NewZ, NewType = tonumber(a_NewX), tonumber(a_NewY), tonumber(a_NewZ), tonumber(a_NewType)
	assert(NewX)
	assert(NewY)
	assert(NewZ)
	assert(NewType)
	assert(a_NewDir)

	local IsSuccess, Msg = self:ExecuteStatement(
		"UPDATE Connectors SET X = ?, Y = ?, Z = ?, TypeNum = ?, Direction = ? WHERE ID = ?",
		{
			NewX, NewY, NewZ, NewType, a_NewDir, ConnID
		}
	)
	if not(IsSuccess) then
		return false, Msg
	end

	-- Mark the connector's area as changed:
	self:MarkConnectorsAreaChangedNow(ConnID)

	return true
end





--- Changes the position and, optionally, direction of the specified connector in the DB
-- Returns true on success, false and potentially a message on failure
function StorageSQLite:ChangeConnectorPos(a_ConnID, a_NewX, a_NewY, a_NewZ, a_NewDir)
	-- Check params:
	assert(self)
	local ConnID = tonumber(a_ConnID)
	assert(ConnID)
	local NewX, NewY, NewZ = tonumber(a_NewX), tonumber(a_NewY), tonumber(a_NewZ)
	assert(NewX)
	assert(NewY)
	assert(NewZ)

	local IsSuccess, Msg
	if (a_NewDir) then
		IsSuccess, Msg = self:ExecuteStatement(
			"UPDATE Connectors SET X = ?, Y = ?, Z = ?, Direction = ? WHERE ID = ?",
			{
				NewX, NewY, NewZ, a_NewDir, ConnID
			}
		)
	else
		IsSuccess, Msg = self:ExecuteStatement(
			"UPDATE Connectors SET X = ?, Y = ?, Z = ? WHERE ID = ?",
			{
				NewX, NewY, NewZ, ConnID
			}
		)
	end
	if not(IsSuccess) then
		return false, Msg
	end

	-- Mark the connector's area as changed:
	self:MarkConnectorsAreaChangedNow(ConnID)

	return true
end





--- Changes the type of the specified connector in the DB
-- Returns true on success, false and potentially a message on failure
function StorageSQLite:ChangeConnectorType(a_ConnID, a_NewType)
	-- Check params:
	assert(self)
	local ConnID = tonumber(a_ConnID)
	assert(ConnID)
	local NewType = tonumber(a_NewType)
	assert(NewType)

	local IsSuccess, Msg = self:ExecuteStatement(
		"UPDATE Connectors SET TypeNum = ? WHERE ID = ?",
		{
			NewType, ConnID
		}
	)
	if not(IsSuccess) then
		return false, "Failed to update connector type: " .. (Msg or "<unknown DB error>")
	end

	-- Mark the connector's area as changed:
	self:MarkConnectorsAreaChangedNow(ConnID)
end





--- Deletes the specified connector from the DB
-- Returns true if successful, false and potentially an error message on failure
function StorageSQLite:DeleteConnector(a_ConnID)
	-- Check params:
	assert(self)
	local ConnID = tonumber(a_ConnID)
	assert(ConnID)

	-- Get the connector's AreaID (for marking the area as changed):
	local AreaID
	self:ExecuteStatement(
		"SELECT AreaID FROM Connectors WHERE ID = ?",
		{ ConnID },
		function (a_Values)
			AreaID = a_Values["AreaID"]
		end
	)

	-- Delete from the DB:
	local IsSuccess, Msg = self:ExecuteStatement(
		"DELETE FROM Connectors WHERE ID = ?",
		{ ConnID }
	)
	if not(IsSuccess) then
		return false, "Failed to delete connector from the DB: " .. (Msg or "<unknown DB error>")
	end

	-- Mark the area as changed:
	if (AreaID) then
		self:MarkAreaChangedNow(AreaID)
	end

	return true
end





--- Sets the area (specified by its ID) as not approved. Keeps all the other data for the area
-- Returns true on success, false and optional message on failure
-- Invalid / non-approved AreaIDs will be reported as success!
function StorageSQLite:DisapproveArea(a_AreaID)
	-- Check params:
	assert(self)
	local AreaID = tonumber(a_AreaID)
	assert(AreaID)

	-- Update the DB:
	local IsSuccess, Msg = self:ExecuteStatement(
		"UPDATE Areas SET IsApproved = 0 WHERE ID = ?",
		{
			AreaID
		}
	)
	if not(IsSuccess) then
		return false, "Failed to update are in the DB: " .. (Msg or "<unknown DB error>")
	end

	-- Mark the area as changed:
	self:MarkAreaChangedNow(AreaID)

	return true
end





--- Returns an array of tables describing all the approved areas
-- Each sub-table has all the attributes read from the DB row
-- Returns an empty table if there are no approved areas
-- Returns nil on DB error
function StorageSQLite:GetAllApprovedAreas()
	-- Check params:
	assert(self)

	-- Load from the DB:
	local res = {}
	if not(self:ExecuteStatement(
		"SELECT * FROM Areas WHERE IsApproved = 1",
		{},
		function (a_Values)
			-- Require the area to have at least the ID:
			if (a_Values.ID) then
				table.insert(res, a_Values)
			end
		end
	)) then
		-- DB error or no data (?)
		return nil
	end

	return res
end





--- Returns an array of all connectors stored in the DB
-- Returns false and optional error message on failure
function StorageSQLite:GetAllConnectors()
	-- Check params:
	assert(self)

	-- Load from the DB:
	local res = {}
	local IsSuccess, Msg = self:ExecuteStatement(
		"SELECT * FROM Connectors", nil,
		function (a_Values)
			table.insert(res, a_Values)
		end
	)
	if not(IsSuccess) then
		return false, Msg
	end

	return res
end





--- Returns an array of all export groups' names stored in the DB.
-- Returns nil on failure
function StorageSQLite:GetAllGroupNames()
	-- Check params:
	assert(self)

	-- Get the groups:
	local res = {}
	if not(self:ExecuteStatement(
		"SELECT DISTINCT(ExportGroupName) FROM Areas",
		{},
		function (a_Values)
			if (a_Values.ExportGroupName) then
				table.insert(res, a_Values.ExportGroupName)
			end
		end
	)) then
		return nil
	end

	return res
end





--- Returns an array of tables describing the approved areas in the specified group
-- Each sub-table has all the attributes read from the DB row
-- Returns an empty table if there are no areas in the group
-- Returns nil on DB error
function StorageSQLite:GetApprovedAreasInGroup(a_GroupName)
	-- Check params:
	assert(self)
	assert(type(a_GroupName) == "string")

	-- Load from the DB:
	local res = {}
	if not(self:ExecuteStatement(
		"SELECT * FROM Areas WHERE IsApproved = 1 AND ExportGroupName = ? COLLATE NOCASE",
		{
			a_GroupName,
		},
		function (a_Values)
			-- Require the area to have at least the ID:
			if (a_Values.ID) then
				table.insert(res, a_Values)
			end
		end
	)) then
		-- DB error or no data (?)
		return nil
	end

	return res
end





--- Returns a table describing the area at the specified coords
-- The table has all the attributes read from the DB row
-- Returns nil if there's no area at those coords
function StorageSQLite:GetAreaByCoords(a_WorldName, a_BlockX, a_BlockZ)
	-- Check params:
	assert(self)
	assert(type(a_WorldName) == "string")
	assert(type(a_BlockX) == "number")
	assert(type(a_BlockZ) == "number")

	-- Load from the DB:
	local res
	if not(self:ExecuteStatement(
		"SELECT * FROM Areas WHERE (MinX <= ?) AND (MaxX > ?) AND (MinZ < ?) AND (MaxZ > ?)",
		{
			a_BlockX, a_BlockX,
			a_BlockZ, a_BlockZ,
		},
		function (a_Values)
			res = a_Values
		end
	)) then
		-- DB error or no data (?)
		return nil
	end

	if (not(res) or not(res.ID)) then
		-- No valid data has been returned by the DB call
		return nil
	end

	return res
end





--- Returns a table describing the area of the specified ID
-- The table has all the attributes read from the DB row
-- Returns nil and possibly an error message if there's no area with such ID or there's a DB error
function StorageSQLite:GetAreaByID(a_AreaID)
	-- Check params:
	assert(self)
	local AreaID = tonumber(a_AreaID)
	assert(AreaID)

	-- Load from the DB:
	local res
	local IsSuccess, Msg = self:ExecuteStatement(
		"SELECT * FROM Areas WHERE ID = ?",
		{
			AreaID
		},
		function (a_Values)
			res = a_Values
		end
	)
	if (not(IsSuccess) or (res == nil) or (res.ID == nil)) then
		-- DB error or no valid data:
		return nil, Msg
	end

	return res
end





--- Returns the count of connectors for the specified area
-- Returns nil and possibly message on error
function StorageSQLite:GetAreaConnectorCount(a_AreaID)
	-- Check params:
	assert(self)
	local AreaID = tonumber(a_AreaID)
	assert(AreaID)

	-- Query the DB:
	local res
	local IsSuccess, Msg = self:ExecuteStatement(
		"SELECT COUNT(*) AS Count FROM Connectors WHERE AreaID = ?",
		{ AreaID },
		function (a_Values)
			res = a_Values.Count
		end
	)
	if not(IsSuccess) then
		return nil, Msg
	end

	return res
end





--- Returns an array of all the connectors for the specified area
-- Each member is a table with all the DB values for the connector
-- Returns nil and possibly message on error
function StorageSQLite:GetAreaConnectors(a_AreaID)
	-- Check params:
	assert(self)
	local AreaID = tonumber(a_AreaID)
	assert(AreaID)

	-- Load from the DB:
	local res = {}
	local ins = table.insert
	local IsSuccess, Msg = self:ExecuteStatement(
		"SELECT * FROM Connectors WHERE AreaID = ?",
		{ AreaID },
		function (a_Values)
			ins(res, a_Values)
		end
	)
	if not(IsSuccess) then
		return nil, Msg
	end

	return res
end





--- Returns a table of all the DB values (ident) of the specified connector
-- Returns nil and possibly message on failure
function StorageSQLite:GetConnectorByID(a_ConnectorID)
	-- Check params:
	assert(self)
	local ConnectorID = tonumber(a_ConnectorID)
	assert(ConnectorID)

	-- Load from DB:
	local res
	local IsSuccess, Msg = self:ExecuteStatement(
		"SELECT * FROM Connectors WHERE ID = ?",
		{ ConnectorID },
		function(a_Values)
			res = a_Values
		end
	)
	if not(IsSuccess) then
		return nil, Msg
	end

	return res
end





--- Returns the number of approved areas in the specified export group
-- Returns zero if no area in the group (group doesn't exist)
-- Returns false and optional error message on error
function StorageSQLite:GetGroupAreaCount(a_GroupName)
	-- Check params:
	assert(self)
	assert(type(a_GroupName) == "string")

	-- Get the count from the DB:
	local res
	local IsSuccess, Msg = self:ExecuteStatement(
		"SELECT COUNT(*) AS Cnt FROM Areas WHERE IsApproved = 1 AND ExportGroupName = ?",
		{
			a_GroupName
		},
		function (a_Values)
			res = a_Values["Cnt"]
		end
	)
	if not(IsSuccess) then
		return false, Msg
	end
	return res
end





--- Returns the number of approved areas in the specified export group that have the IsStarting metadata set
-- Returns zero if no area in the group (group doesn't exist)
-- Returns false and optional error message on error
function StorageSQLite:GetGroupStartingAreaCount(a_GroupName)
	-- Check params:
	assert(self)
	assert(type(a_GroupName) == "string")

	-- Get the count from the DB:
	local res
	local IsSuccess, Msg = self:ExecuteStatement(
		"SELECT COUNT(*) AS Cnt FROM Areas LEFT JOIN MetaData ON Areas.ID = Metadata.AreaID WHERE \
		  Areas.IsApproved = 1 AND Areas.ExportGroupName = ? AND Metadata.Name = 'IsStarting' AND CAST(Metadata.Value AS NUMBER) = 1",
		{
			a_GroupName
		},
		function (a_Values)
			res = a_Values["Cnt"]
		end
	)
	if not(IsSuccess) then
		return false, Msg
	end
	return res
end





--- Retrieves the last status of the specified check
-- Returns a table describing the check status on success, or false and optional message on failure
function StorageSQLite:GetMaintenanceCheckStatus(a_CheckName)
	-- Check params:
	assert(self)
	assert(type(a_CheckName) == "string")

	-- Load from DB:
	local res
	local IsSuccess, Msg = self:ExecuteStatement(
		"SELECT * FROM LastMaintenanceCheckStatus WHERE CheckName = ?",
		{
			a_CheckName
		},
		function (a_Values)
			res = a_Values
		end
	)
	if not(IsSuccess) or not(res) then
		return false, Msg
	end

	return res
end





--- Retrieves the metadata for the specified area, as a dict table {"name" -> "value"}
-- If a_IncludeDefaults is true, the defaults are added to the result, producing the full set of metadata
function StorageSQLite:GetMetadataForArea(a_AreaID, a_IncludeDefaults)
	-- Check params:
	assert(self)
	local AreaID = tonumber(a_AreaID)
	assert(AreaID)

	-- Load from DB:
	local res = {}
	local IsSuccess, Msg = self:ExecuteStatement(
		"SELECT Name, Value FROM Metadata WHERE AreaID = ?",
		{ AreaID },
		function (a_Values)
			res[a_Values.Name] = a_Values.Value
		end
	)
	if not(IsSuccess) then
		return nil, Msg
	end

	-- Add the defaults:
	if (a_IncludeDefaults) then
		for k, v in pairs(g_MetadataDefaults) do
			res[k] = res[k] or v
		end
	end

	return res
end





--- Retrieves the metadata for the specified group, as a dict table {"name" -> "value"}
-- Returns the dictionary table on success, or false and error message on failure
function StorageSQLite:GetMetadataForGroup(a_GroupName)
	-- Check params:
	assert(self)
	assert(type(a_GroupName) == "string")

	-- Load from DB:
	local res = {}
	local IsSuccess, Msg = self:ExecuteStatement(
		"SELECT Name, Value FROM GroupMetadata WHERE GroupName = ?",
		{ a_GroupName },
		function (a_Values)
			res[a_Values.Name] = a_Values.Value
		end
	)
	if not(IsSuccess) then
		return false, Msg
	end
	return res
end





--- Returns the total number of approved areas
-- Returns false and optional error message on failure
function StorageSQLite:GetNumApprovedAreas()
	local res
	local IsSuccess, Msg = self:ExecuteStatement(
		"SELECT COUNT(*) as Count FROM Areas WHERE IsApproved = ?",
		{ 1 },
		function (a_Values)
			res = a_Values["Count"]
		end
	)
	if not(IsSuccess) then
		return false, Msg
	end
	return res
end





--- Retrieves a map of AreaID => true for all areas that have been sponged
-- Areas that are not sponged are not in the map at all
-- Returns false and optional message on error
function StorageSQLite:GetSpongedAreaIDsMap()
	-- Check params:
	assert(self)

	-- Load data from the DB:
	local res = {}
	local IsSuccess, Msg = self:ExecuteStatement(
		"SELECT AreaID FROM ExportSponges",
		nil,
		function (a_Values)
			res[a_Values.AreaID] = true
		end
	)
	if not(IsSuccess) then
		return false, Msg
	end

	return res
end





--- Retrieves the sponges for the specified area
-- Returns a cBlockArea representing the whole area (MinX to MaxX etc), where sponges should be put
-- Returns nil and message on error
function StorageSQLite:GetSpongesForArea(a_AreaID)
	-- Check params:
	assert(self)
	local AreaID = tonumber(a_AreaID)
	assert(AreaID)

	-- Load data from DB:
	local SpongeSchematic
	local IsSuccess, Msg = self:ExecuteStatement(
		"SELECT Sponges FROM ExportSponges WHERE AreaID = ?",
		{
			AreaID
		},
		function (a_Values)
			SpongeSchematic = a_Values.Sponges
		end
	)
	if not(IsSuccess) then
		return nil, Msg
	end

	-- If the sponge hasn't been saved in the DB, bail out:
	if ((SpongeSchematic == nil) or (SpongeSchematic == "")) then
		return nil, "there are no sponges saved for this area"
	end

	-- Create the block area from the data:
	local Sponges = cBlockArea()
	if not(Sponges:LoadFromSchematicString(Base64Decode(SpongeSchematic))) then
		return nil, "cannot decode the stored schematic"
	end
	return Sponges
end





--- Returns whether the specified area has a sponge defined
-- Returns nil and optional error message on failure
function StorageSQLite:HasSponge(a_AreaID)
	-- Check params:
	assert(self)
	local AreaID = tonumber(a_AreaID)
	assert(AreaID)

	-- Query the DB:
	local res
	local IsSuccess, Msg = self:ExecuteStatement(
		"SELECT COUNT(*) AS Count FROM ExportSponges WHERE AreaID = ?",
		{ AreaID },
		function (a_Values)
			res = (a_Values.Count > 0)
		end
	)
	if not(IsSuccess) then
		return nil, Msg
	end

	return res
end





--- Returns whether the specified area has the IsStarting metadata set to 1
-- Returns nil and optional error message on failure
function StorageSQLite:IsAreaStarting(a_AreaID)
	-- Check params:
	assert(self)
	local AreaID = tonumber(a_AreaID)
	assert(AreaID)

	local res = false
	local IsSuccess, Msg = self:ExecuteStatement(
		"SELECT Value FROM Metadata WHERE AreaID = ? AND Name = 'IsStarting'",
		{ AreaID },
		function (a_Values)
			res = (a_Values ~= "0")
		end
	)
	if not(IsSuccess) then
		return nil, Msg
	end

	return res
end





--- Returns an array of tables describing the approved areas in the specified range
-- Returns false and optional error message on failure
function StorageSQLite:LoadApprovedAreasRange(a_StartIdx, a_EndIdx)
	-- Check params:
	assert(self)
	assert(tonumber(a_StartIdx))
	assert(tonumber(a_EndIdx))

	-- Load from the DB:
	local res = {}
	local IsSuccess, Msg = self:ExecuteStatement(
		"SELECT * FROM Areas WHERE IsApproved = 1 ORDER BY ExportGroupName ASC, ID LIMIT ? OFFSET ?",
		{
			a_EndIdx - a_StartIdx,
			a_StartIdx
		},
		function (a_Values)
			-- Require the area to have at least the ID:
			if (a_Values.ID) then
				table.insert(res, a_Values)
			end
		end
	)
	if not(IsSuccess) then
		-- DB error or no data (?)
		return false, Msg
	end

	return res
end





--- Locks all areas that are approved
-- Returns true on success, false and optional error msg on failure
function StorageSQLite:LockApprovedAreas()
	return self:ExecuteStatement(
		"UPDATE Areas SET IsLocked = 1, DateLastChanged = ? WHERE (CAST(IsApproved AS NUMBER) = 1) AND (CAST(IsLocked AS NUMBER) <> 0)",
		{ FormatDateTime(os.time()) }
	)
end





--- Sets the specified area's DateLastChanged to current time
-- Called from all relevant other SQLite access functions
-- Returns true on success, false and optional error msg on failure
function StorageSQLite:MarkAreaChangedNow(a_AreaID)
	-- Check params:
	assert(self)
	assert(type(a_AreaID) == "number")

	-- Retrieve the world name from the DB:
	local worldName
	local isSuccess, msg = self:ExecuteStatement(
		"SELECT WorldName FROM Areas WHERE ID = ?",
		{ a_AreaID },
		function(a_Values)
			worldName = a_Values.WorldName
		end
	)
	if not(worldName) then
		return false, "Cannot query worldname for area: " .. (msg or "<no message>")
	end

	local world = cRoot:Get():GetWorld(worldName)
	if not(world) then
		return false, "Invalid world for the area"
	end
	local tick = world:GetWorldAge()

	-- Update the DB:
	return self:ExecuteStatement(
		"UPDATE Areas SET DateLastChanged = ?, TickLastChanged = ? WHERE ID = ?",
		{
			FormatDateTime(os.time()), tick, a_AreaID
		}
	)
end





--- Sets the specified connector's area's DateLastChanged to current time
-- Called from all relevant SQLite access functions handling connectors
-- Returns true on success, false and optional error msg on failure
function StorageSQLite:MarkConnectorsAreaChangedNow(a_ConnID)
	-- Check params:
	assert(self)
	assert(type(a_ConnID) == "number")

	-- Get the AreaID of the connector:
	local AreaID
	local IsSuccess, Msg = self:ExecuteStatement("SELECT AreaID FROM Connectors WHERE ID = ?", {a_ConnID},
		function (a_Values)
			AreaID = a_Values["AreaID"]
		end
	)
	if not(IsSuccess) then
		return false, "Failed to get connector's AreaID: " .. (Msg or "<unknown error>")
	end

	-- Mark the area as changed:
	if (AreaID) then
		return self:MarkAreaChangedNow(AreaID)
	end

	return false, "Connector's Area ID not found in the DB"
end





--- Renames the group in the DB, by overwriting the group name of all areas that use the a_FromName and changing the metadata
-- Returns false and error message on failure, or true on success
function StorageSQLite:RenameGroup(a_FromName, a_ToName)
	-- Check params:
	assert(self)
	assert(type(a_FromName) == "string")
	assert(type(a_ToName) == "string")

	-- Rename:
	local IsSuccess, Msg = self:ExecuteStatement(
		"UPDATE Areas SET ExportGroupName = ? WHERE ExportGroupName = ?",
		{
			a_ToName, a_FromName
		}
	)
	if not(IsSuccess) then
		return false, Msg
	end
	return self:ExecuteStatement(
		"UPDATE GroupMetadata SET GroupName = ? WHERE GroupName = ?",
		{
			a_ToName, a_FromName
		}
	)
end





--- Sets the area's ExportGroup name
-- Returns false and error message on failure, or true on success
function StorageSQLite:SetAreaExportGroup(a_AreaID, a_GroupName)
	-- Check params:
	assert(self)
	assert(tonumber(a_AreaID))
	assert(type(a_GroupName) == "string")

	-- Update in DB:
	local IsSuccess, Msg = self:ExecuteStatement(
		"UPDATE Areas SET ExportGroupName = ? WHERE ID = ?",
		{
			a_GroupName, a_AreaID
		}
	)
	if not(IsSuccess) then
		return false, "Failed to update area in the DB: " .. (Msg or "<unknown DB error>")
	end

	-- Mark the area as changed:
	self:MarkAreaChangedNow(a_AreaID)

	return true
end





--- Sets the area's ExportName
-- Returns false and error message on failure, or true on success
function StorageSQLite:SetAreaExportName(a_AreaID, a_AreaName)
	-- Check params:
	assert(self)
	assert(tonumber(a_AreaID))
	assert(type(a_AreaName) == "string")

	-- Rename in DB:
	local IsSuccess, Msg = self:ExecuteStatement(
		"UPDATE Areas SET ExportName = ? WHERE ID = ?",
		{
			a_AreaName, a_AreaID
		}
	)
	if not(IsSuccess) then
		return false, "Failed to update area in the DB: " .. (Msg or "<unknown DB error>")
	end

	-- Mark the area as changed:
	self:MarkAreaChangedNow(a_AreaID)

	return true
end





--- Sets the area's metadata value in the DB
-- Returns true on success, false and optional message on failure
function StorageSQLite:SetAreaMetadata(a_AreaID, a_Name, a_Value)
	-- Check params:
	assert(self)
	local AreaID = tonumber(a_AreaID)
	assert(AreaID)
	assert(type(a_Name) == "string")

	-- Remove any previous value:
	local IsSuccess, Msg = self:ExecuteStatement(
		"DELETE FROM Metadata WHERE AreaID = ? AND Name = ?",
		{
			AreaID, a_Name
		}
	)
	if not(IsSuccess) then
		return false, "Failed to remove old value: " .. (Msg or "<no details>")
	end

	-- Add the new value:
	if (a_Value and (a_Value ~= "")) then
		IsSuccess, Msg = self:ExecuteStatement(
			"INSERT INTO Metadata (AreaID, Name, Value) VALUES (?, ?, ?)",
			{
				AreaID, a_Name, a_Value
			}
		)
		if not(IsSuccess) then
			return false, "Failed to set new value: " .. (Msg or "<no details>")
		end
	end

	-- Mark the area as changed:
	self:MarkAreaChangedNow(a_AreaID)

	return true
end





--- Sets the sponging in the DB for the selected area
-- a_Sponging is the area containing only sponge blocks or air, inside a cBlockArea object
-- Returns true on success, false and message on failure
function StorageSQLite:SetAreaSponging(a_AreaID, a_Sponging)
	-- Check the params:
	assert(self)
	local AreaID = tonumber(a_AreaID)
	assert(AreaID)
	assert(tolua.type(a_Sponging) == "cBlockArea")

	-- Remove all existing sponges for the specified area:
	local IsSuccess, Msg = self:ExecuteStatement(
		"DELETE FROM ExportSponges WHERE AreaID = ?",
		{
			AreaID
		}
	)
	if not(IsSuccess) then
		return false, Msg
	end

	-- Convert the sponging into DB-friendly representation:
	local SchematicData = a_Sponging:SaveToSchematicString()
	local AreaRep = Base64Encode(SchematicData)

	-- Save the sponge area into the DB:
	IsSuccess, Msg = self:ExecuteStatement(
		"INSERT INTO ExportSponges (AreaID, Sponges) VALUES (?, ?)",
		{
			AreaID,
			AreaRep
		}
	)
	if not(IsSuccess) then
		return false, "Failed to update area sponges in the DB: " .. (Msg or "<unknown DB error>")
	end

	-- Mark the area as changed:
	self:MarkAreaChangedNow(AreaID)

	return true
end





--- Sets the metadata value for the specified group.
-- Returns true on success, false and optional message on failure
function StorageSQLite:SetGroupMetadata(a_GroupName, a_Name, a_Value)
	-- Check params:
	assert(self)
	assert(type(a_GroupName) == "string")
	assert(type(a_Name) == "string")

	-- Remove any previous value:
	local IsSuccess, Msg = self:ExecuteStatement(
		"DELETE FROM GroupMetadata WHERE GroupName = ? AND Name = ?",
		{
			a_GroupName, a_Name
		}
	)
	if not(IsSuccess) then
		return false, "Failed to remove old value: " .. (Msg or "<no details>")
	end

	-- Add the new value:
	if (a_Value and (a_Value ~= "")) then
		IsSuccess, Msg = self:ExecuteStatement(
			"INSERT INTO GroupMetadata (GroupName, Name, Value) VALUES (?, ?, ?)",
			{
				a_GroupName, a_Name, a_Value
			}
		)
		if not(IsSuccess) then
			return false, "Failed to set new value: " .. (Msg or "<no details>")
		end
	end

	return true
end





--- Stores the last result of the specified check
-- Returns true on success, or false and optional message on failure
function StorageSQLite:SetMaintenanceCheckStatus(a_CheckName, a_Result)
	-- Check params:
	assert(self)
	assert(type(a_CheckName) == "string")
	assert(a_Result)

	-- Delete the previous result:
	local IsSuccess, Msg = self:ExecuteStatement(
		"DELETE FROM LastMaintenanceCheckStatus WHERE CheckName = ?",
		{
			a_CheckName
		}
	)
	if not(IsSuccess) then
		return false, Msg
	end

	-- Store the new result:
	IsSuccess, Msg = self:ExecuteStatement(
		"INSERT INTO LastMaintenanceCheckStatus (CheckName, DateTime, Result) VALUES (?, ?, ?)",
		{
			a_CheckName, FormatDateTime(os.time()), a_Result
		}
	)
	if not(IsSuccess) then
		return false, Msg
	end

	return true
end





--- Sets the specified connector's position
-- Returns true on success, false and possibly an error message on failure
function StorageSQLite:SetConnectorPos(a_ConnID, a_NewX, a_NewY, a_NewZ)
	-- Check params:
	assert(self)
	local ConnID = tonumber(a_ConnID)
	assert(ConnID)
	local NewX, NewY, NewZ = tonumber(a_NewX), tonumber(a_NewY), tonumber(a_NewZ)
	assert(NewX)
	assert(NewY)
	assert(NewZ)

	-- Update in the DB:
	local IsSuccess, Msg = self:ExecuteStatement(
		"UPDATE Connectors SET X = ?, Y = ?, Z = ? WHERE ID = ?",
		{
			NewX, NewY, NewZ, ConnID
		}
	)
	if not(IsSuccess) then
		return false, "Failed to update connector in the DB: " .. (Msg or "<unknown DB error>")
	end

	-- Mark the area as changed:
	self:MarkConnectorsAreaChangedNow(ConnID)
end





--- Returns true if the table exists in the DB
function StorageSQLite:TableExists(a_TableName)
	-- Check params:
	assert(self)
	assert(type(a_TableName) == "string")

	-- Check existence:
	local res = false
	self:ExecuteStatement(
		"SELECT name FROM sqlite_master WHERE type='table' AND name=?",
		{a_TableName},
		function(a_Values)
			res = (a_Values.name == a_TableName)
		end
	)
	return res
end





--- Unlocks all areas
-- Returns true on success, false and optional message on failure
function StorageSQLite:UnlockAllAreas()
	-- Check params:
	assert(self)

	return self:ExecuteStatement(
		"UPDATE Areas SET IsLocked = 0, DateLastChanged = ? WHERE CAST(IsLocked AS NUMBER) = 1"
	)
end





--- Unsets the area's metadata value in the DB
-- Returns true on success, false and optional message on failure
function StorageSQLite:UnsetAreaMetadata(a_AreaID, a_Name)
	-- Check params:
	assert(self)
	local AreaID = tonumber(a_AreaID)
	assert(AreaID)
	assert(type(a_Name) == "string")

	-- Remove the value:
	local IsSuccess, Msg = self:ExecuteStatement(
		"DELETE FROM Metadata WHERE AreaID = ? AND Name = ?",
		{
			AreaID, a_Name
		}
	)
	if not(IsSuccess) then
		return false, "Failed to remove old value: " .. (Msg or "<no details>")
	end

	-- Mark the area as changed:
	self:MarkAreaChangedNow(AreaID)

	return true
end





--- Unsets the group's metadata value in the DB
-- Returns true on success, false and optional message on failure
function StorageSQLite:UnsetGroupMetadata(a_GroupName, a_Name)
	-- Check params:
	assert(self)
	assert(type(a_GroupName) == "string")
	assert(type(a_Name) == "string")

	-- Remove the value:
	local IsSuccess, Msg = self:ExecuteStatement(
		"DELETE FROM GroupMetadata WHERE GroupName = ? AND Name = ?",
		{
			a_GroupName, a_Name
		}
	)
	if not(IsSuccess) then
		return false, "Failed to remove old value: " .. (Msg or "<no details>")
	end
	return true
end





--- Updates the export bbox in the DB to the specified values
-- Returns false and error message on failure, or true on success
function StorageSQLite:UpdateAreaBBox(a_AreaID, a_MinX, a_MinY, a_MinZ, a_MaxX, a_MaxY, a_MaxZ)
	-- Check the params:
	assert(self)
	assert(tonumber(a_AreaID))
	assert(tonumber(a_MinX))
	assert(tonumber(a_MinY))
	assert(tonumber(a_MinZ))
	assert(tonumber(a_MaxX))
	assert(tonumber(a_MaxY))
	assert(tonumber(a_MaxZ))

	-- Write into DB:
	local IsSuccess, Msg = self:ExecuteStatement(
		"UPDATE Areas SET ExportMinX = ?, ExportMinY = ?, ExportMinZ = ?, ExportMaxX = ?, ExportMaxY = ?, ExportMaxZ = ? WHERE ID = ?",
		{
			a_MinX, a_MinY, a_MinZ, a_MaxX, a_MaxY, a_MaxZ,
			a_AreaID
		}
	)
	if not(IsSuccess) then
		return false, "Failed to update area in the DB: " .. (Msg or "<unknown DB error>")
	end

	-- Mark the area as changed:
	self:MarkAreaChangedNow(a_AreaID)

	return true
end





--- Updates the hitbox in the DB to the specified values
-- Returns false and error message on failure, or true on success
function StorageSQLite:UpdateAreaHBox(a_AreaID, a_MinX, a_MinY, a_MinZ, a_MaxX, a_MaxY, a_MaxZ)
	-- Check the params:
	assert(self)
	assert(tonumber(a_AreaID))
	assert(tonumber(a_MinX))
	assert(tonumber(a_MinY))
	assert(tonumber(a_MinZ))
	assert(tonumber(a_MaxX))
	assert(tonumber(a_MaxY))
	assert(tonumber(a_MaxZ))

	-- Write into DB:
	local IsSuccess, Msg = self:ExecuteStatement(
		"UPDATE Areas SET HitboxMinX = ?, HitboxMinY = ?, HitboxMinZ = ?, HitboxMaxX = ?, HitboxMaxY = ?, HitboxMaxZ = ? WHERE ID = ?",
		{
			a_MinX, a_MinY, a_MinZ, a_MaxX, a_MaxY, a_MaxZ,
			a_AreaID
		}
	)
	if not(IsSuccess) then
		return false, "Failed to update area in the DB: " .. (Msg or "<unknown DB error>")
	end

	-- Mark the area as changed:
	self:MarkAreaChangedNow(a_AreaID)

	return true
end





--- Updates all the sponges in the DB for the selected area, based on the area's image
-- a_SpongedBlockArea is the area containing the sponge blocks; the sponge blocks are extracted and saved to DB
-- Returns true on success, false and message on failure
function StorageSQLite:UpdateAreaSponges(a_AreaID, a_SpongedBlockArea)
	-- Check the params:
	assert(self)
	assert(tolua.type(a_SpongedBlockArea) == "cBlockArea")

	-- Create a block area that has sponges where a_SpongedBlockArea has sponges, and air everywhere else:
	local BA = cBlockArea()
	BA:CopyFrom(a_SpongedBlockArea)
	BA:Fill(cBlockArea.baTypes + cBlockArea.baMetas, E_BLOCK_SPONGE, 0)
	BA:Merge(a_SpongedBlockArea, 0, 0, 0, cBlockArea.msMask)

	-- Update in the DB:
	local IsSuccess, Msg = self:SetAreaSponging(a_AreaID, BA)
	BA:Clear()
	if not(IsSuccess) then
		return false, "Failed to set area's sponging in the DB: " .. (Msg or "<unknown DB error>")
	end

	-- Mark the area as changed:
	self:MarkAreaChangedNow(a_AreaID)

	return true
end





function SQLite_CreateStorage(a_Params)
	local res = {}
	SQLite_extend(res)  -- Extend with basic SQLite functions (SQLite.lua)

	-- Extend the object with StorageSQLite methods:
	for k, v in pairs(StorageSQLite) do
		assert(not(res[k]))
		res[k] = v
	end

	-- Open the DB:
	local DBFile = a_Params.File or "Galleries.sqlite"
	local isSuccess, errCode, errMsg = res:OpenDB(DBFile)
	if not(isSuccess) then
		LOGWARNING(PLUGIN_PREFIX .. "Cannot open database \"" .. DBFile .. "\": " .. errMsg or "<no message>")
		error(errMsg or "<no message>")  -- Abort the plugin
	end

	-- Create the tables, if they don't exist yet:
	local AreasColumns =
	{
		{"IsApproved",       "INTEGER"},  -- Simple 0 / 1
		{"DateApproved",     "TEXT"},     -- ISO 8601 DateTime of the approving
		{"ApprovedBy",       "TEXT"},     -- Name of the admin who approved the area
		{"ExportMinX",       "INTEGER"},  -- The min coords of the exported area
		{"ExportMinY",       "INTEGER"},  -- The min coords of the exported area
		{"ExportMinZ",       "INTEGER"},  -- The min coords of the exported area
		{"ExportMaxX",       "INTEGER"},  -- The max coords of the exported area
		{"ExportMaxY",       "INTEGER"},  -- The max coords of the exported area
		{"ExportMaxZ",       "INTEGER"},  -- The max coords of the exported area
		{"ExportGroupName",  "TEXT"},     -- The name of the group to which this area belongs
		{"ExportName",       "TEXT"},     -- The name of the area to use for export. If NULL, the ID is used
		{"HitboxMinX",       "INTEGER"},  -- The min coords of the exported area's hitbox. If NULL, ExportMin coords are used
		{"HitboxMinY",       "INTEGER"},  -- The min coords of the exported area's hitbox. If NULL, ExportMin coords are used
		{"HitboxMinZ",       "INTEGER"},  -- The min coords of the exported area's hitbox. If NULL, ExportMin coords are used
		{"HitboxMaxX",       "INTEGER"},  -- The max coords of the exported area's hitbox. If NULL, ExportMax coords are used
		{"HitboxMaxY",       "INTEGER"},  -- The max coords of the exported area's hitbox. If NULL, ExportMax coords are used
		{"HitboxMaxZ",       "INTEGER"},  -- The max coords of the exported area's hitbox. If NULL, ExportMax coords are used
		{"StructureBoxMinX", "INTEGER"},  -- The min coords of the exported area's StructureBox. If NULL, ExportMin coords are used
		{"StructureBoxMinY", "INTEGER"},  -- The min coords of the exported area's StructureBox. If NULL, ExportMin coords are used
		{"StructureBoxMinZ", "INTEGER"},  -- The min coords of the exported area's StructureBox. If NULL, ExportMin coords are used
		{"StructureBoxMaxX", "INTEGER"},  -- The max coords of the exported area's StructureBox. If NULL, ExportMax coords are used
		{"StructureBoxMaxY", "INTEGER"},  -- The max coords of the exported area's StructureBox. If NULL, ExportMax coords are used
		{"StructureBoxMaxZ", "INTEGER"},  -- The max coords of the exported area's StructureBox. If NULL, ExportMax coords are used
	}
	local ExportSpongesColumns =
	{
		{"AreaID",  "INTEGER PRIMARY KEY"},  -- ID of the area to which the sponges belong. Note that the area needn't be approved
		{"Sponges", "BLOB"},                 -- BLOB containing the base64-ed .schematic representation of the sponges (just air + sponges)
	}
	local ConnectorsColumns =
	{
		{"ID",        "INTEGER PRIMARY KEY"},  -- ID of the connector
		{"AreaID",    "INTEGER"},              -- ID of the area to which the connector belongs. Note that the area needn't be approved
		{"X",         "INTEGER"},              -- (World) Coords of the connector
		{"Y",         "INTEGER"},              -- (World) Coords of the connector
		{"Z",         "INTEGER"},              -- (World) Coords of the connector
		{"Direction", "INTEGER"},              -- Direction of the connector
		{"TypeNum",   "INTEGER"},              -- Type of the connector (only same-type connectors will be connected in the generator)
	}
	local MetadataColumns =
	{
		{"AreaID", "INTEGER"},  -- ID of the area for which the metadata is defined
		{"Name",   "TEXT"},     -- Name of the metadata item
		{"Value",  "BLOB"},     -- Value of the metadata item
	}
	local GroupMetadataColumns =
	{
		{"GroupName", "TEXT"},
		{"Name",      "TEXT"},
		{"Value",     "BLOB"},
	}
	local LastMaintenanceCheckStatusColumns =
	{
		{"CheckName", "TEXT"},  -- Name of the check; key
		{"DateTime",  "TEXT"},  -- ISO-formatted date and time of the check
		{"Result",    "BLOB"},  -- Check results, in a per-check-specific format
	}
	if (
		not(res:TableExists("Areas")) or
		not(res:CreateDBTable("Areas",                      AreasColumns)) or
		not(res:CreateDBTable("ExportSponges",              ExportSpongesColumns)) or
		not(res:CreateDBTable("Connectors",                 ConnectorsColumns)) or
		not(res:CreateDBTable("Metadata",                   MetadataColumns)) or
		not(res:CreateDBTable("GroupMetadata",              GroupMetadataColumns)) or
		not(res:CreateDBTable("LastMaintenanceCheckStatus", LastMaintenanceCheckStatusColumns))
	) then
		LOGWARNING(PLUGIN_PREFIX .. "Cannot create DB tables!")
		error("Cannot create DB tables!")
	end

	-- Returns the initialized database access object
	return res
end




