# 07 — package implementation self-audit

Status: package-local Unix v1 implemented; **harness integration remains blocked**.

## Evidence run

- Installed authorized package manager compiled and executed under private Elm
  0.19.2 compiler `bb9bad30` in debug and optimize.
- Real Node 24 fixture spawned direct argv, observed exit 7 as data, ran
  TERM/grace/KILL/probes, and classified controlled group cleanup as observed
  gone in both modes.
- Builder negative/boundary worker passed debug/optimize.
- Source scan found no package `process.on`/`process.once` global signal hooks.
- Diff BigO scan found no added `acc ++ [x]` or `List.member` accumulator.

## Implementation inventory

- `Schelm.Node.ChildProcess`: opaque builders, separated spawn/run modes, typed
  results/errors.
- `Supervisor`: installed effect manager, monotonic non-reused IDs, operation-
  only controls with explicit callbacks, explicit shutdown.
- kernel: private scalar-ID registry, direct argv/cwd/env, stdin backpressure,
  demand reads, capture bounds, deadline, process-group cleanup probes.
- `ParentAdapter`: protocol-only pre-spawn preparation surface. No harness
  transport or integration exists.

## Honest limitations / audit blockers for integration

The package is broad enough for Unix v1 but the full `06` matrix is not yet
automated in this minimal repository. Before harness integration, add generated
pure-model/fake-kernel suites, macOS CI, 10k chunk/RSS measurements, controlled
in-group grandchild and setsid-exclusion fixtures, async stdin race injection,
archive reproducibility, and parent fake protocol execution. Current smoke tests
are not substitutes for those gates.

Node internal Readable/Writable buffers remain Node-managed; package bounds only
copied capture bytes, one retained write, one pending demand, a 64KiB delivered
slice, and at most one foreign remainder chunk. Cleanup observed means a fixed
probe returned ESRCH, not proof about escaped descendants or timeless PGID
identity.

No harness code was changed. Do not begin integration until the remaining audit
fixtures pass and a package release/provenance commit is pinned.

Additional executed evidence: buffered `run` captured exactly three stdout bytes
and returned leader exit 9 as data in both debug and optimize.
