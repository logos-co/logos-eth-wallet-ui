# Ethereum wallet UI

The Ethereum wallet is a portfolio over a device-wide chain scope, backed by the single
`eth_wallet_backend` composer. Tokens and Activity span every enabled chain in that scope;
Send uses an explicit UI-local chain picker. The composer itself has no active-chain setting.

Five sections keep daily work separate: Tokens, Send, Receive, Activity and Settings.
The header always shows the selected account and portfolio scope. Send always names the
network that will receive the transaction, and every multi-chain token, balance and activity
row carries its own network label.

## Scope and refresh model

The Networks settings screen controls two registry facts through the composer:

- device scope: `mainnets`, `testnets`, or `both`;
- the enabled switch for each configured chain.

Changing either refreshes the portfolio and chooses a valid local cursor if the old one left
scope. It does not write a global active chain. A registry generation witness prevents a
re-entrant, stale `list_networks` reply from overwriting a newer choice.

Balances arrive as per-chain results. A healthy chain remains visible when another is blocked
or unreadable; the failed chain gets an explicit row rather than being rendered as zero.
Activity is filtered by the same scope and each transaction retains its recorded `chainId`.
The Tokens toolbar can refresh balances on demand. It enters the same single-flight lane as
automatic token, account and network updates, so repeated requests coalesce instead of
starting concurrent portfolio reads.

Every asynchronous reply is checked against the account, chain and request it names before it
can reach the screen. Selection changes withdraw narrower data first, so a previous account or
chain is never shown under the new heading. Unknown values render as an em-dash, not zero or
an empty assertion.

## Assets and amounts

An asset is identified by `(chainId, contract)`, with a reserved native identity per chain.
A symbol is only a label: two contracts, or the same contract address on two chains, never
share UI identity. Token detail, ordering, Send selection and object names all use the
chain-aware key.

The UI does no amount scaling. Raw values, exact decimal strings and bounded display strings
come from the asset/composer layer. JavaScript numbers are never used for 256-bit amounts.
Sorting by balance means each asset's own exact token amount; it is not fiat-value sorting and
the UI does not contact a price service.

Token membership is device-wide and belongs to the Token Lists UI. Wallet Settings hands off
through the `evm.token_lists.configure` intent; this UI does not search the catalogue or enable
and disable tokens itself. Changes announced by the composer refresh the portfolio.

## Sending

Every wallet send includes `chainId`, `from`, `to`, an exact `amountUnits` or base-unit
`amount`, and an asset symbol/address. The selected chain must be enabled and in scope. The
backend resolves and builds the transfer through `evm_assets_module`, while
`tx_sender_module` owns fee checks, nonce reservation, approval and broadcast.

Backend refusals are shown beside the control or review that caused them. A
`verified_blocked` response remains a structured safety outcome; the UI does not turn it into
a generic transport failure.

A pending send is polled through `send_status` until the sender says `final`, and on nothing
else: a refusal that may yet pass is asked again, never taken as the end of the send. A
`stuck` broadcast — sent, never answered, possibly on chain — is titled "Not confirmed", not
"Not sent". Cancel is refused once the broadcast is claimed; the send then ends however the
poll says.

Send opens a review before the signer is asked: what leaves, to whom, on which network, the
most it can cost, the fee ceiling and the nonce, and the one transaction. Only its Confirm
submits, and a refusal stays on it beside its reason. Another app's request is reviewed in the
same dialog. The fee tiers, the fee summary, the Advanced fields and the review come from
[logos-evm-tx-kit](https://github.com/logos-co/logos-evm-tx-kit), vendored in `src/qml/kit`;
CI checks the copy against the commit in `src/qml/kit/VERSION`.

A nonce that holds up later sends is named above the tabs, one line per chain: the lowest
nonce still waiting, once it has waited three minutes with a later send queued behind it, or
has stalled on its own. A number the sender reserved and never sent (`strandedNonces`) counts
too, once a send has waited on it. For a transfer this wallet can rebuild from the row's
`meta`, "Resend with current fees" prices it again, pinned to that nonce, and opens it for
review; Resend sends it. The fees are the Market tier's, raised where needed to more than the
pending transaction's and at least 10% above it on both fields, the minimum a node needs to
accept a replacement. The receipt is re-read first, so a row that mined after the sender
stopped asking is not resent. Another app's call and a gap get a hint instead: replace it from
Send with the nonce under Advanced. A row whose nonce another transaction mined reads
"replaced": tx_sender settles it so itself, and for a sender that predates that status the
wallet sees it from another row at the same nonce.

The app also provides the `evm.transactions.send` intent for QML-only dapps. A request may
name any enabled in-scope chain, even when it differs from the wallet's current Send cursor.
The review names that requested network and every call before the signer sees it. Out-of-scope
chains and inconsistent payloads are refused before approval. The app is answered once, when
the send is final: `ok` with every hash for a broadcast, otherwise the sender's status word as
the error. Basecamp's broker passes an error code it does not know — `stuck` is one — to the
app as `failed`, without the data that carries the reason.

## Accounts and secrets

The UI holds no secret. It reads the keystore's account inventory, labels and wallet
provenance through the composer. Passwords are handled only by `evm_signer_ui`; seed phrases
and imports belong only to `evm_keystore_ui`.

Receive encodes the selected EIP-55 address locally as a QR code. It includes no amount and
does not contact an explorer. No screen links account or transaction data to a third-party
explorer.

## Verification disclosure

`eth_rpc_module` labels balance replies with the route actually used. Only `verified` means
proof-backed, so the header says **Balances verified**, not a generic “Verified”. Forwarded
fee and receipt reads are disclosed where they appear. The selected-chain verdict is shown in
the header; failures belonging to other portfolio chains stay attached to those chain rows.

## Testing

The local tables execute the pure state transitions, scope guards, intent validation, the
send-status rule, the stuck-nonce rule and its replacement pricing, token identity, sweep
behavior and QR encoder:

```bash
./doctests/run_tables.sh
python3 doctests/assert_ui.py --grep-only
```

View probes run automatically when a Qt Quick runtime is available and otherwise skip with a
clear message. `doctests/eth-wallet-ui-e2e.test.yaml` builds the actual plugin and its seven
core modules, including `evm_assets_module`, then checks the empty-wallet UI through the QML
inspector.

## Build

```bash
nix build .#lgx-portable
nix build .#install
```

Icons in `src/qml/assets/` are local UI resources. The `metadata.json` icon is packaged for
host chrome and is a separate mechanism.
