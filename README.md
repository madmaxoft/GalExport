This plugin allows admins to mass-export Gallery areas that they have chosen as "approved". It provides a grouping for those areas and can export either all areas, specified area or a named group of areas. The export can write either .schematic files or C++ source code (XPM3-like) that is used in MCServer for the built-in piece generator.

Note that this plugin requires interaction with the WorldEdit plugin - the area bounding-boxes are defined and edited with the help of WorldEdit and its WECUI link. 

# Commands

### General
| Command | Permission | Description |
| ------- | ---------- | ----------- |
|/ge approve | galexport.approve | Approves the area where you're standing|
|/ge autoselect | galexport.autoselect | Turns AutoSelect on or off|
|/ge boundingbox |  | Manipulates the bounding boxes for export|
|/ge boundingbox change | galexport.bbox.change | Updates the bounding box of the area you're standing in to your current WE selection|
|/ge boundingbox show | gallexport.bbox.show | Sets your WE selection to the bounding box of the area you're standing in|
|/ge connector |  | Manipulates the connectors at individual areas|
|/ge connector add | galexport.conn.add | Adds a new connector at your feet pos and head rotation|
|/ge connector del | galexport.conn.del | Deletes a connector|
|/ge connector goto | galexport.conn.goto | Teleports you to the specified connector at the current area|
|/ge connector list | galexport.conn.list | Lists the connectors for the current area|
|/ge connector reposition | galexport.conn.reposition | Changes the connector's position to your current position|
|/ge connector retype | galexport.conn.retype | Changes the connector's type|
|/ge connector shift | galexport.conn.shift | Shifts the connector by the specified block distance|
|/ge disapprove | galexport.disapprove | Disapproves a previously approved area|
|/ge export |  | Exports areas|
|/ge export all | galexport.export.all | Exports all areas that have been approved|
|/ge export group | galexport.export.group | Exports all areas in the specified group|
|/ge export this | galexport.export.this | Exports the area you're standing on|
|/ge group | galexport.group | Manages groups of approved areas|
|/ge group list |  | Lists available groups|
|/ge group rename |  | Renames existing group|
|/ge group set |  | Sets the group for the current area|
|/ge hitbox |  | Manipulates the hit boxes for export|
|/ge hitbox change | galexport.hbox.change | Updates the hit box of the area you're standing in to your current WE selection|
|/ge hitbox show | gallexport.hbox.show | Sets your WE selection to the hit box of the area you're standing in|
|/ge info | galexport.info | Shows export-related information for the current area|
|/ge listapproved | galexport.listapproved | Shows a list of all the approved areas.|
|/ge name | galexport.name | Sets the export name for the approved area you're standing in|
|/ge set | galexport.set | Sets a metadata value for the current area|
|/ge sponge | galexport.sponge | Helps with "sponging" the areas for export|
|/ge sponge hide |  | Hides the sponges for the current area, discarding the changes|
|/ge sponge save |  | Saves the sponges for the current area, overwriting anything stored before|
|/ge sponge show |  | Shows the sponges for the current area|



# Permissions
| Permissions | Description | Commands | Recommended groups |
| ----------- | ----------- | -------- | ------------------ |
| galexport.approve |  | `/ge approve` |  |
| galexport.autoselect |  | `/ge autoselect` |  |
| galexport.bbox.change |  | `/ge boundingbox change` |  |
| galexport.conn.add |  | `/ge connector add` |  |
| galexport.conn.del |  | `/ge connector del` |  |
| galexport.conn.goto |  | `/ge connector goto` |  |
| galexport.conn.list |  | `/ge connector list` |  |
| galexport.conn.reposition |  | `/ge connector reposition` |  |
| galexport.conn.retype |  | `/ge connector retype` |  |
| galexport.conn.shift |  | `/ge connector shift` |  |
| galexport.disapprove |  | `/ge disapprove` |  |
| galexport.export.all |  | `/ge export all` |  |
| galexport.export.group |  | `/ge export group` |  |
| galexport.export.this |  | `/ge export this` |  |
| galexport.group |  | `/ge group` |  |
| galexport.hbox.change |  | `/ge hitbox change` |  |
| galexport.info |  | `/ge info` |  |
| galexport.listapproved |  | `/ge listapproved` |  |
| galexport.name |  | `/ge name` |  |
| galexport.set |  | `/ge set` |  |
| galexport.sponge |  | `/ge sponge` |  |
| gallexport.bbox.show |  | `/ge boundingbox show` |  |
| gallexport.hbox.show |  | `/ge hitbox show` |  |
