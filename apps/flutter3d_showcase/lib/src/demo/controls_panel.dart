/// The panel of sliders, switches and choices beside a viewport.
///
/// One widget for every page, so the panel looks like one panel and a page
/// only says what can be changed. A control changes a field of the demo and
/// calls [onChanged]; the demo reads the field the next frame.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';

class ControlsPanel extends StatelessWidget {
  const ControlsPanel({
    super.key,
    required this.controls,
    required this.onChanged,
  });

  final List<DemoControl> controls;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text('Try it', style: text.titleSmall),
        const SizedBox(height: 8),
        for (final DemoControl control in controls)
          switch (control) {
            final SliderControl c => _slider(context, c),
            final ToggleControl c => SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(c.label),
              value: c.value(),
              onChanged: (bool v) {
                c.onChanged(v);
                onChanged();
              },
            ),
            final ChoiceControl c => _choice(context, c),
          },
      ],
    );
  }

  Widget _slider(BuildContext context, SliderControl c) {
    final double value = c.value().clamp(c.min, c.max);
    final String shown = c.format?.call(value) ?? value.toStringAsFixed(2);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(c.label),
            Text(shown, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        Slider(
          value: value,
          min: c.min,
          max: c.max,
          divisions: c.divisions,
          onChanged: (double v) {
            c.onChanged(v);
            onChanged();
          },
        ),
      ],
    );
  }

  Widget _choice(BuildContext context, ChoiceControl c) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(c.label),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (var i = 0; i < c.options.length; i++)
                ChoiceChip(
                  label: Text(c.options[i]),
                  selected: c.index() == i,
                  onSelected: (bool _) {
                    c.onChanged(i);
                    onChanged();
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}
