/// A material's parameters by typed key or by name, against the schema its
/// `.f3dmat` declares — what `RenderMaterial.parameters` holds, and what a
/// `MeshNode` overrides for itself.
library;

import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show Flutter3dFormatException, LinearColor, Quantity, Unit;
import 'package:vector_math/vector_math.dart';

import '../../formats/material_language/material_ast.dart' show MaterialProgram;
import '../../formats/material_language/material_bundle.dart'
    show BundledMaterials;

/// A parameter name, a value or a unit a material does not take: a name it
/// does not declare, a value of another width, a `param` folded into the
/// shader when it was compiled, or a value [MaterialParameters.setNamed]
/// cannot read as numbers.
final class MaterialParameterException extends Flutter3dFormatException {
  const MaterialParameterException(this.message);

  @override
  final String message;

  @override
  String toString() => 'MaterialParameterException: $message';
}

/// How a Dart value of [T] is laid out as the floats a uniform block reads.
///
/// **An open set**: the engine's own are the constants here, and a plugin
/// whose shader reads something else extends this with its own layout.
abstract base class ParameterType<T extends Object> {
  const ParameterType(this.name, this.components);

  /// The type's name, as a schema or a tool writes it: `float`, `vec3`,
  /// `color`.
  final String name;

  /// How many floats a value takes.
  final int components;

  /// [value] as [components] floats, written into [out] from index 0.
  void write(T value, Float32List out);

  /// The value [floats] hold, read from index 0.
  T read(Float32List floats);

  /// One number: `float`.
  static const ParameterType<double> float = _FloatType();

  /// Two numbers, as a [Vector2]: `vec2`.
  static const ParameterType<Vector2> vec2 = _Vector2Type();

  /// Three numbers, as a [Vector3]: `vec3`.
  static const ParameterType<Vector3> vec3 = _Vector3Type();

  /// Four numbers, as a [Vector4]: `vec4`.
  static const ParameterType<Vector4> vec4 = _Vector4Type();

  /// A linear colour's red, green and blue: a `vec3` the shader reads as a
  /// colour. Alpha is not written, and reads back as one.
  static const ParameterType<LinearColor> color = _ColorType();

  /// A linear colour with its alpha: a `vec4`.
  static const ParameterType<LinearColor> colorWithAlpha = _ColorAlphaType();

  @override
  String toString() => 'ParameterType.$name';
}

final class _FloatType extends ParameterType<double> {
  const _FloatType() : super('float', 1);

  @override
  void write(double value, Float32List out) => out[0] = value;

  @override
  double read(Float32List floats) => floats[0];
}

final class _Vector2Type extends ParameterType<Vector2> {
  const _Vector2Type() : super('vec2', 2);

  @override
  void write(Vector2 value, Float32List out) => out
    ..[0] = value.x
    ..[1] = value.y;

  @override
  Vector2 read(Float32List floats) => Vector2(floats[0], floats[1]);
}

final class _Vector3Type extends ParameterType<Vector3> {
  const _Vector3Type() : super('vec3', 3);

  @override
  void write(Vector3 value, Float32List out) => out
    ..[0] = value.x
    ..[1] = value.y
    ..[2] = value.z;

  @override
  Vector3 read(Float32List floats) => Vector3(floats[0], floats[1], floats[2]);
}

final class _Vector4Type extends ParameterType<Vector4> {
  const _Vector4Type() : super('vec4', 4);

  @override
  void write(Vector4 value, Float32List out) => out
    ..[0] = value.x
    ..[1] = value.y
    ..[2] = value.z
    ..[3] = value.w;

  @override
  Vector4 read(Float32List floats) =>
      Vector4(floats[0], floats[1], floats[2], floats[3]);
}

final class _ColorType extends ParameterType<LinearColor> {
  const _ColorType() : super('color', 3);

  @override
  void write(LinearColor value, Float32List out) => out
    ..[0] = value.r
    ..[1] = value.g
    ..[2] = value.b;

  @override
  LinearColor read(Float32List floats) =>
      LinearColor(floats[0], floats[1], floats[2]);
}

final class _ColorAlphaType extends ParameterType<LinearColor> {
  const _ColorAlphaType() : super('colorWithAlpha', 4);

  @override
  void write(LinearColor value, Float32List out) => out
    ..[0] = value.r
    ..[1] = value.g
    ..[2] = value.b
    ..[3] = value.a;

  @override
  LinearColor read(Float32List floats) =>
      LinearColor(floats[0], floats[1], floats[2], floats[3]);
}

/// One parameter of a material, named as its `.f3dmat` names it, with the
/// Dart type its value is and the unit that value is in.
///
/// **Typed, so a wrong value is a compile error rather than a dark frame.**
/// A generated material library declares one constant per parameter its
/// source declares:
///
/// ```dart
/// abstract final class WaterParameters {
///   static const waveHeight =
///       ParameterKey<double>('waveHeight', ParameterType.float, unit: Unit.meter);
///   static const tint = ParameterKey<LinearColor>('tint', ParameterType.color);
/// }
///
/// parameters.set(WaterParameters.waveHeight, 0.4);
/// ```
final class ParameterKey<T extends Object> {
  const ParameterKey(this.name, this.type, {this.unit});

  /// The parameter's name in the material's source and in the uniform
  /// block — its wire name.
  final String name;

  /// How a value is laid out.
  final ParameterType<T> type;

  /// The unit a value set or read through this key is in, or null for the
  /// one the material declares. Where both are known and differ, the value
  /// is converted on the way in and out: a key in centimetres sets a
  /// parameter declared in metres.
  final Unit? unit;

  @override
  bool operator ==(Object other) =>
      other is ParameterKey<T> &&
      other.name == name &&
      other.type == type &&
      other.unit == unit;

  @override
  int get hashCode => Object.hash(name, type, unit);

  @override
  String toString() => 'ParameterKey<$T>($name, ${type.name})';
}

/// One parameter a material declares: its [name], how many floats it is,
/// its default, whether a draw can set it, and the unit its numbers are in
/// when the source says.
final class ParameterDeclaration {
  const ParameterDeclaration(
    this.name, {
    required this.components,
    required this.defaultValue,
    this.isUniform = true,
    this.unit,
  });

  /// The name in the source and in the uniform block.
  final String name;

  /// How many floats a value takes.
  final int components;

  /// The value a material that sets none is drawn with.
  final List<double> defaultValue;

  /// Whether a draw can set it: a `uniform`, read from the block on every
  /// draw. False for a `param`, which a variant folds into the shader when
  /// it is compiled.
  final bool isUniform;

  /// The unit its numbers are in, or null where the source does not say.
  final Unit? unit;

  @override
  String toString() =>
      'ParameterDeclaration($name, $components, '
      '${isUniform ? 'uniform' : 'param'}${unit == null ? '' : ', $unit'})';
}

/// What a material declares it takes, in the order its source declares it.
final class MaterialParameterSchema {
  MaterialParameterSchema(Iterable<ParameterDeclaration> declarations)
    : _byName = LinkedHashMap<String, ParameterDeclaration>.fromIterable(
        declarations,
        key: (Object? d) => (d! as ParameterDeclaration).name,
      );

  /// The schema of a parsed `.f3dmat`: each `uniform` and `param` it
  /// declares, with its width and default. A source says no unit yet, so
  /// none is filled in.
  factory MaterialParameterSchema.fromProgram(MaterialProgram program) =>
      MaterialParameterSchema(<ParameterDeclaration>[
        for (final parameter in program.parameters)
          ParameterDeclaration(
            parameter.name,
            components: parameter.type.components,
            defaultValue: List<double>.unmodifiable(parameter.defaultValue),
            isUniform: parameter.uniform,
          ),
      ]);

  final Map<String, ParameterDeclaration> _byName;

  /// Every declared name, in source order.
  Iterable<String> get names => _byName.keys;

  /// Every declaration, in source order.
  Iterable<ParameterDeclaration> get declarations => _byName.values;

  /// The declaration called [name], or null when there is none.
  ParameterDeclaration? operator [](String name) => _byName[name];
}

/// The schemas of a bundle's materials.
extension BundledMaterialSchemas on BundledMaterials {
  /// What material [name] lets a draw set: each `uniform` its source
  /// declares, its width and its default, as the bundle carries them — the
  /// schema a [MaterialParameters] over `material(name).parameters` checks
  /// against. A bundle keeps no `param`, which is folded into its stages.
  /// Throws an [ArgumentError] naming the materials the bundle has.
  MaterialParameterSchema schema(String name) {
    final bindings =
        stages[name] ??
        (throw ArgumentError.value(
          name,
          'name',
          'bundle "${bundle.name}" has the materials '
              '${lighting.keys.join(', ')}',
        ));
    return MaterialParameterSchema(<ParameterDeclaration>[
      for (final MapEntry(:key, :value) in bindings.uniforms.entries)
        ParameterDeclaration(
          key,
          components: value.length,
          defaultValue: List<double>.unmodifiable(value),
        ),
    ]);
  }
}

/// A material's parameter values: set and read by [ParameterKey] from code
/// and by name from data, checked against a [schema] when there is one, and
/// held as the floats the uniform block is filled from.
///
/// **What `RenderMaterial.parameters` holds, given types.** A
/// [MaterialParameters.over] that map edits what the encoder binds; a
/// `MeshNode.parameters` of its own overrides the material's for that node
/// alone, which is how a hundred rocks share one material and one rock
/// glows.
final class MaterialParameters {
  /// Values of their own, starting at [schema]'s defaults for every
  /// parameter a draw can set.
  MaterialParameters({this.schema}) : _values = <String, Float32List>{} {
    for (final declared in schema?.declarations ?? <ParameterDeclaration>[]) {
      if (!declared.isUniform) continue;
      _values[declared.name] = Float32List.fromList(declared.defaultValue);
    }
  }

  /// Over [values], which every set writes into and every read reads: a
  /// `RenderMaterial`'s own map, typed.
  MaterialParameters.over(Map<String, Float32List> values, {this.schema})
    : _values = values;

  /// What the material declares, or null to take any name and width.
  final MaterialParameterSchema? schema;

  final Map<String, Float32List> _values;

  /// The values, by name, as the uniform block is filled from them.
  Map<String, Float32List> get uniforms =>
      UnmodifiableMapView<String, Float32List>(_values);

  /// Bumped by every change, for a caller that caches what it built from
  /// the values.
  int get version => _version;
  int _version = 0;

  /// Whether nothing is set.
  bool get isEmpty => _values.isEmpty;

  /// Sets [key] to [value], in [key]'s unit.
  ///
  /// Throws a [MaterialParameterException] where [schema] says the material
  /// does not declare [key], declares another width, or folds it into the
  /// shader (`param`); a `UnitMismatchException` where the declared unit
  /// measures something else than [key]'s.
  void set<T extends Object>(ParameterKey<T> key, T value) {
    final declared = _declared(key.name, key.type.components);
    final floats = Float32List(key.type.components);
    key.type.write(value, floats);
    _convert(floats, from: key.unit, to: declared?.unit);
    _put(key.name, floats);
  }

  /// [key]'s value in [key]'s unit, or null when nothing is set.
  T? get<T extends Object>(ParameterKey<T> key) {
    final held = _values[key.name];
    if (held == null || held.length < key.type.components) return null;
    final floats = Float32List.fromList(held);
    _convert(floats, from: schema?[key.name]?.unit, to: key.unit);
    return key.type.read(floats);
  }

  /// Sets the parameter called [name] from data: a number, a list of
  /// numbers, a `Vector2`/`Vector3`/`Vector4`, a [LinearColor] (as wide as
  /// the declaration, red-green-blue or with alpha), or a [Quantity],
  /// converted into the declared unit.
  ///
  /// Throws a [MaterialParameterException] for a name [schema] does not
  /// declare, a value of another width, a `param`, or a value that is not
  /// numbers; a `UnitMismatchException` for a quantity of another dimension.
  void setNamed(String name, Object value) {
    final declared = schema?[name];
    final width = declared?.components;
    final Float32List floats;
    switch (value) {
      case num():
        floats = Float32List.fromList(<double>[value.toDouble()]);
      // Where the material says no unit, the number is taken as it is.
      case Quantity():
        final into = declared?.unit;
        floats = Float32List.fromList(<double>[
          if (into == null) value.value else value.valueIn(into),
        ]);
      case Vector2():
        floats = Float32List.fromList(<double>[value.x, value.y]);
      case Vector3():
        floats = Float32List.fromList(<double>[value.x, value.y, value.z]);
      case Vector4():
        floats = Float32List.fromList(<double>[
          value.x,
          value.y,
          value.z,
          value.w,
        ]);
      case LinearColor():
        floats = Float32List.fromList(<double>[
          value.r,
          value.g,
          value.b,
          if (width != 3) value.a,
        ]);
      case List<Object?>() when value.every((Object? v) => v is num):
        floats = Float32List.fromList(<double>[
          for (final v in value) (v! as num).toDouble(),
        ]);
      default:
        throw MaterialParameterException(
          'the parameter "$name" takes numbers, and was handed '
          '${value.runtimeType}',
        );
    }
    _declared(name, floats.length);
    _put(name, floats);
  }

  /// The floats the parameter called [name] holds, or null when nothing
  /// is set. A copy.
  Float32List? named(String name) {
    final held = _values[name];
    return held == null ? null : Float32List.fromList(held);
  }

  /// Takes the parameter called [name] back to nothing set: the material's
  /// own value for a node's override, the shader's default otherwise.
  void remove(String name) {
    if (_values.remove(name) != null) _version++;
  }

  void _put(String name, Float32List floats) {
    _values[name] = floats;
    _version++;
  }

  /// [name]'s declaration, after checking a value of [components] floats
  /// may be set to it; null without a schema.
  ParameterDeclaration? _declared(String name, int components) {
    final known = schema;
    if (known == null) return null;
    final declared = known[name];
    if (declared == null) {
      throw MaterialParameterException(
        'the material declares no parameter "$name"; it declares '
        '${known.names.isEmpty ? 'none' : known.names.join(', ')}',
      );
    }
    if (!declared.isUniform) {
      throw MaterialParameterException(
        '"$name" is a param, folded into the shader when it was compiled; a '
        'draw cannot set it. Declare it uniform to set it on a draw, or '
        'compile a variant with the value',
      );
    }
    if (declared.components != components) {
      throw MaterialParameterException(
        '"$name" is ${declared.components} float(s), and was handed '
        '$components',
      );
    }
    return declared;
  }

  /// [floats] from unit [from] into unit [to], each component, where both
  /// are known.
  static void _convert(Float32List floats, {Unit? from, Unit? to}) {
    if (from == null || to == null || from == to) return;
    for (var i = 0; i < floats.length; i++) {
      floats[i] = Quantity(floats[i], from).valueIn(to);
    }
  }

  @override
  String toString() => 'MaterialParameters(${_values.keys.join(', ')})';
}
