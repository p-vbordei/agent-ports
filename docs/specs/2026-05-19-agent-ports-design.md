# Porting the `agent-*` Bun family to Python and Rust

**Status:** draft for approval
**Date:** 2026-05-19
**Author:** Vlad Bordei

## Goal

Re-implement the 12 TypeScript/Bun repos under `p-vbordei/agent-*` in both Python and Rust, producing 24 new repos that are **byte-deterministic-compatible** with the TypeScript reference for all serialization-critical surfaces (JCS, CIDs, DSSE envelopes, transcript hashes, DID-doc construction, VC proofs).

This is not a transliteration. The result must be idiomatic in each language. The contract is shared **conformance vectors**, not shared code shape.

## Scope

### In scope (12 repos × 2 languages = 24 new repos)

| # | Repo | LOC (TS) | Network | Notes |
|---|---|---:|---|---|
| 1 | agent-id        | 463 | no  | Pilot. did:key + did:web + capability VC + eddsa-jcs-2022. |
| 2 | agent-cid       | 388 | no  | CIDv1 + JCS + Ed25519 artifact manifest. |
| 3 | agent-scroll    | 263 | no  | Byte-deterministic transcript format + Merkle hash. |
| 4 | agent-toolprint | 347 | no  | DSSE + JCS receipts for tool calls. |
| 5 | agent-rerun     | 554 | no  | Reproducibility seed bundles. |
| 6 | agent-launch    | 566 | no  | CHANGELOG/README → social drafts. |
| 7 | agent-publish   | 499 | yes | npm + GitHub release publisher. |
| 8 | agent-fleet     | 465 | yes | OSS maintainer bot (single-binary CLI). |
| 9 | agent-phone     | 764 | yes | Noise-XK over WebSocket, DID-bound. |
| 10 | agent-pay      | 792 | yes | L402 + Lightning + DID-signed invoices. |
| 11 | agent-ask      | 621 | yes | Federated Q&A protocol (HTTP). |
| 12 | agent-rooms    | multi | yes | Multi-package (backend/cli/plugin/conformance). Done last. |

### Out of scope (for now)
- Non-`agent-*` repos (NuitClaw, solar-*, hermes-*, etc.).
- Replacing the TS reference. TS remains the reference; ports are first-class peers.
- New protocol features. Ports target the **current** version of each TS repo as of 2026-05-19.

## Non-goals

- 100% line-by-line equivalence.
- Identical public function names. Use language-idiomatic naming.
- Backwards compatibility shims between language ports.

## Architecture

### Per-port repo layout

**Python** (`<name>-py`):
```
<name>-py/
├── pyproject.toml              # uv + hatchling; deps minimal
├── src/<pkg>/
│   ├── __init__.py             # public API re-exports
│   ├── jcs.py                  # if needed
│   ├── keys.py                 # ed25519 via `cryptography`
│   ├── ...                     # mirrors TS src/ structure
│   └── cli.py                  # if TS has a CLI (uses typer)
├── tests/
│   ├── test_*.py               # pytest, mirrors TS tests/
│   └── conformance/            # symlink or copy of ../vectors/<repo>/
├── vectors/                    # canonical JSON vectors (shared with TS + Rs)
├── README.md
├── SPEC.md                     # copied from TS for self-contained discovery
├── LICENSE                     # Apache-2.0
└── .github/workflows/ci.yml    # pytest + ruff + mypy
```

**Rust** (`<name>-rs`):
```
<name>-rs/
├── Cargo.toml                  # author = Vlad Bordei <bordeivlad@gmail.com>
├── src/
│   ├── lib.rs                  # public API
│   ├── jcs.rs
│   ├── keys.rs                 # ed25519-dalek
│   ├── ...                     # mirrors TS src/ structure
│   └── bin/<name>.rs           # if TS has a CLI (uses clap)
├── tests/
│   ├── conformance.rs          # loads ../vectors/<repo>/*.json
│   └── ...                     # mirrors TS tests/
├── vectors/                    # canonical JSON vectors (shared)
├── README.md
├── SPEC.md
├── LICENSE
└── .github/workflows/ci.yml    # cargo test + clippy + fmt
```

### Conformance vectors are the contract

Every repo that has a `conformance/` directory in the TS source becomes the **canonical test vector set**. Each port copies these vectors verbatim and asserts the same pass/fail outcomes. No vector is modified in a port — if a port disagrees with a vector, the bug is in the port.

For repos without explicit conformance vectors (e.g., agent-launch), we generate vectors during the pilot — fixed inputs → fixed outputs — using the TS implementation as oracle, then check both ports against them.

### Crypto / serialization choices

| Concern | TS | Python | Rust |
|---|---|---|---|
| Ed25519 | `@noble/ed25519` | `cryptography` (RFC 8032 path) | `ed25519-dalek` |
| SHA-256 / BLAKE3 | `@noble/hashes` | `hashlib` / `blake3` | `sha2` / `blake3` |
| JCS (RFC 8785) | `canonicalize` | hand-rolled module in `jcs.py` | hand-rolled module in `jcs.rs` |
| Multiformats / CID | `multiformats` | `multiformats` (pypi) | `cid` crate |
| JSON Schema | `ajv` | `jsonschema` | `jsonschema` crate |
| HTTP server (if any) | Bun's `Bun.serve` | `fastapi` + `uvicorn` | `axum` |
| WebSocket (phone) | Bun WS | `websockets` | `tokio-tungstenite` |
| Lightning (pay) | `lightning` | `pylnd` or LND REST client | `lightning-invoice` |
| CLI | `process.argv` parsing | `typer` | `clap` |

Author metadata follows global rule: **`Vlad Bordei <bordeivlad@gmail.com>`** for all published metadata.

## Methodology

### Pilot phase — agent-id

The pilot does two jobs at once:
1. Ship `agent-id-py` and `agent-id-rs` to GitHub, both passing the existing TS conformance vectors C1/C2/C3.
2. Distill a **porting playbook** (`docs/playbook.md` in this workspace) capturing every decision so the rest can be batched mechanically.

The playbook must answer:
- Concrete dep choices per concern (locked above, may refine during pilot).
- `pyproject.toml` and `Cargo.toml` templates.
- GitHub Actions templates (CI for each language).
- Exact JCS port test (a round-trip vector that exercises Unicode, nested objects, escape edge cases).
- Exact Ed25519 byte equivalence test.
- Conventions for module split, type signatures, error reporting.

### Batch phase — wave by wave

**Wave 1 (no-network, pure crypto/serialization)**: agent-cid, agent-scroll, agent-toolprint, agent-rerun, agent-launch. These mostly reuse the JCS+Ed25519 substrate from agent-id. Each repo: ~30–60 min/language once the playbook is solid.

**Wave 2 (no-network, tool-oriented)**: agent-publish (registry HTTP calls but not server), agent-fleet (calls GH API).

**Wave 3 (network protocols)**: agent-phone (Noise-XK is delicate; test against TS reference over loopback), agent-pay (Lightning — test against a regtest fixture or mock), agent-ask (HTTP server + federation pull).

**agent-rooms**: separate workstream at the end, given its multi-package nature.

### Per-repo workflow (applied identically to every port)

1. Read TS `SPEC.md`, `src/`, `tests/`, `conformance/`.
2. Scaffold target repo with the playbook template.
3. Port public types first (struct/dataclass parity with TS interfaces).
4. Port pure functions (JCS, hashing, signing) and verify byte equivalence against TS-generated vectors.
5. Port verification/issue/protocol logic.
6. Wire conformance test: load `vectors/*.json`, run, assert.
7. Add language-native unit tests for any TS test that exists.
8. Add a minimal CLI if TS has one.
9. CI green locally (`pytest` / `cargo test` + lints).
10. `gh repo create p-vbordei/<name>-{py,rs} --public --source=. --remote=origin --push`.

### Cross-port drift detection

In `agent-ports-workspace/`, a small `verify-all.sh` script (built during pilot) clones the relevant TS repo and both ports, generates fresh test vectors with the TS impl, and confirms both ports still pass. This is the safety net for the batch phase.

## GitHub repo conventions

- Visibility: **public** (matches the TS repos).
- License: Apache-2.0 (copy from TS).
- Description: `Python port of agent-id — <one-line summary>` (or `Rust port…`).
- Topics: copy from TS repo + add `python` / `rust`.
- README header links to the TS reference repo prominently.
- Each port repo is independent — no submodules, no monorepo.
- Initial commit: scaffold. Final commit before push: conformance green.

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| JCS edge cases differ silently | Pilot includes a 50+ case JCS torture-test vector set shared across all 3 langs. |
| Ed25519 signature determinism | Reference impls (`@noble/ed25519`, `cryptography`, `ed25519-dalek`) all use RFC 8032 — verify with shared fixed-input vectors. |
| Network-protocol drift (Noise-XK, Lightning) | Wave 3 each gets a cross-impl loopback test (TS server ↔ Py client, etc.). |
| Scope creep on agent-rooms | Treat as a separate brainstorm; only after first 11 are done. |
| Repo-name collisions | Pre-check `gh repo view p-vbordei/<name>-py` before scaffolding. |
| Cache/lockfile commits leak personal paths | `.gitignore` from playbook excludes `.venv`, `target/`, `__pycache__`, `*.lock` (but **keep** `Cargo.lock` for binaries and `uv.lock` for libraries since uv recommends checking it in). |

## Success criteria

- [ ] 24 GitHub repos published under `p-vbordei/<name>-{py,rs}`.
- [ ] Every port passes the corresponding TS repo's conformance vectors (or generated equivalents).
- [ ] Every repo has green CI on push.
- [ ] Author metadata in published artifacts is `Vlad Bordei <bordeivlad@gmail.com>`.
- [ ] Each repo's README links to the TS reference.
- [ ] agent-rooms-py and agent-rooms-rs added in a follow-up.

## Execution plan (writing-plans will turn this into a step-list)

1. Pilot: agent-id-py.
2. Pilot: agent-id-rs.
3. Extract playbook + templates.
4. Wave 1 ports (5 repos × 2 langs = 10).
5. Wave 2 ports (2 × 2 = 4).
6. Wave 3 ports (3 × 2 = 6).
7. agent-rooms (2).
8. Final sweep: cross-port drift script, README links audit.
