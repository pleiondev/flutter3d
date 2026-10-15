/// The rules that hold the HAL's 1.0 contract to its backends: the shapes it
/// settled before the freeze, the refusal every backend gives in the HAL's
/// words, the loss every backend reports for its own `dispose`, the pass
/// state that has a field for every setter, and the caret every package asks
/// for the HAL with.
///
/// **Each is a detector over text and a rule over the tree**, as the rest of
/// `tool/structure` is, so [proveHalDetectorsWork] runs every detector on a
/// made-up input before a single file is read: a detector that cannot fire
/// is worse than none, because the rule that uses it prints a green line.
library;

import 'dart:io';

import 'api.dart';
import 'detectors.dart';
import 'repository.dart';

/// The HAL's package name.
const String halPackage = 'flutter3d_hardware';

/// The packages whose `lib/` is a backend: the engine's five, and the null
/// example a backend from outside is written from (and the template is held
/// to, file for file).
const List<String> backendPackages = <String>[
  'packages/flutter3d_cpu',
  'packages/flutter3d_webgl',
  'packages/flutter3d_webgpu',
  'packages/flutter3d_impeller',
  'packages/flutter3d_wgpu',
  'examples/flutter3d_backend_null',
];

/// Why [pubspec] asks for the HAL the wrong way, or null when it asks with a
/// caret that admits [halVersion] (or not at all, or by path).
///
/// **A caret, and nothing narrower.** The HAL has no internal library, an
/// outside backend is told to write `^1.0.0`, and an in-repo backend that
/// pinned the minor (`'>=1.0.0-rc.1 <1.1.0'`) said something else than the
/// contract it is the example of.
String? halPinProblemIn(String pubspec, String halVersion) {
  final pin = RegExp(
    '^  $halPackage:[ \\t]*(\\S.*?)\\s*\$',
    multiLine: true,
  ).firstMatch(pubspec);
  if (pin == null) return null;
  final asked = pin.group(1)!;
  final caret = RegExp(r'^\^([0-9][^\s]*)$').firstMatch(asked);
  if (caret == null) {
    return 'asks for $halPackage $asked: the HAL is asked for with a caret '
        "(^$halVersion), by the engine's backends as by an outside one — it "
        'has no internal library, so nothing a dependent reads changes '
        'within a major';
  }
  final floor = caret.group(1)!;
  if (!caretAdmits(floor, halVersion) ||
      (compareVersionTexts(floor, halVersion) ?? 1) > 0) {
    return 'asks for $halPackage ^$floor, which declares $halVersion and is '
        'outside that range';
  }
  return null;
}

/// The lines of [source] (counted from one) that construct an
/// `UnsupportedError` a caller could meet: in code, not in a comment, and
/// not on an arm marked `// unreachable:` on its own line or the one above.
///
/// **Every refusal reachable through the HAL is typed** (decision 73): a
/// feature is refused with `UnsupportedCapabilityException` and a request
/// the device has the feature for with `DeviceResourceException`. A wildcard
/// over an open set is reachable, by the constant a minor adds.
List<int> untypedRefusalsIn(String source) {
  final lines = source.split('\n');
  final out = <int>[];
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final code = line.split('//').first;
    if (!RegExp(r'\bUnsupportedError\s*\(').hasMatch(code)) continue;
    final quoted = code.replaceAll(RegExp(r"'(?:[^'\\]|\\.)*'"), "''");
    if (!RegExp(r'\bUnsupportedError\s*\(').hasMatch(quoted)) continue;
    final marked =
        line.contains('// unreachable:') ||
        (i > 0 && lines[i - 1].trim().startsWith('// unreachable:'));
    if (!marked) out.add(i + 1);
  }
  return out;
}

/// The setters of `PassEncoder` in [encoder] that `PassState` in
/// [passState] has no field for, by setter name.
///
/// **A pass state object accumulates every setter or it is not the pipeline
/// state** (decision 97): a backend that builds pipeline objects from it
/// loses whatever it lacks. `setBlendColor` is the one setter without a
/// field — the blend constant is dynamic state on every API, never part of
/// a pipeline object — and [setterWithoutField] says so.
List<String> passStateGapsIn(String encoder, String passState) {
  final start = encoder.indexOf('abstract base mixin class PassEncoder');
  if (start < 0) return const <String>['PassEncoder is not in the encoder'];
  final end = encoder.indexOf('\n}\n', start);
  final body = encoder.substring(start, end < 0 ? encoder.length : end);
  final setters = <String>{
    for (final m in RegExp(
      r'^  void set([A-Z]\w*)\(',
      multiLine: true,
    ).allMatches(body))
      m.group(1)!,
  };
  final fields = <String>{
    for (final m in RegExp(
      r'^  final [\w<>?, ]+ (\w+);',
      multiLine: true,
    ).allMatches(passState))
      m.group(1)!,
  };
  return <String>[
    for (final setter in setters.toList()..sort())
      if (!setterWithoutField.containsKey(setter) &&
          !fields.contains('${setter[0].toLowerCase()}${setter.substring(1)}'))
        'set$setter',
  ];
}

/// The `PassEncoder` setters `PassState` has no field for, and why.
const Map<String, String> setterWithoutField = <String, String>{
  'BlendColor':
      'the blend constant is dynamic state on every API, set per pass and '
      'never part of a pipeline object',
};

/// What [libraries] (path to text, one backend's `lib/`) owes and does not
/// say about loss: a package that declares a device must report a loss, and
/// `DeviceLossReason.destroyed` for its own `dispose`.
List<String> lossProblemsIn(Map<String, String> libraries) {
  final devices = <String>[
    for (final MapEntry(key: path, value: text) in libraries.entries)
      if (RegExp(r'\bclass \w+ extends GraphicsDevice\b').hasMatch(text)) path,
  ];
  if (devices.isEmpty) return const <String>[];
  final all = libraries.values.join('\n');
  final device = devices.first;
  const noLost =
      'never overrides `lost`: the empty default reads as "never lost", and '
      'every backend owes a DeviceLoss at least for its own dispose';
  const noDestroyed =
      'never reports `DeviceLossReason.destroyed`: its own dispose is a loss '
      'a caller is told of';
  return <String>[
    if (!RegExp(r'Stream<DeviceLoss> get lost\b').hasMatch(all))
      'declares a device ($device) and $noLost',
    if (!all.contains('DeviceLossReason.destroyed'))
      'declares a device ($device) and $noDestroyed',
  ];
}

/// The shapes the HAL settled before the freeze (decisions 83–87, 95–97),
/// each a line [snapshot] (`api/flutter3d_hardware.api`) must carry or must
/// not, and what changing it would break.
const List<({String line, bool present, String why})>
halShapes = <({String line, bool present, String why})>[
  (
    line:
        'typedef BackendOpener = Future<GraphicsDevice> Function(DeviceRequest request);',
    present: true,
    why: 'an opener takes one request, so a field added later breaks none',
  ),
  (
    line:
        'typedef ComputeOpener = Future<GraphicsDevice> Function(DeviceRequest request);',
    present: true,
    why: 'a compute opener takes one request too',
  ),
  (
    line: 'abstract void setViewport(PassViewport viewport)',
    present: true,
    why: 'the viewport is doubles with a depth range',
  ),
  (
    line:
        'bool bindUniformBuffer(ShaderHandle stage, String blockName, StorageBuffer buffer, int offsetInBytes, int sizeInBytes)',
    present: true,
    why: 'a buffer range binds as a block, with a refusing default',
  ),
  (
    line: 'abstract bool bindUniformBuffer(',
    present: false,
    why: 'a member a backend may not have must have a refusing body',
  ),
  (
    line: 'Stream<DeviceError> get errors',
    present: true,
    why: 'a refusal an API makes late goes to `errors`, not `beginFrame`',
  ),
  (
    line: 'final ClearColor? clearValue',
    present: true,
    why: 'a clear colour is an immutable value that holds every integer',
  ),
  (
    line: 'Vector4',
    present: false,
    why: 'no vector_math type in the contract, so its major is not ours',
  ),
  (
    line: 'static const blendConstantAlpha = DeviceFeature._(',
    present: true,
    why: 'the alpha pair of the blend constant is its own feature',
  ),
  (
    line: 'static const primitiveStrips = DeviceFeature._(',
    present: true,
    why: 'a strip is a capability, decided before 1.0 backends accept it',
  ),
  (
    line: 'static const pointPrimitives = DeviceFeature._(',
    present: true,
    why: 'points are a capability, decided before 1.0 backends accept them',
  ),
  (
    line: 'static const indexUint32 = DeviceFeature._(',
    present: true,
    why: '32-bit indices are a capability, decided before the freeze',
  ),
];

/// Which of [halShapes] [snapshot] has lost.
List<String> halShapeProblemsIn(String snapshot) => <String>[
  for (final shape in halShapes)
    if (snapshot.contains(shape.line) != shape.present)
      _shapeProblem(shape.line, present: shape.present, why: shape.why),
];

String _shapeProblem(
  String line, {
  required bool present,
  required String why,
}) => '${present ? 'no longer carries' : 'carries'} `$line`: $why';

/// The terms a backend author relies on that [halMd] no longer states.
List<String> halTermsMissingFrom(String halMd) => <String>[
  for (final MapEntry(key: phrase, value: why) in halTerms.entries)
    if (!halMd.contains(phrase)) 'does not say "$phrase": $why',
];

/// What `HAL.md` must keep saying, and why (decisions 90 and 91).
const Map<String, String> halTerms = <String, String>{
  '**It is versioned with the\nengine**':
      'the HAL shares the engine major.minor, and the stability document '
      'says the same',
  '**Every backend depends on\nit through a caret range**':
      'an outside backend is told to write a caret, and the in-repo ones do',
  "**A backend's own members are its author's risk.**":
      'a member a minor adds can collide with a backend\'s own',
  '**A new limit inherits a safe default.**':
      'a DeviceLimits field a minor adds must not claim more than a 1.0 '
      'backend has',
};

// ----------------------------------------------------------------- rules

/// Every backend's `lib/` refuses in the HAL's words.
List<Finding> backendsRefuseTyped() => <Finding>[
  for (final package in backendPackages)
    for (final file in dartFilesIn(
      Directory('${repositoryRoot.path}/$package/lib'),
    ))
      for (final line in untypedRefusalsIn(file.readAsStringSync()))
        Finding(
          '$package/${relative(file, Directory('${repositoryRoot.path}/$package'))}:$line',
          'throws an UnsupportedError a caller can meet: refuse a feature '
              "with `refuse(feature)` or `features.require`, and a request the "
              'device cannot honour with `refuseResource` or the backend\'s '
              'helper over `DeviceResourceException`; mark an arm that truly '
              'cannot be reached `// unreachable: <why>`',
        ),
];

/// Every backend reports its own dispose on `lost`.
List<Finding> backendsReportTheirLoss() => <Finding>[
  for (final package in backendPackages)
    for (final problem in lossProblemsIn(<String, String>{
      for (final file in dartFilesIn(
        Directory('${repositoryRoot.path}/$package/lib'),
      ))
        relative(file, Directory('${repositoryRoot.path}/$package')): file
            .readAsStringSync(),
    }))
      Finding(package, problem),
];

/// `PassState` has a field for every setter of `PassEncoder`.
List<Finding> passStateCoversTheSetters() {
  final src = '${repositoryRoot.path}/packages/$halPackage/lib/src';
  final encoder = File('$src/command_encoder.dart');
  final state = File('$src/pass_state.dart');
  if (!encoder.existsSync() || !state.existsSync()) {
    return const <Finding>[
      Finding(
        'packages/flutter3d_hardware',
        'the encoder or PassState is gone',
      ),
    ];
  }
  return <Finding>[
    for (final setter in passStateGapsIn(
      encoder.readAsStringSync(),
      state.readAsStringSync(),
    ))
      Finding(
        'packages/flutter3d_hardware/lib/src/pass_state.dart',
        'has no field for `PassEncoder.$setter`: a backend that builds '
            'pipeline objects from PassState loses it — add the field, its '
            'copyWith, ==, and the call in setState, or say in '
            '`setterWithoutField` why it is no pipeline state',
      ),
  ];
}

/// The HAL keeps the shapes it settled before the freeze, and HAL.md the
/// terms an outside backend relies on.
List<Finding> halKeepsItsShapes() {
  final dir = '${repositoryRoot.path}/packages/$halPackage';
  final snapshot = File('$dir/api/$halPackage.api');
  final doc = File('$dir/HAL.md');
  return <Finding>[
    if (snapshot.existsSync())
      for (final problem in halShapeProblemsIn(snapshot.readAsStringSync()))
        Finding('packages/$halPackage/api/$halPackage.api', problem)
    else
      Finding('packages/$halPackage/api/$halPackage.api', 'is not there'),
    if (doc.existsSync())
      for (final problem in halTermsMissingFrom(doc.readAsStringSync()))
        Finding('packages/$halPackage/HAL.md', problem)
    else
      Finding('packages/$halPackage/HAL.md', 'is not there'),
  ];
}

// ---------------------------------------------------------------- proofs

/// Each detector above, run on a made-up input it must fire on and one it
/// must not. Empty when all of them work.
List<Finding> proveHalDetectorsWork() {
  final broken = <Finding>[];
  void fires(String what, bool condition, String source) {
    if (!condition) broken.add(Finding(what, 'did not fire on: $source'));
  }

  void quiet(String what, bool condition, String source, String why) {
    if (!condition) broken.add(Finding(what, 'fired on $source — $why'));
  }

  // The HAL pin. Mutation: accept any `>=` range, and the in-repo backends
  // pin the minor the contract tells others not to.
  fires(
    'a HAL pin',
    halPinProblemIn(
          "dependencies:\n  flutter3d_hardware: '>=1.0.0-rc.1 <1.1.0'\n",
          '1.0.0-rc.1+2',
        ) !=
        null,
    'a pin within the minor',
  );
  fires(
    'a HAL pin',
    halPinProblemIn(
          'dependencies:\n  flutter3d_hardware: ^2.0.0\n',
          '1.0.0-rc.1+2',
        ) !=
        null,
    'a caret that cannot reach what the HAL declares',
  );
  quiet(
    'a HAL pin',
    halPinProblemIn(
          'dependencies:\n  flutter3d_hardware: ^1.0.0-rc.1\n',
          '1.0.0-rc.1+2',
        ) ==
        null,
    'a caret from an older floor',
    'a floor below what the HAL declares is admitted',
  );
  quiet(
    'a HAL pin',
    halPinProblemIn(
          'dependencies:\n  flutter3d_hardware:\n    path: ../x\n',
          '1.0.0-rc.1+2',
        ) ==
        null,
    'a path dependency',
    'an example that depends by path asks for no version',
  );

  // Untyped refusals. Mutation: read comments as code, and the doc that
  // names the rule breaks it; drop the marker test, and an arm somebody
  // proved unreachable is flagged.
  fires(
    'an untyped refusal',
    untypedRefusalsIn(
      "  _ => throw UnsupportedError('no layout for \$format'),\n",
    ).isNotEmpty,
    'a wildcard arm',
  );
  fires(
    'an untyped refusal',
    untypedRefusalsIn(
      "    if (mipLevel != 0) {\n      throw UnsupportedError(\n",
    ).isNotEmpty,
    'a reachable refusal',
  );
  quiet(
    'an untyped refusal',
    untypedRefusalsIn(
      '/// refused with an UnsupportedError(...) before 1.0\n'
      '} on UnsupportedError {\n'
      "  final said = 'an UnsupportedError(x) in a string';\n"
      '  // unreachable: every value this version names is above\n'
      "  _ => throw UnsupportedError('\$this'),\n",
    ).isEmpty,
    'a doc, a catch, a string and a marked arm',
    'only a construction a caller can meet is a finding',
  );

  // PassState's setters. Mutation: compare the setter name as written, and
  // `setViewport` looks for a `Viewport` field.
  const encoder = '''
abstract base mixin class PassEncoder {
  void setViewport(PassViewport viewport);
  void setDepthBias(DepthBias bias) => refuse();
  void setBlendColor(LinearColor color) => refuse();
}
''';
  fires(
    'pass state setters',
    passStateGapsIn(
      encoder,
      '  final PassViewport? viewport;\n',
    ).contains('setDepthBias'),
    'a setter PassState has no field for',
  );
  quiet(
    'pass state setters',
    passStateGapsIn(
      encoder,
      '  final PassViewport? viewport;\n  final DepthBias? depthBias;\n',
    ).isEmpty,
    'a PassState with both fields, and the blend colour',
    'a field per setter, and the one setter that is no pipeline state',
  );

  // Loss on dispose. Mutation: look for `lost` only, and the null example
  // that overrode nothing passes.
  fires(
    'loss on dispose',
    lossProblemsIn(<String, String>{
          'lib/src/x_device.dart':
              'final class XDevice extends GraphicsDevice {\n'
              '  void dispose() => _disposed = true;\n}\n',
        }).length ==
        2,
    'a device that never reports a loss',
  );
  quiet(
    'loss on dispose',
    lossProblemsIn(<String, String>{
      'lib/src/x_device.dart':
          'final class XDevice extends GraphicsDevice {\n'
          '  Stream<DeviceLoss> get lost => _lost.stream;\n'
          '  void dispose() => _lost.add(const DeviceLoss(\n'
          '    reason: DeviceLossReason.destroyed));\n}\n',
      'lib/x.dart': 'export "src/x_device.dart";\n',
    }).isEmpty,
    'a device that reports its dispose',
    'a backend that keeps the promise is not blamed for it',
  );
  quiet(
    'loss on dispose',
    lossProblemsIn(<String, String>{
      'lib/x.dart': 'final class XCompiler extends MaterialCompiler {}\n',
    }).isEmpty,
    'a package with no device',
    'only a package that declares a device owes a loss',
  );

  // The settled shapes. Mutation: test presence for every row, and the
  // Vector4 row passes the snapshot that still names one.
  final good = <String>[
    for (final shape in halShapes)
      if (shape.present) shape.line,
  ].join('\n');
  quiet(
    'the HAL shapes',
    halShapeProblemsIn(good).isEmpty,
    'a snapshot with every settled line',
    'the shapes as they are settled are no finding',
  );
  fires(
    'the HAL shapes',
    halShapeProblemsIn(
      '$good\n  final vm.Vector4? clearValue\n',
    ).any((String p) => p.contains('Vector4')),
    'a snapshot that names a vector_math type',
  );
  fires(
    'the HAL shapes',
    halShapeProblemsIn(
      good.replaceAll('PassViewport viewport', 'ScreenRect rect'),
    ).isNotEmpty,
    'a viewport of whole pixels again',
  );
  fires(
    'the HAL terms',
    halTermsMissingFrom('# The hardware abstraction layer\n').length ==
        halTerms.length,
    'a HAL.md that says none of them',
  );
  quiet(
    'the HAL terms',
    halTermsMissingFrom(halTerms.keys.join('\n')).isEmpty,
    'a HAL.md that says all of them',
    'the terms as written are no finding',
  );
  return broken;
}
