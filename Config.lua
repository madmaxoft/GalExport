
-- Config.lua

-- Implements loading and verifying the configuration from the file





--- The configuration
g_Config = {};





--- Checks if a_Config has all the keys it needs, adds defaults for the missing ones
-- Returns the modified a_Config (but also modifies a_Config in-place)
local function VerifyConfig(a_Config)
	a_Config.CommandPrefix  = a_Config.CommandPrefix or "/ge"
	a_Config.DatabaseEngine = a_Config.DatabaseEngine or "sqlite"
	a_Config.DatabaseParams = a_Config.DatabaseParams or {}
	a_Config.ExportFolder   = a_Config.ExportFolder or "GalExports"

	-- Check the WebPreview, if it doesn't have all the requirements, set it to nil to disable previewing:
	if (a_Config.WebPreview) then
		if not(a_Config.WebPreview.ThumbnailFolder) then
			LOGINFO(PLUGIN_PREFIX .. "The config doesn't define WebPreview.ThumbnailFolder. Web preview is disabled.")
			a_Config.WebPreview = nil
		end
		if (a_Config.WebPreview and not(a_Config.WebPreview.MCSchematicToPng)) then
			LOGINFO(PLUGIN_PREFIX .. "The config doesn't define WebPreview.MCSchematicToPng. Web preview is disabled.")
			a_Config.WebPreview = nil
		end
		if (a_Config.WebPreview and not(cFile:Exists(a_Config.WebPreview.MCSchematicToPng))) then
			LOGINFO(PLUGIN_PREFIX .. "The WebPreview.MCSchematicToPng in the config is not valid. Web preview is disabled.")
			a_Config.WebPreview = nil
		end
	end
	
	-- Apply the CommandPrefix - change the actual g_PluginInfo table:
	if (a_Config.CommandPrefix ~= "/ge") then
		g_PluginInfo.Commands[a_Config.CommandPrefix] = g_PluginInfo.Commands["/ge"]
		g_PluginInfo.Commands["/ge"] = nil
	end
	
	return a_Config
end





--- Loads the galleries from the config file CONFIG_FILE
function LoadConfig()
	if not(cFile:Exists(CONFIG_FILE)) then
		-- No file to read from, bail out with a log message
		-- But first copy our example file to the folder, to let the admin know the format:
		local PluginFolder = cPluginManager:Get():GetCurrentPlugin():GetLocalFolder()
		local ExampleFile = CONFIG_FILE:gsub(".cfg", ".example.cfg")
		if (cFile:Copy(PluginFolder .. "/example.cfg", ExampleFile)) then
			LOGWARNING(PLUGIN_PREFIX .. "The config file '" .. CONFIG_FILE .. "' doesn't exist. An example configuration file '" .. ExampleFile .. "' has been created for you.")
		else
			LOGWARNING(PLUGIN_PREFIX .. "The config file '" .. CONFIG_FILE .. "' doesn't exist.")
		end
		g_Config = VerifyConfig({})
		return
	end
	
	-- Load and compile the config file:
	local cfg, err = loadfile(CONFIG_FILE)
	if (cfg == nil) then
		LOGWARNING(PLUGIN_PREFIX .. "Cannot open '" .. CONFIG_FILE .. "': " .. err)
		g_Config = VerifyConfig({})
		return
	end
	
	-- Execute the loaded file in a sandbox:
	-- This is Lua-5.1-specific and won't work in Lua 5.2!
	local Sandbox = {}
	setfenv(cfg, Sandbox)
	cfg()
	
	-- Retrieve the values we want from the sandbox:
	Config = Sandbox.Config
	if not(g_Config) then
		LOGWARNING(PLUGIN_PREFIX .. "Config not found in the config file '" .. CONFIG_FILE .. "'. Using defaults.")
		Config = {}  -- Defaults will be inserted by VerifyConfig()
	end
	g_Config = VerifyConfig(Config)
end




