# 02 — adversarial review A: reject `01-design.md`

Verdict: **reject**. The design has useful cancellation instincts, but its core
feasibility conclusion is wrong and that error infects ownership, API shape,
backpressure, shutdown, and the harness migration. Do not implement it.

## 1. The effect-manager feasibility claim is false

`01-design.md` says private effect modules are unavailable because an effect
module under an application source directory was rejected. That proves only the
standard Elm rule: applications cannot declare effect managers.

The pinned Schelm compiler defines `Pkg.isKernel` as author `elm`,
`elm-explorations`, or `sjalq`. Effect-module parsing uses that package
predicate. An effect manager installed as
`sjalq/schelm-node-child-process` compiled successfully in both debug and
`--optimize` application builds during this review.

The correct result is:

- application-local effect manager: rejected, correctly;
- installed authorized `sjalq/*` package effect manager: legal;
- therefore a manager-owned lifecycle is feasible and should be the v1 shape.

This is not a small correction. A package manager can mint opaque operation
handles, retain callbacks/state, serialize commands, and own all live resources.
The Task-only proposal discarded exactly the mechanism needed to make the
lifecycle coherent.

## 2. Raw opaque Node handles crossing into Elm are unsound

The feasibility fixture returns a `ChildProcess` JavaScript object while Elm
pretends it is `type Process = Process`. That is not an opaque Elm token; it is
an untyped foreign object. Optimized compilation rewrites Elm record fields and
can collide with arbitrary properties. Retaining that object through the proof
manager produced an optimized runtime failure.

The manager must mint scalar IDs (`Operation Int`) and kernel JS must keep Node
objects in a private registry keyed by those IDs. Elm handles are authority
only because the manager owns and validates membership. No Node stream, child,
timer, or callback object may cross the typed boundary.

## 3. Ownership is split between caller Tasks and kernel state

The proposal says the kernel registry owns processes, while callers directly
invoke `read`, `wait`, `terminate`, and `kill` Tasks. Elm cannot linearly consume
the handle, cannot know which caller owns cleanup, and cannot prevent a retained
Task handle from racing shutdown. It later suggests ordinary Elm maintain
another live-handle registry. That creates two lifecycle authorities.

The effect manager must be the single process owner:

- `spawn` mints an operation;
- read/write/wait/control commands are routed through that manager;
- every command validates manager membership;
- shutdown drains the manager's active Dict;
- the kernel registry is a mechanism mirror, not a second policy owner;
- settled operations move to a bounded terminal cache or become absent.

## 4. “Process tree” is overclaimed

A fresh Unix process group reaches descendants that remain in that group. It
does not reach a child that calls `setsid()`, changes process group, double-forks
into another session, or delegates work elsewhere. The design repeatedly says
“whole tree” and “descendants must die,” which is false.

The honest guarantee is **owned Unix process group**:

- leader is spawned as a new group leader;
- package signals that PGID;
- descendants remaining in the group are reached;
- `setsid`/`setpgid` escape is explicitly outside the guarantee;
- arbitrary process-tree discovery is not claimed.

Fixtures must include both an in-group descendant (must die) and a deliberate
`setsid` escape (documented non-guarantee, cleaned by the fixture itself).

## 5. Leader exit is confused with supervision completion

Node's `close` event describes the leader and its attached stdio. The leader may
exit while descendants in its group remain alive. Caching leader `Exit` and
removing the registry entry at `close` loses the authority needed to clean the
group.

The design needs two facts:

1. `LeaderExit`: the direct child's observed exit/signal and stream closure;
2. `Cleanup`: whether owned-group supervision is still active and how it ended.

`wait` may report leader exit, but operation settlement/removal must not happen
until the chosen cleanup contract is satisfied. For a normal leader exit, v1
must either:

- run a bounded group cleanup ladder before final completion; or
- explicitly return a result saying leader exited while group cleanup remains
  caller-controlled.

For a supervised tool API, the first is coherent: leader exit closes/captures
streams, then manager sends TERM to the remaining group, waits grace, sends
KILL, and only then emits one final result.

## 6. PGID reuse is ignored

After the group leader exits, blindly signaling `-pid` later risks hitting a
reused process-group ID. POSIX does not give Node an immortal group handle.
There is no race-free “is this still my original PGID?” query.

The design must be honest:

- act immediately on the retained PGID while the operation is active;
- use short, bounded grace;
- never persist/reconstruct PGIDs across process/daemon restart;
- parent-visible registration is ephemeral and tied to the live worker/leader;
- acknowledge a residual PGID-reuse race after leader exit;
- do not claim proof of descendant cleanup beyond observable group signaling;
- preserve the parent watchdog's direct-child discovery as the final crash path.

A Linux pidfd for the leader does not solve group identity. A stronger future
solution would require a platform supervisor/cgroup/job-object design.

## 7. Global library signal hooks violate authority

The proposal allows package-level process shutdown hooks. A library must not
install global `SIGTERM`, `SIGINT`, `exit`, or stdin handlers. Those handlers
compete with the harness worker and surprise every other application.

Expose an explicit `Supervisor` scope and `shutdown`. The application owns
signals/EOF and commands supervisor shutdown. The manager owns only operations
minted under that supervisor.

## 8. A blocked worker cannot run manager cleanup

The worker's event loop can be blocked by an infinite Elm loop. In that case no
Elm update, manager `onEffects`, JS signal handler, or timer runs. The proposal
mentions the existing parent rung but does not define a replacement registration
boundary for package-owned groups.

Each successful spawn must be registered outside the worker with the supervising
parent before it is considered started to the Elm app. Registration includes a
bounded opaque outer operation ID plus leader PID/PGID facts. Unregistration
occurs only after cleanup completion. The parent watchdog retains an external
wall clock and, after worker grace, kills registered PGIDs/direct child groups
before SIGKILLing the worker.

This parent mirror is not product policy: it is crash recovery for facts the
blocked owner cannot execute. Missing registration acknowledgement must fail
spawn closed and clean the child.

## 9. `run` is underspecified and ergonomically broken

The proposed `run`:

- initially has the wrong error type, revised later in prose;
- accepts spawn modes it cannot return;
- has no timeout despite timeout being central to the harness slice;
- provides no operation handle for cancellation while running;
- cannot expose partial output/control status on timeout or overflow;
- says timeout is an ordinary Elm race, but the Task returns no process handle
  to the racing caller.

A buffered run should be a manager recipe, not a separate hidden lifecycle:
spawn under a supervisor with captured streams, demand both drains, close/write
stdin, arm deadline, and finish through the same cleanup state machine. It needs
`onStarted : Operation -> msg`, `onFinished : Operation -> RunResult -> msg`,
and explicit `cancel operation`/`shutdown supervisor` commands. Timeout must be
part of `RunOptions` or represented by a manager command armed at start.

## 10. Mode/result accessibility is incoherent

The API exposes one `Process` regardless of stdio modes, then lets callers ask
to read unavailable streams and discover `StreamNotPiped` at runtime. It also
returns empty bytes for inherited output, which cannot distinguish “captured
empty” from “not captured.”

V1 should keep one operation handle for manager routing but make result
accessibility explicit:

- streaming `spawn` has `onStdout`/`onStderr` demand callbacks only for declared
  `Streamed` modes;
- buffered `run` has dedicated `RunOptions` where output is always bounded
  capture or discard;
- `RunResult.stdout/stderr` are `CapturedOutput = NotCaptured | Captured Bytes`;
- inherited output is not silently represented as captured empty bytes;
- stdin streaming capability is represented by the chosen mode and rejected
  commands are total typed errors.

## 11. Async stdin errors and cancellation races are incomplete

Node stdin can fail asynchronously after `write()` reports acceptance but
before `finish`, or race leader exit/cleanup. `Task WriteError ()` is not enough
if the manager also sends terminal callbacks. The design must define:

- write acknowledgement semantics (`accepted by Node buffer`, not consumed by
  child);
- asynchronous `error`/`close` delivery;
- exactly one result for each write request;
- ordering relative to final operation result;
- pending writes resolved with a typed terminal/cancel error during cleanup;
- no `drain` callback after cancellation;
- `end`/`finish`/`error` races through one stdin claim function.

## 12. Error algebra is not total

The proposal omits or blurs:

- invalid options before spawn;
- manager/supervisor absent, shutting down, or foreign operation;
- parent registration failure;
- output overflow final result with partial/discard status;
- deadline expiry versus explicit cancel versus supervisor shutdown;
- group TERM/KILL syscall failures;
- leader exit unknown/missing code;
- async stdin failure after prior write acceptance;
- stream demand after final/cancel;
- waiter/demand supersession;
- kernel invariant violation/unsupported runtime.

“No JS exception escapes” requires every event site to map constructively and a
single final result that records why supervision ended.

## 13. Windows scope is half broad, half absent

Failing every spawn on Windows is honest, but then v1 is not a broad Node child
process package; it is a Unix supervisor. That is acceptable if named and
documented plainly. Do not expose generic platform-neutral guarantees and hide
`UnsupportedPlatform` at runtime.

The design should state: v1 supports Node 24 on tested Linux/macOS for owned
process groups; Windows is compile-compatible but operationally unsupported.
Job Objects are a separate v2 design, not a TODO inside v1.

## 14. Models and fixtures are too aspirational

The property list lacks a manager model, supervisor scope, parent registration
ack, leader/group split, and PGID reuse/escape honesty. The existing fixture
proves only direct child output/exit and contains an invalid raw foreign handle.

Required pre-implementation evidence includes:

- installed package manager compiles debug/optimize (now proved);
- scalar operation ID + kernel registry runtime in both modes;
- model-based manager command/event permutations;
- demand one-chunk-at-a-time backpressure;
- bounded buffered run recipe using the same machine;
- leader exits while in-group descendant remains;
- ignored TERM escalates to KILL;
- deliberate setsid escape documented and fixture-cleaned;
- parent registration ack/failure/unregister protocol;
- blocked worker externally reaped by parent watchdog;
- no global signal listeners installed by the package;
- async stdin error/drain/finish races;
- differential harness result compatibility.

## Required revision

Replace the Task-owned design with an installed package effect manager that
owns explicit `Supervisor` scopes and manager-minted `Operation`s. Use
demand-driven stream commands, a buffered `run` recipe, one final supervision
result, explicit shutdown, Unix process-group-only guarantees, and an
acknowledged parent registration/watchdog boundary. Preserve the no-production-
implementation gate until the revised design survives the second hostile
review.
