/// A level material that names what it is made of, by id: the catalogue's
/// optical group fills in what the document leaves unsaid, and never what
/// it says.
///
///     dart test test/level_substance_test.dart
library;

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show LinearColor;
import 'package:flutter3d_level_scene/flutter3d_level_scene.dart';
import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

/// One floor in a material made of [substance], with [said] beside it.
Level _floor(String substance, {Map<String, Object?> said = const {}}) =>
    Level.fromJson(<String, Object?>{
      'version': 5,
      'materials': <String, Object?>{
        'pipe': <String, Object?>{'physicalMaterial': substance, ...said},
      },
      'brushes': <Object?>[
        <String, Object?>{
          'material': 'pipe',
          'at': <double>[0.0, -0.5, 0.0],
          'size': <double>[4.0, 1.0, 4.0],
        },
      ],
    });

void main() {
  final device = CpuDevice(
    width: 4,
    height: 4,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final catalog = MaterialCatalog.builtIn();
  final copper = catalog.byId('f3d.copper')!.optical!.metalReflectance!;

  RenderMaterial drawn(Level level, {MaterialCatalog? materials}) => LevelScene(
    materials: materials,
  ).build(level, device: device).batches.single.node.material;

  test('a metal named by id is drawn as that metal', () {
    // Mutation: drop `substance:` from the `materialFrom` call in
    // `brushBatches`. The copper pipe is then the document's default grey
    // dielectric.
    final material = drawn(_floor('f3d.copper'), materials: catalog);
    expect(material.metallic, 1.0);
    expect(material.baseColor.r, closeTo(copper.red, 1e-12));
    expect(material.baseColor.g, closeTo(copper.green, 1e-12));
    expect(material.baseColor.b, closeTo(copper.blue, 1e-12));
  });

  test('what the document says wins over the catalogue', () {
    // Mutation: ignore what the document said in `_lookOf`. A painted
    // copper pipe then loses its paint to the metal's colour.
    final material = drawn(
      _floor(
        'f3d.copper',
        said: <String, Object?>{
          'metallic': 0.0,
          'baseColor': <double>[0.2, 0.4, 0.2, 1.0],
        },
      ),
      materials: catalog,
    );
    expect(material.metallic, 0.0);
    // Read through the document's single precision.
    expect(
      material.baseColor.g,
      closeTo(LinearColor.fromSrgb(0.2, 0.4, 0.2, 1.0).g, 1e-6),
    );
  });

  test('a dielectric, or no catalogue, keeps the document\'s numbers', () {
    final plain = drawn(_floor('f3d.copper'));
    expect(plain.metallic, 0.0);
    final concrete = drawn(_floor('f3d.concrete'), materials: catalog);
    expect(concrete.metallic, 0.0);
    expect(concrete.baseColor, LinearColor.fromSrgb(0.5, 0.5, 0.5));
  });

  test('a material\'s parameter values reach the surface as written', () {
    // Mutation: leave `LevelMaterial.parameters` out of `materialFrom`. The
    // values a level gives a material's parameters then reach nothing.
    final material = drawn(
      _floor(
        'f3d.copper',
        said: <String, Object?>{
          'parameters': <String, Object?>{
            'glow': 2.0,
            'tint': <double>[0.1, 0.2, 0.3],
          },
        },
      ),
    );
    expect(material.parameters['glow'], <double>[2.0]);
    expect(material.parameters['tint']![2], closeTo(0.3, 1e-6));
  });
}
