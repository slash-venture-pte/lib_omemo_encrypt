import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:lib_omemo_encrypt/constants/constant.dart';
import 'package:lib_omemo_encrypt/encryptions/axolotl/axolotl.dart';
import 'package:lib_omemo_encrypt/encryptions/cipher_session/bob_cipher_session_params.dart';

import 'package:lib_omemo_encrypt/encryptions/cipher_session/session_factory_interface.dart';
import 'package:lib_omemo_encrypt/encryptions/cipher_session/alice_cipher_session_params.dart';
import 'package:lib_omemo_encrypt/exceptions/invalid_key_exception.dart';
import 'package:lib_omemo_encrypt/keys/bundle/receiving_prekey_bundle.dart';
import 'package:lib_omemo_encrypt/keys/ecc/publickey.dart';
import 'package:lib_omemo_encrypt/keys/noob/nokey_pair.dart';
import 'package:lib_omemo_encrypt/keys/whisper/identity_key.dart';
import 'package:lib_omemo_encrypt/keys/whisper/pending_prekey.dart';
import 'package:lib_omemo_encrypt/keys/whisper/prekey.dart';
import 'package:lib_omemo_encrypt/keys/whisper/signed_prekey.dart';
import 'package:lib_omemo_encrypt/messages/message.dart';
import 'package:lib_omemo_encrypt/rachet/key_and_chain.dart';
import 'package:lib_omemo_encrypt/rachet/rachet.dart';
import 'package:lib_omemo_encrypt/sessions/session.dart';
import 'package:lib_omemo_encrypt/sessions/session_state.dart';
import 'package:lib_omemo_encrypt/storage/storage_interface.dart';
import 'package:lib_omemo_encrypt/utils/log.dart';

const sessionFactoryTag = 'sessionFactory';

class SessionCipherState {
  final Session session;
  late SimplePublicKey identityKey;
  late String registrationId;

  SessionCipherState(
      this.session, List<int> identityKey, List<int> registrationId) {
    this.identityKey = SimplePublicKey(identityKey, type: KeyPairType.x25519);
    this.registrationId = base64Url.encode(registrationId);
  }
}

class SessionFactory extends SessionFactoryInterface {
  final Rachet rachet = Rachet();
  final algorithmx25519 = X25519();
  final StorageInterface store;
  final Axololt axololt = Axololt();

  SessionFactory({required this.store});

  @override
  Future<Session> createSessionFromPreKeyBundle(
      ReceivingPreKeyBundle receivingPreKeyBundle) async {
    if (receivingPreKeyBundle.signedPreKey != null) {
      final data = await receivingPreKeyBundle.signedPreKey!.key.bytes;
      final validSignature = await axololt.verifySignature(
          data,
          receivingPreKeyBundle.signature,
          receivingPreKeyBundle.identityKey.key);

      if (!validSignature) {
        throw InvalidKeyException('Invalid signature on device key');
      }
    }
    if (receivingPreKeyBundle.preKey is NoKeyPair &&
        receivingPreKeyBundle.signedPreKey != null) {
      throw InvalidKeyException('Both signed and unsigned pre keys are absent');
    }
    final supportsV3 = receivingPreKeyBundle.signedPreKey != null;
    final ourBaseKeyPair = await axololt.generateKeyPair();
    final SignedPreKey theirSignedPreKey = supportsV3
        ? receivingPreKeyBundle.signedPreKey!
        : SignedPreKey(
            key: receivingPreKeyBundle.preKey.key,
            signedPreKeyId: receivingPreKeyBundle.preKey.preKeyId);

    Log.instance.d(sessionFactoryTag, 'Session Version : 3');
    Log.instance
        .d(sessionFactoryTag, 'ourBaseKeyPair : ${await ourBaseKeyPair.bytes}');
    Log.instance.d(sessionFactoryTag,
        'ourIdentityKeyPair : ${await store.getLocalIdentityKeyPair().keyPair.bytes}');
    Log.instance.d(sessionFactoryTag, 'ourSignedPreKeyPair : null');
    Log.instance.d(sessionFactoryTag,
        'receivingPreKeyBundle.identityKey : ${receivingPreKeyBundle.identityKey}');
    Log.instance.d(sessionFactoryTag, 'theirSignedPreKey : $theirSignedPreKey');
    Log.instance.d(sessionFactoryTag, 'theirRatchetKey : $theirSignedPreKey');
    Log.instance.d(sessionFactoryTag,
        'theirOneTimePreKey : ${supportsV3 ? receivingPreKeyBundle.preKey : null}');

    final aliceParameters = AliceCipherSessionParams(
        sessionVersion: supportsV3 ? 3 : 2,
        ourBaseKeyPair: ourBaseKeyPair,
        ourIdentityKeyPair: store.getLocalIdentityKeyPair(),
        ourSignedPreKeyPair: null,
        theirIdentityKey: receivingPreKeyBundle.identityKey,
        theirSignedPreKey: theirSignedPreKey,
        theirRatchetKey: theirSignedPreKey,
        theirOneTimePreKey: supportsV3 ? receivingPreKeyBundle.preKey : null);

    final sessionState = await initializeAliceSession(aliceParameters);
    sessionState.pending = PendingPreKey(
        preKeyId: supportsV3 ? receivingPreKeyBundle.preKeyId : noPreKeyId,
        key: await ourBaseKeyPair.publicKey,
        signedPreKeyId: receivingPreKeyBundle.signedPreKeyId);
    sessionState.localRegistrationId = await store.getLocalRegistrationId();

    var session = Session();
    session.addState(sessionState);
    return session;
  }

  @override
  Future<SessionState> initializeAliceSession(
      AliceCipherSessionParams parameters) async {
    final sendingRatchetKeyPair = await axololt.generateKeyPair();
    final agreement1 = await axololt.calculateAgreement(
        parameters.ourIdentityKeyPair.keyPair,
        parameters.theirSignedPreKey.key);
    final agreement2 = await axololt.calculateAgreement(
        parameters.ourBaseKeyPair, parameters.theirIdentityKey.key);
    final agreement3 = await axololt.calculateAgreement(
        parameters.ourBaseKeyPair, parameters.theirSignedPreKey.key);

    final agreements = [agreement1, agreement2, agreement3];

    if (parameters.sessionVersion >= 3 &&
        parameters.theirOneTimePreKey != null) {
      final agreement4 = await axololt.calculateAgreement(
          parameters.ourBaseKeyPair, parameters.theirOneTimePreKey!.key);
      agreements.add(agreement4);
    }
    final KeyAndChain derivedRootKeyChain = rachet.deriveInitialRootKeyAndChain(
        parameters.sessionVersion, agreements);
    final KeyAndChain sendingKeyChain = await rachet.deriveNextRootKeyAndChain(
        derivedRootKeyChain.rootKey,
        parameters.theirRatchetKey.key,
        sendingRatchetKeyPair);
    final SessionState sessionState = SessionState(
      sessionVersion: parameters.sessionVersion,
      remoteIdentityKey: parameters.theirIdentityKey,
      localIdentityKey: await parameters.ourIdentityKeyPair.identityKey,
      rootKey: sendingKeyChain.rootKey,
      sendingChain: sendingKeyChain.chain,
      senderRatchetKeyPair: sendingRatchetKeyPair,
    );
    sessionState.addReceivingChain(
        parameters.theirRatchetKey.key, derivedRootKeyChain.chain);
    return sessionState;
  }

  @override
  Future<SessionCipherState> createSessionFromPreKeyWhisperMessage(
      Session session, Uint8List preKeyWhisperMessageBytes) async {
    final preKeyWhisperMessage =
        Message.message.decodePreKeyWhisperMessage(preKeyWhisperMessageBytes);
    if (preKeyWhisperMessage.version.current != 3) {
      throw Exception(
          "Protocol version ${preKeyWhisperMessage.version.current} is not supported");
    }

    final message = preKeyWhisperMessage.message;

    for (var cachedSessionState in session.states) {
      if (cachedSessionState.theirBaseKey != null) {
        final theirBaseKeyBytes =
            await cachedSessionState.theirBaseKey!.key.bytes;
        if (theirBaseKeyBytes == message.ek) {
          return SessionCipherState(
              session, message.ik, message.registrationId);
        }
      }
    }

    final ourSignedPreKeyPair = store.getLocalSignedPreKeyPair(message.spkId);
    final preKeyPair = store.getLocalPreKeyPair(message.pkId);

    Log.instance.d(sessionFactoryTag,
        'sessionVersion: ${preKeyWhisperMessage.version.current}');
    Log.instance.d(sessionFactoryTag, 'theirBaseKey/prekey: ${message.ek}');
    Log.instance.d(sessionFactoryTag, 'theirIdentityKey: ${message.ik}');
    Log.instance.d(sessionFactoryTag,
        'ourIdentityKeyPair: ${await store.getLocalIdentityKeyPair().keyPair.publicKeyBytes}');
    Log.instance
        .d(sessionFactoryTag, 'ourSignedPreKeyPair: $ourSignedPreKeyPair');
    Log.instance
        .d(sessionFactoryTag, 'ourRatchetKeyPair: $ourSignedPreKeyPair');
    Log.instance.d(sessionFactoryTag, 'ourOneTimePreKeyPair: $preKeyPair');

    final bobParameters = BobCipherSessionParams(
        sessionVersion: preKeyWhisperMessage.version.current,
        theirBaseKey: PreKey(
            key: ECDHPublicKey.fromBytes(message.ek), preKeyId: message.pkId),
        theirIdentityKey: IdentityKey(key: ECDHPublicKey.fromBytes(message.ik)),
        ourIdentityKeyPair: store.getLocalIdentityKeyPair(),
        ourSignedPreKeyPair: ourSignedPreKeyPair,
        ourRatchetKeyPair: ourSignedPreKeyPair,
        ourOneTimePreKeyPair: preKeyPair);

    final sessionState = await initializeBobSession(bobParameters);
    sessionState.theirBaseKey = PreKey(
        key: ECDHPublicKey.fromBytes(message.ek), preKeyId: message.pkId);
    final clonedSession = Session();
    clonedSession.clone(session.states);
    clonedSession.addState(sessionState);
    return SessionCipherState(
        clonedSession, message.ik, message.registrationId);
  }

  @override
  Future<SessionState> initializeBobSession(
      BobCipherSessionParams parameters) async {
    final agreement1 = await axololt.calculateAgreement(
        parameters.ourSignedPreKeyPair.keyPair,
        parameters.theirIdentityKey.key);
    final agreement2 = await axololt.calculateAgreement(
        parameters.ourIdentityKeyPair.keyPair, parameters.theirBaseKey.key);
    final agreement3 = await axololt.calculateAgreement(
        parameters.ourSignedPreKeyPair.keyPair, parameters.theirBaseKey.key);

    final agreements = [agreement1, agreement2, agreement3];
    if (parameters.sessionVersion >= 3 &&
        parameters.ourOneTimePreKeyPair != null) {
      final agreement4 = await axololt.calculateAgreement(
          parameters.ourOneTimePreKeyPair!.keyPair,
          parameters.theirBaseKey.key);
      agreements.add(agreement4);
    }

    final KeyAndChain initialRootKeyChain = rachet.deriveInitialRootKeyAndChain(
        parameters.sessionVersion, agreements);

    final SessionState sessionState = SessionState(
      sessionVersion: parameters.sessionVersion,
      remoteIdentityKey: parameters.theirIdentityKey,
      localIdentityKey: await parameters.ourIdentityKeyPair.identityKey,
      rootKey: initialRootKeyChain.rootKey,
      sendingChain: initialRootKeyChain.chain,
      senderRatchetKeyPair: parameters.ourRatchetKeyPair.keyPair,
    );
    return sessionState;
  }
}