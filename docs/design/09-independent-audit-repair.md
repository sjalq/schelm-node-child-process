# 09 — independent audit repair

The audit of `6afa809` correctly blocked release. Repairs bind evidence to the
production manager/kernel boundary.

- Compiled `ConformanceMain` imports the real effect manager and ParentAdapter;
  debug and optimize execute under an injected deterministic Node child/stream/
  signal fake and match an independent fixed trace. The trace covers parent
  prepare/bind/ack/unregister, post-start child error, false-return stdin write,
  pending demand/write cancellation, one final, and typed probe count.
- Compiled `DemandMain` uses `Supervisor.demandStdout` against real Node for
  10,000 x 1KiB chunks. Debug/opt assert exact 10.24MB, repeated demand,
  slicing/EOF/final completion, and RSS bounds. The old direct-Node baseline is
  not in the canonical gate.
- Cleanup preserves typed TERM and KILL syscall results plus every fixed probe
  result; observed-gone requires `ProbeGone`.
- Post-start child `error` claims ProcessTransportFailed and enters cleanup;
  pre-start error remains spawn failure.
- False-return stdin writes retain drain/error/close listeners and cancellation
  cleanup. EPIPE/close map to BrokenPipe; cleanup maps to WriteCancelled.
- Kernel cleanup settles pending reads, writes, and close exactly once. Manager
  finalization removes and resolves all operation-owned pending requests before
  the final callback.
- Kernel-internal branching no longer inspects optimization-sensitive Elm
  custom constructor tags; plain JS booleans/errors are converted only at the
  scheduler boundary.

No harness files or transport integration were added.
