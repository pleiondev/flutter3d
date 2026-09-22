/// The shape `tool/tutorial/shoot.dart` reads a case's own steps from — a
/// plain JSON file, not a DSL. `tut-00`'s plan is explicit that this is a
/// small thing: "a list of {tool, args} steps plus an output filename per
/// step is enough" for the six tutorial cases none of which exist on this
/// branch yet, so this stays exactly that and nothing more.
library;

import 'dart:convert';

/// One step of a scenario: an MCP tool to call, its arguments, and —
/// optionally — the filename this step's screenshot is saved under.
///
/// [tool] and [args] are a `tools/call` request's own `name`/`arguments`
/// verbatim, so a step can name either a document tool (`import`,
/// `addPrimitive`, `exportModel`, …) or one of `mcp-16d`'s seven `ui.*`
/// tools (`ui.setMode`, `ui.say`, …) — [ShootRunner] does not tell the two
/// apart, and neither does this parser.
final class TutorialStep {
  const TutorialStep({required this.tool, required this.args, this.screenshot});

  /// The MCP tool name — `tools/call`'s own `name`.
  final String tool;

  /// `tools/call`'s own `arguments`, JSON-shaped.
  final Map<String, Object?> args;

  /// The PNG filename this step is caught under, joined to the scenario's
  /// own output directory by [TutorialScenario.screenshotPath] —
  /// `NN-<step>.png`, the convention T6's plan fixes for
  /// `cloud/server/web/assets/learn/modeler/<case>/`. Null for a step with
  /// nothing of its own worth catching — a setup step a later screenshot
  /// depends on, say.
  final String? screenshot;

  factory TutorialStep.fromJson(Map<String, Object?> json) {
    final tool = json['tool'];
    if (tool is! String || tool.isEmpty) {
      throw FormatException('a step needs a non-empty "tool" name: $json');
    }
    final rawArgs = json['args'];
    if (rawArgs != null && rawArgs is! Map) {
      throw FormatException('step "$tool"\'s "args" must be an object: $json');
    }
    final screenshot = json['screenshot'];
    if (screenshot != null && screenshot is! String) {
      throw FormatException(
        'step "$tool"\'s "screenshot" must be a string filename: $json',
      );
    }
    return TutorialStep(
      tool: tool,
      args: rawArgs == null
          ? const <String, Object?>{}
          : Map<String, Object?>.from(rawArgs as Map),
      screenshot: screenshot as String?,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'tool': tool,
    if (args.isNotEmpty) 'args': args,
    if (screenshot != null) 'screenshot': screenshot,
  };
}

/// A named sequence of [TutorialStep]s — one tutorial case, or the
/// placeholder scenario `tool/tutorial/test/fixtures` carries until a real
/// one exists.
final class TutorialScenario {
  const TutorialScenario({required this.name, required this.steps});

  /// The case's own slug — `a-prop-from-a-scan`, say — used both as this
  /// scenario's own name and as the subdirectory its screenshots land in
  /// (see [screenshotPath]), matching
  /// `cloud/server/web/assets/learn/modeler/<case>/`.
  final String name;

  final List<TutorialStep> steps;

  factory TutorialScenario.fromJson(Map<String, Object?> json) {
    final name = json['name'];
    if (name is! String || name.isEmpty) {
      throw const FormatException('a scenario needs a non-empty "name"');
    }
    final rawSteps = json['steps'];
    if (rawSteps is! List) {
      throw FormatException('scenario "$name" needs a "steps" list');
    }
    return TutorialScenario(
      name: name,
      steps: <TutorialStep>[
        for (final step in rawSteps)
          TutorialStep.fromJson(step! as Map<String, Object?>),
      ],
    );
  }

  /// Parses [source] as JSON and builds the scenario it describes. The one
  /// entry point `bin/shoot.dart` reads a scenario file through.
  factory TutorialScenario.parse(String source) =>
      TutorialScenario.fromJson(json.decode(source) as Map<String, Object?>);

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'steps': <Object?>[for (final step in steps) step.toJson()],
  };

  /// Where [screenshot] lands under [outDir] — `<outDir>/<name>/<screenshot>`
  /// — the one filename convention every step's own [TutorialStep.screenshot]
  /// is relative to.
  String screenshotPath(String outDir, String screenshot) =>
      '$outDir/$name/$screenshot';
}
