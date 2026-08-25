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
another engine, and not affiliated with the Flutter team.
Documentation: <https://flutter3d.pleion.dev>.
