
-- Storage_SQLite.lua

-- Implements the SQLite-backed database storage





--- The SQLite backend namespace:
local SQLite = {}





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
	
	-- Whether the area should expand its lowest level towards the nearest non-air block; 0 or 1
	["ShouldExpandFloor"] = 1,
	
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
function SQLite:AddConnector(a_AreaID, a_BlockX, a_BlockY, a_BlockZ, a_Direction, a_Type)
	-- Check params:
	assert(self)
	local AreaID = tonumber(a_AreaID)
	assert(AreaID)
	assert(type(a_BlockX) == "number")
	assert(type(a_BlockY) == "number")
	assert(type(a_BlockZ) == "number")
	assert(type(a_Direction) == "number")
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
	
	-- Return the connector ident by loading the area:
	return self:GetConnectorByID(RowID)
end





--- Sets the area as approved by the specified player in the specified group and with the specified export cuboid
-- If the area is already approved, returns false, the name of the approver, date approved and the group name
-- If any of the DB queries fail, returns nil.
-- Returns true on success
function SQLite:ApproveArea(a_AreaID, a_PlayerName, a_GroupName, a_ExportCuboid, a_AreaName)
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
	
	-- Report success
	return true
end





--- Changes the position of the specified connector in the DB
-- Returns true on success, false and potentially a message on failure
function SQLite:ChangeConnectorPos(a_ConnID, a_NewX, a_NewY, a_NewZ)
	-- Check params:
	assert(self)
	local ConnID = tonumber(a_ConnID)
	assert(ConnID)
	local NewX, NewY, NewZ = tonumber(a_NewX), tonumber(a_NewY), tonumber(a_NewZ)
	assert(NewX)
	assert(NewY)
	assert(NewZ)
	
	return self:ExecuteStatement(
		"UPDATE Connectors SET X = ?, Y = ?, Z = ? WHERE ID = ?",
		{
			NewX, NewY, NewZ, ConnID
		}
	)
end





--- Changes the type of the specified connector in the DB
-- Returns true on success, false and potentially a message on failure
function SQLite:ChangeConnectorType(a_ConnID, a_NewType)
	-- Check params:
	assert(self)
	local ConnID = tonumber(a_ConnID)
	assert(ConnID)
	local NewType = tonumber(a_NewType)
	assert(NewType)
	
	return self:ExecuteStatement(
		"UPDATE Connectors SET TypeNum = ? WHERE ID = ?",
		{
			NewType, ConnID
		}
	)
end





--- Creates the table of the specified name and columns[]
-- If the table exists, any columns missing are added; existing data is kept
function SQLite:CreateDBTable(a_TableName, a_Columns)
	-- Check params:
	assert(self)
	assert(a_TableName)
	assert(a_Columns)
	
	-- Try to create the table first
	local sql = "CREATE TABLE IF NOT EXISTS '" .. a_TableName .. "' ("
	sql = sql .. table.concat(a_Columns, ", ") .. ")"
	local ExecResult = self.DB:exec(sql)
	if (ExecResult ~= sqlite3.OK) then
		LOGWARNING(PLUGIN_PREFIX .. "Cannot create DB Table " .. a_TableName .. ": " .. ExecResult)
		LOGWARNING(PLUGIN_PREFIX .. "Command: \"" .. sql .. "\".")
		return false
	end
	-- SQLite doesn't inform us if it created the table or not, so we have to continue anyway
	
	-- Check each column whether it exists
	-- Remove all the existing columns from a_Columns:
	local RemoveExistingColumn = function(a_Values)
		if (a_Values.name) then
			local ColumnName = a_Values.name:lower()
			-- Search the a_Columns if they have that column:
			for j = 1, #a_Columns do
				-- Cut away all column specifiers (after the first space), if any:
				local SpaceIdx = string.find(a_Columns[j], " ")
				if (SpaceIdx) then
					SpaceIdx = SpaceIdx - 1
				end
				local ColumnTemplate = string.lower(string.sub(a_Columns[j], 1, SpaceIdx))
				-- If it is a match, remove from a_Columns:
				if (ColumnTemplate == ColumnName) then
					table.remove(a_Columns, j)
					break  -- for j
				end
			end  -- for j - a_Columns[]
		end  -- if (a_Values.name)
	end
	if (not(self:ExecuteStatement("PRAGMA table_info(" .. a_TableName .. ")", {}, RemoveExistingColumn))) then
		LOGWARNING(PLUGIN_PREFIX .. "Cannot query DB table structure")
		return false
	end
	
	-- Create the missing columns
	-- a_Columns now contains only those columns that are missing in the DB
	if (#a_Columns > 0) then
		LOGINFO(PLUGIN_PREFIX .. "Database table \"" .. a_TableName .. "\" is missing " .. #a_Columns .. " columns, fixing now.")
		for idx, ColumnName in ipairs(a_Columns) do
			if (not(self:ExecuteStatement("ALTER TABLE '" .. a_TableName .. "' ADD COLUMN '" .. ColumnName .. "'", {}))) then
				LOGWARNING(PLUGIN_PREFIX .. "Cannot add DB table \"" .. a_TableName .. "\" column \"" .. ColumnName .. "\"")
				return false
			end
		end
		LOGINFO(PLUGIN_PREFIX .. "Database table \"" .. a_TableName .. "\" columns fixed.")
	end
	
	return true
end





--- Deletes the specified connector from the DB
-- Returns true if successful, false and potentially an error message on failure
function SQLite:DeleteConnector(a_ConnID)
	-- Check params:
	assert(self)
	local ConnID = tonumber(a_ConnID)
	assert(ConnID)
	
	-- Delete from the DB:
	return self:ExecuteStatement(
		"DELETE FROM Connectors WHERE ID = ?",
		{ ConnID }
	)
end





--- Sets the area (specified by its ID) as not approved. Keeps all the other data for the area
-- Returns true on success, false and optional message on failure
-- Invalid / non-approved AreaIDs will be reported as success!
function SQLite:DisapproveArea(a_AreaID)
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
	return IsSuccess, Msg
end





--- Executes the SQL statement, substituting "?" in the SQL with the specified params
-- Calls a_Callback for each row
-- The callback receives a dictionary table containing the row values (stmt:nrows())
-- Returns false and error message on failure, or true on success
function SQLite:ExecuteStatement(a_SQL, a_Params, a_Callback, a_RowIDCallback)
	-- Check params:
	assert(self)
	assert(a_SQL)
	assert((a_Params == nil) or (type(a_Params) == "table"))
	assert(self.DB)
	assert((a_Callback == nil) or (type(a_Callback) == "function"))
	assert((a_RowIDCallback == nil) or (type(a_RowIDCallback) == "function"))
	
	-- Prepare the statement (SQL-compile):
	local Stmt, ErrCode, ErrMsg = self.DB:prepare(a_SQL)
	if (Stmt == nil) then
		ErrMsg = (ErrCode or "<unknown>") .. " (" .. (ErrMsg or "<no message>") .. ")"
		LOGWARNING(PLUGIN_PREFIX .. "Cannot prepare SQL \"" .. a_SQL .. "\": " .. ErrMsg)
		LOGWARNING(PLUGIN_PREFIX .. "  Params = {" .. table.concat(a_Params or {}, ", ") .. "}")
		return nil, ErrMsg
	end
	
	-- Bind the values into the statement:
	if (a_Params) then
		ErrCode = Stmt:bind_values(unpack(a_Params))
		if ((ErrCode ~= sqlite3.OK) and (ErrCode ~= sqlite3.DONE)) then
			ErrMsg = (ErrCode or "<unknown>") .. " (" .. (self.DB:errmsg() or "<no message>") .. ")"
			LOGWARNING(PLUGIN_PREFIX .. "Cannot bind values to statement \"" .. a_SQL .. "\": " .. ErrMsg)
			Stmt:finalize()
			return nil, ErrMsg
		end
	end
	
	-- Step the statement:
	if (a_Callback == nil) then
		ErrCode = Stmt:step()
		if ((ErrCode ~= sqlite3.ROW) and (ErrCode ~= sqlite3.DONE)) then
			ErrMsg = (ErrCode or "<unknown>") .. " (" .. (self.DB:errmsg() or "<no message>") .. ")"
			LOGWARNING(PLUGIN_PREFIX .. "Cannot step statement \"" .. a_SQL .. "\": " .. ErrMsg)
			Stmt:finalize()
			return nil, ErrMsg
		end
		if (a_RowIDCallback) then
			a_RowIDCallback(self.DB:last_insert_rowid())
		end
	else
		-- Iterate over all returned rows:
		for v in Stmt:nrows() do
			a_Callback(v)
		end
		
		if (a_RowIDCallback) then
			a_RowIDCallback(self.DB:last_insert_rowid())
		end
	end
	Stmt:finalize()
	return true
end





--- Returns an array of tables describing all the approved areas
-- Each sub-table has all the attributes read from the DB row
-- Returns an empty table if there are no approved areas
-- Returns nil on DB error
function SQLite:GetAllApprovedAreas()
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
function SQLite:GetAllConnectors()
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
function SQLite:GetAllGroupNames()
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





--- Returns a table describing the area at the specified coords
-- The table has all the attributes read from the DB row
-- Returns nil if there's no area at those coords
function SQLite:GetAreaByCoords(a_WorldName, a_BlockX, a_BlockZ)
	-- Check params:
	assert(self)
	assert(type(a_WorldName) == "string")
	assert(type(a_BlockX) == "number")
	assert(type(a_BlockZ) == "number")
	
	-- Load from the DB:
	local res = {}
	if not(self:ExecuteStatement(
		"SELECT * FROM Areas WHERE (MinX <= ?) AND (MaxX > ?) AND (MinZ < ?) AND (MaxZ > ?)",
		{
			a_BlockX, a_BlockX,
			a_BlockZ, a_BlockZ,
		},
		function (a_Values)
			-- Copy all values to the result table:
			for k, v in pairs(a_Values) do
				res[k] = v
			end
		end
	)) then
		-- DB error or no data (?)
		return nil
	end
	
	if not(res.ID) then
		-- No data has been returned by the DB call
		return nil
	end
	
	return res
end





--- Returns a table describing the area of the specified ID
-- The table has all the attributes read from the DB row
-- Returns nil and possibly an error message if there's no area with such ID or there's a DB error
function SQLite:GetAreaByID(a_AreaID)
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
function SQLite:GetAreaConnectorCount(a_AreaID)
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
function SQLite:GetAreaConnectors(a_AreaID)
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





--- Returns an array of tables describing the approved areas in the specified group
-- Each sub-table has all the attributes read from the DB row
-- Returns an empty table if there are no areas in the group
-- Returns nil on DB error
function SQLite:GetApprovedAreasInGroup(a_GroupName)
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





--- Returns a table of all the DB values (ident) of the specified connector
-- Returns nil and possibly message on failure
function SQLite:GetConnectorByID(a_ConnectorID)
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
function SQLite:GetGroupAreaCount(a_GroupName)
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
function SQLite:GetGroupStartingAreaCount(a_GroupName)
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
function SQLite:GetMaintenanceCheckStatus(a_CheckName)
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
function SQLite:GetMetadataForArea(a_AreaID, a_IncludeDefaults)
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
function SQLite:GetMetadataForGroup(a_GroupName)
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
function SQLite:GetNumApprovedAreas()
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
function SQLite:GetSpongedAreaIDsMap()
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
function SQLite:GetSpongesForArea(a_AreaID)
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
function SQLite:HasSponge(a_AreaID)
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





--- Returns an array of tables describing the approved areas in the specified range
-- Returns false and optional error message on failure
function SQLite:LoadApprovedAreasRange(a_StartIdx, a_EndIdx)
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
function SQLite:LockApprovedAreas()
	return self:ExecuteStatement(
		"UPDATE Areas SET IsLocked = 1 WHERE CAST(IsApproved AS NUMBER) = 1"
	)
end





--- Renames the group in the DB, by overwriting the group name of all areas that use the a_FromName and changing the metadata
-- Returns false and error message on failure, or true on success
function SQLite:RenameGroup(a_FromName, a_ToName)
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
function SQLite:SetAreaExportGroup(a_AreaID, a_GroupName)
	-- Check params:
	assert(self)
	assert(tonumber(a_AreaID))
	assert(type(a_GroupName) == "string")
	
	-- Update in DB:
	return self:ExecuteStatement(
		"UPDATE Areas SET ExportGroupName = ? WHERE ID = ?",
		{
			a_GroupName, a_AreaID
		}
	)
end





--- Sets the area's ExportName
-- Returns false and error message on failure, or true on success
function SQLite:SetAreaExportName(a_AreaID, a_AreaName)
	-- Check params:
	assert(self)
	assert(tonumber(a_AreaID))
	assert(type(a_AreaName) == "string")
	
	-- Rename in DB:
	return self:ExecuteStatement(
		"UPDATE Areas SET ExportName = ? WHERE ID = ?",
		{
			a_AreaName, a_AreaID
		}
	)
end





--- Sets the area's metadata value in the DB
-- Returns true on success, false and optional message on failure
function SQLite:SetAreaMetadata(a_AreaID, a_Name, a_Value)
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
	
	return true
end





--- Sets the metadata value for the specified group.
-- Returns true on success, false and optional message on failure
function SQLite:SetGroupMetadata(a_GroupName, a_Name, a_Value)
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
function SQLite:SetMaintenanceCheckStatus(a_CheckName, a_Result)
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
function SQLite:SetConnectorPos(a_ConnID, a_NewX, a_NewY, a_NewZ)
	-- Check params:
	assert(self)
	local ConnID = tonumber(a_ConnID)
	assert(ConnID)
	local NewX, NewY, NewZ = tonumber(a_NewX), tonumber(a_NewY), tonumber(a_NewZ)
	assert(NewX)
	assert(NewY)
	assert(NewZ)
	
	-- Update in the DB:
	return self:ExecuteStatement(
		"UPDATE Connectors SET X = ?, Y = ?, Z = ? WHERE ID = ?",
		{
			NewX, NewY, NewZ, ConnID
		}
	)
end





--- Returns true if the table exists in the DB
function SQLite:TableExists(a_TableName)
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
function SQLite:UnlockAllAreas()
	-- Check params:
	assert(self)
	
	return self:ExecuteStatement(
		"UPDATE Areas SET IsLocked = 0"
	)
end





--- Unsets the area's metadata value in the DB
-- Returns true on success, false and optional message on failure
function SQLite:UnsetAreaMetadata(a_AreaID, a_Name)
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
	return true
end





--- Unsets the group's metadata value in the DB
-- Returns true on success, false and optional message on failure
function SQLite:UnsetGroupMetadata(a_GroupName, a_Name)
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
function SQLite:UpdateAreaBBox(a_AreaID, a_MinX, a_MinY, a_MinZ, a_MaxX, a_MaxY, a_MaxZ)
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
	return self:ExecuteStatement(
		"UPDATE Areas SET ExportMinX = ?, ExportMinY = ?, ExportMinZ = ?, ExportMaxX = ?, ExportMaxY = ?, ExportMaxZ = ? WHERE ID = ?",
		{
			a_MinX, a_MinY, a_MinZ, a_MaxX, a_MaxY, a_MaxZ,
			a_AreaID
		}
	)
end





--- Updates the hitbox in the DB to the specified values
-- Returns false and error message on failure, or true on success
function SQLite:UpdateAreaHBox(a_AreaID, a_MinX, a_MinY, a_MinZ, a_MaxX, a_MaxY, a_MaxZ)
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
	return self:ExecuteStatement(
		"UPDATE Areas SET HitboxMinX = ?, HitboxMinY = ?, HitboxMinZ = ?, HitboxMaxX = ?, HitboxMaxY = ?, HitboxMaxZ = ? WHERE ID = ?",
		{
			a_MinX, a_MinY, a_MinZ, a_MaxX, a_MaxY, a_MaxZ,
			a_AreaID
		}
	)
end





--- Updates all the sponges in the DB for the selected area
-- a_SpongedBlockArea is the area containing the sponge blocks; the sponge blocks are extracted and saved to DB
-- Returns true on success, false and message on failure
function SQLite:UpdateAreaSponges(a_AreaID, a_SpongedBlockArea)
	-- Check the params:
	assert(self)
	local AreaID = tonumber(a_AreaID)
	assert(AreaID)
	assert(tolua.type(a_SpongedBlockArea) == "cBlockArea")
	
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
	
	-- Create a block area that has sponges where a_SpongedBlockArea has sponges, and air everywhere else:
	local BA = cBlockArea()
	BA:CopyFrom(a_SpongedBlockArea)
	BA:Fill(cBlockArea.baTypes + cBlockArea.baMetas, E_BLOCK_SPONGE, 0)
	BA:Merge(a_SpongedBlockArea, 0, 0, 0, cBlockArea.msMask)
	local SchematicData = BA:SaveToSchematicString()
	local AreaRep = Base64Encode(SchematicData)
	
	-- Save the sponge area into the DB:
	IsSuccess, Msg = self:ExecuteStatement(
		"INSERT INTO ExportSponges (AreaID, Sponges) VALUES (?, ?)",
		{
			AreaID,
			AreaRep
		}
	)
	BA:Clear();
	return IsSuccess, Msg
end





function SQLite_CreateStorage(a_Params)
	DB = SQLite
	local DBFile = a_Params.File or "Galleries.sqlite"
	
	-- Open the DB:
	local ErrCode, ErrMsg
	DB.DB, ErrCode, ErrMsg = sqlite3.open(DBFile)
	if (DB.DB == nil) then
		LOGWARNING(PLUGIN_PREFIX .. "Cannot open database \"" .. DBFile .. "\": " .. ErrMsg)
		error(ErrMsg)  -- Abort the plugin
	end
	
	-- Create the tables, if they don't exist yet:
	local AreasColumns =
	{
		"IsApproved NUMBER",                       -- Simple 0 / 1
		"DateApproved",                            -- ISO 8601 DateTime of the approving
		"ApprovedBy",                              -- Name of the admin who approved the area
		"ExportMinX", "ExportMinY", "ExportMinZ",  -- The min coords of the exported area
		"ExportMaxX", "ExportMaxY", "ExportMaxZ",  -- The max coords of the exported area
		"ExportGroupName",                         -- The name of the group to which this area belongs
		"ExportName",                              -- The name of the area to use for export. If NULL, the ID is used
		"HitboxMinX", "HitboxMinY", "HitboxMinZ",  -- The min coords of the exported area's hitbox. If NULL, ExportMin coords are used
		"HitboxMaxX", "HitboxMaxY", "HitboxMaxZ",  -- The max coords of the exported area's hitbox. If NULL, ExportMax coords are used
	}
	local ExportSpongesColumns =
	{
		"AreaID  INTEGER PRIMARY KEY",  -- ID of the area to which the sponges belong. Note that the area needn't be approved
		"Sponges"                       -- BLOB containing the base64-ed .schematic representation of the sponges (just air + sponges)
	}
	local ConnectorsColumns =
	{
		"ID INTEGER PRIMARY KEY",  -- ID of the connector
		"AreaID",                  -- ID of the area to which the connector belongs. Note that the area needn't be approved
		"X", "Y", "Z",             -- (World) Coords of the connector
		"Direction",               -- Direction (eBlockFace) of the connector
		"TypeNum",                 -- Type of the connector (only same-type connectors will be connected in the generator)
	}
	local MetadataColumns =
	{
		"AreaID INTEGER",  -- ID of the area for which the metadata is defined
		"Name   STRING",   -- Name of the metadata item
		"Value",           -- Value of the metadata item
	}
	local GroupMetadataColumns =
	{
		"GroupName",
		"Name",
		"Value"
	}
	local LastMaintenanceCheckStatusColumns =
	{
		"CheckName",  -- Name of the check; key
		"DateTime",   -- ISO-formatted date and time of the check
		"Result",     -- Check results, in a per-check-specific format; BLOB
	}
	if (
		not(DB:TableExists("Areas")) or
		not(DB:CreateDBTable("Areas",                      AreasColumns)) or
		not(DB:CreateDBTable("ExportSponges",              ExportSpongesColumns)) or
		not(DB:CreateDBTable("Connectors",                 ConnectorsColumns)) or
		not(DB:CreateDBTable("Metadata",                   MetadataColumns)) or
		not(DB:CreateDBTable("GroupMetadata",              GroupMetadataColumns)) or
		not(DB:CreateDBTable("LastMaintenanceCheckStatus", LastMaintenanceCheckStatusColumns))
	) then
		LOGWARNING(PLUGIN_PREFIX .. "Cannot create DB tables!")
		error("Cannot create DB tables!")
	end
	
	-- Returns the initialized database access object
	return DB
end




