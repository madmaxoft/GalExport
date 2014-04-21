
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
				
				connector =
				{
					HelpString = "Manipulates the connectors at individual areas",
					Alias = {"conn", "c"},
					Subcommands =
					{
						add =
						{
							HelpString = "Adds a new connector at your feet pos and head rotation",
							Permission = "galexport.conn.add",
							Alias = "a",
							Handler = HandleCmdConnAdd,
							ParameterCombinations =
							{
								{
									Params = "Type",
									Help = "Adds a new connector of the specified type at your feet pos and head rotation",
								},
							},
						},
						del =
						{
							HelpString = "Deletes a connector",
							Permission = "galexport.conn.del",
							Alias = {"d", "delete"},
							Handler = HandleCmdConnDel,
							ParameterCombinations =
							{
								Params = "",
								Help = "Deletes the connector at your feet pos",
							},
							{
								Params = "LocalID",
								Help = "Deletes the specified connector at the current area",
							},
						},
						["goto"] =  -- goto is a Lua keyword, so it needs to be "escaped"
						{
							HelpString = "Teleports you to the specified connector at the current area",
							Permission = "galexport.conn.goto",
							Alias = "g",
							Handler = HandleCmdConnGoto,
							ParameterCombinations =
							{
								{
									Params = "LocalID",
									Help = "Teleports you to the specified connector at the current area",
								},
							},
						},
						list =
						{
							HelpString = "Lists the connectors for the current area",
							Permission = "galexport.conn.list",
							Alias = {"l", "ls"},
							Handler = HandleCmdConnList,
						}
					},  -- Subcommands
				},  -- connector
				
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
						
						set =
						{
							HelpString = "Sets the group for the current area",
							Handler = HandleCmdGroupSet,
							Alias = "s",
							ParameterCombinations =
							{
								Params = "NewGroupName",
								Help = "Sets the group name for the current area",
							},
						},  -- set
					},  -- Subcommands
				},  -- group
				
				hitbox =
				{
					HelpString = "Manipulates the hit boxes for export",
					Alias = {"hbox", "hb", "h"},
					Subcommands =
					{
						change =
						{
							HelpString = "Updates the hit box of the area you're standing in to your current WE selection",
							Permission = "galexport.hbox.change",
							Alias = {"c", "update", "u"},
							Handler = HandleCmdHboxChange,
						},  -- change
						
						show =
						{
							HelpString = "Sets your WE selection to the hit box of the area you're standing in",
							Permission = "gallexport.hbox.show",
							Alias = {"s", "view", "v"},
							Handler = HandleCmdHboxShow,
						},  -- show
					},  -- Subcommands
				},  -- hitbox
				
				info =
				{
					HelpString = "Shows export-related information for the current area",
					Permission = "galexport.info",
					Alias = "i",
					Handler = HandleCmdInfo,
				},  -- info
				
				listapproved =
				{
					HelpString = "Shows a list of all the approved areas.",
					Permission = "galexport.listapproved",
					Alias = {"la", "list"},
					Handler = HandleCmdListApproved,
					ParameterCombinations =
					{
						{
							Params = "GroupName",
							Help = "Shows only the approved areas from the given group",
						},
						
						{
							Params = "",
							Help = "Shows all the approved areas from every group",
						},
					},
				},  -- listapproved
				
				name =
				{
					HelpString = "Sets the export name for the approved area you're standing in",
					Permission = "galexport.name",
					Alias = "n",
					Handler = HandleCmdName,
					ParameterCombinations =
					{
						{
							Params = "Name",
							Help = "Sets the export name for the approved area you're standing in",
						},
					},
				},  -- name
				
				set =
				{
					HelpString = "Sets a metadata value for the current area",
					Permission = "galexport.set",
					Handler = HandleCmdSet,
					ParameterCombinations =
					{
						{
							Params = "",
							Help = "Lists the metadata available for setting",
						},
						{
							Params = "Name Value",
							Help = "Sets the metadata named Name to value Value",
						},
					},
				},  -- set
				
				sponge =
				{
					HelpString = "Helps with \"sponging\" the areas for export",
					DevNotes = "Note that the area needn't be approved, sponging works on non-approved areas, too",
					Permission = "galexport.sponge",
					Alias = {"sp"},
					Subcommands =
					{
						hide =
						{
							HelpString = "Hides the sponges for the current area, discarding the changes",
							Handler = HandleCmdSpongeHide,
							Alias = "h",
						},
						save =
						{
							HelpString = "Saves the sponges for the current area, overwriting anything stored before",
							Handler = HandleCmdSpongeSave,
							Alias = "sa",
						},
						show =
						{
							HelpString = "Shows the sponges for the current area",
							Handler = HandleCmdSpongeShow,
							Alias = "sh",
						},
					},  -- Subcommands
				},  -- sponge
			},  -- Subcommands
		},  -- ["/ge"]
	},  -- Commands
	
	ConsoleCommands =
	{
		ge =
		{
			HelpString = "Exports the gallery areas marked as approved",
			Subcommands =
			{
				all =
				{
					HelpString = "Exports all the approved areas",
					Handler = HandleConExportAll,
				},
				
				group =
				{
					HelpString = "Exports the approved areas in the specified group",
					Handler = HandleConExportGroup,
				},
			}
		}
	},  -- ConsoleCommands
}  -- g_PluginInfo
				



