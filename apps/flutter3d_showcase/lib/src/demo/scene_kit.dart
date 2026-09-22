/// The few solids a page needs to show a thing that has no picture of its own:
/// a floor, a block, a ball, a sun. Kept here so a page's own source is about
/// what it demonstrates and not about building a cuboid.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

/// A box of [size] centred at [at], in one flat colour.
MeshNode blockNode(
  DemoContext context,
  String name,
  Vector3 size,
  Vector4 color, {
  Vector3? at,
}) {
  final MeshNode node = MeshNode(
    DeviceMesh.upload(context.device, CuboidShape(size: size).build()),
    Material(name: name, baseColor: color, roughness: 0.8),
    name: name,
  );
  if (at != null) node.setPositionFrom(at);
  return node;
}

/// A ball of [radius] centred at [at], in one flat colour.
MeshNode ballNode(
  DemoContext context,
  String name,
  double radius,
  Vector4 color, {
  Vector3? at,
}) {
  final MeshNode node = MeshNode(
    DeviceMesh.upload(
      context.device,
      SphereShape(segments: 24, rings: 12, radius: radius).build(),
    ),
    Material(name: name, baseColor: color, roughness: 0.6),
    name: name,
  );
  if (at != null) node.setPositionFrom(at);
  return node;
}

/// A flat floor [width] by [depth], its top face at y = 0.
MeshNode floorNode(
  DemoContext context, {
  double width = 12.0,
  double depth = 12.0,
  Vector4? color,
}) => blockNode(
  context,
  'floor',
  Vector3(width, 0.1, depth),
  color ?? Vector4(0.34, 0.38, 0.36, 1.0),
  at: Vector3(0.0, -0.05, 0.0),
);

/// A scene with a little ambient light, a sun and [nodes].
Scene sceneOf(Iterable<SceneNode> nodes) {
  final Scene scene = Scene()
    ..ambientColor = Vector3(0.5, 0.55, 0.65)
    ..ambientIntensity = 0.3;
  for (final SceneNode node in nodes) {
    scene.add(node);
  }
  return scene..add(
    LightNode(name: 'sun', intensity: 2.8)
      ..setLocalForward(Vector3(-0.35, -1.0, -0.45)),
  );
}

/// A bar that grows with a value from 0 to 1, in front of a dark backing, for
/// a number that has no picture of its own. Standing up when [vertical], and
/// otherwise lying on the floor and growing along +x, which is the one to use
/// under a camera looking down.
final class BarGauge {
  BarGauge(
    DemoContext context,
    String name,
    Vector4 color,
    Vector3 at, {
    this.height = 3.0,
    double width = 0.5,
    this.vertical = false,
  }) : _bar = blockNode(context, name, Vector3.all(1.0), color),
       _back = blockNode(
         context,
         '$name back',
         vertical
             ? Vector3(width + 0.16, height + 0.16, width * 0.6)
             : Vector3(height + 0.16, 0.06, width + 0.16),
         Vector4(0.08, 0.09, 0.1, 1.0),
         at: vertical
             ? Vector3(at.x, at.y + height / 2, at.z - width * 0.4)
             : Vector3(at.x + height / 2, at.y + 0.03, at.z),
       ),
       _width = width,
       _at = at.clone();

  /// How long the bar is at 1.
  final double height;
  final bool vertical;
  final double _width;
  final MeshNode _bar;
  final MeshNode _back;
  final Vector3 _at;

  /// Both nodes, to add to a scene.
  List<SceneNode> get nodes => <SceneNode>[_back, _bar];

  /// Sets the fill, 0 to 1.
  void set(double value) {
    final double v = value.clamp(0.0, 1.0);
    final double length = math.max(v * height, 0.001);
    if (vertical) {
      _bar
        ..setScale(_width, length, _width)
        ..setPosition(_at.x, _at.y + length / 2, _at.z);
    } else {
      _bar
        ..setScale(length, 0.1, _width)
        ..setPosition(_at.x + length / 2, _at.y + 0.08, _at.z);
    }
  }
}

/// A horizontal rail with a knob on it that slides from -1 to 1.
final class RailGauge {
  RailGauge(
    DemoContext context,
    String name,
    Vector4 color,
    Vector3 at, {
    this.length = 4.0,
  }) : _knob = blockNode(context, name, Vector3(0.35, 0.35, 0.35), color),
       _rail = blockNode(
         context,
         '$name rail',
         Vector3(length, 0.08, 0.12),
         Vector4(0.08, 0.09, 0.1, 1.0),
         at: at,
       ),
       _at = at.clone();

  final double length;
  final MeshNode _knob;
  final MeshNode _rail;
  final Vector3 _at;

  /// Both nodes, to add to a scene.
  List<SceneNode> get nodes => <SceneNode>[_rail, _knob];

  /// Puts the knob at [value], from -1 (left end) to 1 (right end).
  void set(double value) {
    _knob.setPosition(
      _at.x + value.clamp(-1.0, 1.0) * length / 2,
      _at.y + 0.2,
      _at.z,
    );
  }
}
