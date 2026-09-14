/// `tool/tutorial/shoot.dart` — plays one scenario back against a running
/// `flutter3d_modeler` and saves a screenshot per step. `tut-00`'s own row
/// in `doc/model-editor-plan.md`: "peregenerация всех картинок — одна
/// команда" (regenerating every picture is one command) — this is that
/// command, for one case at a time.
///
///     flutter run -d macos --dart-define=mcpPort=0 \
///         -a --window=1440x900
///     dart run tool/tutorial/bin/shoot.dart \
///         --scenario tool/tutorial/test/fixtures/smoke_scenario.json \
///         --out cloud/server/web/assets/learn/modeler
///
/// Needs a real GUI build of the modeler running with `--mcp-port` — there
/// is no such window in the environment this was written in, so only the
/// pure-logic pieces (scenario parsing, step sequencing, the
/// expected-filename convention, in `package:tutorial`) were exercised
/// while writing it. An actual `--session`/`--process` pair against a live
/// window, and the `screencapture` permission prompt it needs the first
/// time, are unverified here and need a real macOS run to confirm — see
/// this repository's `tut-00` gaps journal if that run turns up a
/// surprise.
library;

import 'dart:io';

import 'package:args/args.dart';
import 'package:tutorial/tutorial.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption(
      'scenario',
      help: 'path to a scenario JSON file (TutorialScenario.parse\'s shape)',
      mandatory: true,
    )
    ..addOption(
      'session',
      help:
          'path to mcp-session.json; defaults to the sandboxed app-support '
          'path the modeler writes it under — an unverified guess (see this '
          'file\'s own doc comment), so pass this explicitly on a real run '
          'until that is confirmed',
      defaultsTo: _defaultSessionPath(),
    )
    ..addOption(
      'out',
      help:
          'base output directory screenshots are saved under, one '
          'subdirectory per scenario name',
      defaultsTo: 'cloud/server/web/assets/learn/modeler',
    )
    ..addOption(
      'process',
      help: 'the process name window_id.swift looks for',
      defaultsTo: 'flutter3d_modeler',
    )
    ..addOption(
      'frame-delay-ms',
      help: 'how long to wait after a tool call before screenshotting it',
      defaultsTo: '150',
    )
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'print this usage and exit',
    );

  final ArgResults args;
  try {
    args = parser.parse(arguments);
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(parser.usage);
    exitCode = 64; // EX_USAGE
    return;
  }

  if (args.flag('help')) {
    stdout.writeln(parser.usage);
    return;
  }

  // `mandatory: true` on `--scenario` is only checked the first time
  // something reads it back — `parse()` itself never throws for a missing
  // one — so that first read has to be guarded here rather than above.
  final String scenarioPath;
  try {
    scenarioPath = args.option('scenario')!;
  } on ArgumentError catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(parser.usage);
    exitCode = 64; // EX_USAGE
    return;
  }

  final TutorialScenario scenario;
  final McpSession session;
  try {
    final scenarioFile = File(scenarioPath);
    if (!scenarioFile.existsSync()) {
      throw FormatException('no scenario at ${scenarioFile.path}');
    }
    scenario = TutorialScenario.parse(scenarioFile.readAsStringSync());
    session = McpSession.readFile(File(args.option('session')!));
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 1;
    return;
  }

  final client = McpClient(session);
  final windowIdScript = File.fromUri(
    Platform.script.resolve('../window_id.swift'),
  ).path;
  final capture = WindowCapture(windowIdScript: windowIdScript);
  final processName = args.option('process')!;
  final frameDelay = Duration(
    milliseconds: int.parse(args.option('frame-delay-ms')!),
  );

  await client.initialize();
  try {
    // One window id for the whole scenario — the window this app opens does
    // not change mid-run, and looking it up once keeps every screenshot on
    // the same target even if a later step opens a second window (a dialog)
    // that briefly outranks it in the window list.
    int? windowId;
    final executed = await runScenario(
      scenario,
      callTool: (tool, args) async {
        await client.callTool(tool, args);
      },
      waitFrame: () => Future<void>.delayed(frameDelay),
      capture: (outputPath) async {
        windowId ??= await capture.findWindowId(processName);
        await capture.capture(windowId!, outputPath);
      },
      outDir: args.option('out')!,
    );

    final shot = executed.where((step) => step.screenshotPath != null).length;
    stdout.writeln(
      'scenario "${scenario.name}": ${executed.length} steps, $shot '
      'screenshots',
    );
  } finally {
    client.close();
  }
}

/// A best-effort default for where the modeler's sandboxed app-support
/// directory holds `mcp-session.json` — `dev.flutter3d.modeler`
/// (`Configs/AppInfo.xcconfig`'s own `PRODUCT_BUNDLE_IDENTIFIER`) under
/// `com.apple.security.app-sandbox`'s container. **Unconfirmed**: nothing
/// in this environment could run the actual app to see where
/// `getApplicationSupportDirectory()` really lands inside the sandbox —
/// pass `--session` explicitly until a real run confirms this.
String _defaultSessionPath() {
  final home = Platform.environment['HOME'] ?? '';
  return '$home/Library/Containers/dev.flutter3d.modeler/Data/Library/'
      'Application Support/mcp-session.json';
}
