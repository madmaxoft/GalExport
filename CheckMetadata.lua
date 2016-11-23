
-- CheckMetadata.lua

-- Implements the metadata checking





local ins = table.insert





--- Maps valid lowercased vertical strategies to a table describing the min and max number of params for that strategy
local g_VerticalStrategyParams =
{
	fixed =
	{
		min = 1,
		max = 1,
	},
	range =
	{
		min = 2,
		max = 2,
	},
	terraintop =
	{
		min = 0,
		max = 2,
	},
	terrainoroceantop =
	{
		min = 0,
		max = 2,
	},
}





--- Maps valid lowercased vertical limits to a table describing the min and max number of params for that limit
local g_VerticalLimitParams =
{
	[""] =
	{
		min = 0,
		max = 1000,
	},
	none =
	{
		min = 0,
		max = 1000,
	},
	above =
	{
		min = 1,
		max = 1,
	},
	aboveterrain =
	{
		min = 0,
		max = 2,
	},
	aboveterrainandocean =
	{
		min = 0,
		max = 2,
	},
	below =
	{
		min = 1,
		max = 1,
	},
	belowterrain =
	{
		min = 0,
		max = 2,
	},
	belowterrainorocean =
	{
		min = 0,
		max = 2,
	},
}





--- Group parameters that are required, based on the value of group's IntendedUse
-- Maps lowercased IntendedUse to an array of requires group parameter names
-- Also used to determine whether IntendedUse is known or not, so all IntendedUse values must be present (with empty arrays if needed)
local g_RequiredParamsPerIntendedValue =
{
	piecestructures =
	{
		"GridSizeX",
		"GridSizeZ",
		"MaxDepth",
		"MaxOffsetX",
		"MaxOffsetZ",
		"MaxStructureSizeX",
		"MaxStructureSizeZ",
		"SeedOffset",
	},

	trees =
	{
	},

	village =
	{
	},
}





--- Group-metadata checking functions
-- Maps lowercased metadata name to a function that checks the value
-- If a meta name value is not present, there's no check for it (-> not necessarily invalid name)
-- Checker signature: fn(a_OutputArray, a_GroupName, a_MetaValue); issues are appended to a_OutputArray
local g_GroupMetaChecker =
{
	intendeduse = function (a_Out, a_GroupName, a_MetaValue)
		if not(g_RequiredParamsPerIntendedValue[string.lower(a_MetaValue)]) then
			ins(a_Out, { GroupName = a_GroupName, Issue = "Unknown IntendedUse value: \"" .. a_MetaValue .. "\""})
		end
	end,

	allowedbiomes = function (a_Out, a_GroupName, a_MetaValue)
		local biomes = StringSplitAndTrim(a_MetaValue, ",")
		for _, biomeStr in ipairs(biomes) do
			local biomeValue = StringToBiome(biomeStr)
			if (biomeValue == biInvalidBiome) then
				ins(a_Out, { GroupName = a_GroupName, Issue = "Unknown biome in AllowedBiomes: \"" .. biomeStr .. "\""})
			end
		end
	end,
}





--- Checks the VerticalStrategy string for validness
-- Returns true if the strategy is valid, false and reason string if not
local function checkVerticalStrategy(a_VerticalStrategy)
	local s = StringSplit(a_VerticalStrategy, "|")
	if not(s[1]) then
		return false, "Failed to parse strategy class"
	end
	local strategyParams = g_VerticalStrategyParams[string.lower(s[1])]
	if not(strategyParams) then
		return false, "Unknown strategy class: " .. s[1]
	end
	local numParams = #s - 1
	if (numParams < strategyParams.min) then
		return false, "Too few parameters (got " .. numParams .. ", expected at least " .. strategyParams.min .. ")"
	end
	if (numParams > strategyParams.max) then
		return false, "Too many parameters (got " .. numParams .. ", expected at most " .. strategyParams.max .. ")"
	end
	return true
end





--- Checks the VerticalLimit string for validness
-- Returns true if the limit is valid, false and reason string if not
local function checkVerticalLimit(a_VerticalLimit)
	local s = StringSplit(a_VerticalLimit, "|")
	if not(s[1]) then
		return false, "Failed to parse limit class"
	end
	local limitParams = g_VerticalLimitParams[string.lower(s[1])]
	if not(limitParams) then
		return false, "Unknown limit class: " .. s[1]
	end
	local numParams = #s - 1
	if (numParams < limitParams.min) then
		return false, "Too few parameters (got " .. numParams .. ", expected at least " .. limitParams.min .. ")"
	end
	if (numParams > limitParams.max) then
		return false, "Too many parameters (got " .. numParams .. ", expected at most " .. limitParams.max .. ")"
	end
	return true
end





--- Checks metadata for the specified areas
-- Returns an array of all issues found, { Area = <AreaDesc>, Issue = "" }
-- Returns false and an optional error message on error
local function checkAreasMetadata(a_Areas)
	local res = {}
	for _, area in ipairs(a_Areas) do
		local metadata, msg = g_DB:GetMetadataForArea(area.ID)
		if not(metadata) then
			ins(res, { Area = area, Issue = "Failed to query area metadata from the DB: " .. (msg or "<unknown error>")})
		else
			local isStarting = (tostring(metadata["IsStarting"]) == "1")
			if (isStarting) then
				local verticalStrategy = metadata["VerticalStrategy"]
				if not(verticalStrategy) then
					ins(res, { Area = area, Issue = "Area is starting, but has no VerticalStrategy assigned to it"})
				else
					local isValid, msg = checkVerticalStrategy(verticalStrategy)
					if not(isValid) then
						ins(res, { Area = area, Issue = "VerticalStrategy is invalid: " .. msg})
					end
				end
				if (metadata["VerticalLimit"]) then
					ins(res, { Area = area, Issue = "Area is starting, but has a VerticalLimit assigned to it"})
				end
			else
				if (metadata["VerticalStrategy"]) then
					ins(res, { Area = area, Issue = "Area is not starting, but has a VerticalStrategy assigned to it"})
				end
				local verticalLimit = metadata["VerticalLimit"]
				if (verticalLimit) then
					local isValid, msg = checkVerticalLimit(verticalLimit)
					if not(isValid) then
						ins(res, { Area = area, Issue = "VerticalLimit is invalid: " .. msg})
					end
				end
			end  -- else (isStarting)
		end  -- else (metadata)
	end  -- for area - a_Areas[]
	return res
end





--- Checks the specified groups' metadata
-- Returns an array of all issues found, { GroupName = "", Issue = "" }
-- Returns false and an optional error message on error
local function checkGroupsMetadata(a_GroupNames)
	local res = {}
	for _, grp in ipairs(a_GroupNames) do
		local groupMeta, msg = g_DB:GetMetadataForGroup(grp)
		if not(groupMeta) then
			ins(res, { GroupName = grp, Issue = "Cannot retrieve group metadata from the DB: " .. (msg or "<unknown error>")})
		else
			-- Check that IntendedUse is always present:
			local intendedUse = groupMeta["IntendedUse"]
			if not(intendedUse) then
				ins(res, { GroupName = grp, Issue = "The value for IntendedUse is not set"})
			end

			-- Check the required params for the intended use:
			if (intendedUse) then
				for _, rn in ipairs(g_RequiredParamsPerIntendedValue[string.lower(intendedUse)] or {}) do
					if not(groupMeta[rn]) then
						ins(res, { GroupName = grp, Issue = string.format("Required parameter \"%s\" is not set", rn)})
					end
				end
			end

			-- If there is a checker for the meta, call it:
			for mn, mv in pairs(groupMeta) do
				local checker = g_GroupMetaChecker[string.lower(mn)]
				if (checker) then
					checker(res, grp, mv)
				end
			end
		end
	end  -- for grp - a_GroupNames[]
	return res
end





--- Checks metadata for all areas in the DB
-- Returns an array of all issues found, { Area = <AreaDesc>, Issue = "" }
-- Returns false and an optional error message on error
function checkAllAreasMetadata()
	-- Get all areas:
	local areas, msg = g_DB:GetAllApprovedAreas()
	if not(areas) then
		return false, "Cannot load approved areas from the DB: " .. (msg or "[unknown error]")
	end

	return checkAreasMetadata(areas)
end





--- Checks all export groups' metadata
-- Returns an array of all issues found, { GroupName = "", Issue = "" }
-- Returns false and an optional error message on error
function checkAllGroupsMetadata()
	-- Get all groups:
	local groups, msg = g_DB:GetAllGroupNames()
	if not(groups) then
		return false, "Cannot load export groups from the DB: " .. (msg or "[unknown error]")
	end
	table.sort(groups)

	return checkGroupsMetadata(groups)
end




