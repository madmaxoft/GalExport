
-- Info.lua

-- Implements the g_PluginInfo standard plugin description





g_PluginInfo =
{
	Name = "GalExport",
	Date = "2015-06-19",
	Description =
[[
This plugin allows admins to mass-export Gallery areas that they have chosen as "approved". It provides
a grouping for those areas and can export either all areas, specified area or a named group of areas. The
export can write .schematic files, C++ source code (XPM3-like) or .cubeset files that are used in MCServer
for the piece generators, such as Villages.

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

				autoselect =
				{
					HelpString = "Turns AutoSelect on or off",
					Permission = "galexport.autoselect",
					Handler = HandleCmdAutoSelect,
					Alias = { "as", "asel", "autosel"},
					ParameterCombinations =
					{
						{
							Params = "bb",
							Help = "Automatically selects boundingbox when you enter an approved area",
						},
						{
							Params = "hb",
							Help = "Automatically selects hitbox when you enter an approved area",
						},
						{
							Params = "",
							Help = "Turns off auto-selection",
						},
					},
				},  -- autoselect

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
								Params = "ConnectorID",
								Help = "Deletes the specified connector",
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
									Params = "ConnectorID",
									Help = "Teleports you to the specified connector",
								},
							},
						},
						list =
						{
							HelpString = "Lists the connectors for the current area",
							Permission = "galexport.conn.list",
							Alias = {"l", "ls"},
							Handler = HandleCmdConnList,
						},
						reposition =
						{
							HelpString = "Changes the connector's position to your current position",
							Permission = "galexport.conn.reposition",
							Handler = HandleCmdConnReposition,
							Alias = "repos",
							ParameterCombinations =
							{
								{
									Params = "ConnectorID",
									Help = "Changes the connector's position to your current position",
								},
							},
						},
						retype =
						{
							HelpString = "Changes the connector's type",
							Permission = "galexport.conn.retype",
							Handler = HandleCmdConnRetype,
							ParameterCombinations =
							{
								{
									Params = "ConnectorID NewType",
									Help = "Changes the type of the specified connector",
								},
							},
						},
						shift =
						{
							HelpString = "Shifts the connector by the specified block distance",
							Permission = "galexport.conn.shift",
							Handler = HandleCmdConnShift,
							ParameterCombinations =
							{
								{
									Params = "ConnectorID Distance Direction",
									HelpString = "Shifts the connector by the specified distance in the given direction",
								},
								{
									Params = "ConnectorID Distance",
									HelpString = "Shifts the connector by the specified distance in your look direction",
								},
								{
									Params = "ConnectorID Direction",
									HelpString = "Shifts the connector by the 1 block in the given direction",
								},
								{
									Params = "ConnectorID",
									HelpString = "Shifts the connector by the 1 block in your look direction",
								},
							},
						},
					},  -- Subcommands
				},  -- connector

				disapprove =
				{
					HelpString = "Disapproves a previously approved area",
					Permission = "galexport.disapprove",
					Alias = {"dis", "da", "d"},
					Handler = HandleCmdDisapprove,
					ParameterCombinations =
					{
						{
							Params = "",
							Help = "Disapproves the area you're currently standing in",
						},
					},
				},  -- disapprove

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

				structurebox =
				{
					HelpString = "Manipulates the StructureBox property of an area",
					Alias = {"sbox", "sb"},
					Subcommands =
					{
						change =
						{
							HelpString = "Updates the structure box of the area you're standing in to your current WE selection",
							Permission = "galexport.sbox.change",
							Alias = {"c", "update", "u"},
							Handler = HandleCmdSboxChange,
						},  -- change

						show =
						{
							HelpString = "Sets your WE selection to the structure box of the area you're standing in",
							Permission = "gallexport.sbox.show",
							Alias = {"s", "view", "v"},
							Handler = HandleCmdSboxShow,
						},  -- show
					},  -- Subcommands
				},  -- structurebox

				unset =
				{
					HelpString = "Removes metadata value for the current area",
					Handler = HandleCmdUnset,
					ParameterCombinations =
					{
						{
							Params = "name",
							Help = "Removes the specified metadata from the current area",
						},
					},
				},  -- unset
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

				evolve =
				{
					HelpString = "Fixes various issues that have evolved during GalExport's lifetime, such as converting ShouldExpandFloor metadata to ExpandFloorStrategy metadata",
					Handler = HandleConEvolve,
				},

				group =
				{
					HelpString = "Exports the approved areas in the specified group",
					Handler = HandleConExportGroup,
				},

				meta =
				{
					HelpString = "Manipulates group metadata",
					Subcommands =
					{
						list =
						{
							HelpString = "Lists all metadata values for a single group",
							Handler = HandleConMetaList,
							ParameterCombinations =
							{
								{
									Params = "GroupName",
									Help = "Lists the metadata assigned to the specified group",
								},
							},
						},  -- list
						set =
						{
							HelpString = "Sets a metadata value for a single group",
							Handler = HandleConMetaSet,
							ParameterCombinations =
							{
								{
									Params = "GroupName MetaName MetaValue",
									Help = "Sets the specified group's metadata",
								},
							},
						},  -- set
					},  -- Subcommands
				},  -- meta
			}  -- Subcommands
		}  -- ge
	},  -- ConsoleCommands
}  -- g_PluginInfo




