# 01 — `schelm-node-child-process` v1 design

Status: first-turn design for independent hostile review. No production implementation is authorized by this artifact.

## 1. Goal and boundary

Provide a coherent Node child-process package for trusted Elm programs:

- executable plus literal argv;
- inherited, merged, or replaced environment;
- inherited or explicit cwd;
- closed/bytes/streaming stdin;
- inherited, ignored, captured, or incrementally read stdout/stderr;
- an opaque live process handle;
- nonzero exit as ordinary terminal data;
- constructive spawn failure as `Task` error;
- Unix process-group ownership and TERM → grace → KILL supervision;
- bounded capture and pull-driven stream backpressure;
- one terminal observation, repeatable `wait`, idempotent cancellation.

The package owns reusable process mechanics only. It does **not** own command
allowlisting, shell policy, workspace policy, timeout defaults, transcript
formatting, tool-result schemas, orchestration limits, or daemon/session policy.
Those remain ordinary harness Elm.

V1 is direct-exec only. It does not expose `shell : Bool` or a command string.
A caller that deliberately wants a shell must execute the shell explicitly with
literal argv. This avoids a second quoting authority and makes argv behavior
portable enough to document.

## 2. Compiler-driven API shape

`00-feasibility.md` proves private effect modules are rejected by the pinned
compiler. Therefore v1 is Task/pull based rather than `Cmd`/push based.

Proposed module:

```elm
module Schelm.Node.ChildProcess exposing
    ( Permission
    , initialize
    , Process
    , Pid
    , SpawnOptions
    , defaultSpawnOptions
    , WorkingDirectory(..)
    , Environment(..)
    , Stdin(..)
    , Output(..)
    , CaptureLimit
    , captureUpTo
    , GracePeriod
    , graceMilliseconds
    , SpawnError(..)
    , StreamError(..)
    , WriteError(..)
    , Termination(..)
    , Exit
    , Captured
    , spawn
    , readStdout
    , readStderr
    , writeStdin
    , closeStdin
    , wait
    , terminate
    , kill
    , run
    )
```

Core types:

```elm
type Permission
    = Permission


type Process
    = Process


type Pid
    = Pid Int


type WorkingDirectory
    = InheritWorkingDirectory
    | SetWorkingDirectory String


type Environment
    = InheritEnvironment
    | MergeEnvironment (Dict String String)
    | ReplaceEnvironment (Dict String String)


type Stdin
    = StdinClosed
    | StdinBytes Bytes
    | StdinPipe
    | InheritStdin


type Output
    = InheritOutput
    | IgnoreOutput
    | CaptureOutput CaptureLimit
    | PipeOutput


type CaptureLimit
    = CaptureLimit Int


type GracePeriod
    = GracePeriod Int


type alias SpawnOptions =
    { workingDirectory : WorkingDirectory
    , environment : Environment
    , stdin : Stdin
    , stdout : Output
    , stderr : Output
    , ownership : Ownership
    }


type Ownership
    = OwnedProcessTree


type SpawnError
    = ExecutableNotFound
    | PermissionDenied
    | InvalidWorkingDirectory
    | InvalidEnvironment
    | ResourceExhausted
    | UnsupportedPlatform String
    | UnknownSpawnFailure { code : String, operation : String }


type StreamError
    = StreamNotPiped
    | ConcurrentRead
    | StreamFailed { code : String, operation : String }


type WriteError
    = StdinNotPiped
    | StdinClosedAlready
    | ConcurrentWrite
    | BrokenPipe
    | StdinFailed { code : String, operation : String }


type Termination
    = Exited Int
    | Signaled String


type alias Exit =
    { pid : Pid
    , termination : Termination
    }


type alias Captured =
    { exit : Exit
    , stdout : Bytes
    , stderr : Bytes
    }
```

Signatures:

```elm
initialize : Task Never Permission

spawn :
    Permission
    -> String
    -> List String
    -> SpawnOptions
    -> Task SpawnError Process

readStdout : Process -> Task StreamError (Maybe Bytes)
readStderr : Process -> Task StreamError (Maybe Bytes)
writeStdin : Bytes -> Process -> Task WriteError ()
closeStdin : Process -> Task WriteError ()
wait : Process -> Task Never Exit
terminate : GracePeriod -> Process -> Task Never Exit
kill : Process -> Task Never Exit

run :
    Permission
    -> String
    -> List String
    -> SpawnOptions
    -> Task SpawnError Captured
```

`defaultSpawnOptions` is boring and deadlock-resistant:

```elm
{ workingDirectory = InheritWorkingDirectory
, environment = InheritEnvironment
, stdin = StdinClosed
, stdout = CaptureOutput (captureUpTo (1024 * 1024))
, stderr = CaptureOutput (captureUpTo (1024 * 1024))
, ownership = OwnedProcessTree
}
```

Construction rules clamp neither negatives nor giant values silently:

```elm
captureUpTo : Int -> Maybe CaptureLimit
graceMilliseconds : Int -> Maybe GracePeriod
```

Both accept `0 <= n <= maxSafeInt`; zero capture means overflow on the first
non-empty byte. The harness chooses its own concrete limits and grace.

### API honesty about handles

Elm cannot linearly consume `Process`; callers can retain and reuse it. MISI is
therefore enforced by an opaque handle plus one kernel registry/state machine:
operations after terminal become typed cached results, EOF, or no-ops. The
public API does not claim compile-time linearity it cannot provide.

`Pid` is observational only. No API accepts a `Pid` for signaling, so a stale or
foreign PID cannot confer authority. Only an opaque package-created `Process`
can control a child.

## 3. Mode matrix and invalid combinations

A process has one stdin mode and independent stdout/stderr modes.

| Mode | stdin operation | read operation | `run` result |
|---|---|---|---|
| inherited | unavailable | unavailable | empty bytes for that stream |
| ignored/closed | unavailable | unavailable | empty bytes |
| bytes/capture | package owns draining | unavailable to caller | captured bytes |
| pipe | caller owns writes/reads | available, one pending op | `run` rejects |

`run` accepts only modes it can fully own:

- stdin: `StdinClosed`, `StdinBytes`, or `InheritStdin`;
- stdout/stderr: `CaptureOutput`, `IgnoreOutput`, or `InheritOutput`;
- any `PipeOutput`/`StdinPipe` produces `UnsupportedRunMode` before spawning.

That error should ideally be made impossible by separate `RunOptions` and
`SpawnOptions` before implementation. Hostile review must choose between:

1. two option records with shared helper types (stronger MISI); or
2. one ergonomic record plus `RunConfigurationError` (less type-safe).

**Preferred revision:** introduce `RunOptions` separately. V1 should not spawn
and then discover that the caller selected an unowned pipe.

Output chunks are raw `Bytes`. Text decoding, line splitting, JSONL framing,
and SSE parsing are ordinary Elm concerns and must preserve decoder carry.

## 4. Resource ownership and lifecycle

### 4.1 Process state

```text
Absent
  └─ spawn ─> Spawning

Spawning
  ├─ synchronous throw / Node error before spawn ─> SpawnFailed ─> Absent
  ├─ Node spawn ─> Live
  └─ Task abandoned ─> abort spawn; kill if child appeared ─> Absent

Live
  ├─ read/write/wait registration ─> Live
  ├─ terminate ─> Terminating(TERM, timer)
  ├─ kill ─> Terminating(KILL, no timer)
  └─ terminal events ─> Settling

Terminating(TERM)
  ├─ close ─> Settling
  └─ grace timer ─> send KILL once ─> Terminating(KILL)

Terminating(KILL)
  └─ close/error fallback ─> Settling

Settling
  ├─ close owned stdin
  ├─ mark streams ended/failure
  ├─ clear grace timer
  ├─ cache Exit
  ├─ resolve all wait/terminate/kill waiters once
  └─ remove OS child reference and timers ─> Exited(cache)

Exited(cache)
  ├─ wait/terminate/kill ─> same cached Exit
  ├─ read capture/pipe remainder ─> chunks then EOF
  └─ write/close stdin ─> typed closed error/no-op as documented
```

There is exactly one terminal claim function in kernel JS. Node `error`,
`exit`, `close`, timer, stream failures, Task abandonment, and repeated control
calls all race through it. Callback queued or terminal cached means later
terminal candidates are ignored.

`wait` uses Node `close` as the normal completion event because it follows stdio
closure. A defensive `error` after successful spawn cannot strand waiters: it
records stream/process failure and enters the same settling path if no `close`
can follow.

### 4.2 Stream state per pipe

```text
Unavailable
Capturing { chunks, bytes }
ReadableIdle { queuedAtMostOneChunkOrNodePaused }
ReadPending { callback }
Ended
Failed StreamError
```

Rules:

- one pending `readStdout` and one pending `readStderr` per process;
- a second read on the same stream fails `ConcurrentRead` immediately;
- the kernel pauses a Node readable whenever no Elm read is pending;
- it resumes only for a pending read, then pauses after one delivered chunk;
- cancellation of the Elm Task removes only that waiter and pauses the stream;
- stream end resolves a pending read with `Nothing`; later reads return
  `Nothing`;
- no cumulative history is traversed per chunk.

A one-chunk kernel queue is allowed solely for the race between Node emission
and `pause`; its byte size is bounded by `maxChunkBytes` chosen internally. If
Node supplies a larger chunk, production code slices without copying more than
necessary or fails closed; hostile review must settle the exact rule.

### 4.3 Stdin state

```text
Unavailable | WritableIdle | WritePending | Closing | Closed | Failed
```

`writeStdin` resolves only when Node accepted the bytes: immediately if
`write()` returns true, otherwise after `drain`. Exactly one write may be
pending. This bounds retained caller bytes and makes backpressure explicit.
Task abandonment removes listeners but does not falsely report success.
`closeStdin` waits for `finish`; after terminal it is idempotent success only if
already closed, otherwise a typed closed error. Hostile review should choose one
stable rule and test it; silently dropping bytes is forbidden.

## 5. Capture, backpressure, and bounds

### Captured output

The kernel drains stdout and stderr concurrently from spawn until both close.
Each capture tracks only:

```text
{ chunks : Array/JS array of copied byte chunks
, keptBytes : Int
, limit : Int
}
```

Per chunk cost is O(new chunk). Final concatenation is O(total retained bytes)
once. No `acc ++ [ chunk ]`, repeated concatenation, or per-chunk full-buffer
copy is permitted.

Overflow policy is **fail and terminate**, not truncate. Truncation can produce
a syntactically plausible but semantically false tool result. On first byte
beyond either stream's cap:

1. claim `OutputLimitExceeded { stream, limit }` for `run`;
2. start owned TERM → grace → KILL cleanup;
3. continue draining/discarding until close as needed to avoid deadlock;
4. release captured chunks before resolving the outer failure.

This requires `run` to have an execution error distinct from `SpawnError`.
Therefore the earlier signature is revised to:

```elm
type RunError
    = RunSpawnFailed SpawnError
    | OutputLimitExceeded { stream : OutputStream, limit : Int }
    | InputFailed WriteError
    | RunStreamFailed StreamError

run : ... -> Task RunError Captured
```

Nonzero exit remains `Ok Captured`; only inability to execute/transport within
contract is `Err`.

### Streamed output

Pull reads are the acknowledgement. At chunk 10,000, cost is O(chunk 10,000),
state is O(one queued chunk + one waiter), and no prior chunks are walked.

### Input bytes

`StdinBytes` has no package-side cap because the caller already owns the
`Bytes`; `run` writes it with Node backpressure, then closes stdin. Harness
policy may cap request/input size before constructing it.

## 6. Process-tree ownership and cancellation ladder

### Unix

Every v1 child is owned. Spawn uses `detached : true` to create a new process
group. This is **not** a user-facing detached/fire-and-forget mode. The package
retains the handle and signals `-pid` so shells, pipelines, and grandchildren
receive cancellation.

`terminate grace process`:

1. atomically mark termination requested;
2. send `SIGTERM` to the negative process-group id;
3. arm one grace timer;
4. if terminal wins, clear timer and return cached `Exit`;
5. if timer wins, send `SIGKILL` to the group once;
6. wait for terminal settlement and return it.

`kill` starts at step 5. Repeated terminate/kill calls join the same terminal
wait; KILL dominates TERM. No call manufactures an exit result before Node
observes termination.

The package registry owns every live child it created. On Node process shutdown
hooks, a best-effort synchronous KILL of all live Unix groups is allowed as a
last-resort mechanism. The primary harness path must still explicitly cancel;
shutdown hooks are not product policy.

### Harness cancellation law

The existing Orchestrate law is preserved, not weakened:

```text
outer parent: SIGTERM worker → grace → reap worker-owned child groups → SIGKILL worker
worker/package: on SIGTERM or stdin EOF → terminate all package-owned children
               → wait package grace → KILL survivors → exit
normal completion: no live package-owned children remain
```

A child-process package cannot solve a worker whose JS event loop is blocked;
the parent must retain the existing last rung that discovers/reaps worker-owned
process groups before killing the worker. Integration must not delete
`killWorkerBashGroups` until differential evidence proves an equally strong
generic registry bridge.

The first vertical slice should replace one `tools-impl.js` Bash spawn path, not
the parent watchdog. Elm chooses policy/timeouts; kernel JS executes signals,
timers, and child-process facts.

### Windows honesty

Node does not provide Unix process groups or signals on Windows:

- negative PID signaling is unavailable;
- `SIGTERM` is not a faithful graceful tree signal;
- `child.kill()` does not guarantee descendant termination;
- detached semantics differ.

Broad v1 has two honest choices:

1. Unix-only owned-tree spawning, returning
   `UnsupportedPlatform "owned process-tree supervision"` on Windows; or
2. a reviewed Windows kernel verb using Job Objects (native dependency) with
   different graceful semantics.

**V1 decision: Unix-only supervision.** Compilation may work on Windows, but
`spawn` fails before creating a child. Do not claim Windows support by invoking
`taskkill`; that is another subprocess, has localization/availability races,
and still does not provide the same TERM grace contract. A later v2 can add Job
Objects as an explicit platform capability.

Supported matrix for v1 runtime evidence: Linux x64/arm64 and macOS x64/arm64
where CI is available. FreeBSD/other Unix are unclaimed until tested.

## 7. Spawn details

- `program` is passed directly to `child_process.spawn`; argv is converted from
  Elm list once. No joining, interpolation, globbing, or shell.
- cwd is inherited or supplied literally. Node validation failures map to
  constructive `SpawnError`.
- environment merge occurs once at spawn. JS converts Elm `Dict` by a single
  fold into a null-prototype object. Replacement does not secretly preserve
  `PATH`; if callers need it, they supply it.
- environment keys and values must not contain NUL. Empty key and platform-
  invalid keys fail before spawning. On Windows this is moot in v1.
- `stdin/stdout/stderr` map to exact Node `stdio` entries; no late mode changes.
- successful `spawn` resolves only after Node's `spawn` event. Pre-spawn
  synchronous throws and `error` events are failures. `ENOENT`, `EACCES`, cwd,
  and resource failures map from allowlisted codes; unknown details are bounded
  and never include environment values.
- PID is captured only after successful spawn and is never accepted back as
  authority.

## 8. MISI, MITI, and DRY decisions

### MISI

- no ambient spawn function without `Permission`;
- no signal-by-PID API;
- no shell bool/string mode;
- `Termination` distinguishes exit code from signal;
- nonzero exit cannot inhabit `SpawnError`;
- each stdio mode is explicit;
- `CaptureLimit` and `GracePeriod` require smart constructors;
- unsupported Windows ownership fails before spawn;
- one kernel terminal claimant; terminal result is cached;
- process control is idempotent by joining terminal state;
- separate `RunOptions` should make pipe modes in `run` unconstructable.

`initialize : Task Never Permission` is cooperative authority, as in Gren: it
prevents accidental effect use through API threading, not malicious code in the
same Elm application from calling `initialize`. Documentation must say so.

### MITI

- all JS exceptions are caught at each Node boundary and mapped to typed errors;
- listeners/timers/waiters are owned by one process entry and removed on settle;
- abandoned Tasks unregister callbacks and do not kill a live process unless
  that Task owns the operation (`spawn` before handoff or whole `run`);
- `run` abandonment owns and terminates its child; abandonment of `wait` or one
  read does not;
- capture overflow terminates and drains/discards;
- shutdown cleanup is idempotent;
- registry entry is absent after terminal cleanup, while the opaque handle keeps
  only immutable terminal/EOF facts needed for repeatable operations.

### DRY authorities

| Rule | Single authority |
|---|---|
| argv/cwd/env/stdio conversion | package Elm + minimal kernel encoder boundary |
| lifecycle and one-terminal claim | package kernel process entry |
| capture/stream byte accounting | package kernel stream state |
| TERM/grace/KILL mechanics | package process controller |
| command/tool allowlist | harness `ToolPolicy.elm` |
| timeout/grace/output defaults | harness Elm catalog/tool policy |
| orchestration ownership | harness `Exec.elm` / worker owner registry |
| provider/session/journal behavior | harness existing owners |

During migration the old JS and package path coexist only behind differential
tests. After cutover, remove the old spawn/capture/signal authority rather than
keeping two implementations.

## 9. Exact Gren comparison

Reference inspected: `gren-lang/node` ChildProcess 6.1.3 and
`gren-lang/core` Stream 6.0.0.

| Concern | Gren 6.1.3 | Proposed Schelm v1 |
|---|---|---|
| permission | `initialize : Task Permission` | same cooperative capability idea |
| run | buffered `Task FailedRun SuccessfulRun` | bounded `Task RunError Captured` |
| nonzero | `ProgramError` failure | **terminal data**, matching harness law |
| spawn | effect-manager `Cmd`, push `onExit` | Task returns opaque handle; pull reads/wait |
| streams | `Writable/Readable Bytes` Web Streams | package-specific blocking Tasks |
| connection | Integrated/External/Ignored/Detached | explicit stdin/stdout/stderr modes; no fire-and-forget |
| env/cwd | inherit/merge/replace and inherit/set | same broad options |
| shell | no/default/custom | direct executable only; explicit shell argv if desired |
| timeout | run duration option | caller/harness races timer then calls terminate |
| capture bound | maximum bytes | per-stream exact caps, overflow terminates |
| cancellation | scheduler cancel calls `kill()`; spawned `Id` | owned process group, TERM → grace → KILL, cached terminal |
| process tree | not guaranteed | explicit Unix owned-tree contract |
| Windows | partial Node semantics | fail closed for owned-tree v1 |

We intentionally do not copy Gren's weaknesses visible in the inspected kernel:
joining program/arguments into one command string, collapsing spawn failures to
an exit sentinel, treating nonzero exit as Task failure, and relying on
immediate-child `kill()` for supervision.

We also cannot copy Gren's effect manager/Stream ergonomics under the present
Elm compiler. The pull API is an honest consequence, not an aesthetic choice.

## 10. Complexity and resource budgets

| Operation | Time | Retained state |
|---|---:|---:|
| spawn conversion | O(argv + env entries) once | O(argv + env) until Node copies |
| streamed read | O(new chunk) | O(one pending/queued chunk) |
| stdin write | O(new bytes) | O(one pending write) |
| capture chunk | O(new chunk) | O(total captured ≤ cap) |
| capture finish | O(total captured) once | final bytes only |
| wait/control | O(1) | O(number of current waiters) |
| terminal cleanup | O(current listeners + waiters) | terminal cache |
| cancel all owned children | O(live children), cold shutdown path | O(live children) registry |

At process 1,000, no operation scans prior processes. At stream chunk 10,000,
no operation scans prior chunks. Registry lookup is by opaque entry/ID, not by
walking all children. A 1,000-waiter fanout is technically O(waiters) at terminal
and should be bounded internally or documented; hostile review should decide a
small maximum (preferred) because unbounded repeated `wait` calls retain
callbacks.

Default package mechanisms should cap:

- one pending read per stream;
- one pending stdin write;
- finite capture per stream;
- finite grace period supplied by smart constructor;
- bounded error strings/codes;
- finite terminal waiter count (proposal: 64 per process).

The package does not impose a global process-count policy; harness orchestration
meters remain the owner of total/concurrent subprocess policy.

## 11. Property/model test design

The later `06-property-test-plan.md` will make exact generators, but this design
requires a pure reference model now.

### Model state

```elm
type Phase
    = Spawning
    | Live
    | Terminating TerminationStage
    | Exited Exit
    | SpawnFailed SpawnError


type StreamModel
    = Unavailable
    | Idle
    | ReadPending ReaderId
    | Ended
    | Failed StreamError


type StdinModel
    = NoStdin
    | Writable
    | WritePending WriterId Int
    | Closing
    | Closed
    | WriteFailed WriteError


type alias Model =
    { phase : Phase
    , stdout : StreamModel
    , stderr : StreamModel
    , stdin : StdinModel
    , capturedOut : Int
    , capturedErr : Int
    , terminalDeliveries : Int
    , termSent : Bool
    , killSent : Bool
    , timerOwned : Bool
    , registered : Bool
    }
```

Generated actions include spawn success/failure, stdout/stderr chunks and EOF in
all interleavings, reads and abandoned reads, writes/drain/finish/error,
`exit`/`close`/`error` permutations, repeated wait/terminate/kill, grace firing,
capture overflow on exact boundaries, and outer `run` abandonment.

### Required properties

1. terminal delivery count is at most one;
2. every accepted waiter resolves at most once;
3. once terminal, all later waits return structurally equal `Exit`;
4. nonzero exit is never `SpawnError`/`RunError`;
5. spawn failure never yields a `Process` or registry entry;
6. KILL is sent at most once and only after explicit kill or grace expiry;
7. TERM is sent at most once; KILL dominates later TERM requests;
8. terminal settlement owns no timer/listener/pending callback;
9. same-stream concurrent read/write fails without replacing the first waiter;
10. task abandonment removes exactly its waiter and cannot resolve it later;
11. streamed retained bytes never exceed one bounded chunk;
12. capture retained bytes never exceed the cap;
13. overflow at `limit + 1` always initiates cleanup; exactly `limit` succeeds;
14. stdout backpressure cannot block stderr draining in `run`;
15. env merge/replace matches a pure Dict model and never mutates ambient env;
16. argv elements are delivered byte-for-byte as separate arguments;
17. Windows unsupported result occurs before the fake spawn verb is called;
18. cancel-all leaves registry empty under all generated live phases;
19. debug and optimized workers produce equal normalized traces;
20. old harness Bash and package path agree for exit, stdout/stderr bytes,
    timeout/cancel, spawn failure, and descendant survival checks.

### Real runtime/failure injection matrix

- child emits alternating stdout/stderr with random chunk sizes;
- child writes beyond pipe high-water marks while Elm delays reads;
- child ignores TERM; grandchild ignores TERM; both must die after grace;
- shell/pipeline creates grandchildren and attempts to orphan them;
- executable missing, cwd missing, EACCES, EMFILE/resource simulation;
- stdin consumer reads slowly, exits during write, or never reads;
- child closes one pipe early, exits before draining, or is externally killed;
- cancellation at every await boundary;
- 1,000 processes sequentially to detect registry/listener leaks;
- long stream (≥10,000 chunks) with heap and latency gates;
- Node Linux and macOS, debug and optimize, cold and warm package cache.

## 12. Harness vertical slice

Target the current asynchronous Bash mechanism in
`elm-pkg-js/tools-impl.js`/`run-exec-worker.js`, preserving Orchestrate laws.

### Slice sequence

1. Add a package-backed Elm worker/tool operation for one direct executable +
   argv path. It returns the existing harness Bash result shape:
   `{ exitCode, stdout, stderr }`; exit 1 remains `Ok` data.
2. Elm `ToolPolicy` continues to authorize command/workspace and chooses cwd,
   env, timeout, caps, and grace. The package sees already-authorized facts.
3. Use bounded `run` for capture; on timeout, ordinary Elm calls
   `terminate grace`, not a kernel-owned default timeout.
4. Register the live `Process` in worker-owned Elm state. Worker SIGTERM and
   stdin EOF issue cancellation for every owned process before worker exit.
5. Keep the parent's SIGTERM → grace → descendant reap → SIGKILL ladder during
   migration. Prove no orphan with the existing ignore-TERM Bash fixtures.
6. Differentially execute old/new paths for literal argv commands, nonzero,
   missing executable, mixed output, timeout, interrupt, overflow, and nested
   descendants.
7. Only after full harness tests and leak/orphan gates pass, remove the replaced
   `runBashAsync` mechanics. Do not remove the outer blocked-worker last rung.

### Important mismatch

The current Bash tool takes a shell command string. This package deliberately
uses executable + argv. The first slice should target an internal supervised
spawn that already has structured argv, or introduce an ordinary Elm shell
adapter that explicitly executes `/bin/sh -lc <command>` on Unix. The package
must not absorb shell quoting/policy merely to mimic Bash.

No deployment occurs from the integration evidence branch.

## 13. Unix/Windows and support matrix

| Platform | Compile | Spawn v1 | Owned descendants | TERM grace | Claim |
|---|---:|---:|---:|---:|---|
| Linux x64/arm64 | yes | yes | process group | yes | supported after CI |
| macOS x64/arm64 | yes | yes | process group | yes | supported after CI |
| Windows | potentially | fail before spawn | no | no | explicitly unsupported |
| other Unix | unknown | likely | likely | likely | unclaimed until tested |

Signals are reported as Node's canonical signal string. Normal exits preserve
full integer exit code supplied by Node. A signaled process is `Signaled`, never
encoded as magic negative exit data in the public API.

## 14. Open questions for hostile review

1. Split `RunOptions` from `SpawnOptions` now (preferred) or retain a runtime
   mode-validation error?
2. Should `closeStdin` after process exit be idempotent success or typed
   `StdinClosedAlready`? Which rule composes best in cleanup code?
3. Is 64 terminal waiters a sensible mechanical bound, or should wait be a
   single shared Task pattern documented at the app layer?
4. On pipe chunks above internal `maxChunkBytes`, slice/deliver pieces or fail
   the stream? Slicing preserves data and bounds each callback but adds kernel
   queue state.
5. Should `terminate` return `Exit` (proposed, race-safe) or only acknowledge
   signal initiation and require separate `wait`?
6. Should `run` allow inherited stdout/stderr even though returned bytes are
   empty, or keep `run` purely capture/ignore?
7. Is Unix-only acceptable for v1, or is Windows Job Object support a release
   gate requiring a native helper and separate capability?
8. How will ordinary Elm own all live handles for worker-wide cancellation
   without adding an O(all processes) hot path? Proposed answer: keyed registry,
   scanned only on cold shutdown.
9. Can compiler authorization safely extend to private effect modules later?
   This is explicitly not a v1 dependency and would need its own compiler
   design/review.

## 15. Evidence inspected

- Schelm `docs/PROGRAM.md` and package constitution;
- real private compiler branch and authorization fixtures;
- real compile/runtime feasibility fixture in this branch;
- Gren `ChildProcess` 6.1.3 public API and kernel source;
- Gren core `Stream` 6.0.0 API/source;
- harness `elm-pkg-js/tools-impl.js` Bash registry and process-group kill;
- harness `elm-pkg-js/run-exec-worker.js` SIGTERM/EOF cancellation;
- harness `elm-pkg-js/elmexec.js` parent TERM → grace → descendant reap → KILL;
- harness `Exec.elm` and `StateMachine/ExecBridge.elm` ownership laws.

The feasibility fixture is intentionally narrow and non-production. All six
required design/review/property artifacts still gate implementation.
