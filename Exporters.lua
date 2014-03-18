
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
-- The callback takes a single param, the cBlockArea that has been read from the world
-- There is no notification on error, since this function queues a delayed task and only calls the callback
-- after the chunks have loaded
local function DoWithArea(a_AreaDef, a_Callback)
	assert(type(a_AreaDef) == "table")
	assert(type(a_Callback) == "function")
	
	-- Calculate the chunk range needed:
	local MinChunkX = math.floor(a_AreaDef.ExportMinX / 16)
	local MinChunkZ = math.floor(a_AreaDef.ExportMinZ / 16)
	local MaxChunkX = math.floor((a_AreaDef.ExportMaxX + 15) / 16)
	local MaxChunkZ = math.floor((a_AreaDef.ExportMaxZ + 15) / 16)

	-- Make a list of the needed chunks:
	local Chunks = {}
	for x = MinChunkX, MaxChunkX do for z = MinChunkZ, MaxChunkZ do
		table.insert(Chunks, {x, z})
	end end
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
				a_Callback(BA)
			else
				LOGWARNING("DoWithArea: Failed to read the cBlockArea")
			end
		end
	)
end





--- Converts the cBlockArea into a cpp source
-- Returns the cpp source as a string if successful
-- Returns nil and error message if unsuccessful
local function MakeCppSource(a_BlockArea, a_AreaDef)
	assert(tolua.type(a_BlockArea) == "cBlockArea")
	assert(type(a_AreaDef) == "table")
	
	-- Write the header:
	local res = { "// ", a_AreaDef.ExportGroupName, "/", a_AreaDef.ID, ".cpp\n\n",
		"// WARNING! This file has been generated automatically by GalExport. Any changes you make will be lost on next export!\n\n",
		"static const cPrefab::sDef g_", a_AreaDef.ExportGroupName, "_", a_AreaDef.ID, " =\n{\n",
	}
	local ins = table.insert
	local con = table.concat

	--[[
	NOTE: This function uses "BlockDef" extensively. It is a number that represents a combination of
	BlockType + BlockMeta uniquely simply by multiplying BlockType by 16 and adding it to BlockMeta.
	--]]
	
	-- Prepare the tables used for blockdef-counting:
	local BlockToLetter = {}  -- dict: BlockDef -> Letter
	local LetterToBlock = {}  -- dict: Letter -> BlockDef
	local Letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890!@#$%^&*,.<>/?;:[{]}|_-=+~"  -- Letters that can be used in the definition
	local MaxLetters = string.len(Letters)
	local LastLetterIdx = 1   -- Index into Letters for the next letter to use for new BlockDef
	
	-- Transform blocktypes to letters:
	local SizeX, SizeY, SizeZ = a_BlockArea:GetSize()
	local def = {}
	local Levels = {}
	for y = 0, SizeY - 1 do
		local Level = {}
		ins(Level, "\t// Level ")
		ins(Level, y + 1)
		ins(Level, "\n")
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
			ins(Level, "\t\"")
			ins(Level, Line)
			ins(Level, "\",\n")
			Line = ""
		end  -- for z
		ins(Levels, con(Level))
	end  -- for y
	ins(def, con(Levels, "\n"))
	
	-- Write the dimensions:
	ins(res, "\t// Size:\n")
	ins(res, con({"\t", SizeX, ", ", SizeY, ", ", SizeZ, ",  // SizeX = ", SizeX, ", SizeY = ", SizeY, ", SizeZ = ", SizeZ, "\n\n"}))
	
	-- Write the letter-to-blockdef table:
	local LetterToBlockDef = {}
	for ltr, blk in pairs(LetterToBlock) do
		local BlockType = math.floor(blk / 16)
		local BlockMeta = blk - 16 * BlockType
		ins(LetterToBlockDef, string.format(
			"\t\"%s:%3d:%2d\"  /* %s */",
			ltr, BlockType, BlockMeta, ItemTypeToString(BlockType)
		))
	end
	table.sort(LetterToBlockDef)
	ins(res, "\t// Block definitions:\n")
	ins(res, con(LetterToBlockDef, " \\\n"))
	ins(res, ",\n")
	
	-- Write the block data:
	ins(res, "\n\t// Block data:\n")
	ins(res, con(def))
	ins(res, "};\n")
	
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
			FileName = FileName .. a_AreaDef.ID .. ".schematic"
			local IsSuccess = a_BlockArea:SaveToSchematicFile(FileName)
			if (a_Callback ~= nil) then
				a_Callback(IsSuccess)
			end
		end
	)
	return true
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
		FileName = FileName .. a_AreaDef.ID .. ".cpp"
		
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





--- The descriptor for .schematic export
local SchematicExporterDesc =
{
	ExportArea = ExportSchematic,
	ExportGroupMetadata = nil,  -- TODO
}





--- The descriptor for .cpp export:
local CppExporterDesc =
{
	ExportArea = ExportCpp,
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




