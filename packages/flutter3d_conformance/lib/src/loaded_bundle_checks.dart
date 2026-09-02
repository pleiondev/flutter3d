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
typedef OwnShaderSection = ({String id, ByteData bytes, String sdk});

/// The checks a backend runs with its own shaders packed as a bundle.
///
/// A function of the section rather than a constant list, for the reason
/// [OwnShaderSection] gives: only the harness has the bytes.
List<ConformanceCheck> loadedBundleChecks(
  Future<OwnShaderSection?> Function() ownShaders,
) => <ConformanceCheck>[
  (
    name: 'a library loaded from bytes answers to the same names',
    run: (GraphicsDevice device) async =>
        checkLoadedLibrary(device, await ownShaders()),
  ),
];

/// The engine's names, as a bundle claims them.
List<ShaderBundleStage> _engineStages() => <ShaderBundleStage>[
  for (final shader in kRequiredShaders)
    ShaderBundleStage(shader.name, fragment: shader.fragment),
];

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
    throw const ConformanceFailure(
      'twenty-four zero bytes were accepted as a shader bundle',
    );
  } on ShaderBundleRefused {
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
  } on ShaderBundleRefused catch (refused) {
    throw ConformanceFailure(
      'the backend refused its own shaders packed as a bundle: $refused',
    );
  }
  require(
    loaded.name == bundle.name,
    'the loaded library is called "${loaded.name}"; the bundle is called '
    '"${bundle.name}"',
  );
  final missing = <String>[
    for (final shader in kRequiredShaders)
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
    device.createPipeline(vertex, fragment);
  } catch (error) {
    throw ConformanceFailure(
      'MeshVertex + Pbr from the loaded library do not link: $error',
    );
  }

  // The reload contract: the same bytes again, and the handles already
  // handed out are the same objects — which is what lets a renderer that
  // resolved its stages once keep drawing through them. Linked again after,
  // because a reload that kept the handle and broke the stage behind it
  // would pass the identity check and fail at the first frame.
  try {
    loaded.refresh(bundle.encode());
  } on ShaderBundleRefused catch (refused) {
    throw ConformanceFailure(
      'refreshing the bundle it had just accepted was refused: $refused',
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
    device.createPipeline(loaded['MeshVertex']!, loaded['Pbr']!);
  } catch (error) {
    throw ConformanceFailure(
      'MeshVertex + Pbr do not link after a refresh: $error',
    );
  }

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
  } on ShaderBundleRefused catch (refused) {
    require(
      refused.name == 'claims too much' &&
          refused.reason.contains('NoSuchStageAnywhere'),
      'the refusal names neither the bundle nor the stage: $refused',
    );
  }
}
