# 03 — `schelm-node-child-process` design revision A

Status: replaces the architecture and API in `01-design.md`. This is design and
feasibility evidence only; production implementation remains blocked.

## 1. Corrected feasibility and governing decision

The pinned compiler allows effect managers in installed authorized kernel
packages. `sjalq/schelm-node-child-process` is such a package. The review fixture
`Schelm.Node.ChildProcess.FeasibilityManager` compiles as an installed dependency
in debug and optimized application builds. The earlier application-local
rejection was expected and did not disprove package managers.

V1 therefore uses one package effect manager as lifecycle owner.

A second feasibility lesson is equally binding: Node `ChildProcess`, stream,
timer, and callback objects never cross into Elm disguised as opaque values.
The manager mints scalar Elm IDs. Kernel JS retains foreign objects in a private
registry keyed by those IDs and returns only stable primitives/bytes/tuples.

## 2. Scope and honest support statement

V1 is a **supervised Unix child-process package for Node 24**:

- tested Linux and macOS targets;
- direct executable plus literal argv;
- cwd and inherited/merged/replaced environment;
- inherited, closed/bytes/streamed stdin;
- inherited, discarded, demand-streamed, or bounded-captured stdout/stderr;
- nonzero leader exit as result data;
- owned Unix process group with TERM → grace → KILL;
- explicit supervisor shutdown;
- parent registration protocol for blocked-worker recovery.

“Owned process group” means the leader is created as a new Unix process-group
leader and signals target that PGID. It includes descendants only while they
remain in that group. A descendant that calls `setsid`, `setpgid`, enters a
container/cgroup boundary, or delegates work elsewhere escapes this guarantee.
V1 does not claim arbitrary process-tree ownership.

Windows applications may compile, but creating a supervisor returns
`UnsupportedPlatform UnixProcessGroupsRequired` before any child is spawned.
Windows Job Objects require a separate v2 design.

V1 does not own shell quoting or command policy. A caller wanting shell syntax
explicitly executes `/bin/sh` with argv; the harness owns whether that is
allowed.

## 3. Public modules and broad coherent API

Two modules separate ordinary configuration/result data from the manager:

```elm
Schelm.Node.ChildProcess
Schelm.Node.ChildProcess.Supervisor
```

### 3.1 Shared data module

```elm
module Schelm.Node.ChildProcess exposing
    ( Program
    , program
    , WorkingDirectory(..)
    , Environment(..)
    , Stdin(..)
    , StreamOutput(..)
    , RunOutput(..)
    , SpawnOptions
    , RunOptions
    , defaultSpawnOptions
    , defaultRunOptions
    , ByteLimit
    , byteLimit
    , Duration
    , milliseconds
    , Deadline(..)
    , OutputStream(..)
    , CapturedOutput(..)
    , LeaderTermination(..)
    , LeaderExit
    , CleanupReason(..)
    , Cleanup(..)
    , Final
    , SpawnError(..)
    , ControlError(..)
    , ReadError(..)
    , WriteError(..)
    , RunError(..)
    )
```

Opaque validated values:

```elm
type Program
    = Program String

program : String -> Result ConfigurationError Program


type ByteLimit
    = ByteLimit Int

byteLimit : Int -> Maybe ByteLimit


type Duration
    = Duration Int

milliseconds : Int -> Maybe Duration
```

`program` rejects empty/NUL-containing names. Arguments, cwd, and environment
receive equivalent total validation before entering the kernel. Durations and
limits are finite nonnegative safe integers.

Modes are split so `run` cannot select an inaccessible pipe:

```elm
type Stdin
    = ClosedStdin
    | InheritStdin
    | InputBytes Bytes
    | StreamStdin


type StreamOutput
    = InheritStream
    | DiscardStream
    | DemandStream


type RunOutput
    = InheritRunOutput
    | DiscardRunOutput
    | CaptureUpTo ByteLimit


type alias SpawnOptions =
    { cwd : WorkingDirectory
    , environment : Environment
    , stdin : Stdin
    , stdout : StreamOutput
    , stderr : StreamOutput
    , grace : Duration
    }


type alias RunOptions =
    { cwd : WorkingDirectory
    , environment : Environment
    , stdin : RunStdin
    , stdout : RunOutput
    , stderr : RunOutput
    , deadline : Deadline
    , grace : Duration
    }


type RunStdin
    = RunClosedStdin
    | RunInheritStdin
    | RunInputBytes Bytes


type Deadline
    = NoDeadline
    | DeadlineAfter Duration
```

`run` modes are closed by construction: no streamed stdin and no demand output.

Result accessibility is explicit:

```elm
type CapturedOutput
    = NotCaptured
    | Captured Bytes


type LeaderTermination
    = Exited Int
    | Signaled String
    | ExitUnknown


type alias LeaderExit =
    { pid : Int
    , termination : LeaderTermination
    }


type CleanupReason
    = LeaderFinished
    | ExplicitCancel
    | DeadlineReached
    | SupervisorShutdown
    | OutputOverflow OutputStream ByteLimit
    | InputTransportFailed
    | ProcessTransportFailed


type Cleanup
    = GroupAlreadyGone
    | GroupTerminated
        { termAttempted : Bool
        , killAttempted : Bool
        , termErrorCode : Maybe String
        , killErrorCode : Maybe String
        }
    | GroupCleanupUncertain
        { termAttempted : Bool
        , killAttempted : Bool
        , detail : CleanupUncertainty
        }


type alias Final =
    { leader : LeaderExit
    , cleanupReason : CleanupReason
    , cleanup : Cleanup
    , stdout : CapturedOutput
    , stderr : CapturedOutput
    }
```

`Final` is emitted once after leader observation, stream settlement, and the
owned-group cleanup protocol. Nonzero `Exited n` remains successful process
data. Transport/configuration/supervision failures are typed separately; they
never masquerade as exit codes.

### 3.2 Manager module

```elm
effect module Schelm.Node.ChildProcess.Supervisor
    where { command = MyCmd }
    exposing
        ( Supervisor
        , Operation
        , Request
        , create
        , spawn
        , run
        , demandStdout
        , demandStderr
        , writeStdin
        , closeStdin
        , cancel
        , shutdown
        )
```

Opaque manager-minted authority:

```elm
type Supervisor
    = Supervisor Int


type Operation
    = Operation Int Int


type Request
    = Request Int Int
```

`Operation` carries supervisor/operation IDs internally, preventing accidental
cross-supervisor use. The manager additionally validates membership. IDs wrap
only after finding an unused key; active IDs are never reused.

Creation and lifecycle callbacks:

```elm
type alias SupervisorCallbacks msg =
    { onCreated : Supervisor -> msg
    , onCreateFailed : CreateError -> msg
    , onShutdown : Supervisor -> ShutdownReport -> msg
    }

create : SupervisorCallbacks msg -> SupervisorOptions -> Cmd msg


type alias SpawnCallbacks msg =
    { onStarted : Supervisor -> Operation -> ProcessInfo -> msg
    , onSpawnFailed : Supervisor -> SpawnError -> msg
    , onStdout : Supervisor -> Operation -> Request -> ReadResult -> msg
    , onStderr : Supervisor -> Operation -> Request -> ReadResult -> msg
    , onWrite : Supervisor -> Operation -> Request -> Result WriteError () -> msg
    , onStdinClosed : Supervisor -> Operation -> Request -> Result WriteError () -> msg
    , onFinished : Supervisor -> Operation -> Final -> msg
    }

spawn : Supervisor -> SpawnCallbacks msg -> Program -> List String -> SpawnOptions -> Cmd msg


type alias RunCallbacks msg =
    { onStarted : Supervisor -> Operation -> ProcessInfo -> msg
    , onSpawnFailed : Supervisor -> SpawnError -> msg
    , onFinished : Supervisor -> Operation -> Result RunError Final -> msg
    }

run : Supervisor -> RunCallbacks msg -> Program -> List String -> RunOptions -> Cmd msg
```

Demand/control commands:

```elm
demandStdout : Supervisor -> Operation -> Cmd msg
demandStderr : Supervisor -> Operation -> Cmd msg
writeStdin : Supervisor -> Operation -> Bytes -> Cmd msg
closeStdin : Supervisor -> Operation -> Cmd msg
cancel : Supervisor -> Operation -> Cmd msg
shutdown : Supervisor -> Cmd msg
```

Each accepted demand/write is assigned a manager-minted `Request`, surfaced in
its callback, and resolves exactly once. A command against an unknown, foreign,
finished, or shutting-down operation produces a typed callback result rather
than disappearing. To achieve this, command forms carry a control-error callback
for commands not already covered by `SpawnCallbacks`; the exact ergonomic
record may be revised, but silent no-op is forbidden except documented repeated
`cancel` joining the same final result.

A supervisor is explicit scope, not global permission. The package installs no
process signal, stdin EOF, uncaught-exception, or exit listeners. The application
owns those boundaries and calls `shutdown supervisor`.

## 4. One ownership chain

```text
Application
  owns Supervisor token and decides when to shutdown

Effect manager State
  Dict SupervisorId SupervisorState
    Dict OperationId OperationState
      callbacks, modes, request IDs, pure lifecycle facts

Kernel registry
  (SupervisorId, OperationId) -> Node mechanism entry
    ChildProcess, PGID, streams, timers, listeners, pending callbacks

Parent supervisor (harness integration only)
  outerRegistrationId -> workerPid, leaderPid, pgid
    crash-recovery mirror acknowledged before onStarted
```

The manager is the policy/lifecycle authority. Kernel registry entries are
unreachable except through manager kernel functions and cannot mint callbacks
on their own without routing `SelfMsg` back to the manager. The parent mirror is
not a second normal owner; it acts only if the worker is blocked/dead and cannot
run manager shutdown.

No raw Node object enters manager state. Kernel calls use IDs and stable
primitives/bytes/tuples only. Optimized fixtures must prove every boundary.

## 5. Manager and kernel state machines

### 5.1 Supervisor

```text
Creating
  ├─ supported/registered ─> Open
  └─ unsupported/failure ─> CreateFailed (absent)

Open
  ├─ spawn/run ─> operation state
  └─ shutdown ─> ShuttingDown

ShuttingDown
  ├─ reject new spawn/run
  ├─ cancel every active operation
  ├─ wait for every operation Final/unregistered
  └─ no active operations ─> Closed + one ShutdownReport

Closed
  └─ all commands return SupervisorClosed/UnknownSupervisor
```

Supervisor shutdown is O(active operations), intentionally cold. Ordinary
chunk/demand events never scan supervisors or sibling operations.

### 5.2 Operation lifecycle

```text
Prepared
  └─ kernel spawn ─> Starting

Starting
  ├─ validation/sync throw/Node error ─> SpawnFailed ─> Absent
  ├─ Node spawn + parent registration ack ─> Running + onStarted
  ├─ parent registration failure ─> Cleanup(RegisterFailed)
  └─ supervisor shutdown ─> Cleanup(SupervisorShutdown)

Running
  ├─ demand/write/control ─> Running substates
  ├─ deadline ─> Cleanup(DeadlineReached)
  ├─ explicit cancel ─> Cleanup(ExplicitCancel)
  ├─ overflow/transport failure ─> Cleanup(reason)
  └─ leader close ─> LeaderObserved ─> Cleanup(LeaderFinished)

Cleanup(reason)
  ├─ freeze new reads/writes; settle pending requests exactly once
  ├─ retain/drain or discard stream facts according to mode
  ├─ signal owned PGID TERM immediately
  ├─ grace expires ─> signal PGID KILL once
  ├─ observe group-gone where possible / bounded final cleanup point
  ├─ unregister parent mirror
  └─ streams + leader + cleanup facts complete ─> Finished

Finished
  ├─ emit one Final
  ├─ manager removes active operation
  ├─ kernel drops all foreign objects/listeners/timers
  └─ no live control by stale handle
```

One `claimFinal` transition owns the final callback. Node `error`, `exit`,
`close`, stream errors, deadline, cancel, shutdown, registration failure, TERM
and KILL timer events can propose facts but cannot emit independently.

### 5.3 Leader exit versus group cleanup

Leader exit is a fact, not operation completion. `close` normally supplies the
leader termination after stdio closes. The operation still owns its PGID and
runs cleanup so in-group descendants do not outlive the supervised operation.

On normal leader completion, cleanup sends TERM to the group immediately. If
the group still exists at grace, KILL follows. This may signal the already-dead
leader harmlessly and reaches remaining in-group descendants.

POSIX gives Node no race-free durable PGID handle. After leader exit, the numeric
PGID can theoretically be reused before a later signal. V1 mitigates but cannot
eliminate this:

- dedicated group created immediately at spawn;
- registration and cleanup begin while operation is live;
- short bounded grace;
- no PGID persisted or reconstructed after restart;
- no delayed user signal API after Final;
- cleanup result may be `GroupCleanupUncertain`;
- documentation states the residual reuse race.

The package never claims cleanup of `setsid` escapees. A stronger guarantee
requires cgroups/job objects/a dedicated native supervisor and is outside v1.

## 6. Demand-driven output and bounded buffered run

### 6.1 Streamed spawn

`DemandStream` starts paused. `demandStdout`/`demandStderr` each authorize at
most one delivered chunk:

```text
Paused
  ├─ demand ─> DemandPending(request)
  ├─ EOF ─> Ended
  └─ cleanup ─> Cancelled

DemandPending
  ├─ one chunk ─> callback(request, Chunk bytes) ─> Paused
  ├─ EOF ─> callback(request, End) ─> Ended
  ├─ stream error ─> callback(request, ReadFailed e) ─> Failed
  └─ cleanup ─> callback(request, ReadCancelled reason) ─> Cancelled
```

A second demand while pending returns `ReadAlreadyPending`. There is no
unbounded push queue. The Node stream is paused unless one demand is pending.
The kernel may retain at most one Node-emitted chunk due to pause timing and
slices chunks to an internal maximum delivery size. Remaining slices are
bounded by the original Node chunk and delivered only on future demand; the
property model accounts for this transient bound.

`Chunk Bytes` is raw. Text/line framing remains ordinary Elm.

### 6.2 Buffered `run` is a recipe, not another lifecycle

The manager lowers `run` into the same operation machine:

1. spawn with run-only modes;
2. register externally and emit `onStarted`;
3. concurrently drain both captured streams;
4. write `RunInputBytes` with Node backpressure, then close stdin;
5. arm optional deadline at successful start;
6. on leader exit, deadline, overflow, input error, or explicit cancel, enter the
   same group cleanup;
7. emit one `onFinished` with typed result and accessible capture facts.

Capture uses per-stream exact limits, JS arrays of copied chunks, O(new chunk)
append, and one O(total retained bytes) final concatenation. On byte `limit + 1`:

- retained output never exceeds limit;
- later bytes are drained/discarded to avoid pipe deadlock;
- cleanup reason becomes `OutputOverflow stream limit` unless an earlier
  higher-priority reason already claimed control;
- final/run error reports overflow and may return bounded partial captures via a
  dedicated `RunFailure` record.

Revised run result:

```elm
type RunError
    = RunCancelled RunFailure
    | RunDeadlineReached RunFailure
    | RunOutputOverflow OutputStream ByteLimit RunFailure
    | RunInputFailed WriteError RunFailure
    | RunTransportFailed TransportError RunFailure


type alias RunFailure =
    { leader : Maybe LeaderExit
    , cleanup : Cleanup
    , stdout : CapturedOutput
    , stderr : CapturedOutput
    }
```

Spawn failure stays `onSpawnFailed` because no `Operation` becomes started.
After `onStarted`, exactly one `onFinished` follows, success or `RunError`.
Explicit `cancel operation` works for both streamed spawn and buffered run.

Deadline starts only after spawn and external registration acknowledgement. It
is a manager/kernel timer, so it shares one terminal machine. The harness still
keeps an outer wall clock because a blocked worker cannot run it.

## 7. Stdin semantics and total asynchronous errors

### Modes

- `ClosedStdin`: child starts with ignored/closed stdin.
- `InheritStdin`: package exposes no write commands.
- `InputBytes`: manager writes all bytes with backpressure then closes.
- `StreamStdin`: caller may issue manager write/close commands.

### Write state

```text
Unavailable
Writable
WritePending(request, retained bytes, waitingDrain)
Closing(request)
Closed
Failed WriteError
Cancelled CleanupReason
```

Only one write or close request may be pending. `write()` returning true means
accepted into Node's writable machinery, not consumed by the child. The request
resolves success at accepted/drain according to Node backpressure. A later
asynchronous stream error is delivered as an operation transport fact and may
initiate cleanup even if an earlier write request succeeded.

Every request callback claims once. `error`, `close`, `finish`, `drain`, leader
exit, and cleanup remove all associated listeners/tokens before callback. During
cleanup:

- pending write resolves `WriteCancelled cleanupReason` unless a prior concrete
  `BrokenPipe`/transport error won;
- pending close resolves similarly;
- future writes return `OperationFinished`, `OperationCancelling`, or
  `StdinUnavailable`;
- no `drain` callback may resolve a removed request.

`InputBytes` failures become `RunInputFailed` and initiate cleanup. For streamed
spawn they produce a typed write/transport callback and cleanup reason
`InputTransportFailed`; they cannot vanish behind a later leader exit.

## 8. Total error algebra

Every boundary is constructive and bounded. No JS exception escapes and no
unknown command silently disappears.

```elm
type CreateError
    = UnsupportedPlatform PlatformRequirement
    | ParentRegistrationUnavailable
    | UnsupportedRuntime String


type SpawnError
    = InvalidConfiguration ConfigurationError
    | ExecutableNotFound
    | PermissionDenied
    | WorkingDirectoryNotFound
    | ResourceExhausted
    | ParentRegistrationFailed BoundedDetail
    | SpawnTransportFailed TransportError
    | SupervisorUnavailable SupervisorError


type SupervisorError
    = UnknownSupervisor
    | SupervisorShuttingDown
    | SupervisorClosed


type ControlError
    = ForeignOperation
    | UnknownOperation
    | OperationStarting
    | OperationCancelling
    | OperationFinished


type ReadError
    = StdoutUnavailable
    | StderrUnavailable
    | ReadAlreadyPending
    | ReadCancelled CleanupReason
    | ReadTransportFailed TransportError
    | ReadControlFailed ControlError


type WriteError
    = StdinUnavailable
    | WriteAlreadyPending
    | CloseAlreadyPending
    | StdinAlreadyClosed
    | BrokenPipe
    | WriteCancelled CleanupReason
    | WriteTransportFailed TransportError
    | WriteControlFailed ControlError
```

`TransportError` contains an allowlisted code, operation site, and bounded safe
detail; it never contains environment contents, stdin, or captured output.

Priority does not rewrite history. The first cleanup initiator is recorded as
`CleanupReason`; later transport/signal errors enrich `Cleanup` but do not emit a
second final. Leader termination remains independently recorded whenever
observed.

## 9. Parent-visible registration and blocked-worker watchdog

A generic standalone package cannot contact an arbitrary parent. Therefore the
supervisor is configured with an optional host registration capability at
creation. In normal applications it is `NoOuterWatchdog`; cleanup depends on
explicit `shutdown` and the application event loop. Harness integration supplies
`OuterWatchdog` through the package's minimal kernel host adapter.

Protocol facts:

```text
worker -> parent: register { outerOperationId, workerPid, leaderPid, pgid }
parent -> worker: registered { outerOperationId }
worker -> parent: unregister { outerOperationId }
```

Rules:

1. kernel spawn creates the child/group but manager does not emit `onStarted`;
2. registration is sent immediately;
3. acknowledgement transitions `Starting -> Running` and permits `onStarted`;
4. failure/timeout enters cleanup and spawn fails closed;
5. unregister happens only after group cleanup finalization;
6. parent records are ephemeral and scoped to the live worker; never journaled
   or restored after restart;
7. IDs are parent-minted/worker-scoped opaque values, not user-supplied PGIDs.

Outer cancellation ladder:

```text
parent wall clock/interrupt
  -> SIGTERM worker
  -> wait longer than manager group grace
  -> if worker remains alive, signal registered PGIDs KILL while direct-child
     relationship/facts are still available
  -> SIGKILL worker
  -> clear ephemeral registrations
```

The parent's existing direct-child discovery remains a belt-and-braces fallback
for registration races. A blocked Elm/Node event loop cannot acknowledge or
clean; the external parent remains mandatory for harness wall-clock guarantees.

This boundary requires a harness integration design because the package alone
cannot invent IPC. Production package API must keep the registration adapter
narrow: facts and send/ack verbs in JS, decisions/state in the manager Elm.

## 10. No global signal ownership

The package registers no global signal/exit/stdin handlers. Example application
wiring is explicit:

```text
application receives SIGTERM / EOF / own shutdown request
  -> Supervisor.shutdown supervisor
  -> waits on onShutdown
  -> application exits
```

The harness worker may retain a tiny host signal handler because signals are a
Node boundary, but it sends one shutdown command into Elm and waits. If Elm is
blocked, the parent watchdog handles the failure. The library does not call
`process.exit`.

## 11. Complexity and bounds

Hot-path costs:

| Path | Cost | Retained state |
|---|---:|---:|
| route manager command/event | O(log operations) Dict lookup | O(active ops) |
| output demand/chunk | O(new chunk) | one pending demand + bounded chunk/slices |
| stdin write/drain | O(new bytes) | one retained write |
| capture append | O(new chunk) | O(captured bytes <= limit) |
| final capture concat | O(total captured) once | final bytes |
| operation final | O(pending requests for that operation), mechanically bounded | terminal callback |
| supervisor shutdown | O(active operations), cold | active operations until final |
| parent kill rung | O(registered operations), cold crash path | ephemeral registrations |

Mechanical bounds:

- one pending stdout demand;
- one pending stderr demand;
- one pending stdin write/close;
- per-stream capture limit;
- internal maximum delivered chunk/slice;
- bounded grace and deadline;
- one final callback;
- no arbitrary waiters: lifecycle uses the one registered callbacks record;
- bounded transport detail;
- harness meters total/concurrent processes outside the package.

At chunk 10,000 no prior chunk is scanned. At operation 1,000 no settled
operation is scanned. Finished operations are removed after final callback; IDs
are not retained as an ever-growing tombstone set.

## 12. Pure models and executable fixture matrix

### 12.1 Manager reference model

```elm
type alias Model =
    { supervisors : Dict SupervisorId SupervisorModel
    , kernel : Dict OperationKey KernelModel
    , parent : Dict OuterId RegistrationModel
    }


type OperationPhase
    = Starting RegistrationPhase
    | Running RunningModel
    | Cleaning CleanupModel
    | Finished Final
```

Generated commands/events cover:

- create/open/shutdown/closed supervisors;
- spawn validation, sync throw, async error, spawn, registration ack/failure;
- every stdout/stderr demand/chunk/EOF/error ordering;
- stdin write/drain/error/finish/close orderings;
- leader `error`/`exit`/`close` orderings;
- leader exits with live in-group descendant;
- deadline/cancel/shutdown/overflow races;
- TERM success/failure, grace, KILL success/failure;
- unregister ack/loss and blocked worker parent kill;
- forged/foreign/stale supervisor, operation, and request IDs.

Core properties:

1. no operation emits more than one `onStarted`, `onSpawnFailed`, or final;
2. spawn failure and started operation are mutually exclusive;
3. started operation emits exactly one final under a fair terminal/cleanup trace;
4. every accepted request resolves exactly once;
5. manager active membership equals kernel registry membership modulo explicit
   `Starting` registration and `Finished` teardown transitions;
6. parent registration exists from start acknowledgement until cleanup
   unregister; no success callback precedes acknowledgement;
7. supervisor shutdown rejects new work and reaches empty registries under fair
   cleanup;
8. nonzero leader exit is data, never spawn/transport failure;
9. leader exit alone never deletes cleanup authority;
10. KILL occurs at most once and only after explicit hard kill/escalation;
11. new demands cannot increase buffered chunks without acknowledgement;
12. captured bytes never exceed limit; `limit + 1` records overflow;
13. pending stdin listeners/requests are absent after cleanup;
14. stale/foreign handles cannot control another operation;
15. debug and optimized normalized traces are equal;
16. no model transition depends on a global process signal listener.

### 12.2 Real compiler/runtime fixtures before implementation review

Feasibility/release fixtures must include:

- installed `sjalq/*` effect manager compile and execute debug/optimize;
- manager scalar IDs with kernel registry; assert no foreign Node object appears
  in Elm values;
- 10,000 demand-driven chunks with delayed demand and bounded RSS;
- concurrent buffered stdout/stderr at both exact caps;
- overflow at cap + 1 with bounded partial output;
- slow stdin consumer, EPIPE, error-after-write-acceptance, close races;
- direct nonzero exit, missing executable, invalid cwd/env/argv;
- leader exits while in-group TERM-ignoring descendant remains; KILL removes it;
- child and in-group grandchild ignore TERM; escalation removes group;
- child deliberately calls `setsid`; fixture records escape as out of guarantee
  and cleans it independently so CI leaks nothing;
- short grace stress to expose numeric PGID reuse risk without claiming it can
  be eliminated;
- outer registration success/failure/ack timeout/unregister;
- worker blocked in infinite Elm loop; parent kills registered group before
  worker SIGKILL;
- package installs zero global signal/exit/stdin listeners;
- sequential 1,000-operation registry/listener leak test;
- Linux/macOS, Node 24, debug/optimize, cold/warm isolated overlay.

## 13. Harness vertical milestone

The first integration milestone is one **structured-argv supervised subprocess
path**, not wholesale Bash replacement.

1. Harness Elm creates one supervisor with outer-watchdog registration.
2. Tool policy validates executable/shell adapter, cwd, environment, deadline,
   capture caps, and grace before package calls.
3. Package `run` executes the structured command. For legacy Bash, ordinary Elm
   explicitly chooses `/bin/sh [ "-lc", command ]`; package remains shell-blind.
4. `onStarted` registers the manager operation in worker-owned Elm state.
5. timeout, interrupt, normal completion, overflow, and shutdown all resolve the
   same operation final/result shape; exit 1 is `Ok` data.
6. Worker signal/EOF boundary commands supervisor shutdown. Parent wall clock
   and registration mirror cover blocked worker.
7. Differential tests compare old/new stdout, stderr, exit, missing executable,
   EPIPE, timeout, interrupt, overflow, and in-group descendant cleanup.
8. Preserve old `cancellableTools`/`killWorkerBashGroups` until every spawned
   package operation is parent-visible and blocked-worker fixtures pass.
9. Cut over one path, remove its old authority, then expand. No permanent dual
   lifecycle implementation.
10. Run full harness Elm/GUI/host/format suites on the evidence branch. No
    deployment.

Milestone acceptance is not “child exited.” It is:

```text
one final result
+ package manager/kernel registries empty
+ parent registration absent
+ no in-guarantee process-group survivor
+ no pending stream/write/timer/listener
```

## 14. Decisions fixed by revision A

- Installed authorized package effect manager: **yes**.
- Application-local effect manager: **no**, as standard Elm requires.
- Lifecycle owner: **one manager**, scoped by opaque `Supervisor`.
- Foreign handles in Elm: **forbidden**; scalar IDs + kernel registry.
- Streaming: **demand-driven**, one outstanding read per stream.
- Buffered run: **same manager machine**, bounded capture, explicit deadline and
  cancellation handle via `onStarted`.
- Nonzero exit: **data**.
- Final callback: **exactly one after cleanup protocol**, not merely leader exit.
- Unix guarantee: **owned process group only**, no setsid escape claim.
- PGID reuse: **residual acknowledged risk**, no persistence/restart signaling.
- Signals: **application/worker boundary owns them**, never library-global.
- Blocked worker: **parent-visible acked registration + outer watchdog**.
- Windows: **operationally unsupported in v1**, explicit pre-spawn failure.
- Production implementation: **still forbidden** pending review B and remaining
  required artifacts.

## 15. Remaining review targets

1. Is automatic group cleanup after every normal leader exit acceptable for
   applications that intentionally daemonize? V1's supervised scope says yes;
   daemonization should use another package/API.
2. Can the parent registration adapter be packaged without coupling a generic
   library to harness IPC, or should it be an internal optional kernel callback
   supplied only by a dedicated harness integration module?
3. What observable condition ends cleanup when `kill(-pgid, 0)` races
   permission/reuse? Revision uses bounded attempt + uncertainty, not proof.
4. Should explicit cancel produce `Ok Final` with `CleanupReason`, or a
   `RunCancelled RunFailure`? The revised split favors typed `RunError` while
   preserving `Final` for streamed spawn.
5. Does `onStarted` need to expose PID? It is observational only and must never
   become signal authority.
6. Exact priority table when deadline, overflow, leader exit, and input error
   arrive in one turn needs hostile review and then a single pure Elm function.
7. Registration ack timeout itself needs a bounded configuration owner. Harness
   should own the value; generic supervisor may use no outer registration.
