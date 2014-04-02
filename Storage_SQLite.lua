
-- Storage_SQLite.lua

-- Implements the SQLite-backed database storage





--- The SQLite backend namespace:
local SQLite = {}





--- Formats the datetime (as returned by os.time() ) into textual representation used in the DB
function FormatDateTime(a_DateTime)
	assert(type(a_DateTime) == "number")
	
	return os.date("%Y-%m-%dT%H:%M:%S", a_DateTime)
end





--- Sets the area as approved by the specified player in the specified group and with the specified export cuboid
-- If the area is already approved, returns false, the name of the approver, date approved and the group name
-- If any of the DB queries fail, returns nil.
-- Returns true on success
function SQLite:ApproveArea(a_AreaID, a_PlayerName, a_GroupName, a_ExportCuboid, a_AreaName)
	-- Check params:
	assert(self ~= nil)
	assert(tonumber(a_AreaID) ~= nil)
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
	if (Info ~= nil) then
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





--- Creates the table of the specified name and columns[]
-- If the table exists, any columns missing are added; existing data is kept
function SQLite:CreateDBTable(a_TableName, a_Columns)
	-- Check params:
	assert(self ~= nil)
	assert(a_TableName ~= nil)
	assert(a_Columns ~= nil)
	
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
		if (a_Values.name ~= nil) then
			local ColumnName = a_Values.name:lower()
			-- Search the a_Columns if they have that column:
			for j = 1, #a_Columns do
				-- Cut away all column specifiers (after the first space), if any:
				local SpaceIdx = string.find(a_Columns[j], " ")
				if (SpaceIdx ~= nil) then
					SpaceIdx = SpaceIdx - 1
				end
				local ColumnTemplate = string.lower(string.sub(a_Columns[j], 1, SpaceIdx))
				-- If it is a match, remove from a_Columns:
				if (ColumnTemplate == ColumnName) then
					table.remove(a_Columns, j)
					break  -- for j
				end
			end  -- for j - a_Columns[]
		end  -- if (a_Values.name ~= nil)
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





--- Executes the SQL statement, substituting "?" in the SQL with the specified params
-- Calls a_Callback for each row
-- The callback receives a dictionary table containing the row values (stmt:nrows())
-- Returns false and error message on failure, or true on success
function SQLite:ExecuteStatement(a_SQL, a_Params, a_Callback)
	-- Check params:
	assert(self ~= nil)
	assert(a_SQL ~= nil)
	assert(a_Params ~= nil)
	assert(self.DB ~= nil)
	
	local Stmt, ErrCode, ErrMsg = self.DB:prepare(a_SQL)
	if (Stmt == nil) then
		LOGWARNING(PLUGIN_PREFIX .. "Cannot prepare SQL \"" .. a_SQL .. "\": " .. (ErrCode or "<unknown>") .. " (" .. (ErrMsg or "<no message>") .. ")")
		LOGWARNING(PLUGIN_PREFIX .. "  Params = {" .. table.concat(a_Params, ", ") .. "}")
		return nil, (ErrMsg or "<no message>")
	end
	Stmt:bind_values(unpack(a_Params))
	if (a_Callback == nil) then
		Stmt:step()
	else
		for v in Stmt:nrows() do
			a_Callback(v)
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
	assert(self ~= nil)

	-- Load from the DB:
	local res = {}
	if not(self:ExecuteStatement(
		"SELECT * FROM Areas WHERE IsApproved = 1",
		{},
		function (a_Values)
			-- Require the area to have at least the ID:
			if (a_Values.ID ~= nil) then
				table.insert(res, a_Values)
			end
		end
	)) then
		-- DB error or no data (?)
		return nil
	end
	
	return res
end





--- Returns an array of all export groups stored in the DB.
-- Returns nil on failure
function SQLite:GetAllGroups()
	-- Check params:
	assert(self ~= nil)
	
	-- Get the groups:
	local res = {}
	if not(self:ExecuteStatement(
		"SELECT DISTINCT(ExportGroupName) FROM Areas",
		{},
		function (a_Values)
			if (a_Values.ExportGroupName ~= nil) then
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
	assert(self ~= nil)
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





--- Returns an array of tables describing the approved areas in the specified group
-- Each sub-table has all the attributes read from the DB row
-- Returns an empty table if there are no areas in the group
-- Returns nil on DB error
function SQLite:GetApprovedAreasInGroup(a_GroupName)
	-- Check params:
	assert(self ~= nil)
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
			if (a_Values.ID ~= nil) then
				table.insert(res, a_Values)
			end
		end
	)) then
		-- DB error or no data (?)
		return nil
	end
	
	return res
end





--- Retrieves the sponges for the specified area
-- Returns a cBlockArea representing the whole area (MinX to MaxX etc), where sponges should be put
-- Returns nil and message on error
function SQLite:GetSpongesForArea(a_AreaID)
	-- Check params:
	assert(self ~= nil)
	local AreaID = tonumber(a_AreaID)
	assert(AreaID ~= nil)

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
	
	-- Create the block area from the data:
	local Sponges = cBlockArea()
	if not(Sponges:LoadFromSchematicString(Base64Decode(SpongeSchematic))) then
		return nil, "Cannot decode the stored schematic"
	end
	return Sponges
end





--- Renames the group in the DB, by overwriting the group name of all areas that use the a_FromName
-- Returns false and error message on failure, or true on success
function SQLite:RenameGroup(a_FromName, a_ToName)
	-- Check params:
	assert(self ~= nil)
	assert(type(a_FromName) == "string")
	assert(type(a_ToName) == "string")
	
	-- Rename:
	return self:ExecuteStatement(
		"UPDATE Areas SET ExportGroupName = ? WHERE ExportGroupName = ?",
		{
			a_ToName, a_FromName
		}
	)
end





--- Sets the area's ExportName
-- Returns false and error message on failure, or true on success
function SQLite:SetAreaExportName(a_AreaID, a_AreaName)
	-- Check params:
	assert(self ~= nil)
	assert(tonumber(a_AreaID) ~= nil)
	assert(type(a_AreaName) == "string")
	
	return self:ExecuteStatement(
		"UPDATE Areas SET ExportName = ? WHERE ID = ?",
		{
			a_AreaName, a_AreaID
		}
	)
end





--- Returns true if the table exists in the DB
function SQLite:TableExists(a_TableName)
	-- Check params:
	assert(self ~= nil)
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





--- Updates the export bbox in the DB to the specified values
-- Returns false and error message on failure, or true on success
function SQLite:UpdateAreaBBox(a_AreaID, a_MinX, a_MinY, a_MinZ, a_MaxX, a_MaxY, a_MaxZ)
	-- Check the params:
	assert(self ~= nil)
	assert(tonumber(a_AreaID) ~= nil)
	assert(tonumber(a_MinX) ~= nil)
	assert(tonumber(a_MinY) ~= nil)
	assert(tonumber(a_MinZ) ~= nil)
	assert(tonumber(a_MaxX) ~= nil)
	assert(tonumber(a_MaxY) ~= nil)
	assert(tonumber(a_MaxZ) ~= nil)
	
	-- Write into DB:
	return self:ExecuteStatement(
		"UPDATE Areas SET ExportMinX = ?, ExportMinY = ?, ExportMinZ = ?, ExportMaxX = ?, ExportMaxY = ?, ExportMaxZ = ? WHERE ID = ?",
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
	assert(self ~= nil)
	local AreaID = tonumber(a_AreaID)
	assert(AreaID ~= nil)
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
	}
	local ExportSpongesColumns =
	{
		"AreaID  INTEGER PRIMARY KEY",  -- ID of the area to which the sponges belong. Note that the area needn't be approved
		"Sponges"                       -- BLOB containing the base64-ed .schematic representation of the sponges (just air + sponges)
	}
	if (
		not(DB:TableExists("Areas")) or
		not(DB:CreateDBTable("Areas", AreasColumns)) or
		not(DB:CreateDBTable("ExportSponges", ExportSpongesColumns))
	) then
		LOGWARNING(PLUGIN_PREFIX .. "Cannot create DB tables!")
		error("Cannot create DB tables!")
	end
	
	-- Returns the initialized database access object
	return DB
end




