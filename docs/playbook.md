# Porting playbook (derived from agent-id pilot)

A repeatable recipe to port one `agent-*` TypeScript repo to Python + Rust. Each iteration follows these steps.

## Inputs

For each TS repo at `~/Documents/Development/PERSONAL/<name>/`:
- `src/` — source files.
- `SPEC.md` — protocol spec (if present).
- `conformance/*.json` — canonical test vectors (if present).
- `schema/*.json` — JSON Schemas (if present).
- `package.json` — dep + version metadata.
- `LICENSE`, `README.md`.

## Outputs

Two new GitHub repos:
- `p-vbordei/<name>-py` — Python package, `pip install <name>`.
- `p-vbordei/<name>-rs` — Rust crate, `cargo add <name>`.

Each port repo:
1. Reuses the TS `LICENSE`, `SPEC.md`, `schema/`, `vectors/` (renamed from `conformance/`).
2. Passes the same conformance vectors as the TS reference.
3. Has GitHub Actions CI green.
4. README cross-links to the TS reference and the sibling port.

## Step-by-step

### 1. Scaffold both target dirs

```bash
cd ~/Documents/Development/PERSONAL
mkdir -p <name>-py/src/<pkg> <name>-py/tests <name>-py/vectors <name>-py/schema <name>-py/.github/workflows
mkdir -p <name>-rs/src <name>-rs/tests <name>-rs/vectors <name>-rs/schema <name>-rs/.github/workflows

# Copy shared assets
cp <name>/LICENSE        <name>-py/LICENSE
cp <name>/LICENSE        <name>-rs/LICENSE
cp <name>/SPEC.md        <name>-py/SPEC.md  2>/dev/null
cp <name>/SPEC.md        <name>-rs/SPEC.md  2>/dev/null
cp -r <name>/schema/*    <name>-py/schema/  2>/dev/null
cp -r <name>/schema/*    <name>-rs/schema/  2>/dev/null
cp -r <name>/conformance/*.json <name>-py/vectors/ 2>/dev/null
cp -r <name>/conformance/*.json <name>-rs/vectors/ 2>/dev/null
```

`<pkg>` is the Python package name (underscore form, e.g. `agent_id`).

### 2. Python: pyproject.toml template

```toml
[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[project]
name = "<name>"
version = "0.1.0"
description = "<one-line, mentions Python port of @p-vbordei/<name>>"
readme = "README.md"
license = { text = "Apache-2.0" }
authors = [{ name = "Vlad Bordei", email = "bordeivlad@gmail.com" }]
requires-python = ">=3.10"
dependencies = [ ... ]  # minimal, see decision table below

[project.optional-dependencies]
dev = ["pytest>=8.0", "pytest-asyncio>=0.23", "ruff>=0.5", "mypy>=1.10"]

[project.urls]
Homepage = "https://github.com/p-vbordei/<name>-py"
Reference = "https://github.com/p-vbordei/<name>"

[tool.hatch.build.targets.wheel]
packages = ["src/<pkg>"]

[tool.ruff] # line-length 100, py310
[tool.mypy] # strict
[tool.pytest.ini_options] # testpaths = ["tests"], asyncio_mode = "auto"
```

### 3. Rust: Cargo.toml template

```toml
[package]
name = "<name>"
version = "0.1.0"
edition = "2021"
authors = ["Vlad Bordei <bordeivlad@gmail.com>"]
description = "<one-line, mentions Rust port of @p-vbordei/<name>>"
license = "Apache-2.0"
repository = "https://github.com/p-vbordei/<name>-rs"
readme = "README.md"
keywords = [ ... ]
categories = [ ... ]

[dependencies]
serde = { version = "1.0", features = ["derive"] }
serde_json = { version = "1.0", features = ["preserve_order"] }
thiserror = "1.0"
tokio = { version = "1", features = ["macros", "rt-multi-thread"] }   # if async
chrono = { version = "0.4", default-features = false, features = ["std", "serde", "clock"] }
# add others from decision table
```

### 4. Dependency decision table

| Concern | TS package | Python | Rust |
|---|---|---|---|
| Ed25519 | `@noble/ed25519` | `cryptography>=42` (Ed25519PrivateKey) | `ed25519-dalek = "2.1"` + `rand = "0.8"` |
| SHA-256 | `@noble/hashes/sha256` | `hashlib` | `sha2 = "0.10"` |
| BLAKE3 | `@noble/hashes/blake3` | `blake3` | `blake3 = "1.5"` |
| JCS (RFC 8785) | `canonicalize` | `jcs` (pypi) | `serde_jcs = "0.1"` |
| Base58btc | `multiformats/bases/base58` | `base58` (pypi) | `bs58 = "0.5"` |
| CID v1 | `multiformats` | `multiformats` (pypi) | `cid = "0.11"` |
| JSON Schema (2020-12) | `ajv/2020` | `jsonschema>=4.21` | `jsonschema = "0.18"` (let it auto-detect draft) |
| HTTP client | `fetch` global | `httpx>=0.27` | `reqwest = "0.12"` (rustls-tls) |
| HTTP server | `Bun.serve` | `fastapi` + `uvicorn` | `axum = "0.7"` |
| WebSocket | Bun WS | `websockets>=12` | `tokio-tungstenite` |
| CLI | argv | `typer` | `clap = "4"` (derive) |
| DSSE | inline | `cryptography` + manual | manual |
| L402 / Lightning | custom | `pylnd` / LND REST | `lightning-invoke` crate |

### 5. Map TS source files → port files (1:1)

Each `src/<file>.ts` becomes `src/<pkg>/<file>.py` (Python) and `src/<file>.rs` (Rust). Public exports go through `__init__.py` / `lib.rs`. Reuse this exact correspondence for traceability.

### 6. Key idioms

**Python:**
- Use `dataclass(frozen=True)` for value objects.
- `TypedDict` for JSON-shaped objects with reserved keys (e.g. `"@context"`); use functional form for hyphens/`@`.
- `async def` everywhere TS is async.
- Use `serde_json`-equivalent through stdlib + `jcs` for serialization that must match TS canonicalization.

**Rust:**
- `serde_json::Value` for JSON-shaped inputs (preserves byte-deterministic round-trip).
- `serde_json::Map<String, Value>` with `preserve_order` feature for inserting fields in TS-equivalent order before passing to JCS.
- For `iso(now)`: `dt.format("%Y-%m-%dT%H:%M:%S%.3fZ")` mirrors `Date.toISOString()`.
- Async with `tokio`; expose `pub async fn`.
- Errors via `thiserror` enum.

### 7. Conformance test pattern (Python)

```python
# tests/test_conformance.py
import json, re
from pathlib import Path
import pytest
from <pkg> import verify  # or relevant entry point
from <pkg>.types import VerifyOptions

VECTORS = Path(__file__).resolve().parent.parent / "vectors"

@pytest.mark.parametrize("vector",
    [json.loads(p.read_text()) for p in sorted(VECTORS.glob("*.json"))],
    ids=lambda v: f"{v['clause']}-{v['name']}",
)
async def test_vector(vector):
    res = await verify(vector["payload"], VerifyOptions(...))
    assert res.verified == vector["expect"]["verified"]
    for pat in vector["expect"].get("errorMatches", []):
        assert any(re.search(pat, e) for e in res.errors)
```

### 8. Conformance test pattern (Rust)

```rust
// tests/conformance.rs
use std::fs;
use std::path::PathBuf;
use serde_json::Value;

#[tokio::test]
async fn all_vectors_pass() {
    let dir = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("vectors");
    for entry in fs::read_dir(dir).unwrap() {
        let entry = entry.unwrap();
        if !entry.file_name().to_string_lossy().ends_with(".json") { continue; }
        let v: Value = serde_json::from_slice(&fs::read(entry.path()).unwrap()).unwrap();
        // ... run port's verify, assert
    }
}
```

### 9. GitHub Actions templates

`.github/workflows/ci.yml` for both languages — see `agent-id-py` / `agent-id-rs` for the canonical copies. Python matrix runs 3.10–3.13. Rust uses `dtolnay/rust-toolchain@stable` + `Swatinem/rust-cache@v2`.

### 10. README skeleton

- Title with port-language suffix.
- CI badge, spec badge, license badge.
- One-liner: "X port of @p-vbordei/\<name\>. Byte-deterministic-compatible: passes the same conformance vectors."
- 15-line code example.
- "Why this exists" paragraph linking to TS reference.
- Install command.
- Conformance section.
- License.

### 11. Publish

```bash
cd <name>-py
git init -q && git add -A && git -c user.email=bordeivlad@gmail.com -c user.name="Vlad Bordei" \
  commit -q -m "Initial Python port of <name>

Byte-deterministic-compatible with https://github.com/p-vbordei/<name>.
Passes the same conformance vectors."
gh repo create p-vbordei/<name>-py --public --source=. --remote=origin \
  --description "Python port of @p-vbordei/<name> — <one-line>" --push

# Same for <name>-rs
```

### 12. Verification checklist before pushing

- [ ] `uv run pytest -v` green (or `pytest` from venv).
- [ ] `cargo test` green.
- [ ] README links to TS reference.
- [ ] LICENSE present.
- [ ] `vectors/*.json` byte-identical to TS source (use `diff`).
- [ ] `pyproject.toml` / `Cargo.toml` author = "Vlad Bordei <bordeivlad@gmail.com>".

## Per-repo notes (will be filled out as each is done)

- **agent-id** — pilot. Done.
- **agent-cid** — next.
