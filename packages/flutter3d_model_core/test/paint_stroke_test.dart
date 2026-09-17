/// `PaintStroke` — `pro-pt-03`: a texture stroke as one step, the layers it
/// keeps, and the mask that gates it.
///
///     dart test test/paint_stroke_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A UV-mapped unit quad on `z = 0`.
EditMesh sheet({bool withUv = true}) {
  final builder = EditMeshBuilder();
  builder
    ..addVertex(Vector3(0, 0, 0))
    ..addVertex(Vector3(1, 0, 0))
    ..addVertex(Vector3(1, 1, 0))
    ..addVertex(Vector3(0, 1, 0));
  final int face = builder.addFace(<int>[0, 1, 2, 3]);
  final EditMesh mesh = builder.build();
  if (withUv) {
    mesh.beginStep();
    mesh.forEachHalfEdge(face, (int he) {
      final Vector3 at = mesh.positionOf(mesh.originOf(he));
      mesh.setUv(he, Vector2(at.x, at.y));
    });
    mesh.endStep();
  }
  mesh.clearJournal();
  return mesh;
}

/// A PNG of one flat value, for a mask.
Uint8List flatPng(int size, int value) {
  final rgba = Uint8List(size * size * 4);
  for (var i = 0; i < size * size; i++) {
    rgba[i * 4] = value;
    rgba[i * 4 + 1] = value;
    rgba[i * 4 + 2] = value;
    rgba[i * 4 + 3] = 255;
  }
  return encodeCompressedPng(size, size, rgba);
}

ModelHistory opened({
  bool withMaterial = true,
  bool withUv = true,
  List<EncodedImage> images = const <EncodedImage>[],
}) {
  final ModelProject project = ModelProject(
    objects: <ModelObject>[
      ModelObject(
        id: 1,
        name: 'sheet',
        geometry: EditedGeometry(sheet(withUv: withUv)),
        transform: Matrix4.identity(),
        materialSlots: withMaterial ? const <int>[0] : const <int>[],
      ),
    ],
    materials: withMaterial
        ? <ProjectMaterial>[
            ProjectMaterial(surface: SurfaceMaterial(name: 'paint')),
          ]
        : const <ProjectMaterial>[],
    images: images,
    nextId: 2,
  );
  return ModelHistory(project);
}

PaintStroke stroke({
  Vector3? at,
  double radius = 0.2,
  List<double>? colour,
  int layer = 0,
  int? maskImage,
  bool maskInverted = false,
  int size = 64,
}) => PaintStroke(
  objectId: 1,
  samples: <PaintSample>[
    PaintSample(centre: at ?? Vector3(0.5, 0.5, 0), radius: radius),
  ],
  colour: colour ?? const <double>[1, 0, 0, 1],
  layer: layer,
  size: size,
  maskImage: maskImage,
  maskInverted: maskInverted,
);

/// The flattened canvas the material's own base-colour slot points at.
DecodedImage? painted(ModelHistory history) {
  final int? index =
      history.project.materials.single.surface.baseColorTexture?.imageIndex;
  if (index == null) return null;
  return decodePng(history.project.images[index].bytes);
}

void main() {
  group('one stroke', () {
    test('paints inside the brush and nowhere else', () {
      final ModelHistory history = opened();
      expect(history.run(stroke()), isNull);

      final DecodedImage canvas = painted(history)!;
      expect(canvas.width, 64);
      int alphaAt(int x, int y) => canvas.rgba[(y * 64 + x) * 4 + 3];
      // **The row's own "the frame only differs inside the area".**
      // Mutation: paint the whole canvas and rely on the weight being zero
      // outside. It is the same picture and a hundred times the work, and
      // the dirty rectangle a renderer uploads becomes the whole texture.
      expect(alphaAt(32, 32), greaterThan(200));
      expect(alphaAt(2, 2), 0);
      expect(alphaAt(61, 61), 0);
    });

    test('keeps the layers, not just the picture', () {
      final ModelHistory history = opened();
      expect(history.run(stroke()), isNull);
      final PaintStack? stack = history.project.materials.single.paint;
      expect(stack, isNotNull);
      expect(stack!.layers, hasLength(1));
      // Mutation: keep only the flattened image. The layer order, the blend
      // modes and the layer above the one being painted all stop existing
      // the moment a stroke lands.
      expect(stack.layers.single.tiles, isNotEmpty);
    });

    test('and undo puts the document back exactly', () {
      final ModelHistory history = opened();
      expect(history.run(stroke()), isNull);
      expect(history.undo(), isTrue);
      expect(history.project.images, isEmpty);
      expect(history.project.materials.single.paint, isNull);
      expect(history.project.materials.single.surface.baseColorTexture, isNull);
    });
  });

  group('the layers', () {
    test('painting onto layer one makes two', () {
      final ModelHistory history = opened();
      expect(history.run(stroke(layer: 1)), isNull);
      expect(history.project.materials.single.paint!.layers, hasLength(2));
    });

    test('and a second stroke reuses the image rather than adding one', () {
      final ModelHistory history = opened();
      expect(history.run(stroke()), isNull);
      expect(history.run(stroke(at: Vector3(0.3, 0.3, 0))), isNull);
      // Mutation: append a new image per stroke. A gesture of a hundred
      // samples would grow the file by a hundred canvases.
      expect(history.project.images, hasLength(1));
    });
  });

  group('the mask', () {
    test('at zero suppresses the stroke entirely', () {
      final ModelHistory history = opened(
        images: <EncodedImage>[EncodedImage(bytes: flatPng(8, 0), name: 'ao')],
      );
      expect(history.run(stroke(maskImage: 0)), isNull);

      // **The row's own "an AO=0 mask suppresses it".** The canvas the slot
      // points at is the one this stroke wrote, and every texel of it is
      // still transparent.
      final DecodedImage canvas = painted(history)!;
      var painted_ = 0;
      for (var i = 0; i < canvas.width * canvas.height; i++) {
        if (canvas.rgba[i * 4 + 3] != 0) painted_++;
      }
      expect(painted_, 0);
    });

    test('inverted, the same mask paints everywhere the brush reaches', () {
      final ModelHistory history = opened(
        images: <EncodedImage>[EncodedImage(bytes: flatPng(8, 0), name: 'ao')],
      );
      expect(history.run(stroke(maskImage: 0, maskInverted: true)), isNull);
      final DecodedImage canvas = painted(history)!;
      expect(canvas.rgba[(32 * 64 + 32) * 4 + 3], greaterThan(200));
    });

    test('and an image that is not there is refused', () {
      final ModelHistory history = opened();
      expect(history.run(stroke(maskImage: 7)), contains('7'));
    });
  });

  group('refusals', () {
    test('no samples', () {
      final ModelHistory history = opened();
      expect(
        history.run(
          const PaintStroke(
            objectId: 1,
            samples: <PaintSample>[],
            colour: <double>[1, 1, 1, 1],
          ),
        ),
        contains('at least one sample'),
      );
    });

    test('a colour that is not four numbers', () {
      final ModelHistory history = opened();
      expect(
        history.run(stroke(colour: const <double>[1, 0])),
        contains('four numbers'),
      );
    });

    test('a mesh with no UVs, saying to unwrap it', () {
      final ModelHistory history = opened(withUv: false);
      expect(history.run(stroke()), contains('unwrap'));
    });

    test('an object with no material', () {
      final ModelHistory history = opened(withMaterial: false);
      expect(history.run(stroke()), contains('material'));
    });

    test('and a brush nowhere near the mesh', () {
      final ModelHistory history = opened();
      expect(
        history.run(stroke(at: Vector3(80, 80, 80))),
        contains('reached no texels'),
      );
      expect(history.canUndo, isFalse);
    });
  });

  group('an imported texture', () {
    test('becomes the bottom layer rather than being thrown away', () {
      final ModelHistory history = opened(
        images: <EncodedImage>[
          EncodedImage(bytes: flatPng(16, 200), name: 'wall'),
        ],
      );
      // The material points at the imported texture, the way an imported
      // model's own does.
      history.selection = ProjectSelection.none;
      expect(
        history.run(
          const SetTexture(materialIndex: 0, slot: 'albedo', imageIndex: 0),
        ),
        isNull,
      );

      expect(history.run(const AdoptTexture(materialIndex: 0)), isNull);
      final PaintStack stack = history.project.materials.single.paint!;
      expect(stack.layers, hasLength(1));
      // **Mutation: start the stack empty.** The first stroke then writes a
      // red dot on transparency into the slot the wall was in, which reads
      // as the application having deleted the texture.
      expect(stack.pixelAt(4, 4)[0], closeTo(200 / 255, 0.02));
      expect(stack.pixelAt(4, 4)[3], closeTo(1, 0.01));
    });

    test('and painting over it keeps what is underneath', () {
      final ModelHistory history = opened(
        images: <EncodedImage>[
          EncodedImage(bytes: flatPng(16, 200), name: 'wall'),
        ],
      );
      expect(
        history.run(
          const SetTexture(materialIndex: 0, slot: 'albedo', imageIndex: 0),
        ),
        isNull,
      );
      expect(history.run(const AdoptTexture(materialIndex: 0)), isNull);
      expect(history.run(stroke(layer: 1)), isNull);

      final DecodedImage canvas = painted(history)!;
      final int side = canvas.width;
      // The corner is the wall the material came with; the middle is the
      // stroke over it.
      expect(canvas.rgba[(2 * side + 2) * 4], closeTo(200, 6));
      expect(
        canvas.rgba[((side ~/ 2) * side + side ~/ 2) * 4],
        greaterThan(200),
      );
    });

    test('a material with layers already on it refuses', () {
      final ModelHistory history = opened(
        images: <EncodedImage>[
          EncodedImage(bytes: flatPng(16, 200), name: 'wall'),
        ],
      );
      expect(history.run(stroke()), isNull);
      expect(
        history.run(const AdoptTexture(materialIndex: 0)),
        contains('already has layers'),
      );
    });

    test('and a material with no texture says so', () {
      final ModelHistory history = opened();
      expect(
        history.run(const AdoptTexture(materialIndex: 0)),
        contains('no base-colour texture'),
      );
    });
  });

  group('a project file', () {
    test('carries the layers, not just the flattening — pro-doc-01', () {
      final ModelHistory history = opened();
      expect(history.run(stroke()), isNull);

      final ModelProject read = switch (readProject(
        writeProject(history.project),
      )) {
        ProjectOpened(:final project) => project,
        final ProjectRefused it => fail(it.because),
      };

      // **Mutation: write only the flattened image.** The file opens, the
      // model looks right, and the layer somebody painted is gone — which
      // they find out the first time they try to change its blend mode.
      final PaintStack? stack = read.materials.single.paint;
      expect(stack, isNotNull);
      expect(stack!.layers, hasLength(1));
      expect(
        stack.layers.single.tiles.length,
        history.project.materials.single.paint!.layers.single.tiles.length,
      );
      expect(stack.layers.single.blendMode.name, 'normal');
      expect(
        stack.pixelAt(32, 32),
        history.project.materials.single.paint!.pixelAt(32, 32),
      );
    });

    test('and a project with no paint reads back with none', () {
      final ModelHistory history = opened();
      final ModelProject read = switch (readProject(
        writeProject(history.project),
      )) {
        ProjectOpened(:final project) => project,
        final ProjectRefused it => fail(it.because),
      };
      expect(read.materials.single.paint, isNull);
    });
  });

  group('written down', () {
    test('reads back as itself', () {
      final ModelCommand? read = modelCommandFromJson(
        stroke(size: 128).toJson(),
      );
      expect(read, isA<PaintStroke>());
      final PaintStroke back = read! as PaintStroke;
      expect(back.objectId, 1);
      expect(back.samples, hasLength(1));
      expect(back.samples.single.radius, 0.2);
      expect(back.colour, <double>[1, 0, 0, 1]);
      expect(back.size, 128);
    });
  });
}
