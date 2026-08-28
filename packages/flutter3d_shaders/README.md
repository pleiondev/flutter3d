# flutter3d_shaders

The engine's shader sources, in GLSL, for every backend to compile.

One copy, shared, so that two backends cannot drift: `flutter3d_impeller` builds
them into a `flutter_gpu` bundle, `flutter3d_webgl` translates them to GLSL ES
3.00, and `flutter3d_cpu` implements the same stages in Dart against the same
declarations.

**A shader in one backend and not the others is a picture that differs by
platform and nothing that can see it.** That is not hypothetical: the sky was
rewritten here and the browser's copy of the table was a year out of date, so
two backends drew different skies until a generated file was finally diffed.

---

Part of [flutter3d](https://github.com/pleiondev/flutter3d), an **independent
implementation** of a 3D engine for Flutter — not a fork or a binding of
another engine, and not affiliated with the Flutter team. Three switchable
rendering backends: Impeller via Flutter GPU, WebGL2, and a software
rasteriser. glTF, OBJ and `.f3d` loading, six lighting models, shadows, bloom,
skinning, animation, BVH culling and picking; a deterministic fixed-step game
layer with collision, navigation, positional audio, and gamepad and touch
input. Three example games — shooter, platformer, racing — each built on its
genre package: [`flutter3d_game_shooter`](../flutter3d_game_shooter),
[`flutter3d_game_platformer`](../flutter3d_game_platformer),
[`flutter3d_game_racing`](../flutter3d_game_racing). A new game starts from
[`apps/flutter3d_template_app`](../../apps/flutter3d_template_app).
Documentation: <https://flutter3d.pleion.dev>.
