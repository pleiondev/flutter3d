/// A field's values: [FieldStorage], and the host memory every machine has,
/// [HostField].
library;

import 'dart:typed_data';

import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show SnapshotPart;

import 'field.dart';

/// Where one field's values are held right now: host memory here, a
/// device's buffer or 3D texture in the renderer's core.
///
/// **Extended by the engine, read by everyone.** `base`, so a residence a
/// later minor adds is one more subclass, and a member added here arrives
/// with a default.
abstract base class FieldStorage {
  const FieldStorage();

  /// The field these are the values of.
  FieldDeclaration get declaration;

  /// Where they are held.
  FieldResidence get residence;
}

/// A field held in host memory: one `Float32List`, the cells in x, then y,
/// then z order, each cell's components side by side.
///
/// **What a simulation subsystem steps.** Float32, as the bodies are, and
/// read and written with nothing but `+`, `-`, `*` and `/`, so a field
/// stepped from one state on two machines holds the same bits on both: its
/// [snapshotPart] puts it in the loop's snapshots, its digest among them,
/// and a rollback or a replay puts it back.
final class HostField extends FieldStorage {
  /// The field [declaration] describes, every value nought.
  HostField(this.declaration)
    : values = Float32List(declaration.grid.valueCount),
      _writable = true;

  /// The field [declaration] describes holding [values], which must be
  /// [FieldGrid.valueCount] long. They are the field's own from here on,
  /// not a copy.
  HostField.of(this.declaration, this.values) : _writable = true {
    if (values.length != declaration.grid.valueCount) {
      throw ArgumentError.value(
        values.length,
        'values',
        'field "${declaration.id}" is ${declaration.grid} and holds '
            '${declaration.grid.valueCount} values',
      );
    }
  }

  HostField._view(this.declaration, this.values) : _writable = false;

  @override
  final FieldDeclaration declaration;

  @override
  FieldResidence get residence => FieldResidence.host;

  /// Every value, the cells in x, then y, then z order.
  final Float32List values;

  final bool _writable;

  /// Whether this one may be written: false for a [readOnly] view, whose
  /// [values] throw on a write.
  bool get isWritable => _writable;

  /// The same values, seen through a view that refuses a write: what a
  /// subsystem that only reads the field is handed.
  HostField get readOnly => _writable
      ? HostField._view(declaration, values.asUnmodifiableView())
      : this;

  /// A copy that shares nothing with this one.
  HostField copy() => HostField.of(declaration, Float32List.fromList(values));

  /// Takes [other]'s values, which must be of a grid this size.
  void copyFrom(HostField other) {
    if (other.values.length != values.length) {
      throw ArgumentError.value(
        other.declaration.grid,
        'other',
        'is not the size of field "${declaration.id}" (${declaration.grid})',
      );
    }
    values.setAll(0, other.values);
  }

  /// Where cell ([x], [y], [z])'s [component] is in [values].
  int indexOf(int x, int y, int z, {int component = 0}) {
    final grid = declaration.grid;
    if (x < 0 ||
        y < 0 ||
        z < 0 ||
        x >= grid.width ||
        y >= grid.height ||
        z >= grid.depth ||
        component < 0 ||
        component >= grid.components) {
      throw RangeError(
        'cell ($x, $y, $z) component $component is outside field '
        '"${declaration.id}" ($grid)',
      );
    }
    return ((z * grid.height + y) * grid.width + x) * grid.components +
        component;
  }

  /// The value of cell ([x], [y], [z]), in the field's unit.
  double valueAt(int x, int y, int z, {int component = 0}) =>
      values[indexOf(x, y, z, component: component)];

  /// Sets cell ([x], [y], [z]) to [value], in the field's unit.
  void setValueAt(int x, int y, int z, double value, {int component = 0}) =>
      values[indexOf(x, y, z, component: component)] = value;

  /// Every value [value].
  void fill(double value) => values.fillRange(0, values.length, value);

  /// The field at [position], blended between the eight cells around it
  /// and held at the edge cells' values beyond the grid.
  double sample(WorldPosition position, {int component = 0}) {
    final at = declaration.transform.gridOf(position);
    final grid = declaration.grid;
    final (x0, fx) = _split(at.x, grid.width);
    final (y0, fy) = _split(at.y, grid.height);
    final (z0, fz) = _split(at.z, grid.depth);
    final x1 = x0 + 1 < grid.width ? x0 + 1 : x0;
    final y1 = y0 + 1 < grid.height ? y0 + 1 : y0;
    final z1 = z0 + 1 < grid.depth ? z0 + 1 : z0;
    double v(int x, int y, int z) => valueAt(x, y, z, component: component);
    double mix(double a, double b, double t) => a + (b - a) * t;
    return mix(
      mix(
        mix(v(x0, y0, z0), v(x1, y0, z0), fx),
        mix(v(x0, y1, z0), v(x1, y1, z0), fx),
        fy,
      ),
      mix(
        mix(v(x0, y0, z1), v(x1, y0, z1), fx),
        mix(v(x0, y1, z1), v(x1, y1, z1), fx),
        fy,
      ),
      fz,
    );
  }

  /// [sample] as a quantity in the field's unit.
  Quantity quantityAt(WorldPosition position, {int component = 0}) =>
      Quantity(sample(position, component: component), declaration.unit);

  /// The cell below [at] along an axis of [cells] cells, and how far past
  /// it [at] is, clamped into the grid.
  static (int, double) _split(double at, int cells) {
    if (!(at > 0)) return (0, 0.0);
    if (at >= cells - 1) return (cells - 1, 0.0);
    final below = at.floor();
    return (below, at - below);
  }

  /// A digest of the values' bits: equal values, equal digest, on every
  /// platform.
  int digest() {
    var hash = 0x811c9dc5;
    for (final word in Uint32List.sublistView(values)) {
      hash = ((hash ^ word) * 0x01000193) & 0xffffffff;
    }
    return hash;
  }

  /// The field as a part of the loop's snapshots, under its id: captured
  /// as its values, restored in place, digested by [digest]. What the loop
  /// adds for every host field the simulation writes, so a rollback, a
  /// replay and the double-step check carry it like the world.
  SnapshotPart get snapshotPart => SnapshotPart.of(
    id: 'field:${declaration.id}',
    capture: () => List<double>.of(values),
    restore: (Object? data, int version) {
      if (data is! List || data.length != values.length) {
        throw StateError(
          'the snapshot of field "${declaration.id}" is not '
          '${values.length} values',
        );
      }
      for (var i = 0; i < data.length; i++) {
        values[i] = (data[i] as num).toDouble();
      }
    },
    digest: digest,
  );

  @override
  String toString() => 'HostField(${declaration.id}, ${declaration.grid})';
}
