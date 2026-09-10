# eth_wallet_ui

Send ether on one Ethereum network at a time, with the full set of fee controls.

Information design follows MetaMask: one question per screen, everything else behind a
disclosure. Three sections (Tokens, Send, Activity) and **the active network visible
at all times** — a user must never be able to mistake which chain they are spending on.
Testnets are visually distinct from mainnet.

## What this module cannot do

It holds no secret. It requests signatures and reads which accounts exist; the vault password
is taken only by `evm_signer_ui`, and seed phrases only ever reach `evm_keystore_ui`. There is no
password parameter anywhere in `src/eth_wallet_ui.rep`, and there never may be.

## What the chip claims

`eth_rpc` labels every reply with a `route`, and only `verified` means proof-backed. On this
screen that is the balances alone: an Activity status is an `eth_getTransactionReceipt` and a
Send fee is `eth_feeHistory` / `eth_gasPrice` / `eth_estimateGas`, all forwarded to the
proxy's own execution provider on trust. So the header chip reads **Balances verified** —
never a bare "Verified" — and it says that only when `balancesRoute` really came back
`verified`, not when the proxy merely reports `ready`. Its other two states are
**Verification unknown** (the verdict could not be read) and **Not verified**. The figures
that were only forwarded say so where they are shown, on the Activity tab and in Send.

Validation lives in the backend. Setting a priority fee above the max fee, or sending more
than the balance covers, surfaces the **backend's** refusal verbatim — the UI adds no rule of
its own, so the two cannot drift apart. Those refusals render **beside the control that caused
them**, in the Send section: the wallet's own error line sits above the tab bar, so a send
refused after a scroll down to Advanced would report itself off-screen. The section is left
on `pendingRequestId`, never on the click, so a submit that was refused stays on screen with
its reason.

## What a figure on screen belongs to

Every balance, transaction row, token, quote and route label means something only against the
account **and** network it was read under. When either moves, everything narrower than the new
selection is withdrawn before the new selection is published, and the view shows an em-dash —
never a zero, never "none", and never the previous selection's number for the few hundred
milliseconds the re-read takes.

That is one rule in one place. `enterScope` in `src/eth_wallet_ui_scope.h` performs the
withdrawal on a plain struct, and the backend reaches it only by **overriding** the two
generated selection setters onto it: a handler that publishes an account or a network gets the
withdrawal whether it asked for it or not. Remembering to clear in each handler is what
produced the defect this replaces — `setActiveChain` cleared and `selectAccount` did not.

The same shape carries every *reply*. `src/eth_wallet_ui_apply.h` holds one pure transition per
reply — balances, history, tokens, fee tiers, the quote, the verdict, the send — each taking the
scoped state and the reply and returning the state the view should show, **with its own guard
inside it**. `EthWalletUiBackend` snapshots, calls one, and publishes; `publishScope` is the
only writer of a scoped property in the whole file, and `doctests/assert_ui.py` asserts that as
an absence. So no scoped value reaches the screen except through a rule some table row ran.

The generation counter drops an in-flight *reply* for a selection the view has left. It is not
enough on its own, and cannot be: it only knows about moves the view **made**. `eth_wallet_backend`
is `concurrency: "multi"`, so a synchronous call into it runs a nested event loop and pumps async
replies inline — which is how a balances reply for the chain just switched *to* arrives while the
counter still matches, putting one network's number under another's name.

So every reply is checked against the scope it **names**, which is the half the counter cannot
know. `get_balances` and `get_history` name `chainId` and `address`, `list_tokens`, `suggest_fees`
and the verified-proxy verdict name `chainId`, and a quote names `chainId` and `from`.
`answersFor` in `src/eth_wallet_ui_scope.h` refuses a payload naming another account or chain,
and refuses a *successful* payload naming neither — an answer that cannot be attributed is not
evidence about the selection on screen. A refusal names nothing by design and is this call's own
answer, so it still lands. `active_chain_changed` names the new chain and is taken rather than
discarded, so the move is adopted before any reply for the network being left can be accepted.

The **producer** of the selection is checked the same way, and for a sharper reason: its write
*is* `shown()`, the thing every one of those checks is made against. `get_active_network` is
slow by construction and spins the event loop, so a network picked in Settings is adopted
re-entrantly and would then be overwritten by the answer computed before it — putting the chain
back, and turning every correct reply for the network the wallet is really on into a refusal.
One stale write to `shown()` does not show one wrong value; it inverts every other check on the
screen. So the read takes a witness first and publishes only if the selection stood still, and
`list_networks` — the later of the two reads — carries `activeChainId`, which is what decides
the chain when this view was never told the move happened.

The Send figures carry one dimension more: the quote is scoped by account, chain, token **and
request**, and the wire echoes no request. So the view stamps the one it priced —
`quoteRequestJson` — and renders a figure only while that still equals the request the form
describes. The re-price hangs off the request itself rather than off each control, because a
control handler is exactly what a change can go around: clearing the amount used to call
nothing, withdraw nothing, and leave the previous request's gas limit, ceiling and nonce on
screen with **Submit still armed**.

The view checks its own half too, rendering a scoped figure only while `scopedDataFresh` says it
describes the selection on screen. A spinner appears only where a value is both unknown **and**
being read; a read that failed falls back to the em-dash, because a spinner that never stops
reads as a hang.

Within one selection two replies can name the *same* account and chain, so `answersFor` cannot
separate them and the in-flight **ticket** does: a claim whose deadline lapsed applies nothing,
drains nothing and clears no spinner, because the call that replaced it is still running. The
claim is also strictly longer than the calls under it — one that lapses at the instant its own
call times out is not guarding it — and when it does lapse it runs the re-run queued behind it,
which otherwise lives only in a flag a lost callback never drains.

Two paths are guarded this way, balances+history and the quote, and for twelve passes they were
written twice: every fix landed on the data path and none of the three reached its twin. So the
protocol is now written once, as `AsyncLane` in `src/eth_wallet_ui_guard.h` — take, own,
hand on — and both paths enter it through `beginLane` and leave through `handOnLane`. The
budgets come from one formula, `guardBudgetMs(legs)`, so no claim can be written with no margin
at all.

An **unknown** value matches nothing, and never everything: `(a || "") === (b || "")` answers
true about two absent values, which is how a token page with no entry for its symbol came to
list every native transaction on the account rather than none. Case-folded comparison goes
through one helper whose absent case is explicit, and the shape itself is banned in `0g`.

Two events carry less than they need to, and are named here rather than papered over:
`balances_updated` names the account but **not** the chain, so it is only half a scope check —
a change on a chain that is not on screen still costs one re-read. `tx_status_changed` names a
hash and no scope at all, so it cannot be filtered; the re-read it triggers is checked by the
appliers instead.

**Nothing this view writes is re-read on its own reply.** `set_token_enabled` and
`set_token_sort` now announce, so the callback that used to re-read is gone: `tokens_changed`
moves both listings and `token_sort_changed` adopts the order. That is not a tidy-up. The
re-read wired to the reply fired for this view's own press and for nothing else, so a custom
token imported into `token_list` by another app never reached the Manage-tokens screen.

`networks_changed` closes the same hole one level out. `eth_rpc` is configured from
`eth_rpc_ui`, a different app, and `applyVerdict` **stops** the verdict poll on a confirmed
`off` — so before this event, a user turning verification on elsewhere would never be shown
here. The refresh it triggers carries the verdict inline and restarts the poll.

The poll itself stays: proxy **health** moves with no event behind it, and that is exactly what
the verdict for a `required` chain turns on.

## Money

There is exactly one amount formatter and it is in the backend, where the arithmetic is exact
256-bit integer work. This view does no scaling at all: every figure on screen is a string the
backend already composed, looked up by key. Two resolutions are published per amount —
`…Display` is bounded (only an **exactly** zero balance renders `0`; real dust renders
`<0.00001`) and `…Exact` carries every digit. Lists and titles use the bounded one, detail
screens use the exact one, and an amount whose decimals were never recorded emits **no key at
all**, which is an em-dash. "We could not read it" is not "you have none".

Amounts are entered and shown in **token units** — `0.1` ETH, never `100000000000000000`. The
advanced fee overrides are the one deliberate exception: `maxFeePerGas` and the priority fee
are prices per unit of gas, so wei is the correct unit and their placeholders say so.

## What a token IS

A token is its **(chain, contract)**. It is never its symbol: a symbol is a label anyone may
deploy a contract wearing, and the bundled Uniswap snapshot already carries five
`(chainId, symbol)` pairs answered by two different contracts — on chain 1, `LIT` is both
Litentry `0xb594…9723` and Lighter `0x232C…4Ee2`, at eighteen decimals each. Holding both is
ordinary.

So `tokenKey()` is the one identity in this view: the contract, case-folded, and the reserved
key `native` for the chain's own currency, which has no contract. Everything keys on it — the
balance lookup, the list's order map, the detail screen, the Send picker, the Manage rows, and
**every `objectName`**. Keyed on the symbol instead, one token's row showed the other's
balance, a real holding rendered as an em-dash on the row that owned it, the second contract's
detail screen was unreachable, `tokenRow_LIT` named whichever rendered last, and the order map
was last-write-wins — which collapsed the pair onto one position, made the comparator answer
`0` for it, and let Qt's unstable sort reshuffle the whole order the backend had published.

The wire says it too. A send carries `tokenAddress` — the contract, exactly — beside `token`,
which stays the symbol; the backend resolves the address first and **refuses** a symbol two
enabled contracts share rather than guessing. `prepare_send` answers with the contract it
resolved, and the Send screen states it wherever the symbol settles nothing, in the error
colour if it is not the contract the picker chose.

And a reader has to be able to tell two of them apart, not just the wallet: wherever both can
appear together, a row carries its name and enough of its contract to distinguish it. Only
where the symbol is shared — an address on every row is noise, and `LIT (2)` names neither.

A token is also enabled **per chain**, and `list_available_tokens` names the chain it answered
for, so a network change withholds every row on the Manage tokens screen. The chain can move
without that screen doing anything — the backend adopts the network it is really on — so the
view re-runs the **current query** when it does. Without that the screen sat on its "does not
know" em-dash permanently, recovering only if the user typed. It re-runs the query rather than
the empty one: resetting to the whole offered set throws away what they were looking for. The
screen has to be open for the call to go out; reopening it reads the whole set anyway.

## Sorting the token list

Two orders, chosen from a small control above the list and persisted by the backend:
**Alphabetically (A-Z)** and **Declining balance**. The sorting itself is the backend's —
`get_balances` answers a row for every enabled token, already in the persisted order, because
comparing eighteen-decimal amounts is exact 256-bit work and belongs where a table can run it.
The view asks with `set_token_sort`, reads `tokenSort` back off the published scope, and
renders the order it is handed; an order it does not know is shown as no order at all.

The persisted order is **adopted from whichever listing lands first**. `list_tokens`,
`get_balances` and `list_available_tokens` all echo `tokenSort`, and the first two run on every
refresh — so an ordinary launch restores the order the user chose. Reading it off the catalogue
search alone, as this once did, meant the Tokens tab opened in the default order unless the user
happened to go into Manage tokens and type.

Three readers means one hazard: a listing issued under the previous order can land after the
user has picked a different one, naming the order they just replaced. So every read captures a
choice counter when it goes out, `chooseTokenSort` bumps that counter **before** its call — the
call is synchronous into a `multi` backend and pumps the event loop — and a reply older than the
last choice may not speak for the order at all.

MetaMask's own label for the second one is "Declining balance ($ high-low)". There are no
prices here and there will not be — a price feed is told which tokens to quote, which is the
holdings — so the label may not promise an order by value, and the line under it in the menu
says what it does order by.

## What this app does NOT configure

`eth_rpc`'s endpoints and verified-proxy routing live in `chains.json`, which is **device-wide
and shared with every Logos wallet here**. Configuring it from inside one wallet's Settings
sheet is a category error, so those controls now live in the **Ethereum RPC** app and this
wallet has no setter for them at all. Settings reports the endpoint and the routing mode
read-only, and keeps the network selector, which is genuinely this wallet's own state.

No screen anywhere links to a block explorer, and none may be added: a fetched explorer URL
leaks the user's IP address and their address together. The one address a user wants to hand
out is copyable wherever it appears, which is what an explorer link is usually a stand-in for.

## The transaction screen

Three cards. **Transaction** carries status, both timestamps, both addresses, the network, the
hash, the nonce and the block. **Tokens transferred** is present only when the receipt's logs
decoded to something — never as "none", because a row whose receipt was never read carries no
`transfers` key and we do not assert that nothing moved. **Fee** carries the paid fee, the
ceiling it was quoted at, gas used against the approved limit, the two gas prices, the total,
and one button. Every figure there is bounded to five fraction digits in the row and carries
its **exact** string on a copy button: a fee of `0.00000600250665` and a ceiling of
`0.00000926341017` both render `<0.00001`, and where the two collide the rows print every
digit instead — a row that duplicates the one above it is worse than absent.

**One address per row, labelled by what it means.** The Transaction card carries RAW fields
only, and the transaction's one `to` means two different things: `kind` picks the row that names
it, so a native send gets **"To"** and an ERC-20 send gets **"Interacted with"** — the token
contract — and no "To" row at all, because the transaction has no such field. This view compares
no addresses itself.

The recipient of a token send is therefore *interpretation*, and lives below with the decoded
transfers. Until a receipt lands there is nothing decoded, so **Recorded recipient** stands in,
said in as many words to be this wallet's own record rather than chain data. Once the receipt
decodes a Transfer that card goes away and each transfer's own **From** and **To** carry it —
each a row with a copy button, because every address on this screen is copyable in full.

**Day headings.** The activity list groups by day, MetaMask-style, and "Today"/"Yesterday" are
decided against a minute ticker on the root rather than against `new Date()`: the wall clock is
not a QML binding dependency, and an idle wallet republishes no history, so a heading that dated
itself stayed "Today" past local midnight for as long as nothing else moved. The heading is a
**sibling** of the row rather than part of it: anchored inside the delegate it sat under that
delegate's own hover and press background, so pointing at "Yesterday" lit up the transaction
beneath it as one block.

**`Fetch block details`** reads the mined time, and for an older row the tip and the on-chain gas
limit: the only things a receipt genuinely does not carry. The mined row is rendered to the
**second**, with the wait spelled out beside it — at minute resolution it printed the string the
Broadcast row above it already showed, which for a row that stores its own tip was the whole of
what the fetch bought. It is not the header's refresh icon, which re-reads the *receipt* — a
different question with a different answer, and asynchronous like every other chain read here. One spinner, on the
button that was pressed; the rows it will fill keep their em-dashes, because four spinners for
one action read as four things going wrong. A half answer is still an answer: whichever leg
landed is shown, and the other's reason is printed **inside the card, beside the rows it is
about** — never on the wallet's error line, which sits outside the nav stack and would be read
under whatever screen replaces this one.

Everything fetched belongs to **one** transaction. The reply carries the hash it is about, the
screen renders it only for that hash, and `enterScope` withdraws it with every other scoped
figure — so opening one transaction, fetching, going back and opening another cannot show the
first one's mined time under the second one's name.

Gas prices are shown in **gwei**, in the unit the backend priced them in. In ether every gas
price there has ever been renders as `<0.00001`. Nothing on this screen is computed here: the
gas *percentage* is the backend's integer, and a token the wallet does not list shows its raw
on-chain integer labelled `base units` rather than being scaled by an assumed 18.

## QR

**Receive** encodes the selected account's address and draws it as a grid of plain
`Rectangle`s, one per **run** of dark modules. That drawing is ported from the Monero wallet,
which arrived at it the hard way: inside Basecamp's `ui_qml` sandbox a `data:` URI is refused,
a remote URL is refused, and a `Canvas` never receives `paint()` in the plugin's own
`QQuickWidget`. All three were measured; none is worth rediscovering. What the sandbox *does*
admit is a local file under the plugin's own roots, so a sibling `.js` import works.

Where this **diverges** from Monero is which side of the wire the encoder sits on. There, the
backend publishes the matrix, because a Monero receive URI carries an **amount** the backend
owns and re-encodes on every keystroke. Here there is no amount and never will be — an
EIP-681 URI whose amount a scanning wallet silently ignores is a wrong figure with nothing on
screen saying so — and the payload is the bare EIP-55 address, which is already a property of
the view. So `src/qml/qrcodegen.js` (Nayuki's MIT encoder, flattened to top-level functions
because QML has no module system and the published UMD preamble throws) encodes it in the view,
the `.rep` is untouched, and no backend round trip stands between selecting an account and
seeing its code.

The address goes in **bare and unmodified**: uppercasing it voids the EIP-55 checksum. The cell
size is floored and the box takes whatever falls out, rather than the modules being fitted into
a fixed 240px — a fractional cell leaves hairline seams that some scanners read as module
boundaries. The two colours are literal `#000000` on `#ffffff`, not `Theme` tokens, because a
palette colour inverts in dark mode and an inverted code does not scan.

`doctests/qr_table.mjs` runs the encoder against facts the ISO spec fixes rather than against
itself — the version a 42-character byte segment needs, the finder and timing patterns, and the
published format-information string for level M. `doctests/probe_receive.qml` covers everything
between the encoder and the screen.

## Testing

`doctests/assert_ui.py` drives the running view over the QML inspector and asserts what is on
screen. Both harnesses take the port from `LOGOS_INSPECTOR_PORT`, defaulting to the app's own
3768; point them at a fixture you started yourself, because everything past their setup writes
real keystore and `eth_rpc` state. Its sections `0` through `0n` need no app at all — `--grep-only` runs them
and opens no socket. Beside it are seven tables of plain C++ over the pure headers in `src/`
(and, for `test_token_identity.cpp`, over the view's own source) and one of JavaScript over the
view's own QR encoder, which need no app either; `doctests/run_tables.sh` runs all eight, and
each file also carries its own one-line invocation.

`doctests/assert_live_accounts.py` is the one regression a table could not hold: rename an
account in the keystore and the wallet must stop showing the old name **without being
reopened**. It never calls `refresh()` — that absence is the assertion, and section 4 fails the
run if one creeps in. It needs `keystore_custodian` (the fixture in `keystore-module/doctests/
custodian-probe`) staged, because `set_label` refuses every other caller, this view included.
There is no config file to name it in: the harness names it itself, with a `configure` call on
the keystore module — a total document, so it restates the approver at its default rather than
emptying it — and section 0 fails the run if the names did not take. Stage the plugin and its
modules, then:

```bash
QT_QPA_PLATFORM=offscreen QML_INSPECTOR_PORT=3769 logos-standalone-app \
  --modules-dir ./modules --user-dir ./user \
  --load keystore_module --load eth_rpc_module --load fee_module --load token_list_module \
  --load keystore_custodian --load eth_wallet_backend ./plugins/eth_wallet_ui
LOGOS_INSPECTOR_PORT=3769 python3 doctests/assert_live_accounts.py
```

The plugin goes **positionally**: `QApplication` consumes `-plugin`/`--plugin` as Qt's own
generic-plugin option, so the app's parser never sees it and reports "no UI plugin specified".

`run_tables.sh` finishes with the view probes — every `doctests/probe_*.qml`, run by
`run_view_probe.sh` — which are the level between the two: they stand the view up under an
offscreen Qt with a fabricated backend and assert what it **says**. A source assertion cannot
tell you that the mined row renders an em-dash for a transaction the fetched detail is not
about, or that a menu row is not being drawn under its own tick; only evaluating the bindings
can. They skip cleanly when there is no Qt Quick runtime to hand.

**A source-text assertion cannot see a neutered guard.** `if (!answersFor(reply, shown()) &&
false)` leaves the call present, in order, in the right function, anchored to the write it
guards — and every grep that described it passes while it guards nothing. That was measured on
this file. Four more assertions turned out to be answered by a *different* line than the one
they were about: a deleted `m_refreshAgain` covered by the same statement 30 lines down, a
deleted `sendDialog.token =` covered by an identical substring in the handler above it, a fix
that still passed once turned entirely into a comment, and an exemption keyed on the parameter
names `a`/`b` rather than on a site.

Writing cleverer greps loses that game. So the guards moved into the pure transitions above,
where a table **runs** them:

| table | what it runs |
| --- | --- |
| `test_apply.cpp` | every guard deciding whether a reply reaches the screen |
| `test_scope_invariant.cpp` | the selection-change withdrawal |
| `test_reply_scope.cpp` | the reply's own scope, and the quote's request pairing |
| `test_data_guard.cpp` | the guarded async lane: ticket, queue, lapse, budget |
| `test_sweep_decision.cpp` | the sweep schedule, including a read that failed |
| `probe_tx_detail.qml` | the transaction screen's own bindings, loaded and driven |
| `probe_tokens_sort.qml` | the sort control, and the order the token list is laid out in |
| `qr_table.mjs` | the QR encoder, against the spec's own version, pattern and format facts |
| `probe_receive.qml` | the Receive screen: what is encoded, and what is drawn |

Neutering any of those now fails a row that executed it. What is left for a grep is what no
table can see — QML bindings, and whether the backend *consults* the transitions at all — and
that residue is asserted as an **absence** (`no scoped setter is called outside publishScope`,
`no claim is taken for a bare call budget`, `no comparison defaults both of its sides to an
empty string`), because an absence is the one claim another line cannot answer for.

## Building

```bash
nix build .#lgx-portable   # the installable package (Basecamp / logosctl)
nix build .#install        # the dev variant, for logos-standalone-app
```

Icons live in `src/qml/assets/` and are local to this module by design. `metadata.json`'s
`icon` is a different mechanism — it packages exactly one 256x256 PNG for the host's own
chrome and is not reachable from the view's QML.
