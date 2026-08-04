# 05 — final design revision B

This document is the implementation contract. It supersedes API/state details in 01 and 03.

## Scope

Unix Node 24 supervised process groups on tested Linux/macOS. Direct executable and argv, cwd/env, stdin modes, demand-streamed or inherited/discarded output, bounded buffered run, deadlines, cancellation, explicit supervisor shutdown. Windows and escaped sessions/groups are unsupported. “Owned descendants” means only processes remaining in the spawned PGID.

## Public shape

`Schelm.Node.ChildProcess` owns validated builders and result/error data. `Schelm.Node.ChildProcess.Supervisor` is the installed effect manager. `Schelm.Node.ChildProcess.ParentAdapter` defines, but does not integrate, the external-watchdog protocol.

Opaque IDs:

```elm
type Supervisor = Supervisor Int
type Operation = Operation Int Int
type Request = Request Int Int Int
```

Counters are monotonic per runtime and never wrap/reuse. Allocation at `maxSafeInteger` fails `IdentifierExhausted`; supervisors refuse new work but can shut down existing work.

Builders:

```elm
program : String -> Result ConfigurationError Program
argument : String -> Result ConfigurationError Argument
workingDirectory : String -> Result ConfigurationError WorkingDirectory
inheritedEnvironment : Environment
mergeEnvironment : Dict String String -> Result ConfigurationError Environment
replaceEnvironment : Dict String String -> Result ConfigurationError Environment
byteLimit : Int -> Maybe ByteLimit
milliseconds : Int -> Maybe Duration
```

`SpawnOptions` and `RunOptions` are opaque, constructed by builders/setters. Invalid pipe/run combinations are unconstructable. Defaults are closed stdin, demand output for spawn, 1 MiB capture per run stream, 120 s deadline, 500 ms grace, three post-KILL probes 25 ms apart. Package defaults are documented mechanisms; harness policy supplies explicit values.

Controls accept only `Operation` and callbacks:

```elm
demandStdout : Operation -> (Request -> Result ReadError ReadResult -> msg) -> Cmd msg
demandStderr : Operation -> (Request -> Result ReadError ReadResult -> msg) -> Cmd msg
writeStdin : Operation -> Bytes -> (Request -> Result WriteError () -> msg) -> Cmd msg
closeStdin : Operation -> (Request -> Result WriteError () -> msg) -> Cmd msg
cancel : Operation -> (Result ControlError () -> msg) -> Cmd msg
```

Unknown/foreign/settled handles return `UnknownOperation`. No tombstones are retained and no `Finished` distinction is claimed.

Spawn/run callbacks expose `onStarted : Operation -> ProcessInfo -> msg`, spawn failure, and exactly one final after start. `run` has a started operation and is cancellable. `RunFailure` includes bounded partial `CapturedOutput` and cleanup facts. Nonzero exit is data.

## Standalone versus parent-adapted creation

Standalone:

```elm
create : SupervisorOptions -> (Result CreateError Supervisor -> msg) -> Cmd msg
```

It provides explicit shutdown but cannot survive a blocked/dead event loop.

Parent-adapted preparation is separate:

```elm
ParentAdapter.prepare : ParentCallbacks msg -> Cmd msg
createParented : ParentAdapter.Prepared -> SupervisorOptions -> ... -> Cmd msg
```

Harness protocol before each spawn:

```text
prepare slot with parent -> Prepared(slot)
spawn child into new PGID -> Binding(slot,pid,pgid)
bind facts to parent -> BoundAwaitingAck
ack -> Registered -> onStarted
failure/timeout -> manager kills group, clears slot, reports spawn failure
cleanup final -> Unregistering -> parent ack/timeout -> Absent -> final callback
```

Thus the parent participates before spawn. The adapter API is compile-tested package surface only in this milestone; no harness transport implementation occurs before package audit.

## State and arbitration

Manager routing serializes decisions. Same `onEffects` batch follows list order; self messages follow mailbox order. While `Running`, the first routed control event among explicit cancel, deadline, overflow, stdin transport failure, process transport failure, supervisor shutdown, and leader close claims `CleanupReason`. Leader exit facts are recorded independently and never replace the claimed reason. Later errors enrich cleanup only.

Accepted demands/writes own a Request and resolve exactly once. EOF behavior:

- pending demand at EOF -> `Ok End`;
- demand after EOF while operation retained -> `Ok End`;
- demand after final removal -> `Err UnknownOperation`.

Final requires: leader fact (or explicit unknown after transport failure), both output modes settled, stdin pending requests settled, fixed cleanup ladder complete, and parent registration absent when parented. Then one final callback runs and manager/kernel entries are removed.

## Honest buffers

Demand mode keeps at most one package pending demand and one package-owned delivered slice (`maxDeliveryBytes`, 64 KiB). Node may retain additional bytes in its internal Readable buffer up to/runtime-around its configured high-water behavior; the package neither calls that zero nor promises an exact Node byte maximum. Tests inspect `readableLength` and RSS under delayed demand. A Node chunk larger than 64 KiB is retained by the kernel as one foreign chunk and sliced without copying on demands; package-owned copied output per callback is <=64 KiB. No unbounded Elm queue exists.

Capture stores copied chunks up to exact per-stream ByteLimit; byte limit + 1 claims overflow and switches to discard/drain. Final concatenation is once. Stdin retains at most one caller Bytes for a pending write, while Node's writable internal buffer is runtime-managed and measured separately.

## Cleanup ladder

For every started operation, including normal leader exit:

1. send TERM to `-pgid` once;
2. wait configured grace;
3. probe `kill(-pgid, 0)`;
4. if present/uncertain, send KILL once;
5. execute exactly `probeCount` post-KILL probes separated by `probeInterval`;
6. first `ESRCH` -> `CleanupObservedGone`;
7. success through final probe -> `CleanupUncertain StillPresent`;
8. `EPERM`/other probe failure through final probe -> `CleanupUncertain ProbeFailed`.

Signal syscall failures are retained. Leader close is never group-gone evidence. Numeric PGID reuse remains an acknowledged race; no PGID is persisted or signaled after final. Controlled fixtures assert no surviving descendant that remains in the PGID. Setsid escape is excluded and fixture-cleaned separately.

## Errors and terminal law

All configuration, ID exhaustion, unsupported platform, spawn, registration, control, read, write, deadline, overflow, transport, signal/probe, and shutdown outcomes are typed. JS catches exceptions and sends bounded code/site facts. Async stdin error after a successful earlier write is an operation transport fact and can claim cleanup; each already-resolved request stays resolved.

Before `onStarted`: exactly one spawn failure, no operation authority delivered. After `onStarted`: exactly one final. Cancel acknowledgement means cleanup was accepted/joined, not completed; completion is the final callback.

## Resource law

The manager owns every operation. Kernel registry mirrors manager membership plus explicit transition windows. The package installs no global signal/exit/stdin handlers and never calls `process.exit`. Shutdown is explicit and resolves only after active operations finalize. Hot event paths perform keyed lookup and O(new bytes); shutdown scans active operations only.

## Harness milestone boundary

No harness integration in this package milestone. The package exposes/compiles ParentAdapter protocol types and proves a deterministic fake protocol. Integration begins only after audit records:

- debug/optimized real fixture parity;
- pure model and fake-kernel properties;
- controlled in-PGID no-survivor tests;
- registry/listener/timer emptiness;
- bounds/RSS evidence;
- no global listeners;
- compiler/package provenance and reproducible archive.

Only then may a separate harness evidence branch replace one structured-argv subprocess path while preserving the external wall-clock/reap rung.
