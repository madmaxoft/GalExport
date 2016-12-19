
-- GalExport.lua

-- Implements the Gallery Exporter plugin main entrypoint




--- The prefix used for console logging
PLUGIN_PREFIX = "GalExport: "

--- The name of the config file, stored next to the MCS executable
CONFIG_FILE = "GalExport.cfg"





--- Map of cPlayer UniqueID -> status bar message displayed to that player
local g_PlayerStatusMsgs = {}





local function FormatAreaName(a_Area)
	if (a_Area.ExportName and (a_Area.ExportName ~= "")) then
		return a_Area.ExportName
	elseif (a_Area.Name and (a_Area.Name ~= "")) then
		return a_Area.Name
	else
		return string.format("%s %d", a_Area.GalleryName, a_Area.GalleryIndex)
	end
end





local function OnPlayerMoving(a_Player, a_OldPosition, a_NewPosition)
	local area = g_DB:GetAreaByCoords(a_Player:GetWorld():GetName(), a_NewPosition.x, a_NewPosition.z)
	local msg
	if not(area) then
		msg = ""
	else
		if (area.IsApproved) then
			msg = string.format("%s by %s, approved, group %s",
				FormatAreaName(area),
				area.PlayerName,
				area.ExportGroupName
			)
		else
			msg = string.format("%s by %s",
				FormatAreaName(area),
				area.PlayerName
			)
		end
	end

	-- If the message has changed, send it to the player:
	-- (Thus avoiding overwriting other plugins' messages in unrelated worlds)
	if (g_PlayerStatusMsgs[a_Player:GetUniqueID()] ~= msg) then
		g_PlayerStatusMsgs[a_Player:GetUniqueID()] = msg
		a_Player:SendAboveActionBarMessage(msg)
	end
end





--- A tick counter, separate for each world.
-- Map of WorldName -> number of ticks registered in OnWorldTick
-- Used to update the player above-bar message only once per second
local g_TickCounter = {}

local function OnWorldTick(a_World)
	-- Only process the rest of this function once per second:
	local name = a_World:GetName()
	g_TickCounter[name] = (g_TickCounter[name] or 0) + 1
	if (g_TickCounter[name] < 20) then
		return
	end
	g_TickCounter[name] = 0

	-- Update the message, if not empty:
	a_World:ForEachPlayer(
		function (a_CBPlayer)
			local msg = g_PlayerStatusMsgs[a_CBPlayer:GetUniqueID()]
			if (msg and (msg ~= "")) then
				a_CBPlayer:SendAboveActionBarMessage(msg)
			end
		end
	)
end





function Initialize(a_Plugin)
	-- Load the InfoReg library file for registering the Info.lua command table:
	dofile(cPluginManager:GetPluginsPath() .. "/InfoReg.lua")

	-- Load the config
	LoadConfig()

	-- Initialize the DB storage:
	InitStorage()

	-- Initialize commands:
	RegisterPluginInfoCommands()
	RegisterPluginInfoConsoleCommands()

	-- Initialize the webadmin page:
	InitWeb()

	cPluginManager:AddHook(cPluginManager.HOOK_PLAYER_MOVING, OnPlayerMoving)
	cPluginManager:AddHook(cPluginManager.HOOK_WORLD_TICK,    OnWorldTick)

	return true
end




