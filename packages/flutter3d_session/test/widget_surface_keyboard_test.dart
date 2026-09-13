/// `wg-01`'s keyboard-at-focus item, and the honest limit found while
/// building it.
///
/// **What is real and tested below:** a tap inside a `WidgetSurface` can
/// request focus for a control inside it, resolved by that surface's own
/// isolated `FocusManager` — proven from the SDK's own source, not assumed:
/// `FocusNode._reparent` reads its manager off `context.owner.focusManager`
/// (`focus_manager.dart`), where `owner` is the `Element`'s own `BuildOwner`
/// — so a node built under this pipeline's private `BuildOwner` answers to
/// *this* pipeline's manager, never the running application's.
///
/// **What is not, and could not be made to work here:** a real `TextField`
/// receiving typed characters through the platform's text input channel.
/// Two independent walls, both found by reproducing the failure rather than
/// reading about it:
///
/// 1. `TextField` finds its own `EditableTextState` through a `GlobalKey`,
///    and `GlobalKey.currentState` is `WidgetsBinding.instance.buildOwner!
///    ._globalKeyRegistry[this]` (`framework.dart`) — the *application's*
///    single global registry, not `context.owner`'s. An element built under
///    any other `BuildOwner`, this pipeline's included, registers itself
///    somewhere that lookup never checks. Reproduced: tapping a `TextField`
///    here throws `Null check operator used on a null value` inside
///    `TextSelectionGestureDetectorBuilder.editableText` — every time, with
///    no other pipeline complexity involved.
/// 2. Even a bare `EditableText` (no `TextField`, no `GlobalKey`) still
///    calls `View.of(context)` unconditionally inside
///    `EditableTextState.textInputConfiguration` (`editable_text.dart`), to
///    tag the platform connection with a `viewId`. `WidgetSurfacePipeline`
///    has no `View` ancestor by design — it builds its own `RenderView`
///    directly, because the surface is not a second window. Reproduced
///    twice: without a `View` ancestor, `View.of` throws outright; a `View`
///    widget added inside the pipeline's own tree throws its own assertion
///    on mount — "cannot maintain an independent render tree at its current
///    location" — because `View` refuses to attach under an
///    already-attached `RenderObjectToWidgetAdapter`.
///
/// Neither wall is this package's to fix: both are the Flutter SDK's own
/// single-application assumptions, upstream of anything a pipeline's own
/// code can route around. `wg-01`'s own write-up in `doc/tooling-plan.md`
/// names this plainly rather than shipping a `TextField` that looks wired
/// up and silently drops every keystroke.
library;

import 'package:flutter/widgets.dart' hide Matrix4;
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_session/flutter3d_session.dart';
import 'package:flutter_test/flutter_test.dart';

GraphicsDevice _device() =>
    CpuDevice(width: 4, height: 4, shaders: CpuShaderLibrary(builtinCpuShaders()));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'a tap requests focus for a control inside the surface, on the '
    'surface\'s own isolated FocusManager rather than the real one',
    (tester) async {
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      var tapped = false;
      final surface = WidgetSurface(
        device: _device(),
        width: 2.0,
        height: 1.0,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            tapped = true;
            focusNode.requestFocus();
          },
          child: Focus(focusNode: focusNode, child: const ColoredBox(color: Color(0xFF224466))),
        ),
      );
      addTearDown(surface.dispose);

      // Nothing here ever called `tester.pumpWidget` on this widget — the
      // real application tree, whatever it is, is untouched — so this is
      // the isolated manager's own opinion, not a borrowed one.
      expect(focusNode.hasFocus, isFalse);

      const pointer = 5;
      surface.pipeline.announcePointer(pointer, added: true);
      surface.pipeline.dispatchAtUv(
        const Offset(0.5, 0.5),
        (local) => PointerDownEvent(pointer: pointer, position: local),
      );
      surface.pipeline.dispatchAtUv(
        const Offset(0.5, 0.5),
        (local) => PointerUpEvent(pointer: pointer, position: local),
      );
      surface.pipeline.announcePointer(pointer, added: false);

      // Focus changes are applied on a scheduled microtask
      // (`FocusManager._markNeedsUpdate`) rather than synchronously —
      // `pump(Duration.zero)` drains it the same way it would for the real
      // application tree.
      await tester.pump();

      expect(tapped, isTrue);
      expect(focusNode.hasFocus, isTrue);
    },
  );

  testWidgets(
    'two surfaces hold focus independently — each has its own manager, so '
    'focusing one does not touch the other\'s',
    (tester) async {
      final focusA = FocusNode();
      final focusB = FocusNode();
      addTearDown(focusA.dispose);
      addTearDown(focusB.dispose);

      WidgetSurface build(FocusNode node) => WidgetSurface(
        device: _device(),
        width: 2.0,
        height: 1.0,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: node.requestFocus,
          child: Focus(focusNode: node, child: const ColoredBox(color: Color(0xFF224466))),
        ),
      );

      final surfaceA = build(focusA);
      final surfaceB = build(focusB);
      addTearDown(surfaceA.dispose);
      addTearDown(surfaceB.dispose);

      Future<void> tap(WidgetSurface surface, int pointer) async {
        surface.pipeline.announcePointer(pointer, added: true);
        surface.pipeline.dispatchAtUv(
          const Offset(0.5, 0.5),
          (local) => PointerDownEvent(pointer: pointer, position: local),
        );
        surface.pipeline.dispatchAtUv(
          const Offset(0.5, 0.5),
          (local) => PointerUpEvent(pointer: pointer, position: local),
        );
        surface.pipeline.announcePointer(pointer, added: false);
        await tester.pump();
      }

      await tap(surfaceA, 10);
      expect(focusA.hasFocus, isTrue);
      expect(focusB.hasFocus, isFalse);

      await tap(surfaceB, 11);
      expect(
        focusB.hasFocus,
        isTrue,
        reason: 'each surface has its own isolated manager, so nothing '
            'about focusing B needed A to release anything first',
      );
      expect(
        focusA.hasFocus,
        isTrue,
        reason: 'and for the same reason, B taking focus never told A\'s '
            'own manager anything happened — the two are not one shared '
            'focus tree, which is exactly what keeps them from colliding, '
            'and exactly why nothing here can arbitrate "the one focused '
            'surface" for a real keyboard the way a single shared '
            'FocusManager would',
      );
    },
  );
}
