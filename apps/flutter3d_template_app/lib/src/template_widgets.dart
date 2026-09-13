/// `tpl-04`'s three widgets, one per non-game template — real, live Flutter
/// widgets held by a [WidgetSurface] (`wg-01`) rather than a mock-up. Each
/// widget's own state lives in a controller outside the widget tree, the
/// same split `edu-05`'s `DataSourceRegistry` already makes between "what
/// changed" and "what draws it" — a test can drive a controller directly and
/// read its result without going through a widget at all.
library;

import 'package:flutter/material.dart';

import 'operator_panel.dart';

/// The viewer's own steps, walked one at a time — `edu_step` captions, in
/// `edu_sequence.steps`'s own order. [captions] is itself a [ValueNotifier]
/// rather than a plain field: the level a `widget_surface` names this widget
/// from is not open yet when the registry that will build it is assembled
/// (`LevelCubit.open` takes the registry before it has read the document),
/// so the real captions arrive later, through [setCaptions] — the same two-
/// stage shape `DataSourceRegistry.replace` already uses for "the source is
/// named before what it will say is known".
final class ViewerTourController {
  ViewerTourController([List<String> initial = const <String>['…']])
    : captions = ValueNotifier<List<String>>(initial);

  final ValueNotifier<List<String>> captions;
  final ValueNotifier<int> index = ValueNotifier<int>(0);

  void setCaptions(List<String> value) {
    captions.value = value.isEmpty ? const <String>['…'] : value;
    index.value = 0;
  }

  void next() => index.value = (index.value + 1) % captions.value.length;

  void previous() =>
      index.value =
          (index.value - 1 + captions.value.length) % captions.value.length;
}

Widget _viewerCaptionWidget(ViewerTourController tour) =>
    ValueListenableBuilder<List<String>>(
      valueListenable: tour.captions,
      builder: (context, captions, _) => ValueListenableBuilder<int>(
        valueListenable: tour.index,
        builder: (context, index, _) => ColoredBox(
          color: const Color(0xFF14161A),
          child: Row(
            children: <Widget>[
              IconButton(
                onPressed: tour.previous,
                icon: const Icon(Icons.chevron_left, color: Colors.white),
              ),
              Expanded(
                child: Text(
                  captions[index],
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 20),
                ),
              ),
              IconButton(
                onPressed: tour.next,
                icon: const Icon(Icons.chevron_right, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );

/// The configurator's own state: which of a fixed set of options is picked.
///
/// **Retints the panel's own display, not the product's mesh.** A brush
/// carries no `name` (`packages/flutter3d_sim/lib/src/level/brush.dart`), so
/// there is no way to address "this one box" in `scene.meshes` the way a
/// `widget_surface`'s own node already can be — see `doc/tooling-plan.md`'s
/// `### tpl-04` for the honest boundary this leaves.
final class ConfiguratorController {
  static const List<(String, double)> options = <(String, double)>[
    ('Red', 199.0),
    ('Blue', 219.0),
    ('Green', 209.0),
  ];

  final ValueNotifier<int> index = ValueNotifier<int>(0);

  (String, double) get current => options[index.value];

  void cycle() => index.value = (index.value + 1) % options.length;
}

Widget _configuratorPanelWidget(ConfiguratorController controller) =>
    ValueListenableBuilder<int>(
      valueListenable: controller.index,
      builder: (context, value, _) {
        final (name, price) = ConfiguratorController.options[value];
        return GestureDetector(
          onTap: controller.cycle,
          child: ColoredBox(
            color: const Color(0xFF14161A),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    name,
                    style: const TextStyle(color: Colors.white, fontSize: 22),
                  ),
                  Text(
                    '\$${price.toStringAsFixed(0)}',
                    style: const TextStyle(color: Color(0xFF9AA4B2)),
                  ),
                  const Text(
                    'tap to change',
                    style: TextStyle(color: Color(0xFF6C7684), fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

/// The three widgets a `widget_surface` entity in one of `tpl-04`'s levels
/// may name — the "reistry the application hands over" `wg-01`'s own write-up
/// describes, superset over all three templates because only the level
/// actually open ever names one of these keys.
///
/// `'twin-dashboard'` is `wg-02`'s own [OperatorPanel] — `edu-05`'s
/// `resolveBindings` writes [twinReading] every tick; the panel only ever
/// reads it back.
Map<String, WidgetBuilder> templateWidgetRegistry({
  required ViewerTourController viewerTour,
  required ConfiguratorController configurator,
  required ValueNotifier<double> twinReading,
}) => <String, WidgetBuilder>{
  'viewer-caption': (_) => _viewerCaptionWidget(viewerTour),
  'configurator-panel': (_) => _configuratorPanelWidget(configurator),
  'twin-dashboard': (_) =>
      OperatorPanel(label: 'spindle temp', unit: '°C', value: twinReading),
};
