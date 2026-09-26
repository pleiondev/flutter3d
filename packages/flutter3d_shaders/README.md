# flutter3d_shaders

The engine's shader sources, in GLSL, for every backend to compile.

There is one shared copy so that backends cannot drift apart:
`flutter3d_impeller` builds them into a `flutter_gpu` bundle, `flutter3d_webgl`
translates them to GLSL ES 3.00, and `flutter3d_cpu` implements the same
stages in Dart against the same declarations.

A shader that exists in one backend and not the others gives a picture that
differs by platform, and nothing notices. This has happened: the sky was
rewritten here while the browser's copy of the table was a year out of date,
so two backends drew different skies until a generated file was finally
diffed.

---

Part of [flutter3d](https://github.com/pleiondev/flutter3d), an independent
implementation of a 3D engine for Flutter. It is not a fork or a binding of
another engine, and it is not affiliated with the Flutter team. It has four
switchable rendering backends: Impeller via Flutter GPU, WebGL2, WebGPU and a
software rasteriser. It loads glTF, OBJ and `.f3d`, and has six lighting models,
shadows, bloom, skinning, animation, BVH culling and picking, plus a
deterministic fixed-step game layer with collision, navigation, positional
audio, and gamepad and touch input. Four example games (shooter, platformer,
racing, strategy) are each built on a genre package:
[`flutter3d_game_shooter`](https://pub.dev/packages/flutter3d_game_shooter),
[`flutter3d_game_platformer`](https://pub.dev/packages/flutter3d_game_platformer),
[`flutter3d_game_racing`](https://pub.dev/packages/flutter3d_game_racing),
[`flutter3d_game_strategy`](https://pub.dev/packages/flutter3d_game_strategy).
A new game starts from the editor's scaffold, which writes one from a template:
<https://flutter3d.pleion.dev/first-project/>. Documentation:
<https://flutter3d.pleion.dev>.
