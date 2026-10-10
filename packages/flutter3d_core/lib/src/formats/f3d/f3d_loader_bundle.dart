/// Reads what makes a `.f3d` a whole asset: lights, cameras and the nodes
/// that carry them, each material's lighting model, material language
/// programs, prefab documents and files carried whole.
///
/// **A part of `f3d_loader.dart`, not a file of its own**, for the reason
/// the other parts give. Every section here is optional: a file without one
/// reads as having none, which is every file written before 1.0.0-rc.1.
part of 'f3d_loader.dart';

extension _F3dBundle on F3dDocument {
  List<ModelLight> _readLights() {
    final table = _table(F3dSection.lights, F3dRecord.light);
    return <ModelLight>[
      for (var i = 0; i < table.count; i++)
        () {
          final o = _recordOffset(F3dSection.lights, i, F3dRecord.light);
          double f(int at) => _view.getFloat32(o + at, Endian.little);
          final hasRange = _view.getUint32(o + 40, Endian.little) & 1 != 0;
          return ModelLight(
            type: switch (_view.getUint32(o, Endian.little)) {
              0 => ModelLightType.directional,
              2 => ModelLightType.spot,
              // A type a later writer added reads as the plainest light.
              _ => ModelLightType.point,
            },
            color: LinearColor(f(4), f(8), f(12)),
            intensity: f(16),
            range: hasRange ? f(20) : null,
            innerConeAngle: f(24),
            outerConeAngle: f(28),
            name: _string(
              _view.getUint32(o + 32, Endian.little),
              _view.getUint32(o + 36, Endian.little),
            ),
          );
        }(),
    ];
  }

  List<ModelCamera> _readCameras() {
    final table = _table(F3dSection.cameras, F3dRecord.camera);
    return <ModelCamera>[
      for (var i = 0; i < table.count; i++)
        () {
          final o = _recordOffset(F3dSection.cameras, i, F3dRecord.camera);
          double f(int at) => _view.getFloat32(o + at, Endian.little);
          final flags = _view.getUint32(o + 20, Endian.little);
          return ModelCamera(
            projection: _view.getUint32(o, Endian.little) == 1
                ? ModelOrthographicCamera(
                    xmag: f(4),
                    ymag: f(8),
                    znear: f(12),
                    zfar: f(16),
                  )
                : ModelPerspectiveCamera(
                    yfov: f(4),
                    aspectRatio: flags & 1 != 0 ? f(8) : null,
                    znear: f(12),
                    zfar: flags & 2 != 0 ? f(16) : null,
                  ),
            name: _string(
              _view.getUint32(o + 24, Endian.little),
              _view.getUint32(o + 28, Endian.little),
            ),
          );
        }(),
    ];
  }

  /// Section 31, by node index: the light and the camera each node carries.
  Map<int, (int?, int?)> _readNodeAttachments() {
    final table = _table(F3dSection.nodeAttachments, F3dRecord.nodeAttachment);
    return <int, (int?, int?)>{
      for (var i = 0; i < table.count; i++)
        if (_recordOffset(
              F3dSection.nodeAttachments,
              i,
              F3dRecord.nodeAttachment,
            )
            case final o)
          _view.getUint32(o, Endian.little): (
            switch (_view.getInt32(o + 4, Endian.little)) {
              final int light when light >= 0 => light,
              _ => null,
            },
            switch (_view.getInt32(o + 8, Endian.little)) {
              final int camera when camera >= 0 => camera,
              _ => null,
            },
          ),
    };
  }

  /// Section 32, by material index. A model this build does not know reads
  /// as none — the material's base parameters — and says so in [warnings]'s
  /// place: the record is skipped rather than refused.
  Map<int, LightingModel> _readMaterialLighting() {
    final table = _table(
      F3dSection.materialLighting,
      F3dRecord.materialLighting,
    );
    final lighting = <int, LightingModel>{};
    for (var i = 0; i < table.count; i++) {
      final o = _recordOffset(
        F3dSection.materialLighting,
        i,
        F3dRecord.materialLighting,
      );
      final json = _string(
        _view.getUint32(o + 4, Endian.little),
        _view.getUint32(o + 8, Endian.little),
      );
      final Object? decoded;
      try {
        decoded = json == null ? null : jsonDecode(json);
      } on FormatException catch (error) {
        throw F3dFormatException('A lighting model is not JSON: $error');
      }
      final model = readLightingJson(decoded, <String>[]);
      if (model != null) lighting[_view.getUint32(o, Endian.little)] = model;
    }
    return lighting;
  }

  /// A names-to-text section (programs, prefabs) in file order.
  Map<String, String> _readNamedTexts(int kind) {
    final table = _table(kind, F3dRecord.namedText);
    return <String, String>{
      for (var i = 0; i < table.count; i++)
        if (_recordOffset(kind, i, F3dRecord.namedText) case final o)
          _string(
                    _view.getUint32(o, Endian.little),
                    _view.getUint32(o + 4, Endian.little),
                  ) ??
                  '':
              _string(
                _view.getUint32(o + 8, Endian.little),
                _view.getUint32(o + 12, Endian.little),
              ) ??
              '',
    };
  }

  Map<String, Map<String, Object?>> _readPrefabs() =>
      <String, Map<String, Object?>>{
        for (final MapEntry(:key, :value) in _readNamedTexts(
          F3dSection.prefabs,
        ).entries)
          key: switch (_decodeJson(value, 'prefab "$key"')) {
            final Map<String, Object?> document => document,
            _ => throw F3dFormatException(
              'Prefab "$key" is not a JSON object.',
            ),
          },
      };

  Object? _decodeJson(String text, String what) {
    try {
      return jsonDecode(text);
    } on FormatException catch (error) {
      throw F3dFormatException('$what is not JSON: ${error.message}');
    }
  }

  Map<String, Uint8List> _readFiles() {
    final table = _table(F3dSection.files, F3dRecord.file);
    return <String, Uint8List>{
      for (var i = 0; i < table.count; i++)
        if (_recordOffset(F3dSection.files, i, F3dRecord.file) case final o)
          _string(
                _view.getUint32(o, Endian.little),
                _view.getUint32(o + 4, Endian.little),
              ) ??
              '': Uint8List.view(
            _bytes.buffer,
            _blobOffset(
              _view.getUint32(o + 8, Endian.little),
              _view.getUint32(o + 12, Endian.little),
            ),
            _view.getUint32(o + 12, Endian.little),
          ),
    };
  }
}
