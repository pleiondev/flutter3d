/// A command's arguments read in American as well as in the British words a
/// journal written before 1.0 holds.
///
///     dart test test/command_spelling_test.dart
library;

import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';

void main() {
  // Mutation: read only `colour` and `centre` in the paint readers, and the
  // American halves of these come back null.
  for (final name in <String>['paintStroke', 'paintVertexColour']) {
    test('$name reads color and center, and colour and centre', () {
      Map<String, Object?> call(String color, String center) =>
          <String, Object?>{
            'name': name,
            'objectId': 1,
            'samples': <Object?>[
              <String, Object?>{
                center: <double>[0.5, 0.5, 0],
                'radius': 0.25,
              },
            ],
            color: <double>[0.8, 0.3, 0.2, 1],
          };
      for (final (color, center) in <(String, String)>[
        ('color', 'center'),
        ('colour', 'centre'),
      ]) {
        final command = modelCommandFromJson(call(color, center));
        expect(command, isNotNull, reason: '$color and $center');
        final json = command!.toJson();
        expect(modelCommandFromJson(json)?.toJson(), json);
      }
    });
  }

  // Mutation: compare only the wire word in the placement reader, and
  // `boundsCenter` is not read.
  test('setOrigin reads boundsCenter and boundsCentre alike', () {
    for (final word in <String>['boundsCenter', 'boundsCentre']) {
      final command = modelCommandFromJson(<String, Object?>{
        'name': 'setOrigin',
        'id': 3,
        'to': word,
      });
      expect(command, isA<SetOrigin>(), reason: word);
      expect((command! as SetOrigin).to, OriginPlacement.boundsCenter);
    }
  });
}
