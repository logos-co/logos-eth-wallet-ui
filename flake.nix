{
  description = "Logos eth_wallet_ui — Send ether on one Ethereum network at a time, with the full set of fee controls.";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    # Every dependency builds against THIS module-builder. Without the follows each drags
    # its own, and a skewed generated ABI segfaults the module inside provider init.
    eth_wallet_backend = {
      url = "github:logos-co/logos-eth-wallet-backend";
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
