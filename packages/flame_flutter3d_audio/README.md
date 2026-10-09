# flame_flutter3d_audio

Sound for a Flame game bridged to flutter3d with
[`flame_flutter3d`](https://pub.dev/packages/flame_flutter3d), over
[`flutter3d_audio`](https://pub.dev/packages/flutter3d_audio).

```dart
class MyGame extends FlameGame with HasFlutter3d {
  late final sound = AudioSceneComponent(bank: Sounds.all);
  final engine = SoundEmitterComponent(Sounds.engine, playing: false);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    await addAll([sound, engine]);
  }

  // From the player's first key, touch or button:
  void takeOff() => sound.open();

  @override
  void update(double dt) {
    engine
      ..playing = flying
      ..rate = 0.8 + 0.5 * throttle;
    super.update(dt);
  }
}
```

## The game's sound

`AudioSceneComponent` holds one `AudioScene`. Until `open()` it plays into a
silent backend, so the game makes the same calls either way and nothing is
heard; a browser allows sound only after the user has touched the page, so
`open()` belongs to the first input. When the game has `HasFlutter3d`, the
listener rides on its 3D camera. The mix is worked out after everything else
has moved in the frame.

## Loops held by state

`SoundEmitterComponent` asks every frame whether it should be sounding: it
plays while it is in the game and `playing` is true, and stops when either
changes. Under a bridged component it sounds from that component's place in
the scene. Set `playing` before the game's children update (before
`super.update` in the game's own `update`) and the loop is mixed in the same
frame.

## Positional and flat sounds together

Each `SoundDef` says how it carries. `NoAttenuation()` is heard the same
everywhere, like music or an interface click. `InverseRolloff`, the default,
`LinearRolloff` and `ExponentialRolloff` fade with distance from the listener
up to their `maximum`, and every sound that carries is panned by which side
of the listener it is on.
Both play in the same scene: `play(boom, at: craft.scenePosition)` for a
blast out on the river, `play(click)` for a sound at the listener.

## Why a separate package

`flutter3d_audio` plays through SoLoud, which brings a native library and,
on the web, a script. A bridged game with no sound should carry neither, so
the bridge does not depend on this package.
