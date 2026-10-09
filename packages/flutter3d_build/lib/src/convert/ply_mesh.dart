/// A PLY file read as a mesh: the scanner's and the point-cloud tool's
/// format, ASCII or binary, with faces.
///
/// A PLY whose header names `f_dc_0` is a Gaussian splat capture instead,
/// and goes to `convertSplat`; this is every other PLY.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:vector_math/vector_math.dart';

import '../build_exceptions.dart';
import 'polygon_mesh.dart';

/// One property of a PLY element: a scalar, or a list with a count type.
final class _PlyProperty {
  const _PlyProperty(this.name, this.type, {this.countType});

  final String name;
  final String type;
  final String? countType;

  bool get isList => countType != null;
}

final class _PlyElement {
  _PlyElement(this.name, this.count);

  final String name;
  final int count;
  final List<_PlyProperty> properties = <_PlyProperty>[];
}

/// Whether [bytes] are a PLY whose vertices carry a fitted Gaussian.
bool isSplatPly(Uint8List bytes) {
  final head = latin1.decode(
    bytes.length > 4096 ? bytes.sublist(0, 4096) : bytes,
  );
  final end = head.indexOf('end_header');
  return head.substring(0, end < 0 ? head.length : end).contains('f_dc_0');
}

/// Reads [bytes] as a PLY mesh. [warnings] hears what was not read.
///
/// Reads `x y z`, `nx ny nz`, `red green blue [alpha]` (bytes or floats),
/// and `u v`, `s t` or `texture_u texture_v`; faces from
/// `vertex_indices` or `vertex_index`. Every other element and property is
/// skipped, by its size, and named in [warnings]. A file with no faces is a
/// point cloud and is refused: the engine draws it as a splat capture or
/// not at all.
ModelDocument readPlyMesh(Uint8List bytes, {List<String>? warnings}) {
  final notes = warnings ?? <String>[];
  final headerEnd = _indexOf(bytes, 'end_header');
  if (headerEnd < 0 || !_startsWith(bytes, 'ply')) {
    throw const SourceFormatException(
      'not a PLY file: no "ply" … "end_header"',
    );
  }
  var bodyStart = headerEnd + 'end_header'.length;
  if (bodyStart < bytes.length && bytes[bodyStart] == 0x0D) bodyStart++;
  if (bodyStart < bytes.length && bytes[bodyStart] == 0x0A) bodyStart++;
  final header = latin1.decode(bytes.sublist(0, headerEnd));

  var format = '';
  final elements = <_PlyElement>[];
  for (final raw in const LineSplitter().convert(header)) {
    final words = raw.trim().split(RegExp(r'\s+'));
    if (words.isEmpty || words.first.isEmpty) continue;
    switch (words.first) {
      case 'format':
        format = words.length > 1 ? words[1] : '';
      case 'element':
        if (words.length < 3) {
          throw SourceFormatException('bad element line: $raw');
        }
        elements.add(_PlyElement(words[1], int.parse(words[2])));
      case 'property':
        if (elements.isEmpty) {
          throw SourceFormatException('property before element');
        }
        if (words.length >= 5 && words[1] == 'list') {
          elements.last.properties.add(
            _PlyProperty(words[4], words[3], countType: words[2]),
          );
        } else if (words.length >= 3) {
          elements.last.properties.add(_PlyProperty(words[2], words[1]));
        }
    }
  }

  final reader = switch (format) {
    'ascii' => _AsciiReader(
      utf8.decode(bytes.sublist(bodyStart), allowMalformed: true),
    ),
    'binary_little_endian' => _BinaryReader(bytes, bodyStart, Endian.little),
    'binary_big_endian' => _BinaryReader(bytes, bodyStart, Endian.big),
    _ => throw SourceFormatException('unknown PLY format "$format"'),
  };

  final points = <Vector3>[];
  final normals = <Vector3>[];
  final colors = <Vector4>[];
  final uvs = <Vector2>[];
  final counts = <int>[];
  final indices = <int>[];
  var hasNormals = false, hasColors = false, hasUvs = false;

  for (final element in elements) {
    final names = element.properties.map((p) => p.name).toSet();
    if (element.name == 'vertex') {
      hasNormals = names.containsAll(const <String>['nx', 'ny', 'nz']);
      hasColors = names.containsAll(const <String>['red', 'green', 'blue']);
      hasUvs =
          names.containsAll(const <String>['u', 'v']) ||
          names.containsAll(const <String>['s', 't']) ||
          names.containsAll(const <String>['texture_u', 'texture_v']);
      final unknown = names.difference(const <String>{
        'x', 'y', 'z', 'nx', 'ny', 'nz', 'red', 'green', 'blue', 'alpha', //
        'u', 'v', 's', 't', 'texture_u', 'texture_v',
      });
      if (unknown.isNotEmpty) {
        notes.add(
          'vertex properties not read: ${(unknown.toList()..sort()).join(', ')}',
        );
      }
      for (var i = 0; i < element.count; i++) {
        final values = <String, double>{};
        for (final property in element.properties) {
          if (property.isList) {
            reader.skipList(property);
          } else {
            values[property.name] = reader.scalar(property.type);
          }
        }
        points.add(
          Vector3(values['x'] ?? 0.0, values['y'] ?? 0.0, values['z'] ?? 0.0),
        );
        if (hasNormals) {
          normals.add(Vector3(values['nx']!, values['ny']!, values['nz']!));
        }
        if (hasColors) {
          final byType = element.properties
              .firstWhere((p) => p.name == 'red')
              .type;
          final scale = _isInteger(byType) ? 1.0 / 255.0 : 1.0;
          colors.add(
            Vector4(
              values['red']! * scale,
              values['green']! * scale,
              values['blue']! * scale,
              (values['alpha'] ?? (scale == 1.0 ? 1.0 : 255.0)) * scale,
            ),
          );
        }
        if (hasUvs) {
          final u = values['u'] ?? values['s'] ?? values['texture_u'] ?? 0.0;
          final v = values['v'] ?? values['t'] ?? values['texture_v'] ?? 0.0;
          // PLY's v runs up the image, as OBJ's does; the engine's runs down.
          uvs.add(Vector2(u, 1.0 - v));
        }
      }
    } else if (element.name == 'face') {
      for (var i = 0; i < element.count; i++) {
        for (final property in element.properties) {
          if (property.isList &&
              (property.name == 'vertex_indices' ||
                  property.name == 'vertex_index')) {
            final list = reader.list(property);
            counts.add(list.length);
            indices.addAll(list.map((double d) => d.toInt()));
          } else if (property.isList) {
            reader.skipList(property);
          } else {
            reader.scalar(property.type);
          }
        }
      }
      final others = element.properties
          .where((p) => p.name != 'vertex_indices' && p.name != 'vertex_index')
          .map((p) => p.name)
          .toList();
      if (others.isNotEmpty) {
        notes.add('face properties not read: ${others.join(', ')}');
      }
    } else {
      notes.add('element "${element.name}" (${element.count}) not read');
      for (var i = 0; i < element.count; i++) {
        for (final property in element.properties) {
          if (property.isList) {
            reader.skipList(property);
          } else {
            reader.scalar(property.type);
          }
        }
      }
    }
  }

  if (counts.isEmpty) {
    throw const SourceFormatException(
      'a PLY with no faces is a point cloud; only meshes and Gaussian splat '
      'captures (with f_dc_0) are converted',
    );
  }

  final mesh = PolygonMesh(
    points: points,
    counts: counts,
    indices: indices,
    normals: hasNormals
        ? PolygonAttribute<Vector3>(normals, AttributeRate.point)
        : null,
    uvs: hasUvs ? PolygonAttribute<Vector2>(uvs, AttributeRate.point) : null,
    colors: hasColors
        ? PolygonAttribute<Vector4>(colors, AttributeRate.point)
        : null,
  ).build();

  return PlainModelDocument(
    surfaces: <ModelSurface>[
      ModelSurface(
        mesh: mesh,
        materialIndex: 0,
        authoredAttributes: <String>{
          'position',
          if (hasNormals) 'normal',
          if (hasUvs) 'texcoord',
          if (hasColors) 'color',
        },
      ),
    ],
    materials: <SurfaceMaterial>[SurfaceMaterial(name: 'ply', roughness: 0.8)],
    nodes: <ModelNode>[
      ModelNode(name: 'ply', surfaces: <int>[0]),
    ],
    warnings: notes,
  );
}

bool _isInteger(String type) => const <String>{
  'char', 'uchar', 'short', 'ushort', 'int', 'uint', //
  'int8', 'uint8', 'int16', 'uint16', 'int32', 'uint32',
}.contains(type);

int _indexOf(Uint8List bytes, String text) {
  final pattern = latin1.encode(text);
  final limit = bytes.length < 65536 ? bytes.length : 65536;
  outer:
  for (var i = 0; i + pattern.length <= limit; i++) {
    for (var j = 0; j < pattern.length; j++) {
      if (bytes[i + j] != pattern[j]) continue outer;
    }
    return i;
  }
  return -1;
}

bool _startsWith(Uint8List bytes, String text) {
  if (bytes.length < text.length) return false;
  for (var i = 0; i < text.length; i++) {
    if (bytes[i] != text.codeUnitAt(i)) return false;
  }
  return true;
}

abstract interface class _Reader {
  double scalar(String type);
  List<double> list(_PlyProperty property);
  void skipList(_PlyProperty property);
}

final class _AsciiReader implements _Reader {
  _AsciiReader(String body)
    : _tokens = body.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

  final List<String> _tokens;
  int _at = 0;

  double _next() {
    if (_at >= _tokens.length) {
      throw const SourceFormatException('PLY body ends early');
    }
    return double.parse(_tokens[_at++]);
  }

  @override
  double scalar(String type) => _next();

  @override
  List<double> list(_PlyProperty property) {
    final n = _next().toInt();
    return <double>[for (var i = 0; i < n; i++) _next()];
  }

  @override
  void skipList(_PlyProperty property) => list(property);
}

final class _BinaryReader implements _Reader {
  _BinaryReader(Uint8List bytes, this._at, this._endian)
    : _view = ByteData.sublistView(bytes);

  final ByteData _view;
  final Endian _endian;
  int _at;

  @override
  double scalar(String type) {
    final size = _sizeOf(type);
    if (_at + size > _view.lengthInBytes) {
      throw const SourceFormatException('PLY body ends early');
    }
    final value = switch (type) {
      'char' || 'int8' => _view.getInt8(_at).toDouble(),
      'uchar' || 'uint8' => _view.getUint8(_at).toDouble(),
      'short' || 'int16' => _view.getInt16(_at, _endian).toDouble(),
      'ushort' || 'uint16' => _view.getUint16(_at, _endian).toDouble(),
      'int' || 'int32' => _view.getInt32(_at, _endian).toDouble(),
      'uint' || 'uint32' => _view.getUint32(_at, _endian).toDouble(),
      'float' || 'float32' => _view.getFloat32(_at, _endian),
      'double' || 'float64' => _view.getFloat64(_at, _endian),
      _ => throw SourceFormatException('unknown PLY type "$type"'),
    };
    _at += size;
    return value;
  }

  @override
  List<double> list(_PlyProperty property) {
    final n = scalar(property.countType!).toInt();
    return <double>[for (var i = 0; i < n; i++) scalar(property.type)];
  }

  @override
  void skipList(_PlyProperty property) {
    final n = scalar(property.countType!).toInt();
    _at += n * _sizeOf(property.type);
  }

  static int _sizeOf(String type) => switch (type) {
    'char' || 'uchar' || 'int8' || 'uint8' => 1,
    'short' || 'ushort' || 'int16' || 'uint16' => 2,
    'int' || 'uint' || 'int32' || 'uint32' || 'float' || 'float32' => 4,
    'double' || 'float64' => 8,
    _ => throw SourceFormatException('unknown PLY type "$type"'),
  };
}
