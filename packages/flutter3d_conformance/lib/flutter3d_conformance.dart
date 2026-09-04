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
/// pipeline: twenty-three of the thirty-one link stages and draw. A new
/// backend following the old promise would have met twenty-three shader checks
/// it could do nothing about, so the lists say which is which — [coreChecks]
/// needs clears, uploads and readback alone, [shaderChecks] needs the bundle.
/// The tiers answer "can this be asked yet", not "does this matter": the
/// buffer-usage check sat in the first list for as long as it asserted
/// nothing, and asking it properly is what moved it to the second. What still
/// needs a shader and is not here (an unbound sampler) stays in
/// `ARCHITECTURE.md` §7, and is named there as such. A uniform block's members
/// used to be on that list and are checked now — see
/// [checkUniformMemberMismatchIsRefused], which asks a backend whether it
/// reflects its shaders before holding it to a rule only reflection can keep.
///
/// **The counts in this file are held to the lists by `tool/structure.dart`.**
/// They were three different wrong answers at once — "five of the twelve", "the
/// seven checks", "two of the nine rules" — because a number in a doc comment
/// is a number nobody recounts, and these are a reader's only map of how much
/// of §7 the suite covers.
///
/// **The checks themselves live under `src/`, grouped by what they are testing**
/// — capability queries and readback, shader-bundle and link checks, a pass's
/// own coverage of its attachment, a pipeline switch's binding isolation,
/// instancing and cube-texture draws, the blend constant, a multisample
/// resolve, and the id stage picking reads back — so that finding "the
/// row-order check" or "the scissor-inheritance check" does not mean scrolling
/// past eleven others.
///
/// **A check may decline**, and [ConformanceDeclined] is how: a backend that
/// answers false to the capability a check is about is not asked, and the
/// harness prints which backend declined and why rather than a green line for
/// something it never ran.
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter_test/flutter_test.dart' show markTestSkipped, test;

import 'src/blend_checks.dart';
import 'src/compressed_checks.dart';
import 'src/core_checks.dart';
import 'src/draw_checks.dart';
import 'src/loaded_bundle_checks.dart';
import 'src/multisample_checks.dart';
import 'src/pass_coverage_checks.dart';
import 'src/picking_checks.dart';
import 'src/pipeline_checks.dart';
import 'src/refusal_checks.dart';
import 'src/render_target_checks.dart';
import 'src/sampling_checks.dart';
import 'src/semantics_checks.dart';
import 'src/shader_link_checks.dart';
import 'src/stencil_checks.dart';

export 'src/loaded_bundle_checks.dart'
    show OwnShaderSection, loadedBundleChecks;

/// Builds a device to test. Called fresh for each check, because a backend that
/// leaves state behind should fail on its own account rather than on the
/// previous test's.
typedef DeviceFactory =
    GraphicsDevice Function({required int width, required int height});

/// Raised by a check the backend did not satisfy.
final class ConformanceFailure implements Exception {
  const ConformanceFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Raised by a check the backend is not in a position to answer at all.
///
/// **Not a failure, and — this is the point — not a silent pass either.** A
/// check that cannot run on a backend used to `return`, which the harnesses
/// reported as PASS: the multisample check would have said the software
/// rasteriser resolves correctly, which it does not do at all. Both harnesses —
/// [runDeviceConformance] and the application the Impeller backend runs from —
/// report it as a skip instead, and both print [reason], because the person
/// running a device harness is usually not the person who wrote the check.
///
/// [decline] builds one, and stamps the backend's own type on the front so the
/// line says who declined as well as why.
final class ConformanceDeclined implements Exception {
  const ConformanceDeclined(this.reason);
  final String reason;
  @override
  String toString() => reason;
}

/// Ends the check with no verdict: [device] cannot be asked this, and [why]
/// says what it answered.
///
/// [why] is a sentence about the capability, not about the check — "answers
/// false to supportsOffscreenMsaa, and multisamples nothing" — because it is
/// read on its own, beside a check name, by somebody holding a phone.
Never decline(GraphicsDevice device, String why) =>
    throw ConformanceDeclined('${device.runtimeType} $why');

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
///
/// [ownShaders] is the backend's own shaders as the section of a loadable
/// bundle — see [OwnShaderSection] — and adds the loaded-library check when
/// given. Optional, so a backend can pass the rest before it can pack one;
/// every backend in this repository passes it.
void runDeviceConformance({
  required String backend,
  required DeviceFactory makeDevice,
  Future<OwnShaderSection?> Function()? ownShaders,
}) {
  final checks = ownShaders == null
      ? conformanceChecks
      : conformanceChecksWith(ownShaders);
  for (final check in checks) {
    test('$backend: ${check.name}', () async {
      final device = makeDevice(width: 64, height: 64);
      try {
        await check.run(device);
      } on ConformanceDeclined catch (declined) {
        // Skipped, not passed. A runner that prints a green line for a check
        // the backend never ran is the same lie as the `return` this replaced,
        // only louder.
        markTestSkipped('$backend: ${declined.reason}');
      } finally {
        // **A device per check and none of them disposed**, which on the one
        // backend where dispose actually frees anything meant a suite that
        // leaked every texture it made. In a `finally` so a failing check
        // still lets go — a check that fails is exactly when the next one
        // wants a clean device.
        device.dispose();
      }
    });
  }
}

/// The checks a backend can run before it has compiled a single shader.
///
/// **This list is why the two exist separately.** The library used to say it
/// was shader-free as a whole, and it stopped being true the day the third
/// check needed a pipeline — so a new backend, following the promise, would
/// have hit twenty-three shader checks it had no way to act on yet. Clears,
/// uploads and readback only: the answers here are the cheapest ones to get,
/// and they are the ones worth having first.
List<ConformanceCheck> get coreChecks => <ConformanceCheck>[
  (name: 'answers every capability query', run: checkCapabilities),
  (name: 'the HDR format it names is renderable', run: checkHdrRenderable),
  (name: 'a clear covers the whole attachment', run: checkClearCoversAll),
  (name: 'uploaded pixels keep their row order', run: checkRowOrder),
  (name: 'a cube takes the mip chain it is handed', run: checkCubeMipLevels),
  (
    name: 'a pixel buffer of the wrong size is refused',
    run: checkPixelBufferSize,
  ),
  (
    name: 'a readback returns the frame before',
    run: checkReadbackReturnsTheFrameBefore,
  ),
];

/// The checks that need the shader bundle and a pipeline.
///
/// Run these once [coreChecks] pass and the bundle loads. What they cover is
/// what no signature states: that a pass starts covering its own attachment and
/// nothing else, that it inherits no clipping from the pass before it, and that
/// a binding made for one pipeline does not follow the next.
List<ConformanceCheck> get shaderChecks => <ConformanceCheck>[
  (
    name: 'the bundle answers to every name the engine asks for',
    run: checkShaderNames,
  ),
  (name: 'a stage pair the engine links does link', run: checkLinking),
  (
    name: 'a pass covers the whole of its attachment',
    run: checkPassCoversItsAttachment,
  ),
  (
    name: 'a pass does not inherit the previous pass\'s scissor',
    run: checkPassDoesNotInheritScissor,
  ),
  (
    name: 'a readback of a region reads that region',
    run: checkReadbackOfRegion,
  ),
  (name: 'an instanced draw draws every instance', run: checkInstancedDraw),
  (
    name: 'a buffer is uploaded for its declared use, and draws as it',
    run: checkGeometryUsage,
  ),
  (
    name: 'a pipeline switch leaves no stale bindings',
    run: checkPipelineSwitchKeepsBindingsApart,
  ),
  (
    name: 'a cube map answers the face a direction points at',
    run: checkCubeFaces,
  ),
  (
    name: 'a compressed format it supports samples its colour back',
    run: checkCompressedTextureSamples,
  ),
  (
    name: 'a pass renders into a cube face and a mip',
    run: checkRenderToCubeFaceAndMip,
  ),
  // The other half of that rule, which the clears above cannot ask about
  // because a clear covers the whole attachment however the viewport is set.
  (
    name: 'a pass\'s initial viewport covers the level',
    run: checkPassViewportCoversTheLevel,
  ),
  // Two of the fourteen rules ARCHITECTURE.md §7.2 states and that no
  // signature can. Both are decisions a new backend has to make deliberately,
  // and neither produces an error when made the other way round.
  (
    name: 'a null sampler means linear and repeat',
    run: checkNullSamplerRepeats,
  ),
  (
    name: 'setDepthWrite(false) stops depth writes',
    run: checkDepthWriteIsHonoured,
  ),
  // The half of `bindUniformBlock` that was named as outside this suite for as
  // long as it existed, and under which the two hardware backends drifted
  // apart: a block missing a member the caller wrote.
  (
    name: 'a block missing a member the caller named is refused',
    run: checkUniformMemberMismatchIsRefused,
  ),
  // The clamp the HAL promises for `SamplerOptions.anisotropy`: a request
  // above `maxAnisotropy` is lowered, never refused, on every backend.
  (
    name: 'a sampler asking for more anisotropy than there is is accepted',
    run: checkAnisotropicSamplerAccepted,
  ),
  // The stencil in the shape the x-ray stage uses it: a mark that leaves the
  // picture alone, then `equal` and `notEqual` reading it back.
  (
    name: 'a stencil test keeps what it should',
    run: checkStencilKeepsWhatItShould,
  ),
  // The half of the stencil rule that every other pass hides by tidying up
  // after itself. This one deliberately does not.
  (
    name: 'a pass starts with the stencil test off',
    run: checkPassStartsWithStencilOff,
  ),
  // The two capabilities that differ across the three backends, asked in the
  // direction that matters: what a backend that answers no must do instead.
  (
    name: 'wireframe is drawn as edges or refused, never filled',
    run: checkWireframeIsDrawnOrRefused,
  ),
  (
    name: 'every primitive type is assembled as itself or refused',
    run: checkPrimitiveTypesAreDrawnOrRefused,
  ),
  // The four BlendFactor values that read a constant, which for as long as
  // nothing could set one were the enum's dead corner: two backends drew the
  // term as zero and said nothing.
  (
    name: 'a blend constant reaches the blend, or is refused',
    run: checkBlendColorReachesTheBlend,
  ),
  // The three multisampling fields of the HAL, which nothing held. The one
  // check here a backend may decline — see `decline`, and the software
  // rasteriser, which multisamples nothing and says so.
  (
    name: 'a multisample resolve resolves',
    run: checkMultisampleResolveResolves,
  ),
  // Picking, drawn and decoded on the software backend alone until now — and
  // the only draw in this suite through the standard five-attribute layout.
  (
    name: 'an object id survives the draw and the readback',
    run: checkObjectIdDrawsAndDecodes,
  ),
];

/// Every check, as plain functions, for a harness that is not a test runner.
List<ConformanceCheck> get conformanceChecks => <ConformanceCheck>[
  ...coreChecks,
  ...shaderChecks,
];

/// [conformanceChecks] and the check that needs the backend's own shaders
/// as bytes — see [loadedBundleChecks] for why that one is a function.
List<ConformanceCheck> conformanceChecksWith(
  Future<OwnShaderSection?> Function() ownShaders,
) => <ConformanceCheck>[
  ...conformanceChecks,
  ...loadedBundleChecks(ownShaders),
];
