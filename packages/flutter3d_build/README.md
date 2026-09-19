# flutter3d_build

The build hook behind `dart run flutter3d:init`, part of
[flutter3d](https://flutter3d.pleion.dev): converts model and texture
sources into what the engine loads, on every build rather than as a
step somebody remembers to run.

**Plain Dart.** `hook/build.dart` is started by the Flutter tool as a
separate process with no window and no Flutter SDK to resolve inside
it — this package depends only on `flutter3d_core`, for its formats and geometry
libraries, and `package:hooks`, neither of which names Flutter, so a hook that needed
the SDK would not start on any machine that has not got it.

This is `ap-02`'s own scaffold: the package exists, `dart pub get`
resolves it, and it has nothing to export yet. What lands here next is
`doc/asset-pipeline-plan.md`'s own order — `dart run flutter3d_build:convert`
(`ap-03`), the manifest and directory convention (`ap-04`), and
`buildAssets()` itself, the function `hook/build.dart` calls (`ap-05`).
