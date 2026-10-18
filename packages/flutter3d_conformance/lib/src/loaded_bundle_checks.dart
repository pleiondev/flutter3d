import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_shaders/flutter3d_shaders.dart';

import '../flutter3d_conformance.dart';

/// This backend's own shaders, as the section of a loadable bundle it reads.
///
/// Supplied by the harness rather than made here, because the bytes are the
/// backend's compiler's — `impellerc` output for Impeller, the translated
/// GLSL ES for WebGL — and this package has neither. [sdk] is what the header
/// is stamped with, so a backend that checks it sees its own. Null from a
/// backend that compiles nothing and answers a bundle with what it has.
///
/// A class rather than a record, so it can carry more in a minor.
final class OwnShaderSection {
  /// A section [id] of [bytes], in a bundle stamped with [sdk].
  const OwnShaderSection({
    required this.id,
    required this.bytes,
    required this.sdk,
  });

  /// The section's id in the bundle: the backend's own.
  final String id;

  /// The section's bytes, as the backend's compiler wrote them.
  final ByteData bytes;

  /// The SDK the bundle's header is stamped with.
  final String sdk;

  @override
  bool operator ==(Object other) =>
      other is OwnShaderSection &&
      other.id == id &&
      other.bytes == bytes &&
      other.sdk == sdk;

  @override
  int get hashCode => Object.hash(id, bytes, sdk);

  @override
  String toString() => 'OwnShaderSection($id, sdk $sdk)';
}

/// The checks a backend runs with its own shaders packed as a bundle.
///
/// A function of the section rather than a constant list, for the reason
/// [OwnShaderSection] gives: only the harness has the bytes.
List<ConformanceCheck> loadedBundleChecks(
  Future<OwnShaderSection?> Function() ownShaders,
) => <ConformanceCheck>[
  ConformanceCheck(
    name: 'a library loaded from bytes answers to the same names',
    run: (GraphicsDevice device) async =>
        checkLoadedLibrary(device, await ownShaders()),
  ),
];

/// The engine's names, as a bundle claims them.
List<ShaderBundleStage> _engineStages() => <ShaderBundleStage>[
  for (final shader in requiredShaders)
    ShaderBundleStage(shader.name, fragment: shader.fragment),
];

/// Checks that [device] refuses bytes that are not a bundle with a
/// [ShaderBundleException], and that its own shaders packed as a bundle ([own],
/// or none) load into a library answering every engine name.
Future<void> checkLoadedLibrary(
  GraphicsDevice device,
  OwnShaderSection? own,
) async {
  // Not a bundle: refused, and refused with the one exception the interface
  // names. A backend that threw something else — or worse, handed back a
  // library with nothing in it — would send the caller reading a stack trace
  // for what should be one sentence.
  try {
    await device.loadShaders(ByteData(24));
    throw const ConformanceFailureException(
      'twenty-four zero bytes were accepted as a shader bundle',
    );
  } on ShaderBundleException {
    // The right answer.
  }

  // The backend's own shaders, packed the way an application would pack a
  // bundle it ships, then loaded from bytes. Every name the engine asks for
  // has to be answered by the loaded library exactly as the built-in one
  // answers it — the same names, and a pair that links.
  final bundle = ShaderBundle(
    name: 'the engine, from bytes',
    sdk: own?.sdk ?? '',
    stages: _engineStages(),
    sections: <String, ByteData>{if (own != null) own.id: own.bytes},
  );
  final LoadedShaderLibrary loaded;
  try {
    loaded = await device.loadShaders(bundle.encode());
  } on ShaderBundleException catch (refused, stackTrace) {
    Error.throwWithStackTrace(
      ConformanceFailureException(
        'the backend refused its own shaders packed as a bundle: $refused',
      ),
      stackTrace,
    );
  }
  require(
    loaded.name == bundle.name,
    'the loaded library is called "${loaded.name}"; the bundle is called '
    '"${bundle.name}"',
  );
  final missing = <String>[
    for (final shader in requiredShaders)
      if (loaded[shader.name] == null) shader.name,
  ];
  require(
    missing.isEmpty,
    'loaded from bytes, the bundle has no ${missing.join(', ')}; the '
    'built-in library answers every one of them',
  );

  final vertex = loaded['MeshVertex']!;
  final fragment = loaded['Pbr']!;
  try {
    device.createPipelineFrom(
      PipelineDescriptor(vertex: vertex, fragment: fragment),
    );
  } catch (error, stackTrace) {
    Error.throwWithStackTrace(
      ConformanceFailureException(
        'MeshVertex + Pbr from the loaded library do not link: $error',
      ),
      stackTrace,
    );
  }

  // The reload contract: the same bytes again, and the handles already
  // handed out are the same objects — which is what lets a renderer that
  // resolved its stages once keep drawing through them. Linked again after,
  // because a reload that kept the handle and broke the stage behind it
  // would pass the identity check and fail at the first frame.
  try {
    loaded.refresh(bundle.encode());
  } on ShaderBundleException catch (refused, stackTrace) {
    Error.throwWithStackTrace(
      ConformanceFailureException(
        'refreshing the bundle it had just accepted was refused: $refused',
      ),
      stackTrace,
    );
  }
  require(
    identical(loaded['MeshVertex'], vertex) &&
        identical(loaded['Pbr'], fragment),
    'a refresh handed out new handles for MeshVertex or Pbr; the ones already '
    'handed out must keep their identity, or every pipeline the renderer '
    'builds afterwards links against stale stages',
  );
  try {
    device.createPipelineFrom(
      PipelineDescriptor(
        vertex: loaded['MeshVertex']!,
        fragment: loaded['Pbr']!,
      ),
    );
  } catch (error, stackTrace) {
    Error.throwWithStackTrace(
      ConformanceFailureException(
        'MeshVertex + Pbr do not link after a refresh: $error',
      ),
      stackTrace,
    );
  }

  // The other half of the identity promise: a bundle that no longer names a
  // stage already handed out is refused, naming the stage, and the library
  // is left as it was. Accepting it would leave the renderer holding `Pbr`
  // over a bundle that has no `Pbr` — a picture that disagrees with the
  // file, differently on every backend. The check is made before anything
  // is swapped, so the name and the handles afterwards are the old ones.
  final dropping = ShaderBundle(
    name: 'drops Pbr',
    sdk: own?.sdk ?? '',
    stages: <ShaderBundleStage>[
      for (final stage in _engineStages())
        if (stage.name != 'Pbr') stage,
    ],
    sections: <String, ByteData>{if (own != null) own.id: own.bytes},
  );
  try {
    loaded.refresh(dropping.encode());
    throw const ConformanceFailureException(
      'a refresh with a bundle that no longer names Pbr was accepted while '
      'the Pbr handle was in use',
    );
  } on ShaderBundleException catch (refused) {
    require(
      refused.name == 'drops Pbr' && refused.reason.contains('Pbr'),
      'the refusal for a dropped stage names neither the bundle nor the '
      'stage: $refused',
    );
  }
  require(
    loaded.name == bundle.name && identical(loaded['Pbr'], fragment),
    'a refused refresh changed the library: it is now called '
    '"${loaded.name}" and Pbr is ${loaded['Pbr']}',
  );

  // A bundle naming a stage nobody has. Two honest answers, depending on
  // what the backend is: refused at load naming the stage, which is the
  // software rasteriser's — it cannot compile, so a name it has no Dart for
  // is a bundle it cannot run — or accepted with that name answering null,
  // which is a compiled section that simply has no such entry. What is not
  // honest is a handle: something that would be bound and drawn with.
  final claiming = ShaderBundle(
    name: 'claims too much',
    sdk: own?.sdk ?? '',
    stages: <ShaderBundleStage>[
      ..._engineStages(),
      const ShaderBundleStage('NoSuchStageAnywhere', fragment: true),
    ],
    sections: <String, ByteData>{if (own != null) own.id: own.bytes},
  );
  try {
    final accepted = await device.loadShaders(claiming.encode());
    require(
      accepted['NoSuchStageAnywhere'] == null,
      'a stage the bundle claims and no section holds was answered with a '
      'handle',
    );
  } on ShaderBundleException catch (refused) {
    require(
      refused.name == 'claims too much' &&
          refused.reason.contains('NoSuchStageAnywhere'),
      'the refusal names neither the bundle nor the stage: $refused',
    );
  }
}
