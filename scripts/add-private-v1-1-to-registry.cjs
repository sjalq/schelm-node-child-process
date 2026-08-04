"use strict";

const fs = require("node:fs");

const registryPath = process.argv[2];
const author = process.argv[3];
const project = process.argv[4];
if (!registryPath || !author || !project || author.length > 255 || project.length > 255) {
  throw new Error("usage: add-private-fixture-to-registry.cjs REGISTRY AUTHOR PROJECT");
}

let registry = fs.readFileSync(registryPath);
let position = 16;
const count = Number(registry.readBigUInt64BE(8));
const entries = [];
for (let index = 0; index < count; index += 1) {
  const start = position;
  const authorLength = registry[position++];
  const entryAuthor = registry.subarray(position, position + authorLength).toString();
  position += authorLength;
  const projectLength = registry[position++];
  const entryProject = registry.subarray(position, position + projectLength).toString();
  position += projectLength + 3;
  const previousVersions = Number(registry.readBigUInt64BE(position));
  position += 8 + 3 * previousVersions;
  entries.push({ key: `${entryAuthor}/${entryProject}`, start });
}

const key = `${author}/${project}`;
if (entries.some((entry) => entry.key === key)) process.exit(0);
const following = entries.find((entry) => entry.key > key);
const insertion = following ? following.start : registry.length;
const entry = Buffer.concat([
  Buffer.from([author.length]),
  Buffer.from(author),
  Buffer.from([project.length]),
  Buffer.from(project),
  Buffer.from([1, 1, 1]),
  Buffer.alloc(8),
]);
registry = Buffer.concat([registry.subarray(0, insertion), entry, registry.subarray(insertion)]);
registry.writeBigUInt64BE(registry.readBigUInt64BE(0) + 1n, 0);
registry.writeBigUInt64BE(BigInt(count + 1), 8);
fs.writeFileSync(registryPath, registry);
