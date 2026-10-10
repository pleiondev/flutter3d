/// `PeerRoom`'s hello as an older build says it.
///
///     dart test test/peer_room_test.dart
///
/// Each test was written by breaking what it covers; the mutation is named.
library;

import 'package:flutter3d_net/flutter3d_net.dart';
import 'package:test/test.dart';

void main() {
  test('a hello with no body is answered, so the older machine hears which '
      'version to update to', () {
    final (ours, theirs) = LoopbackWire.pair();
    final room = PeerRoom(ours, slot: 0);
    final heard = <Map<String, Object?>>[];
    theirs.listen(heard.add);

    // What a build from before `about` says: a tag and nothing else, so
    // protocol 0.0 by `WireHello.read`.
    theirs.send(<String, Object?>{'tag': 'hello', 'met': false});
    ours.tick();
    theirs.tick();

    // Mutation: drop a hello without a `body` before reading it, as before
    // 1.0. The room never answers and the older machine waits for ever
    // instead of telling its player to update.
    expect(room.refusal, contains('update the other game to protocol'));
    expect(room.hasMet, isFalse);
    final answer = heard.where((m) => m['tag'] == 'hello').single;
    expect(answer['met'], isTrue);
    expect(answer['protocol'], <int>[
      WireHello.currentProtocolMajor,
      WireHello.currentProtocolMinor,
    ]);
  });

  test('a frame with no body on a channel is dropped, not thrown on', () {
    final (ours, theirs) = LoopbackWire.pair();
    final room = PeerRoom(ours, slot: 0);
    final heard = <Map<String, Object?>>[];
    room.channel('play').listen(heard.add);
    theirs.send(<String, Object?>{'tag': 'play'});
    theirs.send(<String, Object?>{
      'tag': 'play',
      'body': <String, Object?>{'n': 1},
    });
    expect(ours.tick, returnsNormally);
    expect(heard, <Map<String, Object?>>[
      <String, Object?>{'n': 1},
    ]);
  });
}
