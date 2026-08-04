# 06 — property and execution test plan

## Provenance gate

Pin compiler commit `bb9bad30`, upstream base `48befde1`, compiler SHA-256, Node 24 minor, public package seed SHA-256, package commit, archive SHA-256, and generated debug/optimize worker SHA-256. Run cold isolated overlay and warm-cache builds. Public/private identity collision fails closed. Archive excludes build outputs, credentials, and fixtures not declared for release.

## Layer 1: pure Elm transition model

Generate supervisors, monotonic IDs near exhaustion, operations, requests, modes, limits, deadlines, parent states, and event sequences. Model states include supervisor Creating/Open/ShuttingDown/Closed; registration Prepared/Binding/BoundAwaitingAck/Registered/Unregistering/Absent; operation Starting/Running/Cleaning/Finished; each stream and stdin request state; leader fact; cleanup reason; signal/probe facts.

Properties:

1. IDs strictly increase and never reuse; exhaustion creates no resource.
2. control requires only operation authority; forged/stale IDs are unknown.
3. pre-start has exactly one failure or one start, never both.
4. started operation has at most one final; under fair completion exactly one.
5. first manager-routed Running control event claims reason; later events cannot overwrite it.
6. leader fact and cleanup reason are independent.
7. each accepted Request resolves exactly once.
8. pending or retained-operation demand at EOF returns End; removed operation is unknown.
9. one pending demand per stream and one pending write/close.
10. capture retained bytes <= limit; byte limit + 1 claims overflow.
11. TERM <=1, KILL <=1, exactly configured post-KILL probes unless ESRCH ends early.
12. cleanup observed only from ESRCH; all other exhausted outcomes uncertain.
13. parent start callback cannot precede registration ack.
14. parent slot absent before final callback; failure paths clear it.
15. shutdown rejects new work and empties active state under fair events.
16. no accumulated history is walked on chunk/event transitions.

Use shrinking command sequences and deterministic seed recording.

## Layer 2: deterministic fake kernel and fake parent

Compile the real manager against injected fake verbs/events. Script synchronous throw, async spawn error, spawn success, chunks, EOF, drain, stdin errors, leader exit/close, deadlines, signal return codes, probes, parent ack/failure/timeouts, and teardown acknowledgements.

Assert exact callback traces and manager/kernel/parent registry equality after every step. Exhaustively permute race clusters: cancel/deadline/leader; overflow/EOF; write/drain/error/close; TERM result/grace/probe; KILL/probes; registration ack/shutdown. Run debug and optimize and compare normalized traces byte-for-byte.

Inject Node chunks larger than delivery slices, delayed demand, exact capture boundary, cap+1, and asynchronous stdin failure after a successful write callback. Assert listener/timer/request counts return to zero.

Parent protocol properties cover all six states and the pre-spawn prepare rule. Simulate blocked worker by ceasing worker events; fake parent must reap bound PGIDs and clear ephemeral slots.

## Layer 3: real OS/Node fixtures

On Linux and macOS Node 24, debug and optimize:

- argv/cwd/inherit/merge/replace environment fidelity including spaces and empty values;
- missing executable, EACCES, missing cwd, invalid NUL configuration;
- exit 0 and nonzero as data; signal and unknown leader termination;
- alternating stdout/stderr, 10,000 delayed-demand chunks, EOF demand totality;
- Node `readableLength`, writable length, and RSS measurements under delayed readers/writers;
- exact capture cap and cap+1 overflow with bounded partial output;
- slow stdin, large stdin, EPIPE, error-after-acceptance, close races;
- deadline and explicit cancel races;
- child plus grandchild remain in PGID and ignore TERM: post-KILL no controlled fixture survivor;
- leader exits while in-PGID grandchild remains: cleanup still removes controlled grandchild;
- deliberate setsid escape demonstrates documented exclusion and fixture independently kills/reaps it;
- signal/probe uncertainty injection where permissions permit;
- 1,000 sequential operations and bounded concurrent batches: registries, handles, listeners, timers, and RSS return to thresholds;
- inspect process global listener counts before/after: package added none.

No test says “all descendants” or attempts to prove PGID non-reuse. Assertions are limited to controlled PIDs known to stay in the created group.

## Public API and negative compilation

Compile installed package consumers for every builder/mode/callback in debug and optimize. Negative fixtures prove raw constructors are inaccessible, run cannot select demand/stream stdin, applications cannot import kernel modules, unauthorized authors cannot publish kernel/effect modules, and controls cannot take a Supervisor/PID in place of Operation.

## Differential and audit gate

Before harness integration, compare package buffered results to a small direct Node oracle for argv, bytes, exit, spawn failure, deadline, overflow, and controlled PGID cancellation. This is package-local differential evidence, not harness integration.

Audit report must include command lines, seeds, platform/kernel/Node versions, hashes, peak RSS, buffer observations, controlled PIDs/PGIDs, registry snapshots, listener/timer counts, and known exclusions. Any leaked fixture process fails the suite and is explicitly reaped by test cleanup.

Acceptance requires all three layers, both compiler modes, cold/warm builds, deterministic artifacts, and clean Git status. Example-only tests or compile-only manager evidence are insufficient.
