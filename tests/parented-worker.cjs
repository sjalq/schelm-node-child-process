"use strict";
const assert = require("node:assert/strict");
const { fork } = require("node:child_process");
const path = require("node:path");

const artifact = path.resolve(process.argv[2]);
const runs = Number(process.argv[3] || 1);
const mode = process.argv[4] || "ack";

function one(index) {
  return new Promise((resolve, reject) => {
    const trace = [];
    let settled = false;
    const child = fork(path.join(__dirname, "parented-runner.cjs"), [artifact], {
      stdio: ["ignore", "pipe", "inherit", "ipc"],
    });
    const timer = setTimeout(() => finish(new Error(`parented fixture timeout ${index}`)), 10000);
    function finish(error) {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      if (child.connected) child.disconnect();
      if (error) reject(error); else resolve(trace);
    }
    child.on("error", finish);
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
        if (mode === "reap-timeout" && message.type === "schelm-child.before-kill") return;
        child.send({ type: replies[message.type], request: message.request, reservation: message.reservation, ok: true });
        return;
      }
      if (message.report) trace.push(message.report);
    });
    child.on("exit", (code, signal) => {
      try {
        assert.equal(signal, null);
        assert.equal(code, 0);
        assert.deepEqual(trace.slice(0, 2), ["schelm-child.prepare", "schelm-child.bind"]);
        const started = trace.find((item) => item && typeof item === "object" && item.started);
        const finished = trace.find((item) => item && typeof item === "object" && item.finished);
        assert.ok(started && started.started === started.pgid, "package-observed fresh PGID");
        assert.ok(finished, "one terminal result");
        assert.ok(trace.indexOf("schelm-child.bind") < trace.indexOf(started));
        assert.ok(trace.includes("schelm-child.before-kill"));
        assert.ok(trace.includes("schelm-child.unregister"));
        assert.equal(finished.finished, mode === "reap-timeout" ? "timeout" : "ack");
        assert.equal(trace.at(-1), finished);
        finish();
      } catch (error) { finish(error); }
    });
  });
}

(async () => {
  for (let i = 0; i < runs; i += 1) await one(i);
  console.log(JSON.stringify({ ok: true, artifact: path.basename(artifact), runs, mode }));
})().catch((error) => { console.error(error); process.exit(1); });
