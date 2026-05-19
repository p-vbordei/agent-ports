# verify scripts

Three layers of confidence — pick based on what you need.

| Script | What it checks | Time | When to use |
|---|---|---|---|
| `verify-ci.sh` | Latest GitHub Actions run per repo | seconds | "is the public state green?" |
| `verify-local.sh` | `pytest` / `cargo test` against the local repo dirs | ~1 min | dev loop, after a change |
| `verify-fresh.sh` | Clone each repo from GitHub into a tmp dir, install, run tests | 10–15 min | "does a new user get green?" — authoritative |

All three accept an optional filter argument:

```bash
./scripts/verify-ci.sh agent-id        # one repo
./scripts/verify-local.sh agent-id     # both -py and -rs
./scripts/verify-fresh.sh agent-phone  # full reclone + retest
```

`verify-fresh.sh --keep` leaves the temp workspace in place for debugging.

Exit codes are uniform: `0` all green, `1` something red, `2` something missing or pending. Wire them into CI by chaining `&&`.

## What "green" means per layer

- **verify-ci.sh**: GitHub's `gh run list` reports `completed:success` for the latest workflow on `main`.
- **verify-local.sh**: every `pytest` / `cargo test` exits 0 with at least one test passing and zero `test result: FAILED` lines.
- **verify-fresh.sh**: same as local, but starting from `git clone --depth 1` (so it catches "I forgot to commit a file" bugs).

## Notes

- `verify-local.sh` reuses each repo's `.venv` if present. Delete it (`rm -rf $repo-py/.venv`) to force a clean install.
- `verify-fresh.sh` writes per-repo logs to `$TMP/<name>.log`. With `--keep`, paths are printed at the end.
- All three scripts cover all 12 base repos × 2 langs, plus `agent-rooms-rs` (no Python port — the source is already Python).
