/// Rings in the colour a player chose, and roles moved apart for the
/// player's colour vision.
///
///     flutter test test/colour_roles_test.dart
///
/// The pair here is a red and a green ΔE 122 apart to normal eyes and 7
/// apart to a deutan's, 40 to a protan's and 124 to a tritan's: the colours
/// a team or a key is most often told apart by, and the pair that fails most
/// often.
library;

import 'package:flutter/painting.dart' show Color;
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_ui/access.dart';
import 'package:flutter_test/flutter_test.dart';

const Color _red = Color(0xFFD02020);
const Color _green = Color(0xFF20A020);

ColorRoles _roles() => ColorRoles(<ColorRole>[
  const ColorRole('ours', 'Our side', _red),
  const ColorRole('theirs', 'Their side', _green),
]);

GameSettings _seeing(int vision) =>
    const GameSettings().withValue(GameSettingKeys.colorVision, vision);

void main() {
  group('RoleRings', () {
    test("a role's ring is the player's choice, read every time", () {
      var config = const GameSettings();
      final rings = RoleRings(_roles(), () => config);
      expect(rings.of('ours', fallback: _green), outlineColorOf(_red));
      // The player picks Okabe and Ito's sky blue, the third choice.
      config = config.withValue(GameSettingKeys.colorRole('ours'), 3);
      // Mutation: read the settings once, at construction — the ring keeps
      // red.
      expect(
        rings.of('ours', fallback: _green),
        outlineColorOf(ColorRoles.palette[2]),
      );
    });

    test('a role the game does not have is its fallback', () {
      final rings = RoleRings(_roles(), () => const GameSettings());
      expect(rings.has('key.brass'), isFalse);
      expect(rings.has('ours'), isTrue);
      // Mutation: answer the first role for a name it does not know — red.
      expect(
        rings.of('key.brass', fallback: const Color(0xFFFFFFFF)),
        Vector3(1.0, 1.0, 1.0),
      );
    });
  });

  group('RolesApart', () {
    test('with no colour vision set there is nothing to move', () {
      expect(
        // Mutation: settle for a deutan when nothing is set — `theirs` moves.
        RolesApart(
          _roles(),
        ).choicesFor(<String>['ours', 'theirs'], const GameSettings()),
        isEmpty,
      );
    });

    test('a deutan has the second of a colliding pair moved', () {
      final apart = RolesApart(_roles());
      // Deutan is the second kind; the setting counts from one.
      final moved = apart.choicesFor(<String>['ours', 'theirs'], _seeing(2));
      // Mutation: settle against nothing — nothing collides and nothing
      // moves. Mutation: move the first role — `ours` is in the map.
      // The first choice that is not the role's own and stays apart from red
      // to a deutan is Okabe and Ito's black, choice 1.
      expect(moved, <String, int>{'theirs': 1});
    });

    test('only the deficiency the player named', () {
      final apart = RolesApart(_roles());
      // Mutation: check every deficiency, as `ColorRoles.confusions` does —
      // a protan or a tritan has the deutan's move made for them.
      expect(apart.choicesFor(<String>['ours', 'theirs'], _seeing(1)), isEmpty);
      expect(apart.choicesFor(<String>['ours', 'theirs'], _seeing(3)), isEmpty);
    });

    test('applied, the choice is the role in the settings', () {
      final roles = _roles();
      final config = RolesApart(
        roles,
      ).apply(<String>['ours', 'theirs'], _seeing(2));
      // Mutation: write the setting under the role's name rather than its
      // `color.` key — the role keeps its own green.
      expect(roles.of(roles.named('theirs')!, config), ColorRoles.palette[0]);
      // Asked again, there is nothing left to move.
      expect(
        RolesApart(roles).choicesFor(<String>['ours', 'theirs'], config),
        isEmpty,
      );
    });
  });
}
