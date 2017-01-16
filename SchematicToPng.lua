
-- SchematicToPng.lua

-- Implements the cSchematicToPng class representing a connection to MCSchematicToPng

--[[
Members:
	Link: the cNetwork object representing the connection. Only valid when the connection is established.
	IsFullyConnected: bool specifying whether the connection can be used for exporting (handshake has finished)
	Queue: table of export requests. Each item has at least AreaData, Options and OutFileName members
	PendingCommands: dictionary-table of commands that have been sent to server but not yet finished.
		Maps CmdID to its corresponding export request (same format as Queue item, additionally has CmdID member)
	IncomingData: string of incoming network data that hasn't been parsed yet
	NextCmdID: number used as the next command's CmdID
	HostName: The name of the machine to connect to
	Port: The port on the machine to connect to
--]]





--- The class prototype
local cSchematicToPng = {}

--- If not nil, this is a file into which all communication gets logged
local g_LogFile -- = io.open("MCSchematicToPng-GalExport.log", "w")





function cSchematicToPng:Connect()
	-- Check params:
	assert(self)
	assert(self.Port)
	assert(not(self.Link))

	-- Start the connection:
	cNetwork:Connect(self.HostName, self.Port,
	{
		OnError = function (a_Link, a_ErrorCode, a_ErrorMsg)
			LOGWARNING(PLUGIN_PREFIX .. "Error in connection to MCSchematicToPng (" .. self.HostName .. ":" .. self.Port .. "): " .. (a_ErrorMsg or "<unknown error>"))
			self:Disconnected()
		end,
		OnRemoteClosed = function (a_Link)
			self:Disconnected()
		end,
		OnReceivedData = function (a_Link, a_Data)
			self.Link = a_Link
			self:ProcessIncomingData(a_Data)
		end
	})
end





--- Called when the link gets disconnected
-- Resets all internal variables to their defaults, so that reconnection works
function cSchematicToPng:Disconnected()
	assert(self)

	self.Link = nil
	self.Version = nil
	self.IncomingData = ""
	self.IsFullyConnected = false

	-- Move PendingCommands back into the queue:
	for _, cmd in pairs(self.PendingCommands) do
		cmd.CmdID = nil  -- Reset the Command ID
		table.insert(self.Queue, cmd)
	end
	self.PendingCommands = {}
end





--- Sends an area to MCSchematicToPng for export to the specified file name.
-- Note that the execution is asynchronous - the function may return before MCSchematicToPng decides
-- to return the image data.
-- a_BlockArea is the cBlockArea object representing the area
-- a_Options is a simple table of the options to specify for the request (sizes, markers, ...)
-- a_OutFileName is the filename for the resulting PNG image to be written to
function cSchematicToPng:Export(a_BlockArea, a_Options, a_OutFileName)
	-- Check params:
	assert(self)
	assert(tolua.type(a_BlockArea) == "cBlockArea")
	assert(type(a_Options or {}) == "table")
	assert(type(a_OutFileName) == "string")

	-- Save the area data to a schematic string:
	local areaData, msg = a_BlockArea:SaveToSchematicString()
	if not(areaData) then
		LOGWARNING("Cannot save area to schematic string for PNG export: " .. (msg or "[no message]"))
		return
	end

	-- Enqueue the request:
	local queueItem =
	{
		AreaData = areaData,
		Options = a_Options,
		OutFileName = a_OutFileName,
	}
	self:QueueExport(queueItem)
end





--- Returns an unused CmdID for a new command
function cSchematicToPng:GetNextCmdID()
	-- Check params:
	assert(self)

	local cmdID = self.NextCmdID or 0
	self.NextCmdID = cmdID + 1
	return cmdID
end





--- Processes a reply to a previously sent command incoming from the network connection
function cSchematicToPng:ProcessIncomingCmdReply(a_CmdReply)
	-- Check params:
	assert(self)
	assert(type(a_CmdReply) == "table")

	-- Find the command:
	local cmdID = a_CmdReply.CmdID
	if not(cmdID) then
		LOG(PLUGIN_PREFIX .. "MCSchematicToPng connection received a cmd reply without CmdID; ignoring message.")
		return
	end
	if (cmdID == "SetNameCmdID") then
		-- Ignore this response, it was the SetName command
		return
	end
	local cmd = self.PendingCommands[cmdID]
	if not(cmd) then
		LOG(string.format("%sMCSchematicToPng connection received a cmd reply with an invalid CmdID %q; ignoring message.",
			PLUGIN_PREFIX, cmdID
		))
		return
	end
	self.PendingCommands[cmdID] = nil

	-- Check the command status:
	local status = a_CmdReply.Status
	if (status == "error") then
		LOG(string.format("%sMCSchematicToPng connection received a cmd reply with an error for CmdID %q: %s",
			PLUGIN_PREFIX, cmdID, a_CmdReply.ErrorText or "[no message]"
		))
		return
	end
	if (status ~= "ok") then
		LOG(string.format("%sMCSchematicToPng connection received a cmd reply with an unknown status %q for CmdID %q: %s",
			PLUGIN_PREFIX, tostring(status), cmdID, a_CmdReply.ErrorText or "[no message]"
		))
		return
	end

	-- Store the data into the destination file:
	if (cmd.OutFileName) then
		if not(a_CmdReply.PngData) then
			LOG(string.format("%sMCSchematicToPng connection received a cmd reply with no PNG data for CmdID %q",
				PLUGIN_PREFIX, cmdID
			))
			return
		end
		local f, msg = io.open(cmd.OutFileName, "wb")
		if not(f) then
			LOG(string.format("%sCannot save PNG image to file %s: %s",
				PLUGIN_PREFIX, cmd.OutFileName, msg or "[no message]"
			))
			return
		end
		f:write(Base64Decode(a_CmdReply.PngData))
		f:close()
	end
end





--- Processes the data incoming from the network connection
function cSchematicToPng:ProcessIncomingData(a_Data)
	-- Check params:
	assert(self)
	assert(type(a_Data) == "string")

	-- Log the incoming data to the logfile:
	if (g_LogFile) then
		g_LogFile:write("Incoming data (", string.len(a_Data), " bytes):\n", a_Data, "\n\n")
	end

	-- Split data on message boundaries
	self.IncomingData = string.gsub(self.IncomingData .. a_Data, "([^\23]+)\23",
		function (a_Message)
			-- a_Package is a single JSON message from the peer, parse and process:
			local json, msg = cJson:Parse(a_Message)
			if not(json) then
				LOGWARNING(string.format("%sMCSchematicToPng connection received unparsable data: %s", PLUGIN_PREFIX, msg or "[no message]"))
				self.Link:Close()
				self:Disconnected()
				return ""
			end
			self:ProcessIncomingMessage(json)
			return ""
		end
	)
end





--- Processes a single incoming message from the network connection
function cSchematicToPng:ProcessIncomingMessage(a_Message)
	-- Check params:
	assert(self)
	assert(type(a_Message) == "table")

	if (self.IsFullyConnected) then
		return self:ProcessIncomingCmdReply(a_Message)
	end


	-- Receiving the initial handshake - name and version information:
	if not(a_Message.MCSchematicToPng) then
		LOGWARNING(PLUGIN_PREFIX .. "MCSchematicToPng connection received invalid handshake.")
		self.Link:Close()
		self:Disconnected()
	end
	if (tostring(a_Message.MCSchematicToPng) ~= "2") then
		LOGWARNING(string.format("%sMCSchematicToPng connection received unhandled protocol version: %s",
			PLUGIN_PREFIX, tostring(a_Message.MCSchematicToPng))
		)
		self.Link:Close()
		self:Disconnected()
	end
	self.Version = header
	self.IsFullyConnected = true
	self:SendJson({Cmd = "SetName", Name = "GalExport", CmdID = "SetNameCmdID"})

	-- Send the export requests that have been queued:
	for _, qi in ipairs(self.Queue or {}) do
		self:SendExportRequest(qi)
	end
	self.Queue = {}
end





--- Adds the export request to the queue and attempts to send it to MCSchematicToPng, if connected
-- a_QueueItem is a table describing the export request, it has at least AreaData, Options and OutFileName members
function cSchematicToPng:QueueExport(a_QueueItem)
	-- Check params:
	assert(self)
	assert(type(a_QueueItem) == "table")
	assert(a_QueueItem.AreaData)
	assert(a_QueueItem.Options)
	assert(a_QueueItem.OutFileName)
	assert(not(a_QueueItem.CmdID))

	-- Send the request, or add to queue and reconnect
	if (self.IsFullyConnected) then
		self:SendExportRequest(a_QueueItem)
	else
		table.insert(self.Queue, a_QueueItem)
		self:Connect()
	end
end





function cSchematicToPng:ReconnectIfNeeded()
	assert(self)

	if (self.Link) then
		-- The link is valid, no reconnection needed
		return
	end

	-- The link is not valid, try to reconnect:
	self:Connect()
end





--- Sends the specified request for export to the connected peer
-- Assumes that the connection is already established
-- a_QueueItem is a table describing the export request
function cSchematicToPng:SendExportRequest(a_QueueItem)
	-- Check params and preconditions:
	assert(self)
	assert(type(a_QueueItem) == "table")
	assert(self.IsFullyConnected)

	-- Assignd CmdID, add to PendingCommands:
	a_QueueItem.CmdID = self:GetNextCmdID()
	self.PendingCommands[a_QueueItem.CmdID] = a_QueueItem

	-- Write to the link:
	local cmd =
	{
		Cmd = "RenderSchematic",
		CmdID = a_QueueItem.CmdID,
		BlockData = Base64Encode(a_QueueItem.AreaData),
	}
	for k, v in pairs(a_QueueItem.Options) do
		cmd[k] = v
	end
	self:SendJson(cmd)
end





--- Sends the given table as a JSON message to the server
-- a_JsonTable is a table that will be serialized and sent over the network connection
function cSchematicToPng:SendJson(a_JsonTable)
	-- Check params and preconditions:
	assert(self)
	assert(self.Link)

	local json = cJson:Serialize(a_JsonTable)

	-- DEBUG: Log into file:
	if (g_LogFile) then
		g_LogFile:write("Sending JSON:\n", json, "\n\n")
	end

	self.Link:Send(json)
	self.Link:Send('\23')
end





function SchematicToPng_new(a_Config)
	assert(type(a_Config) == "table")
	cSchematicToPng.HostName = a_Config.HostName or "localhost"
	cSchematicToPng.Port = a_Config.Port
	cSchematicToPng.Queue = {}
	cSchematicToPng.PendingCommands = {}
	cSchematicToPng.IncomingData = ""
	cSchematicToPng:Connect()
	return cSchematicToPng
end




