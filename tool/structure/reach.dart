/// The rules that hold the backends to what they are promised to reach for:
/// a widget drawn into a texture takes the platform's own texture where the
/// device can wrap one, Impeller wraps one, and WebGL2 uses the extensions
/// its 1.0 feature list rests on.
///
/// **Each is a detector over text and a rule over the tree**, as the rest of
/// `tool/structure` is, so [proveReachDetectorsWork] runs every detector on
/// a made-up input before a single file is read.
library;

import 'dart:io';

import 'detectors.dart';
import 'repository.dart';

/// Where the widget surfaces live.
const String widgetSurfaceDir = 'packages/flutter3d_app/lib/src/widget_surface';

/// The Impeller backend's `lib/`.
const String impellerLib = 'packages/flutter3d_impeller/lib';

/// The WebGL2 backend's `lib/`.
const String webglLib = 'packages/flutter3d_webgl/lib';

/// [source] with its comments taken out, so a doc that names a call is not
/// read as the call.
String _code(String source) => source
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

/// The files of [files] (path to text) that read an image's pixels back
/// (`toByteData`) without asking the device for its platform texture first
/// (`is PlatformTextures<`).
///
/// **A widget surface pays the CPU round trip only where it must**: on a
/// device that wraps a `dart:ui` image, the copy through the host is the
/// whole cost of drawing a sign, and nothing else in the frame shows it.
List<String> roundTripsWithoutAskingIn(Map<String, String> files) => <String>[
  for (final MapEntry(key: path, value: text) in files.entries)
    if (_code(text).contains('.toByteData(') &&
        !_code(text).contains('is PlatformTextures<'))
      path,
];

/// What [library] (one backend's `lib/`, joined) lacks to wrap a platform
/// image: the mixin, for `dart:ui`'s `Image`, and the call that wraps one.
List<String> platformTextureProblemsIn(String library) {
  final code = _code(library);
  const noMixin =
      'mixes in no `PlatformTextures<ui.Image>`, so a widget drawn into a '
      'texture is copied through the host on the one backend that need not';
  const noWrap =
      'never calls `Texture.fromImage`, the call that wraps an image with no '
      'copy';
  return <String>[
    if (!code.contains('PlatformTextures<ui.Image>')) noMixin,
    if (!code.contains('Texture.fromImage(')) noWrap,
  ];
}

/// Each WebGL2 extension the backend's 1.0 features rest on, and a call or
/// constant that shows it is used rather than only asked for.
const Map<String, String> webglExtensions = <String, String>{
  'KHR_parallel_shader_compile': 'webglCompletionStatus',
  'EXT_disjoint_timer_query_webgl2': 'TIME_ELAPSED_EXT',
  'WEBGL_multi_draw': 'multiDrawElementsInstancedWEBGL',
  'OVR_multiview2': 'framebufferTextureMultiviewOVR',
  'EXT_clip_control': "'clipControlEXT'",
  'WEBGL_compressed_texture_s3tc': 'compressedTexSubImage2D',
  'WEBGL_compressed_texture_s3tc_srgb': 'compressedTexSubImage2D',
  'WEBGL_compressed_texture_etc': 'compressedTexSubImage2D',
  'WEBGL_compressed_texture_astc': 'compressedTexSubImage2D',
  'EXT_texture_compression_bptc': 'compressedTexSubImage2D',
  'EXT_texture_compression_rgtc': 'compressedTexSubImage2D',
};

/// The [webglExtensions] [library] (the backend's `lib/`, joined) never asks
/// for with `getExtension('…')`, or asks for and never uses.
List<String> webglExtensionProblemsIn(String library) {
  final code = _code(library);
  return <String>[
    for (final MapEntry(key: name, value: use) in webglExtensions.entries)
      if (!RegExp("getExtension\\(\\s*'$name'\\s*\\)").hasMatch(code))
        'never asks for $name'
      else if (!code.contains(use))
        'asks for $name and never uses it (no `$use`)',
  ];
}

// ----------------------------------------------------------------- rules

String _joined(String dir) => <String>[
  for (final file in dartFilesIn(Directory('${repositoryRoot.path}/$dir')))
    file.readAsStringSync(),
].join('\n');

/// A widget surface asks the device for the platform texture before it
/// reads pixels back, and Impeller wraps one.
List<Finding> widgetSurfacesSkipTheRoundTrip() => <Finding>[
  for (final path in roundTripsWithoutAskingIn(<String, String>{
    for (final file in dartFilesIn(
      Directory('${repositoryRoot.path}/$widgetSurfaceDir'),
    ))
      relative(file, repositoryRoot): file.readAsStringSync(),
  }))
    Finding(
      path,
      'reads an image back with toByteData without asking `device is '
      'PlatformTextures<ui.Image>` first: go through `textureFromImage`',
    ),
  for (final problem in platformTextureProblemsIn(_joined(impellerLib)))
    Finding(impellerLib, problem),
];

/// WebGL2 asks for and uses each extension its 1.0 features rest on.
List<Finding> webglUsesItsExtensions() => <Finding>[
  for (final problem in webglExtensionProblemsIn(_joined(webglLib)))
    Finding(webglLib, problem),
];

// ---------------------------------------------------------------- proofs

/// Each detector above, run on a made-up input it must fire on and one it
/// must not. Empty when all of them work.
List<Finding> proveReachDetectorsWork() {
  final broken = <Finding>[];
  void fires(String what, bool condition, String source) {
    if (!condition) broken.add(Finding(what, 'did not fire on: $source'));
  }

  void quiet(String what, bool condition, String source, String why) {
    if (!condition) broken.add(Finding(what, 'fired on $source — $why'));
  }

  // The round trip. Mutation: accept the question in a comment, and a file
  // that only says it asks passes.
  fires(
    'a widget surface round trip',
    roundTripsWithoutAskingIn(<String, String>{
      'a.dart':
          '// asks `device is PlatformTextures<ui.Image>` first\n'
          'final p = await image.toByteData(format: f);\n',
    }).contains('a.dart'),
    'a readback whose question is only in a comment',
  );
  quiet(
    'a widget surface round trip',
    roundTripsWithoutAskingIn(<String, String>{
      'a.dart':
          'if (device is PlatformTextures<ui.Image>) { return wrap(); }\n'
          'final p = await image.toByteData(format: f);\n',
      'b.dart': '/// once read back with `image.toByteData(...)`\n',
    }).isEmpty,
    'a readback behind the question, and one only a doc names',
    'the folder asks first, and a doc is no call',
  );

  // Impeller's wrap. Mutation: look for the mixin's name alone, and a
  // backend that mixes it in for another image type passes.
  fires(
    'the Impeller wrap',
    platformTextureProblemsIn(
          'final class D extends GraphicsDevice with PlatformTextures<Object> {}',
        ).length ==
        2,
    'a device that mixes it in for another type and wraps nothing',
  );
  quiet(
    'the Impeller wrap',
    platformTextureProblemsIn(
      'final class D extends GraphicsDevice with PlatformTextures<ui.Image> {\n'
      '  T wrap(ui.Image i) => gpu.Texture.fromImage(gpu.gpuContext, i);\n}\n',
    ).isEmpty,
    'a device that wraps a dart:ui image',
    'the wrap as written is no finding',
  );

  // The extensions. Mutation: credit a name in a comment, and the extension
  // the backend once only meant to wire passes.
  final all = <String>[
    for (final MapEntry(key: name, value: use) in webglExtensions.entries)
      "gl.getExtension('$name'); $use;",
  ].join('\n');
  quiet(
    'the WebGL2 extensions',
    webglExtensionProblemsIn(all).isEmpty,
    'a library that asks for and uses each one',
    'the extensions as wired are no finding',
  );
  fires(
    'the WebGL2 extensions',
    webglExtensionProblemsIn(
      all.replaceAll(
        "gl.getExtension('OVR_multiview2');",
        "// gl.getExtension('OVR_multiview2');",
      ),
    ).contains('never asks for OVR_multiview2'),
    'an extension asked for only in a comment',
  );
  fires(
    'the WebGL2 extensions',
    webglExtensionProblemsIn(
      all.replaceAll('TIME_ELAPSED_EXT', 'TIMESTAMP_EXT'),
    ).any((String p) => p.contains('never uses')),
    'an extension asked for and not used for what it is promised',
  );
  return broken;
}
