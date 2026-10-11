import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_hub/flutter3d_hub.dart';
import 'package:test/test.dart';

void main() {
  group('HubRefusal', () {
    test('names the six reasons of the contract, by their wire names', () {
      expect(
        <String>[for (final r in HubRefusal.values) r.name],
        <String>[
          'notFound',
          'withdrawn',
          'hashMismatch',
          'offline',
          'tooLarge',
          'protocol',
        ],
      );
    });

    test('byName reads each back and knows no other', () {
      for (final reason in HubRefusal.values) {
        expect(HubRefusal.byName(reason.name), same(reason));
      }
      expect(HubRefusal.byName('quarantined'), isNull);
    });
  });

  group('HubRefusedException', () {
    test('is a resource exception of the engine', () {
      expect(
        const HubRefusedException(HubRefusal.offline),
        isA<ResourceException>(),
      );
    });

    test('says the model and the reason in a sentence', () {
      final reference = HubReference.parse(
        '0f8b5c2e-7a41-4d3b-9c6e-2a1f8e4d7b90@3',
      );
      for (final reason in HubRefusal.values) {
        final message = HubRefusedException(
          reason,
          reference: reference,
        ).message;
        expect(message, startsWith('The hub model $reference '));
        expect(message, endsWith('.'));
      }
      expect(
        HubRefusedException(
          HubRefusal.notFound,
          reference: reference,
          detail: 'No model has this UUID.',
        ).message,
        'The hub model $reference was not found: No model has this UUID.',
      );
    });
  });

  group('HubCachePolicy', () {
    test('the standard policy reads, fetches, keeps and has a limit', () {
      const policy = HubCachePolicy.standard;
      expect(policy.readCache, isTrue);
      expect(policy.useNetwork, isTrue);
      expect(policy.writeCache, isTrue);
      expect(policy.maxBytes, HubCachePolicy.defaultMaxBytes);
      expect(policy, const HubCachePolicy());
    });

    test('offline never asks the network', () {
      expect(HubCachePolicy.offline.useNetwork, isFalse);
      expect(HubCachePolicy.offline.readCache, isTrue);
    });

    test('noStore neither reads nor writes the cache', () {
      expect(HubCachePolicy.noStore.readCache, isFalse);
      expect(HubCachePolicy.noStore.writeCache, isFalse);
    });

    test('copyWith and unlimited change what they say', () {
      final policy = HubCachePolicy.standard.copyWith(maxBytes: 1024);
      expect(policy.maxBytes, 1024);
      expect(policy.unlimited.maxBytes, isNull);
      expect(policy.unlimited.useNetwork, isTrue);
    });
  });
}
