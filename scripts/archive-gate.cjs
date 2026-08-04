"use strict";

const cp = require("node:child_process");
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "..");
const build = path.join(root, "build");
const manifest = JSON.parse(fs.readFileSync(path.join(root, "elm.json"), "utf8"));
const version = manifest.version;
const prefix = `schelm-node-child-process-${version}`;
const commit = process.env.SCHELM_ARCHIVE_COMMIT || "HEAD";
const files = cp
  .execFileSync("git", ["ls-tree", "-r", "--name-only", commit], { cwd: root, encoding: "utf8" })
  .trim()
  .split("\n")
  .filter((rel) => rel && !rel.startsWith("build/"))
  .sort();

for (const rel of files) {
  if (/credential|secret|token/i.test(rel)) throw new Error(`forbidden archive path ${rel}`);
}

fs.mkdirSync(build, { recursive: true });
const stage = fs.mkdtempSync(path.join(build, "archive-stage-"));
const top = path.join(stage, prefix);
fs.mkdirSync(top);

try {
  for (const rel of files) {
    const contents = cp.execFileSync("git", ["show", `${commit}:${rel}`], { cwd: root });
    const destination = path.join(top, rel);
    fs.mkdirSync(path.dirname(destination), { recursive: true });
    fs.writeFileSync(destination, contents);
    fs.utimesSync(destination, 0, 0);
  }

  const out = path.join(build, `${prefix}.tar.gz`);
  cp.execFileSync("tar", [
    "--sort=name",
    "--mtime=@0",
    "--owner=0",
    "--group=0",
    "--numeric-owner",
    "-czf",
    out,
    "-C",
    stage,
    prefix,
  ]);
  const hash = crypto.createHash("sha256").update(fs.readFileSync(out)).digest("hex");
  fs.writeFileSync(`${out}.sha256`, `${hash}  ${path.basename(out)}\n`);
  console.log(
    JSON.stringify({
      ok: true,
      commit: cp.execFileSync("git", ["rev-parse", commit], { cwd: root, encoding: "utf8" }).trim(),
      files: files.length,
      archive: path.relative(root, out),
      sha256: hash,
    }),
  );
} finally {
  fs.rmSync(stage, { recursive: true, force: true });
}
