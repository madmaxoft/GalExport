
-- Info.lua

-- Implements the g_PluginInfo standard plugin description





g_PluginInfo = 
{
	Name = "GalExport",
	Date = "2014-03-12",
	Description =
[[
This plugin allows admins to mass-export Gallery areas that they have chosen as "approved". It provides
a grouping for those areas and can export either all areas, specified area or a named group of areas. The
export can write either .schematic files or C++ source code (XPM3-like) that is used in MCServer for the
built-in piece generator.

Note that this plugin requires interaction with the WorldEdit plugin - the area bounding-boxes are defined
and edited with the help of WorldEdit and its WECUI link.
]],

	Commands =
	{
		["/ge"] =
		{
			Permission = "",
			HelpString = "",
			Handler = nil,
			Subcommands =
			{
				approve =
				{
					HelpString = "Approves the area where you're standing",
					Permission = "galexport.approve",
					Handler = HandleCmdApprove,
					Alias = {"appr", "a", "accept", "acc"},
					ParameterCombinations =
					{
						{
							Params = "GroupName",
							Help = "Approves the area where you're now standing, adding it to the specified group",
						},
					},
				},  -- approve
				
				boundingbox =
				{
					HelpString = "Manipulates the bounding boxes for export",
					Alias = {"bbox", "bb", "b"},
					Subcommands =
					{
						change =
						{
							HelpString = "Updates the bounding box of the area you're standing in to your current WE selection",
							Permission = "galexport.bbox.change",
							Alias = {"c", "update", "u"},
							Handler = HandleCmdBboxChange,
						},  -- change
						
						show =
						{
							HelpString = "Sets your WE selection to the bounding box of the area you're standing in",
							Permission = "gallexport.bbox.show",
							Alias = {"s", "view", "v"},
							Handler = HandleCmdBboxShow,
						},  -- show
					},  -- Subcommands
				},  -- boundingbox
				
				export =
				{
					HelpString = "Exports areas",
					Alias = {"exp", "e"},
					Subcommands =
					{
						this =
						{
							HelpString = "Exports the area you're standing on",
							Permission = "galexport.export.this",
							Handler = HandleCmdExportThis,
							Alias = "t",
							ParameterCombinations =
							{
								{
									Params = "Format",
									Help = "Exports the area you're standing on in the specified format",
								},
							},
						},  -- this
						
						all =
						{
							HelpString = "Exports all areas that have been approved",
							Permission = "galexport.export.all",
							Handler = HandleCmdExportAll,
							Alias = "a",
							ParameterCombinations =
							{
								{
									Params = "Format",
									Help = "Exports all approved areas in the specified format",
								},
							},
						},  -- all
						
						group =
						{
							HelpString = "Exports all areas in the specified group",
							Permission = "galexport.export.group",
							Handler = HandleCmdExportGroup,
							Alias = {"grp", "g"},
							ParameterCombinations =
							{
								{
									Params = "GroupName Format",
									Help = "Exports all areas in the specified group in the specified format",
								},
							},
						},  -- group
					},  -- Subcommands
				},  -- export
				
				group =
				{
					HelpString = "Manages groups of approved areas",
					Permission = "galexport.group",
					Alias = {"grp", "g"},
					Subcommands =
					{
						list =
						{
							HelpString = "Lists available groups",
							Handler = HandleCmdGroupList,
							Alias = {"ls", "l"},
						},  -- list
						
						rename =
						{
							HelpString = "Renames existing group",
							Handler = HandleCmdGroupRename,
							Alias = {"ren", "r"},
							ParameterCombinations =
							{
								{
									Params = "FromName ToName",
									Help = "Renames the group from FromName to ToName",
								},
							},
						},  -- rename
					},  -- Subcommands
				},  -- group
				
				listapproved =
				{
					HelpString = "Shows a list of all the approved areas.",
					Permission = "galexport.listapproved",
					Alias = {"la", "list"},
					ParameterCombinations =
					{
						{
							Params = "GroupName",
							Help = "Shows only the approved areas from the given group",
						},
					},
				},
			},  -- Subcommands
		},  -- ["/ge"]
	},  -- Commands
}  -- g_PluginInfo
				



