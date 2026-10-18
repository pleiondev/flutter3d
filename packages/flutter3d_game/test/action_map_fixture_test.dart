/// The action map an older build saved, opened by this one.
///
///     flutter test test/action_map_fixture_test.dart
///
/// `test/fixtures/v<N>/controls.actions.json` is minted once at each
/// version and never re-minted: when this goes red, a player's saved
/// controls have stopped loading.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the version 1 map reads, its axes kept and written back', () {
    final json =
        jsonDecode(
              File('test/fixtures/v1/controls.actions.json').readAsStringSync(),
            )
            as Map<String, Object?>;
    final map = ActionMap.fromJson(
      json,
      defaults: () => ActionMap(actions: ActionSet.common),
    );
    // Mutation: drop a binding kind from `ActionBinding.fromJson` and keep
    // nothing of it, and the gyro or the composite is gone from the save.
    expect(map.axesToJson(), hasLength((json['axes']! as List).length));
    expect(map.buttons.sources, isNotEmpty);
  });
}
