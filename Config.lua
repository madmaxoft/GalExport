
-- Config.lua

-- Implements loading and verifying the configuration from the file





--- The configuration
g_Config = {};





--- Checks if g_Config has all the keys it needs, adds defaults for the missing ones
function VerifyConfig()
	g_Config.CommandPrefix = g_Config.CommandPrefix or "/ge";
	g_Config.DatabaseEngine = g_Config.DatabaseEngine or "sqlite";
	g_Config.DatabaseParams = g_Config.DatabaseParams or {};

	-- Apply the CommandPrefix - change the actual g_PluginInfo table:
	if (g_Config.CommandPrefix ~= "/ge") then
		g_PluginInfo.Commands[g_Config.CommandPrefix] = g_PluginInfo.Commands["/ge"];
		g_PluginInfo.Commands["/ge"] = nil;
	end
end





--- Loads the galleries from the config file CONFIG_FILE
function LoadConfig()
	if not(cFile:Exists(CONFIG_FILE)) then
		-- No file to read from, bail out with a log message
		-- But first copy our example file to the folder, to let the admin know the format:
		local PluginFolder = cPluginManager:Get():GetCurrentPlugin():GetLocalFolder()
		local ExampleFile = CONFIG_FILE:gsub(".cfg", ".example.cfg");
		if (cFile:Copy(PluginFolder .. "/example.cfg", ExampleFile)) then
			LOGWARNING(PLUGIN_PREFIX .. "The config file '" .. CONFIG_FILE .. "' doesn't exist. An example configuration file '" .. ExampleFile .. "' has been created for you.");
		else
			LOGWARNING(PLUGIN_PREFIX .. "The config file '" .. CONFIG_FILE .. "' doesn't exist.");
		end
		return;
	end
	
	-- Load and compile the config file:
	local cfg, err = loadfile(CONFIG_FILE);
	if (cfg == nil) then
		LOGWARNING(PLUGIN_PREFIX .. "Cannot open '" .. CONFIG_FILE .. "': " .. err);
		return;
	end
	
	-- Execute the loaded file in a sandbox:
	-- This is Lua-5.1-specific and won't work in Lua 5.2!
	local Sandbox = {};
	setfenv(cfg, Sandbox);
	cfg();
	
	-- Retrieve the values we want from the sandbox:
	g_Config = Sandbox.Config;
	if (g_Config == nil) then
		LOGWARNING(PLUGIN_PREFIX .. "Config not found in the config file '" .. CONFIG_FILE .. "'. Using defaults.");
		g_Config = {};  -- Defaults will be inserted by VerifyConfig()
	end
end




