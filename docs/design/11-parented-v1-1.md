# 11 — parent-adapted supervision contract (1.1)

Status: implementation contract. This extends, and does not replace, the audited
1.0 standalone API.

## Five governing principles

1. **Parent before spawn.** A parent-minted reservation must be acknowledged
   before the package invokes `child_process.spawn`.
2. **Authority is opaque and singular.** `Supervisor.Operation` is the only
   child-control authority. Parent registrations and PID/PGID observations are
   opaque facts; no public control function accepts them. The package manager is
   the only active-operation registry in the worker.
3. **Started means registered.** A physical child is not exposed to application
   code until the parent acknowledges binding package-observed `{ pid, pgid }`.
   Bind rejection, transport loss, or timeout kills and clears it without
   `onStarted`.
4. **The blocked-worker last rung remains.** Immediately before SIGKILL the
   parent receives an idempotent reap request while the worker/leader relation is
   still observable. The parent acknowledges after reaping worker-linked escaped
   groups. A bounded timeout preserves KILL if acknowledgement is lost. The
   parent can drive this rung without scheduling Elm in the blocked worker.
5. **Settled means absent everywhere.** Final delivery follows unregister
   acknowledgement or its bounded timeout. Cancellation, deadline, spawn error,
   parent loss, shutdown, and normal exit converge on one cleanup arbiter; no
   path can finalise while manager or parent registration remains.

## Public additive API

```elm
ParentAdapter.prepare :
    ParentAdapter.Options
    -> ParentAdapter.Callbacks msg
    -> (Result ParentAdapter.PrepareError ParentAdapter.Prepared -> msg)
    -> Cmd msg

Supervisor.createParented :
    ParentAdapter.Prepared
    -> (Result Child.CreateError Supervisor -> msg)
    -> Cmd msg
```

`Prepared` is opaque, parent-minted, and single-use. `create`, `spawn`, `run`,
and all 1.0 option builders retain source compatibility. `ProcessInfo` adds
`pgid`; callers compiling against 1.1 may observe it but cannot signal with it.

## Transport boundary

The kernel owns only Node IPC verbs and timer facts. Lifecycle decisions remain
in the Elm managers. Requests carry package-generated reservation/request IDs;
the host parent may acknowledge or reject them. The protocol tags are:

- `schelm-child.prepare` / `schelm-child.prepared`
- `schelm-child.bind` / `schelm-child.bound`
- `schelm-child.before-kill` / `schelm-child.reaped`
- `schelm-child.unregister` / `schelm-child.unregistered`

Every response must match reservation and request. Duplicate/stale responses are
ignored. Disconnect becomes a typed transport-loss fact and starts cleanup for
all preparing, binding, registered, and unregistering operations. No global
SIGTERM/EOF handlers and no `process.exit` are installed.

## Lifecycle

```text
Absent
  -> Preparing -> Prepared
  -> Spawning -> Binding -> BoundAwaitingAck -> Registered -> onStarted
  -> Terminating(TERM) -> BeforeKillAwaitingAck -> KILL -> fixed probes
  -> Unregistering -> Absent -> onFinished
```

Spawn failure consumes the reservation and unregisters it. Normal leader exit
still enters the same cleanup/unregister railway. Each request has a package
validated positive timeout. First cleanup reason wins. Before-kill and
unregister settlement are idempotent and at most once.

## Evidence gate

Debug and optimized compiled fixtures use a fake IPC parent and real Linux
process groups. They cover prepare-before-spawn ordering, bind gating,
rejection/timeouts/loss, cancellation in every intermediate state, TERM-ignore,
a blocked worker with a detached nested group, pre-KILL reap ack and timeout,
unregister gating, shutdown joins, 200 sequential/bounded concurrent runs,
empty registries/listeners/timers, 1.0 caller compatibility, unauthorized-author
rejection, archive reproduction, and package/compiler provenance.
