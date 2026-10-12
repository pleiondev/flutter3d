/// Every recipe builds its scene and draws it on the software rasteriser,
/// which is what a test without Impeller opens; and every recipe stays a
/// recipe, forty lines of code or fewer.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_cookbook/buy_button.dart';
import 'package:flutter3d_cookbook/campfire.dart';
import 'package:flutter3d_cookbook/decode_in_a_worker.dart';
import 'package:flutter3d_cookbook/falling_crates.dart';
import 'package:flutter3d_cookbook/follow_a_ball.dart';
import 'package:flutter3d_cookbook/glowing_sign.dart';
import 'package:flutter3d_cookbook/load_and_orbit.dart';
import 'package:flutter3d_cookbook/material_ladder.dart';
import 'package:flutter3d_cookbook/pendulum_slider.dart';
import 'package:flutter3d_cookbook/placeholder_while_loading.dart';
import 'package:flutter3d_cookbook/play_a_clip.dart';
import 'package:flutter3d_cookbook/read_a_probe.dart';
import 'package:flutter3d_cookbook/runner_at_60.dart';
import 'package:flutter3d_cookbook/scene_without_widgets.dart';
import 'package:flutter3d_cookbook/scenes_in_a_list.dart';
import 'package:flutter3d_cookbook/spin_a_shape.dart';
import 'package:flutter3d_cookbook/sun_and_shadow.dart';
import 'package:flutter3d_cookbook/tap_to_pick.dart';
import 'package:flutter3d_cookbook/ten_times_faster.dart';
import 'package:flutter3d_cookbook/twin_over_rest.dart';
import 'package:flutter_test/flutter_test.dart';

/// Each recipe by its file's name, as the widget its `main` runs.
final Map<String, Widget Function()> recipes = <String, Widget Function()>{
  'buy_button': BuyButton.new,
  'campfire': Campfire.new,
  'decode_in_a_worker': DecodeInAWorker.new,
  'falling_crates': FallingCrates.new,
  'follow_a_ball': FollowABall.new,
  'glowing_sign': GlowingSign.new,
  'load_and_orbit': LoadAndOrbit.new,
  'material_ladder': MaterialLadder.new,
  'pendulum_slider': PendulumSlider.new,
  'placeholder_while_loading': PlaceholderWhileLoading.new,
  'play_a_clip': PlayAClip.new,
  'read_a_probe': ReadAProbe.new,
  'runner_at_60': RunnerAt60.new,
  'scene_without_widgets': SceneWithoutWidgets.new,
  'scenes_in_a_list': ScenesInAList.new,
  'spin_a_shape': SpinAShape.new,
  'sun_and_shadow': SunAndShadow.new,
  'tap_to_pick': TapToPick.new,
  'ten_times_faster': TenTimesFaster.new,
  'twin_over_rest': TwinOverRest.new,
};

/// The lines of [source] that are code: not blank, not a comment.
int linesOfCode(String source) => source
    .split('\n')
    .where((line) => line.trim().isNotEmpty && !line.trim().startsWith('//'))
    .length;

void main() {
  test('the cookbook is twenty recipes, each one listed here', () {
    final files = Directory('lib')
        .listSync()
        .whereType<File>()
        .map((file) => file.uri.pathSegments.last.replaceAll('.dart', ''))
        .toSet();
    expect(files, recipes.keys.toSet());
    expect(files, hasLength(20));
  });

  for (final MapEntry(key: name, value: recipe) in recipes.entries) {
    test('$name is forty lines of code or fewer', () {
      expect(
        linesOfCode(File('lib/$name.dart').readAsStringSync()),
        lessThanOrEqualTo(40),
      );
    });

    testWidgets('$name builds its scene and draws it', (tester) async {
      // A small frame: the software rasteriser pays for every pixel.
      await tester.pumpWidget(
        MaterialApp(
          home: Center(child: SizedBox(width: 200, height: 120, child: recipe())),
        ),
      );
      // The device opens, the models decode on an isolate, and a frame's
      // pixels are turned into an image: each of them real time, not the
      // test's clock.
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(tester.takeException(), isNull);
      expect(find.byType(Flutter3dView), findsWidgets);
      final frames = tester.widgetList<RawImage>(find.byType(RawImage));
      expect(
        frames.where((frame) => frame.image != null),
        isNotEmpty,
        reason: 'no frame reached the screen',
      );
      // Gone, and every timer it started run out: a source polled once a
      // minute is asked one last time and stops.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(minutes: 2));
    });
  }
}
