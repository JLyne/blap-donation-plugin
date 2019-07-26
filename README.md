# blap-2019-plugin
Sourcemod plugin for Blap Summer Jam 2019. Displays donation total ingame among other things.

## Features

* Ingame donation total displays. Shown above objectives and next to resupplies by default, but can be added to any entity with custom positioning, rotation and size
* Supports amounts from $1 to $9999999
* Donations above $25, $50, $100 and which cross $x000, have their own effects and spawned props
* Blap medals drop on player kills
* Blap reskinned control points

## Requirements
* SteamWorks extension - For HTTP requests
* Socket extension - For socket connections (not currently used)
* Smjansson extension - For json parsing

## Configuration

Donation displays can be added to arbitrary entities on a per map basis, in the blap.cfg config file. More documentation can be found there.

## Cvars

* `blap_ducks_enabled` - Whether blap medal drops are enabled.
* `blap_cps_enabled`- Whether blap reskinned control points are enabled. Will take effect on map changes.
* `blap_sounds_enabled` - Whether donation displays can make sounds.
* `blap_props_enabled` - Whether donation displays can spawn props.
* `blap_donations_enabled` - Whether blap donation total displays are enabled. Will destroy/recreate displays immediately as required.

## Known issues

* Displays created at certain rotations can look incorrect
* If a display is recreated while an entity is rotated (i.e a payload on a hill, rotating control point), the rotation will be incorrect.
* Multiple prop spawning milestones in a row may stop spawning props, due to hitting the `cl_phys_props_max` limit. You'll need to increase it.
