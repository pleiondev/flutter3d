import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d/src/engine/animation/animation.dart';
import 'package:flutter3d/src/engine/assets/f3d/f3d.dart';
import 'package:flutter3d/src/engine/assets/gltf/gltf.dart';
import 'package:flutter3d/src/engine/assets/obj/obj.dart';
import 'package:flutter3d/src/engine/geometry/geometry.dart';
import 'package:flutter3d_samples/flutter3d_samples.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const String kSamples = kSamplesPath;

Uint8List readSample(String name) => File('$kSamples/$name').readAsBytesSync();

/// Round-trips a document through the container.
F3dDocument roundTrip(ModelDocument document) =>
    F3dDocument.parse(F3dWriter(document).write());

/// A small document assembled by hand, so the awkward cases can be reached
/// without hunting for a sample file that happens to contain them.
final class _FakeDocument extends ModelDocument {
  _FakeDocument({
    required this.surfaces,
    this.materials = const <SurfaceMaterial>[],
    this.images = const <EncodedImage>[],
    this.warnings = const <String>[],
  });

  @override
  final List<ModelSurface> surfaces;
  @override
  final List<SurfaceMaterial> materials;
  @override
  final List<EncodedImage> images;
  @override
  final List<String> warnings;
  @override
  final List<AnimationClip> animations = const <AnimationClip>[];
}

/// A document that also carries skins, for the packed-field checks.
final class _FakeSkinnedDocument extends ModelDocument {
  _FakeSkinnedDocument({required this.surfaces});

  @override
  final List<ModelSurface> surfaces;
  @override
  final List<SurfaceMaterial> materials = const <SurfaceMaterial>[];
  @override
  final List<EncodedImage> images = const <EncodedImage>[];
  @override
  final List<String> warnings = const <String>[];
  @override
  final List<AnimationClip> animations = const <AnimationClip>[];

  @override
  List<ModelSkin> get skins => <ModelSkin>[
    for (var i = 0; i < 3; i++)
      ModelSkin(
        name: 'skin$i',
        joints: const <int>[0],
        inverseBindMatrices: <Matrix4>[Matrix4.identity()],
      ),
  ];
}

MeshData triangle({Vector4? colour}) {
  final builder = MeshBuilder(VertexLayout.standard);
  final a = builder.addVertex(
    position: Vector3(0.0, 0.0, 0.0),
    normal: Vector3(0.0, 0.0, 1.0),
    texcoord: Vector2(0.0, 0.0),
    color: colour,
  );
  final b = builder.addVertex(
    position: Vector3(1.0, 0.0, 0.0),
    normal: Vector3(0.0, 0.0, 1.0),
    texcoord: Vector2(1.0, 0.0),
    color: colour,
  );
  final c = builder.addVertex(
    position: Vector3(0.0, 1.0, 0.0),
    normal: Vector3(0.0, 0.0, 1.0),
    texcoord: Vector2(0.0, 1.0),
    color: colour,
  );
  builder.addTriangle(a, b, c);
  return builder.build();
}

void main() {
  group('the geometry survives byte for byte', () {
    // The acceptance criterion for the format: a converted model must hand back
    // exactly the arrays the decoder produced. Comparing counts would pass a
    // file whose floats had been mangled by an endianness slip, so this compares
    // every element.
    test('the teapot matches the OBJ decoder exactly', () async {
      final source = await ObjLoader(
        layout: VertexLayout.standard,
      ).load(readSample('teapot.obj'));
      final reloaded = roundTrip(source);

      expect(reloaded.surfaces.length, source.surfaces.length);

      for (var i = 0; i < source.surfaces.length; i++) {
        final a = source.surfaces[i].mesh;
        final b = reloaded.surfaces[i].mesh;

        expect(b.layout.toString(), a.layout.toString());
        expect(b.vertexCount, a.vertexCount);
        expect(b.indexCount, a.indexCount);
        expect(b.vertices, orderedEquals(a.vertices));
        expect(b.indices, orderedEquals(a.indices));
      }
    });

    test('a textured GLB keeps its image bytes', () async {
      final source = await GltfLoader(
        layout: VertexLayout.standard,
      ).load(readSample('BoxTextured.glb'));
      final reloaded = roundTrip(source);

      expect(source.images, isNotEmpty);
      expect(reloaded.images.length, source.images.length);
      for (var i = 0; i < source.images.length; i++) {
        expect(reloaded.images[i].bytes, orderedEquals(source.images[i].bytes));
        expect(reloaded.images[i].mimeType, source.images[i].mimeType);
      }
    });

    test('vertex arrays are views over the file, not copies', () {
      // The claim the format is built on. If these were copies the loader would
      // be doing per-element work and the whole exercise would be pointless.
      //
      // Two documents are parsed over the same bytes and one is written
      // through: if both are views they alias, and the write is visible in the
      // other. Comparing `.buffer` identity would prove nothing — it hands back
      // a fresh wrapper each time — and aliasing is the property that matters.
      final encoded = F3dWriter(
        _FakeDocument(surfaces: <ModelSurface>[ModelSurface(mesh: triangle())]),
      ).write();

      final first = F3dDocument.parse(encoded);
      final second = F3dDocument.parse(encoded);

      first.surfaces.single.mesh.vertices[0] = 1234.5;
      expect(
        second.surfaces.single.mesh.vertices[0],
        1234.5,
        reason: 'the meshes do not alias the file, so the loader copied',
      );

      first.surfaces.single.mesh.indices[0] = 7;
      expect(second.surfaces.single.mesh.indices[0], 7);
    });

    test('a mesh shared by two surfaces is written once and stays shared', () {
      final shared = triangle();
      final encoded = F3dWriter(
        _FakeDocument(
          surfaces: <ModelSurface>[
            ModelSurface(mesh: shared, name: 'left'),
            ModelSurface(mesh: shared, name: 'right'),
          ],
        ),
      ).write();
      final document = F3dDocument.parse(encoded);

      // Identity, not equality: the GPU upload path deduplicates on it, and a
      // format that split one mesh into two would double the buffers uploaded.
      expect(
        identical(document.surfaces[0].mesh, document.surfaces[1].mesh),
        isTrue,
      );

      // And the geometry appears once in the file rather than twice.
      final oneCopy = F3dWriter(
        _FakeDocument(surfaces: <ModelSurface>[ModelSurface(mesh: shared)]),
      ).write();
      expect(
        encoded.length - oneCopy.length,
        lessThan(shared.vertices.lengthInBytes),
      );
    });
  });

  group('everything else survives too', () {
    test('surface placement and winding', () {
      final transform = Matrix4.compose(
        Vector3(1.0, 2.0, 3.0),
        Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), 0.7),
        Vector3(2.0, 2.0, 2.0),
      );
      final document = roundTrip(
        _FakeDocument(
          surfaces: <ModelSurface>[
            ModelSurface(
              mesh: triangle(),
              transform: transform,
              materialIndex: 3,
              flipWinding: true,
              name: 'mirrored',
            ),
          ],
          materials: List<SurfaceMaterial>.generate(
            4,
            (i) => SurfaceMaterial(name: 'm$i'),
          ),
        ),
      );

      final surface = document.surfaces.single;
      expect(surface.name, 'mirrored');
      expect(surface.materialIndex, 3);
      expect(surface.flipWinding, isTrue);
      for (var i = 0; i < 16; i++) {
        expect(
          surface.transform.storage[i],
          closeTo(transform.storage[i], 1e-6),
        );
      }
    });

    test('a surface with no material comes back with none', () {
      final document = roundTrip(
        _FakeDocument(surfaces: <ModelSurface>[ModelSurface(mesh: triangle())]),
      );
      expect(document.surfaces.single.materialIndex, isNull);
    });

    test('every material field, including the texture slots', () {
      final source = SurfaceMaterial(
        name: 'brushed',
        baseColor: Vector4(0.2, 0.4, 0.6, 0.8),
        metallic: 0.75,
        roughness: 0.25,
        baseColorTexture: const TextureBinding(imageIndex: 0),
        metallicRoughnessTexture: const TextureBinding(
          imageIndex: 1,
          texCoordSet: 1,
          sampling: TextureSampling(
            magLinear: false,
            minLinear: true,
            useMipmaps: false,
            wrapS: TextureWrap.clampToEdge,
            wrapT: TextureWrap.mirroredRepeat,
          ),
        ),
        normalTexture: const TextureBinding(imageIndex: 2),
        normalScale: 1.5,
        occlusionTexture: const TextureBinding(imageIndex: 3),
        occlusionStrength: 0.4,
        emissiveTexture: const TextureBinding(imageIndex: 4),
        emissive: Vector3(0.1, 0.2, 0.3),
        emissiveStrength: 2.5,
        alphaMode: SurfaceAlphaMode.mask,
        alphaCutoff: 0.35,
        doubleSided: true,
        unlit: true,
      );

      final document = roundTrip(
        _FakeDocument(
          surfaces: <ModelSurface>[
            ModelSurface(mesh: triangle(), materialIndex: 0),
          ],
          materials: <SurfaceMaterial>[source],
          images: List<EncodedImage>.generate(
            5,
            (i) => EncodedImage(bytes: Uint8List.fromList(<int>[i])),
          ),
        ),
      );

      final m = document.materials.single;
      expect(m.name, 'brushed');
      expect(m.baseColor.x, closeTo(0.2, 1e-6));
      expect(m.baseColor.w, closeTo(0.8, 1e-6));
      expect(m.metallic, closeTo(0.75, 1e-6));
      expect(m.roughness, closeTo(0.25, 1e-6));
      expect(m.normalScale, closeTo(1.5, 1e-6));
      expect(m.occlusionStrength, closeTo(0.4, 1e-6));
      expect(m.emissive.y, closeTo(0.2, 1e-6));
      expect(m.emissiveStrength, closeTo(2.5, 1e-6));
      expect(m.alphaMode, SurfaceAlphaMode.mask);
      expect(m.alphaCutoff, closeTo(0.35, 1e-6));
      expect(m.doubleSided, isTrue);
      expect(m.unlit, isTrue);

      expect(m.baseColorTexture!.imageIndex, 0);
      expect(m.normalTexture!.imageIndex, 2);
      expect(m.occlusionTexture!.imageIndex, 3);
      expect(m.emissiveTexture!.imageIndex, 4);

      // The packed sampler flags are the fiddliest part of the record, so every
      // bit is checked rather than a representative one.
      final orm = m.metallicRoughnessTexture!;
      expect(orm.texCoordSet, 1);
      expect(orm.sampling.magLinear, isFalse);
      expect(orm.sampling.minLinear, isTrue);
      expect(orm.sampling.useMipmaps, isFalse);
      expect(orm.sampling.wrapS, TextureWrap.clampToEdge);
      expect(orm.sampling.wrapT, TextureWrap.mirroredRepeat);
    });

    test('an absent texture slot stays absent', () {
      final document = roundTrip(
        _FakeDocument(
          surfaces: <ModelSurface>[
            ModelSurface(mesh: triangle(), materialIndex: 0),
          ],
          materials: <SurfaceMaterial>[SurfaceMaterial(name: 'plain')],
        ),
      );
      final m = document.materials.single;
      expect(m.baseColorTexture, isNull);
      expect(m.normalTexture, isNull);
      expect(m.emissiveTexture, isNull);
    });

    test('the node hierarchy, with children and surfaces', () async {
      // BoxAnimated has transform-only nodes and a real tree, which is what
      // animation addresses by index.
      final source = await GltfLoader(
        layout: VertexLayout.standard,
      ).load(readSample('BoxAnimated.glb'));
      final reloaded = roundTrip(source);

      expect(reloaded.nodes.length, source.nodes.length);
      expect(reloaded.roots, orderedEquals(source.roots));

      for (var i = 0; i < source.nodes.length; i++) {
        final a = source.nodes[i];
        final b = reloaded.nodes[i];
        expect(b.name, a.name);
        expect(b.children, orderedEquals(a.children));
        expect(b.surfaces, orderedEquals(a.surfaces));
        expect(b.translation.x, closeTo(a.translation.x, 1e-6));
        expect(b.rotation.w, closeTo(a.rotation.w, 1e-6));
        expect(b.scale.z, closeTo(a.scale.z, 1e-6));
      }
    });

    test('animation clips sample identically after a round trip', () async {
      // InterpolationTest carries all three interpolations, including the cubic
      // one whose keys hold three values each — the layout most likely to be
      // mis-sized by a serializer.
      final source = await GltfLoader(
        layout: VertexLayout.standard,
      ).load(readSample('InterpolationTest.glb'));
      final reloaded = roundTrip(source);

      expect(reloaded.animations.length, source.animations.length);
      expect(source.animations, isNotEmpty);

      for (var c = 0; c < source.animations.length; c++) {
        final a = source.animations[c];
        final b = reloaded.animations[c];
        expect(b.name, a.name);
        expect(b.tracks.length, a.tracks.length);
        expect(b.duration, closeTo(a.duration, 1e-6));

        for (var t = 0; t < a.tracks.length; t++) {
          final ta = a.tracks[t];
          final tb = b.tracks[t];
          expect(tb.nodeIndex, ta.nodeIndex);
          expect(tb.path, ta.path);
          expect(tb.interpolation, ta.interpolation);
          expect(tb.componentCount, ta.componentCount);

          // Sampled rather than compared field by field: what has to survive is
          // the pose, and sampling is the only check that covers the times, the
          // values and the layout of both at once.
          final outA = Float32List(ta.componentCount);
          final outB = Float32List(tb.componentCount);
          for (var step = 0; step <= 8; step++) {
            final time = ta.endTime * step / 8;
            ta.sample(time, outA);
            tb.sample(time, outB);
            expect(
              outB,
              orderedEquals(outA),
              reason: 'clip $c track $t differs at $time',
            );
          }
        }
      }
    });

    test('warnings are carried, not dropped', () {
      // They describe the model — an ignored extension, a skipped primitive —
      // not the parse. Losing them at conversion makes the converted asset look
      // clean while still being the asset that had the problem.
      final document = roundTrip(
        _FakeDocument(
          surfaces: <ModelSurface>[ModelSurface(mesh: triangle())],
          warnings: <String>['meshes[0] uses KHR_draco, read uncompressed'],
        ),
      );
      expect(document.warnings, hasLength(1));
      expect(document.warnings.single, contains('KHR_draco'));
    });

    test('a non-ASCII name survives the string table', () {
      final document = roundTrip(
        _FakeDocument(
          surfaces: <ModelSurface>[
            ModelSurface(mesh: triangle(), name: 'чайник — 茶壶'),
          ],
        ),
      );
      expect(document.surfaces.single.name, 'чайник — 茶壶');
    });

    test('an empty document is valid, not a crash', () {
      final document = roundTrip(
        _FakeDocument(surfaces: const <ModelSurface>[]),
      );
      expect(document.surfaces, isEmpty);
      expect(document.materials, isEmpty);
      expect(document.nodes, isEmpty);
      expect(document.computeBounds().min.x.isFinite, isTrue);
    });
  });

  group('skinning survives the container', () {
    test('a rigged model keeps its skin, joints and bind matrices', () async {
      final source = await GltfLoader().load(readSample('RiggedFigure.glb'));
      final reloaded = roundTrip(source);

      expect(source.skins, hasLength(1));
      expect(reloaded.skins, hasLength(1));

      final a = source.skins.single;
      final b = reloaded.skins.single;
      expect(b.name, a.name);
      expect(b.joints, orderedEquals(a.joints));
      expect(b.skeletonRoot, a.skeletonRoot);
      expect(b.inverseBindMatrices, hasLength(a.inverseBindMatrices.length));

      for (var j = 0; j < a.inverseBindMatrices.length; j++) {
        expect(
          b.inverseBindMatrices[j].storage,
          orderedEquals(a.inverseBindMatrices[j].storage),
          reason: 'inverse bind matrix $j differs',
        );
      }
    });

    test('the surface still points at its skin', () async {
      final source = await GltfLoader().load(readSample('RiggedSimple.glb'));
      final reloaded = roundTrip(source);
      expect(
        reloaded.surfaces.single.skinIndex,
        source.surfaces.single.skinIndex,
      );
    });

    test('the skinned vertex layout survives', () async {
      final source = await GltfLoader().load(readSample('RiggedFigure.glb'));
      final reloaded = roundTrip(source);

      expect(reloaded.surfaces.single.mesh.layout.isSkinned, isTrue);
      expect(
        reloaded.surfaces.single.mesh.vertices,
        orderedEquals(source.surfaces.single.mesh.vertices),
      );
    });

    test('a static surface still reports no skin', () async {
      // The skin index shares a field with the winding flag, so "no skin" has
      // to survive the packing as null rather than as joint zero.
      final source = await GltfLoader().load(readSample('Box.glb'));
      final reloaded = roundTrip(source);
      expect(reloaded.skins, isEmpty);
      expect(reloaded.surfaces.single.skinIndex, isNull);
    });

    test('flip winding and a skin index coexist in the packed field', () {
      final document = roundTrip(
        _FakeSkinnedDocument(
          surfaces: <ModelSurface>[
            ModelSurface(mesh: triangle(), flipWinding: true, skinIndex: 2),
          ],
        ),
      );
      expect(document.surfaces.single.flipWinding, isTrue);
      expect(document.surfaces.single.skinIndex, 2);
    });
  });

  group('a bad file is rejected with something readable', () {
    test('the wrong magic', () {
      expect(
        // Long enough to clear the header-size check, so the magic is what
        // rejects it rather than the length.
        () => F3dDocument.parse(
          Uint8List.fromList(utf8Bytes('this is definitely not a model file')),
        ),
        throwsA(
          isA<F3dFormatException>().having(
            (e) => e.message,
            'message',
            contains('Not a .f3d'),
          ),
        ),
      );
    });

    test('a file too short to hold a header', () {
      expect(
        () => F3dDocument.parse(Uint8List(4)),
        throwsA(isA<F3dFormatException>()),
      );
    });

    test('a version this build does not read', () {
      final encoded = F3dWriter(
        _FakeDocument(surfaces: <ModelSurface>[ModelSurface(mesh: triangle())]),
      ).write();
      // Bump the version in place; everything else stays valid, so the version
      // check is the only thing that can reject it.
      ByteData.view(
        encoded.buffer,
      ).setUint32(4, kF3dVersion + 1, Endian.little);

      expect(
        () => F3dDocument.parse(encoded),
        throwsA(
          isA<F3dFormatException>().having(
            (e) => e.message,
            'message',
            allOf(contains('version'), contains('convert_asset')),
          ),
        ),
      );
    });

    test('a truncated file', () {
      final encoded = F3dWriter(
        _FakeDocument(surfaces: <ModelSurface>[ModelSurface(mesh: triangle())]),
      ).write();
      expect(
        () => F3dDocument.parse(
          Uint8List.sublistView(encoded, 0, encoded.length ~/ 2),
        ),
        throwsA(isA<F3dFormatException>()),
      );
    });

    test('isF3dFile recognises its own output and nothing else', () {
      final encoded = F3dWriter(
        _FakeDocument(surfaces: <ModelSurface>[ModelSurface(mesh: triangle())]),
      ).write();
      expect(isF3dFile(encoded), isTrue);
      expect(isF3dFile(readSample('Box.glb')), isFalse);
      expect(isF3dFile(readSample('teapot.obj')), isFalse);
      expect(isF3dFile(Uint8List(0)), isFalse);
    });
  });
}

List<int> utf8Bytes(String value) => value.codeUnits;
