/// `gfx-69n`: the family a build takes comes from the platform it is for.
///
///     dart test test/texture_family_target_test.dart
///
/// **A block format is a fact about the platform, not a taste.** Every desktop
/// GPU samples BC; ETC2 is required by OpenGL ES 3.0 and by Metal on every iOS
/// device this engine runs on. Getting it wrong is not a worse picture —
/// `uploadTexture` refuses a format the device does not sample, names it, and
/// the material draws untextured — which is why the hook reads the target
/// rather than picking a default and hoping.
///
/// The table is tested and the guard beside it is not, and that is deliberate:
/// `CodeAssetBuildInputBuilder`, which holds `setupCode`, is not among the
/// symbols `package:code_assets` exports, so a test cannot build an input that
/// names a target. What it can do is hold the mapping, which is the part with
/// something to get wrong; the guard is one read of a documented flag.
library;

import 'package:code_assets/code_assets.dart';
import 'package:flutter3d_build/flutter3d_build.dart';
import 'package:test/test.dart';

void main() {
  test('a desktop build takes BC', () {
    for (final os in <OS>[OS.macOS, OS.windows, OS.linux]) {
      expect(familyForTargetOS(os), TextureFamily.bc, reason: '$os');
    }
  });

  test('a phone build takes ETC2', () {
    // Required by OpenGL ES 3.0 and by Metal on every iOS device this engine
    // runs on, so this is what those two platforms guarantee rather than what
    // some device on them happens to have.
    for (final os in <OS>[OS.android, OS.iOS]) {
      expect(familyForTargetOS(os), TextureFamily.etc2, reason: '$os');
    }
  });

  test('a build that names no target compresses nothing', () {
    // `HookConfig.code` throws without a code configuration, and an asset-only
    // invocation that never mentions code assets is entitled to exist. A build
    // that cannot see its target must not invent one.
    expect(familyForTargetOS(null), TextureFamily.auto);
  });

  test('and neither does anything else', () {
    // The web is the one target where a choice would be a guess: a browser is
    // whatever machine it runs on. `ap-09`'s answer is to ship both sets and
    // choose at load time from the context's extensions, and until that exists
    // a build is left alone rather than handed a family half its visitors
    // cannot sample. Every other OS the enum grows falls here too, which is the
    // right default for a platform nobody has checked.
    for (final os in OS.values.where(
      (OS os) =>
          ![OS.macOS, OS.windows, OS.linux, OS.android, OS.iOS].contains(os),
    )) {
      expect(familyForTargetOS(os), TextureFamily.auto, reason: '$os');
    }
  });
}
