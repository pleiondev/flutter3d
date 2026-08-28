/// What the field looks like, and what it must not look like.
///
/// The rivals used to be boxes. They are the same model the player drives now,
/// which means a rival's colour is no longer a material of its own but a tint
/// written into a copy of the model's materials — and the two ways that goes
/// wrong are painting the parts that are not bodywork, and painting materials
/// somebody else is also using.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_demo_racing/src/looks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// A device is needed only because a [MeshNode] owns an uploaded mesh; nothing
/// here draws, so the smallest one that can accept an upload will do.
CpuDevice _device() => CpuDevice(
  width: 4,
  height: 4,
  shaders: CpuShaderLibrary(builtinCpuShaders()),
);

/// One node wearing a material by that name, which is all [Looks.paint] reads.
MeshNode _part(CpuDevice device, String name) =>
    carBox(device, Material(name: name), name: name);

/// A texture standing in for a livery: only its presence is ever read.
TextureHandle? _anyTexture(CpuDevice device) => device.createTextureFromPixels(
  width: 1,
  height: 1,
  format: TextureFormat.r8g8b8a8UNormInt,
  pixels: ByteData.sublistView(Uint8List.fromList(<int>[255, 0, 0, 255])),
);

void main() {
  group('a car wears one colour', () {
    test('the box and the model agree on what it is', () {
      // The box stands in for the few frames before the model is decoded. If
      // the two colours came from different lists a rival would visibly change
      // livery as the race loaded.
      //
      // Mutation: give `rival` a palette of its own — fails, because the two
      // lists have to be typed out identically to keep passing, which is the
      // duplication this is here to forbid.
      for (var i = 0; i < 6; i++) {
        expect(Looks.rival(i).baseColor, equals(Looks.carPaint(i)));
      }
    });

    test('and rivals do not share one', () {
      // Mutation: drop the `% palette.length` and return palette[0] — fails.
      expect(Looks.carPaint(1), isNot(equals(Looks.carPaint(2))));
    });

    test('and a field larger than the palette still gets a colour', () {
      // Five colours, and nothing stops a later circuit lining up more than
      // five cars. Mutation: index the palette directly — throws.
      expect(Looks.carPaint(7), equals(Looks.carPaint(2)));
    });
  });

  group('only the bodywork is painted', () {
    test('the panels are found by name', () {
      // The exporter suffixes duplicates, so the names in the asset are
      // `car_chassis.005` and `car_chassis2.005` rather than anything stable.
      expect(Looks.isBodywork('car_chassis.005'), isTrue);
      expect(Looks.isBodywork('car_chassis2.005'), isTrue);
      expect(Looks.isBodywork('CHASSIS'), isTrue);
    });

    test('and the tyres, glass and carbon are not', () {
      // Mutation: match every material — fails here first, which is the point:
      // a rival with red tyres and a red windscreen is the failure this guards.
      expect(Looks.isBodywork('Tyre.005'), isFalse);
      expect(Looks.isBodywork('WIND_MCL'), isFalse);
      expect(Looks.isBodywork('CARBON.005'), isFalse);
      expect(Looks.isBodywork('Brake_Disk.005'), isFalse);
    });

    test('and a material with no name is not', () {
      // glTF does not require material names. Mutation: drop the null guard —
      // throws instead of failing, which is worse: it takes the whole load
      // path down and the field silently stays boxes.
      expect(Looks.isBodywork(null), isFalse);
    });

    test('so painting a car leaves everything but its panels alone', () {
      final device = _device();
      final chassis = _part(device, 'car_chassis.005');
      final tyre = _part(device, 'Tyre.005');
      final colour = Looks.carPaint(1);

      Looks.paint(<MeshNode>[chassis, tyre], colour);

      expect(chassis.material.baseColor, equals(colour));
      // White, because `baseColor` multiplies the livery texture and one is
      // the tint that changes nothing.
      expect(tyre.material.baseColor, equals(Vector4(1.0, 1.0, 1.0, 1.0)));
    });

    test('and painting it twice leaves the colour asked for', () {
      // Mutation: multiply into `baseColor` instead of setting it — this fails
      // and the single-paint test above does not, because one multiplication
      // against white is indistinguishable from a set.
      final device = _device();
      final chassis = _part(device, 'car_chassis.005');
      final colour = Looks.carPaint(3);

      Looks.paint(<MeshNode>[chassis], colour);
      Looks.paint(<MeshNode>[chassis], colour);

      expect(chassis.material.baseColor, equals(colour));
    });

    test('but a ghost is haunted all over', () {
      // The opposite rule to painting, and worth its own test because the two
      // walk the same list: a ghost is one translucent shape, so its tyres and
      // its engine go too. Mutation: guard `haunt` with `isBodywork` — fails.
      final device = _device();
      final chassis = _part(device, 'car_chassis.005');
      final tyre = _part(device, 'Tyre.005');

      Looks.haunt(<MeshNode>[chassis, tyre]);

      for (final part in <MeshNode>[chassis, tyre]) {
        expect(part.material.alphaMode, equals(MaterialAlphaMode.blend));
        expect(part.material.lighting, equals(LightingModel.unlit));
        // Nothing writes depth through a ghost: two parts of it overlapping
        // should be brighter, not a hole in the one behind.
        expect(part.material.depthWrite, isFalse);
      }
    });

    test('and a haunted part keeps none of its livery', () {
      // Replacing the material rather than editing it is what drops the albedo.
      // Mutation: set `baseColor` and `alphaMode` on the existing material
      // instead — this fails, because the texture survives and the ghost is
      // drawn with sponsors on it.
      final device = _device();
      final part = carBox(
        device,
        Material(name: 'car_chassis.005', albedo: _anyTexture(device)),
      );

      Looks.haunt(<MeshNode>[part]);

      expect(part.material.albedo, isNull);
    });

    test('and one car is painted without touching another', () {
      // The real guard for this is `shareMaterials: false` at the instantiate
      // call; what this pins is that `paint` writes only into the materials it
      // was handed, so that flag is the only thing that has to be right.
      final device = _device();
      final mine = _part(device, 'car_chassis.005');
      final theirs = _part(device, 'car_chassis.005');

      Looks.paint(<MeshNode>[mine], Looks.carPaint(1));

      expect(theirs.material.baseColor, equals(Vector4(1.0, 1.0, 1.0, 1.0)));
    });
  });
}
