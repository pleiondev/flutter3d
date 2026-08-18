/// The sky, as arithmetic and as geometry.
///
///     flutter test test/sky_test.dart
///
/// What is drawn is checked in `packages/flutter3d_cpu/test/sky_frame_test.dart`,
/// on a real frame. Here are the two halves that can be checked without one: the
/// gradient answers a colour for every direction, and the dome is inside out.
///
/// Inside out is the claim worth stating plainly, because it is invisible in
/// every other way: a sphere built the ordinary way looks identical from the
/// outside, is drawn from the inside as nothing at all, and the failure reads as
/// "the sky did not appear" rather than as "the winding is backwards".
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

SkyGradient _plain() => SkyGradient(
      zenith: Vector3(0.0, 0.0, 1.0),
      horizon: Vector3(0.5, 0.5, 0.5),
      nadir: Vector3(0.0, 0.0, 0.0),
      directionToSun: Vector3(1.0, 0.0, 0.0),
      glowStrength: 0.0,
    );

/// Every vertex position of [mesh], as directions from its centre.
List<Vector3> _positions(MeshData mesh) {
  final stride = mesh.layout.floatsPerVertex;
  final offset = mesh.layout.floatOffsetOf(VertexLayout.position.name);
  return <Vector3>[
    for (var base = 0; base < mesh.vertices.length; base += stride)
      Vector3(
        mesh.vertices[base + offset],
        mesh.vertices[base + offset + 1],
        mesh.vertices[base + offset + 2],
      ),
  ];
}

List<Vector4> _colours(MeshData mesh) {
  final stride = mesh.layout.floatsPerVertex;
  final offset = mesh.layout.floatOffsetOf(VertexLayout.color.name);
  return <Vector4>[
    for (var base = 0; base < mesh.vertices.length; base += stride)
      Vector4(
        mesh.vertices[base + offset],
        mesh.vertices[base + offset + 1],
        mesh.vertices[base + offset + 2],
        mesh.vertices[base + offset + 3],
      ),
  ];
}

void main() {
  group('the gradient', () {
    test('reaches its three stops', () {
      final sky = _plain().colour;

      expect(sky(Vector3(0.0, 1.0, 0.0)).z, closeTo(1.0, 1e-6));
      expect(sky(Vector3(1.0, 0.0, 0.0)).x, closeTo(0.5, 1e-6));
      expect(sky(Vector3(0.0, -1.0, 0.0)).x, closeTo(0.0, 1e-6));
    });

    test('leaves the horizon flat rather than ramping straight off it', () {
      // Mutation: interpolate linearly in `y`. The band just above the horizon
      // is where a sky is read, and a straight ramp starts changing colour
      // immediately — five degrees up would already be nine percent of the way
      // to the zenith. The smoothstep leaves it at two, which is what makes the
      // horizon a band rather than an edge.
      final sky = _plain().colour;
      double towardsZenith(double degrees) {
        final radians = degrees * math.pi / 180.0;
        final blue = sky(Vector3(math.cos(radians), math.sin(radians), 0.0)).z;
        // The gradient runs 0.5 (horizon) to 1.0 (zenith) in blue.
        return (blue - 0.5) / 0.5;
      }

      expect(towardsZenith(5.0), lessThan(0.05),
          reason: 'a linear ramp would already be at 0.087 here');
      expect(towardsZenith(45.0), greaterThan(0.4),
          reason: 'and it still has to arrive');
    });

    test('brightens towards the sun and nowhere else', () {
      // Mutation: drop the `towards <= 0.0` guard and let the lobe apply in
      // every direction. `pow` of a negative base is NaN, and a NaN vertex
      // colour is a triangle that vanishes on some backends and is black on
      // others.
      final sky = SkyGradient(
        zenith: Vector3(0.2, 0.2, 0.2),
        horizon: Vector3(0.2, 0.2, 0.2),
        nadir: Vector3(0.2, 0.2, 0.2),
        directionToSun: Vector3(1.0, 0.0, 0.0),
        glowStrength: 0.5,
      ).colour;

      final into = sky(Vector3(1.0, 0.0, 0.0));
      final across = sky(Vector3(0.0, 0.0, 1.0));
      final away = sky(Vector3(-1.0, 0.0, 0.0));

      expect(into.x, greaterThan(0.6));
      expect(across.x, closeTo(0.2, 1e-6));
      expect(away.x, closeTo(0.2, 1e-6));
      for (final colour in <Vector4>[into, across, away]) {
        expect(colour.x.isFinite, isTrue);
      }
    });

    test('the sun direction is normalised whatever it is given', () {
      // Mutation: keep the vector as passed. The lobe is `pow(dot, n)`, so an
      // unnormalised sun makes the glow either enormous or absent, depending on
      // a length nobody thinks of as meaningful.
      final long = SkyGradient(
        zenith: Vector3.zero(),
        horizon: Vector3.zero(),
        nadir: Vector3.zero(),
        directionToSun: Vector3(0.0, 40.0, 0.0),
      );
      expect(long.directionToSun.length, closeTo(1.0, 1e-6));
    });
  });

  group('the dome', () {
    test('faces inwards', () {
      // The claim that cannot be seen any other way. A triangle wound
      // counter-clockwise seen from the inside has its geometric normal
      // pointing *at* the centre, so the dot of the face normal with the
      // outward direction is negative.
      //
      // Mutation: order the profile bottom-to-top. Every one of these flips
      // sign, the dome is back-face culled from the inside, and the symptom is
      // simply no sky.
      final mesh = const SkyDome(rings: 8, segments: 12).build();
      final positions = _positions(mesh);

      var checked = 0;
      for (var i = 0; i < mesh.indices.length; i += 3) {
        final a = positions[mesh.indices[i]];
        final b = positions[mesh.indices[i + 1]];
        final c = positions[mesh.indices[i + 2]];
        final normal = (b - a).cross(c - a);
        if (normal.length2 < 1e-9) continue; // degenerate at the poles
        final outward = (a + b + c)..scale(1 / 3);
        expect(normal.dot(outward), lessThan(0.0),
            reason: 'triangle $i faces out');
        checked++;
      }
      expect(checked, greaterThan(50), reason: 'nothing was actually checked');
    });

    test('surrounds the camera at its radius', () {
      final mesh = const SkyDome(radius: 10.0, rings: 8, segments: 12).build();
      for (final position in _positions(mesh)) {
        expect(position.length, closeTo(10.0, 1e-4));
      }
    });

    test('is built with somewhere to put a colour', () {
      // Mutation: build with `positionNormalTexcoord`. `MeshBuilder` fills an
      // absent colour with opaque white so the mesh still draws — as a white
      // ball, which is a sky nobody asked for and no error anywhere.
      final mesh = const SkyDome(rings: 4, segments: 6).build();
      expect(mesh.layout.has(VertexLayout.color), isTrue);
    });
  });

  group('painting', () {
    test('gives each vertex the colour of the direction it sits in', () {
      final mesh = const SkyDome(rings: 8, segments: 12).build();
      paintSky(mesh, _plain().colour);

      final positions = _positions(mesh);
      final colours = _colours(mesh);
      final sky = _plain().colour;
      for (var i = 0; i < positions.length; i++) {
        final expected = sky(positions[i].normalized());
        expect(colours[i].x, closeTo(expected.x, 1e-5));
        expect(colours[i].y, closeTo(expected.y, 1e-5));
        expect(colours[i].z, closeTo(expected.z, 1e-5));
      }
    });

    test('the top is the zenith and the bottom is the nadir', () {
      // Mutation: pass the raw position instead of normalising it, or index the
      // colour offset from the wrong attribute. Both survive the test above if
      // it is written loosely; this one names the two poles.
      final mesh = const SkyDome(rings: 8, segments: 12).build();
      paintSky(mesh, _plain().colour);

      final positions = _positions(mesh);
      final colours = _colours(mesh);
      for (var i = 0; i < positions.length; i++) {
        if (positions[i].y > 9.99) {
          expect(colours[i].z, closeTo(1.0, 1e-4), reason: 'the zenith is blue');
        }
        if (positions[i].y < -9.99) {
          expect(colours[i].x, closeTo(0.0, 1e-4), reason: 'the nadir is dark');
        }
      }
    });

    test('refuses a mesh with nowhere to put it', () {
      final mesh = const SkyDome(rings: 4, segments: 6)
          .build(layout: VertexLayout.positionNormalTexcoord);
      expect(() => paintSky(mesh, _plain().colour), throwsArgumentError);
    });
  });

  group('the node', () {
    test('is flagged as a backdrop, four ways', () {
      // Each flag is a distinct failure: drawn last, clipping the level away,
      // drawn into every shadow cascade, and culled by bounds that describe a
      // ball around the camera. A test per flag would be four tests about one
      // list; the list is the claim.
      final node = skyNode(CpuMesh(const SkyDome(rings: 4, segments: 6).build()));

      expect(node.material.drawBucket, lessThan(0), reason: 'drawn first');
      expect(node.material.depthWrite, isFalse, reason: 'writes no depth');
      expect(node.material.lighting, LightingModel.unlit);
      expect(node.castsShadow, isFalse);
      expect(node.frustumCulled, isFalse);
    });

    test('does not ask for a depth test it does not need', () {
      // The sky is drawn first, into a cleared depth buffer, so `less` passes on
      // its own. Asking for `always` would emit a state change every frame to
      // buy nothing — and `PassState`'s own history is why a redundant depth
      // call is worth refusing.
      final node = skyNode(CpuMesh(const SkyDome(rings: 4, segments: 6).build()));
      expect(node.material.depthCompare, isNull);
    });

    test('follows the camera in position and not in rotation', () {
      // Mutation: copy the camera's rotation too. The gradient would turn with
      // the head, which is the one thing a sky must never do — and it looks
      // almost right, because the horizon stays level.
      final node = skyNode(CpuMesh(const SkyDome(rings: 4, segments: 6).build()));
      final camera = CameraNode()
        ..setPosition(30.0, 5.0, -12.0)
        ..lookAt(Vector3(100.0, 40.0, 60.0));

      followCamera(node, camera);

      expect(node.readPosition().x, closeTo(30.0, 1e-6));
      expect(node.readPosition().y, closeTo(5.0, 1e-6));
      expect(node.readPosition().z, closeTo(-12.0, 1e-6));
      expect(node.readRotation(), Quaternion.identity());
    });
  });
}
