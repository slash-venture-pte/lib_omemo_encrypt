import 'dart:typed_data';

import 'package:lib_omemo_encrypt/keys/ecc/keypair.dart';
import 'package:lib_omemo_encrypt/keys/ecc/publickey.dart';
import 'package:lib_omemo_encrypt/ratchet/chain.dart';
import 'package:lib_omemo_encrypt/ratchet/key_and_chain.dart';
import 'package:lib_omemo_encrypt/ratchet/message_key.dart';

const messageKeySeed = 0x01;
const chainKeySeed = 0x02;
final whisperMessageKeys = Uint8List.fromList([
  87,
  104,
  105,
  115,
  112,
  101,
  114,
  77,
  101,
  115,
  115,
  97,
  103,
  101,
  75,
  101,
  121,
  115
]).buffer;
final whisperRatchet = Uint8List.fromList(
    [87, 104, 105, 115, 112, 101, 114, 82, 97, 116, 99, 104, 101, 116]).buffer;
final whisperText =
    Uint8List.fromList([87, 104, 105, 115, 112, 101, 114, 84, 101, 120, 116])
        .buffer;
final discontinuityBytes = Uint8List.fromList([
  0xff,
  0xff,
  0xff,
  0xff,
  0xff,
  0xff,
  0xff,
  0xff,
  0xff,
  0xff,
  0xff,
  0xff,
  0xff,
  0xff,
  0xff,
  0xff,
  0xff,
  0xff,
  0xff,
  0xff,
  0xff,
  0xff,
  0xff,
  0xff,
  0xff,
  0xff,
  0xff,
  0xff,
  0xff,
  0xff,
  0xff,
  0xff
]).buffer;

abstract class RatchetInterface {
  KeyAndChain deriveInitialRootKeyAndChain(
      int sessionVersion, List<ByteBuffer> agreements);
  Future<KeyAndChain> deriveNextRootKeyAndChain(
      Uint8List rootKey,
      ECDHPublicKey theirEphemeralPublicKey,
      ECDHKeyPair ourEphemeralPrivateKey);
  Future<Chain> clickSubRatchet(Chain chain);
  Future<MessageKey> deriveMessageKeys(
      Uint8List chainKey, int indexChainMessageKey);
  Future<Uint8List> deriveMessageKey(Uint8List chainKey);
  Future<Uint8List> deriveNextChainKey(Uint8List chainKey);
}
