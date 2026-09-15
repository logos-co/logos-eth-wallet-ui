{
  description = "Logos eth_wallet_ui — Multi-chain EVM portfolio and explicit-chain sends.";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    eth_rpc_module = {
      url = "github:logos-co/logos-evm-eth-rpc-module";
      inputs.logos-module-builder.follows = "logos-module-builder";
    };
    token_list_module = {
      url = "github:logos-co/logos-evm-token-list-module";
      inputs.logos-module-builder.follows = "logos-module-builder";
    };
    keystore_module = {
      url = "github:logos-co/logos-evm-keystore-module";
      inputs.logos-module-builder.follows = "logos-module-builder";
    };
    fee_module = {
      url = "github:logos-co/logos-evm-fee-module";
      inputs.logos-module-builder.follows = "logos-module-builder";
      inputs.eth_rpc_module.follows = "eth_rpc_module";
    };
    evm_assets_module = {
      url = "github:logos-co/logos-evm-assets-module";
      inputs.logos-module-builder.follows = "logos-module-builder";
      inputs.eth_rpc_module.follows = "eth_rpc_module";
      inputs.token_list_module.follows = "token_list_module";
    };
    # Every dependency builds against THIS module-builder. Without the follows each drags
    # its own, and a skewed generated ABI segfaults the module inside provider init.
    eth_wallet_backend = {
      url = "github:logos-co/logos-eth-wallet-backend";
      inputs.logos-module-builder.follows = "logos-module-builder";
      # One sender, one lidl: the backend sends through the same module this view hands an
      # app's transactions to, and two pins of it would generate two clients for one name.
      inputs.tx_sender_module.follows = "tx_sender_module";
      inputs.eth_rpc_module.follows = "eth_rpc_module";
      inputs.fee_module.follows = "fee_module";
      inputs.keystore_module.follows = "keystore_module";
      inputs.token_list_module.follows = "token_list_module";
      inputs.evm_assets_module.follows = "evm_assets_module";
    };
    tx_sender_module = {
      url = "github:logos-co/logos-evm-tx-sender-module";
      inputs.logos-module-builder.follows = "logos-module-builder";
      inputs.eth_rpc_module.follows = "eth_rpc_module";
      inputs.fee_module.follows = "fee_module";
      inputs.keystore_module.follows = "keystore_module";
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
