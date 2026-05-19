# agent-ports

Meta-repo for the multi-language port of the [`agent-*`](https://github.com/p-vbordei?tab=repositories&q=agent-) protocol family.

The 12 TypeScript/Bun reference repos at `p-vbordei/agent-*` each ship with a Python and a Rust port (one exception: `agent-rooms` is already Python, so only a Rust port exists). Every port is byte-deterministic-compatible with its TypeScript reference for serialization-critical surfaces — JCS canonical encoding, Ed25519 signatures, CIDv1 strings, Noise-XK handshake bytes, DSSE envelopes.

## The matrix

| # | Protocol | TypeScript reference | Python port | Rust port |
|---|---|---|---|---|
| 1 | DID + capability VC | [agent-id](https://github.com/p-vbordei/agent-id) | [agent-id-py](https://github.com/p-vbordei/agent-id-py) | [agent-id-rs](https://github.com/p-vbordei/agent-id-rs) |
| 2 | Content-addressed manifest | [agent-cid](https://github.com/p-vbordei/agent-cid) | [agent-cid-py](https://github.com/p-vbordei/agent-cid-py) | [agent-cid-rs](https://github.com/p-vbordei/agent-cid-rs) |
| 3 | Byte-deterministic transcript | [agent-scroll](https://github.com/p-vbordei/agent-scroll) | [agent-scroll-py](https://github.com/p-vbordei/agent-scroll-py) | [agent-scroll-rs](https://github.com/p-vbordei/agent-scroll-rs) |
| 4 | Reproducibility seed bundle | [agent-rerun](https://github.com/p-vbordei/agent-rerun) | [agent-rerun-py](https://github.com/p-vbordei/agent-rerun-py) | [agent-rerun-rs](https://github.com/p-vbordei/agent-rerun-rs) |
| 5 | DSSE tool-call receipts | [agent-toolprint](https://github.com/p-vbordei/agent-toolprint) | [agent-toolprint-py](https://github.com/p-vbordei/agent-toolprint-py) | [agent-toolprint-rs](https://github.com/p-vbordei/agent-toolprint-rs) |
| 6 | Release announcement drafter | [agent-launch](https://github.com/p-vbordei/agent-launch) | [agent-launch-py](https://github.com/p-vbordei/agent-launch-py) | [agent-launch-rs](https://github.com/p-vbordei/agent-launch-rs) |
| 7 | Multi-registry publisher | [agent-publish](https://github.com/p-vbordei/agent-publish) | [agent-publish-py](https://github.com/p-vbordei/agent-publish-py) | [agent-publish-rs](https://github.com/p-vbordei/agent-publish-rs) |
| 8 | OSS-maintainer bot | [agent-fleet](https://github.com/p-vbordei/agent-fleet) | [agent-fleet-py](https://github.com/p-vbordei/agent-fleet-py) | [agent-fleet-rs](https://github.com/p-vbordei/agent-fleet-rs) |
| 9 | Federated Q&A | [agent-ask](https://github.com/p-vbordei/agent-ask) | [agent-ask-py](https://github.com/p-vbordei/agent-ask-py) | [agent-ask-rs](https://github.com/p-vbordei/agent-ask-rs) |
| 10 | Noise-XK RPC | [agent-phone](https://github.com/p-vbordei/agent-phone) | [agent-phone-py](https://github.com/p-vbordei/agent-phone-py) | [agent-phone-rs](https://github.com/p-vbordei/agent-phone-rs) |
| 11 | L402 + Lightning | [agent-pay](https://github.com/p-vbordei/agent-pay) | [agent-pay-py](https://github.com/p-vbordei/agent-pay-py) | [agent-pay-rs](https://github.com/p-vbordei/agent-pay-rs) |
| 12 | Parley rooms (already Python) | [agent-rooms](https://github.com/p-vbordei/agent-rooms) | (source is Python) | [agent-rooms-rs](https://github.com/p-vbordei/agent-rooms-rs) |

**Total**: 23 port repos, all public, all CI-green.

## Layout

```
agent-ports/
├── README.md                    you are here
├── docs/
│   ├── specs/
│   │   └── 2026-05-19-agent-ports-design.md   the original design spec
│   └── playbook.md              repeatable port recipe + gotchas
└── scripts/
    ├── README.md
    ├── verify-ci.sh             query GitHub Actions for each repo
    ├── verify-local.sh          run tests against local clones
    └── verify-fresh.sh          fresh clone + retest (authoritative)
```

## Verification

```bash
# Fastest: GitHub Actions status (seconds)
./scripts/verify-ci.sh

# Local: run tests against the repos in ~/Documents/Development/PERSONAL (~1 min)
./scripts/verify-local.sh

# Authoritative: clone everything fresh and rebuild (~15 min)
./scripts/verify-fresh.sh
```

Each script accepts a filter: `./scripts/verify-local.sh agent-id` runs just `agent-id-py` and `agent-id-rs`.

## Conformance contract

Every port that has TypeScript conformance vectors passes them byte-for-byte:

- **JCS canonical encoding** matches RFC 8785; integers above 2^53 lose precision per ECMA-262 ToString (see `docs/playbook.md` for the `serde_jcs` Rust gotcha and the `normalize_numbers` workaround).
- **Ed25519 signatures** are RFC 8032; every port uses an audited library (`@noble/ed25519` / `cryptography` / `ed25519-dalek`).
- **CIDv1 strings** are bit-identical: raw codec (`0x55`) + sha256 multihash (`0x12 0x20 …`) + base32 lowercase, no padding, multibase prefix `b`.
- **Noise-XK** wire bytes are identical across TS / Python / Rust (`agent-phone`): all three implementations port the same X25519+ChaCha20Poly1305+BLAKE2s+HKDF construction the TS reference uses.

## License

The meta-repo content (specs, playbook, scripts) is Apache-2.0. Each port repo carries its own LICENSE matching the upstream TypeScript reference (Apache-2.0 for all of them except `agent-rooms-rs`, which is AGPL-3.0-or-later to match the parley source).
