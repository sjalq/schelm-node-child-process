# 00 — `schelm-node-child-process` feasibility

Status: **feasible with a pull-based Task API; a private push effect manager is not feasible on the pinned compiler.**

## Question proved first

Can Schelm expose an opaque spawned-process handle, incremental stdout/stderr,
waiting, and cancellation through real Elm 0.19.2 kernel code, in both debug and
optimized output, without routing child-process policy through harness JS?

Yes, with an important boundary:

- kernel Tasks can return an opaque `Process`, block on one stream chunk, cache
  and return one terminal result, and send a signal to the child/process group;
- ordinary Elm can turn those blocking reads into messages with `Task.attempt`
  and reader loops;
- this compiler fork authorizes `sjalq/*` kernel packages, but it **does not**
  authorize private `effect module`s. A Gren-like `Cmd`/push event manager is
  therefore unavailable unless the compiler receives a separate, reviewed
  authorization change.

The v1 design must use Tasks and opaque handles. It must not pretend that a
private effect manager compiled.

## Real executable fixture

The feasibility-only files are:

- `src/Schelm/Node/ChildProcess/Feasibility.elm`
- `src/Elm/Kernel/SchelmChildProcess.js`
- `fixtures/feasibility/src/Main.elm`
- `fixtures/feasibility/run.cjs`

They prove the mechanism, not the final API. The fixture:

1. spawns Node with an argv array;
2. receives independent three-byte stdout and stderr chunks through blocking
   kernel Tasks;
3. waits for a nonzero exit and receives `{ code = 7, signal = "" }` as data;
4. attempts a nonexistent executable and receives spawn failure `ENOENT`;
5. spawns a long-running process, sends `SIGTERM` to its Unix process group,
   and waits for the same cached terminal result;
6. compiles and executes in debug and `--optimize` mode.

Observed successful output in both modes:

```text
"spawn-failed:ENOENT"
{"exit":-1,"signal":"SIGTERM"}
"stdout:3"
"stderr:3"
{"exit":7,"signal":""}
FEASIBILITY_OK_DEBUG_OPTIMIZE
```

The optimized run exposed a genuine kernel concern: raw JavaScript records do
not automatically retain Elm record field names after optimization. The proof
was corrected to cross the kernel boundary as `_Utils_Tuple2`, then construct
the public Elm record in ordinary Elm. The production design therefore allows
only stable kernel representations (tuples, custom constructors deliberately
imported in the kernel header, and documented opaque tokens), never guessed Elm
record layouts.

## Compiler/effect-manager result

A minimal package-local effect module was attempted with the same pinned
compiler. It failed with the compiler's explicit boundary:

```text
INVALID EFFECT MODULE
It is not possible to declare an `effect module` outside the @elm organization
```

This is not a Node limitation and not solved by the Schelm kernel-author patch.
The patch authorizes private kernel imports; it intentionally does not broaden
Elm effect-manager authorship.

Consequences:

- no v1 `spawn : ... -> Cmd msg` that pushes `Stdout`/`Stderr`/`Exited` from a
  package-owned effect manager;
- no package-owned `Sub` stream;
- streaming is a pull protocol: at most one outstanding read per pipe;
- applications build reader loops with `Task.attempt`, which naturally provides
  acknowledgement/backpressure;
- the package may offer a fully buffered `run` Task implemented in the kernel,
  because draining both pipes concurrently is a Node mechanism rather than an
  Elm effect-manager requirement.

## Feasibility state machine proved

The fixture uses this reduced process state:

```text
Spawning
  ├─ Node "spawn" ─> Live
  └─ Node "error" ─> SpawnFailed (terminal)

Live
  ├─ stdout read pending ─> chunk | EOF | read failure
  ├─ stderr read pending ─> chunk | EOF | read failure
  ├─ wait pending
  ├─ terminate ─> signal process group
  └─ Node "close" ─> Exited (cached terminal)

Exited
  ├─ wait ─> same cached terminal
  ├─ read ─> remaining queued chunk(s), then EOF
  └─ terminate ─> no-op
```

`close`, not `exit`, is the terminal observation because Node documents `close`
as occurring after the stdio streams close. Production must still tolerate
`error`, `exit`, and `close` races and claim one terminal exactly once.

## What remains unproved by the fixture

These are design/implementation obligations, not claims of completed code:

- stdin write/drain backpressure and close races;
- byte and chunk bounds under adversarial producers;
- TERM → grace → KILL timer races;
- killing descendants rather than only the immediate child;
- supervisor-wide cancellation on harness worker shutdown/EOF;
- Windows tree termination;
- generated state-machine/property tests and harness differential evidence.

## Decision

Proceed to design and hostile review with a Task-based API. Do not begin the
production implementation yet. Keep these fixtures as compiler/runtime evidence
until production fixtures supersede them.

A future compiler change could authorize `sjalq/*` effect modules, but v1 does
not depend on that possibility.

## Reproduction environment

- compiler: private Elm 0.19.2 build from
  `feat/schelm-kernel-author` (`bb9bad30` inspected);
- baseline tag: official `48befde1`;
- runtime: Node `v24.4.1`;
- isolated package overlay prepared from the already pinned Schelm toolchain;
- builds: debug and `--optimize`, both executed, not compile-only.

The exact fixture command is intentionally not yet promoted to a release build
script; implementation work will replace it with the package's reproducible
cold/warm overlay tooling.
