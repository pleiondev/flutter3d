/// Two machines, one crawl: each drives its own hero and the rollback session
/// keeps the two simulations the same.
///
/// **Not a new mechanism.** `flutter3d_net`'s `NetSession` does the input
/// delay, the prediction by the last frame and the rollback when a guess was
/// wrong; this is the four functions a crawl hands it, as the racing game's
/// `NetRace` is for two cars. The crawl was built for it: fixed steps, a save
/// that carries the horde and the shots, and a restore that takes the world
/// back to before a monster was born — which is what a rollback past a birth
/// is.
///
/// **Slots are the room's, not the machine's.** Whoever made the room drives
/// hero nought and whoever joined drives hero one, on both machines; each
/// calling itself nought would be two people watching two different crawls.
library;

import 'package:flutter3d_game_crawler/flutter3d_game_crawler.dart';
import 'package:flutter3d_net/flutter3d_net.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

/// What one hero is asked to do for a step, as it travels.
///
/// **The stick in whole hundredths.** The session compares a frame it guessed
/// with the one that arrives by equality, and the two machines must apply the
/// same numbers; a double read off a stick is neither short nor stable, and
/// a hundredth of a stick is finer than a thumb.
Map<String, Object?> heroFrame(
  double x,
  double z, {
  required bool fire,
  required bool drink,
}) => <String, Object?>{
  'x': (x.clamp(-1.0, 1.0) * 100.0).round(),
  'z': (z.clamp(-1.0, 1.0) * 100.0).round(),
  'fire': fire,
  'drink': drink,
};

/// The far side of [heroFrame]: writes it onto [hero] for the step about to
/// run. An empty frame — nothing heard yet — is a hero standing still.
void applyHeroFrame(Map<String, Object?> frame, Hero hero) {
  hero.wish.setValues(
    ((frame['x'] as num?) ?? 0) / 100.0,
    0.0,
    ((frame['z'] as num?) ?? 0) / 100.0,
  );
  hero.fire = frame['fire'] == true;
  hero.drink = frame['drink'] == true;
}

/// One wire carrying several conversations, each named by a tag: the
/// handshake, and then a session per level.
///
/// **A session per level, and nothing crossing between them.** A level's
/// session counts its steps from nought, and frames of the last level still
/// on the wire when the next one starts would otherwise land in the new
/// session as steps it has not run yet. Each channel hears only messages sent
/// on its own tag.
final class Channels {
  Channels(this.wire) {
    wire.listen(_hear);
  }

  final NetTransport wire;
  final Map<String, void Function(Map<String, Object?>)> _listeners =
      <String, void Function(Map<String, Object?>)>{};

  /// The conversation named [tag].
  NetTransport channel(String tag) => _Channel(this, tag);

  void _hear(Map<String, Object?> message) {
    final tag = message['tag'];
    final body = message['body'];
    if (tag is! String || body is! Map) return;
    _listeners[tag]?.call(body.cast<String, Object?>());
  }
}

final class _Channel implements NetTransport {
  _Channel(this._channels, this._tag);

  final Channels _channels;
  final String _tag;

  @override
  void send(Map<String, Object?> message) =>
      _channels.wire.send(<String, Object?>{'tag': _tag, 'body': message});

  @override
  void listen(void Function(Map<String, Object?> message) onMessage) =>
      _channels._listeners[_tag] = onMessage;
}

final class NetCrawl {
  NetCrawl({
    required this.sim,
    required this.localSlot,
    required this.capture,
    required NetTransport transport,
    this.stepSeconds = 1.0 / 60.0,
    int inputDelay = 3,
    int maxRollbackFrames = 20,
    void Function(int step, Snapshot after)? onSettled,
  }) : assert(
         localSlot == 0 || localSlot == 1,
         'two machines, one hero each: the room decides which',
       ) {
    session = NetSession(
      transport: transport,
      captureLocalFrame: capture,
      applyAndStep: _applyAndStep,
      save: sim.save,
      restore: sim.restore,
      inputDelay: inputDelay,
      maxRollbackFrames: maxRollbackFrames,
      onSettled: onSettled,
    );
  }

  final CrawlerSimulation sim;

  /// Which hero this machine drives.
  final int localSlot;

  /// This machine's hero's frame for the step about to be captured — see
  /// [heroFrame].
  final Map<String, Object?> Function() capture;

  final double stepSeconds;

  late final NetSession session;

  /// Whether the far side has said anything yet.
  bool get connected => _connected;
  bool _connected = false;

  /// Captures, sends and runs one step. Call once per fixed step.
  void advance() => session.advance();

  void _applyAndStep(Map<String, Object?> local, Map<String, Object?> remote) {
    if (remote.isNotEmpty) _connected = true;
    final heroes = sim.heroes;
    applyHeroFrame(local, heroes[localSlot]);
    applyHeroFrame(remote, heroes[1 - localSlot]);
    sim.step(stepSeconds);
  }
}
