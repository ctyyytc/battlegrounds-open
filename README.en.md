# Battlegrounds Open · 14.5.0

[简体中文](README.md) | **English**

An unofficial battlegrounds gameplay implementation built with Godot 4.7. This repository contains a runnable source project: game code, functional data, resource interfaces, and project-authored placeholder images, UI artwork, and effects.

The maintainer shares this project free of charge. It is not affiliated with, partnered with, or endorsed by Blizzard Entertainment. The repository does not include original game artwork, original card descriptions, private resource packs, or download links to those materials. Compatibility IDs connect functional data and do not grant rights to third-party assets or trademarks. Resource packs are supplied separately; users must prepare local files they have the appropriate rights to use.

## Download for Windows

Download the [v14.5.0-r2 Windows x64 release](https://github.com/ctyyytc/battlegrounds-open/releases/tag/v14.5.0-r2), extract the entire ZIP, and run `battlegrounds-open.exe`. Keep the adjacent `.pck` file. No Godot installation is required. Resource packs are not included; install or uninstall a separately obtained pack from the in-game resource-pack menu.

The actual Windows release has been checked for resource-pack installation and persistence across restarts, buying and playing minions, manual saving, loading and continuing in a new process, uninstalling without deleting the source pack or saves, and restoring an existing save after reinstalling its matching pack. The final ZIP was also extracted and tested for starting and saving/loading without a pack. Rejecting a save whose numeric profile does not match is intentional compatibility protection. Other hardware, full natural matches, and all content combinations have not been validated.

r2 is a packaging revision of 14.5.0. It fixes built-in texture loading in exported builds, restoring keyword effects and the Yogg fate wheel, and adds 53 editable SVG sources for the current UI. The game version remains 14.5.0.

r2 additionally checks all 205 consumed effect frames, nine wheel images, trinket reminder pulsing on turns 6/9, removal after purchase, and static reduced-motion reminders. The actual executable extracted from the final ZIP was checked for representative keyword visuals, the wheel, manual saving, and loading in a new process. Production APIs in the exported PCK were also checked for installing/uninstalling/reinstalling pack A and saving/loading across processes; all 922 images matched their source hashes and decoded successfully. These checks use isolated constructed saves; full natural matches and all combinations were not rerun.

## Run from source

1. Install Godot 4.7. The source smoke checks used 4.7.2 stable.
2. Import this directory's `project.godot`, wait for the initial resource import, and run the main scene. No development plugin is required.
3. The main menu supports choosing from all legal heroes or choosing one of three candidates. Install a local resource pack from outside the project through the resource-pack menu, or start with the built-in placeholder content.

You can also run `godot --editor --path . --import`, followed by `godot --path .`. On Windows, use the corresponding Godot console executable.

Without a resource pack, the game displays compatibility IDs and generic computed descriptions. Neutral base values are used: heroes have 30 health and 0 armor, ordinary minions are 1/1, explicitly defined golden minions are 2/2, and tavern spells and both trinket sizes cost 2 coins. Code defines rules, eligibility, and effects. This placeholder mode does not claim to reproduce original artwork, text, or base values.

## Resource packs and saves

Keep resource packs outside this project. Extract a separately provided pack, open the main menu's resource-pack screen, choose the install action, and select its `pack.json`. A successful installation takes effect immediately. Uninstalling and restoring defaults removes only the application's managed installation copy; it keeps the source pack and match saves. See [RESOURCE_PACKS.md](RESOURCE_PACKS.md) for the format, path requirements, and offline tools.

The application uses its own `battlegrounds-open` user-data directory, separate from the development project. Saves and installed packs are written to Godot's user-data location rather than the source directory. The game saves once after all mandatory start-of-round choices finish; manual saving remains available during the round. A pack with different base numeric values prevents loading a mismatched match save. Changes to text and images do not change the numeric profile.

Opening settings does not pause the match automatically: recruitment timers and replays continue according to the current pause state. During recruitment, the last three complete actions can be undone with no usage-count limit; undo does not cross rounds, combat, or loading a save.

## Building and validation scope

A Windows export preset is provided. Building requires matching Godot export templates installed separately. The source tree does not contain the engine, export templates, executables, old Git history, or test artifacts. Development plugins, private packs, real player saves, and internal development records are excluded.

The source copy and Windows release have passed smoke checks for import, startup, basic actions, saves, and resource-pack installation/uninstallation within the scope affected by this preparation. The entire historical suite, full natural matches, and all combinations were not rerun. Implementation status is available in the in-game encyclopedia.

See [LICENSE](LICENSE) for the code license, [ASSET_LICENSES.md](ASSET_LICENSES.md) for built-in image licensing, and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for external-tool and third-party boundaries. `PUBLIC_FILES.json` lists the size and SHA-256 of every repository file except the manifest itself.

## Contact

Maintainer email: [2571114956@qq.com](mailto:2571114956@qq.com).
