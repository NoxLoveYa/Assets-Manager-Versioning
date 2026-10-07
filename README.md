# Asset Versioning

Version your Roblox asset folders per place: see what changed, go back, and merge work between places. A replacement for Package links built on **a Studio plugin + Rojo + git**.

## Set up (once)

Needs [Node.js](https://nodejs.org) and [Rojo](https://rojo.space) (already on your PATH if you use Rojo).

1. Double-click **`Setup.bat`**.
2. It installs the Studio plugin, then asks for your Rojo project folder (drag it into the window). It connects the project and adds **`Save Versions.bat`** to it.
3. Commit the new files in your project. Teammates only need to run `Setup.bat` once to get the plugin.
4. Restart Studio. The **Asset Versioning** button is in the Plugins tab.

## Everyday use (artists)

1. Open the **Asset Versioning** panel, click your asset folder in the Explorer, press **Track this folder**.
2. Work as usual. The panel shows whether the folder differs from the last snapshot and lists what changed.
3. **Save snapshot** when you're happy. **Restore snapshot** goes back (Ctrl+Z undoes it).
4. To share: save the place (Ctrl+S), then double-click **`Save Versions.bat`** in the project folder.

Another place's work arrives through git (branch per place, merge as usual). Once Rojo syncs it, the panel shows it under **Found in your project** (or as differences on a tracked folder, then press **Restore snapshot**).

## How it works

- The plugin writes each instance of a tracked folder as a small ModuleScript (`ServerStorage/AssetVersioning/<Folder>/<Name>~<id>`), with sorted properties so diffs stay small. Instances are matched by an `AssetVersioningId` attribute the plugin adds.
- Rojo maps that folder to `asset-versions/`. Rojo can't write Studio changes to disk live, so `Save Versions.bat` runs `rojo syncback` against the saved place (only the snapshot folder is touched) and records it in git.
- Merging is plain git on those files. Editing different items never conflicts.

## Developing

- `npm run plugin:build` builds `build/AssetVersioning.rbxm`; `npm run plugin:install` installs it for Studio.
- `scripts/save.js` is copied into each project by `scripts/setup.js`; re-run Setup to update it.

## Known limits

- Unions are stored as opaque shape data: they version, but two edits of the same union conflict.
- Properties of unsupported types (e.g. `Vector3int16`) and references to instances outside the tracked folder are not saved.
- Anything a plugin can't set (some mesh/read-only properties) is reported after a restore.
