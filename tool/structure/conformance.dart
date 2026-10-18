/// The rules that hold the conformance suite to the features it vouches for:
/// every capability the HAL gained in 1.0 is checked by what it draws or
/// writes, not by whether its call returns.
///
/// **A probe that only calls is a check every backend passes by construction**
/// once it has the call. A wrong bias sign, a write mask applied to the wrong
/// channel or a query answering in another unit all return normally, and the
/// honesty probe that asked only "does it throw" printed a green line for each.
/// So each 1.0 feature names the check that compares its output, and the rule
/// reads that check's body (and the helpers it calls) for a readback and for
/// the feature itself.
///
/// **Each is a detector over text and a rule over the tree**, as the rest of
/// `tool/structure` is, so [proveConformanceDetectorsWork] runs every detector
/// on a made-up input before a single file is read.
library;

import 'dart:io';

import 'detectors.dart';
import 'repository.dart';

/// The conformance package, whose `lib/` holds the checks.
const String conformancePackage = 'packages/flutter3d_conformance';

/// Where the HAL declares its features.
const String capabilitiesFile =
    'packages/flutter3d_hardware/lib/src/capabilities.dart';

/// The file of the conformance package that says which check holds which
/// feature.
const String outputChecksFile =
    '$conformancePackage/lib/src/output_checks.dart';

/// A call that brings a device's output back to the host, where a check can
/// compare it: pixels, bytes or query results.
final RegExp _readsOutput = RegExp(
  r'\b(?:readback|readBuffer|readBufferSync|readQueryResults|mapBuffer)\s*\(',
);

/// The stable features [capabilities] declares after its "since 1.0" marker
/// and before its reserved ones: `(dartName, wireName)` pairs.
///
/// The features before the marker are the ones the `supportsX` getters
/// asked about before 0.9, each with a check of its own from before 1.0;
/// the reserved ones have no call to check.
List<({String dartName, String wireName})> featuresSince10In(
  String capabilities,
) {
  final start = RegExp(
    r'^\s*// -+ since 1\.0\s*$',
    multiLine: true,
  ).firstMatch(capabilities);
  final end = RegExp(
    r'^\s*// -+ reserved\s*$',
    multiLine: true,
  ).firstMatch(capabilities);
  if (start == null || end == null || end.start < start.end) {
    return const <({String dartName, String wireName})>[];
  }
  final section = capabilities.substring(start.end, end.start);
  return <({String dartName, String wireName})>[
    for (final m in RegExp(
      r"static const (\w+) = DeviceFeature\._\(\s*'([^']+)',\s*"
      r'FeatureStability\.stable',
    ).allMatches(section))
      (dartName: m.group(1)!, wireName: m.group(2)!),
  ];
}

/// A Dart string literal in either quote, escapes and all.
const String _literal =
    r"""'(?:[^'\\]|\\.)*'|"(?:[^"\\]|\\.)*"""
    '"';

/// The text of the adjacent string [literals], joined, with their quotes
/// and Dart's escaped quotes taken out.
String _textOf(String literals) => <String>[
  for (final m in RegExp(_literal).allMatches(literals))
    m
        .group(0)!
        .substring(1, m.group(0)!.length - 1)
        .replaceAll(r"\'", "'")
        .replaceAll(r'\"', '"'),
].join();

/// The entries of the `const Map<String, String> <name> = {...}` literal in
/// [source], keys to values, with Dart's escaped quotes unescaped and
/// adjacent string literals joined.
Map<String, String> stringMapIn(String source, String name) {
  final start = RegExp(
    'const Map<String, String> $name = <String, String>\\{',
  ).firstMatch(source);
  if (start == null) return const <String, String>{};
  final end = source.indexOf('\n};', start.end);
  final body = source.substring(start.end, end < 0 ? source.length : end);
  return <String, String>{
    for (final m in RegExp(
      '((?:$_literal))\\s*:\\s*((?:(?:$_literal)\\s*)+),',
    ).allMatches(body))
      _textOf(m.group(1)!): _textOf(m.group(2)!),
  };
}

/// Every `ConformanceCheck(name: ..., run: fn)` in [source]: the check's
/// name to the function it runs.
Map<String, String> checksIn(String source) => <String, String>{
  for (final m in RegExp(
    'ConformanceCheck\\(\\s*name:\\s*((?:(?:$_literal)\\s*)+),\\s*run:\\s*(\\w+)',
  ).allMatches(source))
    _textOf(m.group(1)!): m.group(2)!,
};

/// The top-level functions of [source], by name, each with its body — the
/// lines from its declaration to the next declaration at column zero, with
/// comments taken out, so a doc that names a feature or a readback is not
/// read as code.
///
/// Variables, constants and typedefs are left out: a table of probes names
/// every feature, and a check that reached one through it would be credited
/// with all of them.
Map<String, String> topLevelFunctionsIn(String source) {
  final out = <String, String>{};
  String? current;
  final body = StringBuffer();
  void close() {
    if (current != null) out[current!] = body.toString();
    current = null;
    body.clear();
  }

  for (final raw in source.split('\n')) {
    final line = raw.replaceFirst(RegExp(r'//.*$'), '');
    final declares =
        raw.isNotEmpty &&
        !raw.startsWith(RegExp(r'[\s}\)\]/]')) &&
        !raw.startsWith(RegExp(r'(?:import|export|library|part)\b'));
    if (declares) {
      close();
      if (raw.startsWith(RegExp(r'(?:final|const|var|typedef|late)\b')) ||
          raw.startsWith(
            RegExp(r'(?:abstract |sealed |base |final )*class\b'),
          )) {
        continue;
      }
      final getter = RegExp(r'\bget (\w+)').firstMatch(line);
      final function = RegExp(r'(\w+)\s*(?:<[^()]*>)?\s*\(').firstMatch(line);
      current = getter?.group(1) ?? function?.group(1);
    }
    if (current != null) body.writeln(line);
  }
  close();
  return out;
}

/// Whether [function] in [functions] brings output back to compare, itself
/// or through a function it names.
bool readsOutput(String function, Map<String, String> functions) =>
    _reaches(function, functions, (String body) => _readsOutput.hasMatch(body));

/// Whether [function] in [functions] names `DeviceFeature.<dartName>`,
/// itself or through a function it names.
bool namesFeature(
  String function,
  String dartName,
  Map<String, String> functions,
) => _reaches(
  function,
  functions,
  (String body) => RegExp('\\bDeviceFeature\\.$dartName\\b').hasMatch(body),
);

bool _reaches(
  String function,
  Map<String, String> functions,
  bool Function(String body) holds,
) {
  final seen = <String>{};
  final pending = <String>[function];
  while (pending.isNotEmpty) {
    final name = pending.removeLast();
    if (!seen.add(name)) continue;
    final body = functions[name];
    if (body == null) continue;
    if (holds(body)) return true;
    for (final m in RegExp(r'\b(\w+)\b').allMatches(body)) {
      final callee = m.group(1)!;
      if (callee != name && functions.containsKey(callee)) pending.add(callee);
    }
  }
  return false;
}

/// What is wrong with how the conformance sources [library] (path to text,
/// the package's `lib/`) hold [features]: a feature with no output check
/// and no reason, a check that does not exist, or one that never reads its
/// output back or never names the feature.
///
/// [outputChecks] maps a wire name to the name of the check that compares
/// its output; [unmeasured] maps a wire name to why no check can.
List<String> outputCheckProblemsIn({
  required List<({String dartName, String wireName})> features,
  required Map<String, String> outputChecks,
  required Map<String, String> unmeasured,
  required Map<String, String> library,
}) {
  final all = library.values.join('\n');
  final checks = checksIn(all);
  final functions = <String, String>{
    for (final text in library.values) ...topLevelFunctionsIn(text),
  };
  final known = <String>{for (final f in features) f.wireName};
  String unchecked(String f) =>
      '$f has no check that compares its output: add one that draws or '
      'writes with it and reads the pixels or bytes back, and name it in '
      '`outputChecks`, or say in `unmeasuredFeatures` why nothing can';
  String twice(String f) =>
      '$f is in both `outputChecks` and `unmeasuredFeatures`';
  String unreasoned(String f) =>
      '$f is unmeasured without a reason a reader can act on';
  String missing(String f, String check) =>
      '$f names the check "$check", which no `ConformanceCheck` is called';
  String unread(String f, String check, String run) =>
      '$f: "$check" ($run) never reads its output back — a check that only '
      'calls passes every backend that has the call';
  String unnamed(String f, String check, String run, String dartName) =>
      '$f: "$check" ($run) never names `DeviceFeature.$dartName`, so it is '
      'not asking whether the device has it';
  return <String>[
    for (final (:dartName, :wireName) in features)
      ...switch ((outputChecks[wireName], unmeasured[wireName])) {
        (null, null) => <String>[unchecked(wireName)],
        (String _, String _) => <String>[twice(wireName)],
        (null, final String why) => <String>[
          if (why.trim().length < 20) unreasoned(wireName),
        ],
        (final String check, null) => switch (checks[check]) {
          null => <String>[missing(wireName, check)],
          final run => <String>[
            if (!readsOutput(run, functions)) unread(wireName, check, run),
            if (!namesFeature(run, dartName, functions))
              unnamed(wireName, check, run, dartName),
          ],
        },
      },
    for (final name in <String>{...outputChecks.keys, ...unmeasured.keys})
      if (!known.contains(name))
        '$name is not a stable feature added in 1.0, and is listed anyway',
  ];
}

/// The checks of the lifetime promises every device makes whatever it
/// lists: its own dispose told on `lost`, a second dispose harmless, and
/// sRGB encoded on the way in and decoded on the way out.
const Map<String, String> lifetimeChecks = <String, String>{
  'a dispose is told on lost as destroyed':
      'every backend owes a DeviceLoss for its own dispose, and the null '
      'example the template copies did not report one',
  'a second dispose does nothing':
      'a renderer and its owner can both let go of a device',
  'an sRGB texture is decoded when sampled and encoded when drawn':
      'every backend lists the sRGB formats, and none was asked what they do',
};

/// Which of [lifetimeChecks] no `ConformanceCheck` in [library] is called.
List<String> lifetimeCheckProblemsIn(Map<String, String> library) {
  final checks = checksIn(library.values.join('\n'));
  return <String>[
    for (final MapEntry(key: name, value: why) in lifetimeChecks.entries)
      if (!checks.containsKey(name)) 'has no check "$name": $why',
  ];
}

/// Every `List<ConformanceCheck> get <name> => <ConformanceCheck>[...]` in
/// [sources]: the getter's name to the text of its list.
Map<String, String> checkListsIn(Iterable<String> sources) => <String, String>{
  for (final source in sources)
    for (final m in RegExp(
      r'List<ConformanceCheck> get (\w+) =>\s*(?:<ConformanceCheck>)?\[',
    ).allMatches(source))
      m.group(1)!: source.substring(m.end, switch (source.indexOf(
        '\n];',
        m.end,
      )) {
        -1 => source.length,
        final end => end,
      }),
};

/// How many checks the list [name] in [lists] holds: its own entries and,
/// through each `...other` it spreads, the other list's, as the list is
/// built at run time. A spread of a list not in [lists] counts nothing.
int checksThrough(String name, Map<String, String> lists, [Set<String>? seen]) {
  final visited = seen ?? <String>{};
  final text = lists[name];
  if (text == null || !visited.add(name)) return 0;
  final own = RegExp(r'ConformanceCheck\(\s*name:').allMatches(text).length;
  return own +
      RegExp(r'\.\.\.(\w+)')
          .allMatches(text)
          .map((m) => checksThrough(m.group(1)!, lists, visited))
          .fold(0, (int a, int b) => a + b);
}

// ----------------------------------------------------------------- rules

Map<String, String> _conformanceLibrary() => <String, String>{
  for (final file in dartFilesIn(
    Directory('${repositoryRoot.path}/$conformancePackage/lib'),
  ))
    relative(file, repositoryRoot): file.readAsStringSync(),
};

/// Every stable feature added in 1.0 has a conformance check that compares
/// its output.
List<Finding> everyFeatureComparesItsOutput() {
  final capabilities = File('${repositoryRoot.path}/$capabilitiesFile');
  final table = File('${repositoryRoot.path}/$outputChecksFile');
  if (!capabilities.existsSync() || !table.existsSync()) {
    return <Finding>[
      Finding(
        table.existsSync() ? capabilitiesFile : outputChecksFile,
        'is not there',
      ),
    ];
  }
  final features = featuresSince10In(capabilities.readAsStringSync());
  if (features.isEmpty) {
    return const <Finding>[
      Finding(
        capabilitiesFile,
        'has no stable feature between "since 1.0" and "reserved" — the '
        'markers the rule reads moved',
      ),
    ];
  }
  final text = table.readAsStringSync();
  return <Finding>[
    for (final problem in outputCheckProblemsIn(
      features: features,
      outputChecks: stringMapIn(text, 'outputChecks'),
      unmeasured: stringMapIn(text, 'unmeasuredFeatures'),
      library: _conformanceLibrary(),
    ))
      Finding(outputChecksFile, problem),
  ];
}

/// The suite checks the lifetime promises every device makes.
List<Finding> conformanceChecksTheLifetime() => <Finding>[
  for (final problem in lifetimeCheckProblemsIn(_conformanceLibrary()))
    Finding(conformancePackage, problem),
];

// ---------------------------------------------------------------- proofs

/// Each detector above, run on a made-up input it must fire on and one it
/// must not. Empty when all of them work.
List<Finding> proveConformanceDetectorsWork() {
  final broken = <Finding>[];
  void fires(String what, bool condition, String source) {
    if (!condition) broken.add(Finding(what, 'did not fire on: $source'));
  }

  void quiet(String what, bool condition, String source, String why) {
    if (!condition) broken.add(Finding(what, 'fired on $source — $why'));
  }

  const capabilities = '''
  static const blendConstant = DeviceFeature._(
    'blend-constant',
    FeatureStability.stable,
  );
  // ------------------------------------------------------------- since 1.0
  static const depthBias = DeviceFeature._(
    'depth-bias',
    FeatureStability.stable,
  );
  static const colorWriteMask = DeviceFeature._(
    'color-write-mask',
    FeatureStability.stable,
  );
  // --------------------------------------------------------------- reserved
  static const rayQuery = DeviceFeature._(
    'ray-query',
    FeatureStability.reserved,
  );
''';
  // The features. Mutation: read the whole file, and a pre-1.0 feature or a
  // reserved one is demanded a check it cannot have.
  final features = featuresSince10In(capabilities);
  fires(
    'the 1.0 features',
    features.map((f) => f.wireName).join(',') == 'depth-bias,color-write-mask',
    'two features between the markers',
  );

  // A check that calls and compares nothing, one that compares through a
  // helper, and a documented readback that is not code.
  const library = r'''
/// Draws with a bias and reads it back — `device.readback(target)`.
Future<void> checkBiasCalls(GraphicsDevice device) async {
  if (!device.features.has(DeviceFeature.depthBias)) decline(device, 'x');
  pass.setDepthBias(const DepthBias(constant: 1));
}

Future<List<int>> _centre(GraphicsDevice device) async =>
    (await device.readback(target)).buffer.asUint8List();

Future<void> checkMaskLands(GraphicsDevice device) async {
  if (!device.features.has(DeviceFeature.colorWriteMask)) {
    decline(device, 'has no mask');
  }
  require((await _centre(device))[1] == 0, 'green was written');
}

final Map<DeviceFeature, int> _table = <DeviceFeature, int>{
  DeviceFeature.depthBias: 1,
};

Future<void> checkThroughTable(GraphicsDevice device) async {
  _table.length;
  await _centre(device);
}

List<ConformanceCheck> get checks => <ConformanceCheck>[
  ConformanceCheck(name: 'a bias is drawn', run: checkBiasCalls),
  ConformanceCheck(name: 'a mask is honoured', run: checkMaskLands),
  ConformanceCheck(name: 'a bias via a table', run: checkThroughTable),
  ConformanceCheck(
    name: 'a pass\'s bias '
        'is drawn',
    run: checkMaskLands,
  ),
];
''';
  final files = <String, String>{'lib/src/x.dart': library};
  List<String> problems(Map<String, String> outputs, Map<String, String> why) =>
      outputCheckProblemsIn(
        features: features,
        outputChecks: outputs,
        unmeasured: why,
        library: files,
      );

  // Mutation: credit a check for the call alone, or for a readback its doc
  // mentions, and the bias check that reads nothing passes.
  fires(
    'an output check',
    problems(const <String, String>{
      'depth-bias': 'a bias is drawn',
      'color-write-mask': 'a mask is honoured',
    }, const <String, String>{}).any(
      (String p) => p.startsWith('depth-bias') && p.contains('never reads'),
    ),
    'a check that only calls',
  );
  // Mutation: follow tables as well as functions, and a check that reaches a
  // probe table is credited with every feature in it.
  fires(
    'an output check',
    problems(const <String, String>{
      'depth-bias': 'a bias via a table',
      'color-write-mask': 'a mask is honoured',
    }, const <String, String>{}).any((String p) => p.contains('never names')),
    'a check that names the feature only through a table',
  );
  fires(
    'an output check',
    problems(
      const <String, String>{'color-write-mask': 'a mask is honoured'},
      const <String, String>{},
    ).any((String p) => p.startsWith('depth-bias has no check')),
    'a feature with no entry',
  );
  fires(
    'an output check',
    problems(
      const <String, String>{
        'depth-bias': 'no such check',
        'color-write-mask': 'a mask is honoured',
      },
      const <String, String>{},
    ).any((String p) => p.contains('which no `ConformanceCheck`')),
    'an entry naming a check that is not there',
  );
  fires(
    'an output check',
    problems(
      const <String, String>{'color-write-mask': 'a mask is honoured'},
      const <String, String>{'depth-bias': 'later'},
    ).any((String p) => p.contains('without a reason')),
    'an exemption with no reason',
  );
  fires(
    'an output check',
    problems(
      const <String, String>{
        'color-write-mask': 'a mask is honoured',
        'ray-query': 'a mask is honoured',
      },
      const <String, String>{
        'depth-bias': 'no stage in the bundle can draw it at all',
      },
    ).any((String p) => p.startsWith('ray-query is not')),
    'an entry for a feature that is not a 1.0 one',
  );
  // Mutation: stop following callees, and the mask check that reads back
  // through `_centre` is blamed.
  quiet(
    'an output check',
    problems(
      const <String, String>{'color-write-mask': 'a mask is honoured'},
      const <String, String>{
        'depth-bias': 'no stage in the bundle can draw it at all',
      },
    ).isEmpty,
    'a check comparing through a helper, and a reasoned exemption',
    'a readback in a helper the check calls is the check reading back',
  );
  // Mutation: read only the first literal of a name, and a check named over
  // two adjacent literals with an escaped quote is not found.
  quiet(
    'an output check',
    problems(
      const <String, String>{'color-write-mask': "a pass's bias is drawn"},
      const <String, String>{
        'depth-bias': 'no stage in the bundle can draw it at all',
      },
    ).isEmpty,
    'a check named over two literals',
    'a name split across literals is one name',
  );
  fires(
    'the output check table',
    stringMapIn(
          'const Map<String, String> outputChecks = <String, String>{\n'
              '  "timestamp-query": "a pass\'s timestamps advance",\n};\n',
          'outputChecks',
        )['timestamp-query'] ==
        "a pass's timestamps advance",
    'an entry in double quotes',
  );
  fires(
    'the output check table',
    stringMapIn(
          "const Map<String, String> outputChecks = <String, String>{\n"
              "  'depth-bias': 'a pass\\'s bias '\n      'is drawn',\n};\n",
          'outputChecks',
        )['depth-bias'] ==
        "a pass's bias is drawn",
    'an entry over two literals',
  );

  // The tier counts. Mutation: count the list as written, and the checks a
  // spread brings in are missing from the number the documents are held to.
  const tier =
      "List<ConformanceCheck> get shaderChecks => <ConformanceCheck>[\n"
      "  ConformanceCheck(name: 'a', run: a),\n  ...drawn,\n];\n";
  const spread =
      "List<ConformanceCheck> get drawn => <ConformanceCheck>[\n"
      "  ConformanceCheck(name: 'b', run: b),\n"
      "  ConformanceCheck(name: 'c', run: c),\n  ...shaderChecks,\n];\n";
  final lists = checkListsIn(const <String>[tier, spread]);
  fires(
    'a tier count',
    checksThrough('shaderChecks', lists) == 3,
    'a list of one that spreads a list of two, and spreads back',
  );

  // The lifetime checks. Mutation: test any one name, and a suite with the
  // loss check and no sRGB check passes.
  fires(
    'the lifetime checks',
    lifetimeCheckProblemsIn(<String, String>{
          'lib/x.dart':
              "ConformanceCheck(name: '${lifetimeChecks.keys.first}', run: f)",
        }).length ==
        lifetimeChecks.length - 1,
    'a suite with one of them',
  );
  quiet(
    'the lifetime checks',
    lifetimeCheckProblemsIn(<String, String>{
      'lib/x.dart': <String>[
        for (final name in lifetimeChecks.keys)
          "ConformanceCheck(name: '$name', run: f)",
      ].join('\n'),
    }).isEmpty,
    'a suite with all of them',
    'the checks as named are no finding',
  );
  return broken;
}
