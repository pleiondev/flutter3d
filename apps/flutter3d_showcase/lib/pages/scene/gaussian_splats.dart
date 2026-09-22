/// A small Gaussian cloud, written to a binary PLY and read back the way a
/// capture would arrive.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

typedef _SplatRow = ({
  Vector3 position,
  Vector3 colour,
  double opacity,
  double scale,
});

final class GaussianSplatsDemo extends ShowcaseDemo {
  late final SplatCloud _cloud;
  late final SplatContributor _contributor;

  static const int _count = 35;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 5.0
      ..pitch = 0.18
      ..yaw = 0.4;
  }

  @override
  Scene build(DemoContext context) {
    // #region rows
    final List<_SplatRow> rows = <_SplatRow>[
      for (var i = 0; i < _count; i++)
        (
          position: Vector3(
            (i % 7 - 3) * 0.5,
            0.4 * math.sin(i * 0.6),
            (i ~/ 7 - 2) * 0.5,
          ),
          colour: Vector3(
            0.3 + 0.5 * (i / _count),
            0.4,
            0.9 - 0.5 * (i / _count),
          ),
          opacity: 0.85,
          scale: 0.16,
        ),
    ];
    // #endregion rows

    // #region decode
    final Uint8List bytes = _splatPlyBytes(rows);
    _cloud = parseSplatPly(bytes);
    // #endregion decode

    // #region contributor
    _contributor = context.renderer.addContributor(SplatContributor(_cloud));
    // #endregion contributor

    final Scene scene = Scene()
      ..ambientColor = Vector3(0.4, 0.46, 0.6)
      ..ambientIntensity = 0.24
      ..add(
        LightNode(name: 'key', intensity: 1.2)
          ..setLocalForward(Vector3(-0.4, -0.7, -0.5)),
      );
    return scene;
  }

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    final Int32List order = _cloud.sortedBackToFront(
      Vector3(0.0, 0.0, -5.0),
      Vector3(0.0, 0.0, 1.0),
    );
    final Set<int> seen = order.toSet();
    if (_cloud.count != _count ||
        seen.length != _count ||
        !_contributor.isActive ||
        frame.drawCalls < 1) {
      throw StateError('the splat cloud was not decoded and drawn');
    }
    // #endregion check
  }
}

// #region ply
/// A binary PLY holding [rows], in exactly the properties `parseSplatPly`
/// requires: `x y z`, `f_dc_0..2`, `opacity`, `scale_0..2`, `rot_0..3`.
Uint8List _splatPlyBytes(List<_SplatRow> rows) {
  const List<String> properties = <String>[
    'x',
    'y',
    'z',
    'f_dc_0',
    'f_dc_1',
    'f_dc_2',
    'opacity',
    'scale_0',
    'scale_1',
    'scale_2',
    'rot_0',
    'rot_1',
    'rot_2',
    'rot_3',
  ];
  final StringBuffer header = StringBuffer()
    ..writeln('ply')
    ..writeln('format binary_little_endian 1.0')
    ..writeln('element vertex ${rows.length}');
  for (final String name in properties) {
    header.writeln('property float $name');
  }
  header.writeln('end_header');
  final List<int> headerBytes = ascii.encode(header.toString());

  final ByteData body = ByteData(rows.length * properties.length * 4);
  var offset = 0;
  // The inverse of `splatChannel` and `splatOpacity`: a readable 0..1 colour
  // and probability, converted back to the coefficient and the logit the
  // file stores.
  double coefficientFor(double channel01) => (channel01 - 0.5) / kSplatShC0;
  double logitFor(double probability) =>
      math.log(probability / (1.0 - probability));
  void writeFloat(double value) {
    body.setFloat32(offset, value, Endian.little);
    offset += 4;
  }

  for (final _SplatRow row in rows) {
    writeFloat(row.position.x);
    writeFloat(row.position.y);
    writeFloat(row.position.z);
    writeFloat(coefficientFor(row.colour.x));
    writeFloat(coefficientFor(row.colour.y));
    writeFloat(coefficientFor(row.colour.z));
    writeFloat(logitFor(row.opacity));
    writeFloat(math.log(row.scale));
    writeFloat(math.log(row.scale));
    writeFloat(math.log(row.scale));
    // rot_0..3 is w, x, y, z in the file's own order; the identity rotation
    // leaves every ellipsoid axis-aligned.
    writeFloat(1.0);
    writeFloat(0.0);
    writeFloat(0.0);
    writeFloat(0.0);
  }

  final Uint8List result = Uint8List(headerBytes.length + body.lengthInBytes);
  result.setRange(0, headerBytes.length, headerBytes);
  result.setRange(headerBytes.length, result.length, body.buffer.asUint8List());
  return result;
}
// #endregion ply
