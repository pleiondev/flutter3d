/// `SetMaterialGraph`/`BakeTextureGraph`: `mat-12`'s own missing half — the
/// command that reads a material's `TextureGraph` and writes the result into
/// its texture slots, tagged with the version it was baked from.
///
///     dart test test/bake_texture_graph_test.dart
library;

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// One material, unpainted, no objects — everything these tests need to
/// address is `materials[0]`.
ModelHistory painted() => ModelHistory(
  ModelProject(
    materials: <ProjectMaterial>[ProjectMaterial(surface: SurfaceMaterial())],
  ),
);

/// A graph baking a flat colour straight to [slot] — the smallest graph
/// `BakeTextureGraph` has anything to do with.
TextureGraph flatGraph(Vector4 color, String slot) => TextureGraph(
  nodes: <TextureNode>[
    ColorTextureNode(id: 1, value: color),
    OutputTextureNode(id: 2, result: 1, slot: slot),
  ],
);

void main() {
  group('SetMaterialGraph', () {
    test('sets a graph and moves the material on one version', () {
      final history = painted();
      final graph = flatGraph(Vector4(1, 0, 0, 1), 'albedo');
      final before = history.project.materials.single.version;

      expect(
        history.run(SetMaterialGraph(materialIndex: 0, graph: graph)),
        isNull,
      );
      final material = history.project.materials.single;
      expect(material.graph, same(graph));
      expect(material.version, before + 1);
      expect(material.isGraphStale, isTrue); // never baked
    });

    test('null clears a graph a material already had', () {
      final history = painted();
      history.run(
        SetMaterialGraph(
          materialIndex: 0,
          graph: flatGraph(Vector4(1, 0, 0, 1), 'albedo'),
        ),
      );

      expect(history.run(const SetMaterialGraph(materialIndex: 0)), isNull);
      final material = history.project.materials.single;
      expect(material.graph, isNull);
      expect(material.isGraphStale, isFalse); // nothing to be stale about
    });

    test('refuses a material that is not there', () {
      final history = painted();
      expect(
        history.run(const SetMaterialGraph(materialIndex: 4)),
        contains('4'),
      );
    });
  });

  group('BakeTextureGraph', () {
    test('refuses a material with no graph', () {
      final history = painted();
      expect(
        history.run(const BakeTextureGraph(materialIndex: 0)),
        contains('no texture graph'),
      );
    });

    test('refuses a material that is not there', () {
      final history = painted();
      expect(
        history.run(const BakeTextureGraph(materialIndex: 3)),
        contains('3'),
      );
    });

    test('refuses a graph that does not validate', () {
      final history = painted();
      history.run(
        SetMaterialGraph(
          materialIndex: 0,
          // `result: 99` points at a node this graph does not have.
          graph: const TextureGraph(
            nodes: <TextureNode>[
              OutputTextureNode(id: 1, result: 99, slot: 'albedo'),
            ],
          ),
        ),
      );
      expect(
        history.run(const BakeTextureGraph(materialIndex: 0)),
        contains('not valid'),
      );
    });

    test('refuses a graph with no output wired to a slot', () {
      final history = painted();
      history.run(
        SetMaterialGraph(
          materialIndex: 0,
          graph: TextureGraph(
            nodes: <TextureNode>[
              ColorTextureNode(id: 1, value: Vector4(1, 1, 1, 1)),
              const OutputTextureNode(id: 2, result: 1), // no slot
            ],
          ),
        ),
      );
      expect(
        history.run(const BakeTextureGraph(materialIndex: 0)),
        contains('no material slot'),
      );
    });

    test('bakes a flat colour into albedo, byte for byte', () {
      final history = painted();
      history.run(
        SetMaterialGraph(
          materialIndex: 0,
          graph: flatGraph(Vector4(1, 0, 0, 1), 'albedo'),
        ),
      );

      expect(
        history.run(const BakeTextureGraph(materialIndex: 0, size: 8)),
        isNull,
      );
      final material = history.project.materials.single;
      final binding = material.surface.baseColorTexture;
      expect(binding, isNotNull);
      expect(history.project.images, hasLength(1));

      final decoded = decodePng(
        history.project.images[binding!.imageIndex].bytes,
      )!;
      expect(decoded.width, 8);
      expect(decoded.height, 8);
      // Linear 1/0/0/1 round-trips through the sRGB transfer function exactly
      // at both ends of its own range.
      expect(decoded.rgba.sublist(0, 4), <int>[255, 0, 0, 255]);

      // Mutation: skip the `bakedAtVersion` assignment in `withBake`, and
      // this stays stale forever, indistinguishable from a bake that never
      // ran.
      expect(material.isGraphStale, isFalse);
    });

    test('a later edit of any kind makes the bake read stale again', () {
      final history = painted();
      history.run(
        SetMaterialGraph(
          materialIndex: 0,
          graph: flatGraph(Vector4(1, 1, 1, 1), 'albedo'),
        ),
      );
      history.run(const BakeTextureGraph(materialIndex: 0, size: 4));
      expect(history.project.materials.single.isGraphStale, isFalse);

      // An edit that has nothing to do with the graph — `roughness`, not a
      // node — still moves `version` past `bakedAtVersion`.
      history.run(
        const SetMaterialField(index: 0, field: 'roughness', value: 0.2),
      );
      expect(history.project.materials.single.isGraphStale, isTrue);
    });

    test('two outputs bake in one step and land on their own slots', () {
      final history = painted();
      history.run(
        SetMaterialGraph(
          materialIndex: 0,
          graph: TextureGraph(
            nodes: <TextureNode>[
              ColorTextureNode(id: 1, value: Vector4(1, 0, 0, 1)),
              ColorTextureNode(id: 2, value: Vector4(0, 1, 0, 1)),
              const OutputTextureNode(id: 3, result: 1, slot: 'albedo'),
              const OutputTextureNode(id: 4, result: 2, slot: 'emissive'),
            ],
          ),
        ),
      );
      final before = history.project.materials.single.version;

      expect(
        history.run(const BakeTextureGraph(materialIndex: 0, size: 4)),
        isNull,
      );
      final material = history.project.materials.single;
      // One step for both outputs, not one each.
      expect(material.version, before + 1);
      expect(material.surface.baseColorTexture, isNotNull);
      expect(material.surface.emissiveTexture, isNotNull);
      expect(
        material.surface.baseColorTexture!.imageIndex,
        isNot(material.surface.emissiveTexture!.imageIndex),
      );
      expect(history.project.images, hasLength(2));
    });

    test('baking the same graph twice reuses the first image, not a second '
        'row', () {
      final history = painted();
      history.run(
        SetMaterialGraph(
          materialIndex: 0,
          graph: flatGraph(Vector4(0.2, 0.4, 0.6, 1), 'albedo'),
        ),
      );

      history.run(const BakeTextureGraph(materialIndex: 0, size: 4));
      expect(history.project.images, hasLength(1));
      final firstImage =
          history.project.materials.single.surface.baseColorTexture!.imageIndex;

      // A second bake of a graph that has not changed — nothing here
      // triggers it (`mat-13`'s own panel would, on a node edit), only that
      // `BakeTextureGraph` was asked to run again — writes the identical
      // bytes.
      //
      // Mutation: compare interned images by identity or skip the scan in
      // `BakeTextureGraph`, and this grows the image table by one every
      // rebake even though nothing about the picture changed.
      history.run(const BakeTextureGraph(materialIndex: 0, size: 4));
      expect(history.project.images, hasLength(1));
      expect(
        history.project.materials.single.surface.baseColorTexture!.imageIndex,
        firstImage,
      );
    });

    test('a graph the format never saw a slot for skips that output, keeps '
        'the rest', () {
      final history = painted();
      history.run(
        SetMaterialGraph(
          materialIndex: 0,
          graph: TextureGraph(
            nodes: <TextureNode>[
              ColorTextureNode(id: 1, value: Vector4(1, 1, 1, 1)),
              const OutputTextureNode(id: 2, result: 1, slot: 'chrome'),
              const OutputTextureNode(id: 3, result: 1, slot: 'albedo'),
            ],
          ),
        ),
      );
      expect(
        history.run(const BakeTextureGraph(materialIndex: 0, size: 4)),
        isNull,
      );
      expect(
        history.project.materials.single.surface.baseColorTexture,
        isNotNull,
      );
    });
  });

  group('round trip through the project file', () {
    test('a graph and its baked-at version survive a save and reopen', () {
      final history = painted();
      history.run(
        SetMaterialGraph(
          materialIndex: 0,
          graph: flatGraph(Vector4(0, 0, 1, 1), 'albedo'),
        ),
      );
      history.run(const BakeTextureGraph(materialIndex: 0, size: 4));
      final baked = history.project.materials.single;

      final bytes = writeProject(history.project);
      final reopened =
          (readProject(bytes) as ProjectOpened).project.materials.single;

      expect(reopened.graph, isNotNull);
      expect(reopened.graph!.nodes, hasLength(baked.graph!.nodes.length));
      expect(reopened.bakedAtVersion, baked.bakedAtVersion);
      expect(reopened.version, baked.version);
      expect(reopened.isGraphStale, isFalse);
    });

    test('a material with no graph opens with none, not a stale one', () {
      final history = painted();
      final bytes = writeProject(history.project);
      final reopened =
          (readProject(bytes) as ProjectOpened).project.materials.single;
      expect(reopened.graph, isNull);
      expect(reopened.isGraphStale, isFalse);
    });
  });
}
