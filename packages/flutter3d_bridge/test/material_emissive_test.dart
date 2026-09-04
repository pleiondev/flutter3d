/// A level material that says it glows reaches the renderer glowing.
///
///     flutter test test/material_emissive_test.dart
///
/// `emissive` is the one number in a level material that has no other way to
/// be seen: base colour, roughness and metallic all show up in a picture test
/// of a wall, but a surface lit from inside looks exactly like a bright one
/// until the bloom pass reads the emissive factor. The platformer's hazards,
/// checkpoints and exit all ask for it, so the seam that drops it drops them
/// all at once, silently.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_bridge/flutter3d_bridge.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  test('a glowing level material arrives with a factor and a strength', () {
    // Mutation: drop `emissiveStrength` from `materialFrom` and the strength
    // falls back to the renderer's default of one, which is a hazard glowing
    // twice as hard as the level asked; drop `emissive` and the factor is
    // black, which is the surface not glowing at all.
    final material = LevelLoader.materialFrom(
      LevelMaterial(
        baseColor: Vector4(0.75, 0.13, 0.10, 1.0),
        roughness: 0.6,
        emissive: 0.5,
      ),
      const <String, TextureHandle?>{},
      name: 'hazard',
    );
    expect(material.emissiveStrength, 0.5);
    // The base colour, not white: the level says how much a surface glows,
    // never in what colour, so the colour can only be the one it is painted.
    expect(material.emissive.x, closeTo(0.75, 1e-6));
    expect(material.emissive.y, closeTo(0.13, 1e-6));
    expect(material.emissive.z, closeTo(0.10, 1e-6));
  });

  test('a level material that says nothing does not glow', () {
    // The default has to stay black end to end: every wall in every level
    // goes through this seam, and a wall that emits its own base colour is a
    // crypt with no shadows in it.
    final material = LevelLoader.materialFrom(
      LevelMaterial(baseColor: Vector4(0.5, 0.5, 0.5, 1.0)),
      const <String, TextureHandle?>{},
    );
    expect(material.emissiveStrength, 0.0);
    expect(
      material.emissive.x * material.emissiveStrength,
      0.0,
      reason: 'the product is what the shader multiplies the map by',
    );
  });

  test('a mapped material keeps its glow as well as its textures', () {
    // The early return for an unmapped material is the line most likely to
    // grow a second copy of this wiring; one test on each side of it.
    final material = LevelLoader.materialFrom(
      LevelMaterial(
        baseColor: Vector4(0.95, 0.95, 0.85, 1.0),
        albedo: 'exit.png',
        emissive: 0.7,
      ),
      const <String, TextureHandle?>{},
    );
    expect(material.emissiveStrength, 0.7);
    expect(material.albedoSampler, SamplerOptions.trilinearRepeat);
  });
}
