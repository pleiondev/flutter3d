/// Builds a GLB holding one `KHR_gaussian_splatting` primitive — `C1`.
///
/// Shared by the loader's tests, which vary one attribute at a time, and by
/// `tool/make_splat_fixture.dart`, which writes the checked-in
/// `fixtures/splat/splat_grid.glb` the render test draws.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';

/// glTF's component type codes, the four a splat file uses.
const int kGlFloat = 5126;
const int kGlUnsignedByte = 5121;
const int kGlShort = 5122;
const int kGlUnsignedShort = 5123;

/// One attribute of the primitive: its semantic, accessor type
/// (`SCALAR`/`VEC3`/`VEC4`), component type, and the values in order —
/// already scaled to integers for an integer [componentType].
typedef SplatAttribute = ({
  String semantic,
  String type,
  int componentType,
  bool normalized,
  List<num> values,
});

/// A float attribute.
SplatAttribute floats(String semantic, String type, List<double> values) => (
  semantic: semantic,
  type: type,
  componentType: kGlFloat,
  normalized: false,
  values: values,
);

/// A normalized integer attribute of [componentType].
SplatAttribute normalized(
  String semantic,
  String type,
  int componentType,
  List<int> values,
) => (
  semantic: semantic,
  type: type,
  componentType: componentType,
  normalized: true,
  values: values,
);

/// A GLB with one node drawing one mesh of one primitive carrying
/// [attributes] and the extension object [extension].
///
/// [node] is merged into the node object, for a transform. [mode] defaults to
/// POINTS, which is what the extension requires.
Uint8List splatGlb({
  required List<SplatAttribute> attributes,
  Map<String, Object?> extension = const <String, Object?>{
    'kernel': 'ellipse',
    'colorSpace': 'srgb_rec709_display',
  },
  Map<String, Object?> node = const <String, Object?>{},
  int mode = 0,
  List<String> extensionsRequired = const <String>[],
}) {
  final binary = BytesBuilder();
  final views = <Map<String, Object?>>[];
  final accessors = <Map<String, Object?>>[];
  final semantics = <String, int>{};

  for (final attribute in attributes) {
    final components = switch (attribute.type) {
      'SCALAR' => 1,
      'VEC3' => 3,
      'VEC4' => 4,
      _ => throw ArgumentError(attribute.type),
    };
    final bytes = switch (attribute.componentType) {
      kGlFloat => Float32List.fromList(<double>[
        for (final v in attribute.values) v.toDouble(),
      ]).buffer.asUint8List(),
      kGlUnsignedByte => Uint8List.fromList(<int>[
        for (final v in attribute.values) v.toInt(),
      ]),
      kGlShort => Int16List.fromList(<int>[
        for (final v in attribute.values) v.toInt(),
      ]).buffer.asUint8List(),
      kGlUnsignedShort => Uint16List.fromList(<int>[
        for (final v in attribute.values) v.toInt(),
      ]).buffer.asUint8List(),
      _ => throw ArgumentError(attribute.componentType),
    };
    final offset = binary.length;
    binary.add(bytes);
    // Every view starts on four bytes, which a float accessor needs.
    while (binary.length % 4 != 0) {
      binary.addByte(0);
    }
    views.add(<String, Object?>{
      'buffer': 0,
      'byteOffset': offset,
      'byteLength': bytes.length,
    });
    semantics[attribute.semantic] = accessors.length;
    accessors.add(<String, Object?>{
      'bufferView': views.length - 1,
      'componentType': attribute.componentType,
      'count': attribute.values.length ~/ components,
      'type': attribute.type,
      if (attribute.normalized) 'normalized': true,
      if (attribute.semantic == 'POSITION')
        ...() {
          final v = attribute.values;
          final min = <double>[
            double.infinity,
            double.infinity,
            double.infinity,
          ];
          final max = <double>[
            double.negativeInfinity,
            double.negativeInfinity,
            double.negativeInfinity,
          ];
          for (var i = 0; i < v.length; i++) {
            final c = i % 3;
            if (v[i] < min[c]) min[c] = v[i].toDouble();
            if (v[i] > max[c]) max[c] = v[i].toDouble();
          }
          return <String, Object?>{'min': min, 'max': max};
        }(),
    });
  }

  final bin = binary.toBytes();
  final json = <String, Object?>{
    'asset': <String, Object?>{'version': '2.0'},
    'extensionsUsed': <String>['KHR_gaussian_splatting'],
    if (extensionsRequired.isNotEmpty) 'extensionsRequired': extensionsRequired,
    'scene': 0,
    'scenes': <Object?>[
      <String, Object?>{
        'nodes': <int>[0],
      },
    ],
    'nodes': <Object?>[
      <String, Object?>{'name': 'splats', 'mesh': 0, ...node},
    ],
    'meshes': <Object?>[
      <String, Object?>{
        'primitives': <Object?>[
          <String, Object?>{
            'attributes': semantics,
            'mode': mode,
            'extensions': <String, Object?>{
              'KHR_gaussian_splatting': extension,
            },
          },
        ],
      },
    ],
    'accessors': accessors,
    'bufferViews': views,
    'buffers': <Object?>[
      <String, Object?>{'byteLength': bin.length},
    ],
  };
  return GlbContainer.encode(json, binary: bin);
}

/// The zeroth-band coefficient that decodes to [colour], the inverse of
/// `splatChannel`.
double coefficientFor(double colour) => (colour - 0.5) / kSplatShC0;
