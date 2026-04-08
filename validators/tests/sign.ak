use aiken/cbor
use aiken/crypto.{verify_ed25519_signature}
use cardano/address.{Address, Script}
use cardano/assets
use cardano/transaction.{Input, NoDatum, Output, OutputReference}
use price_oracle_utils.{verify_prices_oracle_messages}
use types.{Message}

test parse_type() {
  let plutusData =
    #"d8799f00a39f581cc69b981db7a65e339a6d783755f85a2e03afa1cece9714c55fe4c913445553444dff9f0100ff9f4040ff9f190a8b04ff9f581c3363b99384d6ee4c4b009068af396c8fdf92dafd111e58a857af0429454e49474854ff9f19124e05ffd8799f58204fa3b153b62f4597e80c6eb25a839332c3e6081385ea7b54912b6a3918208b4300ffff"

  let gg =
    Message {
      vault_equity: 0,
      prices: [
        Pair(
          (
            #"c69b981db7a65e339a6d783755f85a2e03afa1cece9714c55fe4c913",
            #"5553444d",
          ),
          (1, 0),
        ), Pair((#"", #""), (2699, 4)),
        Pair(
          (
            #"3363b99384d6ee4c4b009068af396c8fdf92dafd111e58a857af0429",
            #"4e49474854",
          ),
          (4686, 5),
        ),
      ],
      utxo_ref: OutputReference {
        transaction_id: #"4fa3b153b62f4597e80c6eb25a839332c3e6081385ea7b54912b6a3918208b43",
        output_index: 0,
      },
    }
  let abc = cbor.deserialise(plutusData)

  expect Some(data) = abc
  expect m: Message = data

  m == gg
}

test check_sign() {
  verify_ed25519_signature(
    key: #"f665d3a9cbb3d8068aece5700771893780dbbf30302eb7ff6835ae68c9efe690",
    msg: #"d8799f00a39f581cc69b981db7a65e339a6d783755f85a2e03afa1cece9714c55fe4c913445553444dff9f0100ff9f4040ff9f190a8b04ff9f581c3363b99384d6ee4c4b009068af396c8fdf92dafd111e58a857af0429454e49474854ff9f19124e05ffd8799f58204fa3b153b62f4597e80c6eb25a839332c3e6081385ea7b54912b6a3918208b4300ffff",
    sig: #"fa5a71b545bdcc6064c1538ac8aeeab9dbd4164d22fb879e41f9ca43b920f2fedbc4e185eb1a94c7b298e72f60735dbaeb91e0196dd9a2fd23ef3c2c5f4f380a",
  )
}

test verify_prices_oracle_messages_test() {
  let prices_message =
    #"d8799f00a39f581cc69b981db7a65e339a6d783755f85a2e03afa1cece9714c55fe4c913445553444dff9f0100ff9f4040ff9f190a8b04ff9f581c3363b99384d6ee4c4b009068af396c8fdf92dafd111e58a857af0429454e49474854ff9f19124e05ffd8799f58204fa3b153b62f4597e80c6eb25a839332c3e6081385ea7b54912b6a3918208b4300ffff"

  let hydra_node_pub_keys =
    [
      #"f665d3a9cbb3d8068aece5700771893780dbbf30302eb7ff6835ae68c9efe690",
      #"827444459fa6466ad8fd670179e23b00ea0566547a44cd67a1b37675634280f1",
    ]

  let signatures =
    [
      #"fa5a71b545bdcc6064c1538ac8aeeab9dbd4164d22fb879e41f9ca43b920f2fedbc4e185eb1a94c7b298e72f60735dbaeb91e0196dd9a2fd23ef3c2c5f4f380a",
      #"c069bdd4383ca6384b5c57797cfff7550438852df7dd680e7625b3225d6705162ccd80f2551298804de31fa471a9133be3e7bdd1507e79ef27c226b53083fa0a",
    ]

  let utxo_ref =
    OutputReference {
      transaction_id: #"4fa3b153b62f4597e80c6eb25a839332c3e6081385ea7b54912b6a3918208b43",
      output_index: 0,
    }

  let mock_output =
    Output {
      address: Address {
        payment_credential: Script(#"00"),
        stake_credential: None,
      },
      value: assets.zero,
      datum: NoDatum,
      reference_script: None,
    }

  let inputs = [Input { output_reference: utxo_ref, output: mock_output }]

  let (vault_equity, _prices, message_verified) =
    verify_prices_oracle_messages(
      prices_message,
      inputs,
      hydra_node_pub_keys,
      signatures,
    )

  vault_equity == 0 && message_verified
}
