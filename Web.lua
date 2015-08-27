
-- Web.lua

-- Implements the webadmin interface





local ins = table.insert
local g_NumAreasPerPage = 50

-- Contains the PNG file for "Preview not available yet" image
local g_PreviewNotAvailableYetPng





local DirectionToString =
{
	[BLOCK_FACE_XM] = "X-",
	[BLOCK_FACE_XP] = "X+",
	[BLOCK_FACE_YM] = "Y-",
	[BLOCK_FACE_YP] = "Y+",
	[BLOCK_FACE_ZM] = "Z-",
	[BLOCK_FACE_ZP] = "Z+",
}





--- Returns the HTML-formatted error message with the specified reason
local function HTMLError(a_Reason)
	return "<b style='color: #a00'>" .. cWebAdmin:GetHTMLEscapedString(a_Reason) .. "</b>"
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





--- Uses MCSchematicToPng to convert .schematic files into PNG previews for the specified areas
-- a_Areas is an array of { Area = <db-Area>, NumRotations = <number> }
local ExportCounter = 0
local function ExportPreviewForAreas(a_Areas)
	-- Write the list file:
	local fnam = g_Config.WebPreview.ThumbnailFolder .. "/export" .. ExportCounter .. ".txt"
	ExportCounter = ExportCounter + 1
	local f, msg = io.open(fnam, "w")
	if not(f) then
		LOG(PLUGIN_PREFIX .. "Cannot export preview, failed to open list file for MCSchematicToPng: " .. (msg or "<unknown error>"))
		return
	end
	for _, area in ipairs(a_Areas) do
		f:write(GetAreaSchematicFileName(area.Area.ID) .. "\n")
		f:write(" outfile: " .. GetAreaPreviewFileName(area.Area.ID, area.NumRotations) .. "\n")
		f:write(" numcwrotations: " .. area.NumRotations .. "\n")
	end
	f:close()
	f = nil
	
	-- Start MCSchematicToPng:
	local cmdline = g_Config.WebPreview.MCSchematicToPng .. " " .. fnam .. " >" .. fnam .. ".out 2>" .. fnam .. ".err"
	if (cFile:GetExecutableExt() == ".exe") then
		-- We're on a Windows-like OS, use "start /b <cmd>" to execute in the background:
		cmdline = "start /b " .. cmdline
	else
		-- We're on a Linux-like OS, use "<cmd> &" to execute in the background:
		cmdline = cmdline .. " &"
	end
	os.execute(cmdline)  -- There's no platform-independent way of checking the result
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
	
	local ToExport = {}  -- array of {Area = <db-area>, NumRotations = <number>}
	for _, area in ipairs(a_Areas) do
		local fnam = g_Config.WebPreview.ThumbnailFolder .. "/" .. area.GalleryName .. "/" .. area.GalleryIndex
		if (area.DateLastChanged > FormatDateTime(cFile:GetLastModificationTime(fnam .. ".0.png"))) then
			table.insert(ToExport, { Area = area, NumRotations = 0})
		end
		if (area.DateLastChanged > FormatDateTime(cFile:GetLastModificationTime(fnam .. ".1.png"))) then
			table.insert(ToExport, { Area = area, NumRotations = 1})
		end
		if (area.DateLastChanged > FormatDateTime(cFile:GetLastModificationTime(fnam .. ".2.png"))) then
			table.insert(ToExport, { Area = area, NumRotations = 2})
		end
		if (area.DateLastChanged > FormatDateTime(cFile:GetLastModificationTime(fnam .. ".3.png"))) then
			table.insert(ToExport, { Area = area, NumRotations = 3})
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
	local Page = {"<table><tr><th colspan=4>Preview</th><th>Area</th><th>Group</th><th>Author</th><th>Approved</th><th width='1%'>Action</th></tr>" }
	for idx, Area in ipairs(Areas) do
		ins(Page, "<tr><td valign='top'>")
		for rot = 0, 3 do
			ins(Page, "<img src=\"/~")
			ins(Page, a_Request.Path)
			ins(Page, "?action=getpreview&areaid=")
			ins(Page, Area.ID)
			ins(Page, "&rot=")
			ins(Page, rot)
			ins(Page, "\"/></td><td valign='top'>")
		end
		ins(Page, GetAreaDescription(Area))
		ins(Page, "</td><td valign='top'>")
		ins(Page, cWebAdmin:GetHTMLEscapedString(Area.ExportGroupName or ""))
		ins(Page, "</td><td valign='top'>")
		ins(Page, cWebAdmin:GetHTMLEscapedString(Area.PlayerName) or "&nbsp;")
		ins(Page, "</td><td valign='top'>")
		ins(Page, (Area.DateApproved or "&nbsp;") .. "<br/>by " .. (Area.ApprovedBy or "&lt;unknown&gt;"))
		ins(Page, "</td><td valign='top'>")
		ins(Page, "<form method=\"GET\"><input type=\"hidden\" name=\"areaid\" value=\"")
		ins(Page, Area.ID)
		ins(Page, "\"/><input type=\"submit\" value=\"Details\"/><input type=\"hidden\" name=\"action\" value=\"areadetails\"/></form>")
		-- ins(Page, AddActionButton("unapprove", FormDest, Area.ID, a_Gallery.Name, idx, "Un-approve"))
		ins(Page, "</td></tr>")
	end
	
	return table.concat(Page)
end





--- Returns the HTML code for the main page
local function ShowMainPage(a_Request)
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
		return HTMLError("No Area ID selected") .. ShowMainPage(a_Request)
	end

	-- Load the area:
	local Area = g_DB:GetAreaByID(AreaID)
	if not(Area) then
		return HTMLError("Area " .. AreaID .. " not found") .. ShowMainPage(a_Request)
	end
	
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
	ins(res, "<table><tr><th>Export name: </th><td><form method=\"POST\"><input type=\"hidden\" name=\"areaid\" value=\"")
	ins(res, Area.ID)
	ins(res, "\"/><input type=\"hidden\" name=\"action\" value=\"renamearea\"/><input type=\"text\" name=\"areaname\" size=100 value=\"")
	ins(res, cWebAdmin:GetHTMLEscapedString(Area.ExportName))
	ins(res, "\"/><input type=\"submit\" value=\"Rename\"/></form></td></tr>")
	
	-- Output the group editor:
	ins(res, "<tr><th>Export group</th><td><form method=\"POST\"><input type=\"hidden\" name=\"areaid\" value=\"")
	ins(res, Area.ID)
	ins(res, "\"/><input type=\"hidden\" name=\"action\" value=\"regrouparea\"/><input type=\"text\" name=\"groupname\" size=100 value=\"")
	ins(res, cWebAdmin:GetHTMLEscapedString(Area.ExportGroupName))
	ins(res, "\"/><input type=\"submit\" value=\"Set\"/></form></td></tr>")

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
	AddProp("Approved", Area.DateApproved .. " by " .. Area.ApprovedBy)
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
		ins(res, "</td><td><form method=\"POST\"><input type=\"hidden\" name=\"areaid\" value=\"")
		ins(res, Area.ID)
		ins(res, "\"/><input type=\"hidden\" name=\"action\" value=\"updatemeta\"/><input type=\"hidden\" name=\"metaname\" value=\"")
		ins(res, cWebAdmin:GetHTMLEscapedString(md))
		ins(res, "\"><input type=\"text\" size=100 name=\"metavalue\" value=\"")
		ins(res, cWebAdmin:GetHTMLEscapedString(Metadata[md]))
		ins(res, "\"><input type=\"submit\" value=\"Update\"/></form>")
		ins(res, "<form method=\"POST\"><input type=\"hidden\" name=\"areaid\" value=\"")
		ins(res, Area.ID)
		ins(res, "\"/><input type=\"hidden\" name=\"action\" value=\"delmeta\"/><input type=\"hidden\" name=\"metaname\" value=\"")
		ins(res, cWebAdmin:GetHTMLEscapedString(md))
		ins(res, "\"><input type=\"submit\" value=\"Del\"/></form></td></tr>")
	end
	ins(res, "<tr><td><form method=\"POST\"><input type=\"hidden\" name=\"areaid\" value=\"")
	ins(res, Area.ID)
	ins(res, "\"/><input type=\"hidden\" name=\"action\" value=\"addmeta\"/><input type=\"text\" name=\"metaname\" size=50/></td>")
	ins(res, "<td><input type=\"text\" size=100 name=\"metavalue\" value=\"\"/><input type=\"submit\" value=\"Add\"/></form></td></tr>")
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
		ins(res, "</td></tr>")
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
	return "<p>Area renamed successfully.</p><p>Return to <a href=\"?action=areadetails&areaid=" .. AreaID .. "\">area details</a>.</p>"
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





local g_ActionHandlers =
{
	[""]            = ShowMainPage,
	["addmeta"]     = ExecuteUpdateMeta,  -- "Add" has the same handling as "Update" - translates to "DB set"
	["areadetails"] = ShowAreaDetails,
	["delmeta"]     = ExecuteDelMeta,
	["getpreview"]  = ExecuteGetPreview,
	["regrouparea"] = ExecuteRegroupArea,
	["renamearea"]  = ExecuteRenameArea,
	["updatemeta"]  = ExecuteUpdateMeta,
}





--- Returns the entire tab's HTML contents, based on the player's request
local function HandleRequest(a_Request)
	local Action = (a_Request.PostParams["action"] or "")
	local Handler = g_ActionHandlers[Action]
	if (Handler == nil) then
		return HTMLError("An internal error has occurred, no handler for action " .. Action .. ".")
	end
	
	local PageContent = Handler(a_Request)
	
	return PageContent
end





--- Registers the web page in the webadmin
function InitWeb()
	-- If web preview is not configured, don't register the webadmin tab:
	if not(g_Config.WebPreview) then
		LOG("GalExport: WebPreview is not enabled in the settings.")
		return
	end

	-- Register the webadmin tab:
	cPluginManager:Get():GetCurrentPlugin():AddWebTab("Areas", HandleRequest)

	-- Read the "preview not available yet" image:
	g_PreviewNotAvailableYetPng = cFile:ReadWholeFile(cPluginManager:GetCurrentPlugin():GetLocalFolder() .. "/PreviewNotAvailableYet.png")
end




