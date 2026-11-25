import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
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

  group('openChatId (oberste Seite)', () {
    testWidgets('per push geöffneter Chat gilt als oberste Seite', (tester) async {
      Widget page(GoRouterState s) => Text(s.uri.path);
      final router = GoRouter(
        initialLocation: '/org/1',
        routes: [
          GoRoute(path: '/org/:orgId', builder: (_, s) => page(s)),
          GoRoute(path: '/chat/:chatId', builder: (_, s) => page(s)),
          GoRoute(path: '/profile', builder: (_, s) => page(s)),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      expect(openChatId(router), isNull);

      router.push('/chat/a');
      await tester.pumpAndSettle();
      expect(openChatId(router), 'a');
      // Die Falle, die mark-as-read in App 2.0.0 lahmgelegt hat:
      expect(router.routerDelegate.currentConfiguration.uri.path, '/org/1');

      router.push('/profile');
      await tester.pumpAndSettle();
      expect(openChatId(router), isNull);

      router.pop();
      await tester.pumpAndSettle();
      expect(openChatId(router), 'a');

      router.pop();
      await tester.pumpAndSettle();
      expect(openChatId(router), isNull);
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
