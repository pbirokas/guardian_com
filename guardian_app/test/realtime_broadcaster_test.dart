import 'dart:async';

import 'package:appwrite/appwrite.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guardian_app/core/appwrite_client.dart';

/// In-memory stand-in for the SDK's Realtime: records subscribe/unsubscribe/
/// disconnect calls and lets tests push events into a channel.
class FakeRealtime implements Realtime {
  final List<RealtimeSubscription> subs = [];
  int unsubscribeCalls = 0;
  bool disconnected = false;

  List<String> get subscribedChannels =>
      [for (final s in subs) ...s.channels];

  @override
  RealtimeSubscription subscribe(
    List<Object> channels, {
    List<String> queries = const [],
  }) {
    final controller = StreamController<RealtimeMessage>.broadcast();
    final sub = RealtimeSubscription(
      controller: controller,
      channels: [for (final c in channels) c.toString()],
      queries: queries,
      unsubscribe: () async {
        unsubscribeCalls++;
        await controller.close();
      },
      update: ({channels, queries}) async {},
      close: () => controller.close(),
    );
    subs.add(sub);
    return sub;
  }

  @override
  Future<void> disconnect() async {
    disconnected = true;
    for (final s in subs) {
      if (!s.controller.isClosed) await s.controller.close();
    }
  }

  void emit(String channel, List<String> events) {
    for (final s in subs) {
      if (s.channels.contains(channel) && !s.controller.isClosed) {
        s.controller.add(RealtimeMessage(
          events: events,
          payload: const {'convId': 'c1'},
          channels: [channel],
          timestamp: '2026-10-10T00:00:00Z',
        ));
      }
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _channel = 'databases.guardian.collections.chat_messages.documents';

void main() {
  late List<FakeRealtime> instances;
  late RealtimeBroadcaster broadcaster;

  setUp(() {
    instances = [];
    broadcaster = RealtimeBroadcaster(() {
      final rt = FakeRealtime();
      instances.add(rt);
      return rt;
    });
  });

  test('shares one SDK subscription per channel across listeners', () async {
    final a = broadcaster.stream(_channel).listen((_) {});
    final b = broadcaster.stream(_channel).listen((_) {});
    await pumpEventQueue();

    expect(instances.single.subs, hasLength(1));
    await a.cancel();
    await b.cancel();
  });

  test('delivers typed RealtimeMessage events to every listener', () async {
    final got = <List<String>>[];
    // Regression: v26 types `events` as List<String>; a closure on a dynamic
    // receiver crashed here before the broadcaster stream was typed.
    final a = broadcaster
        .stream(_channel)
        .listen((m) => got.add([...m.events.where((e) => e.endsWith('.create'))]));
    final b = broadcaster.stream(_channel).listen((m) => got.add(m.events));
    await pumpEventQueue();

    instances.single.emit(_channel, ['databases.guardian.x.create']);
    await pumpEventQueue();

    expect(got, hasLength(2));
    expect(got.first, ['databases.guardian.x.create']);
    await a.cancel();
    await b.cancel();
  });

  test('unsubscribes in the SDK when the last listener leaves', () async {
    final a = broadcaster.stream(_channel).listen((_) {});
    final b = broadcaster.stream(_channel).listen((_) {});
    await pumpEventQueue();

    await a.cancel();
    await pumpEventQueue();
    expect(instances.single.unsubscribeCalls, 0);

    await b.cancel();
    await pumpEventQueue();
    expect(instances.single.unsubscribeCalls, 1);

    // Channel was evicted: a new listener opens a fresh subscription.
    final c = broadcaster.stream(_channel).listen((_) {});
    await pumpEventQueue();
    expect(instances.single.subs, hasLength(2));
    await c.cancel();
  });

  test('reconnect() moves active channels to a new instance and resyncs',
      () async {
    final received = <RealtimeMessage>[];
    final active = broadcaster.stream(_channel).listen(received.add);
    final left = broadcaster.stream('other.channel').listen((_) {});
    await pumpEventQueue();
    await left.cancel();
    await pumpEventQueue();

    broadcaster.reconnect();
    await pumpEventQueue();

    expect(instances, hasLength(2));
    final [old, fresh] = instances;
    expect(old.disconnected, isTrue);
    // Only the still-active channel is re-subscribed.
    expect(fresh.subscribedChannels, [_channel]);
    // Listener survived the swap and got the empty resync event.
    expect(received, hasLength(1));
    expect(received.single.events, isEmpty);

    // Events on the new instance still reach the original listener.
    fresh.emit(_channel, ['databases.guardian.y.create']);
    await pumpEventQueue();
    expect(received, hasLength(2));
    await active.cancel();
  });

  test('closing the SDK stream closes listeners and evicts the channel',
      () async {
    var done = false;
    broadcaster.stream(_channel).listen((_) {}, onDone: () => done = true);
    await pumpEventQueue();

    await instances.single.subs.single.controller.close();
    await pumpEventQueue();
    expect(done, isTrue);

    // Evicted → nothing to re-attach on reconnect.
    broadcaster.reconnect();
    await pumpEventQueue();
    expect(instances.last.subs, isEmpty);
  });

  test('dispose() disconnects the current instance', () async {
    broadcaster.stream(_channel).listen((_) {});
    await pumpEventQueue();
    broadcaster.reconnect();
    await broadcaster.dispose();

    expect(instances.last.disconnected, isTrue);
  });
}
