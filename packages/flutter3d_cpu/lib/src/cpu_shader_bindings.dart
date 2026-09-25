/// The uniform blocks and textures a draw was given, by the names the shader
/// asks for.
library;

import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'cpu_texture.dart';

/// A map rather than a generated struct, because the binding contract is by
/// name: the engine writes `bindUniformBlock(shader, 'FragInfo', {...})` and a
/// backend looks the members up. A Dart shader does the same lookup.
final class ShaderBindings {
  const ShaderBindings(this.blocks, this.textures) : _found = null;

  /// The same bindings, remembering what [read] finds.
  ///
  /// For one draw, which is what the encoder builds these for: a stage reads
  /// the same few dozen members for every fragment, and two string-keyed map
  /// lookups per read were a tenth of a software frame. The blocks must not
  /// change while these are in use — true of a draw, where nothing binds.
  ShaderBindings.forDraw(this.blocks, this.textures) : _found = _Found();

  final _Found? _found;

  /// Block name to member name to floats, exactly as the engine wrote them.
  final Map<String, Map<String, Float32List>> blocks;

  /// Sampler slot name to what is bound there, with the sampler it came with.
  final Map<String, BoundTexture> textures;

  /// [member] of [block], or null if the engine did not write it.
  ///
  /// Null rather than an error: a shader here plays the part of a compiled one,
  /// and a compiled shader that reads a member nobody wrote gets zeros. Making
  /// this throw would hold Dart shaders to a stricter rule than the GLSL ones
  /// they stand in for.
  Float32List? read(String block, String member) {
    final found = _found;
    if (found == null) return blocks[block]?[member];
    final known = found.lookup(block, member);
    if (known == null) return found.add(block, member, blocks);
    return identical(known, _Found.absent) ? null : known;
  }

  /// [member] of [block] as a vector, or [fallback].
  Vector4 vec4(String block, String member, Vector4 fallback, {int at = 0}) {
    final data = read(block, member);
    if (data == null || data.length < at * 4 + 4) return fallback;
    return Vector4(
      data[at * 4],
      data[at * 4 + 1],
      data[at * 4 + 2],
      data[at * 4 + 3],
    );
  }

  /// [member] of [block] as a matrix, or the identity.
  Matrix4 mat4(String block, String member, {int at = 0}) {
    final data = read(block, member);
    if (data == null || data.length < at * 16 + 16) return Matrix4.identity();
    return Matrix4.fromList(
      List<double>.generate(16, (i) => data[at * 16 + i]),
    );
  }
}

/// What [ShaderBindings.read] has found during one draw, by the identity of
/// the two names asked with.
///
/// Identity rather than equality because every name a stage asks for is a
/// literal, and literals are canonical: the same call site hands the same
/// string object every time, so a pointer comparison is the whole test. A
/// name built at run time would simply miss and be looked up in the map as
/// before; the table stops growing at [_capacity], so a stage that did that
/// could not make it grow without bound either.
final class _Found {
  /// Slots in the table, a power of two; it is never filled past half, so a
  /// probe always ends at an empty slot.
  static const int _slots = 128;
  static const int _capacity = _slots ~/ 2;

  final List<String?> _blocks = List<String?>.filled(_slots, null);
  final List<String?> _members = List<String?>.filled(_slots, null);

  /// What each pair read: a member's floats, or [absent] for a member
  /// nobody wrote, which has to be remembered too — the fallback path of a
  /// stage reads it on every fragment.
  final List<Float32List?> _values = List<Float32List?>.filled(_slots, null);
  int _count = 0;

  /// Stands for "nobody wrote this member", so that null can mean "not asked
  /// yet".
  static final Float32List absent = Float32List(0);

  static int _slot(String block, String member) =>
      (member.hashCode + 31 * block.hashCode) & (_slots - 1);

  /// The remembered answer, or null when this pair has not been asked yet.
  /// A member nobody wrote comes back as [absent], never as null.
  Float32List? lookup(String block, String member) {
    var i = _slot(block, member);
    while (true) {
      final there = _members[i];
      if (there == null) return null;
      if (identical(there, member) && identical(_blocks[i], block)) {
        return _values[i];
      }
      i = (i + 1) & (_slots - 1);
    }
  }

  Float32List? add(
    String block,
    String member,
    Map<String, Map<String, Float32List>> blocks,
  ) {
    final value = blocks[block]?[member];
    if (_count < _capacity) {
      var i = _slot(block, member);
      while (_members[i] != null) {
        i = (i + 1) & (_slots - 1);
      }
      _blocks[i] = block;
      _members[i] = member;
      _values[i] = value ?? absent;
      _count++;
    }
    return value;
  }
}
