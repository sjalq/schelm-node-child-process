"use strict";

const cp = require("node:child_process");
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "..");
const build = path.join(root, "build");
const manifest = JSON.parse(fs.readFileSync(path.join(root, "elm.json"), "utf8"));
const release = JSON.parse(fs.readFileSync(path.join(root, "release-manifest.json"), "utf8"));
const prefix = `schelm-node-child-process-${manifest.version}`;
const manifestPath = "release-manifest.json";
const sha256 = (data) => crypto.createHash("sha256").update(data).digest("hex");
const modeNumber = (mode) => (mode === "100755" ? 0o755 : 0o644);

if (release.schema !== 1 || release.version !== manifest.version) throw new Error("release manifest version drift");
if (!Array.isArray(release.files) || release.files.length === 0) throw new Error("empty release manifest");
const files = [...release.files].sort((a, b) => (a.path < b.path ? -1 : a.path > b.path ? 1 : 0));
if (files.some((item, index) => item.path !== release.files[index].path)) throw new Error("release manifest paths are not sorted");
if (files.some((item) => item.path === manifestPath || item.path.startsWith("build/") || /credential|secret|token/i.test(item.path))) {
  throw new Error("forbidden release manifest path");
}

for (const item of files) {
  if (!/^[0-9a-f]{64}$/.test(item.sha256) || !["100644", "100755"].includes(item.mode)) throw new Error(`invalid manifest fact ${item.path}`);
  const source = path.join(root, item.path);
  if (sha256(fs.readFileSync(source)) !== item.sha256) throw new Error(`content drift ${item.path}`);
  const actualMode = fs.statSync(source).mode & 0o777;
  if (actualMode !== modeNumber(item.mode)) throw new Error(`mode drift ${item.path}: ${actualMode.toString(8)} != ${item.mode.slice(-3)}`);
}

let sourceIdentity = { kind: "manifest", parent: release.sourceParent, payloadSha256: release.payloadSha256 };
try {
  const commit = cp.execFileSync("git", ["rev-parse", "HEAD"], { cwd: root, encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).trim();
  const parent = cp.execFileSync("git", ["rev-parse", "HEAD^"], { cwd: root, encoding: "utf8" }).trim();
  const status = cp.execFileSync("git", ["status", "--porcelain"], { cwd: root, encoding: "utf8" }).trim();
  if (parent !== release.sourceParent && !(commit === release.sourceParent && status)) throw new Error(`release parent drift ${parent}`);
  if (!status) {
    const treeRows = cp.execFileSync("git", ["ls-tree", "-r", "HEAD"], { cwd: root, encoding: "utf8" }).trim().split("\n");
    const tracked = treeRows.map((row) => {
      const match = /^(100644|100755) blob [0-9a-f]+\t(.+)$/.exec(row);
      if (!match) throw new Error(`unsupported tree entry ${row}`);
      return { mode: match[1], path: match[2] };
    }).filter((item) => !item.path.startsWith("build/") && item.path !== manifestPath);
    if (JSON.stringify(tracked) !== JSON.stringify(files.map(({ mode, path: rel }) => ({ mode, path: rel })))) throw new Error("Git tree path/mode facts drift from release manifest");
    sourceIdentity = { kind: "git", commit, parent, tree: cp.execFileSync("git", ["rev-parse", "HEAD^{tree}"], { cwd: root, encoding: "utf8" }).trim() };
  } else {
    sourceIdentity = { kind: "working-tree", parent: release.sourceParent, payloadSha256: release.payloadSha256 };
  }
} catch (error) {
  if (!String(error.message).includes("not a git repository") && !String(error.message).includes("release parent drift") && !String(error.message).includes("Git tree")) {
    // An extracted release intentionally has no repository. Other Git failures are surfaced below only when .git exists.
    if (fs.existsSync(path.join(root, ".git"))) throw error;
  } else if (fs.existsSync(path.join(root, ".git"))) throw error;
}

const payloadFact = sha256(Buffer.from(files.map((item) => `${item.mode} ${item.sha256} ${item.path}\n`).join("")));
if (payloadFact !== release.payloadSha256) throw new Error(`payload fact drift ${payloadFact}`);

fs.mkdirSync(build, { recursive: true });
const stage = fs.mkdtempSync(path.join(build, "archive-stage-"));
const top = path.join(stage, prefix);
fs.mkdirSync(top, { mode: 0o755 });
try {
  for (const item of [...files, { path: manifestPath, mode: "100644" }]) {
    const source = path.join(root, item.path);
    const destination = path.join(top, item.path);
    fs.mkdirSync(path.dirname(destination), { recursive: true, mode: 0o755 });
    fs.copyFileSync(source, destination);
    fs.chmodSync(destination, modeNumber(item.mode));
    fs.utimesSync(destination, 0, 0);
  }
  const out = path.join(build, `${prefix}.tar.gz`);
  cp.execFileSync("tar", ["--sort=name", "--mtime=@0", "--owner=0", "--group=0", "--numeric-owner", "--mode=u+rwX,go+rX,go-w", "-czf", out, "-C", stage, prefix]);
  const hash = sha256(fs.readFileSync(out));
  fs.writeFileSync(`${out}.sha256`, `${hash}  ${path.basename(out)}\n`);
  console.log(JSON.stringify({ ok: true, sourceIdentity, files: files.length + 1, archive: path.relative(root, out), sha256: hash }));
} finally {
  fs.rmSync(stage, { recursive: true, force: true });
}
