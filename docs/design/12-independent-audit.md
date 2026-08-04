# 12 — independent audit status

Verdict: **BLOCKED; do not resume harness integration.**

The 1.1 branch is progressively committed and pushed, and the standalone 1.0
suite remains green through all pre-parented checks. Package docs, debug and
optimized standalone fixtures, model tests, scale tests, process-group tests,
metadata, and reproducible archive generation run.

The new real fake-parent fixture currently exposes an effect-manager ordering
bug: a parent bind completion can be delivered to `Supervisor.onSelfMsg` before
the state returned by the spawning effect has become the manager state. The
observable failure is `Dict.get oid state.active` receiving an undefined manager
state in both debug and optimized artifacts. Adding sleeps only masks the race
and is not acceptable evidence. The fixture correctly prevents declaring the
release audited.

Further blockers against the requested acceptance contract:

- blocked-worker detached-group reap has not yet been proven by a real fixture;
- parent disconnect fan-out over all lifecycle states is not implemented;
- bind rejection currently begins cleanup but its final callback semantics need
  one explicit arbitration path (no `onStarted`, one terminal failure);
- pre-KILL acknowledgement/timeout evidence is not represented in public
  cleanup evidence;
- preparing/binding/unregistering shutdown joins and 200 parented runs are not
  proven;
- the legacy 1.0 compatibility fixture is compile-covered by existing callers,
  but a pinned 1.0 source archive differential has not been added;
- unauthorized-author debug/optimized gate has not been rerun for the 1.1
  archive.

Required repair: model parent binding as manager state before launching the
kernel request (a `Binding` entry distinct from `Active`), return the updated
state immediately, and route only the later response through `SelfMsg`. Do not
use timing delay as synchronization. Then add an explicit cleanup phase type
that owns before-kill and unregister requests, so final is constructible only
from absent registration.

Harness integration must remain paused until these items pass independently.
