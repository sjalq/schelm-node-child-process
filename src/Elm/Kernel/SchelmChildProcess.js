/*
import Elm.Kernel.List exposing (toArray)
import Elm.Kernel.Scheduler exposing (binding, succeed, fail)
import Elm.Kernel.Utils exposing (Tuple0, Tuple2)
import Bytes exposing (Bytes)
import Maybe exposing (Maybe)
import Schelm.Node.ChildProcess.Feasibility as Feasibility exposing (Process, Exit)
*/
function _SchelmChildProcess_error(error) { return String(error && (error.code || error.message) || error); }
function _SchelmChildProcess_bytes(chunk) { return new DataView(chunk.buffer, chunk.byteOffset, chunk.byteLength); }
function _SchelmChildProcess_reader(stream) {
  var chunks = [], waiter = null, ended = false, failed = null;
  stream.pause();
  stream.on("data", function(chunk) {
    stream.pause();
    var value = $elm$core$Maybe$Just(_SchelmChildProcess_bytes(chunk));
    if (waiter) { var callback = waiter; waiter = null; callback(_Scheduler_succeed(value)); }
    else chunks.push(value);
  });
  stream.once("end", function() { ended = true; if (waiter) { var callback = waiter; waiter = null; callback(_Scheduler_succeed($elm$core$Maybe$Nothing)); } });
  stream.once("error", function(error) { failed = _SchelmChildProcess_error(error); if (waiter) { var callback = waiter; waiter = null; callback(_Scheduler_fail(failed)); } });
  return function() { return _Scheduler_binding(function(callback) {
    if (chunks.length) { callback(_Scheduler_succeed(chunks.shift())); return; }
    if (failed) { callback(_Scheduler_fail(failed)); return; }
    if (ended) { callback(_Scheduler_succeed($elm$core$Maybe$Nothing)); return; }
    if (waiter) { callback(_Scheduler_fail("concurrent read")); return; }
    waiter = callback; stream.resume();
    return function() { if (waiter === callback) { waiter = null; stream.pause(); } };
  }); };
}
var _SchelmChildProcess_spawn = F2(function(program, argv) {
  return _Scheduler_binding(function(callback) {
    var child, settled = false;
    function settle(task) { if (!settled) { settled = true; callback(task); } }
    try {
      child = require("node:child_process").spawn(program, _List_toArray(argv), { stdio: ["ignore", "pipe", "pipe"], detached: process.platform !== "win32" });
      child.once("spawn", function() {
        child.__schelmStdout = _SchelmChildProcess_reader(child.stdout);
        child.__schelmStderr = _SchelmChildProcess_reader(child.stderr);
        child.__schelmExit = null; child.__schelmWaiters = [];
        child.once("close", function(code, signal) { var result = _Utils_Tuple2(code == null ? -1 : code, signal == null ? "" : signal); child.__schelmExit = result; child.__schelmWaiters.splice(0).forEach(function(waiter) { waiter(_Scheduler_succeed(result)); }); });
        settle(_Scheduler_succeed(child));
      });
      child.once("error", function(error) { settle(_Scheduler_fail(_SchelmChildProcess_error(error))); });
    } catch (error) { settle(_Scheduler_fail(_SchelmChildProcess_error(error))); }
    return function() { if (!settled && child) { try { child.kill("SIGKILL"); } catch (_) {} } };
  });
});
var _SchelmChildProcess_readStdout = function(child) { return child.__schelmStdout(); };
var _SchelmChildProcess_readStderr = function(child) { return child.__schelmStderr(); };
var _SchelmChildProcess_wait = function(child) { return _Scheduler_binding(function(callback) { if (child.__schelmExit) callback(_Scheduler_succeed(child.__schelmExit)); else { child.__schelmWaiters.push(callback); return function() { var i=child.__schelmWaiters.indexOf(callback); if(i>=0)child.__schelmWaiters.splice(i,1); }; } }); };
var _SchelmChildProcess_terminate = function(child) { return _Scheduler_binding(function(callback) { try { if (process.platform !== "win32") process.kill(-child.pid,"SIGTERM"); else child.kill("SIGTERM"); } catch (_) {} callback(_Scheduler_succeed(_Utils_Tuple0)); }); };
