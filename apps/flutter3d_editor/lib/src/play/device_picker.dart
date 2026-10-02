/// Which device a [FlutterRun] starts on, for `PlayScreen`'s bar.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_editor_play/flutter3d_editor_play.dart';

/// Picks [run]'s device from [devices].
///
/// **Held still while a run is going** ([enabled] false): the device is
/// `flutter run`'s argument, and changing it means a new run. Its own file
/// because `flutterDevices` runs a process, and `PlayScreen` has to build
/// where there is none.
final class DevicePicker extends StatefulWidget {
  const DevicePicker({
    super.key,
    required this.run,
    required this.enabled,
    this.devices = flutterDevices,
  });

  final FlutterRun run;
  final bool enabled;

  /// What the picker offers; `flutter devices --machine` by default.
  final Future<List<FlutterDevice>> Function() devices;

  @override
  State<DevicePicker> createState() => _DevicePickerState();
}

class _DevicePickerState extends State<DevicePicker> {
  static const Color _background = Color(0xFF14161A);
  static const Color _text = Color(0xFFE6EAF0);

  /// Asked once per opening of the panel: the tool takes a second or two to
  /// answer, and a phone plugged in afterwards is found by opening it again.
  late final Future<List<FlutterDevice>> _devices = widget.devices();

  @override
  Widget build(BuildContext context) => FutureBuilder<List<FlutterDevice>>(
    future: _devices,
    builder: (BuildContext context, AsyncSnapshot<List<FlutterDevice>> it) {
      final devices = it.data ?? const <FlutterDevice>[];
      final chosen = widget.run.device;
      return DropdownButton<String?>(
        key: const ValueKey<String>('play.device'),
        value: devices.any((d) => d.id == chosen) ? chosen : null,
        dropdownColor: _background,
        style: const TextStyle(color: _text, fontSize: 13),
        underline: const SizedBox.shrink(),
        hint: Text(
          it.hasError ? 'devices unavailable' : 'default device',
          style: const TextStyle(color: _text, fontSize: 13),
        ),
        items: <DropdownMenuItem<String?>>[
          const DropdownMenuItem<String?>(child: Text('default device')),
          for (final device in devices)
            DropdownMenuItem<String?>(
              value: device.id,
              child: Text(device.name),
            ),
        ],
        onChanged: widget.enabled
            ? (String? id) => setState(() => widget.run.device = id)
            : null,
      );
    },
  );
}
