
-- GalExport.lua

-- Implements the Gallery Exporter plugin main entrypoint




--- The prefix used for console logging
PLUGIN_PREFIX = "GalExport: "

--- The name of the config file, stored next to the MCS executable
CONFIG_FILE = "GalExport.cfg"





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
	
	return true
end




