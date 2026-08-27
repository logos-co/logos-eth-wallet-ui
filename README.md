# eth_wallet_ui

Send ether on one Ethereum network at a time, with the full set of fee controls.

Information design follows MetaMask: one question per screen, everything else behind a
disclosure. Two tabs (Tokens, Activity), one action (Send), and **the active network visible
at all times** — a user must never be able to mistake which chain they are spending on.
Testnets are visually distinct from mainnet.

## What this module cannot do

It holds no secret. It requests signatures and reads which accounts exist; the vault password
is taken only by `signer_ui`, and seed phrases only ever reach `keystore_ui`. There is no
password parameter anywhere in `src/eth_wallet_ui.rep`, and there never may be.

Validation lives in the backend. Setting a priority fee above the max fee, or sending more
than the balance covers, surfaces the **backend's** refusal verbatim — the UI adds no rule of
its own, so the two cannot drift apart.

## Building

```bash
nix build .#lgx-portable   # the installable package (Basecamp / logosctl)
nix build .#install        # the dev variant, for logos-standalone-app
```

Icons live in `src/qml/assets/` and are local to this module by design. `metadata.json`'s
`icon` is a different mechanism — it packages exactly one 256x256 PNG for the host's own
chrome and is not reachable from the view's QML.
