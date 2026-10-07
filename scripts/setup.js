#!/usr/bin/env node
// One-time setup. Installs the Studio plugin, then connects a Rojo project to Asset Versioning.
//
//   node scripts/setup.js [projectFolder] [--plugin-only] [--project-only]

const fs = require("fs");
const os = require("os");
const path = require("path");
const readline = require("readline");
const { spawnSync } = require("child_process");

const toolRoot = path.resolve(__dirname, "..");
const SNAPSHOTS = "asset-versions";

function fail(message) {
  console.error(`\nSomething needs your attention:\n  ${message}\n`);
  process.exit(1);
}

function ask(question) {
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  return new Promise((resolve) => rl.question(question, (a) => (rl.close(), resolve(a.trim()))));
}

function pluginsDir() {
  if (process.platform === "win32") return path.join(process.env.LOCALAPPDATA || "", "Roblox", "Plugins");
  if (process.platform === "darwin") return path.join(os.homedir(), "Documents", "Roblox", "Plugins");
  fail("Roblox Studio isn't available on this system.");
}

function installPlugin() {
  console.log("\n[1/2] Installing the Studio plugin...");
  const dir = pluginsDir();
  fs.mkdirSync(dir, { recursive: true });
  const dest = path.join(dir, "AssetVersioning.rbxm");
  const r = spawnSync("rojo", ["build", path.join(toolRoot, "plugin.project.json"), "-o", dest], { encoding: "utf8" });
  if (r.error && r.error.code === "ENOENT") {
    fail("Rojo isn't installed (or isn't on PATH). Ask a teammate, or install it from https://rojo.space");
  }
  if (r.status !== 0) fail(`Couldn't build the plugin:\n${r.stderr}`);
  console.log(`  Installed to ${dest}`);
  console.log("  Restart Roblox Studio to see the \"Asset Versioning\" button in the Plugins tab.");
}

function findProjectFile(dir) {
  const preferred = path.join(dir, "default.project.json");
  if (fs.existsSync(preferred)) return preferred;
  const all = fs.readdirSync(dir).filter((f) => f.endsWith(".project.json"));
  if (all.length === 1) return path.join(dir, all[0]);
  if (all.length > 1) fail(`Found several Rojo projects in ${dir}. Keep one default.project.json.`);
  fail(`No Rojo project (default.project.json) found in ${dir}. Is this the right folder?`);
}

function manualSteps(projectFile) {
  console.log(`\n  Couldn't edit ${path.basename(projectFile)} automatically (it has comments or custom formatting).`);
  console.log('  Please add this inside "ServerStorage" in the "tree" part:\n');
  console.log(`    "AssetVersioning": { "$path": "${SNAPSHOTS}", "$ignoreUnknownInstances": true }\n`);
  console.log('  (If there is no "ServerStorage" yet, add: "ServerStorage": { "$className": "ServerStorage", ... })');
}

function connectProject(dir) {
  console.log("\n[2/2] Connecting the project...");
  const projectFile = findProjectFile(dir);

  let json;
  try {
    json = JSON.parse(fs.readFileSync(projectFile, "utf8"));
  } catch {
    manualSteps(projectFile);
    json = null;
  }

  if (json) {
    json.tree = json.tree || {};
    const storage = (json.tree.ServerStorage = json.tree.ServerStorage || { $className: "ServerStorage" });
    if (storage.AssetVersioning) {
      console.log(`  ${path.basename(projectFile)} is already connected.`);
    } else {
      storage.AssetVersioning = { $path: SNAPSHOTS, $ignoreUnknownInstances: true };
      fs.writeFileSync(projectFile, JSON.stringify(json, null, 2) + "\n");
      console.log(`  Updated ${path.basename(projectFile)}.`);
    }
  }

  const snapshots = path.join(dir, SNAPSHOTS);
  fs.mkdirSync(snapshots, { recursive: true });
  const keep = path.join(snapshots, ".gitkeep");
  if (!fs.existsSync(keep)) fs.writeFileSync(keep, "");

  const toolsDir = path.join(dir, "tools", "asset-versioning");
  fs.mkdirSync(toolsDir, { recursive: true });
  fs.copyFileSync(path.join(__dirname, "save.js"), path.join(toolsDir, "save.js"));
  fs.copyFileSync(path.join(__dirname, "Save Versions.bat"), path.join(dir, "Save Versions.bat"));
  console.log('  Added "Save Versions.bat" and tools/asset-versioning/.');

  const configPath = path.join(dir, "asset-versioning.json");
  if (!fs.existsSync(configPath)) {
    fs.writeFileSync(configPath, JSON.stringify({ snapshots: SNAPSHOTS }, null, 2) + "\n");
  }

  const attrPath = path.join(dir, ".gitattributes");
  const rule = `${SNAPSHOTS}/** text eol=lf`;
  const existing = fs.existsSync(attrPath) ? fs.readFileSync(attrPath, "utf8") : "";
  if (!existing.includes(rule)) {
    fs.appendFileSync(attrPath, (existing && !existing.endsWith("\n") ? "\n" : "") + rule + "\n");
  }

  const pkgPath = path.join(dir, "package.json");
  if (fs.existsSync(pkgPath)) {
    try {
      const pkg = JSON.parse(fs.readFileSync(pkgPath, "utf8"));
      pkg.scripts = pkg.scripts || {};
      if (!pkg.scripts["save-versions"]) {
        pkg.scripts["save-versions"] = "node tools/asset-versioning/save.js";
        fs.writeFileSync(pkgPath, JSON.stringify(pkg, null, 2) + "\n");
        console.log('  Added "npm run save-versions" to package.json.');
      }
    } catch {
      // package.json isn't plain JSON; the .bat file works without it.
    }
  }
}

async function main() {
  const argv = process.argv.slice(2);
  const pluginOnly = argv.includes("--plugin-only");
  const projectOnly = argv.includes("--project-only");
  let projectDir = argv.find((a) => !a.startsWith("--"));

  console.log("\n=====  Asset Versioning setup  =====");

  if (!projectOnly) installPlugin();
  if (pluginOnly) return;

  if (!projectDir) {
    console.log("\nWhich project should use it? Drag your project folder into this window, then press Enter.");
    console.log("(Leave empty to only install the plugin.)");
    projectDir = (await ask("> ")).replace(/^"|"$/g, "");
    if (!projectDir) return console.log("\nPlugin installed. Run Setup again later to connect a project.\n");
  }
  projectDir = path.resolve(projectDir.replace(/^"|"$/g, ""));
  if (!fs.existsSync(projectDir) || !fs.statSync(projectDir).isDirectory()) fail(`"${projectDir}" isn't a folder.`);

  connectProject(projectDir);

  console.log("\nAll set! Next, in Roblox Studio:");
  console.log("  1. Open your place and start Rojo as usual (\"Connect\").");
  console.log("  2. Open Plugins > Asset Versioning and follow the steps in the panel.");
  console.log("  3. After saving a snapshot and your place (Ctrl+S), double-click \"Save Versions.bat\".");
  console.log("");
}

main().catch((e) => fail(e.message));
