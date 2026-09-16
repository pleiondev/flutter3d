/// `pro-pt-03`: a texture-painting stroke, as one command and one undo step.
///
/// **A stroke, not a dab, for the reason `SculptStroke` is one.** A brush
/// reports a sample per pointer move; a command per sample would be a
/// hundred presses of ⌘Z to take back one gesture.
///
/// **What is kept is the layers, and what is drawn is the flattening.** The
/// strokes land in a [PaintStack] on the material — copy-on-write in 64×64
/// tiles, so a stroke over three tiles of a 4K canvas copies three of them —
/// and the flattened result is written into the project's images beside
/// every other texture. Keeping only the flattened picture would make the
/// layer order, the blend modes and the layer above the one being painted
/// all unrecoverable the moment a stroke lands.
///
/// **Undo is the kept document, and it is byte-exact by construction.** A
/// step holds the project as it was, which holds the material as it was,
/// which holds the tiles as they were — the untouched ones by reference. No
/// reversal is computed and none can be wrong.
///
/// **A mask is a texture read at the same texel, not a second brush.**
/// `pro-rt-05`'s occlusion and curvature maps are already in
/// [ModelProject.images], already in this material's own UVs; a stroke that
/// names one multiplies its own weight by whatever the mask holds under each
/// texel, which is how paint settles into crevices instead of being painted
/// into them by hand. A mask that reads zero suppresses the stroke there
/// entirely.
part of 'command.dart';

/// One dab of a texture-painting stroke: where the brush touched the
/// surface, and how far it reached.
final class PaintSample {
  const PaintSample({required this.centre, required this.radius});

  /// In the object's own space — the same space `SculptStroke.points` are
  /// in, and the space `projectBrush` measures its ball in.
  final Vector3 centre;

  final double radius;

  Map<String, Object?> toJson() => <String, Object?>{
    'centre': <double>[centre.x, centre.y, centre.z],
    'radius': radius,
  };

  /// A [PaintSample] from its own [toJson], or null.
  static PaintSample? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    return switch (json) {
      {'centre': final Object? centreJson, 'radius': final num radius} =>
        switch (_doubles(centreJson, 3)) {
          final List<double> centre => PaintSample(
            centre: Vector3(centre[0], centre[1], centre[2]),
            radius: radius.toDouble(),
          ),
          null => null,
        },
      _ => null,
    };
  }
}

/// Paints [samples] onto the object's own texture, as one step.
final class PaintStroke extends ModelCommand {
  const PaintStroke({
    required this.objectId,
    required this.samples,
    required this.colour,
    this.layer = 0,
    this.strength = 1.0,
    this.size = 1024,
    this.maskImage,
    this.maskInverted = false,
  });

  /// The object being painted — its mesh carries the UVs, its first material
  /// slot carries the layers.
  final int objectId;

  final List<PaintSample> samples;

  /// Straight-alpha RGBA, `0..1` each.
  final List<double> colour;

  /// Which layer of the stack, counted from the bottom. A layer past the end
  /// is added, so painting onto layer 1 of an empty material makes two.
  final int layer;

  /// How hard, `0..1`, multiplied into the brush's own falloff.
  final double strength;

  /// The side of the square canvas, in texels. Only read when the material
  /// has no stack yet: a stack already painted on keeps its own size, since
  /// changing it would throw away every tile in it.
  final int size;

  /// An index into [ModelProject.images] whose red channel gates the stroke
  /// — `pro-rt-05`'s own occlusion or curvature bake. Null paints evenly.
  final int? maskImage;

  /// Whether the mask is read the other way up: a cavity mask painted into
  /// the crevices rather than away from them.
  final bool maskInverted;

  @override
  String get name => 'paintStroke';

  @override
  String get says => 'paint';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'objectId': objectId,
    'samples': <Object?>[for (final PaintSample it in samples) it.toJson()],
    'colour': colour,
    'layer': layer,
    'strength': strength,
    'size': size,
    if (maskImage != null) 'maskImage': maskImage,
    'maskInverted': maskInverted,
  };

  @override
  Map<String, ParamHint> get hints => const <String, ParamHint>{
    'strength': DoubleHint(min: 0, max: 1, step: 0.05),
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    if (samples.isEmpty) {
      return Outcome.refused('paintStroke needs at least one sample');
    }
    if (colour.length != 4) {
      return Outcome.refused(
        'a colour is four numbers, red green blue alpha; got ${colour.length}',
      );
    }
    if (layer < 0) return Outcome.refused('there is no layer $layer');
    if (size < 16 || size > 4096) {
      return Outcome.refused(
        'a canvas is between 16 and 4096 texels a side, not $size',
      );
    }
    final ModelObject? object = project[objectId];
    if (object == null) return Outcome.refused('there is no object $objectId');
    final EditMesh? mesh = switch (object.geometry) {
      EditedGeometry(:final mesh) => mesh,
      _ => null,
    };
    if (mesh == null) {
      return Outcome.refused('"${object.name}" has no mesh to paint on');
    }
    if (!mesh.hasLayer(MeshDomain.corner, MeshAttribute.uv0)) {
      return Outcome.refused(
        '"${object.name}" has no UVs, and paint is written into them — '
        'unwrap it first',
      );
    }
    final int materialIndex = object.materialSlots.isEmpty
        ? -1
        : object.materialSlots.first;
    if (materialIndex < 0 || materialIndex >= project.materials.length) {
      return Outcome.refused(
        '"${object.name}" has no material to paint onto — assign one first',
      );
    }

    final ProjectMaterial material = project.materials[materialIndex];
    final int canvas = _canvasOf(material.paint) ?? size;
    final int tiles = (canvas / paintTileSize).ceil();
    final List<PaintLayer> layers = <PaintLayer>[...?material.paint?.layers];
    while (layers.length <= layer) {
      layers.add(PaintLayer(tilesX: tiles, tilesY: tiles));
    }

    final MaskRead? mask = switch (maskImage) {
      final int index => _maskOf(project, index, canvas, maskInverted),
      null => null,
    };
    if (maskImage != null && mask == null) {
      return Outcome.refused('there is no image $maskImage to mask with');
    }

    // Every texel the whole stroke touched, gathered first so a texel two
    // dabs crossed is written once at the stronger weight rather than twice.
    final TriangleBvh surface = surfaceOf(mesh);
    final weights = <int, double>{};
    for (final PaintSample sample in samples) {
      for (final UvSpan span in projectBrush(
        mesh: mesh,
        surface: surface,
        centre: sample.centre,
        radius: sample.radius,
        size: canvas,
      )) {
        for (var x = span.x0; x <= span.x1; x++) {
          final double weight = span.weights[x - span.x0] * strength;
          final int at = span.y * canvas + x;
          final double? already = weights[at];
          if (already == null || weight > already) weights[at] = weight;
        }
      }
    }
    if (weights.isEmpty) {
      return Outcome.refused('the brush reached no texels');
    }

    final PaintLayer painted = _paintInto(
      layers[layer],
      weights,
      colour,
      canvas,
      mask,
    );
    layers[layer] = painted;
    final PaintStack stack = PaintStack(layers);

    final Uint8List rgba = stack.flatten();
    final Uint8List png = encodeCompressedPng(canvas, canvas, rgba);
    var images = List<EncodedImage>.of(project.images);
    final int? bound = material.surface.baseColorTexture?.imageIndex;
    if (bound != null && bound < images.length) {
      // The same slot keeps the same image index across a stroke: a stroke
      // that appended a new image every time would grow the file by a whole
      // canvas per pointer gesture.
      images[bound] = EncodedImage(bytes: png, name: images[bound].name);
    } else {
      images = <EncodedImage>[
        ...images,
        EncodedImage(bytes: png, name: 'paint'),
      ];
    }
    final int index = bound ?? images.length - 1;

    final ProjectMaterial next = material
        .withPaint(stack)
        .withSurface(
          _surfaceWith(
            material.surface,
            baseColorTexture: TextureBinding(imageIndex: index),
            setBaseColorTexture: true,
          ),
        );

    return Outcome.done(
      project.copyWith(
        images: images,
        materials: <ProjectMaterial>[
          for (var i = 0; i < project.materials.length; i++)
            i == materialIndex ? next : project.materials[i],
        ],
      ),
    );
  }
}

/// A mask's own gate at one texel — see [PaintStroke.maskImage].
typedef MaskRead = double Function(int x, int y);

/// [stack]'s own canvas side, or null when there is no stack yet.
int? _canvasOf(PaintStack? stack) => stack == null || stack.layers.isEmpty
    ? null
    : stack.layers.first.tilesX * paintTileSize;

/// A reader over image [index], scaled to [canvas] and inverted when asked.
MaskRead? _maskOf(ModelProject project, int index, int canvas, bool inverted) {
  if (index < 0 || index >= project.images.length) return null;
  final decoded = decodePng(project.images[index].bytes);
  if (decoded == null) return null;
  return (int x, int y) {
    final int mx = (x * decoded.width ~/ canvas).clamp(0, decoded.width - 1);
    final int my = (y * decoded.height ~/ canvas).clamp(0, decoded.height - 1);
    final double read = decoded.rgba[(my * decoded.width + mx) * 4] / 255;
    return inverted ? 1 - read : read;
  };
}

/// [layer] with [weights] painted into it in [colour].
PaintLayer _paintInto(
  PaintLayer layer,
  Map<int, double> weights,
  List<double> colour,
  int canvas,
  MaskRead? mask,
) {
  // Gathered per tile so each one is copied once — the whole of the
  // copy-on-write claim `PaintLayer.paintTile` makes.
  final touched = <int, Uint8List>{};
  var next = layer;
  for (final MapEntry<int, double> each in weights.entries) {
    final int x = each.key % canvas;
    final int y = each.key ~/ canvas;
    final double weight =
        each.value * (mask == null ? 1.0 : mask(x, y)).clamp(0.0, 1.0);
    if (weight <= 0) continue;
    final int tx = x ~/ paintTileSize;
    final int ty = y ~/ paintTileSize;
    if (tx >= layer.tilesX || ty >= layer.tilesY) continue;
    final int key = ty * layer.tilesX + tx;
    final Uint8List pixels = touched.putIfAbsent(key, () {
      final PaintTile? already = layer.tileAt(tx, ty);
      return already == null
          ? Uint8List(paintTileSize * paintTileSize * 4)
          : Uint8List.fromList(already.pixels);
    });
    final int at =
        ((y % paintTileSize) * paintTileSize + (x % paintTileSize)) * 4;
    for (var c = 0; c < 4; c++) {
      final double was = pixels[at + c] / 255;
      final double now = was + (colour[c] - was) * weight;
      pixels[at + c] = (now.clamp(0.0, 1.0) * 255).round();
    }
  }
  for (final MapEntry<int, Uint8List> tile in touched.entries) {
    next = next.paintTile(
      tile.key % layer.tilesX,
      tile.key ~/ layer.tilesX,
      tile.value,
    );
  }
  return next;
}

/// Every [PaintSample.fromJson] in [json], or null on the first that does
/// not read back — the "no half-built command" rule every reader keeps.
List<PaintSample>? _paintSamplesFrom(List<Object?> json) {
  final out = <PaintSample>[];
  for (final Object? each in json) {
    final PaintSample? sample = PaintSample.fromJson(each);
    if (sample == null) return null;
    out.add(sample);
  }
  return out;
}
