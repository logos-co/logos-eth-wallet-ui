{
  description = "Logos eth_wallet_ui — Send ether on one Ethereum network at a time, with the full set of fee controls.";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    # Every dependency builds against THIS module-builder. Without the follows each drags
    # its own, and a skewed generated ABI segfaults the module inside provider init.
    eth_wallet_backend = {
      # TEMPORARY, and it must not outlive the merge: this view calls
      # `get_account_wallets`, which exists only on the backend branch below
      # (logos-eth-wallet-backend#5). Move back to the bare URL and relock in the SAME
      # commit that lands on a main carrying it — a pin whose revert note outlives it is
      # how this repo's main stopped compiling last time.
      url = "github:logos-co/logos-eth-wallet-backend/feat/intents-handle";
      inputs.logos-module-builder.follows = "logos-module-builder";
    };
  };

  # mkLogosQmlModule, NOT mkLogosModule: the generic builder compiles the plugin but never
  # assembles the QML, so the .lgx step then fails with "view file not found in staged payload".
  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosQmlModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
    };
}
