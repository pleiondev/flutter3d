/// Turns `document.lights`/`document.cameras` into glTF's
/// `extensions.KHR_lights_punctual.lights` and core `cameras` arrays —
/// `fmt-28`'s own row, the write side of `gltf_loader_lights_cameras.dart`.
///
/// **A part of `gltf_writer.dart`**, for the same reason as every other
/// phase: `writeGlb()` reads the two lists this returns straight into its own
/// top-level `json` map.
part of 'gltf_writer.dart';

extension _GltfWriterLightsCameras on GltfWriter {
  /// `extensions.KHR_lights_punctual.lights`, the document-level array a
  /// node's own `extensions.KHR_lights_punctual.light` indexes into. Empty
  /// when [ModelDocument.lights] is, so `writeGlb()` omits the whole
  /// extension block rather than writing an empty one.
  List<Map<String, Object?>> _writeLights() {
    if (document.lights.isNotEmpty) {
      _extensionsUsed.add('KHR_lights_punctual');
    }
    return <Map<String, Object?>>[
      for (final light in document.lights) _lightJson(light),
    ];
  }

  Map<String, Object?> _lightJson(ModelLight light) => <String, Object?>{
    if (light.name != null) 'name': light.name,
    'type': light.type.name,
    // Written whenever it differs from white, rather than always: white is
    // the spec's own default, so a file this writer produces stays as small
    // as one written by an authoring tool that also omits the default.
    if (light.color.x != 1.0 || light.color.y != 1.0 || light.color.z != 1.0)
      'color': <double>[light.color.x, light.color.y, light.color.z],
    if (light.intensity != 1.0) 'intensity': light.intensity,
    if (light.range != null) 'range': light.range,
    if (light.type == ModelLightType.spot)
      'spot': <String, Object?>{
        if (light.innerConeAngle != 0.0) 'innerConeAngle': light.innerConeAngle,
        // math.pi / 4 is the spec default; written back exactly when the
        // decoded value came from an explicit key, same reasoning as color.
        if (light.outerConeAngle != math.pi / 4)
          'outerConeAngle': light.outerConeAngle,
      },
  };

  /// glTF's own `cameras`, core rather than an extension.
  List<Map<String, Object?>> _writeCameras() => <Map<String, Object?>>[
    for (final camera in document.cameras) _cameraJson(camera),
  ];

  Map<String, Object?> _cameraJson(ModelCamera camera) =>
      switch (camera.projection) {
        final ModelPerspectiveCamera p => <String, Object?>{
          if (camera.name != null) 'name': camera.name,
          'type': 'perspective',
          'perspective': <String, Object?>{
            'yfov': p.yfov,
            if (p.aspectRatio != null) 'aspectRatio': p.aspectRatio,
            'znear': p.znear,
            if (p.zfar != null) 'zfar': p.zfar,
          },
        },
        final ModelOrthographicCamera o => <String, Object?>{
          if (camera.name != null) 'name': camera.name,
          'type': 'orthographic',
          'orthographic': <String, Object?>{
            'xmag': o.xmag,
            'ymag': o.ymag,
            'znear': o.znear,
            'zfar': o.zfar,
          },
        },
      };
}
