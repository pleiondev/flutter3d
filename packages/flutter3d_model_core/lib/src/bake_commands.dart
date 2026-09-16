/// `pro-rt-06`: baking a high mesh's surface onto a low one's UVs, as a
/// command — the maps, the images they become, and the slots they land in.
///
/// **One command for however many maps, because they share the walk.**
/// Every map `flutter3d_mesh`'s own `bake.dart` produces is a different
/// answer asked at the same texels; baking a normal map and an occlusion map
/// as two commands would rasterize the low mesh twice and build the high
/// mesh's tree twice for no gain, and would put two steps on the history
/// where a person did one thing.
///
/// **Two of the four land in a material slot and two do not, and that is
/// glTF's own shape rather than a gap here.** A normal map is
/// `normalTexture` and an occlusion map is `occlusionTexture`; curvature and
/// thickness have no slot in the format at all, so they are added to the
/// project's images, named, and left unbound for a texture graph
/// (`mat-10`) to read as a mask — which is what they are for.
///
/// **An image already in the project is reused rather than added twice.**
/// The same dedup-by-bytes `BakeTextureGraph` does: re-running a bake that
/// produced the same map does not grow the file.
part of 'command.dart';

/// Which maps [BakeMaps] knows how to produce.
///
/// A final class with const instances rather than an enum, the same choice
/// `BrushKind` makes and for the same reason: this package is published and
/// a fifth map would be a breaking change for every external `switch`.
final class BakeMapKind {
  const BakeMapKind._(this.name, this.slot);

  /// What this map is called in a command's arguments and in an image's own
  /// name.
  final String name;

  /// The material slot it binds to, or null where the format has none.
  final String? slot;

  static const BakeMapKind normal = BakeMapKind._('normal', 'normal');
  static const BakeMapKind ambientOcclusion = BakeMapKind._('ao', 'occlusion');
  static const BakeMapKind curvature = BakeMapKind._('curvature', null);
  static const BakeMapKind thickness = BakeMapKind._('thickness', null);

  /// Every map this build can bake, in the order a command lists them.
  static const List<BakeMapKind> values = <BakeMapKind>[
    normal,
    ambientOcclusion,
    curvature,
    thickness,
  ];

  /// The map [name] names, or null.
  static BakeMapKind? named(String name) {
    for (final BakeMapKind kind in values) {
      if (kind.name == name) return kind;
    }
    return null;
  }

  @override
  String toString() => 'BakeMapKind.$name';
}

/// Bakes [maps] from [sourceId]'s surface onto [targetId]'s UVs.
final class BakeMaps extends ModelCommand {
  const BakeMaps({
    required this.sourceId,
    required this.targetId,
    this.maps = const <String>['normal'],
    this.resolution = 1024,
    this.shell = 0.1,
  });

  /// The high mesh, the one with the detail on it.
  final int sourceId;

  /// The low mesh, the one with the UVs the maps are written into.
  final int targetId;

  /// Which maps, by [BakeMapKind.name].
  final List<String> maps;

  /// The side of the square image, in texels.
  final int resolution;

  /// How far either side of the low surface the ray cage reaches, in metres
  /// — see `bake.dart` for why it is a shell and not a one-sided ray.
  final double shell;

  @override
  String get name => 'bakeMaps';

  @override
  String get says => maps.length == 1
      ? 'bake the ${maps.single} map'
      : 'bake ${maps.length} maps';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'sourceId': sourceId,
    'targetId': targetId,
    'maps': maps,
    'resolution': resolution,
    'shell': shell,
  };

  @override
  Map<String, ParamHint> get hints => const <String, ParamHint>{
    'shell': DoubleHint(min: 0.001, max: 1, step: 0.005),
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    if (resolution < 16 || resolution > 4096) {
      return Outcome.refused(
        'a bake is between 16 and 4096 texels a side, not $resolution',
      );
    }
    if (maps.isEmpty) return Outcome.refused('bakeMaps needs a map to bake');
    final kinds = <BakeMapKind>[];
    for (final String named in maps) {
      final BakeMapKind? kind = BakeMapKind.named(named);
      if (kind == null) {
        return Outcome.refused(
          'there is no "$named" map — this build bakes '
          '${BakeMapKind.values.map((BakeMapKind it) => it.name).join(", ")}',
        );
      }
      kinds.add(kind);
    }

    final EditMesh? high = _meshOf(project, sourceId);
    if (high == null) {
      return Outcome.refused('object $sourceId has no mesh to bake from');
    }
    final ModelObject? target = project[targetId];
    final EditMesh? low = _meshOf(project, targetId);
    if (target == null || low == null) {
      return Outcome.refused('object $targetId has no mesh to bake onto');
    }
    if (!low.hasLayer(MeshDomain.corner, MeshAttribute.uv0)) {
      return Outcome.refused(
        '"${target.name}" has no UVs, and a baked map is written into them '
        '— unwrap it first',
      );
    }

    final TriangleBvh surface = surfaceOf(high);
    var images = List<EncodedImage>.of(project.images);
    final bound = <String, int>{};
    for (final BakeMapKind kind in kinds) {
      final BakedMap baked = switch (kind.name) {
        'ao' => bakeAmbientOcclusion(low: low, high: surface, size: resolution),
        'curvature' => bakeCurvature(low: low, size: resolution),
        'thickness' => bakeThickness(low: low, high: surface, size: resolution),
        _ => bakeNormalMap(
          low: low,
          high: surface,
          size: resolution,
          shell: shell,
        ),
      };
      dilate(baked);
      final Uint8List rgba = kind.name == 'normal'
          ? baked.toRgba8(bias: 1, scale: 0.5)
          : baked.toRgba8();
      final Uint8List png = encodeCompressedPng(resolution, resolution, rgba);
      var at = -1;
      for (var i = 0; i < images.length; i++) {
        if (_bytesEqual(images[i].bytes, png)) {
          at = i;
          break;
        }
      }
      if (at == -1) {
        at = images.length;
        images = <EncodedImage>[
          ...images,
          EncodedImage(bytes: png, name: '${kind.name} bake'),
        ];
      }
      if (kind.slot != null) bound[kind.slot!] = at;
    }

    if (bound.isEmpty) {
      // Curvature and thickness alone: the images are in the project for a
      // texture graph to read, and no material changed.
      return Outcome.done(project.copyWith(images: images));
    }

    final int materialIndex = target.materialSlots.isEmpty
        ? -1
        : target.materialSlots.first;
    if (materialIndex < 0 || materialIndex >= project.materials.length) {
      return Outcome.refused(
        '"${target.name}" has no material for a baked map to land on — '
        'assign one first',
      );
    }
    final ProjectMaterial material = project.materials[materialIndex];
    var next = material.surface;
    for (final MapEntry<String, int> each in bound.entries) {
      final binding = TextureBinding(imageIndex: each.value);
      next = switch (each.key) {
        'occlusion' => _surfaceWith(
          next,
          occlusionTexture: binding,
          setOcclusionTexture: true,
        ),
        _ => _surfaceWith(next, normalTexture: binding, setNormalTexture: true),
      };
    }

    return Outcome.done(
      project.copyWith(
        images: images,
        materials: <ProjectMaterial>[
          for (var i = 0; i < project.materials.length; i++)
            i == materialIndex ? material.withBake(next) : project.materials[i],
        ],
      ),
    );
  }
}

/// [id]'s own `EditMesh`, or null when it has none.
EditMesh? _meshOf(ModelProject project, int id) =>
    switch (project[id]?.geometry) {
      EditedGeometry(:final mesh) => mesh,
      _ => null,
    };
