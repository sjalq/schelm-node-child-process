# 12 — independent audit status

Verdict: **REPAIRED AND INDEPENDENTLY AUDITED; harness integration remains separate.**

The 1.1 branch is progressively committed and pushed, and the standalone 1.0
suite remains green through all pre-parented checks. Package docs, debug and
optimized standalone fixtures, model tests, scale tests, process-group tests,
metadata, and reproducible archive generation run.

The ordering blocker is removed by the manager lifecycle `Preparing -> Binding
-> Running | Rejecting`. Each phase is committed before a later self-message can
launch spawn or bind work; asynchronous responses return only through `SelfMsg`.
There is no sleep-based synchronization. Bind rejection is a single `Rejecting`
arbiter: no `onStarted`, cleanup first, then one `onSpawnFailed`.

Kernel cleanup has one explicit phase record. It owns TERM, bounded pre-KILL
reap, KILL/probes, unregister, and absent. Final construction occurs only in the
`absent` transition after registration is false. Public cleanup evidence now
includes `ParentReapNotRequested | Acknowledged | TimedOut | Failed`.

The independent gate covers debug and optimized parent transport, acknowledged
and timed-out pre-KILL reap, unregister-before-final ordering, 200 sequential
parented runs split evenly across debug and optimized artifacts, parent disconnect
fanout, intermediate shutdown joins, pinned 1.0 tree/archive caller differential,
unauthorized-author
rejection in debug and optimize, compiler/Node provenance, deterministic
archive reproduction, standalone model/conformance/scale/process-group suites,
and no global signal/exit hooks.

No harness integration was added.
