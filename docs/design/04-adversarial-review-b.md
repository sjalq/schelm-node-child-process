# 04 — adversarial review B

Verdict: **reject revision A as written; accept the architecture after the binding corrections in revision B.** No implementation may cite `03-design-revision-a.md` without those corrections.

## Findings

1. **Controls still carry redundant supervisor authority.** An `Operation` already identifies and authorizes its supervisor-owned operation. Requiring both permits mismatched pairs and adds a runtime-invalid state. Every control must accept only `Operation` plus an explicit result callback.

2. **ID wrap/reuse is unacceptable.** Searching for an unused wrapped integer avoids collision only with currently active operations; a stale opaque value can later control a newly reused ID. Supervisor, operation, request, and parent-registration counters must be monotonic for the runtime and fail closed with `IdentifierExhausted` before JavaScript's safe-integer limit. No reuse.

3. **Settled behavior is overstated.** If finished operations are removed, a stale control is `UnknownOperation`; the package cannot distinguish finished from forged without retaining unbounded tombstones. Say unknown, not `OperationFinished`.

4. **Demand after EOF needs a total answer.** Removing an operation immediately after final makes late demand unknown, but a demand accepted before final can race EOF. Every accepted demand must resolve once as `End`, `Chunk`, `ReadFailed`, or `ReadCancelled`. Demand submitted after stream EOF but before operation removal returns `End`. After removal it is `UnknownOperation`.

5. **Backpressure bounds omit Node internals.** Pausing a `Readable` does not make total retained bytes equal one Elm chunk. Node has an internal high-water buffer; a delivered Node chunk can exceed the package slice. The contract must separately bound package-owned copied/sliced bytes and honestly report Node's runtime-managed buffer as bounded by configured `readableHighWaterMark`/Node behavior, verified empirically rather than represented as zero.

6. **Cleanup observation is vague.** Define a fixed ladder: TERM, grace, KILL, then a fixed finite probe schedule using `kill(-pgid, 0)`. `ESRCH` is observed gone; successful probe is still present; `EPERM`/other errors are uncertain. Exhausting probes is uncertain. Never call leader `close` group cleanup.

7. **“No survivor” must be fixture-scoped.** The package can prove no surviving process in controlled fixtures whose descendants remain in the PGID. It cannot prove arbitrary descendant absence, prevent `setsid`, or eliminate PGID reuse. Documentation and acceptance language must use “no controlled in-group fixture survivor.”

8. **Parent registration starts too late.** Registering after spawn leaves a worker-block/crash window with an unregistered detached group. Harness mode must obtain a parent-prepared registration slot *before* spawn. Spawn then binds leader PID/PGID to that slot and waits for acknowledgement before `onStarted`. Generic standalone mode is a separate API. Do not hide the distinction in an optional field.

9. **Race precedence is not exact.** “First reason” depends on host callback scheduling and can drift. Define one arbitration function over manager phase and events: a terminal control reason is claimed by the first manager-routed event while Running; leader facts never overwrite control reason; cleanup errors only enrich cleanup; final waits for all required facts. Same-turn command order follows `onEffects` list order; kernel events follow mailbox order.

10. **Registration acknowledgement lacks states.** Required states are Prepared, Binding, BoundAwaitingAck, Registered, Unregistering, and Absent. Every timeout/failure path must say who kills the group and who clears the slot.

11. **The test plan needs three independent layers.** Pure Elm transition model; deterministic fake kernel/parent protocol; real OS process-group fixtures. Passing only generated JS tests is not enough. Debug/optimize and cold/warm package provenance belong in the gate.

12. **Public API is still prose.** Before implementation, builders and modules must compile as an installed package, with no broad raw records that permit invalid limits/modes. `run` must expose start/cancel and bounded partial output on failure.

13. **Parent adapter cannot be generic magic.** Split it explicitly. Standalone supervisor creation is package-only. Harness preparation/bind/ack/reap is a separate `ParentAdapter` protocol/API and is not implemented against harness until package audit passes.

14. **Signal failure reporting must be truthful.** TERM/KILL calls can fail. Final cleanup must preserve each attempted signal/probe result and classify only observed-gone versus uncertain.

15. **Implementation gate must include self-audit.** Package audit must establish registry emptiness, listener/timer cleanup, bound adherence, no global signal listeners, and controlled-fixture group cleanup before any harness integration branch begins.

## Required final shape

- Installed package effect manager owns supervisors and operations.
- Scalar monotonic IDs; exhaustion is typed; no runtime reuse.
- Controls take only `Operation` and explicit callbacks.
- Demand-driven streamed reads; bounded captured `run` using the same operation machine.
- Standalone and parent-adapted spawn are distinct entry points/protocols.
- Leader exit and group cleanup are independent facts.
- Fixed TERM/grace/KILL/probe ladder with observed/uncertain result.
- Unknown stale operations after removal; no tombstone claim.
- Exact arbitration and registration state machines.
- Three-layer test gate plus immutable compiler/package provenance.

With these corrections, implementation may begin on the standalone Unix v1 only. Parent/harness integration remains blocked until the package audit is complete.
