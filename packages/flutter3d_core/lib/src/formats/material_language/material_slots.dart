/// The slot table: what a material binds beyond the engine's own blocks and
/// samplers (D21).
library;

import 'material_ast.dart';

/// One member of a uniform block of a material's own, where std140 puts it.
final class MaterialBlockMember {
  const MaterialBlockMember({
    required this.name,
    required this.type,
    required this.offset,
  });

  final String name;
  final MaterialType type;

  /// Bytes from the start of the block, as std140 lays a `float`, `vec2`,
  /// `vec3` or `vec4` out: aligned to 4, 8, 16 and 16.
  final int offset;

  /// The bytes the member takes: four a component.
  int get size => type.components * 4;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'type': type.name,
    'offset': offset,
  };

  @override
  bool operator ==(Object other) =>
      other is MaterialBlockMember &&
      other.name == name &&
      other.type == type &&
      other.offset == offset;

  @override
  int get hashCode => Object.hash(name, type, offset);
}

/// One uniform block a material binds: `MaterialParams`, or a block of its
/// own (`uniform(Hair) …`), with its members in declaration order.
final class MaterialBlockSlot {
  const MaterialBlockSlot({required this.name, required this.members});

  /// The block's name in the stage, and what it is bound by.
  final String name;

  final List<MaterialBlockMember> members;

  /// The block's size, rounded up to sixteen bytes as std140 does.
  int get size {
    if (members.isEmpty) return 0;
    final end = members.last.offset + members.last.size;
    return (end + 15) ~/ 16 * 16;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'size': size,
    'members': <Object?>[for (final member in members) member.toJson()],
  };
}

/// One texture of a material's own, by what the source calls it and what
/// it is bound under.
final class MaterialTextureSlotEntry {
  const MaterialTextureSlotEntry({required this.name, required this.binding});

  /// What the source calls it: `fur`.
  final String name;

  /// What it is bound under, and what `RenderMaterial.extraTextures` names:
  /// `material_fur`.
  final String binding;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'binding': binding,
  };
}

/// What a material binds beyond the engine's own: its uniform blocks and
/// its own textures, in a fixed order (D21).
///
/// **The contract between a plugin's lit model and every backend.** The
/// engine's lit stages bind five textures and the engine's blocks; a model
/// of a plugin's own — hair, cloth, a subsurface lobe — needs more. Its
/// source declares them (`uniform(Hair) vec3 tint = …;`, `texture fur;`),
/// this table lists them, and:
///
/// - the GLSL emitter declares each block and sampler under these names;
/// - each backend's binding plan maps an entry to its own binding — by name
///   on WebGL2, Impeller and the software backend, by group and binding
///   number on WebGPU, numbered in this order after the engine's (see "The
///   shader ABI" in `docs/CONTRACTS.md`);
/// - the renderer binds each block from `RenderMaterial.parameters` (the
///   members that belong to it) and each texture from
///   `RenderMaterial.extraTextures` under its [MaterialTextureSlotEntry.binding].
///
/// The order is the order of declaration in the source, `MaterialParams`
/// first when the material has a uniform of its own, and is part of the
/// contract: a backend that numbers bindings numbers them in it.
final class MaterialSlotTable {
  const MaterialSlotTable({
    this.blocks = const <MaterialBlockSlot>[],
    this.textures = const <MaterialTextureSlotEntry>[],
  });

  /// [program]'s table: a block per block its uniforms are members of, and
  /// an entry per texture of its own.
  factory MaterialSlotTable.of(MaterialProgram program) {
    final members = <String, List<MaterialParameter>>{};
    for (final parameter in program.parameters) {
      final block = parameter.block;
      if (block == null) continue;
      (members[block] ??= <MaterialParameter>[]).add(parameter);
    }
    return MaterialSlotTable(
      blocks: List<MaterialBlockSlot>.unmodifiable(<MaterialBlockSlot>[
        for (final MapEntry(key: name, value: uniforms) in members.entries)
          MaterialBlockSlot(name: name, members: std140(uniforms)),
      ]),
      textures: List<MaterialTextureSlotEntry>.unmodifiable(
        <MaterialTextureSlotEntry>[
          for (final slot in program.textures)
            if (slot.isOwn)
              MaterialTextureSlotEntry(
                name: slot.name,
                binding: slot.bindingName,
              ),
        ],
      ),
    );
  }

  /// A material that binds nothing beyond the engine's own.
  static const MaterialSlotTable none = MaterialSlotTable();

  final List<MaterialBlockSlot> blocks;
  final List<MaterialTextureSlotEntry> textures;

  /// Whether the material binds nothing of its own.
  bool get isEmpty => blocks.isEmpty && textures.isEmpty;

  /// The block called [name], or null.
  MaterialBlockSlot? block(String name) {
    for (final block in blocks) {
      if (block.name == name) return block;
    }
    return null;
  }

  /// The table as the bundle writer carries it beside a stage.
  Map<String, Object?> toJson() => <String, Object?>{
    if (blocks.isNotEmpty)
      'blocks': <Object?>[for (final block in blocks) block.toJson()],
    if (textures.isNotEmpty)
      'textures': <Object?>[for (final texture in textures) texture.toJson()],
  };

  /// [uniforms] laid out as std140 lays the block the emitter writes.
  static List<MaterialBlockMember> std140(List<MaterialParameter> uniforms) {
    final members = <MaterialBlockMember>[];
    var offset = 0;
    for (final parameter in uniforms) {
      final align = switch (parameter.type.components) {
        1 => 4,
        2 => 8,
        _ => 16,
      };
      offset = (offset + align - 1) ~/ align * align;
      members.add(
        MaterialBlockMember(
          name: parameter.name,
          type: parameter.type,
          offset: offset,
        ),
      );
      offset += parameter.type.components * 4;
    }
    return List<MaterialBlockMember>.unmodifiable(members);
  }
}
