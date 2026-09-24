/// A uniform block as one object — `H1`.
///
/// The contract takes a block as a map of member names to floats, and still
/// does: every backend reads it that way, and changing the wire format would
/// touch four of them for nothing the compiler does not already give. What
/// this adds is the other end. `flutter3d_shaders` generates a class per
/// block from the compiled bundle's own layout, with one preallocated array
/// per member, so a caller fills fields the compiler checks instead of
/// spelling member names it can get wrong, and builds no map per draw.
library;

import 'dart:typed_data';

import 'command_encoder.dart';
import 'shader.dart';

/// A block's members, by name, under the block's own name.
abstract base class UniformBlock {
  const UniformBlock(this.name);

  /// The block's name as the shaders declare it.
  final String name;

  /// Every member, by name. The same map every time: the arrays in it are
  /// the block's own, filled in place.
  Map<String, Float32List> get members;
}

extension BindUniformBlockObject on PassEncoder {
  /// Binds [block] to [stage] — `bindUniformBlock` with the block's name and
  /// members.
  ///
  /// **Only the members [stage] has, where its layout is known.** One block
  /// name can be wider in one stage than another: bloom's upsample declares a
  /// tint its threshold does not, and a generated class carries the union.
  /// Handing the narrower stage the wider map would be refused by name, so
  /// the members its layout does not list are left out here.
  bool bindBlock(ShaderHandle stage, UniformBlock block) {
    final layout = stage.layouts?[block.name];
    final members = block.members;
    if (layout == null || layout.length >= members.length) {
      return bindUniformBlock(stage, block.name, members);
    }
    return bindUniformBlock(stage, block.name, <String, Float32List>{
      for (final MapEntry(:key, :value) in members.entries)
        if (layout.containsKey(key)) key: value,
    });
  }
}
