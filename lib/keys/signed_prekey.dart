import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:lib_omemo_encrypt/keys/key.dart';

class SignedPreKey extends LibOMEMOKey {
  final Uint8List signature;

  const SignedPreKey({required id, required keyPair, required this.signature})
      : super(id: id, keyPair: keyPair);
}