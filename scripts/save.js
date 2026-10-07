#!/usr/bin/env node
// Copies the snapshots saved in your place file into the project (via Rojo syncback) and
// records them in git. Run it from the project folder, or double-click "Save Versions.bat".
//
//   node save.js [--message "what changed"] [--push] [--yes] [--place file.rbxl] [--project dir]

const fs = require("fs");
const os = require("os");
const path = require("path");
const readline = require("readline");
const { spawnSync } = require("child_process");

function parseArgs(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--push" || a === "--yes") out[a.slice(2)] = true;
    else if (a === "--message" || a === "--place" || a === "--project") out[a.slice(2)] = argv[++i];
    else fail(`Unknown option ${a}`);
  }
  return out;
}

function fail(message) {
  console.error(`\nSomething needs your attention:\n  ${message}\n`);
  process.exit(1);
}

function run(cmd, cmdArgs, opts = {}) {
  const r = spawnSync(cmd, cmdArgs, { encoding: "utf8", ...opts });
  if (r.error && r.error.code === "ENOENT") return { missing: true, status: 1, stdout: "", stderr: "" };
  return r;
}

function ask(question) {
  if (!process.stdin.isTTY) return Promise.resolve("");
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  return new Promise((resolve) => rl.question(question, (a) => (rl.close(), resolve(a.trim()))));
}

function ago(ms) {
  const mins = Math.round((Date.now() - ms) / 60000);
  if (mins < 1) return "just now";
  if (mins < 60) return `${mins} minute${mins === 1 ? "" : "s"} ago`;
  const hours = Math.round(mins / 60);
  if (hours < 48) return `${hours} hour${hours === 1 ? "" : "s"} ago`;
  return `${Math.round(hours / 24)} days ago`;
}

function findPlace(root, requested, configured) {
  const wanted = requested || configured;
  if (wanted) {
    const p = path.resolve(root, wanted);
    if (!fs.existsSync(p)) fail(`The place file "${wanted}" doesn't exist.`);
    return p;
  }
  const candidates = fs
    .readdirSync(root)
    .filter((f) => /\.rbxlx?$/i.test(f))
    .map((f) => ({ file: path.join(root, f), time: fs.statSync(path.join(root, f)).mtimeMs }))
    .sort((a, b) => b.time - a.time);
  if (candidates.length === 0) {
    fail(
      "No place file (.rbxl) found in this folder.\n" +
        "  In Roblox Studio: File > Save to File As... and save it in the project folder, then run this again."
    );
  }
  return candidates[0].file;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const root = path.resolve(args.project || process.cwd());

  let config = {};
  const configPath = path.join(root, "asset-versioning.json");
  if (fs.existsSync(configPath)) {
    try {
      config = JSON.parse(fs.readFileSync(configPath, "utf8"));
    } catch {
      fail("asset-versioning.json is not valid JSON.");
    }
  }
  const snapshotsRel = config.snapshots || "asset-versions";
  const snapshotsDir = path.join(root, snapshotsRel);
  if (!fs.existsSync(snapshotsDir)) {
    fail(`The folder "${snapshotsRel}" doesn't exist. Run Setup.bat for this project first.`);
  }

  const place = findPlace(root, args.place, config.place);
  const saved = fs.statSync(place).mtimeMs;
  console.log(`\nPlace file: ${path.basename(place)} (saved ${ago(saved)})`);
  if (Date.now() - saved > 30 * 60000) {
    console.log("  Not what you expected? Go back to Studio and press Ctrl+S first.");
  }

  // Only the snapshot folder is mapped, so nothing else in the project can be touched.
  const tmpProject = path.join(os.tmpdir(), `asset-versioning-${process.pid}.project.json`);
  fs.writeFileSync(
    tmpProject,
    JSON.stringify({
      name: "AssetVersioning",
      tree: {
        $className: "DataModel",
        ServerStorage: { $className: "ServerStorage", AssetVersioning: { $path: snapshotsDir } },
      },
    })
  );

  try {
    const base = ["syncback", tmpProject, "--input", place, "--non-interactive", "--color", "never"];

    console.log("\n[1/3] Reading the snapshots from your place...");
    const preview = run("rojo", [...base, "--dry-run", "--list"]);
    if (preview.missing) {
      fail("Rojo isn't installed (or isn't on PATH). Ask a teammate, or install it from https://rojo.space");
    }
    if (preview.status !== 0) fail(`Rojo couldn't read the place file:\n${preview.stderr.trim()}`);
    const removing = preview.stdout.split("\n").filter((l) => l.startsWith("Removing ")).length;
    if (removing > 0 && !args.yes) {
      console.log(`\n  ${removing} saved file(s) are missing from your place and would be deleted from the project.`);
      console.log("  That's expected if you deleted things in Studio. If not, you may be using an old place file.");
      const answer = await ask("  Continue? (y/N) ");
      if (answer.toLowerCase() !== "y") fail("Cancelled. Nothing was changed.");
    }

    console.log("[2/3] Updating the project files...");
    const result = run("rojo", base);
    if (result.status !== 0) fail(`Rojo couldn't update the project:\n${result.stderr.trim()}`);
  } finally {
    fs.rmSync(tmpProject, { force: true });
  }

  console.log("[3/3] Saving to git...");
  const inRepo = run("git", ["rev-parse", "--show-toplevel"], { cwd: root });
  if (inRepo.missing || inRepo.status !== 0) {
    console.log("  This folder isn't a git repository, so there is nothing to record. Files are updated.");
    return;
  }

  run("git", ["add", "-A", "--", snapshotsRel], { cwd: root });
  const status = run("git", ["status", "--porcelain", "--", snapshotsRel], { cwd: root }).stdout
    .split("\n")
    .filter(Boolean);
  if (status.length === 0) {
    console.log("\nNothing changed since the last save. You're all up to date.\n");
    return;
  }

  const perPackage = {};
  for (const line of status) {
    const kind = line[0] === "A" ? "added" : line[0] === "D" ? "removed" : "changed";
    const file = line.slice(3).replace(/"/g, "").replace(/\\/g, "/");
    if (!file.endsWith(".luau")) continue;
    const parts = path.posix.relative(snapshotsRel, file).split("/");
    const pkg = parts.length > 1 ? parts[0] : "(other)";
    perPackage[pkg] = perPackage[pkg] || { added: 0, changed: 0, removed: 0 };
    perPackage[pkg][kind]++;
  }
  console.log("\nWhat's new:");
  for (const [pkg, c] of Object.entries(perPackage)) {
    const bits = ["added", "changed", "removed"].filter((k) => c[k]).map((k) => `${c[k]} ${k}`);
    console.log(`  ${pkg}: ${bits.join(", ")}`);
  }

  if (args.message) {
    const commit = run("git", ["commit", "-m", args.message, "--", snapshotsRel], { cwd: root });
    if (commit.status !== 0) fail(`git couldn't save the changes:\n${(commit.stderr || commit.stdout).trim()}`);
    console.log(`\nSaved with the note: "${args.message}"`);
    if (args.push) {
      const push = run("git", ["push"], { cwd: root });
      if (push.status !== 0) fail(`Saved locally, but sending to the team failed:\n${push.stderr.trim()}`);
      console.log("Sent to the team.");
    } else {
      console.log("Not sent to the team yet. Use your usual git tool to push.");
    }
  } else {
    console.log("\nReady to commit (the changes are staged). Add a note and commit with your usual git tool.");
  }
  console.log("");
}

main().catch((e) => fail(e.message));
