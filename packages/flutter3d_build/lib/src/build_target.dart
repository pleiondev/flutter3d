/// The platform a conversion is building for — `ap-09` in
/// `doc/asset-pipeline-plan.md`'s own row: "Настольные — BC; Android и iOS —
/// ETC2; веб — оба набора".
///
/// **Not `package:code_assets`'s `OS`.** That type has no `web` value at
/// all — native-asset build hooks never run for a web build, so the type a
/// future `hook/build.dart` (`ap-10`, not written yet) would receive cannot
/// name the one target this file's own row treats specially. Depending on
/// it here for the five it does name would also pull a native-asset-hooks
/// package into `flutter3d_build`, which stays buildable with `dart run`
/// and no Flutter SDK, for a type this package needs a sixth value from
/// anyway.
///
/// **Named by the caller, never guessed from the machine running this CLI.**
/// `TextureFamily.auto`'s own doc comment already refuses that guess for the
/// same reason: the device converting a texture is not the device that will
/// load it. A future `ap-10` hook passes its own `BuildInput`'s target
/// through to this by whichever of these six it maps to; today only an
/// explicit `--target` on the CLI does.
final class BuildTarget {
  const BuildTarget._(this.name);

  final String name;

  static const BuildTarget macos = BuildTarget._('macos');
  static const BuildTarget windows = BuildTarget._('windows');
  static const BuildTarget linux = BuildTarget._('linux');
  static const BuildTarget android = BuildTarget._('android');
  static const BuildTarget ios = BuildTarget._('ios');
  static const BuildTarget web = BuildTarget._('web');

  static const List<BuildTarget> values = <BuildTarget>[
    macos,
    windows,
    linux,
    android,
    ios,
    web,
  ];

  static BuildTarget? parse(String text) {
    for (final target in values) {
      if (target.name == text) return target;
    }
    return null;
  }

  @override
  String toString() => name;
}
