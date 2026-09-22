/// The input policy of the viewport, held to the two things `view-03` promises:
/// two fingers change both the distance and the target, and a stylus changes no
/// yaw.
///
/// Several tests apply the intentions to a real `OrbitController` rather than
/// reading the fields of a `CameraIntent`. That is deliberate for the two
/// acceptance cases: "the pinch reported a zoom factor" is a statement about
/// this file, while "the distance changed" is the statement the plan makes, and
/// only the second one catches a factor that is reported with the wrong sign or
/// applied to the wrong axis.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_modeler/src/orbit_gestures.dart';
import 'package:flutter3d_modeler/src/settings.dart' show NavigationScheme;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// Hands an intent to a camera the way the widget layer will, including the
/// negation of the up-positive fields that `CameraIntent` documents.
void apply(OrbitController orbit, CameraIntent intent) {
  if (intent.deltaYaw != 0.0 || intent.deltaPitch != 0.0) {
    orbit.rotate(intent.deltaYaw, -intent.deltaPitch);
  }
  if (intent.panRight != 0.0 || intent.panUp != 0.0) {
    orbit.pan(intent.panRight, -intent.panUp);
  }
  if (intent.zoomBy != 1.0) orbit.zoom(intent.zoomBy);
}

OrbitController freshCamera() =>
    OrbitController(SceneNode(), distance: 4.0, yaw: 0.5, pitch: 0.2);

void main() {
  group('a stylus', () {
    test('drag changes no yaw, and nothing else about the camera', () {
      final OrbitController orbit = freshCamera();
      final Vector3 targetBefore = orbit.target.clone();
      final double yawBefore = orbit.yaw;
      final double pitchBefore = orbit.pitch;
      final double distanceBefore = orbit.distance;

      final OrbitGestures gestures = OrbitGestures();
      gestures.pointerDown(
        1,
        kind: PointerKind.stylus,
        at: const GesturePoint(100, 100),
      );
      for (var step = 1; step <= 20; step++) {
        apply(
          orbit,
          gestures.pointerMove(
            1,
            GesturePoint(100 + step * 7.0, 100 - step * 3.0),
          ),
        );
      }
      gestures.pointerUp(1);

      // The acceptance case of `view-03`. Mutation: make `_roleFor` answer
      // `_Role.orbit` for a stylus, and this fails along with the barrel-button
      // test below it. What it costs a user is the whole point of the rule:
      // every stroke lands somewhere other than where the nib was aimed,
      // because the model turned while they were drawing on it.
      //
      // Note which mutation that is. *Deleting* the stylus line changes
      // nothing — the `kind != PointerKind.mouse` test two lines below it
      // refuses a pen anyway — so the line is a redundancy no test here can
      // defend, and saying otherwise would be describing a run that never
      // happened. It is kept because a later reordering that checks touch
      // first would need it, and the comment beside it in `_roleFor` says so.
      expect(orbit.yaw, yawBefore);
      expect(orbit.pitch, pitchBefore);
      expect(orbit.distance, distanceBefore);
      expect(orbit.target, targetBefore);
    });

    test('with a button held still does not pan', () {
      final OrbitGestures gestures = OrbitGestures();
      gestures.pointerDown(
        1,
        kind: PointerKind.stylus,
        at: const GesturePoint(0, 0),
        button: GestureButton.middle,
        modifiers: const GestureModifiers(shift: true),
      );

      // A pen with a barrel button reports the middle button on some tablets,
      // which is exactly the combination the mouse rules answer with a camera
      // move. Mutation: the same one — `_Role.orbit` for a stylus — and this
      // reports `deltaYaw: 40`, so a user who rests a thumb on the barrel
      // button while shading would watch the model swing away from the nib.
      // The refusal is two lines deep on purpose: the `kind != PointerKind.mouse`
      // test below it means dropping the stylus line alone changes nothing, so
      // that weaker mutation is not one this test could catch.
      expect(
        gestures.pointerMove(1, const GesturePoint(40, 0)).movesCamera,
        isFalse,
      );
    });

    test('resting on the glass does not turn one finger into a pinch', () {
      final OrbitGestures gestures = OrbitGestures();
      gestures.pointerDown(
        1,
        kind: PointerKind.touch,
        at: const GesturePoint(100, 100),
      );
      gestures.pointerDown(
        2,
        kind: PointerKind.stylus,
        at: const GesturePoint(300, 100),
      );

      final CameraIntent intent = gestures.pointerMove(
        1,
        const GesturePoint(140, 100),
      );

      // The hand holding the pen rests on the screen; that is what palm
      // rejection is for and it is not always perfect. Mutation: let `_fingers`
      // return every live pointer rather than the touch ones, and this drag
      // becomes a two-contact gesture — `deltaYaw` drops to zero and a pan of
      // 20 appears instead. A user with a pen in hand would find that one
      // finger no longer orbits.
      expect(gestures.fingerCount, 1);
      expect(intent.deltaYaw, 40.0);
      expect(intent.panRight, 0.0);
      expect(intent.zoomBy, 1.0);
    });
  });

  group('fingers', () {
    test('one orbits', () {
      final OrbitGestures gestures = OrbitGestures();
      gestures.pointerDown(
        1,
        kind: PointerKind.touch,
        at: const GesturePoint(10, 20),
      );
      final CameraIntent intent = gestures.pointerMove(
        1,
        const GesturePoint(40, 5),
      );

      // Mutation: return `_Role.idle` for touch in `_roleFor` and a finger
      // moves nothing at all, which is a viewport that cannot be turned on a
      // tablet. The vertical sign is checked here too: mutation `deltaPitch:
      // dy` instead of `-dy` reports -15 and fails, and a user would find the
      // model tipping the wrong way, which is the complaint that inverted-look
      // settings exist for.
      expect(intent.deltaYaw, 30.0);
      expect(intent.deltaPitch, 15.0);
      expect(intent.panRight, 0.0);
      expect(intent.zoomBy, 1.0);
    });

    test('two change both the distance and the target', () {
      final OrbitController orbit = freshCamera();
      final double yawBefore = orbit.yaw;
      final double distanceBefore = orbit.distance;
      final Vector3 targetBefore = orbit.target.clone();

      final OrbitGestures gestures = OrbitGestures();
      gestures.pointerDown(
        1,
        kind: PointerKind.touch,
        at: const GesturePoint(100, 200),
      );
      gestures.pointerDown(
        2,
        kind: PointerKind.touch,
        at: const GesturePoint(200, 200),
      );

      // The fingers spread from 100 apart to 200 apart and their midpoint
      // slides 30 to the right at the same time: one hand movement, two
      // outputs.
      apply(orbit, gestures.pointerMove(1, const GesturePoint(80, 200)));
      final CameraIntent second = gestures.pointerMove(
        2,
        const GesturePoint(280, 200),
      );
      apply(orbit, second);

      // The acceptance case of `view-03`: two fingers move `distance` *and*
      // `target`. Mutation: drop `zoomBy` from the intent `_touchMove` builds
      // and the distance stays at 4.0 — a tablet where the model cannot be
      // brought closer. Mutation: drop `panRight`/`panUp` and the target stays
      // at the origin, so the model slides out from under a hand that was
      // plainly dragging it.
      expect(orbit.distance, lessThan(distanceBefore));
      expect(orbit.target, isNot(targetBefore));
      expect(orbit.target.x, isNot(0.0));

      // Mutation: delete the touch branch of `pointerMove` altogether, so a
      // finger always goes through the role switch; two fingers then orbit
      // instead of pinching, the distance never moves and the yaw does. A user
      // pinching to look closer would find the model spinning instead.
      expect(orbit.yaw, yawBefore);
    });

    test('pinching closer reports a factor below one, spreading above', () {
      CameraIntent pinch({required double from, required double to}) {
        final OrbitGestures gestures = OrbitGestures();
        gestures.pointerDown(
          1,
          kind: PointerKind.touch,
          at: const GesturePoint(0, 0),
        );
        gestures.pointerDown(
          2,
          kind: PointerKind.touch,
          at: GesturePoint(from, 0),
        );
        return gestures.pointerMove(2, GesturePoint(to, 0));
      }

      // Mutation: invert the ratio in `_touchMove` to
      // `_touchSpread / previousSpread` and both of these fail. A user would
      // find that spreading their fingers pushes the model away, which is the
      // gesture meaning the opposite of what it means in every photo viewer
      // they have ever used.
      expect(pinch(from: 100, to: 200).zoomBy, closeTo(0.5, 1e-9));
      expect(pinch(from: 200, to: 100).zoomBy, closeTo(2.0, 1e-9));
    });

    test('lifting one of two does not fling the camera', () {
      final OrbitGestures gestures = OrbitGestures();
      gestures.pointerDown(
        1,
        kind: PointerKind.touch,
        at: const GesturePoint(100, 100),
      );
      gestures.pointerDown(
        2,
        kind: PointerKind.touch,
        at: const GesturePoint(500, 100),
      );
      gestures.pointerMove(2, const GesturePoint(520, 100));
      gestures.pointerUp(2);

      final CameraIntent intent = gestures.pointerMove(
        1,
        const GesturePoint(105, 100),
      );

      // The finger that is left carries on orbiting from where it is, and the
      // midpoint the pair had is not consulted. Mutation: return `_Role.idle`
      // for touch in `_roleFor` and this reports nothing at all, so a pinch
      // that ends with one finger still down leaves a viewport that has
      // stopped answering the hand on it.
      //
      // Honestly: removing `_resyncTouch()` from `pointerUp` does *not* fail
      // this test, because a single finger never reads the pair's baseline. It
      // fails the three-fingers test below, which is where dropping back to a
      // pair actually happens.
      expect(intent.deltaYaw, 5.0);
      expect(intent.panRight, 0.0);
      expect(intent.zoomBy, 1.0);
    });

    test('a third finger stops the camera, and lifting it starts again', () {
      final OrbitGestures gestures = OrbitGestures();
      for (var id = 1; id <= 3; id++) {
        gestures.pointerDown(
          id,
          kind: PointerKind.touch,
          at: GesturePoint(id * 100.0, 100),
        );
      }

      // Twice, because the first move after the count changes is answered with
      // nothing whatever the guard says — the baseline has just been cleared —
      // and only the second one shows which rule is in force. Mutation: relax
      // `fingers.length != 2` in `_touchMove` to `< 2` and the second of these
      // reports a pan of 30, so a three-finger system gesture — swiping between
      // desktops on macOS, the launcher on Android — drags the model as it goes
      // past.
      expect(
        gestures.pointerMove(2, const GesturePoint(260, 140)).movesCamera,
        isFalse,
      );
      expect(
        gestures.pointerMove(2, const GesturePoint(320, 180)).movesCamera,
        isFalse,
      );

      gestures.pointerUp(3);
      final CameraIntent afterLift = gestures.pointerMove(
        1,
        const GesturePoint(120, 100),
      );

      // Mutation: skip `_resyncTouch()` in `pointerUp`. Dropping from three
      // fingers to two then leaves the pair with no baseline, and the first
      // move of the hand that is still on the glass is swallowed — `panRight`
      // is 0 here rather than 10. A user who lifts a finger mid-gesture would
      // feel the model stick before it starts moving again.
      expect(afterLift.panRight, 10.0);

      // This is a claim about the count and not about which two: `_active` is
      // insertion-ordered, so the first two fingers stay the pair, and no test
      // here would catch a mutation that took the last two instead — the
      // arithmetic is the same either way for a hand this symmetric.
    });
  });

  group('a mouse', () {
    test('orbits on the middle button and pans on shift with it', () {
      CameraIntent drag({required bool shift}) {
        final OrbitGestures gestures = OrbitGestures();
        gestures.pointerDown(
          1,
          kind: PointerKind.mouse,
          at: const GesturePoint(0, 0),
          button: GestureButton.middle,
          modifiers: GestureModifiers(shift: shift),
        );
        return gestures.pointerMove(1, const GesturePoint(25, -10));
      }

      // Mutation: swap the arms of the `modifiers.shift ? _Role.pan :
      // _Role.orbit` conditional and both halves fail. What it costs is a user
      // whose every attempt to slide the model turns it instead, and who
      // cannot get the camera off the axis it started on.
      expect(drag(shift: false).deltaYaw, 25.0);
      expect(drag(shift: false).panRight, 0.0);
      expect(drag(shift: true).panRight, 25.0);
      expect(drag(shift: true).panUp, 10.0);
      expect(drag(shift: true).deltaYaw, 0.0);
    });

    test('leaves the left and right buttons to the tools', () {
      for (final GestureButton button in <GestureButton>[
        GestureButton.primary,
        GestureButton.secondary,
      ]) {
        final OrbitGestures gestures = OrbitGestures();
        gestures.pointerDown(
          1,
          kind: PointerKind.mouse,
          at: const GesturePoint(0, 0),
          button: button,
        );

        // Mutation: drop the `button != GestureButton.middle` test in
        // `_roleFor` and a left-drag orbits, so selecting a loop of edges by
        // dragging across them spins the model instead. Every tool in the
        // application would be fighting the camera for the same button.
        expect(
          gestures.pointerMove(1, const GesturePoint(60, 60)).movesCamera,
          isFalse,
          reason: '$button must not move the camera',
        );
      }
    });

    test('zooms on the wheel, away when the wheel goes down', () {
      final OrbitGestures gestures = OrbitGestures();
      final CameraIntent away = gestures.scroll(
        kind: PointerKind.mouse,
        dy: 100,
      );
      final CameraIntent closer = gestures.scroll(
        kind: PointerKind.mouse,
        dy: -100,
      );

      // Mutation: report the wheel as a pan (`panUp: dy`) and the first two
      // expectations fail — a mouse would have no way to zoom at all, which is
      // the one thing a wheel is for in every 3D application there is.
      // Mutation: negate the exponent and away/closer swap.
      expect(away.zoomBy, greaterThan(1.0));
      expect(away.panUp, 0.0);
      expect(closer.zoomBy, lessThan(1.0));
      // Multiplicative, so a notch out and a notch back land where they
      // started. Mutation: make the factor `1 + dy * k` instead of `exp` and
      // this product is 0.9775 rather than 1 — a user who scrolls out and back
      // in ends up closer than they were every single time.
      expect(away.zoomBy * closer.zoomBy, closeTo(1.0, 1e-12));
    });
  });

  group('a trackpad', () {
    test('a two-finger scroll with Shift pans, and does not zoom', () {
      final OrbitController orbit = freshCamera();
      final double distanceBefore = orbit.distance;
      final OrbitGestures gestures = OrbitGestures();

      final CameraIntent intent = gestures.scroll(
        kind: PointerKind.trackpad,
        dx: 30,
        dy: 20,
        modifiers: const GestureModifiers(shift: true),
      );
      apply(orbit, intent);

      // **The plain two-finger scroll used to land here, and `ux-04` moved
      // it.** Matching the machine's own scrolling was the better answer
      // right up until the live run found the consequence: on a laptop with
      // no middle button and no touch screen there was then no gesture left
      // that orbited at all, under any modifier. So the trackpad's one
      // continuous two-axis gesture carries the camera's main move and
      // panning takes Shift — the modifier it already means on the middle
      // button, so one rule is learnt rather than two.
      //
      // Mutation: send the trackpad's scroll down the same arm as the mouse
      // wheel's, so it zooms; `panRight` goes to zero, the distance changes,
      // and both expectations fail.
      expect(intent.panRight, -30.0);
      expect(intent.zoomBy, 1.0);
      expect(orbit.distance, distanceBefore);
      expect(orbit.target.x, isNot(0.0));
    });

    test('scroll with control zooms, because that is what a browser sends a '
        'pinch as', () {
      final OrbitGestures gestures = OrbitGestures();
      final CameraIntent intent = gestures.scroll(
        kind: PointerKind.trackpad,
        dy: 60,
        modifiers: const GestureModifiers(control: true),
      );

      // Mutation: drop the `modifiers.control` branch and a pinch on a laptop
      // trackpad in Chrome pans instead of zooming, because that is the event
      // the browser delivers it as. The modeller runs in a browser, so this is
      // not a hypothetical platform.
      expect(intent.zoomBy, greaterThan(1.0));
      expect(intent.panUp, 0.0);
    });

    test('a scale gesture reports the step, not the total', () {
      final OrbitGestures gestures = OrbitGestures()..pinchStart();

      final CameraIntent first = gestures.pinchUpdate(2.0);
      final CameraIntent second = gestures.pinchUpdate(4.0);

      // Mutation: return `1 / scale` and forget `_pinchScale`, so each update
      // reports the whole gesture again; applied one after another as they
      // arrive, the second step would take the camera to a sixteenth of the
      // distance instead of a quarter. A user pinching slowly would watch the
      // camera accelerate into the model.
      expect(first.zoomBy, closeTo(0.5, 1e-12));
      expect(second.zoomBy, closeTo(0.5, 1e-12));
    });
  });

  test('an unknown pointer is ignored rather than crashing', () {
    final OrbitGestures gestures = OrbitGestures();

    // A move for a pointer that never went down arrives whenever a drag starts
    // outside the viewport, and the widget layer cannot always tell. Mutation:
    // index `_active` and use the result without the null test, and this
    // throws where a user simply dragged in from the toolbar.
    expect(
      gestures.pointerMove(7, const GesturePoint(1, 1)).movesCamera,
      isFalse,
    );
    expect(gestures.isDragging, isFalse);
  });

  group('ux-04: the two navigation schemes', () {
    /// What a press with [button] and [modifiers] does when dragged.
    CameraIntent dragged({
      required NavigationScheme scheme,
      required PointerKind kind,
      GestureButton button = GestureButton.primary,
      GestureModifiers modifiers = GestureModifiers.none,
      bool toolArmed = false,
    }) {
      final gestures = OrbitGestures(scheme: scheme, toolArmed: toolArmed);
      gestures.pointerDown(
        1,
        kind: kind,
        at: const GesturePoint(10, 10),
        button: button,
        modifiers: modifiers,
      );
      return gestures.pointerMove(1, const GesturePoint(40, 30));
    }

    bool orbits(CameraIntent it) => it.deltaYaw != 0.0 || it.deltaPitch != 0.0;
    bool pans(CameraIntent it) => it.panRight != 0.0 || it.panUp != 0.0;

    group('middle-mouse orbit', () {
      const scheme = NavigationScheme.middleMouseOrbit;

      test('the middle button orbits and Shift with it pans', () {
        expect(
          orbits(
            dragged(
              scheme: scheme,
              kind: PointerKind.mouse,
              button: GestureButton.middle,
            ),
          ),
          isTrue,
        );
        expect(
          pans(
            dragged(
              scheme: scheme,
              kind: PointerKind.mouse,
              button: GestureButton.middle,
              modifiers: const GestureModifiers(shift: true),
            ),
          ),
          isTrue,
        );
      });

      test('Alt with the left button stands in for the middle one', () {
        // The whole of `ux-04`'s own worst finding: a MacBook has no middle
        // button, and `alt` was declared here and read by nothing at all.
        // Mutation: go back to ignoring it — this is a laptop that cannot
        // orbit under any modifier.
        expect(
          orbits(
            dragged(
              scheme: scheme,
              kind: PointerKind.mouse,
              modifiers: const GestureModifiers(alt: true),
            ),
          ),
          isTrue,
        );
        expect(
          pans(
            dragged(
              scheme: scheme,
              kind: PointerKind.mouse,
              modifiers: const GestureModifiers(alt: true, shift: true),
            ),
          ),
          isTrue,
        );
      });

      test('and a plain left drag is still the tools\'', () {
        // Mutation: give the left button the camera under this scheme too.
        // Every box-select and every brush stroke turns the model instead.
        expect(
          dragged(scheme: scheme, kind: PointerKind.mouse).movesCamera,
          isFalse,
        );
      });
    });

    group('left-drag orbit', () {
      const scheme = NavigationScheme.leftDragOrbit;

      test('a left drag on empty space orbits', () {
        expect(
          orbits(dragged(scheme: scheme, kind: PointerKind.mouse)),
          isTrue,
        );
        expect(
          pans(
            dragged(
              scheme: scheme,
              kind: PointerKind.mouse,
              modifiers: const GestureModifiers(shift: true),
            ),
          ),
          isTrue,
        );
      });

      test('but not while a tool has the drag', () {
        // Mutation: orbit whatever the tool is doing. A transform armed with
        // `G` would turn the camera instead of moving the object, and the
        // scheme would be unusable for anything but looking.
        expect(
          dragged(
            scheme: scheme,
            kind: PointerKind.mouse,
            toolArmed: true,
          ).movesCamera,
          isFalse,
        );
      });

      test('and the middle button still orbits, so one habit carries over', () {
        expect(
          orbits(
            dragged(
              scheme: scheme,
              kind: PointerKind.mouse,
              button: GestureButton.middle,
            ),
          ),
          isTrue,
        );
      });

      test('the right button is free-look, and says so as its own pair', () {
        final CameraIntent it = dragged(
          scheme: scheme,
          kind: PointerKind.mouse,
          button: GestureButton.secondary,
        );

        // Mutation: answer a right drag with `deltaYaw`/`deltaPitch`. The
        // camera swings round the target instead of turning where it stands,
        // which is an orbit on a second button rather than a free-look at
        // all.
        expect(it.lookYaw, isNot(0.0));
        expect(it.lookPitch, isNot(0.0));
        expect(orbits(it), isFalse);
        expect(pans(it), isFalse);
        expect(it.movesCamera, isTrue);
      });

      test('and a tool holding the drag does not take the right button', () {
        // A transform armed claims the *primary* drag. Free-look is the
        // camera's own button and stays reachable — which is the point of
        // putting it on one nothing else is using.
        final CameraIntent it = dragged(
          scheme: scheme,
          kind: PointerKind.mouse,
          button: GestureButton.secondary,
          toolArmed: true,
        );

        expect(it.lookYaw, isNot(0.0));
      });
    });

    group('every device, under both schemes', () {
      for (final scheme in NavigationScheme.values) {
        test('${scheme.id}: one finger orbits unless a tool has it', () {
          expect(
            orbits(dragged(scheme: scheme, kind: PointerKind.touch)),
            isTrue,
            reason: 'a touch screen has no second button to fall back to',
          );
          expect(
            dragged(
              scheme: scheme,
              kind: PointerKind.touch,
              toolArmed: true,
            ).movesCamera,
            isFalse,
          );
        });

        test('${scheme.id}: isLooking answers only while one is held', () {
          final gestures = OrbitGestures(scheme: scheme);
          expect(gestures.isLooking, isFalse);

          gestures.pointerDown(
            1,
            kind: PointerKind.mouse,
            at: const GesturePoint(10, 10),
            button: GestureButton.secondary,
          );
          expect(
            gestures.isLooking,
            scheme == NavigationScheme.leftDragOrbit,
            reason:
                'the right button is the context menu under the other '
                'scheme, and the keyboard must stay the tools\'',
          );

          gestures.pointerUp(1);
          expect(gestures.isLooking, isFalse);
        });

        test('${scheme.id}: a pen never moves the camera, armed or not', () {
          // No setting can ask for this. Mutation: let the scheme decide for
          // a stylus too, and painting weights orbits on every stroke.
          expect(
            dragged(scheme: scheme, kind: PointerKind.stylus).movesCamera,
            isFalse,
          );
          expect(
            dragged(
              scheme: scheme,
              kind: PointerKind.stylus,
              toolArmed: true,
            ).movesCamera,
            isFalse,
          );
        });

        test('${scheme.id}: two fingers on a trackpad orbit', () {
          final gestures = OrbitGestures(scheme: scheme);

          // Mutation: pan, which is what this did — and is why a laptop with
          // no middle button and no touch screen could not orbit at all.
          final CameraIntent plain = gestures.scroll(
            kind: PointerKind.trackpad,
            dx: 6,
            dy: 4,
          );
          expect(orbits(plain), isTrue);
          expect(pans(plain), isFalse);

          // Shift keeps panning, the modifier it already means on the middle
          // button, and Ctrl keeps zooming — which is what a browser delivers
          // a trackpad pinch as, not a preference.
          final CameraIntent shifted = gestures.scroll(
            kind: PointerKind.trackpad,
            dx: 6,
            dy: 4,
            modifiers: const GestureModifiers(shift: true),
          );
          expect(pans(shifted), isTrue);
          expect(orbits(shifted), isFalse);

          final CameraIntent zoomed = gestures.scroll(
            kind: PointerKind.trackpad,
            dy: 4,
            modifiers: const GestureModifiers(control: true),
          );
          expect(zoomed.zoomBy, isNot(1.0));
        });

        test('${scheme.id}: a wheel still zooms', () {
          expect(
            OrbitGestures(
              scheme: scheme,
            ).scroll(kind: PointerKind.mouse, dy: 100).zoomBy,
            isNot(1.0),
          );
        });
      }
    });

    test('a trackpad orbit turns the model the way the fingers went', () {
      final OrbitController orbit = freshCamera();
      final double yawBefore = orbit.yaw;

      apply(orbit, OrbitGestures().scroll(kind: PointerKind.trackpad, dx: 20));

      // Applied to a real camera rather than read off the intent: a sign that
      // is wrong here is a trackpad that turns the model the wrong way, which
      // reads as the gesture being broken rather than reversed.
      expect(orbit.yaw, isNot(closeTo(yawBefore, 1e-9)));
    });
  });
}
