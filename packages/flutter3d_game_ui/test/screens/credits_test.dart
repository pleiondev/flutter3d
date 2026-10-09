/// A game's credits, held to the licence record beside its models.
///
///     flutter test test/credits_test.dart
///
/// The ledger answers what is owed and what is untraced; the record reads
/// both shapes of `LICENSES.md` the games here keep; and the two are compared
/// file by file, so a list that drifts from the record says where.
library;

import 'package:flutter3d_game_ui/screens.dart';
import 'package:flutter_test/flutter_test.dart';

const Credit _byCar = Credit(
  file: 'models/car.glb',
  work: 'A car',
  author: 'Somebody',
  source: 'https://example.org/car',
  license: 'CC BY 4.0',
  licenseUrl: 'http://creativecommons.org/licenses/by/4.0/',
);

const Credit _zeroTree = Credit(
  file: 'models/tree.glb',
  work: 'A tree',
  author: 'Kenney',
  source: 'https://kenney.nl',
  license: 'CC0 1.0',
  licenseUrl: 'http://creativecommons.org/publicdomain/zero/1.0/',
);

const Credit _lostRock = Credit.untraced(file: 'models/rock.glb', work: 'Rock');

const String _sections = '''
# Models

## `car.glb` — "A car"

| | |
|---|---|
| Author | Somebody — https://example.org |
| Source | https://example.org/car |
| Licence | **CC BY 4.0** — http://creativecommons.org/licenses/by/4.0/ |

Attribution is a condition of the licence.

## `tree.glb`, `bush.glb`

| | |
|---|---|
| Author | Kenney, https://kenney.nl |
| Licence | **CC0 1.0**, http://creativecommons.org/publicdomain/zero/1.0/ |

Which is which:

| File | The model |
|---|---|
| `tree.glb` | an oak |

## `key.glb` — generated here

No table: a script in this repository wrote it.
''';

const String _fileTable = '''
# Models

Every model here is CC0 1.0.

| File | Pack | Source |
|---|---|---|
| `tower.glb` | Castle Kit | https://kenney.nl/assets/castle-kit |
| `wall.glb` | Castle Kit | https://kenney.nl/assets/castle-kit |

Prose mentions `rock.glb` in passing.
''';

void main() {
  group('the ledger', () {
    test('owes what a CC BY licence asks for, and nothing CC0', () {
      const ledger = CreditLedger(<Credit>[_byCar, _zeroTree, _lostRock]);
      // Mutation: drop the `owesAttribution` filter from `owed` — the tree
      // and the rock come back too and this fails.
      expect(ledger.owed, <Credit>[_byCar]);
    });

    test('and names what nobody can trace', () {
      const ledger = CreditLedger(<Credit>[_byCar, _zeroTree, _lostRock]);
      // Mutation: test `traced` rather than `!traced` in `untraced` — the two
      // traced models come back and the rock is lost.
      expect(ledger.untraced, <Credit>[_lostRock]);
      expect(const CreditLedger(<Credit>[_zeroTree]).untraced, isEmpty);
    });
  });

  group('the record', () {
    test('reads a section a file, with the rows of its table', () {
      final record = LicenseRecord.parse(_sections);
      final car = record.entryFor('car.glb')!;
      // Mutation: keep the link in `_beforeLink` — the author reads
      // `Somebody — https://example.org` and this fails.
      expect(car.author, 'Somebody');
      expect(car.license, 'CC BY 4.0');
      expect(car.licenseUrl, 'http://creativecommons.org/licenses/by/4.0/');
      expect(car.source, 'https://example.org/car');
    });

    test('and a heading that names two files covers both', () {
      final record = LicenseRecord.parse(_sections);
      // Mutation: take only the first backticked name in `_fileNames` — the
      // bush has no entry.
      expect(record.entryFor('bush.glb')?.license, 'CC0 1.0');
      expect(record.entryFor('tree.glb')?.author, 'Kenney');
    });

    test('and a note table under a section is not an entry', () {
      final record = LicenseRecord.parse(_sections);
      // Mutation: add file-table rows whatever section they are in — the
      // tree gets a second entry with no licence, ahead of none, and the
      // count is four.
      expect(record.entries, hasLength(3));
      expect(record.entryFor('key.glb'), isNotNull);
      expect(record.entryFor('key.glb')!.license, isNull);
    });

    test('reads a table a file when the licence is stated once above it', () {
      final record = LicenseRecord.parse(_fileTable);
      // Mutation: skip the row after a `File` header as the rule under it —
      // the first tower is lost.
      expect(record.entries.map((LicenseEntry e) => e.files.single), <String>[
        'tower.glb',
        'wall.glb',
      ]);
      expect(record.mentions('rock.glb'), isTrue, reason: 'said in prose');
      expect(record.mentions('crate.glb'), isFalse);
    });
  });

  group('the two held to each other', () {
    test('agree when the record says what the list says', () {
      const ledger = CreditLedger(<Credit>[_byCar, _zeroTree]);
      expect(ledger.disagreementsWith(LicenseRecord.parse(_sections)), isEmpty);
    });

    test('say which file the record never mentions', () {
      const ledger = CreditLedger(<Credit>[_byCar, _lostRock]);
      // Mutation: return nothing for an unmentioned file in
      // `_disagreementsWith` — the rock passes unrecorded.
      expect(ledger.disagreementsWith(LicenseRecord.parse(_sections)), <String>[
        'the licence record does not mention rock.glb',
      ]);
    });

    test('and say where a licence or an author differs', () {
      const relicensed = Credit(
        file: 'models/car.glb',
        work: 'A car',
        author: 'Somebody Else',
        source: 'https://example.org/car',
        license: 'CC0 1.0',
        licenseUrl: 'http://creativecommons.org/publicdomain/zero/1.0/',
      );
      // Mutation: compare only the licence — the author's line goes missing.
      expect(
        const CreditLedger(<Credit>[
          relicensed,
        ]).disagreementsWith(LicenseRecord.parse(_sections)),
        <String>[
          'car.glb is credited as CC0 1.0; the record says CC BY 4.0',
          'car.glb is credited to Somebody Else; the record says Somebody',
        ],
      );
    });

    test('and do not invent a licence the record does not state', () {
      const key = Credit(
        file: 'models/key.glb',
        work: 'A key',
        author: 'this repository',
        source: 'tool/make_key.py',
        license: 'CC0 1.0',
        licenseUrl: 'https://creativecommons.org/publicdomain/zero/1.0/',
      );
      // Mutation: compare against an empty string when the entry has no
      // licence — the key, recorded in prose only, disagrees with nothing.
      expect(
        const CreditLedger(<Credit>[
          key,
        ]).disagreementsWith(LicenseRecord.parse(_sections)),
        isEmpty,
      );
    });
  });
}
