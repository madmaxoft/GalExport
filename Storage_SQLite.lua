
-- Storage_SQLite.lua

-- Implements the SQLite-backed database storage





--- The SQLite backend namespace:
local SQLite = {}





--- Formats the datetime (as returned by os.time() ) into textual representation used in the DB
function FormatDateTime(a_DateTime)
	assert(type(a_DateTime) == "number")
	
	return os.date("%Y-%m-%dT%H:%M:%S", a_DateTime)
end





--- Executes the SQL statement, substituting "?" in the SQL with the specified params
-- Calls a_Callback for each row
-- The callback receives a dictionary table containing the row values (stmt:nrows())
-- Returns false and error message on failure, or true on success
function SQLite:ExecuteStatement(a_SQL, a_Params, a_Callback)
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





--- Creates the table of the specified name and columns[]
-- If the table exists, any columns missing are added; existing data is kept
function SQLite:CreateDBTable(a_TableName, a_Columns)
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





--- Returns true if the table exists in the DB
function SQLite:TableExists(a_TableName)
	assert(self ~= nil)
	assert(type(a_TableName) == "string")
	
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
		"IsApproved",                              -- Simple 0 / 1
		"DateApproved",                            -- ISO 8601 DateTime of the approving
		"ApprovedBy",                              -- Name of the admin who approved the area
		"ExportMinX", "ExportMinY", "ExportMinZ",  -- The min coords of the exported area
		"ExportMaxX", "ExportMaxY", "ExportMaxZ",  -- The max coords of the exported area
		"ExportGroupID"                            -- The ID of the group to which this area belongs (ExportGroups table)
	}
	local ExportGroupsColumns =
	{
		"GroupID INTEGER PRIMARY KEY",
		"GroupName",
	}
	if (
		not(DB:TableExists("Areas")) or
		not(DB:CreateDBTable("Areas",        AreasColumns)) or
		not(DB:CreateDBTable("ExportGroups", ExportGroupsColumns))
	) then
		LOGWARNING(PLUGIN_PREFIX .. "Cannot create DB tables!")
		error("Cannot create DB tables!")
	end
	
	-- Returns the initialized database access object
	return DB
end




