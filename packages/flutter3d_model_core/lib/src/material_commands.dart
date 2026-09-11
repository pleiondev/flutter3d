/// The commands that change the material table and what an object is painted
/// with.
///
/// **A material is a row, addressed by position, the way a texture already
/// is.** Nothing here gives a material an id the way an object has one, because
/// nothing needs to survive a reorder the way an object survives one under an
/// undo — a row is only ever appended or, in [RemoveMaterial], collapsed, and
/// every command that names one takes the index it is at right now.
part of 'command.dart';

/// Adds a material to the project's table, painted with nothing in particular.
///
/// **Its index is `project.materials.length` before this runs** — a material
/// has no id of its own, the way an object does, because nothing ever names one
/// out of order: [AssignMaterial] and [SetTexture] both address a material by
/// its row, and a row that is always appended is a row a caller can predict
/// without being handed one back.
final class AddMaterial extends ModelCommand {
  const AddMaterial({this.materialName});

  /// What the table shows for it.
  ///
  /// **Not `name` in [arguments], which `toJson` spreads over the command's
  /// own `name` key.** [AddLathe.shapeName] hit the same trap first.
  final String? materialName;

  @override
  String get name => 'addMaterial';

  @override
  String get says =>
      materialName == null ? 'add a material' : 'add material "$materialName"';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'materialName': materialName,
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) =>
      Outcome.done(
        project.copyWith(
          materials: <ProjectMaterial>[
            ...project.materials,
            ProjectMaterial(surface: SurfaceMaterial(name: materialName)),
          ],
        ),
      );
}

/// Drops a material out of the project's table.
///
/// **Every object beyond it moves down one, because the table has no gaps.**
/// An object slotted onto the material removed comes back unpainted — the
/// viewport's own default — rather than sliding onto whatever used to sit one
/// row further on; an object untouched by either change keeps its own
/// [ModelObject], `identical` to the one before, the way every other edit here
/// leaves what it did not touch alone.
final class RemoveMaterial extends ModelCommand {
  const RemoveMaterial(this.index);

  final int index;

  @override
  String get name => 'removeMaterial';

  @override
  String get says => 'remove a material';

  @override
  Map<String, Object?> get arguments => <String, Object?>{'index': index};

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    if (index < 0 || index >= project.materials.length) {
      return Outcome.refused('there is no material $index');
    }
    final materials = List<ProjectMaterial>.of(project.materials)
      ..removeAt(index);
    final objects = <ModelObject>[
      for (final ModelObject object in project.objects)
        if (object.materialSlots.any((int slot) => slot >= index))
          object.copyWith(
            materialSlots: <int>[
              for (final int slot in object.materialSlots)
                if (slot < index) slot else if (slot > index) slot - 1,
            ],
          )
        else
          object,
    ];
    return Outcome.done(
      ModelProject(
        profile: project.profile,
        objects: objects,
        materials: materials,
        images: project.images,
        nextId: project.nextId,
      ),
    );
  }
}

/// Copies a material to a new row, for a variant that starts from it.
final class DuplicateMaterial extends ModelCommand {
  const DuplicateMaterial(this.index);

  final int index;

  @override
  String get name => 'duplicateMaterial';

  @override
  String get says => 'duplicate a material';

  @override
  Map<String, Object?> get arguments => <String, Object?>{'index': index};

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    if (index < 0 || index >= project.materials.length) {
      return Outcome.refused('there is no material $index');
    }
    final SurfaceMaterial source = project.materials[index].surface;
    final String? copyName = source.name == null ? null : '${source.name} copy';
    return Outcome.done(
      project.copyWith(
        materials: <ProjectMaterial>[
          ...project.materials,
          ProjectMaterial(surface: _surfaceWith(source, name: copyName)),
        ],
      ),
    );
  }
}

/// Sets one field of a material by name.
///
/// **The names are `writeFmat`'s own top-level keys** (`baseColor`, `metallic`,
/// `alphaMode`, …), so a slider bound to a material's field and a hand-edited
/// `.fmat` describe the same thing with the same word — one card, one
/// vocabulary, and a person moving between the two never has to translate.
/// Texture slots are not among them; those are [SetTexture]'s, because a slot
/// takes an image and a sampler together and a single value cannot carry both.
final class SetMaterialField extends ModelCommand {
  const SetMaterialField({
    required this.index,
    required this.field,
    required this.value,
  });

  final int index;
  final String field;

  /// A number, a string, a bool, or a list of three or four numbers,
  /// depending on [field]. See `_fieldSet` for which.
  final Object? value;

  @override
  String get name => 'setMaterialField';

  @override
  String get says => 'set $field';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'index': index,
    'field': field,
    'value': value,
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    if (index < 0 || index >= project.materials.length) {
      return Outcome.refused('there is no material $index');
    }
    final ProjectMaterial material = project.materials[index];
    final SurfaceMaterial? next = _fieldSet(material.surface, field, value);
    if (next == null) {
      return Outcome.refused(
        '"$field" is not a material field, or its value is the wrong shape',
      );
    }
    return Outcome.done(
      project.copyWith(
        materials: <ProjectMaterial>[
          for (var i = 0; i < project.materials.length; i++)
            i == index ? material.withSurface(next) : project.materials[i],
        ],
      ),
    );
  }
}

/// Replaces (or clears) the whole [TextureGraph] a material's texture slots
/// can be baked from.
///
/// **Whole-graph, not node by node.** `AddNode`/`Link`/`Unlink`/
/// `SetNodeField`/`MoveNode` — the fine-grained verbs a panel edits one node
/// at a time with — are `mat-13`'s own row, not this one; this command is
/// the plumbing that gets a graph onto a material at all, the same way
/// [AddMaterial] hands a material a blank [SurfaceMaterial] before anything
/// edits it field by field.
final class SetMaterialGraph extends ModelCommand {
  const SetMaterialGraph({required this.materialIndex, this.graph});

  final int materialIndex;

  /// The new graph, or null to take one off a material entirely.
  final TextureGraph? graph;

  @override
  String get name => 'setMaterialGraph';

  @override
  String get says =>
      graph == null ? 'clear the texture graph' : 'set the texture graph';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'materialIndex': materialIndex,
    'graph': graph?.toJson(),
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    if (materialIndex < 0 || materialIndex >= project.materials.length) {
      return Outcome.refused('there is no material $materialIndex');
    }
    final ProjectMaterial material = project.materials[materialIndex];
    return Outcome.done(
      project.copyWith(
        materials: <ProjectMaterial>[
          for (var i = 0; i < project.materials.length; i++)
            i == materialIndex ? material.withGraph(graph) : project.materials[i],
        ],
      ),
    );
  }
}

/// Bakes a material's own [ProjectMaterial.graph] to pixels and wires the
/// result into whichever texture slots its `OutputTextureNode`s each name —
/// `mat-12`'s own row, the command `mat-11`'s CPU compositor and this file's
/// own [encodePng] existed to be called from.
///
/// **Every output with a [OutputTextureNode.slot] bakes in one step.** A
/// graph feeding `albedo` and `normal` both writes two images and moves the
/// material to its new [ProjectMaterial.version] once, not twice — the same
/// "one call, one step" shape [SetTexture] already gives a single slot, kept
/// for a graph that touches several.
///
/// **A baked image is interned the same way [AddImage] interns an uploaded
/// one.** Baking the same graph twice in a row — nothing between the two
/// calls changed a source image or a node field — writes the same PNG bytes
/// both times, and the second bake reuses the first's row rather than
/// appending a duplicate the file would carry forever.
final class BakeTextureGraph extends ModelCommand {
  const BakeTextureGraph({required this.materialIndex, this.size = 1024});

  final int materialIndex;

  /// The square a graph bakes to. Synchronous — a command's own [apply]
  /// cannot await an isolate the way `bakeTextureFull` does — so this stays
  /// close to `mat-11`'s own preview size rather than an export size a panel
  /// would ask for off the main isolate.
  final int size;

  @override
  String get name => 'bakeTextureGraph';

  @override
  String get says => 'bake the texture graph';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'materialIndex': materialIndex,
    'size': size,
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    if (materialIndex < 0 || materialIndex >= project.materials.length) {
      return Outcome.refused('there is no material $materialIndex');
    }
    final ProjectMaterial material = project.materials[materialIndex];
    final TextureGraph? graph = material.graph;
    if (graph == null) {
      return Outcome.refused(
        'material $materialIndex has no texture graph to bake',
      );
    }
    final issues = graph.validate();
    if (issues.isNotEmpty) {
      return Outcome.refused(
        'the texture graph is not valid: ${issues.first.message}',
      );
    }
    final outputs = <OutputTextureNode>[
      for (final node in graph.nodes)
        if (node is OutputTextureNode && node.slot != null) node,
    ];
    if (outputs.isEmpty) {
      return Outcome.refused('the texture graph feeds no material slot');
    }

    final images = <int, Uint8List>{
      for (var i = 0; i < project.images.length; i++) i: project.images[i].bytes,
    };
    final cache = TextureBakeCache();
    var nextImages = List<EncodedImage>.of(project.images);
    var next = material.surface;
    for (final OutputTextureNode output in outputs) {
      final Uint8List? rgba = bakeTextureGraph(
        graph,
        output.id,
        images,
        size: size,
        cache: cache,
      );
      if (rgba == null) {
        return Outcome.refused('output ${output.id} did not bake');
      }
      final Uint8List png = encodePng(size, size, rgba);
      var at = -1;
      for (var i = 0; i < nextImages.length; i++) {
        if (_bytesEqual(nextImages[i].bytes, png)) {
          at = i;
          break;
        }
      }
      if (at == -1) {
        at = nextImages.length;
        nextImages = <EncodedImage>[
          ...nextImages,
          EncodedImage(bytes: png, name: '${output.slot} bake'),
        ];
      }
      final binding = TextureBinding(imageIndex: at);
      next = switch (output.slot!) {
        'albedo' => _surfaceWith(
          next,
          baseColorTexture: binding,
          setBaseColorTexture: true,
        ),
        'normal' => _surfaceWith(
          next,
          normalTexture: binding,
          setNormalTexture: true,
        ),
        'metallicRoughness' => _surfaceWith(
          next,
          metallicRoughnessTexture: binding,
          setMetallicRoughnessTexture: true,
        ),
        'occlusion' => _surfaceWith(
          next,
          occlusionTexture: binding,
          setOcclusionTexture: true,
        ),
        'emissive' => _surfaceWith(
          next,
          emissiveTexture: binding,
          setEmissiveTexture: true,
        ),
        // Written by `SetMaterialGraph` from `TextureGraph.toJson`/`fromJson`
        // only, never typed by a person, so a name outside `_textureSlots`
        // here is a graph from a build newer than this one, not a mistake
        // to refuse the whole bake over — skip the slot this build cannot
        // place and keep the rest.
        _ => next,
      };
    }

    final bakedMaterial = material.withBake(next);
    return Outcome.done(
      project.copyWith(
        materials: <ProjectMaterial>[
          for (var i = 0; i < project.materials.length; i++)
            i == materialIndex ? bakedMaterial : project.materials[i],
        ],
        images: nextImages,
      ),
    );
  }
}

/// The five texture slots a material has, named the way `writeFmat` names them
/// under `textures`.
const List<String> _textureSlots = <String>[
  'albedo',
  'normal',
  'metallicRoughness',
  'occlusion',
  'emissive',
];

/// Points a material's texture slot at an image, or clears it.
final class SetTexture extends ModelCommand {
  const SetTexture({
    required this.materialIndex,
    required this.slot,
    this.imageIndex,
    this.sampling = const TextureSampling(),
  });

  final int materialIndex;

  /// One of [_textureSlots].
  final String slot;

  /// The image this samples, by index into [ModelProject.images], or null to
  /// paint the slot with nothing.
  final int? imageIndex;

  final TextureSampling sampling;

  @override
  String get name => 'setTexture';

  @override
  String get says => 'set the $slot texture';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'materialIndex': materialIndex,
    'slot': slot,
    'imageIndex': imageIndex,
    'magLinear': sampling.magLinear,
    'minLinear': sampling.minLinear,
    'useMipmaps': sampling.useMipmaps,
    'wrapS': sampling.wrapS.name,
    'wrapT': sampling.wrapT.name,
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    if (materialIndex < 0 || materialIndex >= project.materials.length) {
      return Outcome.refused('there is no material $materialIndex');
    }
    final int? at = imageIndex;
    if (at != null && (at < 0 || at >= project.images.length)) {
      return Outcome.refused('there is no image $at');
    }
    final TextureBinding? binding = at == null
        ? null
        : TextureBinding(imageIndex: at, sampling: sampling);
    final ProjectMaterial material = project.materials[materialIndex];
    final SurfaceMaterial? next = switch (slot) {
      'albedo' => _surfaceWith(
        material.surface,
        baseColorTexture: binding,
        setBaseColorTexture: true,
      ),
      'normal' => _surfaceWith(
        material.surface,
        normalTexture: binding,
        setNormalTexture: true,
      ),
      'metallicRoughness' => _surfaceWith(
        material.surface,
        metallicRoughnessTexture: binding,
        setMetallicRoughnessTexture: true,
      ),
      'occlusion' => _surfaceWith(
        material.surface,
        occlusionTexture: binding,
        setOcclusionTexture: true,
      ),
      'emissive' => _surfaceWith(
        material.surface,
        emissiveTexture: binding,
        setEmissiveTexture: true,
      ),
      _ => null,
    };
    if (next == null) {
      return Outcome.refused(
        '"$slot" is not a texture slot; it is one of ${_textureSlots.join(', ')}',
      );
    }
    return Outcome.done(
      project.copyWith(
        materials: <ProjectMaterial>[
          for (var i = 0; i < project.materials.length; i++)
            i == materialIndex
                ? material.withSurface(next)
                : project.materials[i],
        ],
      ),
    );
  }
}

/// Adds an image a material can sample, interned by content.
///
/// **The same bytes twice come back as the same row.** A texture picked for two
/// materials — or reached through an importer that offers the same file more
/// than once — is one upload here rather than two, which is what
/// `toModelDocument` then writes out unchanged: the table it copies across
/// never held a duplicate to begin with.
final class AddImage extends ModelCommand {
  const AddImage({required this.bytes, this.imageName, this.mimeType});

  final Uint8List bytes;

  /// Not `name` in [arguments], for the reason [AddMaterial.materialName]
  /// gives.
  final String? imageName;
  final String? mimeType;

  @override
  String get name => 'addImage';

  @override
  String get says =>
      imageName == null ? 'add an image' : 'add image "$imageName"';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'bytes': base64Encode(bytes),
    'imageName': imageName,
    'mimeType': mimeType,
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    if (bytes.isEmpty) return Outcome.refused('an image needs bytes');
    for (final EncodedImage each in project.images) {
      if (_bytesEqual(each.bytes, bytes)) return Outcome.done(project);
    }
    return Outcome.done(
      project.copyWith(
        images: <EncodedImage>[
          ...project.images,
          EncodedImage(bytes: bytes, name: imageName, mimeType: mimeType),
        ],
      ),
    );
  }
}

/// Paints one object with a material, or takes its paint off.
final class AssignMaterial extends ModelCommand {
  const AssignMaterial({required this.id, required this.to});

  final int id;

  /// The material's row, or null to leave the object unpainted.
  final int? to;

  @override
  String get name => 'assignMaterial';

  @override
  String get says => to == null ? 'clear the material' : 'assign a material';

  @override
  Map<String, Object?> get arguments => <String, Object?>{'id': id, 'to': to};

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    final ModelObject? object = project[id];
    if (object == null) return Outcome.refused('there is no object $id');
    final int? material = to;
    if (material != null &&
        (material < 0 || material >= project.materials.length)) {
      return Outcome.refused('there is no material $material');
    }
    return Outcome.done(
      project.withObject(
        object.copyWith(
          materialSlots: material == null ? const <int>[] : <int>[material],
        ),
      ),
    );
  }
}

/// A value no caller could pass, so its presence in a default marks a
/// parameter [_surfaceWith] was not asked to change.
const Object _unset = Object();

/// [s] with some fields replaced.
///
/// **A sentinel default rather than a plain nullable one, for the texture
/// slots and the name.** Every other field has no honest "clear" — a material
/// is never asked to un-know its own roughness — so a null there safely means
/// "leave it". A texture slot's null is `SetTexture` clearing it on purpose,
/// and a nullable parameter cannot tell that apart from a parameter nobody
/// touched; the `set…` flags are what tell them apart.
SurfaceMaterial _surfaceWith(
  SurfaceMaterial s, {
  Object? name = _unset,
  Vector4? baseColor,
  double? metallic,
  double? roughness,
  TextureBinding? baseColorTexture,
  bool setBaseColorTexture = false,
  TextureBinding? metallicRoughnessTexture,
  bool setMetallicRoughnessTexture = false,
  TextureBinding? normalTexture,
  bool setNormalTexture = false,
  double? normalScale,
  TextureBinding? occlusionTexture,
  bool setOcclusionTexture = false,
  double? occlusionStrength,
  TextureBinding? emissiveTexture,
  bool setEmissiveTexture = false,
  Vector3? emissive,
  double? emissiveStrength,
  SurfaceAlphaMode? alphaMode,
  double? alphaCutoff,
  bool? doubleSided,
  bool? unlit,
}) => SurfaceMaterial(
  name: identical(name, _unset) ? s.name : name as String?,
  baseColor: baseColor ?? s.baseColor,
  metallic: metallic ?? s.metallic,
  roughness: roughness ?? s.roughness,
  baseColorTexture: setBaseColorTexture ? baseColorTexture : s.baseColorTexture,
  metallicRoughnessTexture: setMetallicRoughnessTexture
      ? metallicRoughnessTexture
      : s.metallicRoughnessTexture,
  normalTexture: setNormalTexture ? normalTexture : s.normalTexture,
  normalScale: normalScale ?? s.normalScale,
  occlusionTexture: setOcclusionTexture ? occlusionTexture : s.occlusionTexture,
  occlusionStrength: occlusionStrength ?? s.occlusionStrength,
  emissiveTexture: setEmissiveTexture ? emissiveTexture : s.emissiveTexture,
  emissive: emissive ?? s.emissive,
  emissiveStrength: emissiveStrength ?? s.emissiveStrength,
  alphaMode: alphaMode ?? s.alphaMode,
  alphaCutoff: alphaCutoff ?? s.alphaCutoff,
  doubleSided: doubleSided ?? s.doubleSided,
  unlit: unlit ?? s.unlit,
);

/// [s] with [field] set to [value], or null when [field] is not a field or
/// [value] is not its shape.
///
/// The shapes: `name` is a string or null; `baseColor` and `emissive` are four
/// and three numbers; `alphaMode` is one of [SurfaceAlphaMode]'s names; every
/// other field is a number or, for `doubleSided`/`unlit`, a bool.
SurfaceMaterial? _fieldSet(SurfaceMaterial s, String field, Object? value) {
  switch (field) {
    case 'name':
      return value == null || value is String
          ? _surfaceWith(s, name: value)
          : null;
    case 'baseColor':
      return switch (_doubles(value, 4)) {
        final List<double> c => _surfaceWith(
          s,
          baseColor: Vector4(c[0], c[1], c[2], c[3]),
        ),
        _ => null,
      };
    case 'metallic':
      return value is num ? _surfaceWith(s, metallic: value.toDouble()) : null;
    case 'roughness':
      return value is num ? _surfaceWith(s, roughness: value.toDouble()) : null;
    case 'normalScale':
      return value is num
          ? _surfaceWith(s, normalScale: value.toDouble())
          : null;
    case 'occlusionStrength':
      return value is num
          ? _surfaceWith(s, occlusionStrength: value.toDouble())
          : null;
    case 'emissive':
      return switch (_doubles(value, 3)) {
        final List<double> c => _surfaceWith(
          s,
          emissive: Vector3(c[0], c[1], c[2]),
        ),
        _ => null,
      };
    case 'emissiveStrength':
      return value is num
          ? _surfaceWith(s, emissiveStrength: value.toDouble())
          : null;
    case 'alphaMode':
      if (value is! String) return null;
      for (final SurfaceAlphaMode mode in SurfaceAlphaMode.values) {
        if (mode.name == value) return _surfaceWith(s, alphaMode: mode);
      }
      return null;
    case 'alphaCutoff':
      return value is num
          ? _surfaceWith(s, alphaCutoff: value.toDouble())
          : null;
    case 'doubleSided':
      return value is bool ? _surfaceWith(s, doubleSided: value) : null;
    case 'unlit':
      return value is bool ? _surfaceWith(s, unlit: value) : null;
    default:
      return null;
  }
}

/// The wrap mode [json] names, [TextureWrap.repeat] for anything else — the
/// same fallback `_readSampling` in `project_format.dart` gives, because a
/// sampler that does not say how it wraps is one nothing has ever asked to
/// wrap unusually.
TextureWrap _wrapNamed(Object? json) => switch (json) {
  'clampToEdge' => TextureWrap.clampToEdge,
  'mirroredRepeat' => TextureWrap.mirroredRepeat,
  _ => TextureWrap.repeat,
};

/// Whether [a] and [b] hold the same bytes.
bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
