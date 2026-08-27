# eth_wallet_ui

The Ethereum wallet interface: tokens, activity, and a Send flow with the full set of fee controls.

Modelled on MetaMask's information design and built from `logos-design-system`. Holds no security-sensitive state: it requests signatures and reads which accounts are available. Key management lives in `keystore_ui`; approval lives in `signer_ui`.

Part of the [Logos](https://github.com/logos-co) modular application platform.
Built and tested through the `logos-workspace` `ws` CLI.

> Status: scaffolding. See the architecture plan for scope and phases.
