# ADR-0002: Match the Keycard and Signer apps' patterns

- Status: Accepted
- Date: 2026-11-23
- Scope: QML, the app icon, and one backend fix (`eth_wallet_ui_apply.h`)

## Decision
- Content sits in a 560 px centred column, as in Keycard and Signer.
- Send on a token screen is the primary (orange) action. The fee tier is a radio group (the label
  selects too), not three buttons.
- In-content tags (network, status, signer) use the Keycard strip-tag style: bold coloured text, no
  border, no dot. The bordered badge stays for the title's scope chip. In the account picker, a
  signer that isn't connected is hidden when another can sign; an absent card reads as a grey
  "Keycard"; an unnamed account reads "Ethereum N", as in Keycard.
- The Address book adds in a sheet, with a full-width Add button over the list and an empty state
  with its own button (the Signer's Passwords pattern). Explanatory paragraphs became (i) buttons or
  were dropped (Address book note, the scope info, the Receive note → an (i) beside Copy).
- The icon is the Ethereum mark, full-tile.
- Fix: "Fetch block details" dropped every reply for a transaction on another chain than the one
  shown (a Sepolia send viewed on Hoodi). The reply is now matched by account and hash on its own
  chain.

## Consequences
Verified by hand on Basecamp 0.3.2 with Keystore, Keycard (reader) and Keycard Shell accounts.
