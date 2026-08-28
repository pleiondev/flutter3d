/// When the static half of the cube atlas is redrawn, and when it is kept.
///
///     flutter test test/static_shadow_rebake_test.dart
///
/// **The bake outlived the settings that made it.** That atlas holds everything
/// in a scene that never moves — a dungeon's walls — drawn once and kept for as
/// long as the atlas rows stay with the same lights, which is the whole reason a
/// room full of torches is affordable. Until [shouldBakeStatic] existed, "the
/// rows did not change" was the only thing that could make it redraw, so a
/// setting deciding *what the pass puts in it* could be changed and nothing
/// happened.
///
/// **Found by measurement, because nothing in the code looked wrong.** A probe
/// drew the crypt twice on Impeller with opposite `casterFaces` and got two
/// frames identical to the pixel: 419 pixels different from a no-shadow frame,
/// the same 419 both times. A setting with no visible effect and a setting that
/// never arrives look identical from outside; the same measurement with the
/// rule in place moves 647.
///
/// The rule is tested rather than the pass. Whether to bake is arithmetic on
/// four values; what the bake then draws needs a GPU, and
/// `flutter3d_webgl/test/engine_parity_test.dart` is where its pixels are held.
library;

import 'package:flutter3d/src/engine/render/shadow_settings.dart';
import 'package:flutter3d/src/engine/render/static_bake_key.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final key = StaticBakeKey.of(const ShadowSettings());

  test('a frame that changed nothing keeps the bake', () {
    // The property the bake exists for. Redrawing it every frame is six views
    // of the level's static geometry per occupied row, and the reason the atlas
    // is split in two in the first place.
    //
    // Mutation: return true unconditionally. Every frame re-bakes, and a
    // dungeon pays twenty-four extra passes a frame to draw walls that have not
    // moved since it loaded.
    expect(
      shouldBakeStatic(rowsChanged: false, baked: true, was: key, now: key),
      isFalse,
    );
  });

  test('and what it compares is a value, not an identity', () {
    // The key is rebuilt from the settings every frame, so it is never the same
    // object twice. Comparing identity would look right in a debugger and
    // re-bake for ever.
    //
    // Mutation: compare with `identical` inside `shouldBakeStatic`.
    expect(
      shouldBakeStatic(
        rowsChanged: false,
        baked: true,
        was: StaticBakeKey.of(const ShadowSettings()),
        now: StaticBakeKey.of(const ShadowSettings()),
      ),
      isFalse,
      reason: 'two keys built from equal settings compared as different',
    );
  });

  test('a row changing hands bakes again', () {
    // The reason that already worked: a row given to another light holds six
    // views from where the previous one stood.
    //
    // Mutation: drop `rowsChanged`. A torch that takes a row from another then
    // lights its room with the walls the old one saw.
    expect(
      shouldBakeStatic(rowsChanged: true, baked: true, was: key, now: key),
      isTrue,
    );
  });

  test('and so does an atlas nothing has baked yet', () {
    // The state after allocation and after a resolution change: the texture
    // exists and holds nothing anybody drew.
    //
    // Mutation: drop `!baked`. The first frame after a reallocation samples
    // uninitialised memory as though it were distances.
    expect(
      shouldBakeStatic(rowsChanged: false, baked: false, was: null, now: key),
      isTrue,
    );
  });

  group('a setting the pass reads', () {
    // **The defect this file is named after.** Each of these decides what the
    // bake draws, so each has to force one.
    //
    // Mutation for all three: drop the field from `StaticBakeKey`. The atlas
    // keeps what the previous setting produced for the rest of the run, and the
    // setting reads as one that does nothing.
    void bakesAgain(String what, ShadowSettings changed) {
      test('changing $what bakes again', () {
        expect(
          shouldBakeStatic(
            rowsChanged: false,
            baked: true,
            was: key,
            now: StaticBakeKey.of(changed),
          ),
          isTrue,
          reason: 'the new setting would never have reached the pass',
        );
      });
    }

    bakesAgain(
      'which side of a caster is recorded',
      const ShadowSettings(casterFaces: ShadowCasterFaces.front),
    );
    bakesAgain(
      'how far the volume is padded',
      const ShadowSettings(depthPadding: 1.8),
    );
    bakesAgain('the cube tile size', const ShadowSettings(cubeResolution: 256));
  });

  group('a setting the lookup reads', () {
    // The other half of the rule, and the reason the key is a list rather than
    // "any settings change": these are applied per fragment when the atlas is
    // sampled. Baking again for one of them would redraw every occupied row to
    // produce exactly the pixels already there.
    //
    // Mutation for all four: add the field to `StaticBakeKey`. Nothing looks
    // wrong, and the engine quietly does six times the work the moment a game
    // offers a shadow-quality slider.
    void keepsTheBake(String what, ShadowSettings changed) {
      test('changing $what does not', () {
        expect(
          shouldBakeStatic(
            rowsChanged: false,
            baked: true,
            was: key,
            now: StaticBakeKey.of(changed),
          ),
          isFalse,
          reason:
              '$what is read when the atlas is sampled, not when it is '
              'drawn',
        );
      });
    }

    keepsTheBake('the bias', const ShadowSettings(pointBias: 0.2));
    keepsTheBake(
      'the normal offset',
      const ShadowSettings(pointNormalOffset: 0.2),
    );
    keepsTheBake('the softness', const ShadowSettings(pointSoftness: 1.0));
    keepsTheBake('the strength', const ShadowSettings(strength: 0.5));
    // The cascade's tile size, which the cube atlas stopped reading when it
    // grew a budget of its own — and which would otherwise re-bake every
    // point-light row for a change to the sun's map.
    keepsTheBake(
      'the cascade tile size',
      const ShadowSettings(resolution: 2048),
    );
  });
}
