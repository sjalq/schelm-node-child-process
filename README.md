# schelm-node-child-process

Private Elm 0.19.2 kernel package for supervised Unix child processes on Node 24.

V1.1 preserves the standalone 1.0 API and adds parent-before-spawn reservation, registration-before-start, package-observed PGID facts, and bounded parent reap/unregister hooks.

V1 guarantees a fresh owned Unix process group and TERM → grace → KILL → fixed
post-KILL probes. It does not own descendants that escape with `setsid`/`setpgid`,
does not eliminate numeric PGID reuse races, and does not support Windows
operation. The package installs no global signal handlers; applications must
explicitly shut down supervisors. Nonzero exit is result data.

See `docs/design/05-design-revision-b.md` and `06-property-test-plan.md`.
