# bet0x Valkey Active/Active Fork Audit

Date: 2026-05-06

## Summary

Target: `bet0x/valkey` branch `unstable` at `9b2284900efa42e205e421ed6307019da5b15497`.

State observed:
- Fork is 13 commits ahead and 187 commits behind `valkey-io/valkey:unstable`.
- `valkey-io/valkey#512` remains open with no upstream PR from `bet0x`.
- The implementation is explicitly documented as experimental in `valkey-multimaster-setup.md`.

Verdict: the branch is a promising experimental active/active prototype for a narrow command subset. It builds and its focused tests pass, and a small TLA+ model supports convergence for modeled supported writes. It is not production-ready or upstream-ready without a design document, stronger command gating, clearer semantics for RMW commands, and more persistence/restart coverage.

Fix update: commit `2499712a2` adds pre-execution rejection for local active/active writes that cannot be represented as RREPLAY. The follow-up RMW fix also rejects lossy read-modify-write commands before local mutation. The TLA+ model and simulator now reflect both fixes by modeling unsupported/RMW attempts as rejected no-ops.

## Build And Tests

Environment:
- macOS 26.4.1 arm64
- OpenJDK 21.0.6
- `clang`, `make`, `tclsh` available
- Built binaries: `valkey-server` and `valkey-cli` report git `9b228490`

Build:
- `make -j$(sysctl -n hw.ncpu)` completed successfully.
- Only visible warning was from vendored `linenoise`.
- `git diff --check upstream/unstable...HEAD` reported no whitespace errors.

Focused tests:

| Test | Result |
| --- | --- |
| `unit/rreplay` | 3 passed, 0 failed |
| `integration/replication-active` | 5 passed, 0 failed |
| `integration/replication-multimaster` | 14 passed, 0 failed |
| `integration/replication-multimaster-connect` | 9 passed, 0 failed |
| `integration/replication-multimaster-longrun` | 6 passed, 0 failed |
| `integration/replication-multimaster-rreplay` | 17 passed, 0 failed |
| `integration/replication-multimaster-topologies` | 9 passed, 0 failed |
| `integration/replication-multimaster-upstreams` | 11 passed, 0 failed |
| `integration/replication-psync-multimaster` | 4 passed, 0 failed |
| `integration/multimaster-psync` | 4 passed, 0 failed |
| `integration/psync2-reg-multimaster` | 5 passed, 0 failed |

Total focused result: 87 passed, 0 failed.

Logs are under `audit/logs/test-*.log`.

## Public Surface Added

The branch adds or changes:
- Config: `active-replica`, `multi-master`, `multi-master-no-forward`, `rreplay-pending-max-entries`, `mvcc-rdb-clock-max-entries`.
- Commands: `REPLICAOF ADD`, `REPLICAOF REMOVE`, internal `RREPLAY`, and `MVCCRESTORE`.
- INFO/ROLE output: active replica state, configured upstreams, runtime links, replay tx/rx/ack counters, replay backlog, pending/dropped/fullsync counters, MVCC clock fields, replica UUIDs.
- Persistence: RDB AUX metadata for configured upstreams, upstream runtime, pending replay frames, replay dedupe entries, and MVCC key clocks.

## Formal And Simulation Results

Artifacts:
- TLA+ spec: `audit/formal/MultiMaster.tla`
- TLC configs: `audit/formal/MultiMaster-supported.cfg`, `audit/formal/MultiMaster-unsupported.cfg`
- Simulator: `audit/sim/mm_sim.py`
- Logs/results: `audit/logs/tlc-*.log`, `audit/logs/simulator.json`

TLC:
- Supported-command model: no invariant violations.
- Search size: 675,905 states generated, 159,245 distinct states.
- Checked invariants: type safety, quiescent convergence, no own-origin in-flight messages.
- Unsupported-command model: no invariant violations after modeling unsupported write attempts as rejected no-ops.

Simulator:
- 2,000 randomized supported-command runs, 80 steps each: no convergence failures after draining the network.
- Concurrent `INCR` and unsupported `XADD`/stream-like local write attempts are rejected before local mutation in the fixed model.

## Findings

### Fixed P1: Unsupported Writes Can Permanently Diverge

Pre-fix behavior rejected unsupported commands only at replay-forwarding time. The command had already executed locally through normal command processing, then `replicationFeedPrimaryWithRReplay` logged and returned.

Relevant code:
- `src/server.c:3675` calls `replicationFeedPrimaryWithRReplay` after normal propagation handling.
- `src/replication.c:1693` to `src/replication.c:1720` rejects streams, functions, TTL mutations, flushes, transactions, arbitrary-key commands, and other unsupported commands.
- `src/replication.c:2433` to `src/replication.c:2439` logs "Skipping upstream RREPLAY forwarding" and returns.

Impact before the fix: a user could issue a successful write in active/active mode and receive OK, while peers never received it. The old tests intentionally demonstrated this for `XADD` and `EXPIRE`.

Fix: `processCommand` now rejects unsupported local writes before execution when `active-replica + multi-master` is enabled. Tests now assert that `XADD` and relative `EXPIRE` are rejected and do not mutate either node.

### Fixed P1: Canonicalized RMW Commands Converge But Lose Concurrent Update Semantics

Pre-fix behavior treated read-modify-write commands as risky, executed them locally, then forwarded the resulting absolute value as a deterministic write. That gave convergence, not CRDT-style merge semantics.

Relevant code:
- `src/replication.c:1568` to `src/replication.c:1577` classifies `INCR`, `HINCRBY`, `ZINCRBY`, etc. as risky RMW commands.
- `src/replication.c:1601` to `src/replication.c:1629` canonicalizes string RMW commands to `SET key current-value KEEPTTL`.

Original simulator trace:
1. A runs `INCR ctr`, canonicalized as `SET ctr 1`.
2. B concurrently runs `INCR ctr`, canonicalized as `SET ctr 1`.
3. Both nodes converge to `1`; a commutative counter expectation would be `2`.

Fix: local RMW commands are rejected before mutation in active/active mode. If counters are in scope later, they need a different per-command merge strategy or a type-level CRDT.

### P2: MVCC Clock Persistence Is Capped And Can Lose Stale-Write Protection

RDB persistence stores only the newest `mvcc-rdb-clock-max-entries` key clocks. When the cap is exceeded, older keys lose their MVCC clocks across restart.

Relevant code:
- `src/rdb.c:1550` to `src/rdb.c:1601` caps persisted MVCC key clocks and records dropped entries.
- `tests/integration/replication-multimaster-rreplay.tcl` includes a test where dropped older clocks allow stale `MVCCRESTORE` payloads to win after restart.

Impact: this is a bounded-memory tradeoff, but it weakens stale replay/restore protection for keys omitted from the RDB AUX metadata.

Recommendation: treat this cap as a correctness knob, not merely telemetry. Upstream design should specify whether stale protection is best-effort, durable, or required.

### P2: Upstream Readiness Is Low Despite Passing Lab Tests

The patch is large and invasive: 4,847 insertions across replication, RDB, command metadata, config, INFO/ROLE, and tests. It is also 187 commits behind upstream `unstable` as of this audit.

Recommendation: before PR, split into an RFC/design doc and reviewable stages: command gating/support matrix, RREPLAY wire protocol, MVCC metadata/persistence, topology management, and test/fault-injection harness.

## Test Gaps To Close

Recommended next tests before upstream consideration:
- AOF enabled, AOF rewrite, and restart behavior for MVCC/replay metadata.
- Explicit unsupported-command rejection behavior if the design changes.
- Concurrent RMW semantics tests that encode expected behavior, not only convergence.
- Jepsen-style process kill, link partition, disk persistence, and recovery scenarios.
- Larger meshes and asymmetric partitions, especially with replay queue overflow and fullsync request loops.
- ACL/security checks for internal commands and peer capabilities.
- Rebase onto current upstream and rerun the full replication suite, not only the new focused files.

## Reproduce

```bash
git clone https://github.com/bet0x/valkey.git .
git checkout 9b2284900efa42e205e421ed6307019da5b15497
git remote add upstream https://github.com/valkey-io/valkey.git
git fetch upstream unstable
make -j$(sysctl -n hw.ncpu)
./runtest --single integration/replication-multimaster-rreplay --clients 1 --timeout 120
cd audit/formal
java -cp tla2tools.jar tlc2.TLC -deadlock -config MultiMaster-supported.cfg MultiMaster.tla
cd ../..
audit/sim/mm_sim.py --runs 2000 --steps 80
```
