
-- Web.lua

-- Implements the webadmin interface





local ins = table.insert
local g_NumAreasPerPage = 50

-- Contains the PNG file for "Preview not available yet" image
local g_PreviewNotAvailableYetPng

-- The object that handles area previews
local g_AreaPreview

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

-- URL name of the CheckMetadata page:
local PAGE_NAME_CHECKMETA = "Metadata"

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





--- Dictionary of exports that have started and not yet completed
-- Maps "<exporterCode>|<groupName>" -> "<startTime>" for such exports.
local g_PendingExports = {}





--- Shortcut name for HTML escaping text
local function Escape(a_Text)
	return cWebAdmin:GetHTMLEscapedString(a_Text)
end





local function UrlEscape(a_Text)
	return cUrlParser:UrlEncode(a_Text)
end





--- Returns the HTML-formatted error message with the specified reason
local function HTMLError(a_Reason)
	return "<b style='color: #a00'>" .. Escape(a_Reason) .. "</b>"
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
	local dir = NormalizeDirection(a_Connector.Direction)

	if (dir == "x-") then
		return (a_Connector.X <= (a_AreaDef.HitboxMinX or a_AreaDef.ExportMinX))
	elseif (dir == "x+") then
		return (a_Connector.X >= (a_AreaDef.HitboxMaxX or a_AreaDef.ExportMaxX))
	elseif (string.sub(dir, 1, 2) == "y-") then
		return (a_Connector.Y <= (a_AreaDef.HitboxMinY or a_AreaDef.ExportMinY))
	elseif (string.sub(dir, 1, 2) == "y+") then
		return (a_Connector.Y >= (a_AreaDef.HitboxMaxY or a_AreaDef.ExportMaxY))
	elseif (dir == "z-") then
		return (a_Connector.Z <= (a_AreaDef.HitboxMinZ or a_AreaDef.ExportMinZ))
	elseif (dir == "z+") then
		return (a_Connector.Z >= (a_AreaDef.HitboxMaxZ or a_AreaDef.ExportMaxZ))
	end

	-- Not a known direction, mark as failure:
	return false
end





--- Array of all known connector directions
local g_AllDirections =
{
	"x-",
	"x+",
	"y-",
	"y+",
	"z-",
	"z+",
	"y-x-z-",
	"y-x-z+",
	"y-x+z-",
	"y-x+z+",
	"y+x-z-",
	"y+x-z+",
	"y+x+z-",
	"y+x+z+",
}

--- Generated the HTML code for a drop-down control containing all directions
-- a_FieldName is the field name for the generated control
-- a_SelectedDirection is the direction that should be pre-selected in the drop-down control
local function GenerateDirectionDropDown(a_FieldName, a_SelectedDirection)
	local res = { "<select name='", a_FieldName, "'>"}
	for _, dir in ipairs(g_AllDirections) do
		if (a_SelectedDirection == dir) then
			ins(res, "<option selected>")
		else
			ins(res, "<option>")
		end
		ins(res, dir)
		ins(res, "</option>")
	end
	ins(res, "</select>")
	return table.concat(res)
end





--- Checks the previews for the specified areas and regenerates the ones that are outdated
-- a_Areas is an array of areas as loaded from the DB
-- a_ShouldNameConnectors specifies whether the connectors should be described with letters (true) or their directions (false)
local function RefreshPreviewForAreas(a_Areas, a_ShouldNameConnectors)
	-- Check params and preconditions:
	assert(type(a_Areas) == "table")
	assert(type(a_ShouldNameConnectors) == "boolean")
	assert(g_Config.WebPreview)

	-- Check each area and each rotation:
	local toExport = {}  -- array of {Area = <db-area>, NumRotations = <number>}
	local idx = 1
	for _, area in ipairs(a_Areas) do
		toExport[idx] = area
		idx = idx + 1
	end

	-- Sort the ToExport array by coords (to help reuse the chunks):
	table.sort(toExport,
		function (a_Item1, a_Item2)
			-- Compare the X coord first:
			if (a_Item1.MinX < a_Item2.MinX) then
				return true
			end
			if (a_Item1.MinX > a_Item2.MinX) then
				return false
			end
			-- The X coord is the same, compare the Z coord:
			return (a_Item1.MinZ < a_Item2.MinZ)
		end
	)

	-- Export each area:
	local connVisStyle
	if (a_ShouldNameConnectors) then
		connVisStyle = "Letters"
	else
		connVisStyle = "Arrows"
	end
	for _, area in ipairs(toExport) do
		for rot = 0, 3 do
			g_AreaPreview:RefreshPreview(area, rot, connVisStyle)
		end
	end
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
		return Escape(Position)
	elseif (Position == a_Area.ExportName) then
		return Escape(a_Area.ExportName)
	else
		return Escape(a_Area.ExportName) .. "<br/>(" .. Escape(Position .. ")")
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
-- If a_ExtraColumn is non-nil, it is a header of an extra inserted column (corresponding to GetAreaHTMLRow's a_ExtraText)
local function GetAreasHTMLHeader(a_ExtraColumn)
	-- Check params:
	assert((a_ExtraColumn == nil) or (type(a_ExtraColumn) == "string"))

	-- Add the preview line(s):
	local res
	if (g_Config.TwoLineAreaList) then
		res = "<tr><th colspan=6>Preview</th></tr><tr>"
	else
		res = "<tr><th colspan=4>Preview</th>"
	end
	res = res .. "<th>Area</th><th>Group</th><th>Connectors</th><th>Author</th><th>Approved</th>"

	-- Add the extra column, if requested:
	if (a_ExtraColumn) then
		res = res .. "<th>" .. a_ExtraColumn .. "</th>"
	end

	-- Add the rest of the table:
	return res .. "<th width='1%'>Action</th></tr>"
end





--- Returns the HTML code for the area's row in the area list
-- a_ExtraActions is an area of extra actions to insert as action buttons
-- a_ExtraText is a text that is output in a separate column; the column is skipped if nil
local function GetAreaHTMLRow(a_Area, a_ExtraActions, a_ExtraText)
	-- Check params:
	assert(type(a_Area) == "table")
	assert(a_Area.ID)
	assert((a_ExtraActions == nil) or (type(a_ExtraActions) == "table"))
	assert((a_ExtraText == nil) or (type(a_ExtraText) == "string"))
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
	ins(res, Escape(a_Area.ExportGroupName or ""))
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
	ins(res, Escape(a_Area.PlayerName) or "&nbsp;")
	ins(res, "</td><td valign='top'>")
	ins(res, (a_Area.DateApproved or "&nbsp;"):gsub("T", " ") .. "<br/>by " .. (a_Area.ApprovedBy or "&lt;unknown&gt;"))
	ins(res, "</td><td valign='top'>")
	if (a_ExtraText) then
		ins(res, a_ExtraText)
		ins(res, "</td><td valign='top'>")
	end
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
			<option value="ExpandFloorStrategy">
			<option value="IsStarting">
			<option value="MergeStrategy">
			<option value="MoveToGround">
			<option value="VerticalLimit">
			<option value="VerticalStrategy">
		</datalist>
	]]
end





--- Returns the HTML code that provides the <datalist> element for group metas
local function GetGroupMetaNamesHTMLDatalist()
	return [[
		<datalist id="groupmetanames">
			<option value="GridSizeX"/>
			<option value="GridSizeZ"/>
			<option value="IntendedUse"/>
			<option value="MaxDensity"/>
			<option value="MaxDepth"/>
			<option value="MaxOffsetX"/>
			<option value="MaxOffsetZ"/>
			<option value="MaxStructureSizeX"/>
			<option value="MaxStructureSizeZ"/>
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
	for _, area in pairs(Areas) do
		table.insert(AreaArray, area)
	end
	RefreshPreviewForAreas(AreaArray, false)

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
	local shouldnameconns = (a_Request.Params["shouldnameconns"] == "true")
	local connVisStyle
	if (shouldnameconns) then
		connVisStyle = "Letters"
	else
		connVisStyle = "Arrows"
	end

	local pngData = g_AreaPreview:GetPreview(areaID, rot, connVisStyle)
	if not(pngData) then
		return g_PreviewNotAvailableYetPng, "image/png"
	end
	return pngData, "image/png"
end





--- Returns the contents of the requested preview PNG
-- Returns g_PreviewNotAvailableYetPng if the specified preview is not yet available
-- Returns an error if the request is for an invalid preview
local function ExecuteGetStatic(a_Request)
	-- Get the params:
	local name = a_Request.Params["name"]
	if not(name) then
		return "Invalid identification"
	end
	if not(string.match(name, "%.png")) then
		return "Invalid request"
	end

	return cFile:ReadWholeFile(cPluginManager:GetCurrentPlugin():GetLocalFolder() .. "/" .. name), "image/png"
end





local function ShowAreaConnectors(a_Request)
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
	RefreshPreviewForAreas({Area}, true)
	local res = {}

	-- Output the breadcrumbs:
	ins(res, "<p><a href='Groups'>Groups</a> &gt;&gt; <a href='Groups?action=groupdetails&groupname=")
	ins(res, UrlEscape(Area.ExportGroupName))
	ins(res, "'>Group ")
	ins(res, Escape(Area.ExportGroupName))
	ins(res, "</a> &gt;&gt; <a href='Areas?action=areadetails&areaid=")
	ins(res, AreaID)
	ins(res, "'>Area ")
	ins(res, Area.ExportName or Area.Name or (Area.GalleryName .. " " .. Area.GalleryIndex))
	ins(res, "</a></p>")

	-- Output the display:
	ins(res, "<h2>Connectors</h2>")
	ins(res, "<table><tr>")
	for rot = 0, 3 do
		ins(res, "<td valign='top'><img src=\"/~")
		ins(res, a_Request.Path)
		ins(res, "?action=getpreview&areaid=")
		ins(res, Area.ID)
		ins(res, "&rot=")
		ins(res, rot)
		ins(res, "&shouldnameconns=true\"/><br/><img src='/~")
		ins(res,a_Request.Path)
		ins(res, "?action=getstatic&name=rot")
		ins(res, rot)
		ins(res, ".png'/></td>")
	end
	ins(res, "</tr></table>")

	-- Output the connectors:
	ins(res, "<form action='Areas' method='POST'><input type='hidden' name='action' value='setallconns'/>")
	ins(res, "<input type='hidden' name='areaid' value='")
	ins(res, Area.ID)
	ins(res, "'/><table><tr><th>Sign</th><th>Index</th><th>ID</th><th>X</th><th>Y</th><th>Z</th><th>Type</th><th>Direction</th></tr>")
	local Connectors = g_DB:GetAreaConnectors(Area.ID)
	for idx, conn in ipairs(Connectors) do
		ins(res, "<tr><td><span style='color: #")
		ins(res, g_AreaPreview:GetConnColorStringByType(conn.TypeNum))
		ins(res, "'>")
		ins(res, string.char(64 + idx))
		ins(res, "</span></td><td>")
		ins(res, idx)
		ins(res, "</td><td>")
		ins(res, conn.ID)
		ins(res, "</td><td><input type='edit' size=3 name='connx")
		ins(res, conn.ID)
		ins(res, "' value='")
		ins(res, conn.X - Area.ExportMinX)
		ins(res, "'/></td><td><input type='edit' size=3 name='conny")
		ins(res, conn.ID)
		ins(res, "' value='")
		ins(res, conn.Y - Area.ExportMinY)
		ins(res, "'/></td><td><input type='edit' size=3 name='connz")
		ins(res, conn.ID)
		ins(res, "' value='")
		ins(res, conn.Z - Area.ExportMinZ)
		ins(res, "'/></td><td><input type='edit' size=4 name='connt")
		ins(res, conn.ID)
		ins(res, "' value='")
		ins(res, conn.TypeNum)
		ins(res, "'/></td><td>\n")
		ins(res, GenerateDirectionDropDown("connd" .. conn.ID, NormalizeDirection(conn.Direction)))
		ins(res, "</td><td>\n")
		if not(IsConnectorReachableThroughHitbox(conn, Area)) then
			ins(res, "<b>Not reachable through hitbox!</b>")
		else
			ins(res, "&nbsp;")
		end
		ins(res, "</td></tr>")
	end
	ins(res, "</table><p><input type='submit' value='Apply all changes'/></p></form>")

	-- Output the coord ranges:
	ins(res, "<hr/><br/><h2>Coord ranges</h2><table><tr><th>X&nbsp;range</th><td>")
	ins(res, (Area.HitboxMinX or Area.ExportMinX) - Area.ExportMinX)
	ins(res, "&nbsp;..&nbsp;")
	ins(res, (Area.HitboxMaxX or Area.ExportMaxX) - Area.ExportMinX)
	ins(res, "</td><td width='100%'/></tr><tr><th>Y range</th><td>")
	ins(res, (Area.HitboxMinY or Area.ExportMinY) - Area.ExportMinY)
	ins(res, "&nbsp;..&nbsp;")
	ins(res, (Area.HitboxMaxY or Area.ExportMaxY) - Area.ExportMinY)
	ins(res, "</td><td width='100%'/></tr><tr><th>Z range</th><td>")
	ins(res, (Area.HitboxMinZ or Area.ExportMinZ) - Area.ExportMinZ)
	ins(res, "&nbsp;..&nbsp;")
	ins(res, (Area.HitboxMaxZ or Area.ExportMaxZ) - Area.ExportMinZ)
	ins(res, "</td><td width='100%'/></tr></table>")

	return table.concat(res)
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
	RefreshPreviewForAreas({Area}, false)
	RefreshPreviewForAreas({Area}, true)  -- Refresh connector-view as well, in advance
	local res = {}

	-- Output the breadcrumbs:
	ins(res, "<p><a href='Groups'>Groups</a> &gt;&gt; <a href='Groups?action=groupdetails&groupname=")
	ins(res, UrlEscape(Area.ExportGroupName))
	ins(res, "'>Group ")
	ins(res, Escape(Area.ExportGroupName))
	ins(res, "</a></p>")

	-- Output the preview:
	ins(res, "<table><tr>")
	for rot = 0, 3 do
		ins(res, "<td valign='top'><img src=\"/~")
		ins(res, a_Request.Path)
		ins(res, "?action=getpreview&areaid=")
		ins(res, Area.ID)
		ins(res, "&rot=")
		ins(res, rot)
		ins(res, "\"/></td>")
	end
	ins(res, "</tr>")

	-- Output the Refresh preview button:
	ins(res, "<tr><td><form method=\"POST\">")
	ins(res, GetHTMLInput("hidden", "areaid",         {value = Area.ID}))
	ins(res, GetHTMLInput("hidden", "action",         {value = "refreshareapreview"}))
	ins(res, GetHTMLInput("submit", "refreshpreview", {value = "Refresh preview"}))
	ins(res, "</form></td></tr></table>")

	-- Output the name editor:
	ins(res, "<table><tr><th>Export name: </th><td><form method=\"POST\">")
	ins(res, GetHTMLInput("hidden", "areaid",   {value = Area.ID}))
	ins(res, GetHTMLInput("hidden", "action",   {value = "renamearea"}))
	ins(res, GetHTMLInput("text",   "areaname", {size = 100, value = Escape(Area.ExportName or "")}))
	ins(res, GetHTMLInput("submit", "rename",   {value = "Rename"}))
	ins(res, "</form></td></tr>")

	-- Output the group editor:
	ins(res, "<tr><th>Export group</th><td><form method=\"POST\">")
	ins(res, GetHTMLInput("hidden", "areaid",    {value = Area.ID}))
	ins(res, GetHTMLInput("hidden", "action",    {value = "regrouparea"}))
	ins(res, GetHTMLInput("text",   "groupname", {size = 100, value = Escape(Area.ExportGroupName)}))
	ins(res, GetHTMLInput("submit", "regroup",   {value = "Set"}))
	ins(res, "</form></td></tr>")

	-- Define a helper function for adding a property to the view
	local function AddProp(a_Title, a_Value)
		ins(res, "<tr><th>")
		ins(res, Escape(a_Title))
		ins(res, "</th><td>")
		ins(res, Escape(a_Value))
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
		ins(res, Escape(md))
		ins(res, "</td><td><form method=\"POST\" style='display: inline'>")
		ins(res, GetHTMLInput("hidden", "areaid",    {value = Area.ID}))
		ins(res, GetHTMLInput("hidden", "action",    {value = "updatemeta"}))
		ins(res, GetHTMLInput("hidden", "metaname",  {value = Escape(md)}))
		ins(res, GetHTMLInput("text",   "metavalue", {size = 100, value = Escape(Metadata[md])}))
		ins(res, GetHTMLInput("submit", "update",    {value = "Update"}))
		ins(res, "</form>")

		ins(res, "<form method=\"POST\" style='display: inline'>")
		ins(res, GetHTMLInput("hidden", "areaid",    {value = Area.ID}))
		ins(res, GetHTMLInput("hidden", "action",    {value = "delmeta"}))
		ins(res, GetHTMLInput("hidden", "metaname",  {value = Escape(md)}))
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
	ins(res, "<br/><h3>Connectors:</h3><a href='Areas?action=areaconns&areaid=")
	ins(res, Area.ID)
	ins(res, "'>Editor</a><br/><table><tr><th>Index</th><th>X</th><th>Y</th><th>Z</th><th>Type</th><th>Direction</th></tr>")
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
		ins(res, "</td><td><span style='color: #")
		ins(res, g_AreaPreview:GetConnColorStringByType(conn.TypeNum))
		ins(res, "'>")
		ins(res, conn.TypeNum)
		ins(res, "</span></td><td>")
		ins(res, DirectionToString(conn.Direction) or "unknown")
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
	return "<p>Area moved to group " .. Escape(NewGroup) .. " successfully.</p><p>Return to <a href=\"?action=areadetails&areaid=" .. AreaID .. "\">area details</a>.</p>"
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





local function ExecuteRefreshAreaPreview(a_Request)
	-- Check params:
	local areaID = tonumber(a_Request.PostParams["areaid"])
	if not(areaID) then
		return HTMLError("Invalid Area ID")
	end

	-- Regenerate all the previews for the area:
	for rot = 0, 3 do
		g_AreaPreview:RegeneratePreview(areaID, rot, "Arrows")
		g_AreaPreview:RegeneratePreview(areaID, rot, "Letters")
	end

	-- Display a success page with a return link:
	return "<p>Area previews scheduled for a refresh.</p><p>Return to <a href=\"?action=areadetails&areaid=" .. areaID .. "\">area details</a>.</p>"
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
		local GroupName = Escape(grp)
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
	ins(res, GetHTMLInput("text",   "name",   {value = Escape(GroupName)}))
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
	local GroupNameHTML = Escape(GroupName)
	for _, mn in ipairs(MetaNames) do
		ins(res, "<tr><td>")
		ins(res, Escape(mn))
		ins(res, "</td><td><form method=\"POST\">")
		ins(res, GetHTMLInput("hidden", "groupname", {value = GroupNameHTML}))
		ins(res, GetHTMLInput("hidden", "action",    {value = "setmeta"}))
		ins(res, GetHTMLInput("hidden", "metaname",  {value = Escape(mn)}))
		ins(res, GetHTMLInput("text",   "metavalue", {size = 100, value = Escape(Metas[mn])}))
		ins(res, GetHTMLInput("submit", "update",    {value = "Update"}))
		ins(res, "</form></td>")
		ins(res, "<td><form method=\"POST\">")
		ins(res, GetHTMLInput("hidden", "groupname", {value = GroupNameHTML}))
		ins(res, GetHTMLInput("hidden", "metaname",  {value = Escape(mn)}))
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
	RefreshPreviewForAreas(Areas, false)

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
	return "<p>Meta value deleted successfully.</p><p>Return to <a href=\"?action=groupdetails&groupname=" .. Escape(GroupName) .. "\">group details</a>.</p>"
end





local function ExecuteSetAllConns(a_Request)
	-- Check params:
	local areaID = tonumber(a_Request.PostParams["areaid"])
	if not(areaID) then
		return HTMLError("Invalid area identification")
	end
	local area = g_DB:GetAreaByID(areaID)
	if not(area) then
		return HTMLError("Invalid area ID")
	end
	local conns = g_DB:GetAreaConnectors(areaID)
	if not(conns) then
		return HTMLError("Invalid area connectors")
	end

	-- Apply changes to each fully specified connector of the area:
	local err = {}
	for _, conn in ipairs(conns) do
		local x = tonumber(a_Request.PostParams["connx" .. conn.ID])
		local y = tonumber(a_Request.PostParams["conny" .. conn.ID])
		local z = tonumber(a_Request.PostParams["connz" .. conn.ID])
		local t = tonumber(a_Request.PostParams["connt" .. conn.ID])
		local d = NormalizeDirection(a_Request.PostParams["connd" .. conn.ID])
		if (x and y and z and t and d) then
			local isSuccess, msg = g_DB:ChangeConnector(conn.ID, area.ExportMinX + x, area.ExportMinY + y, area.ExportMinZ + z, t, d)
			if not(isSuccess) then
				ins(err, string.format("Error while setting connector ID %d: %s", conn.ID, msg or "[unknown error]"))
			end
		end
	end

	-- Regenerate all the previews for the area:
	for rot = 0, 3 do
		g_AreaPreview:RegeneratePreview(areaID, rot, "Arrows")
		g_AreaPreview:RegeneratePreview(areaID, rot, "Letters")
	end

	-- Respond with a "Changes applied" page:
	local groupName = area.ExportGroupName
	local areaName = area.ExportName or area.Name or (area.GalleryName .. " " .. area.GalleryIdx)
	local errorMessages = ""
	if (err[1]) then
		errorMessages = "<p><b>The following errors occurred:<ul><li>" .. table.concat(err, "</li><li>") .. "</li></ul></b></p>"
	end
	return [[
		<p>Changes have been applied.</p>]] .. errorMessages .. [[
		<p>Return to:
		<ul>
			<li><a href="Groups">Groups list</a></li>
			<li><a href="Groups?action=groupdetails&groupname=]] .. groupName .. [[">Group ]] .. groupName .. [[</a></li>
			<li><a href="Areas?action=areadetails&areaid=]] .. areaID .. [[">Area ]] .. areaName .. [[</a></li>
			<li><a href="Areas?action=areaconns&areaid=]] .. areaID .. [[">Connector editor</a></li>
		</ul></p>
	]]
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
	return "<p>Meta value has been set successfully.</p><p>Return to <a href=\"?action=groupdetails&groupname=" .. Escape(GroupName) .. "\">group details</a>.</p>"
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
		return HTMLError("Cannot delete connector from the DB: " .. Escape(Msg or "<unknown DB error>"))
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
		return HTMLError("Cannot lock approved areas: " .. Escape(Msg or "<unknown DB error>"))
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
		return HTMLError("Cannot unlock all areas: " .. Escape(Msg or "<unknown DB error>"))
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
	RefreshPreviewForAreas(Issues, false)

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
				local HtmlName = Escape(grpName)
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
	ins(res, Escape(a_FileName))
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
	local GroupNameHtml = Escape(GroupName)
	for _, fnam in ipairs(Files) do
		ins(res, "<tr><td>")
		ins(res, Escape(fnam))
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





--- Returns the HTML contents of the entire CheckMeta page
local function ShowCheckMetaPage(a_Request)
	-- Check the areas' meta:
	local res = {}
	local issuesFound, msg = checkAllAreasMetadata()
	if not(issuesFound) then
		ins(res, HTMLError("Failed to check area metadata: " .. (msg or "[unknown error]")))
	else
		if not(issuesFound[1]) then
			ins(res, "<p>No issues with areas' metadata were found.</p>")
		else
			ins(res, "<p>The following metadata-related issues were found:</p><table>")
			ins(res, GetAreasHTMLHeader("Issue"))
			for _, issue in ipairs(issuesFound) do
				ins(res, GetAreaHTMLRow(issue.Area, nil, "<b>" .. issue.Issue .. "</b>"))
			end
			ins(res, "</table>")
		end
	end

	-- Check the groups' meta:
	issuesFound, msg = checkAllGroupsMetadata()
	if not(issuesFound) then
		ins(res, HTMLError("Failed to check group metadata: " .. (msg or "[unknown error]")))
	else
		if not(issuesFound[1]) then
			ins(res, "<p>No issues with groups' metadata were found.</p>")
		else
			ins(res, "<p>The following group metadata-related issues were found:</p><table>")
			ins(res, "<tr><th>Group</th><th>Issue</th></tr>")
			for _, issue in ipairs(issuesFound) do
				ins(res, "<tr><td><a href='")
				ins(res, PAGE_NAME_GROUPS)
				ins(res, "?action=groupdetails&groupname=")
				ins(res, issue.GroupName)
				ins(res, "'>")
				ins(res, issue.GroupName)
				ins(res, "</a></td><td>")
				ins(res, Escape(issue.Issue))
				ins(res, "</td></tr>")
			end
			ins(res, "</table>")
		end
	end

	return table.concat(res)
end





-- Action handlers for the Areas page:
local g_AreasActionHandlers =
{
	[""]                   = ShowAreasPage,
	["addmeta"]            = ExecuteUpdateMeta,  -- "Add" has the same handling as "Update" - translates to "DB set"
	["areaconns"]          = ShowAreaConnectors,
	["areadetails"]        = ShowAreaDetails,
	["delmeta"]            = ExecuteDelMeta,
	["getpreview"]         = ExecuteGetPreview,
	["getstatic"]          = ExecuteGetStatic,
	["regrouparea"]        = ExecuteRegroupArea,
	["renamearea"]         = ExecuteRenameArea,
	["refreshareapreview"] = ExecuteRefreshAreaPreview,
	["setallconns"]        = ExecuteSetAllConns,
	["updatemeta"]         = ExecuteUpdateMeta,
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





local g_CheckMetaActionHandlers =
{
	[""] = ShowCheckMetaPage,
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

		return Handler(a_Request)
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
	Plugin:AddWebTab(PAGE_NAME_CHECKMETA,       CreateRequestHandler(g_CheckMetaActionHandlers))
	Plugin:AddWebTab(PAGE_NAME_EXPORTS,         CreateRequestHandler(g_ExportsActionHandlers))

	-- Read the "preview not available yet" image:
	g_PreviewNotAvailableYetPng = cFile:ReadWholeFile(cPluginManager:GetCurrentPlugin():GetLocalFolder() .. "/PreviewNotAvailableYet.png")

	-- Initialize the preview storage and creation object:
	g_AreaPreview = InitAreaPreview(g_Config.WebPreview.MCSchematicToPng)
end




