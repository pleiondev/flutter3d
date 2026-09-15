/// `CabinetLink.fromQuery`'s own parsing, and the gating `TopBarActions`'
/// own "Save to cabinet" button reads off it — `tut-19`/`tut-20`.
///
///     flutter test test/cabinet_link_test.dart
library;

import 'package:flutter3d_modeler/src/cabinet_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group(
    'CabinetLink.none: every launch that is not the cabinet\'s own iframe',
    () {
      test('has no id, no mode, and cannot save back', () {
        expect(CabinetLink.none.id, isNull);
        expect(CabinetLink.none.mode, isNull);
        expect(CabinetLink.none.isFromCabinet, isFalse);
        expect(CabinetLink.none.canSaveBack, isFalse);
      });

      test('is what an empty query string parses to', () {
        final link = CabinetLink.fromQuery(const <String, String>{});
        expect(link.id, isNull);
        expect(link.mode, isNull);
        expect(link.csrf, isEmpty);
        expect(link.canSaveBack, isFalse);
      });
    },
  );

  group('CabinetLink.fromQuery', () {
    test('reads id, mode and csrf out of the query map', () {
      final link = CabinetLink.fromQuery(const <String, String>{
        'id': '42',
        'mode': 'edit',
        'csrf': 'tok123',
      });
      expect(link.id, 42);
      expect(link.mode, 'edit');
      expect(link.csrf, 'tok123');
      expect(link.isFromCabinet, isTrue);
    });

    test(
      'an id that does not parse as an integer is treated as no id at all',
      () {
        final link = CabinetLink.fromQuery(const <String, String>{
          'id': 'not-a-number',
          'mode': 'edit',
        });
        expect(link.id, isNull);
        expect(link.isFromCabinet, isFalse);
        expect(link.canSaveBack, isFalse);
      },
    );

    test('a missing csrf reads as empty, not null', () {
      final link = CabinetLink.fromQuery(const <String, String>{'id': '7'});
      expect(link.csrf, isEmpty);
    });
  });

  group('CabinetLink.canSaveBack: tut-20\'s own "Save to cabinet" gate', () {
    test('true with an id and mode=edit', () {
      expect(
        const CabinetLink(id: 7, mode: 'edit', csrf: '').canSaveBack,
        isTrue,
      );
    });

    test('true with an id and no mode at all — the future default `tut-20`\'s '
        'own doc comment describes, once the cabinet offers a real Edit link '
        'that does not bother setting mode=edit explicitly', () {
      expect(
        const CabinetLink(id: 7, mode: null, csrf: '').canSaveBack,
        isTrue,
      );
    });

    test(
      'false with an id and mode=view — the one link the cabinet sends today',
      () {
        final link = const CabinetLink(id: 7, mode: 'view', csrf: '');
        expect(link.isViewOnly, isTrue);
        expect(link.canSaveBack, isFalse);
      },
    );

    test('false with mode=edit but no id at all', () {
      expect(
        const CabinetLink(id: null, mode: 'edit', csrf: '').canSaveBack,
        isFalse,
      );
    });
  });
}
