/// The behaviour `flutter3d_hardware` requires, as tests a backend runs against
/// itself.
///
/// The interface says what a backend must *have*. Half of what it must *do* is
/// not in any signature: that a clear covers the whole attachment whatever the
/// scissor says, that a rectangle is stated from the top left, that pixels come
/// back rows-from-the-top. Those were prose in `ARCHITECTURE.md` §7, which is to
/// say they were unenforced — and three of them were broken in the second
/// backend, each producing a correct-looking frame with the wrong content and
/// no error anywhere.
///
/// So they are executable now. A backend calls [runDeviceConformance] from its
/// own test suite and finds out.
///
/// **Two tiers, and the split is a correction.** This file used to say it was
/// shader-free as a whole, and that stopped being true the day a check needed a
/// pipeline: five of the twelve now link stages and draw. A new backend
/// following the old promise would have met five failures it could do nothing
/// about, so the lists say which is which — [coreChecks] needs clears, uploads
/// and readback alone, [shaderChecks] needs the bundle. What still needs a
/// shader and is not here (an unbound sampler, a uniform block's members) stays
/// in `ARCHITECTURE.md` §7, and is named there as such.
///
/// **The checks themselves live under `src/`, grouped by what they are testing**
/// — capability queries and readback, shader-bundle and link checks, a pass's
/// own coverage of its attachment, a pipeline switch's binding isolation, and
/// instancing/cube-texture draws — so that finding "the row-order check" or
/// "the scissor-inheritance check" does not mean scrolling past eleven others.
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter_test/flutter_test.dart' show test;

import 'src/core_checks.dart';
import 'src/draw_checks.dart';
import 'src/pass_coverage_checks.dart';
import 'src/pipeline_checks.dart';
import 'src/shader_link_checks.dart';

/// Builds a device to test. Called fresh for each check, because a backend that
/// leaves state behind should fail on its own account rather than on the
/// previous test's.
typedef DeviceFactory = GraphicsDevice Function({
  required int width,
  required int height,
});

/// Raised by a check the backend did not satisfy.
final class ConformanceFailure implements Exception {
  const ConformanceFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Fails the check unless [condition].
///
/// **Not `expect`.** `flutter_test`'s matchers throw `OutsideTestException`
/// when there is no test running, and one of the two backends here cannot run
/// tests at all — Flutter GPU needs Impeller, which a headless `flutter test`
/// does not enable, so its harness is an application. Written with `expect`,
/// three of these checks reported a failure that was the harness rather than
/// the backend, and reported it only on the backend that could not use the
/// harness in the first place.
void require(bool condition, String message) {
  if (!condition) throw ConformanceFailure(message);
}

/// One check: a name and something that throws if the backend is wrong.
typedef ConformanceCheck = ({
  String name,
  Future<void> Function(GraphicsDevice device) run,
});

/// Runs every check against [makeDevice] as ordinary tests.
///
/// [backend] names the implementation in the descriptions, so a suite running
/// two of them says which failed.
///
/// **Not available to every backend.** Flutter GPU needs Impeller enabled,
/// which a headless `flutter test` does not provide — the same reason the
/// golden suite drives an application. That backend runs [conformanceChecks]
/// from an app instead; the checks are the same list either way, which is the
/// point of it being a list.
void runDeviceConformance({
  required String backend,
  required DeviceFactory makeDevice,
}) {
  for (final check in conformanceChecks) {
    test('$backend: ${check.name}', () async {
      await check.run(makeDevice(width: 64, height: 64));
    });
  }
}

/// The checks a backend can run before it has compiled a single shader.
///
/// **This list is why the two exist separately.** The library used to say it
/// was shader-free as a whole, and it stopped being true the day the third
/// check needed a pipeline — so a new backend, following the promise, would
/// have hit five failures it had no way to act on yet. Clears, uploads and
/// readback only: the answers here are the cheapest ones to get, and they are
/// the ones worth having first.
List<ConformanceCheck> get coreChecks => <ConformanceCheck>[
      (name: 'answers every capability query', run: checkCapabilities),
      (name: 'the HDR format it names is renderable', run: checkHdrRenderable),
      (name: 'a clear covers the whole attachment', run: checkClearCoversAll),
      (name: 'uploaded pixels keep their row order', run: checkRowOrder),
      (name: 'a buffer is uploaded for its declared use',
          run: checkGeometryUsage),
      (name: 'a cube takes the mip chain it is handed',
          run: checkCubeMipLevels),
    ];

/// The checks that need the shader bundle and a pipeline.
///
/// Run these once [coreChecks] pass and the bundle loads. What they cover is
/// what no signature states: that a pass starts covering its own attachment and
/// nothing else, that it inherits no clipping from the pass before it, and that
/// a binding made for one pipeline does not follow the next.
List<ConformanceCheck> get shaderChecks => <ConformanceCheck>[
      (name: 'the bundle answers to every name the engine asks for',
          run: checkShaderNames),
      (name: 'a stage pair the engine links does link', run: checkLinking),
      (name: 'a pass covers the whole of its attachment',
          run: checkPassCoversItsAttachment),
      (name: 'a pass does not inherit the previous pass\'s scissor',
          run: checkPassDoesNotInheritScissor),
      (name: 'an instanced draw draws every instance', run: checkInstancedDraw),
      (name: 'a pipeline switch leaves no stale bindings',
          run: checkPipelineSwitchKeepsBindingsApart),
      (name: 'a cube map answers the face a direction points at',
          run: checkCubeFaces),
    ];

/// Every check, as plain functions, for a harness that is not a test runner.
List<ConformanceCheck> get conformanceChecks =>
    <ConformanceCheck>[...coreChecks, ...shaderChecks];
