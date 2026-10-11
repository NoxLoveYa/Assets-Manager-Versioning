# Asset Versioning (Roblox-only)

Version your Roblox asset folders per place: save versions, see what changed, go back, and combine work from different places. A replacement for Package links that lives **entirely inside Roblox Studio**. No Rojo, git or Node needed to use it.

> The git + Rojo version is on the [`v0.1`](../../tree/v0.1) branch.

## Install (once)

1. Download [`dist/AssetVersioning.rbxm`](dist/AssetVersioning.rbxm).
2. Put it in Studio's plugins folder: **Plugins tab > Plugins Folder**, then drop the file in.
3. Restart Studio. The **Asset Versioning** button is in the Plugins tab.

## Everyday use

1. Open the panel, click your asset folder in the Explorer, press **Track this folder**. The first version is saved for you.
2. Work as usual. The panel shows whether the folder differs from your latest version and lists what changed (**See changes**).
3. **Save version** when you're happy (add a short note if you like).
4. **History** lists past versions. **What changed** shows the difference, **Go back to this** puts the folder back (Ctrl+Z undoes it).
5. **Discard changes** throws away unsaved work and returns to the latest version.

## Several places

Each place keeps its own *line* of versions, named after the place. To share:

- **Same Team Create place:** nothing to do, the history is shared automatically.
- **Different places:** press **Export to file** on a folder, open the other place, press **Import a file**, then either **Add to this place** (new folder) or **Combine with another line** (existing folder).

Combining merges item by item: changes to different items, or to different properties of the same item, merge on their own. If both places changed the same property of the same item, you pick **Keep mine** or **Use theirs** for that item. Save a version before combining so nothing is lost.

## How it works

History is stored in the place itself, under `ServerStorage/AssetVersioning/<Folder>/`:

| Folder | Holds |
| --- | --- |
| `Objects` | one ModuleScript per distinct item, named by content hash (unchanged items are stored once) |
| `Commits` | one folder per version: note, author, time, parent version(s) and the list of items |
| `Branches` | the latest version of each line of work |

Items are matched across versions by an `AssetVersioningId` attribute the plugin adds, so renames and moves show up as changes, not delete-and-add.

## Things to know

- **Only import files from people you trust.** Versions are ModuleScripts that the plugin runs to read them.
- The history ships with the place when you publish. Delete `ServerStorage/AssetVersioning` from a release build if you don't want it there.
- Unions are stored as opaque shape data: they version, but two edits of the same union conflict. Script source is merged as a whole (no line-level merge): if two places edited the same script, you choose one.
- Properties of unsupported types (e.g. `Vector3int16`) and references to instances outside the tracked folder are not saved. Anything a plugin can't set is reported after a restore.
- Old versions are never deleted, so the history only grows.

## Developing

`rojo build plugin.project.json -o dist/AssetVersioning.rbxm` rebuilds the plugin (needs [Rojo](https://rojo.space)). Source is in `plugin/src`.
