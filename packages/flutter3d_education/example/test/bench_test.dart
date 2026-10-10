import 'dart:math' as math;
import 'dart:typed_data';

import 'package:chemlab/chemlab.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart' show DartFluid;
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:flutter3d_testing/flutter3d_testing.dart';
import 'package:flutter_test/flutter_test.dart';

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
  // On the run's physics, as `main` puts the app: the core, or the Dart
  // reference with `--dart-define=FLUTTER3D_PHYSICS=dart`.
  setUpAll(startPhysics);

  test('the bench\'s liquids are stepped on the run\'s physics', () {
    // Mutation: a bench whose world is given the reference, and a run on
    // the core pours on Dart anyway.
    final bench = Bench(
      cpuTestDevice(width: 8, height: 8).device,
      physics: usePhysics(),
    );
    expect(bench.world.solver, same(bench.physics.fluid));
    expect(
      bench.world.solver,
      askedPhysics == 'dart' ? isA<DartFluid>() : isA<NativeLiquid>(),
    );
  });

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

  test('pouring fills to the level asked, within its glass', () async {
    final kit = cpuTestDevice(width: 8, height: 8);
    final bench = Bench(kit.device);
    final beaker = bench.vessels.firstWhere((v) => v.name == 'Beaker');
    final before = beaker.layers.single.node.mesh;

    bench.pour(beaker, 0.03);
    expect(beaker.level, closeTo(0.03, 1e-9));
    expect(identical(beaker.layers.single.node.mesh, before), isFalse);

    // Mutation: drop the clamp, and a beaker holds more than it can.
    bench.pour(beaker, 5);
    expect(beaker.level, closeTo(beaker.highest, 1e-9));
  });

  test('the bench stays inside the eight lights an object is lit by', () {
    // Mutation: give the cylinder and the flask caustics too, and a ninth
    // light pushes the sun out and its shadow with it.
    final kit = cpuTestDevice(width: 8, height: 8);
    final bench = Bench(kit.device);
    final lights = bench.scene.root.children.whereType<LightNode>();
    expect(lights.length, lessThanOrEqualTo(LightNode.maxLights));
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
    final layer = tube.layers.single;
    expect(identical(layer.reflection.mesh, layer.node.mesh), isTrue);
  });

  test('the glass and the liquid leave their shadow to the card', () {
    // Mutation: let the glass cast as well, and its own coarse shadow lies
    // over the worked-out one.
    final kit = cpuTestDevice(width: 8, height: 8);
    final bench = Bench(kit.device);
    final tube = bench.vessels.first;
    final glass = tube.glassNode;
    expect(glass.castsShadow, isFalse);
    expect(tube.layers.single.node.castsShadow, isFalse);
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
      clearColorSrgb: Vector4(0.1, 0.11, 0.14, 1.0),
      build: (request) {
        final bench = Bench(request.device);
        final camera = CameraNode(name: 'eye')
          ..setPosition(0.01, 0.085, 0.255)
          ..lookAt(Vector3(0.01, 0.034, 0));
        return (scene: bench.scene, camera: camera);
      },
    );
    await expectMatchesGolden(frame, 'test/goldens/bench.png');
  });

  test('a tap rings the surface, and the rings die away', () {
    final kit = cpuTestDevice(width: 8, height: 8);
    final bench = Bench(kit.device);
    final tube = bench.vessels[1];
    bench.tap(tube);
    expect(bench.step(1 / 60), isTrue);
    var seconds = 0.0;
    while (bench.step(1 / 60)) {
      seconds += 1 / 60;
      expect(seconds, lessThan(30));
    }
  });

  group('leaning and topping up — what the overflowing flask did', () {
    // Reported from the bench: a flask leant to its furthest and topped up
    // threw a stream, thirty thousand drops eleven metres up and a frame of
    // three and a half seconds. Three causes, each held here; the drops
    // themselves are held in `flutter3d_physics`.

    test('leant to its furthest, a glass spills nothing', () {
      // Mutation: turn the glass at once in `lean` — its old level is laid
      // out as a wave no water makes, and four fifths go over the lip.
      final kit = cpuTestDevice(width: 8, height: 8);
      final bench = Bench(kit.device);
      final flask = bench.vessels.firstWhere((v) => v.name == 'Flask');
      final held = flask.liquid.volume;
      bench.lean(flask, bench.maxLean(flask));
      for (var i = 0; i < 120; i++) {
        bench.step(1 / 60);
        expect(bench.world.jets, isEmpty, reason: 'it ran at frame $i');
      }
      expect(flask.tilt, closeTo(bench.maxLean(flask), 1e-9));
      expect(flask.liquid.volume, closeTo(held, held * 1e-9));
    });

    test('a lean is turned at a hand\'s pace, not at once', () {
      final kit = cpuTestDevice(width: 8, height: 8);
      final bench = Bench(kit.device);
      final flask = bench.vessels.firstWhere((v) => v.name == 'Flask');
      bench.lean(flask, 1.0);
      expect(flask.tilt, 0.0);
      expect(flask.aimTilt, 1.0);
      bench.step(0.1);
      expect(flask.tilt, closeTo(0.2, 1e-9));
    });

    test('topped up while it leans, a glass fills only to what it holds', () {
      // Mutation: fill to the upright level in `pour` — the rest runs
      // straight over the lip.
      final kit = cpuTestDevice(width: 8, height: 8);
      final bench = Bench(kit.device);
      final flask = bench.vessels.firstWhere((v) => v.name == 'Flask');
      bench.lean(flask, bench.maxLean(flask));
      for (var i = 0; i < 90; i++) {
        bench.step(1 / 60);
      }
      final everything = bench.world.volume;
      bench.pour(flask, flask.highest);
      final added = bench.world.volume - everything;
      expect(added, greaterThan(0.0), reason: 'it was topped up');
      for (var i = 0; i < 120; i++) {
        bench.step(1 / 60);
        expect(bench.world.jets, isEmpty, reason: 'it ran at frame $i');
      }
      var drops = 0;
      bench.world.particles.forEach((_, f) => drops += f.count);
      expect(drops, 0);
    });
  });

  test('sharing pours half into the clean tube, lip over the rim', () {
    final kit = cpuTestDevice(width: 8, height: 8);
    final bench = Bench(kit.device);
    final from = bench.vessels[2];
    final to = bench.clean;
    final total = from.liquid.volume;
    final everything = bench.world.volume;
    expect(bench.canShare(from), isTrue);
    bench.share(from);
    var seconds = 0.0;
    var poured = false;
    while (bench.busy) {
      final before = from.liquid.volume;
      bench.step(1 / 60);
      seconds += 1 / 60;
      expect(seconds, lessThan(30));
      if (from.liquid.volume < before - 1e-12) {
        poured = true;
        // While it runs, its lip is over the clean tube's mouth.
        // Its own matrix: it hangs off the root, and the world's is only
        // brought up to date when the scene is drawn.
        final lip = from.body.localMatrix.transformed3(from.lip);
        final off = Vector2(lip.x - to.at.x, lip.z - to.at.z).length;
        expect(off, lessThan(to.lip.z));
      }
    }
    while (bench.world.volume > 0 && bench.world.jets.isNotEmpty) {
      bench.step(1 / 60);
    }
    expect(poured, isTrue);
    // The two hold about the same, and nothing is lost: what is not in them
    // is drops on the bench.
    final mine = from.liquid.volume;
    final theirs = to.liquid.volume;
    expect(mine, closeTo(total / 2, total * 0.05));
    expect(theirs, closeTo(total / 2, total * 0.05));
    expect(bench.world.volume, closeTo(everything, everything * 1e-9));
    // And the clean tube holds the colour poured into it.
    expect(bench.color(to), bench.color(from));
  });

  test('two dyes poured together are the colour light through both is', () {
    final kit = cpuTestDevice(width: 8, height: 8);
    final bench = Bench(kit.device);
    final blue = bench.vessels[1];
    final orange = bench.vessels[3];
    final to = bench.clean;
    to.liquid.pour(1e-6, concentrations: {blue.name: 1.0});
    to.liquid.pour(1e-6, concentrations: {orange.name: 1.0});
    final mixed = bench.color(to);
    // Half of each: each dye's absorbance at half strength, added — in
    // linear light, where Beer and Lambert hold. Mutation: take the
    // logarithm of the sRGB numbers, and the mixture is lighter than this.
    final expected = math.sqrt(blue.dye.toLinear().r * orange.dye.toLinear().r);
    expect(mixed.toLinear().r, closeTo(expected, 0.005));
  });

  test('hydrochloric acid is colourless, and only dilutes', () {
    // Mutation: give HCl the pale blue it had. A tenth-molar acid has no
    // colour, and what it is poured into should only get paler.
    final kit = cpuTestDevice(width: 8, height: 8);
    final bench = Bench(kit.device);
    final acid = bench.vessels[0];
    expect(acid.name, 'HCl');
    expect(acid.dye.toARGB32(), 0xFFFFFFFF);
    final blue = bench.vessels[1];
    final to = bench.clean;
    to.liquid.pour(1e-6, concentrations: {blue.name: 1.0});
    to.liquid.pour(1e-6, concentrations: const {});
    final diluted = bench.color(to).toLinear();
    expect(diluted.r, closeTo(math.sqrt(blue.dye.toLinear().r), 0.005));
  });

  test('a pour drawn at uneven frames still pours half', () {
    // A browser's frames are anything from a 90th to a 30th of a second.
    // Mutation: stamp the glass's place with the liquid's own clock, and
    // the frames that ran one fixed step against those that ran eight read
    // as jolts: the liquid is thrown out of the glass and the clean tube
    // gets little of it.
    final kit = cpuTestDevice(width: 8, height: 8);
    final bench = Bench(kit.device);
    final from = bench.vessels[2];
    final to = bench.clean;
    final total = from.liquid.volume;
    bench.share(from);
    const frames = [1 / 60, 1 / 40, 1 / 90, 1 / 30, 1 / 75];
    var i = 0;
    var seconds = 0.0;
    while (bench.busy) {
      final frame = frames[i++ % frames.length];
      bench.step(frame);
      seconds += frame;
      expect(seconds, lessThan(30));
    }
    expect(from.liquid.volume, closeTo(total / 2, total * 0.05));
    expect(to.liquid.volume, closeTo(total / 2, total * 0.05));
  });

  test('a pour never asks the device for a buffer of no bytes', () {
    // Metal makes none, and a stream with no parcels yet threw on every
    // frame of a pour in the macOS app. The software device takes one, so
    // this looks at the meshes rather than waiting for a throw. Mutation:
    // upload the empty stream as it is.
    final kit = cpuTestDevice(width: 8, height: 8);
    final bench = Bench(kit.device);
    final from = bench.vessels[1];
    bench.share(from);
    void check(SceneNode node) {
      if (node is MeshNode && node.mesh is DeviceMesh) {
        expect(
          (node.mesh as DeviceMesh).vertexCount,
          greaterThan(0),
          reason: node.name,
        );
      }
      node.children.forEach(check);
    }

    var seconds = 0.0;
    while (bench.world.jets.isEmpty) {
      bench.step(1 / 60);
      seconds += 1 / 60;
      expect(seconds, lessThan(10));
    }
    check(bench.scene.root);
  });
}
