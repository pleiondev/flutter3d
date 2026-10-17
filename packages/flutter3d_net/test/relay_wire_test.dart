@TestOn('vm')
library;

/// The relay's wire, held as a contract: its own messages under the
/// reserved key, every message it forwards in a party signed with the
/// sender's slot, a route that reaches one slot, and a client that reads
/// the welcome's protocol.
///
///     dart test test/relay_wire_test.dart
///
/// Against the real `bin/relay.dart` in a second process, and, for the
/// protocol, against a stand-in relay this test writes, since the real one
/// only ever speaks this build's protocol.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_net/flutter3d_net.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'wire_contract.dart';

Future<({Process process, int port})> _startRelay() async {
  final process = await Process.start('dart', <String>[
    'run',
    'bin/relay.dart',
    '0',
  ], workingDirectory: Directory.current.path);
  final port = Completer<int>();
  process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(
    (String line) {
      final match = RegExp(r'relay listening on (\d+)').firstMatch(line);
      if (match != null && !port.isCompleted) {
        port.complete(int.parse(match.group(1)!));
      }
    },
  );
  unawaited(process.stderr.drain<void>());
  return (
    process: process,
    port: await port.future.timeout(const Duration(seconds: 20)),
  );
}

/// A relay that welcomes every socket with [welcome] and nothing else.
Future<HttpServer> _standIn(Map<String, Object?> welcome) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((HttpRequest request) async {
    final socket = await WebSocketTransformer.upgrade(request);
    socket.add(jsonEncode(welcome));
  });
  return server;
}

/// The frames a raw socket hears, decoded.
final class _Raw {
  _Raw(this.channel) {
    channel.stream.listen((Object? raw) {
      if (raw is String) heard.add(jsonDecode(raw) as Map<String, Object?>);
    });
  }

  final WebSocketChannel channel;
  final List<Map<String, Object?>> heard = <Map<String, Object?>>[];

  static Future<_Raw> connect(Uri uri) async {
    final channel = WebSocketChannel.connect(uri);
    await channel.ready;
    return _Raw(channel);
  }

  void say(Map<String, Object?> message) =>
      channel.sink.add(jsonEncode(message));
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 300));

void main() {
  test('the relay speaks under the reserved key and signs what it forwards '
      'with the slot it gave', () async {
    final relay = await _startRelay();
    addTearDown(() => relay.process.kill());
    final base = Uri.parse('ws://127.0.0.1:${relay.port}/');
    final code = 'signed-${DateTime.now().microsecondsSinceEpoch}';
    final party = base.replace(
      pathSegments: <String>['party', code],
      queryParameters: <String, String>{
        'size': '2',
        'protocol':
            '${WireHello.currentProtocolMajor}.'
            '${WireHello.currentProtocolMinor}',
      },
    );

    final host = await _Raw.connect(party);
    addTearDown(host.channel.sink.close);
    final guest = await _Raw.connect(party);
    addTearDown(guest.channel.sink.close);
    await _settle();

    // Mutation: the welcome back under a bare `relay` key — a game message
    // with a `relay` field is then taken for the relay's.
    expect(host.heard.first, containsPair(PeerWire.engineKey, 'relay'));
    expect(host.heard.first, containsPair('event', 'welcome'));
    expect(host.heard.first, isNot(contains('relay')));
    // And as the snapshot has it, key for key: the real relay's words, not
    // the constants this file names them by.
    expectOnTheWire(host.heard.first, 'relay.welcome');
    expectOnTheWire(
      host.heard.firstWhere((m) => m['event'] == 'full'),
      'relay.full',
    );
    expect(guest.heard.first['slot'], 1);
    expect(
      host.heard.where((m) => m['event'] == 'full'),
      hasLength(1),
      reason: 'the full party is said under the key too',
    );

    // The guest claims to be the host. Mutation: forward verbatim, as the
    // relay did, and the host hears its own slot speak.
    guest.say(<String, Object?>{
      'from': 0,
      'body': <String, Object?>{'n': 1},
    });
    // A frame with no envelope at all is signed as well.
    guest.say(<String, Object?>{'n': 2});
    guest.channel.sink.add('not json');
    guest.channel.sink.add(Uint8List.fromList(<int>[1, 2, 3]));
    await _settle();
    final forwarded = host.heard
        .where((m) => m[PeerWire.engineKey] == null)
        .toList();
    expect(forwarded, <Map<String, Object?>>[
      <String, Object?>{
        'from': 1,
        'body': <String, Object?>{'n': 1},
      },
      <String, Object?>{'n': 2, 'from': 1},
      // Bytes go as the party wire's bytes frame, signed.
      <String, Object?>{
        'from': 1,
        'body': <String, Object?>{
          PeerWire.engineKey: PeerWire.bytesFrame,
          PeerWire.bytesKey: base64Encode(<int>[1, 2, 3]),
        },
      },
    ]);

    await guest.channel.sink.close();
    await _settle();
    // Mutation: `{"relay": "left"}` as before.
    expect(host.heard.last, <String, Object?>{
      PeerWire.engineKey: 'relay',
      'event': 'left',
      'slot': 1,
    });
  }, timeout: const Timeout(Duration(seconds: 40)));

  test('a party wire hears the slot the relay signed, and a route reaches '
      'one slot while a game\'s `to` reaches everybody', () async {
    final relay = await _startRelay();
    addTearDown(() => relay.process.kill());
    final base = Uri.parse('ws://127.0.0.1:${relay.port}/');
    final code = 'routed-${DateTime.now().microsecondsSinceEpoch}';
    final seats = <PartySeat>[
      for (var i = 0; i < 3; i++) await joinParty(base, code, size: 3),
    ];
    for (final seat in seats) {
      addTearDown(seat.socket.close);
    }
    final heard = <int, List<PeerMessage>>{
      for (final seat in seats) seat.slot: <PeerMessage>[],
    };
    for (final seat in seats) {
      seat.wire.listenFrom(heard[seat.slot]!.add);
    }

    // An engine message addressed to slot two goes in the route envelope.
    seats[0].wire.send(
      PeerSend(
        message: <String, Object?>{
          PeerWire.engineKey: ObserverMessages.step,
          'to': 2,
          'step': 7,
        },
      ),
    );
    // A game's own `to` is the game's. Mutation: route on a bare `to`, as
    // the relay did once observers were present.
    seats[0].wire.send(
      PeerSend(message: <String, Object?>{'to': 2, 'chat': 'hi'}),
    );
    await _settle();

    expect(heard[2]!.map((m) => m.from), <int>[0, 0]);
    expect(heard[2]!.map((m) => m.message), <Map<String, Object?>>[
      <String, Object?>{
        PeerWire.engineKey: ObserverMessages.step,
        'to': 2,
        'step': 7,
      },
      <String, Object?>{'to': 2, 'chat': 'hi'},
    ]);
    expect(heard[1]!.map((m) => m.message), <Object?>[
      <String, Object?>{'to': 2, 'chat': 'hi'},
    ]);
    expect(heard[0], isEmpty);
  }, timeout: const Timeout(Duration(seconds: 40)));

  test('a client refuses a relay of another protocol major, or one from '
      'before its messages carried the key, with a sentence', () async {
    const major = WireHello.currentProtocolMajor;
    const ours = '$major.${WireHello.currentProtocolMinor}';
    Future<Object?> joining(Map<String, Object?> welcome) async {
      final server = await _standIn(welcome);
      addTearDown(server.close);
      try {
        final seat = await joinParty(
          Uri.parse('ws://127.0.0.1:${server.port}/'),
          'any',
          timeout: const Duration(seconds: 5),
        );
        await seat.socket.close();
        return null;
      } on Object catch (error) {
        return error;
      }
    }

    Map<String, Object?> welcome(List<int>? protocol) => <String, Object?>{
      PeerWire.engineKey: 'relay',
      'event': 'welcome',
      'slot': 0,
      'size': 2,
      'code': 'any',
      'protocol': ?protocol,
    };

    // Mutation: the welcome's protocol not read — the machine plays on a
    // relay of the next major and misreads every message it forwards.
    expect(
      await joining(welcome(<int>[major + 1, 0])),
      isA<StateError>().having(
        (e) => e.message,
        'message',
        allOf(
          contains('speaks protocol ${major + 1}.0 and this machine $ours'),
          contains('update this game to protocol ${major + 1}'),
        ),
      ),
    );
    expect(
      await joining(welcome(<int>[major - 1, 3])),
      isA<StateError>().having(
        (e) => e.message,
        'message',
        contains('update the relay to protocol $major'),
      ),
    );
    expect(
      await joining(welcome(null)),
      isA<StateError>().having(
        (e) => e.message,
        'message',
        contains('names no protocol'),
      ),
    );
    // Mutation: a bare `relay` welcome waited on until the timeout, with no
    // reason given.
    expect(
      await joining(<String, Object?>{
        'relay': 'welcome',
        'slot': 0,
        'size': 2,
        'protocol': <int>[major, 0],
      }),
      isA<StateError>().having(
        (e) => e.message,
        'message',
        allOf(
          contains('speaks protocol $major.0'),
          contains('update the relay to protocol $ours'),
        ),
      ),
    );
    // A later minor of the same major is played with.
    final seat = await joining(welcome(<int>[major, 9]));
    expect(seat, isNull);
  }, timeout: const Timeout(Duration(seconds: 40)));
}
