
-- Web.lua

-- Implements the webadmin interface





local ins = table.insert
local g_NumAreasPerPage = 50

-- Contains the PNG file for "Preview not available yet" image
local g_PreviewNotAvailableYetPng

--- URL name of the Areas page:
local PAGE_NAME_AREAS = "Areas"

-- URL name of the Groups page:
local PAGE_NAME_GROUPS = "Groups"

-- URL name of the Maintenance page:
local PAGE_NAME_MAINTENANCE = "Maintenance"

--- URL name of the CheckSponging page:
local PAGE_NAME_CHECKSPONGING = "Sponging"

-- URL name of the CheckConnector page:
local PAGE_NAME_CHECKCONNECTORS = "Connectors"

-- URL name of the Exports page:
local PAGE_NAME_EXPORTS = "Exports"

--- Maps the lowercased IntendedUse metadata to true if such a group doesn't need sponging
local g_SpongelessIntendedUse =
{
	["trees"] = true,
}





--- Array of exporter descriptions
-- Each item is a table with a Title (user-visible) and Name (program use)
local g_ExporterDescs =
{
	{
		Title = "Cubeset",
		Name = "cubeset",
	},
	{
		Title = "Cubeset (with external schematics)",
		Name = "cubesetext",
	},
	{
		Title = "CPP source",
		Name = "cpp",
	},
	{
		Title = "Schematic files",
		Name = "schematic",
	}
}





local DirectionToString =
{
	[BLOCK_FACE_XM] = "X-",
	[BLOCK_FACE_XP] = "X+",
	[BLOCK_FACE_YM] = "Y-",
	[BLOCK_FACE_YP] = "Y+",
	[BLOCK_FACE_ZM] = "Z-",
	[BLOCK_FACE_ZP] = "Z+",
}





--- Dictionary of exports that have started and not yet completed
-- Maps "<exporterCode>|<groupName>" -> "<startTime>" for such exports.
local g_PendingExports = {}





--- Returns the HTML-formatted error message with the specified reason
local function HTMLError(a_Reason)
	return "<b style='color: #a00'>" .. cWebAdmin:GetHTMLEscapedString(a_Reason) .. "</b>"
end





--- For each area in the array, adds an IsStarting meta-value based on the area's IsStarting meta
local function AddAreasStartingFlag(a_Areas)
	-- Check params:
	assert(type(a_Areas) == "table")

	for _, area in ipairs(a_Areas) do
		if (area.IsStarting == nil) then
			local Metadata = g_DB:GetMetadataForArea(area.ID, false)
			area.IsStarting = (tostring(Metadata["IsStarting"]) == "1")
		end
	end
end





--- Sorts areas. To be called before displaying areas in a list
-- Adds the IsStarting meta-value to each area
local function SortAreas(a_Areas)
	-- Check params:
	assert(type(a_Areas) == "table")

	-- Add the IsStarting flag to each area:
	AddAreasStartingFlag(a_Areas)

	-- Sort the areas, starting ones first (#31):
	table.sort(a_Areas,
		function (a_Area1, a_Area2)
			if (a_Area1.IsStarting) then
				if (a_Area2.IsStarting) then
					-- Both areas are starting, sort by ID:
					return (a_Area1.ID < a_Area2.ID)
				else
					-- a_Area1 is starting, a_Area2 is not:
					return true
				end
			elseif (a_Area2.IsStarting) then
				-- a_Area1 is not starting, a_Area2 is:
				return false
			else
				-- Neither area is starting, sort by ID:
				return (a_Area1.ID < a_Area2.ID)
			end
		end
	)
end





--- Returns HTML code for an <input> tag of the specified type ane name, with optional attributes
-- a_Attribs is a dictionary of "name" -> "value", for which 'name="value"' is added
local function GetHTMLInput(a_Type, a_Name, a_Attribs)
	-- Check params:
	assert(a_Type and tostring(a_Type))
	assert(a_Name and tostring(a_Name))
	assert(not(a_Attribs) or (type(a_Attribs) == "table"))  -- either not present, or a table
	
	local res = { "<input type=\"", a_Type, "\" name=\"", a_Name, "\""}
	for n, v in pairs(a_Attribs or {}) do
		ins(res, " ")
		ins(res, n)
		ins(res, "=\"")
		ins(res, v)
		ins(res, "\"")
	end
	ins(res, "/>")
	
	return table.concat(res)
end





--- Returns true if the specified connector reachable through the area's hitbox, i. e. on the hitbox border
-- or outside the hitbox completely.
-- Returns false on error, too
local function IsConnectorReachableThroughHitbox(a_Connector, a_AreaDef)
	-- Check params:
	assert(type(a_Connector) == "table")
	assert(type(a_AreaDef) == "table")
	
	if (a_Connector.Direction == BLOCK_FACE_XM) then
		return (a_Connector.X <= (a_AreaDef.HitboxMinX or a_AreaDef.ExportMinX))
	elseif (a_Connector.Direction == BLOCK_FACE_XP) then
		return (a_Connector.X >= (a_AreaDef.HitboxMaxX or a_AreaDef.ExportMaxX))
	elseif (a_Connector.Direction == BLOCK_FACE_YM) then
		return (a_Connector.Y <= (a_AreaDef.HitboxMinY or a_AreaDef.ExportMinY))
	elseif (a_Connector.Direction == BLOCK_FACE_YP) then
		return (a_Connector.Y >= (a_AreaDef.HitboxMaxY or a_AreaDef.ExportMaxY))
	elseif (a_Connector.Direction == BLOCK_FACE_ZM) then
		return (a_Connector.Z <= (a_AreaDef.HitboxMinZ or a_AreaDef.ExportMinZ))
	elseif (a_Connector.Direction == BLOCK_FACE_ZP) then
		return (a_Connector.Z >= (a_AreaDef.HitboxMaxZ or a_AreaDef.ExportMaxZ))
	end
	
	-- Not a known direction, mark as failure:
	return false
end





--- Returns the chunk coords of chunks that intersect the given area's export cuboid
-- The returned value has the form of { {Chunk1x, Chunk1z}, {Chunk2x, Chunk2z}, ...}
local function GetAreaChunkCoords(a_Area)
	assert(type(a_Area) == "table")
	local MinChunkX = math.floor(a_Area.ExportMinX / 16)
	local MinChunkZ = math.floor(a_Area.ExportMinZ / 16)
	local MaxChunkX = math.floor((a_Area.ExportMaxX + 15) / 16)
	local MaxChunkZ = math.floor((a_Area.ExportMaxZ + 15) / 16)
	local res = {}
	for z = MinChunkZ, MaxChunkZ do
		for x = MinChunkX, MaxChunkX do
			table.insert(res, {x, z})
		end
	end
	assert(res[1])  -- Check that at least one chunk coord pair is being returned
	return res
end





--- Returns the name of the folder in which the .schematic file for the specified area is to be stored
local function GetAreaSchematicFolderName(a_AreaID)
	-- Check params
	assert(tonumber(a_AreaID))
	
	return g_Config.WebPreview.ThumbnailFolder .. "/" .. tostring(math.floor(a_AreaID / 100))
end





--- Returns the .schematic filename to use for the specified area
local function GetAreaSchematicFileName(a_AreaID)
	-- Check params:
	assert(tonumber(a_AreaID))
	assert(g_Config.WebPreview)
	
	return GetAreaSchematicFolderName(a_AreaID) .. "/" .. a_AreaID .. ".schematic"
end





--- Returns the .png filename to use for the specified area and number of rotations
local function GetAreaPreviewFileName(a_AreaID, a_NumRotations)
	-- Check params:
	assert(tonumber(a_AreaID))
	assert(tonumber(a_NumRotations))
	
	return GetAreaSchematicFolderName(a_AreaID) .. "/" .. a_AreaID .. "." .. a_NumRotations .. ".png"
end





--- Translates Connector.Direction to the shape name to use for PNG export
local g_ShapeName =
{
	[BLOCK_FACE_XM] = "BottomArrowXM",
	[BLOCK_FACE_XP] = "BottomArrowXP",
	[BLOCK_FACE_YP] = "ArrowYP",
	[BLOCK_FACE_YM] = "ArrowYM",
	[BLOCK_FACE_ZM] = "BottomArrowZM",
	[BLOCK_FACE_ZP] = "BottomArrowZP",
}

--- Translates Connector.Direction via NumRotations into the new rotated Direction
local g_RotatedDirection =
{
	[0] =  -- No rotation
	{
		[BLOCK_FACE_XM] = BLOCK_FACE_XM,
		[BLOCK_FACE_XP] = BLOCK_FACE_XP,
		[BLOCK_FACE_YM] = BLOCK_FACE_YM,
		[BLOCK_FACE_YP] = BLOCK_FACE_YP,
		[BLOCK_FACE_ZM] = BLOCK_FACE_ZM,
		[BLOCK_FACE_ZP] = BLOCK_FACE_ZP,
	},
	
	[1] =  -- 1 CW rotation
	{
		[BLOCK_FACE_XM] = BLOCK_FACE_ZM,
		[BLOCK_FACE_XP] = BLOCK_FACE_ZP,
		[BLOCK_FACE_YM] = BLOCK_FACE_YM,
		[BLOCK_FACE_YP] = BLOCK_FACE_YP,
		[BLOCK_FACE_ZM] = BLOCK_FACE_XP,
		[BLOCK_FACE_ZP] = BLOCK_FACE_XM,
	},

	[2] =  -- 2 CW rotations
	{
		[BLOCK_FACE_XM] = BLOCK_FACE_XP,
		[BLOCK_FACE_XP] = BLOCK_FACE_XM,
		[BLOCK_FACE_YM] = BLOCK_FACE_YM,
		[BLOCK_FACE_YP] = BLOCK_FACE_YP,
		[BLOCK_FACE_ZM] = BLOCK_FACE_ZP,
		[BLOCK_FACE_ZP] = BLOCK_FACE_ZM,
	},
	
	[3] =  -- 3 CW rotations
	{
		[BLOCK_FACE_XM] = BLOCK_FACE_ZP,
		[BLOCK_FACE_XP] = BLOCK_FACE_ZM,
		[BLOCK_FACE_YM] = BLOCK_FACE_YM,
		[BLOCK_FACE_YP] = BLOCK_FACE_YP,
		[BLOCK_FACE_ZM] = BLOCK_FACE_XM,
		[BLOCK_FACE_ZP] = BLOCK_FACE_XP,
	},
}





--- Returns a table describing the specified connector, rotated and relativized against a_Area
-- The result also contains the shape name to use for PNG export
local function RotateConnector(a_Connector, a_Area, a_NumRotations)
	-- Check params:
	assert(type(a_Connector) == "table")
	assert(type(a_Area) == "table")
	assert(type(a_NumRotations) == "number")
	
	local res = {y = a_Connector.Y - a_Area.ExportMinY}
	local RelX = a_Connector.X - a_Area.ExportMinX
	local RelZ = a_Connector.Z - a_Area.ExportMinZ
	local SizeX = a_Area.ExportMaxX - a_Area.ExportMinX
	local SizeZ = a_Area.ExportMaxZ - a_Area.ExportMinZ
	
	-- Rotate the XZ coords:
	if (a_NumRotations == 0) then
		res.x = RelX
		res.z = RelZ
	elseif (a_NumRotations == 1) then
		res.x = SizeZ - RelZ
		res.z = RelX
	elseif (a_NumRotations == 2) then
		res.x = SizeX - RelX
		res.z = SizeZ - RelZ
	elseif (a_NumRotations == 3) then
		res.x = RelZ
		res.z = SizeX - RelX
	end
	
	-- Rotate and textualize the marker shape:
	local RotatedDir = g_RotatedDirection[a_NumRotations] or {}
	res.shape = g_ShapeName[RotatedDir[a_Connector.Direction]] or "Cube"
	
	return res
end





--- Uses MCSchematicToPng to convert .schematic files into PNG previews for the specified areas
-- a_Areas is an array of { Area = <db-Area>, NumRotations = <number> }
local ExportCounter = 0
local function ExportPreviewForAreas(a_Areas)
	local stp = g_Config.WebPreview.MCSchematicToPng
	if not(stp) then
		-- MCSchematicToPng is not available, bail out
		return
	end
	stp:ReconnectIfNeeded()
	
	-- Write the list to MCSchematicToPng's TCP link:
	for _, area in ipairs(a_Areas) do
		stp:Write(GetAreaSchematicFileName(area.Area.ID) .. "\n")
		stp:Write(" outfile: " .. GetAreaPreviewFileName(area.Area.ID, area.NumRotations) .. "\n")
		stp:Write(" numcwrotations: " .. area.NumRotations .. "\n")
		stp:Write(" horzsize: 6\n vertsize: 8\n")
		
		local Connectors = g_DB:GetAreaConnectors(area.Area.ID) or {}
		for _, conn in ipairs(Connectors) do
			local rotconn = RotateConnector(conn, area.Area, area.NumRotations)
			stp:Write(" marker: " .. rotconn.x .. ", " .. rotconn.y .. ", " .. rotconn.z .. ", " .. rotconn.shape .. ", ff0000\n")
		end
	end
	stp:Write("\4\n")  -- End of text - process the last area
end





--- Generates the preview files for the specified areas
-- a_Areas is an array of { Area = <db-area>, NumRotations = <number> }
local function GeneratePreviewForAreas(a_Areas)
	if not(a_Areas[1]) then
		return
	end
	
	-- Get a list of .schematic files that need updating
	local ToExport = {}
	for _, area in ipairs(a_Areas) do
		if not(ToExport[area]) then
			local fnam = GetAreaSchematicFileName(area.Area.ID)
			local ftim = FormatDateTime(cFile:GetLastModificationTime(fnam))
			if (area.Area.DateLastChanged > ftim) then
				table.insert(ToExport, area.Area)
			end
			ToExport[area] = true
		end
	end
	
	-- Export the .schematic files for each area, process one are after another, using ChunkStays:
	-- (after one area is written to a file, schedule another ChunkStay for the next area)
	-- Note that due to multithreading, the export needs to be scheduled onto the World Tick thread, otherwise a deadlock may occur
	local ba = cBlockArea()
	local idx = 1
	local ProcessArea
	local LastGalleryName
	local LastWorld
	ProcessArea = function()
		local area = ToExport[idx]
		ba:Read(LastWorld, area.ExportMinX, area.ExportMaxX, area.ExportMinY, area.ExportMaxY, area.ExportMinZ, area.ExportMaxZ)
		cFile:CreateFolder(g_Config.WebPreview.ThumbnailFolder)
		cFile:CreateFolder(GetAreaSchematicFolderName(area.ID))
		ba:SaveToSchematicFile(GetAreaSchematicFileName(area.ID))
		idx = idx + 1
		if (ToExport[idx]) then
			-- When moving to the next gallery or after 10 areas, unload chunks that are no longer needed and queue the task on the new world:
			-- When all chunks are loaded, the ChunkStay produces one deep nested call, going over LUAI_MAXCCALLS
			if (
				(ToExport[idx].GalleryName ~= LastGalleryName) or
				(ToExport[idx].WorldName ~= LastWorld:GetName()) or
				(idx % 10 == 0)
			) then
				LastWorld:QueueUnloadUnusedChunks()
				LastGalleryName = ToExport[idx].GalleryName
				LastWorld = cRoot:Get():GetWorld(ToExport[idx].WorldName)
				LastWorld:QueueTask(
					function()
						LastWorld:ChunkStay(GetAreaChunkCoords(ToExport[idx]), nil, ProcessArea)
					end
				)
			else
				-- Queue the next area on the same world:
				LastWorld:ChunkStay(GetAreaChunkCoords(ToExport[idx]), nil, ProcessArea)
			end
		else
			-- All .schematic files have been exported, generate the preview PNGs:
			ExportPreviewForAreas(a_Areas)
		end
	end
	if (ToExport[1]) then
		-- Queue the export task on the cWorld instance, so that it is executed in the world's Tick thread:
		LastGalleryName = ToExport[1].GalleryName
		LastWorld = cRoot:Get():GetWorld(ToExport[1].WorldName)
		LastWorld:QueueTask(
			function()
				LastWorld:ChunkStay(GetAreaChunkCoords(ToExport[1]), nil, ProcessArea)
			end
		)
	else
		-- All .schematic files have been exported, generate the preview PNGs:
		ExportPreviewForAreas(a_Areas)
	end
end





--- Checks the preview files for the specified areas and regenerates the ones that are outdated
-- a_Areas is an array of areas as loaded from the DB
local function RefreshPreviewForAreas(a_Areas)
	-- Check params and preconditions:
	assert(type(a_Areas) == "table")
	assert(g_Config.WebPreview)
	
	-- Check each area and each rotation:
	local ToExport = {}  -- array of {Area = <db-area>, NumRotations = <number>}
	for _, area in ipairs(a_Areas) do
		for rot = 0, 3 do
			local fnam = GetAreaPreviewFileName(area.ID, rot)
			if (area.DateLastChanged > FormatDateTime(cFile:GetLastModificationTime(fnam))) then
				table.insert(ToExport, { Area = area, NumRotations = rot})
			end
		end
	end

	-- Sort the ToExport array by coords (to help reuse the chunks):
	table.sort(ToExport,
		function (a_Item1, a_Item2)
			-- Compare the X coord first:
			if (a_Item1.Area.MinX < a_Item2.Area.MinX) then
				return true
			end
			if (a_Item1.Area.MinX > a_Item2.Area.MinX) then
				return false
			end
			-- The X coord is the same, compare the Z coord:
			return (a_Item1.Area.MinZ < a_Item2.Area.MinZ)
		end
	)
	
	-- Export each area:
	GeneratePreviewForAreas(ToExport)
end





--- Returns the HTML code that provides group-limiting for the display
local function GetGroupLimiter(a_Request, a_GroupNames)
	-- Check if a limit is already applied:
	local GroupLimit = a_Request.Params["Group"]
	
	-- TODO
	return ""
end





--- Returns the HTML-formatted description of the specified area
local function GetAreaDescription(a_Area)
	assert(type(a_Area) == "table")
	
	-- If the area is not valid, return "<unclaimed>":
	if (a_Area.Name == nil) then
		return "<p style='color: grey'>&lt;unclaimed&gt;</p>"
	end
	
	-- Return the area's name and position, unless they're equal:
	local Position = a_Area.GalleryName .. " " .. a_Area.GalleryIndex
	if not(a_Area.ExportName) then
		return cWebAdmin:GetHTMLEscapedString(Position)
	elseif (Position == a_Area.ExportName) then
		return cWebAdmin:GetHTMLEscapedString(a_Area.ExportName)
	else
		return cWebAdmin:GetHTMLEscapedString(a_Area.ExportName) .. "<br/>(" .. cWebAdmin:GetHTMLEscapedString(Position .. ")")
	end
end





--- Returns the (relative) path to the specified page number, based on the request's path
local function PathToPage(a_RequestPath, a_PageNum)
	local res = "/" .. a_RequestPath .. "?startidx=" .. tostring((a_PageNum - 1) * g_NumAreasPerPage)
	return res
end





--- Returns the pager, positioned by the parameters in a_Request
local function GetPager(a_Request)
	-- Read the request params:
	local StartIdx = a_Request.Params["startidx"] or 0
	local EndIdx = StartIdx + g_NumAreasPerPage - 1
	local CurrentPage = StartIdx / g_NumAreasPerPage + 1
	local Path = a_Request.Path
	local MaxPageNum = math.ceil((g_DB:GetNumApprovedAreas() or 0) / g_NumAreasPerPage)
	
	-- Insert the "first page" link:
	local res = {"<table><tr><th><a href=\""}
	ins(res, PathToPage(Path, 1))
	ins(res, "\">|&lt;&lt;&lt</a></th><th width='100%' style='align: center'><center>")
	
	-- Insert the page links for up to 5 pages in each direction:
	local Pager = {}
	for PageNum = CurrentPage - 5, CurrentPage + 5 do
		if (PageNum == CurrentPage) then
			ins(Pager, "<b>" .. PageNum .. "</b>")
		elseif ((PageNum > 0) and (PageNum <= MaxPageNum)) then
			ins(Pager, table.concat({
				"<a href=\"",
				PathToPage(Path, PageNum),
				"\">",
				PageNum,
				"</a>"
			}))
		end
	end
	ins(res, table.concat(Pager, " | "))
	
	-- Insert the "last page" link:
	ins(res, "</center></th><th><a href=\"")
	ins(res, PathToPage(Path, MaxPageNum))
	ins(res, "\">&gt;&gt;&gt;|</a></th></table>")
	
	return table.concat(res)
end





--- Returns the HTML code for the area list header
local function GetAreasHTMLHeader()
	if (g_Config.TwoLineAreaList) then
		return "<tr><th colspan=6>Preview</th></tr><tr><th>Area</th><th>Group</th><th>Connectors</th><th>Author</th><th>Approved</th><th width='1%'>Action</th></tr>"
	else
		return "<tr><th colspan=4>Preview</th><th>Area</th><th>Group</th><th>Connectors</th><th>Author</th><th>Approved</th><th width='1%'>Action</th></tr>"
	end
end





--- Returns the HTML code for the area's row in the area list
-- a_ExtraActions is an area of extra actions to insert as action buttons
local function GetAreaHTMLRow(a_Area, a_ExtraActions)
	-- Check params:
	assert(type(a_Area) == "table")
	assert(a_Area.ID)
	assert((a_ExtraActions == nil) or (type(a_ExtraActions) == "table"))
	a_ExtraActions = a_ExtraActions or {}

	local res = {}
	if (g_Config.TwoLineAreaList) then
		ins(res, "<tr><td valign='top' colspan=6><table width='100%'><tr><td valign='top'>")
	else
		ins(res, "<tr><td valign='top'>")
	end
	for rot = 0, 3 do
		ins(res, "<img src=\"/~webadmin/GalExport/")
		ins(res, PAGE_NAME_AREAS)
		ins(res, "?action=getpreview&areaid=")
		ins(res, a_Area.ID)
		ins(res, "&rot=")
		ins(res, rot)
		ins(res, "\"/></td><td valign='top'>")
	end
	if (g_Config.TwoLineAreaList) then
		ins(res, "</tr></table></tr><tr><td valign='top'>")
	end
	ins(res, GetAreaDescription(a_Area))
	ins(res, "</td><td valign='top'>")
	ins(res, cWebAdmin:GetHTMLEscapedString(a_Area.ExportGroupName or ""))
	local Metadata = g_DB:GetMetadataForArea(a_Area.ID, false)
	if (tonumber(Metadata["IsStarting"] or 0) ~= 0) then
		ins(res, "<br/><i>Starting area</i>")
	end
	ins(res, "</td><td valign='top'><center>")
	local NumConnectors = g_DB:GetAreaConnectorCount(a_Area.ID)
	if (NumConnectors == 0) then
		ins(res, "<b><font color=\"#f00\">")
	end
	ins(res, NumConnectors)
	if (NumConnectors == 0) then
		ins(res, "</font></b>")
	end
	ins(res, "</center></td><td valign='top'>")
	ins(res, cWebAdmin:GetHTMLEscapedString(a_Area.PlayerName) or "&nbsp;")
	ins(res, "</td><td valign='top'>")
	ins(res, (a_Area.DateApproved or "&nbsp;") .. "<br/>by " .. (a_Area.ApprovedBy or "&lt;unknown&gt;"))
	ins(res, "</td><td valign='top'>")
	ins(res, "<form method=\"GET\" action=\"")
	ins(res, PAGE_NAME_AREAS)
	ins(res, "\">")
	ins(res, GetHTMLInput("hidden", "areaid",  {value = a_Area.ID}))
	ins(res, GetHTMLInput("submit", "details", {value = "Details"}))
	ins(res, GetHTMLInput("hidden", "action",  {value = "areadetails"}))
	ins(res, "</form>")
	
	-- Insert any extra actions:
	for _, act in ipairs(a_ExtraActions) do
		ins(res, "<form method=\"")
		ins(res, act.method or "POST")
		ins(res, "\" action=\"")
		ins(res, act.page or PAGE_NAME_AREAS)
		ins(res, "\">")
		ins(res, GetHTMLInput("hidden", "areaid",  {value = a_Area.ID}))
		ins(res, GetHTMLInput("submit", "do",      {value = act.title}))
		ins(res, GetHTMLInput("hidden", "action",  {value = act.action}))
		ins(res, "</form>")
	end
	ins(res, "</td></tr>")
	
	return table.concat(res)
end





--- Returns the HTML code that provides the <datalist> element for area metas
local function GetAreaMetaNamesHTMLDatalist()
	return [[
		<datalist id="areametanames">
			<option value="AddWeightIfSame">
			<option value="AllowedRotations">
			<option value="DefaultWeight">
			<option value="DepthWeight">
			<option value="IsStarting">
			<option value="MergeStrategy">
			<option value="MoveToGround">
			<option value="ShouldExpandFloor">
		</datalist>
	]]
end





--- Returns the HTML code that provides the <datalist> element for group metas
local function GetGroupMetaNamesHTMLDatalist()
	return [[
		<datalist id="groupmetanames">
			<option value="IntendedUse"/>
			<option value="MaxDensity"/>
			<option value="MinDensity"/>
			<option value="VillageRoadBlockType"/>
			<option value="VillageRoadBlockMeta"/>
			<option value="VillageWaterRoadBlockType"/>
			<option value="VillageWaterRoadBlockMeta"/>
		</datalist>
	]]
end





--- Returns the HTML list of areas, based on the limits in the request
local function GetAreaList(a_Request)
	-- Read the request params:
	local StartIdx = tonumber(a_Request.Params["startidx"]) or 0
	local EndIdx = StartIdx + g_NumAreasPerPage - 1
	
	-- Get the areas from the DB, as a map of Idx -> Area
	local Areas = g_DB:LoadApprovedAreasRange(StartIdx, EndIdx)
	
	-- Queue the areas for re-export:
	local AreaArray = {}
	for idx, area in pairs(Areas) do
		table.insert(AreaArray, area)
	end
	RefreshPreviewForAreas(AreaArray)
	
	-- Build the page:
	local FormDest = "/" .. a_Request.Path .. "?startidx=" .. StartIdx
	local Page = {"<table>"}
	ins(Page, GetAreasHTMLHeader())
	for idx, Area in ipairs(Areas) do
		ins(Page, GetAreaHTMLRow(Area))
	end
	ins(Page, "</table>")
	
	return table.concat(Page)
end





--- Returns the HTML code for the Areas page
local function ShowAreasPage(a_Request)
	local res = {}
	
	local Pager = GetPager(a_Request)
	ins(res, Pager)
	ins(res, GetAreaList(a_Request))
	ins(res, Pager)
	local Groups = g_DB:GetAllGroupNames()
	ins(res, GetGroupLimiter(a_Request, Groups))
	
	return table.concat(res)
end





--- Returns the contents of the requested preview PNG
-- Returns g_PreviewNotAvailableYetPng if the specified preview is not yet available
-- Returns an error if the request is for an invalid preview
local function ExecuteGetPreview(a_Request)
	-- Get the params:
	local areaID = tonumber(a_Request.Params["areaid"])
	local rot = tonumber(a_Request.Params["rot"])
	if not(areaID) or not(rot) then
		return "Invalid identification"
	end
	
	local fnam = GetAreaPreviewFileName(areaID, rot)
	local f, msg = io.open(fnam, "rb")
	if not(f) then
		return g_PreviewNotAvailableYetPng
	end
	local res = f:read("*all")
	f:close()
	return res, "image/png"
end





local function ShowAreaDetails(a_Request)
	-- Check params:
	local AreaID = tonumber(a_Request.Params["areaid"])
	if not(AreaID) then
		return HTMLError("No Area ID selected") .. ShowAreasPage(a_Request)
	end

	-- Load the area:
	local Area = g_DB:GetAreaByID(AreaID)
	if not(Area) then
		return HTMLError("Area " .. AreaID .. " not found") .. ShowAreasPage(a_Request)
	end
	if (not(Area.IsApproved) or not(tonumber(Area.IsApproved) ~= 0)) then
		return HTMLError("Area " .. AreaID .. " has not been approved") .. ShowAreasPage(a_Request)
	end
	RefreshPreviewForAreas({Area})
	
	-- Output the preview:
	local res = {"<table><tr>"}
	for rot = 0, 3 do
		ins(res, "<td valign='top'><img src=\"/~")
		ins(res, a_Request.Path)
		ins(res, "?action=getpreview&areaid=")
		ins(res, Area.ID)
		ins(res, "&rot=")
		ins(res, rot)
		ins(res, "\"/></td>")
	end
	ins(res, "</tr></table>")
	
	-- Output the name editor:
	ins(res, "<table><tr><th>Export name: </th><td><form method=\"POST\">")
	ins(res, GetHTMLInput("hidden", "areaid",   {value = Area.ID}))
	ins(res, GetHTMLInput("hidden", "action",   {value = "renamearea"}))
	ins(res, GetHTMLInput("text",   "areaname", {size = 100, value = cWebAdmin:GetHTMLEscapedString(Area.ExportName or "")}))
	ins(res, GetHTMLInput("submit", "rename",   {value = "Rename"}))
	ins(res, "</form></td></tr>")
	
	-- Output the group editor:
	ins(res, "<tr><th>Export group</th><td><form method=\"POST\">")
	ins(res, GetHTMLInput("hidden", "areaid",    {value = Area.ID}))
	ins(res, GetHTMLInput("hidden", "action",    {value = "regrouparea"}))
	ins(res, GetHTMLInput("text",   "groupname", {size = 100, value = cWebAdmin:GetHTMLEscapedString(Area.ExportGroupName)}))
	ins(res, GetHTMLInput("submit", "regroup",   {value = "Set"}))
	ins(res, "</form><a href=\"Groups?action=groupdetails&groupname=")
	ins(res, cWebAdmin:GetHTMLEscapedString(Area.ExportGroupName))
	ins(res, "\">View group</a></td></tr>")

	-- Define a helper function for adding a property to the view
	local function AddProp(a_Title, a_Value)
		ins(res, "<tr><th>")
		ins(res, cWebAdmin:GetHTMLEscapedString(a_Title))
		ins(res, "</th><td>")
		ins(res, cWebAdmin:GetHTMLEscapedString(a_Value))
		ins(res, "</td></tr>")
	end
	
	-- Output the dimensions, hitbox etc.:
	AddProp("Location", Area.GalleryName .. " " .. Area.GalleryIndex)
	AddProp("Author", Area.PlayerName)
	AddProp("Approved", (Area.DateApproved or "[unknown date]") .. " by " .. (Area.ApprovedBy or "[unknown person]"))
	AddProp("Size X", Area.ExportMaxX - Area.ExportMinX + 1)
	AddProp("Size Y", Area.ExportMaxY - Area.ExportMinY + 1)
	AddProp("Size Z", Area.ExportMaxZ - Area.ExportMinZ + 1)
	AddProp("Hitbox extra X-", Area.ExportMinX - (Area.HitboxMinX or Area.ExportMinX))
	AddProp("Hitbox extra X+", (Area.HitboxMaxX or Area.ExportMaxX) - Area.ExportMaxX)
	AddProp("Hitbox extra Y-", Area.ExportMinY - (Area.HitboxMinY or Area.ExportMinY))
	AddProp("Hitbox extra Y+", (Area.HitboxMaxY or Area.ExportMaxY) - Area.ExportMaxY)
	AddProp("Hitbox extra Z-", Area.ExportMinZ - (Area.HitboxMinZ or Area.ExportMinZ))
	AddProp("Hitbox extra Z+", (Area.HitboxMaxZ or Area.ExportMaxZ) - Area.ExportMaxZ)
	ins(res, "</table>")
	
	-- Output the area metadata:
	ins(res, "<br/><h3>Metadata:</h3><table><tr><th>Name</th><th>Value</th></tr>")
	local Metadata = g_DB:GetMetadataForArea(Area.ID, false)  -- Returns a dictionary {Name = Value}
	local MetaArr = {}  -- Convert into a sorted array of Name-s
	for k, _ in pairs(Metadata) do
		ins(MetaArr, k)
	end
	table.sort(MetaArr)
	for _, md in ipairs(MetaArr) do
		ins(res, "<tr><td>")
		ins(res, cWebAdmin:GetHTMLEscapedString(md))
		ins(res, "</td><td><form method=\"POST\">")
		ins(res, GetHTMLInput("hidden", "areaid",    {value = Area.ID}))
		ins(res, GetHTMLInput("hidden", "action",    {value = "updatemeta"}))
		ins(res, GetHTMLInput("hidden", "metaname",  {value = cWebAdmin:GetHTMLEscapedString(md)}))
		ins(res, GetHTMLInput("text",   "metavalue", {size = 100, value = cWebAdmin:GetHTMLEscapedString(Metadata[md])}))
		ins(res, GetHTMLInput("submit", "update",    {value = "Update"}))
		ins(res, "</form>")

		ins(res, "<form method=\"POST\">")
		ins(res, GetHTMLInput("hidden", "areaid",    {value = Area.ID}))
		ins(res, GetHTMLInput("hidden", "action",    {value = "delmeta"}))
		ins(res, GetHTMLInput("hidden", "metaname",  {value = cWebAdmin:GetHTMLEscapedString(md)}))
		ins(res, GetHTMLInput("submit", "delmeta",   {value = "Del"}))
		ins(res, "</form></td></tr>")
	end
	ins(res, "<tr><td><form method=\"POST\">")
	ins(res, GetHTMLInput("hidden", "areaid",    {value = Area.ID}))
	ins(res, GetHTMLInput("hidden", "action",    {value = "addmeta"}))
	ins(res, GetHTMLInput("text",   "metaname",  {size = 50,  list = "areametanames"}))
	ins(res, "</td><td>")
	ins(res, GetHTMLInput("text",   "metavalue", {size = 100}))
	ins(res, GetHTMLInput("submit", "addmeta",    {value = "Add"}))
	ins(res, GetAreaMetaNamesHTMLDatalist())
	ins(res, "</form></td></tr>")
	ins(res, "</table>")
	
	-- Output the connectors:
	ins(res, "<br/><h3>Connectors:</h3><table><tr><th>Index</th><th>X</th><th>Y</th><th>Z</th><th>Type</th><th>Direction</th></tr>")
	local Connectors = g_DB:GetAreaConnectors(Area.ID)
	for idx, conn in ipairs(Connectors) do
		ins(res, "<tr><td>")
		ins(res, idx)
		ins(res, "</td><td>")
		ins(res, conn.X - Area.ExportMinX)
		ins(res, "</td><td>")
		ins(res, conn.Y - Area.ExportMinY)
		ins(res, "</td><td>")
		ins(res, conn.Z - Area.ExportMinZ)
		ins(res, "</td><td>")
		ins(res, conn.TypeNum)
		ins(res, "</td><td>")
		ins(res, DirectionToString[conn.Direction] or "unknown")
		ins(res, "</td><td>")
		if not(IsConnectorReachableThroughHitbox(conn, Area)) then
			ins(res, "<b>Not reachable through hitbox!</b>")
		else
			ins(res, "&nbsp;")
		end
		ins(res, "</td></tr>")
		-- TODO: "Delete connector" action
	end
	-- TODO: Add new connector
	ins(res, "</table>")
	
	return table.concat(res)
end





local function ExecuteDelMeta(a_Request)
	-- Check params:
	local AreaID = tonumber(a_Request.PostParams["areaid"])
	if not(AreaID) then
		return HTMLError("Invalid Area ID")
	end
	local MetaName = a_Request.PostParams["metaname"]
	if not(MetaName) then
		return HTMLError("Invalid meta name")
	end
	
	-- Delete the meta from the DB:
	local IsSuccess, Msg = g_DB:UnsetAreaMetadata(AreaID, MetaName)
	if not(IsSuccess) then
		return HTMLError("Failed to delete meta: " .. (Msg or "<unknown DB error>"))
	end
	
	-- Display a success page with a return link:
	return "<p>Meta value deleted successfully.</p><p>Return to <a href=\"?action=areadetails&areaid=" .. AreaID .. "\">area details</a>.</p>"
end





local function ExecuteRegroupArea(a_Request)
	-- Check params:
	local AreaID = tonumber(a_Request.PostParams["areaid"])
	if not(AreaID) then
		return HTMLError("Invalid Area ID")
	end
	local NewGroup = a_Request.PostParams["groupname"]
	if not(NewGroup) then
		return HTMLError("Invalid group name")
	end
	
	-- Rename in the DB:
	local IsSuccess, Msg = g_DB:SetAreaExportGroup(AreaID, NewGroup)
	if not(IsSuccess) then
		return HTMLError("Failed to set area group: " .. (Msg or "<unknown DB error>"))
	end
	
	-- Display a success page with a return link:
	return "<p>Area moved to group " .. cWebAdmin:GetHTMLEscapedString(NewGroup) .. " successfully.</p><p>Return to <a href=\"?action=areadetails&areaid=" .. AreaID .. "\">area details</a>.</p>"
end





local function ExecuteRenameArea(a_Request)
	-- Check params:
	local AreaID = tonumber(a_Request.PostParams["areaid"])
	if not(AreaID) then
		return HTMLError("Invalid Area ID")
	end
	local NewName = a_Request.PostParams["areaname"]
	if not(NewName) then
		return HTMLError("Invalid new name")
	end
	
	-- Rename in the DB:
	local IsSuccess, Msg = g_DB:SetAreaExportName(AreaID, NewName)
	if not(IsSuccess) then
		return HTMLError("Failed to rename area: " .. (Msg or "<unknown DB error>"))
	end
	
	-- Display a success page with a return link:
	return "<p>Area renamed successfully.</p><p>Return to <a href=\"?action=areadetails&areaid=" .. AreaID .. "\">area details</a>.</p>"
end





local function ExecuteUpdateMeta(a_Request)
	-- Check params:
	local AreaID = tonumber(a_Request.PostParams["areaid"])
	if not(AreaID) then
		return HTMLError("Invalid Area ID")
	end
	local MetaName = a_Request.PostParams["metaname"]
	if not(MetaName) then
		return HTMLError("Invalid meta name")
	end
	local MetaValue = a_Request.PostParams["metavalue"]
	if not(MetaValue) then
		return HTMLError("Invalid meta value")
	end
	
	-- Update the meta:
	local IsSuccess, Msg = g_DB:SetAreaMetadata(AreaID, MetaName, MetaValue)
	if not(IsSuccess) then
		return HTMLError("Failed to update meta: " .. (Msg or "<unknown DB error>"))
	end
	
	-- Display a success page with a return link:
	return "<p>Meta value updated successfully.</p><p>Return to <a href=\"?action=areadetails&areaid=" .. AreaID .. "\">area details</a>.</p>"
end





--- Returns the HTML code for the Groups page
local function ShowGroupsPage(a_Request)
	-- Get a list of groups from the DB:
	local Groups = g_DB:GetAllGroupNames() or {}
	if not(Groups[1]) then
		return "<p>There are no groups</p>"
	end
	table.sort(Groups)
	
	-- Output the list of groups, with basic info and operations:
	local res = {"<table><tr><th>Group</th><th>Areas</th><th>Starting areas</th><th>Action</th></tr>"}
	for _, grp in ipairs(Groups) do
		local GroupName = cWebAdmin:GetHTMLEscapedString(grp)
		ins(res, "<tr><td>")
		ins(res, GroupName)
		ins(res, "</td><td>")
		ins(res, g_DB:GetGroupAreaCount(grp) or "[unknown]")
		ins(res, "</td><td>")
		local NumStartingAreas = g_DB:GetGroupStartingAreaCount(grp)
		if (NumStartingAreas == 0) then
			ins(res, "<b><font color=\"#f00\">")
		end
		ins(res, NumStartingAreas or "[unknown]")
		if (NumStartingAreas == 0) then
			ins(res, "</font></b>")
		end
		ins(res, "</td><td><form method=\"GET\">")
		ins(res, GetHTMLInput("hidden", "groupname", {value = GroupName}))
		ins(res, GetHTMLInput("hidden", "action",    {value = "groupdetails"}))
		ins(res, GetHTMLInput("submit", "details",   {value = "Details"}))
		ins(res, "</form></td></tr>")
	end  -- for grp - Groups[]
	
	return table.concat(res)
end





local function ShowGroupDetails(a_Request)
	-- Check params:
	local GroupName = a_Request.Params["groupname"]
	if not(GroupName) then
		return HTMLError("No group selected") .. ShowGroupsPage(a_Request)
	end

	-- Output basic group details:
	local res = {"<table><tr><th>Group name</th><td>"}
	ins(res, "<form method=\"POST\">")
	ins(res, GetHTMLInput("hidden", "action", {value = "renamegroup"}))
	ins(res, GetHTMLInput("text",   "name",   {value = cWebAdmin:GetHTMLEscapedString(GroupName)}))
	ins(res, GetHTMLInput("submit", "rename", {value = "Rename"}))
	ins(res, "</form></td></tr><tr><th>Number of areas</th><td>")
	ins(res, g_DB:GetGroupAreaCount(GroupName) or "[unknown]")
	ins(res, "</td></tr></table>")
	
	-- Output the group metadata editor:
	ins(res, "<br/><h3>Group metadata:</h3><table><tr><th>Name</th><th>Value</th><th>Action</th></tr>")
	local Metas = g_DB:GetMetadataForGroup(GroupName)
	local MetaNames = {}
	for k, _ in pairs(Metas) do
		ins(MetaNames, k)
	end
	table.sort(MetaNames)
	local GroupNameHTML = cWebAdmin:GetHTMLEscapedString(GroupName)
	for _, mn in ipairs(MetaNames) do
		ins(res, "<tr><td>")
		ins(res, cWebAdmin:GetHTMLEscapedString(mn))
		ins(res, "</td><td><form method=\"POST\">")
		ins(res, GetHTMLInput("hidden", "groupname", {value = GroupNameHTML}))
		ins(res, GetHTMLInput("hidden", "action",    {value = "setmeta"}))
		ins(res, GetHTMLInput("hidden", "metaname",  {value = cWebAdmin:GetHTMLEscapedString(mn)}))
		ins(res, GetHTMLInput("text",   "metavalue", {size = 100, value = cWebAdmin:GetHTMLEscapedString(Metas[mn])}))
		ins(res, GetHTMLInput("submit", "update",    {value = "Update"}))
		ins(res, "</form></td>")
		ins(res, "<td><form method=\"POST\">")
		ins(res, GetHTMLInput("hidden", "groupname", {value = GroupNameHTML}))
		ins(res, GetHTMLInput("hidden", "metaname",  {value = cWebAdmin:GetHTMLEscapedString(mn)}))
		ins(res, GetHTMLInput("hidden", "action",    {value = "delmeta"}))
		ins(res, GetHTMLInput("submit", "del",       {value = "Del"}))
		ins(res, "</form></td>")
		ins(res, "</tr>")
	end
	
	-- Output the new metadata entry form:
	ins(res, "<tr><td><form method=\"POST\">")
	ins(res, GetHTMLInput("hidden", "groupname", {value = GroupNameHTML}))
	ins(res, GetHTMLInput("hidden", "action",    {value = "setmeta"}))
	ins(res, GetHTMLInput("text",   "metaname",  {size = 50, list = "groupmetanames"}))
	ins(res, "</td><td>")
	ins(res, GetHTMLInput("text",   "metavalue", {size = 100}))
	ins(res, GetHTMLInput("submit", "add",       {value = "Add"}))
	ins(res, GetGroupMetaNamesHTMLDatalist())
	ins(res, "</form></td></tr>")
	ins(res, "</table>")
	
	-- Queue the group's areas for re-export:
	local Areas = g_DB:GetApprovedAreasInGroup(GroupName)
	RefreshPreviewForAreas(Areas)
	
	-- Output the group's areas:
	SortAreas(Areas)
	ins(res, "<br/><h3>Group's areas:</h3><table>")
	ins(res, GetAreasHTMLHeader())
	for _, area in ipairs(Areas) do
		ins(res, GetAreaHTMLRow(area))
	end
	ins(res, "</table>")
	
	return table.concat(res)
end





local function ExecuteDelGroupMeta(a_Request)
	-- Check params:
	local GroupName = a_Request.PostParams["groupname"]
	if not(GroupName) then
		return HTMLError("Invalid Group name")
	end
	local MetaName = a_Request.PostParams["metaname"]
	if not(MetaName) then
		return HTMLError("Invalid meta name")
	end

	-- Delete the meta from the DB:
	local IsSuccess, Msg = g_DB:UnsetGroupMetadata(GroupName, MetaName)
	if not(IsSuccess) then
		return HTMLError("Failed to delete meta: " .. (Msg or "<unknown DB error>"))
	end
	
	-- Display a success page with a return link:
	return "<p>Meta value deleted successfully.</p><p>Return to <a href=\"?action=groupdetails&groupname=" .. cWebAdmin:GetHTMLEscapedString(GroupName) .. "\">group details</a>.</p>"
end





local function ExecuteSetGroupMeta(a_Request)
	-- Check params:
	local GroupName = a_Request.PostParams["groupname"]
	if not(GroupName) then
		return HTMLError("Invalid Group name")
	end
	local MetaName = a_Request.PostParams["metaname"]
	if not(MetaName) then
		return HTMLError("Invalid meta name")
	end
	local MetaValue = a_Request.PostParams["metavalue"]
	if not(MetaValue) then
		return HTMLError("Invalid meta value")
	end
	
	-- Update the meta:
	local IsSuccess, Msg = g_DB:SetGroupMetadata(GroupName, MetaName, MetaValue)
	if not(IsSuccess) then
		return HTMLError("Failed to set meta: " .. (Msg or "<unknown DB error>"))
	end
	
	-- Display a success page with a return link:
	return "<p>Meta value has been set successfully.</p><p>Return to <a href=\"?action=groupdetails&groupname=" .. cWebAdmin:GetHTMLEscapedString(GroupName) .. "\">group details</a>.</p>"
end





--- Returns the entire Maintenance page contents
local function ShowMaintenancePage(a_Request)
	return [[
		<h3>Lock approved areas</h3>
		<p>Locks all areas that are approved for export. This prevents even their owners from editing them, thus
		preserving the area as approved. Users with the "gallery.admin.overridelocked" permissions may still
		edit the area. Note that area metadata can still be edited even after locking an area.</p>
		<form method="POST">
		<input type="hidden" name="action" value="lockapproved"/>
		<input type="submit" value="Lock approved areas"/>
		</form>
		<br/><hr/><br/>
		<h3>Unlock all areas</h3>
		<p>Unlocks all areas. All previously locked areas are unlocked, allowing their original authors to edit
		them. Note that this operation is not generally reversible and anyway is highly discouraged.</p>
		<form method="POST">
		<input type="hidden" name="action" value="unlockall"/>
		<input type="submit" value="Unlock all areas"/>
		</form>
		<br/><hr/><br/>
	]]
end





--- Deletes the specified connector and returns the HTML to redirect back to Maintenance page
local function ExecuteDelConn(a_Request)
	-- Check params:
	local ConnID = tonumber(a_Request.PostParams["connid"])
	if not(ConnID) then
		return HTMLError("Invalid ConnID")
	end

	-- Delete  the connector:
	local IsSuccess, Msg = g_DB:DeleteConnector(ConnID)
	if not(IsSuccess) then
		return HTMLError("Cannot delete connector from the DB: " .. cWebAdmin:GetHTMLEscapedString(Msg or "<unknown DB error>"))
	end
	
	-- Return the HTML:
	return [[
		<p>Connector has been deleted. Return to the <a href="?action=">Connectors page</a></p>
	]]
end





--- Locks all approved areas and returns the HTML to redirect back to Maintenance page
local function ExecuteLockApprovedAreas(a_Request)
	local IsSuccess, Msg = g_DB:LockApprovedAreas()
	if not(IsSuccess) then
		return HTMLError("Cannot lock approved areas: " .. cWebAdmin:GetHTMLEscapedString(Msg or "<unknown DB error>"))
	end
	
	return [[
		<p>Approved areas have been locked.</p>
		<p>Return to the <a href="?action=">Maintenance page</a></p>
	]]
end





--- Helper function that sets the sponging for the area specified in the request to single-blocktype-filled
-- Returns HTML code to either indicate an error, or success
local function SetSponge(a_Request, a_BlockType, a_BlockMeta)
	-- Check params:
	assert(type(a_BlockType) == "number")
	assert(type(a_BlockMeta) == "number")
	local AreaID = tonumber(a_Request.PostParams["areaid"])
	if not(AreaID) then
		return HTMLError("Invalid AreaID.")
	end
	local Area = g_DB:GetAreaByID(AreaID)
	if not(Area) then
		return HTMLError("No such area.")
	end
	
	-- Create the BlockArea to use as the sponging:
	local img = cBlockArea()
	img:Create(Area.MaxX - Area.MinX, 256, Area.MaxZ - Area.MinZ)
	img:Fill(a_BlockType, a_BlockMeta)
	
	-- Update the DB:
	g_DB:SetAreaSponging(AreaID, img)
	img:Clear()
	
	return [[
		<p>Area sponge has been set.</p>
		<p>Return to the <a href="?action=">Sponging page</a></p>
	]]
end





--- Adds an empty sponging for the specified area and returns the HTML to redirect back to Maintenance page
local function ExecuteSetSpongeEmpty(a_Request)
	return SetSponge(a_Request, E_BLOCK_AIR, 0)
end





--- Adds a full sponging for the specified area and returns the HTML to redirect back to Maintenance page
local function ExecuteSetSpongeFull(a_Request)
	return SetSponge(a_Request, E_BLOCK_SPONGE, 0)
end





--- Unlocks all areas and returns the HTML to redirect back to Maintenance page
local function ExecuteUnlockAllAreas(a_Request)
	local IsSuccess, Msg = g_DB:UnlockAllAreas()
	if not(IsSuccess) then
		return HTMLError("Cannot unlock all areas: " .. cWebAdmin:GetHTMLEscapedString(Msg or "<unknown DB error>"))
	end
	
	return [[
		<p>All areas have been unlocked.</p>
		<p>Return to the <a href="?action=">Maintenance page</a></p>
	]]
end





--- Actions to be inserted for each area in the sponging check result area list
local g_SpongingActions =
{
	{ action = "setspongeempty", title = "Use no sponges",  page = PAGE_NAME_CHECKSPONGING },
	{ action = "setspongefull",  title = "Use all sponges", page = PAGE_NAME_CHECKSPONGING },
}

--- Returns the HTML contents of the entire CheckSponging page
local function ShowCheckSpongingPage(a_Request)
	-- Load from DB:
	local AllAreas, AllGroups, SpongedAreaIDs, Msg
	AllAreas, Msg = g_DB:GetAllApprovedAreas()
	if not(AllAreas) then
		return HTMLError("Cannot query the DB for approved areas: " .. (Msg or "<unknown DB error>"))
	end
	AllGroups, Msg = g_DB:GetAllGroupNames()
	if not(AllGroups) then
		return HTMLError("Cannot query the DB for export groups: " .. (Msg or "<unknown DB error>"))
	end
	SpongedAreaIDs, Msg = g_DB:GetSpongedAreaIDsMap()
	if not(SpongedAreaIDs) then
		return HTMLError("Cannot query the DB for sponged areas: " .. (Msg or "<unknown DB error>"))
	end
	
	-- Prepare the intended use for each export group:
	local GroupIntendedUse = {}  -- Map of "GroupName" -> <IntendedUseLowerCase>
	for _, grpName in ipairs(AllGroups) do
		local GroupMetas = g_DB:GetMetadataForGroup(grpName) or {}
		GroupIntendedUse[grpName] = string.lower(GroupMetas["IntendedUse"] or "")
	end
	
	-- Check each area:
	local Issues = {}
	for _, area in ipairs(AllAreas) do
		if (
			not(SpongedAreaIDs[area.ID]) and  -- Area is not sponged
			not(g_SpongelessIntendedUse[GroupIntendedUse[area.ExportGroupName]])  -- Area is in an export group that needs sponging
		) then
			ins(Issues, area)
		end
	end
	
	-- If all OK, return the special text for All OK:
	if not(Issues[1]) then
		return [[
			All approved areas have met their sponging requirements. No action is necessary.
		]]
	end
	
	-- List the unsponged areas:
	local res = {
		[[
			<p>Areas listed below are in a group that requires sponging (based on its IntendedUse metadata) but don't
			have their sponging defined in the DB.</p>
			<table>
		]],
		GetAreasHTMLHeader()
	}
	for _, area in ipairs(Issues) do
		ins(res, GetAreaHTMLRow(area, g_SpongingActions))
	end  -- for id - IDs[]
	RefreshPreviewForAreas(Issues)
	
	return table.concat(res)
end





--- Returns the HTML contents of the entire CheckConnectors page
local function ShowCheckConnectorsPage(a_Request)
	local res = {[[
		<a name="connectors"><h3>Check connectors</h3></a>
		<p>Checks each approved area's connectors for basic sanity:
		<ul>
			<li>Connector has to be on hitbox border</li>
			<li>Each area has at least one connector</li>
			<li>Each connector type has a counter-type present in the same group</li>
		</ul>
		</p>
		<table>
	]]}
	
	-- Load all from DB, convert areas from array to map of AreaID -> {AreaDesc}
	local Connectors = g_DB:GetAllConnectors()
	local AreasArr = g_DB:GetAllApprovedAreas()
	local Areas = {}
	for _, area in ipairs(AreasArr) do
		Areas[area.ID] = area
	end
	
	-- Process each connector:
	local Issues = {}
	local ConnectorTypeCounts = {}
	for _, conn in ipairs(Connectors) do
		local area = Areas[conn.AreaID]
		if not(area) then
			ins(res, "<tr><td>Connector ")
			ins(res, conn.ID)
			ins(res, "</td><td>Area is not approved</td><td>")
			ins(res, "<form method=\"POST\">")
			ins(res, GetHTMLInput("hidden", "action",  {value = "delconn"}))
			ins(res, GetHTMLInput("hidden", "connid",  {value = conn.ID}))
			ins(res, GetHTMLInput("submit", "delconn", {value = "Delete connector"}))
			ins(res, "</form></td></tr>")
		elseif not(IsConnectorReachableThroughHitbox(conn, area)) then
			ins(res, "<tr><td>Connector ")
			ins(res, conn.ID)
			ins(res, " (<a href=\"")
			ins(res, PAGE_NAME_AREAS)
			ins(res, "?action=areadetails&areaid=")
			ins(res, area.ID)
			ins(res, "\">")
			ins(res, GetAreaDescription(area))
			ins(res, "</a>)</td><td>Connector not on hitbox border, it will never connect to anything</td><td/></tr>")
		else
			-- Collect per-group connector type counts:
			local ctc = ConnectorTypeCounts[area.ExportGroupName]
			if not(ctc) then
				ctc = {}
				ConnectorTypeCounts[area.ExportGroupName] = ctc
			end
			ctc[conn.TypeNum] = (ctc[conn.TypeNum] or 0) + 1
		end
	end
	
	-- Villages have extra roads not included in the export group, add their connectors to the counts
	for grpName, counts in pairs(ConnectorTypeCounts) do
		local GroupMetas = g_DB:GetMetadataForGroup(grpName) or {}
		local IntendedUse = string.lower(GroupMetas["IntendedUse"] or "")
		if (IntendedUse == "village") then
			counts[-2] = (counts[-2] or 0) + 2
			counts[1]  = (counts[1]  or 0) + 2
		end
	end

	-- Check per-group connector type counts:
	for grpName, counts in pairs(ConnectorTypeCounts) do
		for connType, connCount in pairs(counts) do
			if ((counts[-connType] or 0) == 0) then
				local HtmlName = cWebAdmin:GetHTMLEscapedString(grpName)
				ins(res, "<tr><td><a href=\"")
				ins(res, PAGE_NAME_GROUPS)
				ins(res, "?action=groupdetails&groupname=")
				ins(res, HtmlName)
				ins(res, "\">Group ")
				ins(res, HtmlName)
				ins(res, "</a></td><td>Connector type ")
				ins(res, connType)
				ins(res, " has no counter-connector</td><td/></tr>")
			end
		end
	end
	
	-- Check that each area has at least one connector:
	for _, conn in ipairs(Connectors) do
		local area = Areas[conn.AreaID] or {}
		area.HasConnector = true
	end
	for _, area in pairs(Areas) do
		if not(area.HasConnector) then
			ins(res, "<tr><td><a href=\"")
			ins(res, PAGE_NAME_AREAS)
			ins(res, "?action=areadetails&areaid=")
			ins(res, area.ID)
			ins(res, "\">")
			ins(res, GetAreaDescription(area))
			ins(res, "</a></td><td>Area has no connectors</td><td/></tr>")
		end
	end
	ins(res, "</table>")
	
	return table.concat(res)
end





local g_PathSep = cFile:GetPathSeparator()





--- Returns the folder where exports for the specified group using the specified exporter are saved
-- The returned string doesn't terminate with a path separator
local function GetExportBaseFolder(a_GroupName, a_ExporterName)
	-- Check params:
	assert(type(a_GroupName) == "string")
	assert(type(a_ExporterName) == "string")
	
	
	return
		g_Config.WebPreview.ThumbnailFolder .. g_PathSep ..
		"exports" .. g_PathSep ..
		a_ExporterName .. g_PathSep ..
		a_GroupName
end





--- Returns the contents of a folder, including the contents of its subfolders
-- The items returned are specified relative to a_Folder
local function GetFolderContentsRecursive(a_Folder)
	-- Check params:
	assert(type(a_Folder) == "string")
	
	local ImmediateContents = cFile:GetFolderContents(a_Folder)
	local BaseFolder = a_Folder .. g_PathSep
	local res = {}
	for _, item in ipairs(ImmediateContents) do
		if ((item ~= ".") and (item ~= "..")) then
			local ItemName = BaseFolder .. item
			if (cFile:IsFolder(ItemName)) then
				for _, subitem in ipairs(GetFolderContentsRecursive(ItemName)) do
					ins(res, item .. g_PathSep .. subitem)
				end
			else
				ins(res, item)
			end
		end  -- if (not "." and not "..")
	end  -- for item - ImmediateContents[]
	
	return res
end





local function GetExportFileDownloadLink(a_ExporterName, a_GroupNameHtml, a_FileName)
	-- Check params:
	assert(type(a_ExporterName) == "string")
	assert(type(a_GroupNameHtml) == "string")
	assert(type(a_FileName) == "string")
	
	local res = {"<a href='/~webadmin/GalExport/", PAGE_NAME_EXPORTS, "?action=dl&exporter=" }
	ins(res, a_ExporterName)
	ins(res, "&groupname=")
	ins(res, a_GroupNameHtml)
	ins(res, "&fnam=")
	ins(res, cWebAdmin:GetHTMLEscapedString(a_FileName))
	ins(res, "' download='")
	ins(res, a_FileName)
	ins(res, "'>Download</a>")
	return table.concat(res)
end





--- Returns the HTML contents of a single exporter table cell for the specified group
local function GetGroupExporterCell(a_GroupName, a_ExporterDesc)
	-- Check params:
	assert(type(a_GroupName) == "string")
	assert(type(a_ExporterDesc) == "table")
	assert(a_ExporterDesc.Name)
	
	local ExportButtonText = "Export"
	local ExportIdentifier = a_ExporterDesc.Name .. "|" .. a_GroupName

	-- If the export is pending, return a non-interactive info text:
	if (g_PendingExports[ExportIdentifier]) then
		return "Pending since " .. g_PendingExports[ExportIdentifier]
	end

	local res = {}

	-- Locate any previous results:
	local BaseFolder = GetExportBaseFolder(a_GroupName, a_ExporterDesc.Name)
	if (cFile:IsFolder(BaseFolder)) then
		local LastExportDateTime = FormatDateTime(cFile:GetLastModificationTime(BaseFolder))
		ins(res, "Last exported: ")
		ins(res, LastExportDateTime)

		ins(res, "<form method='POST'>")
		ins(res, GetHTMLInput("hidden", "action",    {value = "exportgroup"}))
		ins(res, GetHTMLInput("hidden", "groupname", {value = a_GroupName}))
		ins(res, GetHTMLInput("hidden", "exporter",  {value = a_ExporterDesc.Name}))
		ins(res, GetHTMLInput("submit", "export",    {value = "Re-export"}))
		ins(res, "</form>")
	
		-- If there's only a single file, give a link to it directly:
		local files = GetFolderContentsRecursive(BaseFolder)
		if (files[1] and not(files[2])) then
			ins(res, GetExportFileDownloadLink(a_ExporterDesc.Name, a_GroupName, files[1]))
		else
			ins(res, "<form method='GET'>")
			ins(res, GetHTMLInput("hidden", "action",    {value = "listfiles"}))
			ins(res, GetHTMLInput("hidden", "groupname", {value = a_GroupName}))
			ins(res, GetHTMLInput("hidden", "exporter",  {value = a_ExporterDesc.Name}))
			ins(res, GetHTMLInput("submit", "list",      {value = "List files"}))
			ins(res, "</form><br/>")
		end
	else
		ins(res, "[not yet exported]")
		ins(res, "<form method='POST'>")
		ins(res, GetHTMLInput("hidden", "action",    {value = "exportgroup"}))
		ins(res, GetHTMLInput("hidden", "groupname", {value = a_GroupName}))
		ins(res, GetHTMLInput("hidden", "exporter",  {value = a_ExporterDesc.Name}))
		ins(res, GetHTMLInput("submit", "export",    {value = "Export"}))
		ins(res, "</form><br/>")
	end

	return table.concat(res)
end





--- Returns the HTML contents of the entire Exports page
local function ShowExportsPage(a_Request)
	-- Add a per-exporter header:
	local res = {"<table><tr><th>Group</th>"}
	for _, exporter in ipairs(g_ExporterDescs) do
		ins(res, "<th>")
		ins(res, exporter.Title)
		ins(res, "</th>")
	end
	ins(res, "</tr><tr>")
	
	-- Output a row for each group:
	local AllGroups = g_DB:GetAllGroupNames()
	table.sort(AllGroups)
	for _, grpName in ipairs(AllGroups) do
		ins(res, "<td valign='top'>")
		ins(res, grpName)
		ins(res, "</td>")
		for _, exporter in ipairs(g_ExporterDescs) do
			ins(res, "<td valign='top'>")
			ins(res, GetGroupExporterCell(grpName, exporter))
			ins(res, "</td>")
		end
		ins(res, "</tr>")
	end
	ins(res, "</table>")
	
	return table.concat(res)
end





--- Queues an export of the specified group using the specified exporter
-- Returns the HTML code to navigate back to the Exports page
local function ExecuteExportGroup(a_Request)
	-- Check params:
	local ExporterName = a_Request.PostParams["exporter"]
	if not(ExporterName) then
		return HTMLError("Missing exporter name")
	end
	local Exporter = g_Exporters[ExporterName]
	if not(Exporter) then
		return HTMLError("Invalid exporter name")
	end
	local GroupName = a_Request.PostParams["groupname"]
	if not(GroupName) then
		return HTMLError("Missing group name")
	end
	
	-- Before export, clear the destination folder:
	local BaseFolder = GetExportBaseFolder(GroupName, ExporterName)
	cFile:CreateFolderRecursive(BaseFolder)
	cFile:DeleteFolderContents(BaseFolder)
	
	-- Get the area ident for each area in the group:
	local Areas, Msg = g_DB:GetApprovedAreasInGroup(GroupName)
	if (not(Areas) or not(Areas[1])) then
		return HTMLError("Cannot load areas in group: " .. (Msg or "[unknown DB error]"))
	end
	
	-- Mark the export as pending:
	local ExportIdentifier = ExporterName .. "|" .. GroupName
	g_PendingExports[ExportIdentifier] = FormatDateTime(os.time())
	
	-- Queue the export:
	Exporter.ExportGroup(BaseFolder, Areas,
		function()  -- success callback
			LOG("Successfully exported group " .. GroupName .. " using exporter " .. ExporterName)
			g_PendingExports[ExportIdentifier] = nil
		end,
		function(a_ErrMsg)  -- failure callback
			LOG("Export for group " .. GroupName .. " using exporter " .. ExporterName .. " has failed (" .. (a_ErrMsg or "<uknown error>") .. "), removing folder")
			g_PendingExports[ExportIdentifier] = nil
			DeleteFolderRecursive(BaseFolder)
		end
	)
	
	return
	[[
		<p>Export was queued. Return to the <a href="?action=">Exports page</a>.</p>
	]]
end





local function ExecuteListFiles(a_Request)
	-- Check params:
	local ExporterName = a_Request.PostParams["exporter"]
	if not(ExporterName) then
		return HTMLError("Missing exporter name")
	end
	local Exporter = g_Exporters[ExporterName]
	if not(Exporter) then
		return HTMLError("Invalid exporter name")
	end
	local GroupName = a_Request.PostParams["groupname"]
	if not(GroupName) then
		return HTMLError("Missing group name")
	end
	
	-- Get the filelist:
	local BaseFolder = GetExportBaseFolder(GroupName, ExporterName)
	local Files = GetFolderContentsRecursive(BaseFolder)
	if not(Files[1]) then
		return "<p>No files produced by the export</p>"
	end
	
	-- List all files with their download link:
	local res = {"<table><tr><th>FileName</th><th>Size</th><th>Download</th></tr>"}
	local GroupNameHtml = cWebAdmin:GetHTMLEscapedString(GroupName)
	for _, fnam in ipairs(Files) do
		ins(res, "<tr><td>")
		ins(res, cWebAdmin:GetHTMLEscapedString(fnam))
		ins(res, "</td><td>")
		ins(res, (cFile:GetSize(BaseFolder .. g_PathSep .. fnam)))
		ins(res, "</td><td>")
		ins(res, GetExportFileDownloadLink(ExporterName, GroupName, fnam))
		ins(res, "</td></tr>")
	end
	ins(res, "</table>")
	
	return table.concat(res)
end





--- Returns the contents of the specified file
local function DownloadExportedFile(a_Request)
	-- Check params:
	local ExporterName = a_Request.PostParams["exporter"]
	if not(ExporterName) then
		return HTMLError("Missing exporter name")
	end
	local Exporter = g_Exporters[ExporterName]
	if not(Exporter) then
		return HTMLError("Invalid exporter name")
	end
	local GroupName = a_Request.PostParams["groupname"]
	if not(GroupName) then
		return HTMLError("Missing group name")
	end
	local FileName = a_Request.PostParams["fnam"]
	if not(FileName) then
		return HTMLError("Missing file name")
	end
	
	local BaseFolder = GetExportBaseFolder(GroupName, ExporterName)
	return cFile:ReadWholeFile(BaseFolder .. g_PathSep .. FileName)
end





-- Action handlers for the Areas page:
local g_AreasActionHandlers =
{
	[""]            = ShowAreasPage,
	["addmeta"]     = ExecuteUpdateMeta,  -- "Add" has the same handling as "Update" - translates to "DB set"
	["areadetails"] = ShowAreaDetails,
	["delmeta"]     = ExecuteDelMeta,
	["getpreview"]  = ExecuteGetPreview,
	["regrouparea"] = ExecuteRegroupArea,
	["renamearea"]  = ExecuteRenameArea,
	["updatemeta"]  = ExecuteUpdateMeta,
}





-- Action handlers for the Groups page:
local g_GroupsActionHandlers =
{
	[""]             = ShowGroupsPage,
	["areadetails"]  = ShowAreaDetails,
	["delmeta"]      = ExecuteDelGroupMeta,
	["getpreview"]   = ExecuteGetPreview,
	["groupdetails"] = ShowGroupDetails,
	["setmeta"]      = ExecuteSetGroupMeta,
}





--- Action handlers for the Maintenance page:
local g_MaintenanceActionHandlers =
{
	[""]               = ShowMaintenancePage,
	["lockapproved"]   = ExecuteLockApprovedAreas,
	["unlockall"]      = ExecuteUnlockAllAreas,
}





local g_CheckSpongingActionHandlers =
{
	[""]               = ShowCheckSpongingPage,
	["setspongeempty"] = ExecuteSetSpongeEmpty,
	["setspongefull"]  = ExecuteSetSpongeFull,
}





local g_CheckConnectorsActionHandlers =
{
	[""]        = ShowCheckConnectorsPage,
	["delconn"] = ExecuteDelConn,
}





local g_ExportsActionHandlers =
{
	[""]            = ShowExportsPage,
	["dl"]          = DownloadExportedFile,
	["listfiles"]   = ExecuteListFiles,
	["exportgroup"] = ExecuteExportGroup,
}





--- Returns a functino that takes a HTTP request and returns the HTML page, using the specified action handlers
local function CreateRequestHandler(a_ActionHandlers)
	return function(a_Request)
		local Action = (a_Request.PostParams["action"] or "")
		local Handler = a_ActionHandlers[Action]
		if (Handler == nil) then
			return HTMLError("An internal error has occurred, no handler for action " .. Action .. ".")
		end
		
		local PageContent = Handler(a_Request)
		
		return PageContent
	end
end





--- Registers the web page in the webadmin
function InitWeb()
	-- If web preview is not configured, don't register the webadmin tab:
	if not(g_Config.WebPreview) then
		LOG("GalExport: WebPreview is not enabled in the settings.")
		return
	end

	-- Register the webadmin tabs:
	local Plugin = cPluginManager:Get():GetCurrentPlugin()
	Plugin:AddWebTab(PAGE_NAME_AREAS,           CreateRequestHandler(g_AreasActionHandlers))
	Plugin:AddWebTab(PAGE_NAME_GROUPS,          CreateRequestHandler(g_GroupsActionHandlers))
	Plugin:AddWebTab(PAGE_NAME_MAINTENANCE,     CreateRequestHandler(g_MaintenanceActionHandlers))
	Plugin:AddWebTab(PAGE_NAME_CHECKSPONGING,   CreateRequestHandler(g_CheckSpongingActionHandlers))
	Plugin:AddWebTab(PAGE_NAME_CHECKCONNECTORS, CreateRequestHandler(g_CheckConnectorsActionHandlers))
	Plugin:AddWebTab(PAGE_NAME_EXPORTS,         CreateRequestHandler(g_ExportsActionHandlers))

	-- Read the "preview not available yet" image:
	g_PreviewNotAvailableYetPng = cFile:ReadWholeFile(cPluginManager:GetCurrentPlugin():GetLocalFolder() .. "/PreviewNotAvailableYet.png")
end




