import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show LinearColor;
import 'package:vector_math/vector_math.dart';

import '../../geometry/polyline_shape.dart';
import '../geometry/device_mesh.dart';
import '../render/material.dart';
import 'mesh_node.dart';

/// A line that grows a point at a time: a missile's trail, a path drawn as
/// the player walks it, a pen on a whiteboard.
///
/// **One mesh, written in place.** A line rebuilt and uploaded every time
/// it grew was a buffer made and thrown away every frame. This one holds
/// room for [capacity] points from the start and rewrites its vertices
/// where they are; points it has not reached yet sit a hair past the last
/// one, as segments too short to see. Full, it lets go of its oldest point
/// for each new one, so a trail follows its missile at a fixed length.
///
/// Drawn with a `RenderMaterial.polyline`, [width] pixels across.
final class LineStripNode extends MeshNode {
  LineStripNode._(
    this._device,
    DeviceMesh mesh,
    RenderMaterial material,
    this.capacity,
    this.width,
    this.color, {
    super.name,
  }) : super(mesh, material);

  /// A strip with room for [capacity] points, on [device].
  factory LineStripNode({
    required GraphicsDevice device,
    required RenderMaterial material,
    int capacity = 64,
    double width = 3.0,
    LinearColor color = LinearColor.white,
    String? name,
  }) {
    if (capacity < 2) throw ArgumentError('A line of $capacity points.');
    final tint = color;
    final data = buildPolyline(
      _padded(const <Vector3>[], capacity),
      width: width,
      color: tint,
    );
    return LineStripNode._(
      device,
      DeviceMesh.upload(device, data),
      material,
      capacity,
      width,
      tint,
      name: name,
    );
  }

  final GraphicsDevice _device;

  /// How many points the strip can hold before it lets go of the oldest.
  final int capacity;

  /// How many pixels across it is drawn.
  final double width;

  /// Its colour, linear.
  final LinearColor color;

  final List<Vector3> _points = <Vector3>[];

  /// The points drawn, oldest first.
  List<Vector3> get points => List<Vector3>.unmodifiable(_points);

  /// How many points are drawn.
  int get count => _points.length;

  /// Adds [point] at the new end, letting go of the oldest when full.
  void append(Vector3 point) {
    if (_points.length == capacity) _points.removeAt(0);
    _points.add(point.clone());
    _write();
  }

  /// Takes every point away.
  void clear() {
    _points.clear();
    _write();
  }

  void _write() {
    final data = buildPolyline(
      _padded(_points, capacity),
      width: width,
      color: color,
    );
    (mesh as DeviceMesh).overwriteVertices(
      _device,
      0,
      ByteData.sublistView(data.vertices),
    );
    markBoundsDirty();
  }

  final Aabb3 _bounds = Aabb3();

  /// Round the points drawn, not the mesh as it was uploaded: the mesh's own
  /// box is the empty line it started as, and a trail culled against that
  /// vanished once its missile had flown out of it.
  @override
  Aabb3 get localBounds {
    if (_points.isEmpty) {
      _bounds.min.setZero();
      _bounds.max.setZero();
      return _bounds;
    }
    _bounds.min.setFrom(_points.first);
    _bounds.max.setFrom(_points.first);
    for (final p in _points) {
      Vector3.min(_bounds.min, p, _bounds.min);
      Vector3.max(_bounds.max, p, _bounds.max);
    }
    return _bounds;
  }

  /// [points] made up to [capacity]: the rest a hair past the end along the
  /// last direction, so no vertex has a zero direction to be widened across.
  static List<Vector3> _padded(List<Vector3> points, int capacity) {
    final out = <Vector3>[for (final p in points) p.clone()];
    final Vector3 last = out.isEmpty ? Vector3.zero() : out.last;
    final Vector3 step = out.length >= 2
        ? (out.last - out[out.length - 2])
        : Vector3(0.0, 0.0, -1.0);
    if (step.length2 < 1e-12) step.setValues(0.0, 0.0, -1.0);
    step
      ..normalize()
      ..scale(1e-4);
    var k = 1;
    while (out.length < capacity) {
      out.add(last + step * k.toDouble());
      k++;
    }
    return out;
  }
}
