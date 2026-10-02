import 'dart:typed_data';

import 'package:chemlab/chemlab.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_testing/flutter3d_testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// flutter_test draws text in a test font unless the real one is loaded. The
/// label's fonts are flutter_math_fork's own, which the test's asset bundle
/// carries like any dependency's.
Future<void> loadKatexFonts() async {
  const faces = <String, List<String>>{
    'Main': ['Regular', 'Italic', 'Bold', 'BoldItalic'],
    'Math': ['Italic', 'BoldItalic'],
    'Size1': ['Regular'],
    'Size2': ['Regular'],
  };
  for (final MapEntry(key: face, value: styles) in faces.entries) {
    final loader = FontLoader('packages/flutter_math_fork/KaTeX_$face');
    for (final style in styles) {
      loader.addFont(
        rootBundle.load(
          'packages/flutter_math_fork/lib/katex_fonts/fonts/'
          'KaTeX_$face-$style.ttf',
        ),
      );
    }
    await loader.load();
  }
}

void main() {
  testWidgets('a label is the formula on paper, turned for the lathe', (
    tester,
  ) async {
    await tester.runAsync(loadKatexFonts);
    final vessel = standardVessels().firstWhere((v) => v.name == 'K2Cr2O7');
    final key = GlobalKey();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(key: key, child: LabelCard(vessel.solution!)),
        ),
      ),
    );
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = forLathe((await tester.runAsync(() => capture(boundary)))!);

    // The card has the strip's proportions. Mutation: a fixed wide card on a
    // tall strip, and the text is pulled upwards on the glass.
    expect(
      (image.width, image.height),
      (LabelCard.size.width.toInt(), LabelCard.size.height.toInt()),
    );
    expect(image.width / image.height, closeTo(labelAspect(), 0.01));
    final pixels = Uint32List.view(image.pixels.buffer);
    int rgb(int p) => p & 0x00FFFFFF;
    // Turned half round, the band that was along the top is along the
    // bottom rows. Mutation: skip the turn, and the band is at the top.
    final band = rgb(pixels[(image.height - 10) * image.width + 256]);
    final paper = rgb(pixels[60 * image.width + 20]);
    expect(band, isNot(paper));
    // Ink: the formula leaves dark pixels in the middle of the label.
    // Mutation: draw the paper and no text.
    final ink = pixels.where((p) {
      final r = p & 0xFF, g = (p >> 8) & 0xFF, b = (p >> 16) & 0xFF;
      return r + g + b < 200;
    }).length;
    expect(ink, greaterThan(2000));
  });

  test('pouring cuts the liquid at the new level, within its glass', () async {
    final kit = cpuTestDevice(width: 8, height: 8);
    final bench = Bench(kit.device);
    final beaker = bench.vessels.firstWhere((v) => v.name == 'Beaker');
    final before = beaker.liquid.mesh;

    bench.pour(beaker, 0.3);
    expect(beaker.level, 0.3);
    expect(identical(beaker.liquid.mesh, before), isFalse);

    // Mutation: drop the clamp, and a beaker holds more than it can.
    bench.pour(beaker, 5);
    expect(beaker.level, beaker.highest);
  });

  test('the bench stays inside the eight lights an object is lit by', () {
    // Mutation: give the cylinder and the flask caustics too, and a ninth
    // light pushes the sun out and its shadow with it.
    final kit = cpuTestDevice(width: 8, height: 8);
    final bench = Bench(kit.device);
    final lights = bench.scene.root.children.whereType<LightNode>();
    expect(lights.length, lessThanOrEqualTo(LightBuffer.maxLights));
  });

  test('pouring paints the shadow again and moves the reflection', () {
    final kit = cpuTestDevice(width: 8, height: 8);
    final bench = Bench(kit.device);
    final tube = bench.vessels.first;
    final before = tube.shadow.material.albedo;

    bench.pour(tube, tube.highest);
    // Mutation: keep the picture painted for the old level, and the shadow
    // shows the liquid where it was.
    expect(tube.shadow.material.albedo, isNot(same(before)));
    expect(tube.shadow.shadowCasting, ShadowCastingMode.shadowsOnly);
    // Mutation: leave the reflection on the old mesh, and it shows the
    // level before the pour.
    expect(identical(tube.liquidReflection.mesh, tube.liquid.mesh), isTrue);
  });

  test('the glass and the liquid leave their shadow to the card', () {
    // Mutation: let the glass cast as well, and its own coarse shadow lies
    // over the worked-out one.
    final kit = cpuTestDevice(width: 8, height: 8);
    final bench = Bench(kit.device);
    final tube = bench.vessels.first;
    final glass = tube.glassNode;
    expect(glass.castsShadow, isFalse);
    expect(tube.liquid.castsShadow, isFalse);
    expect(glass.receivesTranslucentShadows, isFalse);
  });

  test(
    'a label goes on a tube once its picture exists, and only on a tube',
    () {
      final kit = cpuTestDevice(width: 8, height: 8);
      final bench = Bench(kit.device);
      final tube = bench.vessels.first;
      final beaker = bench.vessels.firstWhere((v) => v.name == 'Beaker');
      final picture = Rgba8Image(
        width: 2,
        height: 2,
        pixels: Uint8List.fromList(List<int>.filled(16, 255)),
      );

      // Mutation: put blank labels up in the constructor.
      expect(tube.label, isNull);
      expect(bench.dress(tube, picture), isNotNull);
      expect(tube.label!.material.albedo, isNotNull);
      expect(tube.body.children, contains(tube.label));

      // Drawn again, the old label goes.
      final first = tube.label!;
      bench.dress(tube, picture);
      expect(tube.body.children, isNot(contains(first)));
      expect(first.parent, isNull);

      expect(bench.dress(beaker, picture), isNull);
      expect(beaker.label, isNull);
    },
  );

  test('the bench, drawn with no GPU', () async {
    // Blank labels: text is rasterised by the platform, which differs between
    // machines; the glass, the liquids and the light are the engine's, and
    // the software backend draws them the same everywhere.
    final frame = await renderFrame(
      width: 960,
      height: 504,
      settings: benchSettings,
      clearColor: Vector4(0.1, 0.11, 0.14, 1.0),
      build: (request) {
        final bench = Bench(request.device);
        final camera = CameraNode(name: 'eye')
          ..setPosition(0.1, 0.85, 2.55)
          ..lookAt(Vector3(0.1, 0.34, 0));
        return (scene: bench.scene, camera: camera);
      },
    );
    await expectMatchesGolden(frame, 'test/goldens/bench.png');
  });
}
