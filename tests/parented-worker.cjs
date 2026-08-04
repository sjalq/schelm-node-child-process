"use strict";
const assert = require("node:assert/strict");
const { fork } = require("node:child_process");
const path = require("node:path");

const artifact = path.resolve(process.argv[2]);
const trace = [];
const child = fork(path.join(__dirname, "parented-runner.cjs"), [artifact], {
  stdio: ["ignore", "pipe", "inherit", "ipc"],
});

child.on("message", (message) => {
  if (!message || typeof message !== "object") return;
  if (String(message.type || "").startsWith("schelm-child.")) {
    trace.push(message.type);
    const replies = {
      "schelm-child.prepare": "schelm-child.prepared",
      "schelm-child.bind": "schelm-child.bound",
      "schelm-child.before-kill": "schelm-child.reaped",
      "schelm-child.unregister": "schelm-child.unregistered",
    };
    child.send({ type: replies[message.type], request: message.request, reservation: message.reservation, ok: true });
    return;
  }
  if (message.report) trace.push(message.report);
});

const timer = setTimeout(() => { child.kill("SIGKILL"); throw new Error("parented fixture timeout"); }, 15000);
child.on("exit", (code) => {
  clearTimeout(timer);
  assert.equal(code, 0);
  assert.deepEqual(trace.slice(0, 2), ["schelm-child.prepare", "schelm-child.bind"]);
  const started = trace.find((item) => item && typeof item === "object" && item.started);
  assert.ok(started && started.started === started.pgid, "package-observed fresh PGID");
  assert.ok(trace.indexOf("schelm-child.bind") < trace.indexOf(started));
  assert.ok(trace.includes("schelm-child.unregister"));
  assert.equal(trace.at(-1), "finished");
  console.log(JSON.stringify({ ok: true, trace }));
});
