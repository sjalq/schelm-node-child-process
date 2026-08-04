"use strict";

const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "..");
const provenance = JSON.parse(
  fs.readFileSync(path.join(root, "fixtures/frozen-v1-provenance.json"), "utf8"),
);

assert.equal(provenance.release, "1.0.0");
assert.match(provenance.commit, /^[0-9a-f]{40}$/);
assert.match(provenance.tree, /^[0-9a-f]{40}$/);
assert.match(provenance.gitArchiveSha256, /^[0-9a-f]{64}$/);

let callers = 0;
for (const [rel, expectedHash] of Object.entries(provenance.callers)) {
  const actualHash = crypto.createHash("sha256").update(fs.readFileSync(path.join(root, rel))).digest("hex");
  assert.equal(actualHash, expectedHash, `${rel} drifted from frozen 1.0 caller`);
  callers += 1;
}

console.log(
  JSON.stringify({
    ok: true,
    release: provenance.release,
    commit: provenance.commit,
    tree: provenance.tree,
    gitArchiveSha256: provenance.gitArchiveSha256,
    callers,
  }),
);
