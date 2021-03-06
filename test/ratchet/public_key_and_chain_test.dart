import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lib_omemo_encrypt/keys/ecc/keypair.dart';
import 'package:lib_omemo_encrypt/ratchet/chain.dart';
import 'package:lib_omemo_encrypt/ratchet/message_key.dart';
import 'package:lib_omemo_encrypt/ratchet/publickey_and_chain.dart';
import 'package:lib_omemo_encrypt/utils/utils.dart';

void main() {
  final algorithm = X25519();
  group('rachet/public_key_and_chain.dart', () {
    test('Should serialize public key and chain and parse it back', () async {
      final messageKey = MessageKey.create(
          cipherKey: Uint8List.fromList(Utils.convertStringToBytes('key')),
          macKey: Uint8List.fromList(Utils.convertStringToBytes('mac')),
          iv: Uint8List.fromList(Utils.convertStringToBytes('iv')),
          index: 0);
      final messageKeyNext = MessageKey.create(
          cipherKey: Uint8List.fromList(Utils.convertStringToBytes('key_next')),
          macKey: Uint8List.fromList(Utils.convertStringToBytes('mac_next')),
          iv: Uint8List.fromList(Utils.convertStringToBytes('iv_next')),
          index: 1);

      final chain = Chain.create(
          Uint8List.fromList(Utils.convertStringToBytes('chainKeys')),
          index: 0,
          messageKeysList: [messageKey, messageKeyNext]);

      final xKeyPair = await algorithm.newKeyPair();
      final keyPair =
          ECDHKeyPair.createPair(xKeyPair, await xKeyPair.extractPublicKey());
      final publicKey = await keyPair.publicKey;

      final publicKeyAndChain =
          PublicKeyAndChain.create(ephemeralPublicKey: publicKey, chain: chain);
      final serialized = await publicKeyAndChain.serialize();

      final parsedKeyChain = await PublicKeyAndChain().deserialize(serialized);

      final serializedFromNewKeyChain = await parsedKeyChain.serialize();
      expect(serialized, serializedFromNewKeyChain);
    });
  });
}
