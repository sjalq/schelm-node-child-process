# 08 — package-complete Linux audit

V1 operational scope is Linux x64 on Node 24.4.1. macOS was not available for
execution and is therefore unsupported rather than represented by an unexecuted
matrix claim. Windows remains unsupported. Kernel rejects non-Linux before
spawn.

Package gates now execute: 5,000 generated pure lifecycle traces against an
independent event-fold oracle; deterministic six-state parent registration
success/failure/timeout races; fixed cleanup observed/uncertain oracle; real
leader-exit with surviving same-PGID grandchild followed by TERM/KILL cleanup;
deliberate setsid escape with independent cleanup; 10,000 chunks/10.24MB delayed
backpressure with Node readableLength and RSS bounds; 200 non-reused supervisor
allocations in the model and 200 sequential real manager operations in debug
and optimize; builder, buffered run, direct exit, archive, toolchain, and
artifact checks.

Findings fixed during audit:

- cleanup reason initialized too early, preventing overflow precedence;
- cancel/deadline could overwrite prior arbitration;
- quick leader final could race manager insertion;
- final callback reentrancy could start a second operation before removal state
  returned; final notifications are now deferred from the settled state;
- oversized demand chunk remainder is retained and sliced;
- concurrent kernel demand/write is rejected;
- unknown negative leader code maps to ExitUnknown;
- Linux-only platform check replaces an unverified Unix/macOS claim.

Controlled no-survivor means only known fixture descendants that remain in the
created PGID. Setsid escape and numeric PGID reuse remain documented exclusions.
ParentAdapter is a pure, compile-tested protocol; no harness transport or harness
code is integrated.

The immutable gate records compiler commit/hash, upstream base, Node/platform,
generated worker hashes, deterministic archive hash, and clean repository diff.
