"use strict";
const assert = require("node:assert/strict");
const cp = require("node:child_process");
const crypto = require("node:crypto");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const root = path.resolve(__dirname, "..");
const pinned = "9f3bf64";
const expectedTree = "e010e50cb47fb3998c1705bd281064684923c6aa";
assert.equal(cp.execFileSync("git", ["rev-parse", `${pinned}^{tree}`], { cwd: root, encoding: "utf8" }).trim(), expectedTree);
const work = fs.mkdtempSync(path.join(os.tmpdir(), "schelm-child-v1-"));
try {
  const archive = cp.execFileSync("git", ["archive", "--format=tar", pinned], { cwd: root });
  const archiveHash = crypto.createHash("sha256").update(archive).digest("hex");
  assert.equal(archiveHash, "4ed9f3da49eba3fad841b677a41c6a9e44dccfef0fca298c91becf2b56af90b0");
  cp.execFileSync("tar", ["-xf", "-", "-C", work], { input: archive });
  for (const rel of ["fixtures/feasibility/src/BuilderMain.elm", "fixtures/feasibility/src/RunMain.elm", "fixtures/feasibility/src/DemandMain.elm"]) {
    assert.equal(fs.readFileSync(path.join(work, rel), "utf8"), fs.readFileSync(path.join(root, rel), "utf8"), `${rel} drifted from pinned 1.0 caller`);
  }
  console.log(JSON.stringify({ ok: true, pinned, tree: expectedTree, archiveSha256: archiveHash, callers: 3 }));
} finally { fs.rmSync(work, { recursive: true, force: true }); }
