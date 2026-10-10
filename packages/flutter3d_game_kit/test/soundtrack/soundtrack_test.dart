/// The soundtrack: a cue sheet keyed by event type, the plugin that plays it
/// from the bus's frame channel, footsteps by distance, sounds with a
/// lifetime.
///
///     flutter test test/soundtrack_test.dart
///
/// Each test was written against the mutation named in it: the change to the
/// package that would let it pass while the package was wrong.
library;

import 'package:flutter3d_audio_core/flutter3d_audio_core.dart';
import 'package:flutter3d_game_kit/soundtrack.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const SoundDef _jump = SoundDef(
  name: 'jump',
  asset: 'a/jump.wav',
  attenuation: NoAttenuation(),
);
const SoundDef _locked = SoundDef(
  name: 'locked',
  asset: 'a/locked.wav',
  attenuation: NoAttenuation(),
);
const SoundDef _grind = SoundDef(
  name: 'grind',
  asset: 'a/grind.wav',
  loop: true,
  attenuation: NoAttenuation(),
);

final class _Jumped extends BusEvent {
  const _Jumped(this.at);

  final Vector3 at;

  /// A step event is declared with its codec.
  static final EventCodec<_Jumped> codec = EventCodec<_Jumped>.of(
    encode: (event) => <double>[event.at.x, event.at.y, event.at.z],
    decode: (data, _) => switch (data) {
      [final num x, final num y, final num z] => _Jumped(
        Vector3(x.toDouble(), y.toDouble(), z.toDouble()),
      ),
      _ => null,
    },
  );

  @override
  String get name => 'test.jumped';
}

final class _Locked extends BusEvent {
  const _Locked();

  @override
  String get name => 'test.locked';
}

CueSheet _sheet() => CueSheet()
  ..on<_Jumped>((e, out) => out.add(Heard(_jump, e.at)))
  ..on<_Locked>((e, out) => out.add(Heard(_locked, Vector3.zero())));

void main() {
  test('a sheet hears each event through the cue for its type, in order', () {
    // Mutation: drop the type check in `CueSheet.on`. Every cue would sound
    // for every event, and a jump would also be a locked door.
    final heard = _sheet().listen(<BusEvent>[
      _Jumped(Vector3(1.0, 0.0, 0.0)),
      const _Locked(),
      _Jumped(Vector3(2.0, 0.0, 0.0)),
    ]);
    expect(heard.map((h) => h.sound.name), <String>['jump', 'locked', 'jump']);
    expect(heard.first.at.x, 1.0);
    expect(_sheet().types, <Type>[_Jumped, _Locked]);
  });

  test('footsteps are paid for in metres on the ground, not in time', () {
    // Mutation: count calls instead of distance. Standing still would walk.
    final feet = Footsteps(stride: 2.0);
    expect(feet.walked(Vector3.zero(), grounded: true), isFalse);
    expect(feet.walked(Vector3.zero(), grounded: true), isFalse);
    expect(feet.walked(Vector3(1.5, 0.0, 0.0), grounded: true), isFalse);
    expect(feet.walked(Vector3(2.5, 0.0, 0.0), grounded: true), isTrue);
    // Height is not ground covered: a fall is not a walk.
    expect(feet.walked(Vector3(2.5, -5.0, 0.0), grounded: true), isFalse);
    // Mutation: keep counting in the air. A long jump would land on a step.
    expect(feet.walked(Vector3(10.0, -5.0, 0.0), grounded: false), isFalse);
    expect(feet.walked(Vector3(10.5, -5.0, 0.0), grounded: true), isFalse);
    expect(feet.walked(Vector3(11.5, -5.0, 0.0), grounded: true), isTrue);
    feet.reset();
    expect(feet.walked(Vector3(50.0, 0.0, 0.0), grounded: true), isFalse);
  });

  test('a sustained voice is begun, moved and stopped by its key', () {
    // Mutation: start a new voice on `follow`. A moving door would leave a
    // trail of grinding behind it.
    final scene = AudioScene(backend: SilentBackend());
    final voices = SustainedVoices();
    final door = Object();
    voices.perform(
      Sounding(
        <Heard>[Heard(_jump, Vector3.zero())],
        <Sustained>[Sustained.begin(door, _grind, Vector3.zero())],
      ),
      scene,
    );
    expect(voices.isRunning(door), isTrue);
    voices.perform(
      Sounding(const <Heard>[], <Sustained>[
        Sustained.follow(door, Vector3(0.0, 3.0, 0.0)),
      ]),
      scene,
    );
    final grinding = scene.emitters.where((e) => e.sound == _grind).single;
    expect(grinding.position.y, 3.0);

    voices.perform(
      Sounding(const <Heard>[], <Sustained>[Sustained.end(door)]),
      scene,
    );
    expect(grinding.isStopped, isTrue);
    expect(voices.count, 0);
    expect(Sustained.end(door).what, Voice.end);
  });

  test('stopping every voice silences the ones no end will reach', () {
    // Mutation: clear the map without stopping the voices. A door caught by
    // a level change would grind for ever.
    final scene = AudioScene(backend: SilentBackend());
    final voices = SustainedVoices()
      ..perform(
        Sounding(const <Heard>[], <Sustained>[
          Sustained.begin(Object(), _grind, Vector3.zero()),
        ]),
        scene,
      );
    voices.stop();
    expect(scene.emitters.every((e) => e.isStopped), isTrue);
    expect(voices.count, 0);
  });

  test('the plugin plays the sheet from the frame channel', () {
    // Mutation: play inside the step. The plugin would be refused as a view
    // plugin, and a rollback would play its sounds again.
    final scene = AudioScene(backend: SilentBackend());
    final plugin = SoundtrackPlugin(_sheet(), scene: () => scene);
    expect(plugin.manifest.touches, PluginTouches.view);
    expect(plugin.manifest.idProblem, isNull);

    final loop = EngineLoop(
      input: InputState(),
      plugins: <Flutter3dPlugin>[plugin],
    );
    loop.events.declare<_Jumped>('test.jumped', codec: _Jumped.codec);
    var published = false;
    loop.addSystem('jump once', LoopPhase.rules, (c) {
      if (published) return;
      published = true;
      c.publish(_Jumped(Vector3(4.0, 0.0, 0.0)));
    });
    loop
      ..frame(1.0 / 60.0)
      ..frame(1.0 / 60.0);
    expect(scene.emitters.where((e) => e.sound == _jump), hasLength(1));
  });

  test('a sheet given a bus is mixed on it in the frame it is heard', () {
    // Mutation: drop `bus` on the way to `scene.play`. The cue would sound on
    // its own effects bus, and the UI slider would not reach it.
    const ui = AudioBus('ui');
    final backend = SilentBackend();
    final scene = AudioScene(backend: backend);
    scene.mixer.setVolume(ui, 0.5);
    final loop = EngineLoop(
      input: InputState(),
      plugins: <Flutter3dPlugin>[
        SoundtrackPlugin(_sheet(), scene: () => scene, bus: ui),
        AudioPlugin(scene: () => scene, listener: AudioListener()),
      ],
    );
    loop.events.declare<_Jumped>('test.jumped', codec: _Jumped.codec);
    var published = false;
    loop.addSystem('jump once', LoopPhase.rules, (c) {
      if (published) return;
      published = true;
      c.publish(_Jumped(Vector3(4.0, 0.0, 0.0)));
    });
    // The first frame that runs the step publishes, and the frame channel
    // delivers in that same frame; whichever frame that is, the voice must
    // already be on the bus when it is first live, never at full gain first.
    for (var i = 0; i < 3 && backend.live.isEmpty; i++) {
      loop.frame(1.0 / 60.0);
    }
    expect(backend.live, hasLength(1));
    expect(scene.emitters.single.bus, ui);
    expect(backend.live.single.gain, closeTo(0.5, 1e-12));
  });
}
