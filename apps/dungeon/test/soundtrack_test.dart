/// What the crypt sounds like, asked of the level the game ships.
///
///     flutter test test/soundtrack_test.dart
///
/// **Total silence was undetectable, and one failure was visible from orbit.**
/// `SoLoudBackend` falls back to `SilentBackend` when it cannot open a device,
/// every call site goes on calling into the silence perfectly happily, and the
/// decisions about what to play lived in eight `_audio.play` calls inside a
/// widget — so nothing could ask what a step ought to sound like without a
/// device, a renderer and a window.
///
/// The visible one: the application chose between two sounds for four weapons,
/// on whether the ammunition was shells. **The rocket launcher and the fists
/// both cracked like a pistol**, and nine sounds shipped with no test naming
/// any of them.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dungeon/src/sounds.dart';
import 'package:dungeon/src/soundtrack.dart';
import 'package:dungeon/src/staging.dart';
import 'package:flutter3d_audio/flutter3d_audio.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';
import 'package:flutter3d_game_shooter/sample.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every `SoundDef` this game declares, read from the source.
///
/// From the file rather than from a list here, because a list here is the bug:
/// Dart has no reflection to ask a class what it holds, so the source is the
/// only place that knows — and it is the same source the compiler reads.
Set<String> _declared() => RegExp(r'static const SoundDef ([A-Za-z]+)')
    .allMatches(File('lib/src/sounds.dart').readAsStringSync())
    .map((RegExpMatch m) => m.group(1)!)
    .toSet();

/// The names inside the bank's own literal.
///
/// A `SoundBank` removes the *second list* — there is nothing left that has to
/// agree with anything — but it cannot see a constant declared beside it and
/// left out of it. No type can. This is the check that catches that, and it is
/// the one the platformer did not have on the day six of its fourteen sounds
/// went missing and the game was half mute for months.
Set<String> _inTheBank() {
  final source = File('lib/src/sounds.dart').readAsStringSync();
  final list = RegExp(
    r'static final SoundBank all = SoundBank\(<SoundDef>\[(.*?)\]\);',
    dotAll: true,
  ).firstMatch(source)!.group(1)!;
  return RegExp(r'([A-Za-z]+),')
      .allMatches(list)
      .map((RegExpMatch m) => m.group(1)!)
      .toSet();
}

const double _dt = 1.0 / 60.0;

Level _crypt() => Level.fromJson(
      jsonDecode(File('assets/levels/crypt.json').readAsStringSync())
          as Map<String, Object?>,
    );

/// The shipped level, the shipped registry, and ears on the result.
final class _Run {
  _Run({EntityRegistry? registry}) {
    final kinds = registry ?? sampleRegistry();
    level.addTo(world);
    staged = stage(
      level,
      world,
      input: input,
      registry: kinds,
      inventory: startingInventory(),
    );
    world.update();
  }

  final Level level = _crypt();
  final CollisionWorld world = CollisionWorld();
  final InputState input = InputState();
  late final Staged staged;

  final Soundtrack soundtrack = Soundtrack();
  final List<Heard> heard = <Heard>[];
  final List<Sustained> loops = <Sustained>[];

  bool _forward = false;

  void run(int steps, {bool forward = false}) {
    for (var i = 0; i < steps; i++) {
      input.beginStep();
      if (forward != _forward) {
        forward
            ? input.press(GameAction.moveForward)
            : input.release(GameAction.moveForward);
        _forward = forward;
      }
      staged.sim.step(_dt);
      input.endStep();
      final sounding = soundtrack.listen(staged.sim, staged.player);
      heard.addAll(sounding.once);
      loops.addAll(sounding.loops);
    }
  }

  /// Fires whatever is in hand, once, and listens.
  void fire() {
    input.beginStep();
    input.press(ShooterActions.fire);
    staged.sim.step(_dt);
    input.endStep();
    heard.addAll(soundtrack.listen(staged.sim, staged.player).once);
    input.beginStep();
    input.release(ShooterActions.fire);
    input.endStep();
  }

  Iterable<String> get names => heard.map((Heard h) => h.sound.name);
}

void main() {
  test('walking the shipped level is not silent', () {
    // **The claim the whole file exists for.** Before it, a build with no audio
    // device and a build with no sounds at all were the same green.
    //
    // Mutation: return an empty `Sounding`. Everything below fails at once,
    // which is the point — this is a smoke alarm, not a tuning fork.
    final run = _Run()..run(600, forward: true);

    expect(run.heard, isNotEmpty, reason: 'the game made no sound at all');
  });

  test('and walking makes footsteps, which this game never had', () {
    // A first-person game where walking is silent reads as sliding. There was
    // no footstep sound in the bank at all.
    final run = _Run()..run(600, forward: true);

    expect(run.names, contains('step'));
  });

  test('and standing still does not, because steps are metres not seconds', () {
    // Mutation: count time instead of distance. A player standing in a corridor
    // walks on the spot for ever, which is the single most noticeable way to
    // get this wrong.
    final run = _Run()..run(600);

    expect(run.names.where((String n) => n == 'step'), isEmpty);
  });

  group('every weapon', () {
    test('has a sound of its own, which two of the four did not', () {
      // **The bug this file was written for.** The application played
      // `ammo == shells ? shotgun : pistol`, so the launcher and the fists were
      // both a nine-millimetre crack.
      final track = Soundtrack();

      final sounds = <String>{
        for (final weapon in Weapons.all)
          track.forWeapon(weapon).name,
      };

      expect(sounds, hasLength(Weapons.all.length),
          reason: 'two weapons share a sound: $sounds');
    });

    test('and firing the one in hand is heard', () {
      // Through the simulation rather than through the table above: the arsenal
      // starts on the pistol, and what is checked is that pulling the trigger
      // reaches the ears at all.
      final run = _Run()..fire();

      expect(run.names, contains('pistol'));
    });
  });

  group('the machinery', () {
    test('grinds for as long as it moves, and stops once', () {
      // A door is not a gunshot. It starts, it follows the door, and it stops —
      // and a one-shot per step would be a door that stutters rather than
      // grinds.
      //
      // Driven directly rather than by walking to the button: what is being
      // checked is the shape of the sound, not the level's layout.
      final run = _Run();
      final door = run.staged.mechanisms['crypt_door']! as Door;
      door.activate(Activation(keys: <String>{door.key ?? ''}));
      run.run(30);

      // The door's own voice, and exactly one of it. The crypt starts a lift
      // on the same step, which is the reason this counts *this door's* begins
      // rather than all of them: two mechanisms are two voices, and that is the
      // property being checked.
      final mine = run.loops.where((Sustained s) => identical(s.key, door));
      expect(mine.where((Sustained s) => s.what == Voice.begin), hasLength(1),
          reason: 'the door ground once per step rather than once');
      expect(mine.first.sound, Sounds.stoneMove);
      // One voice per mechanism, stated as distinctness rather than as a
      // count: the count was `2` while the crypt was hand-written and had a
      // lift starting at load, which made this an assertion about that
      // document rather than about the rule.
      final begins =
          run.loops.where((Sustained s) => s.what == Voice.begin).toList();
      expect(begins.map((Sustained s) => s.key).toSet(), hasLength(begins.length),
          reason: 'two mechanisms shared one voice');
      // And followed for as long as it moved, or the grinding stays where the
      // door started while the door goes elsewhere.
      expect(mine.where((Sustained s) => s.what == Voice.follow), isNotEmpty,
          reason: 'the sound was left behind by the door making it');
    });

    test('and a locked door says so', () {
      // `Sounds.locked` existed and was played from the widget. Mutation: drop
      // the branch, and the one piece of feedback that tells a player they need
      // a key becomes nothing at all.
      // The refusal is put where the simulation puts it, because reaching it
      // through the game means walking the player to the door — and what is
      // being checked is the sound, not the crypt's floor plan.
      final run = _Run();
      final door = run.staged.mechanisms['crypt_door']! as Door;

      run.staged.sim.usedThisStep = door.activate(const Activation());
      expect(run.staged.sim.usedThisStep, isA<Refused>(),
          reason: 'the door opened for somebody with no key');
      run.heard.addAll(
        run.soundtrack.listen(run.staged.sim, run.staged.player).once,
      );

      expect(run.names, contains('locked'));
    });
  });

  group('the bank', () {
    test('holds every sound this game declares', () {
      // A declared sound that is not in the bank can never play: the backend
      // has no source for it, hands back no voice, and the emitter waits for
      // one for ever. It looks exactly like a sound nobody triggered.
      final missing = _declared().difference(_inTheBank());

      expect(missing, isEmpty,
          reason: 'declared and never preloaded, so silent in the real build: '
              '${missing.join(', ')}');
    });

    test('and nothing in it was never declared', () {
      expect(_inTheBank().difference(_declared()), isEmpty);
    });

    test('and every one of them has its file where it says', () {
      // The other way this goes silent, and it looks identical from outside: a
      // definition pointing at an asset that is not there.
      for (final sound in Sounds.all) {
        expect(File(sound.asset).existsSync(), isTrue,
            reason: '${sound.asset} is declared and not in the game');
      }
    });
  });
}
