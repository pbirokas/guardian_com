import 'package:flutter_test/flutter_test.dart';
import 'package:guardian_app/core/models/message.dart';
import 'package:guardian_app/core/router/chat_navigation.dart';

void main() {
  group('chatOpenActionFor', () {
    test('kein Chat offen → push', () {
      expect(chatOpenActionFor('/organizations', 'a'), ChatOpenAction.push);
      expect(chatOpenActionFor('/org/123', 'a'), ChatOpenAction.push);
      expect(chatOpenActionFor('', 'a'), ChatOpenAction.push);
    });

    test('derselbe Chat ist bereits offen → nichts stapeln', () {
      expect(chatOpenActionFor('/chat/a', 'a'), ChatOpenAction.none);
    });

    test('anderer Chat offen → ersetzen statt stapeln', () {
      expect(chatOpenActionFor('/chat/b', 'a'), ChatOpenAction.replace);
    });
  });

  group('Message.allImageUrls', () {
    Map<String, dynamic> base() => {
          r'$id': 'm1',
          'senderUid': 'u1',
          'sentAt': '2026-11-13T10:00:00.000Z',
        };

    test('Einzelbild (altes Format)', () {
      final msg = Message.fromAppwrite({...base(), 'imageUrl': 'x'});
      expect(msg.imageUrls, isEmpty);
      expect(msg.allImageUrls, ['x']);
    });

    test('Mehrfach-Bild-Nachricht', () {
      final msg = Message.fromAppwrite({
        ...base(),
        'imageUrl': 'x',
        'imageUrls': ['x', 'y', 'z'],
      });
      expect(msg.allImageUrls, ['x', 'y', 'z']);
      expect(msg.toAppwrite()['imageUrls'], ['x', 'y', 'z']);
    });

    test('ohne Bild', () {
      final msg = Message.fromAppwrite(base());
      expect(msg.allImageUrls, isEmpty);
      expect(msg.toAppwrite().containsKey('imageUrls'), isFalse);
    });
  });
}
