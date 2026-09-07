/// The view over the map: where it can be pushed, how far it can be pulled
/// back, and what it does on the first frame.
library;

import 'dart:typed_data';

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_strategy/flutter3d_game_strategy.dart';
import 'package:flutter_test/flutter_test.dart';

/// Eighty metres square, flat unless [height] says otherwise.
Heightfield _ground([double Function(int column, int row)? height]) {
  const int samples = 41;
  final heights = Float32List(samples * samples);
  if (height != null) {
    for (var row = 0; row < samples; row++) {
      for (var column = 0; column < samples; column++) {
        heights[row * samples + column] = height(column, row);
      }
    }
  }
  return Heightfield(
    columns: samples,
    rows: samples,
    cellSize: 2.0,
    heights: heights,
  );
}

void main() {
  group('panning', () {
    test('starts in the middle of the map', () {
      final camera = MapCamera(ground: _ground());

      expect(camera.focus.x, closeTo(40.0, 1e-9));
      expect(camera.focus.z, closeTo(40.0, 1e-9));
    });

    test('moves the view by what it was pushed', () {
      final camera = MapCamera(ground: _ground())..pan(10.0, -6.0);

      expect(camera.focus.x, closeTo(50.0, 1e-9));
      expect(camera.focus.z, closeTo(34.0, 1e-9));
    });

    test('stops at the edge of the ground', () {
      // Mutation: drop the clamp. The view then leaves the map, and a player
      // looking at the void has nothing to steer back by.
      final camera = MapCamera(ground: _ground())..pan(500.0, 500.0);

      expect(camera.focus.x, closeTo(80.0, 1e-9));
      expect(camera.focus.z, closeTo(80.0, 1e-9));

      camera.pan(-500.0, -500.0);
      expect(camera.focus.x, closeTo(0.0, 1e-9));
      expect(camera.focus.z, closeTo(0.0, 1e-9));
    });
  });

  group('zooming', () {
    test('is bounded at both ends', () {
      const tuning = MapCameraTuning(minDistance: 10.0, maxDistance: 50.0);
      final camera = MapCamera(ground: _ground(), tuning: tuning);

      camera.zoom(1000.0);
      expect(camera.distance, closeTo(50.0, 1e-9));

      camera.zoom(-1000.0);
      expect(camera.distance, closeTo(10.0, 1e-9));
    });
  });

  group('placing', () {
    test('puts the eye above and behind what it watches', () {
      final camera = MapCamera(ground: _ground())..place(1.0 / 60.0);

      expect(camera.target.x, closeTo(camera.focus.x, 1e-6));
      expect(camera.eye.y, greaterThan(camera.target.y));
      expect(
        camera.eye.z,
        greaterThan(camera.target.z),
        reason: 'behind along +Z',
      );
    });

    test('cuts on the first frame and eases after it', () {
      // The rig's own rule, and the reason this camera turns it: a game that
      // opened with the camera flying in from wherever the vectors started
      // would look broken. Mutation: hand the rig a fresh instance every frame
      // — every frame is then a first frame and the view never eases at all.
      final camera = MapCamera(ground: _ground())..place(1.0 / 60.0);
      final settled = camera.eye.clone();

      camera
        ..pan(20.0, 0.0)
        ..place(1.0 / 60.0);

      expect(
        camera.eye.x,
        greaterThan(settled.x),
        reason: 'it moved towards the new focus',
      );
      expect(
        camera.eye.x,
        lessThan(camera.focus.x),
        reason: 'and did not arrive in one frame',
      );
    });

    test('rides the ground rather than cutting into it', () {
      // Mutation: drop `_focus.y = ground.heightAt(...)`. The view over a hill
      // then sits at the height of the valley and the hill grows through it.
      final flat = MapCamera(ground: _ground())..place(1.0 / 60.0);
      final hill = MapCamera(ground: _ground((column, _) => column * 0.5))
        ..place(1.0 / 60.0);

      expect(
        hill.target.y,
        greaterThan(flat.target.y + 5.0),
        reason: 'the middle of the hill is well above the flat',
      );
      expect(hill.eye.y, greaterThan(hill.target.y));
    });
  });
}
