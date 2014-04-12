
-- Exporters.lua

-- Implements the various exported formats

--[[
Each export function takes a table describing the area to export and an optional callback to call afterwards.
The function returns true if successful, false and message if unsuccessful.
Note that the reported success needn't indicate a true success of the export, since the export queues
a ChunkStay; rather, it indicates that the operation has been queued successfully. The callback is called
once the entire operation completes, use that for status reporting.
All the exporter functions are listed at the bottom of this file in the g_Exporters dict table
that lists the formats' names and the functions to call for the actual export.
--]]





--- Reads an area from the world and then calls the specified callback on it
-- This is a helper function called from most exporters to read the area data from the world
-- It uses a ChunkStay mechanism to read the area, because the chunks for the areas needn't be loaded
-- The success callback takes a single param, the cBlockArea that has been read from the world
-- The failure callback is called in case of errors, and gets one parameter, the optional message
local function DoWithArea(a_AreaDef, a_SuccessCallback, a_FailureCallback)
	assert(type(a_AreaDef) == "table")
	assert(type(a_SuccessCallback) == "function")
	assert((a_FailureCallback == nil) or (type(a_FailureCallback) == "function"))
	
	-- Get the array of chunks that need to be loaded:
	local Chunks = GetChunksForAreaExport(a_AreaDef)
	assert(Chunks[1] ~= nil)  -- There must be at least 1 chunk in the table
	
	-- Create a cuboid for the exported coords:
	local Bounds = cCuboid(
		a_AreaDef.ExportMinX, a_AreaDef.ExportMinY, a_AreaDef.ExportMinZ,
		a_AreaDef.ExportMaxX, a_AreaDef.ExportMaxY, a_AreaDef.ExportMaxZ
	)
	
	-- Initiate the ChunkStay:
	local World = cRoot:Get():GetWorld(a_AreaDef.WorldName)
	World:ChunkStay(Chunks,
		function (a_ChunkX, a_ChunkZ) end,  -- Callback for OnChunkAvailable
		function ()  -- Callback for OnAllChunksAvailable
			local BA = cBlockArea()
			if (BA:Read(World, Bounds, cBlockArea.baTypes + cBlockArea.baMetas)) then
				-- Merge the sponges into the area:
				local Sponges = g_DB:GetSpongesForArea(a_AreaDef.ID)
				if (Sponges ~= nil) then
					local OfsX = a_AreaDef.MinX - a_AreaDef.ExportMinX
					local OfsY =                - a_AreaDef.ExportMinY
					local OfsZ = a_AreaDef.MinZ - a_AreaDef.ExportMinZ
					BA:Merge(Sponges, OfsX, OfsY, OfsZ, cBlockArea.msFillAir)
				end
				
				-- Call the callback:
				a_SuccessCallback(BA)
			else
				LOGWARNING("DoWithArea: Failed to read the cBlockArea")
			end
		end
	)
end





--- Returns the string that should be used as area's export name
-- Either the string defined by the user, or composed (if no user-specified string exists)
local function GetAreaExportName(a_AreaDef)
	-- Check params:
	assert(type(a_AreaDef) == "table")
	
	-- If the area's ExportName is defined, use that
	if (a_AreaDef.ExportName and (a_AreaDef.ExportName ~= "")) then
		return a_AreaDef.ExportName
	else
		-- Compose the ExportName from the ExportGroupName and ID:
		return a_AreaDef.ExportGroupName ..  "_" .. a_AreaDef.ID
	end
end





--- Returns the string containing CPP source for the connectors in the specified area
-- a_Indent is inserted at each line's start
local function MakeCppConnectorsSource(a_AreaDef, a_Indent)
	-- No need to check params, they were checked by MakeCppSource, which is the only allowed caller
	
	-- Use simple local values for these functions instead of table lookups in each loop:
	local ins = table.insert
	local con = table.concat
	
	-- Write the header:
	local res = {"\n", a_Indent, "\t// Connectors:\n", a_Indent}
	
	-- Write out each connector's definition:
	local Connectors = g_DB:GetAreaConnectors(a_AreaDef.ID)
	local ConnDefs = {}
	for _, conn in ipairs(Connectors) do
		local X = conn.X - a_AreaDef.ExportMinX
		local Y = conn.Y - a_AreaDef.ExportMinY
		local Z = conn.Z - a_AreaDef.ExportMinZ
		ins(ConnDefs, string.format("\t\"%d: %d, %d, %d: %d\\n\"  /* Type %d, direction %s */",
			conn.TypeNum, X, Y, Z, conn.Direction, conn.TypeNum, DirectionToString(conn.Direction)
		))
	end
	
	-- Join the connector definitions into the output:
	ins(res, con(ConnDefs, "\n" .. a_Indent))
	if (ConnDefs[1] == nil) then
		ins(res, "\t\"\"")
	end
	ins(res, ",\n")
	
	-- Join the output into a single string:
	return con(res)
end





--- Converts the cBlockArea into a cpp source
-- a_Indent is inserted at each line's start
-- Returns the cpp source as a string if successful
-- Returns nil and error message if unsuccessful
local function MakeCppSource(a_BlockArea, a_AreaDef, a_Indent)
	assert(tolua.type(a_BlockArea) == "cBlockArea")
	assert(type(a_AreaDef) == "table")
	a_Indent = a_Indent or ""
	
	-- Write the header:
	local ExportName = GetAreaExportName(a_AreaDef)
	local res = {a_Indent, string.rep("/", 119), "\n",
		a_Indent, "// ", ExportName, ":\n",
		a_Indent, "// The data has been exported from the gallery ", a_AreaDef.GalleryName, ", area index ",
		a_AreaDef.GalleryIndex, ", ID ", a_AreaDef.ID, ", created by ", a_AreaDef.PlayerName, "\n",
		a_Indent, "{\n"
	}
	
	-- Use simple local values for these functions instead of table lookups in each loop:
	local ins = table.insert
	local con = table.concat

	--[[
	NOTE: This function uses "BlockDef" extensively. It is a number that represents a combination of
	BlockType + BlockMeta uniquely simply by multiplying BlockType by 16 and adding it to BlockMeta.
	--]]
	
	-- Prepare the tables used for blockdef-counting:
	-- Force use "." for air and "m" for sponge, so insert it here already
	local BlockToLetter = {[E_BLOCK_AIR * 16] = ".", [E_BLOCK_SPONGE * 16] = "m"}  -- dict: BlockDef -> Letter
	local LetterToBlock = {["."] = E_BLOCK_AIR * 16, ["m"] = E_BLOCK_SPONGE * 16}  -- dict: Letter -> BlockDef
	local Letters = "abcdefghijklnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890!@#$%^&*,<>/?;[{]}|_-=+~"  -- Letters that can be used in the definition
	local MaxLetters = string.len(Letters)
	local LastLetterIdx = 1   -- Index into Letters for the next letter to use for new BlockDef
	local SizeX, SizeY, SizeZ = a_BlockArea:GetSize()
	
	-- Create a horizontal ruler text, used on each level:
	local HorzRuler = {a_Indent, "\t/* z\\x*   "}
	if (SizeX > 9) then
		for x = 0, SizeX - 1 do
			if (x < 10) then
				ins(HorzRuler, " ")
			else
				ins(HorzRuler, string.format("%d", math.floor(x / 10)))
			end
		end
		ins(HorzRuler, " */\n")
		ins(HorzRuler, a_Indent)
		ins(HorzRuler, "\t/*    *   ")
	end
	for x = 0, SizeX - 1 do
		ins(HorzRuler, string.format("%d", x - 10 * math.floor(x / 10)))
	end
	ins(HorzRuler, " */\n")
	local HorzRulerText = con(HorzRuler)

	-- Transform blocktypes to letters:
	local def = {}
	local Levels = {}
	for y = 0, SizeY - 1 do
		local Level = {a_Indent, "\t// Level ", y, "\n", HorzRulerText}
		for z = 0, SizeZ - 1 do
			local Line = ""
			for x = 0, SizeX - 1 do
				local BlockType, BlockMeta = a_BlockArea:GetRelBlockTypeMeta(x, y, z)
				local BlockDef = BlockMeta + 16 * BlockType
				local MyLetter = BlockToLetter[BlockDef]
				if (MyLetter == nil) then
					if (LastLetterIdx == MaxLetters) then
						return false, "Too many different blocktypes, cannot represent as cpp source"
					end
					MyLetter = Letters:sub(LastLetterIdx, LastLetterIdx)
					BlockToLetter[BlockDef] = MyLetter
					LetterToBlock[MyLetter] = BlockDef
					LastLetterIdx = LastLetterIdx + 1
				end
				Line = Line .. MyLetter
			end  -- for x
			ins(Level, a_Indent)
			ins(Level, "\t/* ")
			ins(Level, string.format("%2d", z))
			ins(Level, " */ \"")
			ins(Level, Line)
			if ((y == SizeY - 1) and (z == SizeZ - 1)) then
				ins(Level, "\",\n")
			else
				ins(Level, "\"\n")
			end
			Line = ""
		end  -- for z
		ins(Levels, con(Level))
	end  -- for y
	ins(def, con(Levels, "\n"))
	
	-- Write the dimensions:
	ins(res, a_Indent)
	ins(res, "\t// Size:\n")
	ins(res, a_Indent)
	ins(res, con({"\t", SizeX, ", ", SizeY, ", ", SizeZ, ",  // SizeX = ", SizeX, ", SizeY = ", SizeY, ", SizeZ = ", SizeZ, "\n\n"}))
	
	-- Write the letter-to-blockdef table:
	local LetterToBlockDef = {}
	for ltr, blk in pairs(LetterToBlock) do
		local BlockType = math.floor(blk / 16)
		local BlockMeta = blk - 16 * BlockType
		ins(LetterToBlockDef, string.format(
			"\t\"%s:%3d:%2d\\n\"  /* %s */",
			ltr, BlockType, BlockMeta, ItemTypeToString(BlockType)
		))
	end
	table.sort(LetterToBlockDef)
	ins(res, a_Indent)
	ins(res, "\t// Block definitions:\n")
	ins(res, a_Indent)
	ins(res, con(LetterToBlockDef, "\n" .. a_Indent))
	ins(res, ",\n")
	
	-- Write the block data:
	ins(res, "\n")
	ins(res, a_Indent)
	ins(res, "\t// Block data:\n")
	ins(res, con(def))

	-- Write the connectors:
	ins(res, MakeCppConnectorsSource(a_AreaDef, a_Indent))
	ins(res, "\n")
	
	-- Write the constant metadata:
	ins(res, a_Indent)
	ins(res, "\t// AllowedRotations:\n")
	ins(res, a_Indent)
	ins(res, "\t7,  /* 1, 2, 3 CCW rotations */\n")
	ins(res, "\n")
	ins(res, a_Indent)
	ins(res, "\t// Merge strategy:\n")
	ins(res, a_Indent)
	ins(res, "\tcBlockArea::msSpongePrint,\n")
	ins(res, a_Indent)
	ins(res, "},  // ")
	ins(res, ExportName)
	ins(res, "\n")
	
	return con(res)
end





--- Exports the area into a .schematic file
local function ExportSchematic(a_AreaDef, a_Callback)
	-- Check params:
	assert(type(a_AreaDef) == "table")
	assert((a_Callback == nil) or (type(a_Callback) == "function"))
	
	-- Queue the ChunkStay operation:
	DoWithArea(a_AreaDef,
		function(a_BlockArea)
			cFile:CreateFolder(g_Config.ExportFolder)
			local FileName = g_Config.ExportFolder .. "/" .. (a_AreaDef.ExportGroupName or "undefined_group") .. "/"
			cFile:CreateFolder(FileName)
			local ExportName = a_AreaDef.ExportName
			if ((ExportName == nil) or (ExportName == "")) then
				ExportName = a_AreaDef.ID
			end
			FileName = FileName .. ExportName .. ".schematic"
			local IsSuccess = a_BlockArea:SaveToSchematicFile(FileName)
			if (a_Callback ~= nil) then
				a_Callback(IsSuccess)
			end
		end
	)
	return true
end





--- Exports all areas (assumed in a single group) into their respective .schematic files
-- If all the areas are exported successfully, calls a_SuccessCallback (with no params)
-- If any of the areas fail to export, a_FailureCallback is called with one parameter, the failure message (possibly nil)
local function ExportSchematicGroup(a_Areas, a_SuccessCallback, a_FailureCallback)
	-- Check params:
	assert(type(a_Areas) == "table")
	assert(a_Areas[1] ~= nil)  -- At least one area to export
	assert((a_SuccessCallback == nil) or (type(a_SuccessCallback) == "function"))
	assert((a_FailureCallback == nil) or (type(a_SuccessCallback) == "function"))

	-- Callback to be called when area data has been loaded:
	local CurrArea = 1
	local function ProcessOneArea(a_BlockArea)
		-- Write the area into a file:
		local Area = a_Areas[CurrArea]
		cFile:CreateFolder(g_Config.ExportFolder)
		local FileName = g_Config.ExportFolder .. "/" .. (Area.ExportGroupName or "undefined_group") .. "/"
		cFile:CreateFolder(FileName)
		local ExportName = Area.ExportName
		if ((ExportName == nil) or (ExportName == "")) then
			ExportName = Area.ID
		end
		FileName = FileName .. ExportName .. ".schematic"
		local IsSuccess, Msg = a_BlockArea:SaveToSchematicFile(FileName)
		if not(IsSuccess) then
			a_FailureCallback("Failed to save schematic file " .. FileName .. ": " .. (Msg or "<no details>"))
			return
		end

		-- Advance to next area:
		CurrArea = CurrArea + 1
		if (a_Areas[CurrArea] == nil) then
			-- No more areas in this group, finish the export:
			a_SuccessCallback()
			return
		else
			-- There are more areas to process, queue the next one:
			DoWithArea(a_Areas[CurrArea], ProcessOneArea, a_FailureCallback)
		end
	end
	
	return DoWithArea(a_Areas[1], ProcessOneArea, a_FailureCallback)
end





-- Exports the area into a cpp source file
local function ExportCpp(a_AreaDef, a_Callback)
	-- Check params:
	assert(type(a_AreaDef) == "table")
	assert((a_Callback == nil) or (type(a_Callback) == "function"))

	-- Define a callback for ChunkStay that exports the area, once loaded:
	local function DoExport(a_BlockArea)
		-- Create the folder and the filename to use:
		cFile:CreateFolder(g_Config.ExportFolder)
		local FileName = g_Config.ExportFolder .. "/" .. (a_AreaDef.ExportGroupName or "undefined_group") .. "/"
		cFile:CreateFolder(FileName)
		local ExportName = a_AreaDef.ExportName
		if ((ExportName == nil) or (ExportName == "")) then
			ExportName = a_AreaDef.ID
		end
		FileName = FileName .. ExportName .. ".cpp"
		
		-- Convert the BlockArea into a cpp source:
		local Txt, Msg = MakeCppSource(a_BlockArea, a_AreaDef)
		if (Txt == nil) then
			a_Callback(false, Msg)
			return
		end
		
		-- Save to file:
		local f
		f, Msg = io.open(FileName, "w")
		if (f == nil) then
			a_Callback(false, Msg)
			return
		end
		f:write(Txt)
		f:close()
		
		a_Callback(true)
	end
	
	-- Queue the ChunkStay operation:
	DoWithArea(a_AreaDef, DoExport)
	return true
end





--- Exports all areas (assumed in a single group) into a single CPP file
-- If all the areas are exported successfully, calls a_SuccessCallback (with no params)
-- If any of the areas fail to export, no output is written and a_FailureCallback is called
-- with one parameter, the failure message (possibly nil)
local function ExportCppGroup(a_Areas, a_SuccessCallback, a_FailureCallback)
	-- Check params:
	assert(type(a_Areas) == "table")
	assert(a_Areas[1] ~= nil)  -- At least one area to export
	assert((a_SuccessCallback == nil) or (type(a_SuccessCallback) == "function"))
	assert((a_FailureCallback == nil) or (type(a_SuccessCallback) == "function"))
	
	-- Read the areas' metadata, if not present already:
	for _, area in ipairs(a_Areas) do
		area.Metadata = area.Metadata or g_DB:GetMetadataForArea(area.ID, true)
		area.Metadata.IsStarting = tonumber(area.Metadata.IsStarting)
	end
	
	-- Store usefull stuff:
	local GroupName = a_Areas[1].ExportGroupName
	local CurrArea = 1
	local FileNameBase = g_Config.ExportFolder .. "/" .. GroupName .. "Prefabs"
	
	-- Open the output files:
	local cpp = io.open(FileNameBase .. ".cpp", "w")
	if (cpp == nil) then
		a_FailureCallback("Cannot open file " .. FileNameBase .. ".cpp for output")
		return
	end
	local hdr = io.open(FileNameBase .. ".h", "w")
	if (hdr == nil) then
		cpp:close()
		a_FailureCallback("Cannot open file " .. FileNameBase .. ".h for output")
		return
	end
	
	-- Write the file headers:
	cpp:write("\n// ", GroupName, "Prefabs.cpp\n\n// Defines the prefabs in the group ", GroupName, "\n\n")
	cpp:write("// NOTE: This file has been generated automatically by GalExport!\n")
	cpp:write("// Any manual changes will be overwritten by the next automatic export!\n\n")
	cpp:write("#include \"Globals.h\"\n#include \"", GroupName, "Prefabs.h\"\n\n\n\n\n\n")
	cpp:write("const cPrefab::sDef g_", GroupName, "Prefabs[] =\n{\n")
	hdr:write("\n// ", GroupName, "Prefabs.h\n\n// Declares the prefabs in the group ", GroupName, "\n\n")
	hdr:write("#include \"../Prefab.h\"\n\n\n\n\n\n")
	hdr:write("extern const cPrefab::sDef g_", GroupName, "Prefabs[];\n")
	hdr:write("extern const cPrefab::sDef g_", GroupName, "StartingPrefabs[];\n")
	hdr:write("extern const size_t g_", GroupName, "PrefabsCount;\n")
	hdr:write("extern const size_t g_", GroupName, "StartingPrefabsCount;\n")
	hdr:close()
	
	-- Sort areas so that the starting ones come last; then by their export name:
	table.sort(a_Areas,
		function (a_Area1, a_Area2)
			if (a_Area1.Metadata.IsStarting ~= 0) then
				if (a_Area2.Metadata.IsStarting ~= 0) then
					-- Both are starting, sort by export name:
					return (GetAreaExportName(a_Area1) < GetAreaExportName(a_Area2))
				end
				-- a_Area1 is starting, a_Area2 is not:
				return false
			end
			if (a_Area2.Metadata.IsStarting ~= 0) then
				-- a_Area2 is starting, a_Area1 is not:
				return true
			end
			-- Neither area is starting, sort by name:
			return (GetAreaExportName(a_Area1) < GetAreaExportName(a_Area2))
		end
	)
	
	-- Callback to be called when area data has been loaded:
	local HasStarting = false
	local function ProcessOneArea(a_BlockArea)
		-- Write source for the area into the file:
		local Area = a_Areas[CurrArea]
		local Src = MakeCppSource(a_BlockArea, Area, "\t")
		Src = Src or ("/* Error: Area " .. Area.GalleryName .. "_" .. Area.ID .. " failed to export source! */")
		cpp:write(Src)
		
		-- Advance to next area:
		CurrArea = CurrArea + 1
		if (a_Areas[CurrArea] == nil) then
			-- No more areas in this group, finish the export:
			cpp:write("};\n\n\n\n\n\n")
			cpp:write("// The prefab counts:\n\n")
			cpp:write("const size_t g_", GroupName, "PrefabsCount = ARRAYCOUNT(g_", GroupName, "Prefabs);\n\n")
			if (HasStarting) then
				cpp:write("const size_t g_", GroupName, "StartingPrefabsCount = ARRAYCOUNT(g_", GroupName, "StartingPrefabs);\n\n")
			end
			cpp:close()
			a_SuccessCallback()
			return
		else
			-- There are more areas to process:
			if ((Area.Metadata.IsStarting == 0) and (a_Areas[CurrArea].Metadata.IsStarting ~= 0)) then
				-- going from not-starting into starting areas, break off the array and start a new one:
				cpp:write("};  // g_", GroupName, "Prefabs\n")
				cpp:write("\n\n\n\n\n\nconst cPrefab::sDef g_", GroupName, "StartingPrefabs[] =\n{\n")
				HasStarting = true
			else
				cpp:write("\n\n\n")
			end

			DoWithArea(a_Areas[CurrArea], ProcessOneArea, a_FailureCallback)
		end
	end
	
	return DoWithArea(a_Areas[1], ProcessOneArea, a_FailureCallback)
end





--- The descriptor for .schematic export
local SchematicExporterDesc =
{
	ExportArea = ExportSchematic,
	ExportGroup = ExportSchematicGroup,
}





--- The descriptor for .cpp export:
local CppExporterDesc =
{
	ExportArea = ExportCpp,
	ExportGroup = ExportCppGroup,
}





--- This dictionary table contains a mapping between the format name and its exporting function
g_Exporters =
{
	-- cpp export:
	["c"]   = CppExporterDesc,
	["cpp"] = CppExporterDesc,
	
	-- schematic export:
	["s"]         = SchematicExporterDesc,
	["schem"]     = SchematicExporterDesc,
	["schematic"] = SchematicExporterDesc,
}




