import 'dart:io';

import 'package:flutter3d_build/src/convert/xml.dart';
import 'package:flutter3d_core/formats.dart';
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
}
