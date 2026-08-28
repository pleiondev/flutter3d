import 'package:flutter3d/flutter3d.dart';
import 'package:flutter_test/flutter_test.dart';

/// A plugin that records nothing and draws nothing.
///
/// The registry's whole substance is ordering and filtering, and neither needs
/// a GPU — which is exactly why the registry is its own class.
final class _Fake extends PassContributor {
  _Fake(this.label, {this.order = 0, this.active = true});

  final String label;

  @override
  final int order;

  final bool active;

  @override
  bool get isActive => active;

  @override
  void encode(ContributorFrame frame) {}

  @override
  String toString() => label;
}

List<String> _names(Iterable<PassContributor> plugins) =>
    plugins.map((PassContributor p) => p.toString()).toList();

void main() {
  group('the plugin registry', () {
    test('draws in order, not in registration order', () {
      final registry = ContributorRegistry()
        ..add(_Fake('late', order: 10))
        ..add(_Fake('early', order: -5))
        ..add(_Fake('middle'));

      expect(_names(registry.active), <String>['early', 'middle', 'late']);
    });

    test('a tie keeps registration order', () {
      // The only tie-break an application can actually control, so it has to
      // be stable rather than whatever the sort happens to do.
      final registry = ContributorRegistry();
      for (final label in <String>['a', 'b', 'c', 'd']) {
        registry.add(_Fake(label, order: 3));
      }

      expect(_names(registry.active), <String>['a', 'b', 'c', 'd']);
    });

    test('an inactive plugin is skipped, and costs no pass setup', () {
      final registry = ContributorRegistry()
        ..add(_Fake('empty', active: false))
        ..add(_Fake('busy'));

      expect(_names(registry.active), <String>['busy']);
      // Still registered: being idle this frame is not being removed.
      expect(registry.length, 2);
    });

    test('removing one leaves the rest in order', () {
      final registry = ContributorRegistry();
      final middle = registry.add(_Fake('middle', order: 5));
      registry
        ..add(_Fake('first', order: 1))
        ..add(_Fake('last', order: 9));

      expect(registry.remove(middle), isTrue);
      expect(registry.remove(middle), isFalse);
      expect(_names(registry.active), <String>['first', 'last']);
    });

    test('add returns the plugin, so it can be kept in one line', () {
      final registry = ContributorRegistry();
      final plugin = registry.add(_Fake('sparks'));
      expect(plugin.label, 'sparks');
      expect(registry.all, contains(plugin));
    });

    test('an empty registry is simply empty', () {
      final registry = ContributorRegistry();
      expect(registry.active, isEmpty);
      expect(registry.active, isEmpty);
    });
  });

  group('pass state', () {
    test('invalidating forgets the bound pipeline', () {
      // A plugin that binds its own pipeline and does not say so makes the
      // next mesh trust a stale answer and skip a bind it needed.
      final state = FramePassState()
        ..boundPipeline = LightingModel.pbr
        ..boundSkinned = false;

      state.invalidatePipeline();

      expect(state.boundPipeline, isNull);
      expect(state.boundSkinned, isNull);
    });

    test(
      'counters survive it, because the frame statistics are cumulative',
      () {
        final state = FramePassState()
          ..drawCalls = 7
          ..pipelineSwitches = 3;

        state.invalidatePipeline();

        expect(state.drawCalls, 7);
        expect(state.pipelineSwitches, 3);
      },
    );
  });
}
