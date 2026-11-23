# ADR-0001: The locked view says which device unlocks which wallet

- Status: Accepted
- Date: 2026-11-23
- Scope: QML only (`accountkit/EthAccountPicker.qml`, `accountkit/roster.js`, `EthWalletView.qml`)

## Context
With every wallet locked the app showed one generic banner and an Address book tab that could not
open: the book is sealed under a key the signer manager gives only while a wallet is unlocked.

## Decision
- Locked wallets are grouped by device from the signer manager's `kinds` (a Keycard Shell folds into
  Keycard), each block naming the app that unlocks it.
- With no usable account there are no tabs at all: only the locked banner, or, with no wallet, a
  "No Ethereum accounts yet" state. Once a wallet unlocks the app lands on Tokens.

## Consequences
No dead tab while locked; the next step is the banner's Unlock. Verified by hand with a Keystore
wallet and a Keycard Shell wallet locked.
