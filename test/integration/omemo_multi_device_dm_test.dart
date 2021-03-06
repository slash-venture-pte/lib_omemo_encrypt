import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lib_omemo_encrypt/conversation/dummy/conversation_enum_dummy.dart';
import 'package:lib_omemo_encrypt/conversation/dummy/conversation_person.dart';
import 'package:lib_omemo_encrypt/utils/utils.dart';
import 'package:lib_omemo_encrypt/conversation/dummy/conversation.dart';

void main() {
  late ConversationPerson alice;
  late ConversationPerson bob;
  late Conversation dmAliceBob;
  setUp(() async {
    alice = await ConversationPerson.init(Person.alice.name,
        personDevices[Person.alice]!.map<String>((e) => e.name).toList());
    bob = await ConversationPerson.init(Person.bob.name,
        personDevices[Person.bob]!.map<String>((e) => e.name).toList());

    dmAliceBob = Conversation.createPerson([alice, bob]);
  });
  test(
      'should fully encrypt and decrypt from Alice to one of her device and to Bob and his other device',
      () async {
    // Alice want to chat to Bob from Device "C"
    // She get id from her bob public prekey

    int max = 20;
    int counter = max;
    bool finalResult = true;
    while (counter > 0) {
      counter--;

      int randomSender = Utils.createRandomSequence(max: 2);
      final Person person = personDevices.keys.elementAt(randomSender);
      final Iterable<Device> devices = personDevices[person]!;
      int randomDevice = Utils.createRandomSequence(max: devices.length);
      Device device = devices.elementAt(randomDevice);
      if (kDebugMode) {
        print(
            '================== Message Counter ${max - counter} ==================');
        print(
            '========================================== Send from ${person.name} - ${device.name}');
      }

      await dmAliceBob.setup(person.name, device.name, offsetKey: counter * 10);

      final message =
          messages.elementAt(Utils.createRandomSequence(max: messages.length));

      final distributedMessage = await dmAliceBob.encryptMessageToOthers(
          person.name, device.name, message);
      final result = await dmAliceBob.decryptDistributedMessageOfTarget(
          person.name, device.name, message, distributedMessage);
      finalResult = finalResult && result;
    }
    expect(finalResult, true);
  });
  test('Should parse session of each conversation to mapped of buffer',
      () async {
    ConversationPerson tom = await ConversationPerson.init('Tom', ['Device-A']);
    ConversationPerson jerry =
        await ConversationPerson.init('Jerry', ['Device-B']);

    final dmTomJerry = Conversation.createPerson([tom, jerry]);
    await dmTomJerry.setup('Tom', 'Device-A');

    final bufferMappedSession =
        await dmTomJerry.peopleParties[0].appInstances[0].writeToBufferMap();
    expect(bufferMappedSession.keys.length, 1);
  });
}
