
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





--- The descriptor for .schematic export
local SchematicExporterDesc =
{
	ExportArea = ExportSchematic,
	ExportGroupMetadata = nil,  -- TODO
}





--- This dictionary table contains a mapping between the format name and its exporting function
g_Exporters =
{
	--[[
	-- TODO
	-- cpp export:
	["c"]   = CppExporterDesc,
	["cpp"] = CppExporterDesc,
	--]]
	
	-- schematic export:
	["s"]         = SchematicExporterDesc,
	["schem"]     = SchematicExporterDesc,
	["schematic"] = SchematicExporterDesc,
}




