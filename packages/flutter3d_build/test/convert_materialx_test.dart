import 'dart:io';

import 'package:flutter3d_build/src/convert/xml.dart';
import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_matter/flutter3d_matter.dart'
    show ConstantLaw, MaterialCatalog, OpticalProperties;
import 'package:flutter3d_shaders/flutter3d_shaders.dart' show dielectricF0;
import 'package:test/test.dart';

import 'convert_support.dart';

void main() {
  late Directory scratch;
  late ConvertRun run;
  setUpAll(() async {
    scratch = Directory.systemTemp.createTempSync('f3d_mtlx_');
    run = await convert(<String>['$fixtures/materials.mtlx'], output: scratch);
  });
  tearDownAll(() => scratch.deleteSync(recursive: true));

  MaterialDocument fmat(String name) =>
      readFmat(File('${scratch.path}/materials/$name.fmat').readAsBytesSync());

  test('the XML reader keeps elements, attributes and nesting', () {
    final root = parseXml(
      '<?xml version="1.0"?><!-- c --><a x="1"><b y=\'2\'/><c>t</c></a>',
    );
    expect(root.name, 'a');
    expect(root['x'], '1');
    expect(root.children.map((XmlElement e) => e.name), <String>['b', 'c']);
    expect(root.children.first['y'], '2');
  });

  test('constants are parameters: an .fmat, linear colour encoded', () {
    expect(run.code, 0);
    final gold = fmat('Gold');
    expect(gold.surface.metallic, 1.0);
    expect(gold.surface.roughness, closeTo(0.25, 1e-6));
    // 0.336 linear is about 0.62 encoded.
    expect(gold.surface.baseColor.toSrgb().b, closeTo(0.62, 0.01));
    expect(gold.surface.extensions?.clearcoat, 0.5);
    expect(File('${scratch.path}/materials/Gold.f3dmat').existsSync(), isFalse);
  });

  test('an image times a constant folds into the factor', () {
    final tinted = fmat('TintedWood');
    expect(tinted.images, <String>['../textures/wood.png']);
    expect(tinted.surface.baseColorTexture, isNotNull);
  });

  test('a graph the language can say is a program, beside an .fmat that '
      'names it', () {
    final program = File('${scratch.path}/materials/Gradient.f3dmat');
    expect(program.existsSync(), isTrue);
    // The program is checked by the parser before it is written.
    final parsed = parseMaterial(program.readAsStringSync());
    expect(parsed.name, 'Gradient');
    expect(parsed.light, isNotNull);
    expect(fmat('Gradient').surface.lightingModel?.shaderName, 'Gradient');
  });

  test('a node the language has no word for: the nearest surface, and a '
      'warning naming the node', () {
    expect(
      File('${scratch.path}/materials/Noisy.f3dmat').existsSync(),
      isFalse,
    );
    expect(fmat('Noisy').surface.baseColorTexture, isNull);
    expect(
      run.report('materials.mtlx')['warnings'],
      contains(contains('noise2d')),
    );
  });

  test('a program a material is not bound for reflects as glTF\'s '
      'dielectric', () {
    // Mutation: write the program's F0 as anything but `dielectricF0` and
    // the converted look moves off the engine's own.
    final program = File(
      '${scratch.path}/materials/Gradient.f3dmat',
    ).readAsStringSync();
    // The catalog's own formula for an index of 1.5, glTF's for a
    // non-metal: the default is the optical group's, not a number of its own.
    const glTF = OpticalProperties(
      refractiveIndex: ConstantLaw(1.5),
      source: 'glTF 2.0, the metallic-roughness model',
    );
    expect(dielectricF0, closeTo(glTF.f0!, 1e-15));
    expect(program, contains('mix(vec3(0.04, 0.04, 0.04), baseColor, metal)'));
  });

  test('a material no catalog entry is known by says so, and names none', () {
    // Mutation: bind by a guess and Gold is made of something; stay silent
    // and nobody learns why its physics took the defaults.
    expect(fmat('Gold').surface.physicalMaterial, isNull);
    expect(
      run.report('materials.mtlx')['mapped'],
      contains(contains('"Gold": no material in the catalog')),
    );
  });

  group('a document the catalog knows by its MaterialX name', () {
    late Directory out;
    late ConvertRun glass;
    setUpAll(() async {
      out = Directory.systemTemp.createTempSync('f3d_mtlx_bound_');
      glass = await convert(<String>[
        '$fixtures/standard_surface_glass.mtlx',
      ], output: out);
    });
    tearDownAll(() => out.deleteSync(recursive: true));

    test('is made of that material', () {
      // The MaterialX library names its examples by file, and the catalog
      // knows the glass as `standard_surface_glass`. Mutation: look up only
      // the material's own name and this is null.
      expect(glass.code, 0);
      final document = readFmat(
        File('${out.path}/materials/Glass.fmat').readAsBytesSync(),
      );
      expect(document.surface.physicalMaterial, 'f3d.glass');
      expect(
        glass.report('standard_surface_glass.mtlx')['mapped'],
        contains(contains('"Glass": made of f3d.glass')),
      );
    });

    test('its program reflects with the catalog\'s F0, not the default', () {
      // Soda-lime glass, n 1.52: an F0 of 0.0426 in the catalog's optical
      // group. Mutation: write `dielectricF0` whatever the binding says and
      // this reads 0.04.
      final f0 = MaterialCatalog.builtIn().byId('f3d.glass')!.optical!.f0!;
      expect(f0, 0.0426);
      expect(
        File('${out.path}/materials/Glass.f3dmat').readAsStringSync(),
        contains('mix(vec3(0.0426, 0.0426, 0.0426), baseColor, metal)'),
      );
    });
  });
}
