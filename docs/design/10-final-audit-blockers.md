# 10 — final audit blocker repair

- Manager and kernel now enforce one stdin control in flight: write and close
  are mutually exclusive. Close during write reports `WriteAlreadyPending`.
- Successful close transitions manager/kernel stdin state to closed. Repeated
  close returns `StdinAlreadyClosed` without a kernel call.
- Compiled debug/opt fake-stream races cover false write followed by close and
  drain/error/close outcomes.
- `Final.transportDetail` preserves exact post-start input/process transport
  detail. Buffered `runResult` maps InputTransportFailed to `RunInputError` and
  ProcessTransportFailed to `RunTransportError`.
- Compiled debug/opt run fixtures inject exact `EINPUT`/`EPROCESS` failures and
  assert typed results and details.

No harness integration was added.
