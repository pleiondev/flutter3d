/// Plays a [TutorialScenario] back — the step sequencing at the centre of
/// `tool/tutorial/shoot.dart`, kept pure: nothing here reaches `dart:io` for
/// a socket or a subprocess directly. [ToolCaller], [FrameWaiter] and
/// [Capturer] are the seam `bin/shoot.dart` wires to a real [McpClient] and
/// [WindowCapture], and `shoot_runner_test.dart` wires to a recorder —
/// which is what makes step sequencing and the expected-filename convention
/// testable with no running modeler and no macOS window in front of
/// anything.
library;

import 'scenario.dart';

/// Calls MCP tool [tool] with [args] and waits for the reply — a document
/// tool or a `ui.*` one, [TutorialStep.tool] verbatim.
typedef ToolCaller =
    Future<void> Function(String tool, Map<String, Object?> args);

/// Waits long enough for the step just called to have painted a frame,
/// before a screenshot is taken of it.
typedef FrameWaiter = Future<void> Function();

/// Saves a screenshot to [outputPath].
typedef Capturer = Future<void> Function(String outputPath);

/// One step [runScenario] finished — [callTool] answered, the frame wait
/// ran, and, if the step named one, [screenshotPath] says where its capture
/// went. Returned in scenario order, for a caller (a test, or
/// `bin/shoot.dart`'s own summary print) to check against what the
/// scenario asked for.
final class ExecutedStep {
  const ExecutedStep({
    required this.tool,
    required this.args,
    this.screenshotPath,
  });

  final String tool;
  final Map<String, Object?> args;
  final String? screenshotPath;
}

/// Plays [scenario] back in order: for each step, calls [callTool], waits
/// via [waitFrame], and — when the step names a [TutorialStep.screenshot] —
/// asks [capture] to save it at [TutorialScenario.screenshotPath] under
/// [outDir].
///
/// One step at a time, never in parallel: a later step's tool call —
/// `ui.setMode`, say — can depend on the mode an earlier step already
/// switched to, and the screen has exactly one state a screenshot can catch
/// at once.
Future<List<ExecutedStep>> runScenario(
  TutorialScenario scenario, {
  required ToolCaller callTool,
  required FrameWaiter waitFrame,
  required Capturer capture,
  required String outDir,
}) async {
  final executed = <ExecutedStep>[];
  for (final step in scenario.steps) {
    await callTool(step.tool, step.args);
    await waitFrame();
    String? path;
    final screenshot = step.screenshot;
    if (screenshot != null) {
      path = scenario.screenshotPath(outDir, screenshot);
      await capture(path);
    }
    executed.add(
      ExecutedStep(tool: step.tool, args: step.args, screenshotPath: path),
    );
  }
  return executed;
}
