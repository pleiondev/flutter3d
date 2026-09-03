/// A level's brush materials are sampled with as much anisotropy as the
/// device allows, up to eight.
///
///     flutter test test/tiling_sampler_test.dart
///
/// The bridge is the one place that both knows the device and builds a
/// material, so it is where the level is decided: a brush floor seen along
/// its length is the surface the filter exists for, and a glTF sampler has no
/// way to ask. The number is clamped to the device rather than left for the
/// backend to clamp, because the renderer's own setting leaves a sampler that
/// already carries a level alone and the level it carries should be a true
/// one.
library;

import 'package:flutter3d_bridge/flutter3d_bridge.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('tilingSamplerFor', () {
    test('asks for eight on a device that offers sixteen', () {
      // Eight, not sixteen: the ceiling is a choice about where a corridor
      // floor stops improving, and `tilingAnisotropy` is that choice named.
      final sampler = LevelLoader.tilingSamplerFor(
        FakeBackend(maxAnisotropy: 16),
      );
      expect(sampler.anisotropy, LevelLoader.tilingAnisotropy);
      expect(sampler.anisotropy, 8);
      // And is otherwise the tiling sampler every wall always had.
      expect(sampler.mipFilter, MipFilter.linear);
      expect(sampler.widthAddressMode, SamplerAddressMode.repeat);
      expect(sampler.heightAddressMode, SamplerAddressMode.repeat);
    });

    test('clamps to a device that offers less', () {
      // Mutation: drop the `min`. A device answering four is handed eight,
      // which a backend clamps — but the renderer's setting then sees a
      // sampler carrying a level and leaves it, so the clamp has to be here.
      expect(
        LevelLoader.tilingSamplerFor(FakeBackend(maxAnisotropy: 4)).anisotropy,
        4,
      );
    });

    test('is the plain trilinear sampler on a device that offers none', () {
      // The software rasteriser answers one. Its picture of a level is the
      // picture it drew before the field existed, which is what keeps the
      // software golden set recorded.
      expect(
        LevelLoader.tilingSamplerFor(FakeBackend(maxAnisotropy: 1)),
        SamplerOptions.trilinearRepeat,
      );
    });
  });

  test('materialFrom puts the tiling sampler on every mapped slot', () {
    // The four slots a level material fills, all from the one sampler, so a
    // wall's normal map is filtered the way its albedo is. Mutation: leave
    // one slot at `_tiling` — it comes back at one tap while the others
    // carry eight, and the wall's shading crawls where its colour does not.
    final tiling = LevelLoader.tilingSamplerFor(FakeBackend(maxAnisotropy: 16));
    final material = LevelLoader.materialFrom(
      LevelMaterial(
        albedo: 'wall.png',
        normal: 'wall_n.png',
        orm: 'wall_orm.png',
      ),
      const <String, TextureHandle?>{},
      tiling: tiling,
    );
    expect(material.albedoSampler, tiling);
    expect(material.normalSampler, tiling);
    expect(material.metallicRoughnessSampler, tiling);
    expect(material.occlusionSampler, tiling);
  });

  test('materialFrom with no device given is isotropic, as it was', () {
    // The default a caller with nothing to ask gets: trilinear, repeating,
    // one tap. Not a regression, a statement — the level loader itself
    // always passes the device's.
    final material = LevelLoader.materialFrom(
      LevelMaterial(albedo: 'wall.png'),
      const <String, TextureHandle?>{},
    );
    expect(material.albedoSampler, SamplerOptions.trilinearRepeat);
  });
}
