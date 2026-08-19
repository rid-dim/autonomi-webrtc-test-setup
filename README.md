# Autonomi in the browser — WebRTC-Direct, no install, post-quantum, no relays

This repository is the **front door** to a working browser⇆Autonomi path: an
ordinary web page uploads and downloads files on a real Autonomi network over
**WebRTC-Direct**, with **no browser extension, no local daemon, no gateway**,
and **no node relaying anyone else's traffic**. Every chunk is content-verified
and every session is post-quantum encrypted at the application layer.

It ties together two code deliverables (as git submodules) and the design +
evidence that explain them.

```mermaid
flowchart LR
    B["Web page (WASM)<br/>ant-wasm-client"]
    Boot["Bootstrap node<br/>(entry point)"]
    subgraph NET["ant-node with WebRTC listener"]
        PA["responsible<br/>peer A"]
        PB["responsible<br/>peer B"]
    end
    EVM["Arbitrum<br/>(Anvil in devnet)"]
    B -->|"discover close group"| Boot
    B ==>|"direct WebRTC + PQC tunnel<br/>GET / QUOTE / PUT"| PA
    B ==>|direct| PB
    B -->|"pay (external signer)"| EVM
    PA -.->|"verify payment on-chain"| EVM
    classDef g fill:#1b5e20,stroke:#2e7d32,color:#fff;
    class PA,PB g;
```

> **The one idea:** WebRTC is used purely as a browser-reachable UDP
> replacement. A bootstrap connection solves *initial contact only*; the
> browser then discovers the peers responsible for an address and opens its
> **own direct WebRTC connections** to them — fetching, quoting, paying and
> storing directly, exactly like the native client. Load spreads across the
> network; no node carries another node's payload.

## What's here

| Path | What it is | Home |
|---|---|---|
| `ant-node/` (submodule) | The node change: a feature-gated WebRTC-Direct listener + peer discovery, sharing the existing request handler and node identity. **This is the upstream contribution** (ADR-0010). | fork of `WithAutonomi/ant-node`, branch `feat/webrtc-direct-listener` |
| `ant-wasm-client/` (submodule) | The browser SDK + demo webapp: connect, discover, download, upload, pay. Standalone, `wasm-bindgen` based. | its own repo |
| `docs/` | The design and the evidence — start with [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) and [`docs/FINDINGS.md`](docs/FINDINGS.md). | here |
| `ant-client/` | The official CLI, used unmodified as the baseline/oracle for round-trip tests. | clone of `WithAutonomi/ant-client` |

`.janus/` (if present) is the internal project tracker; `docs/` is the
external distillation.

## Status — verified end to end (local devnet, real nodes, Anvil EVM)

- **Download** from Chrome: discover the close group via the bootstrap
  connection, fetch every chunk **directly** from the responsible peers,
  BLAKE3-verify and decrypt in the browser. 5 MiB in **0.46 s** (parallel
  fetch), SHA-256 identical to the source.
- **Upload** from Chrome, **no MetaMask required**: self-encrypt in WASM →
  quotes from the close group (ML-DSA-65 verified) → on-chain
  `approve`+`payForQuotes` (Anvil) → `PUT` with `ProofOfPayment` directly to
  the storing nodes → accepted after their **on-chain** payment verification.
  The native `ant` CLI then downloads the browser-uploaded file
  byte-identically. (A MetaMask payer is wired for interactive use.)

Evidence: [`docs/evidence/`](docs/evidence).

## Run the full loop locally

```sh
# 1. node + CLI (release)
cargo build --release --features webrtc --manifest-path ant-node/Cargo.toml
cargo build --release --manifest-path ant-client/Cargo.toml
cp ant-client/target/release/ant ant-node/target/release/ant-cli   # for scripts/test_e2e.sh

# 2. a local devnet with real nodes, a per-node WebRTC listener, and Anvil
#    (needs foundry/anvil on PATH)
ant-node/target/release/ant-devnet --preset small --enable-evm \
    --webrtc-port 25000 --manifest /tmp/devnet.json --data-dir /tmp/devnet

# 3. build the browser client + serve the demo
cd ant-wasm-client
cargo build --target wasm32-unknown-unknown --release
wasm-bindgen --target web --out-dir web/pkg \
    target/wasm32-unknown-unknown/release/ant_wasm_client.wasm
cp /tmp/devnet.json web/devnet-manifest.json
python3 -m http.server 8080 --directory web    # open http://127.0.0.1:8080
```

On the page: **Manifest laden** → **Datei wählen → hochladen** (pays over
Anvil by default) → the returned address downloads byte-identically, in the
page or via `ant file download <address>`.

## Reading guide

1. [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — the layer model, the
   no-relay design (with diagrams), and the invariants any implementation
   must keep.
2. [`docs/COMPARISON.md`](docs/COMPARISON.md) — classic native
   `ant-client ⇆ ant-node` vs. this browser path, with upload/download
   sequence diagrams.
3. [`docs/POST-QUANTUM.md`](docs/POST-QUANTUM.md) — a map of exactly where
   data is post-quantum secure and where the remaining classical crypto is
   (and why it doesn't touch the data path).
4. [`docs/FINDINGS.md`](docs/FINDINGS.md) — what was verified in code and
   against a real network: the str0m transport choice, the PQC tunnel, the
   bugs found and fixed, benchmarks.
5. `ant-node/docs/adr/ADR-0010-webrtc-direct-browser-listener.md` — the
   proposed design record for the node change.

## Open points / not yet done

- **MetaMask path** is wired but only interactively testable (the Anvil
  payer is the default, no-click path).
- **NAT'd nodes without port forwarding**: ICE signaling (STUN reflector +
  SDP relay + full-ICE answerer) — see ARCHITECTURE. Cone NAT reachable;
  symmetric NAT a deliberate loss. Verifiable end to end only against real
  NAT (loopback exercises the signaling path, not the hole-punch).
- **Large files**: supported both directions via shrunk data maps (verified:
  20 MiB CLI-upload → browser download, 14 MiB browser-upload → CLI download,
  byte-identical).
- **Upstream MR** into `WithAutonomi/ant-node`: needs a Linear issue and
  likely slicing (GET+discovery+ADR → full chunk pass-through+devnet →
  RFC 9443 single-port). The on-chain **ECDSA payment signature** is the only
  non-PQ surface (inherent to Arbitrum; see POST-QUANTUM.md).
- Two `ant-node` e2e integration tests were flaky under heavy parallel load;
  re-check on an idle machine against upstream `main`.
