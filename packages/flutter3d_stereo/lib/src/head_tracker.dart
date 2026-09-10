import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'head_pose.dart';

/// Whatever knows where the head is.
///
/// An interface with two implementations in mind and one written: a phone's
/// rotation sensor now, a headset's `xrLocateViews` later. The difference
/// between them is not only accuracy — a runtime also states *when* the pose is
/// for, and a phone cannot — so this deliberately promises only the pose, and
/// the timing belongs to whatever drives the frame.
abstract interface class HeadTracker {
  /// The latest pose. A listenable rather than a stream so that a widget can be
  /// rebuilt by it without an application holding a subscription.
  ValueListenable<HeadPose> get pose;

  Future<void> start();

  Future<void> stop();
}

/// A head tracked by the device's own rotation sensor.
///
/// Three degrees of freedom and no more: the sensor says which way the phone is
/// pointing and nothing about where it is. Leaning forward moves nothing, which
/// is honest — a neck model guessing a translation from a rotation is a
/// guess that reads as the room sliding about.
final class SensorHeadTracker implements HeadTracker {
  SensorHeadTracker();

  static const EventChannel _channel = EventChannel('dev.flutter3d/stereo/head');

  final ValueNotifier<HeadPose> _pose = ValueNotifier<HeadPose>(
    HeadPose.still(),
  );

  StreamSubscription<dynamic>? _subscription;

  @override
  ValueListenable<HeadPose> get pose => _pose;

  @override
  Future<void> start() async {
    if (_subscription != null) return;
    _subscription = _channel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is! List) return;
        _pose.value = decodeSensorEvent(
          event.map((dynamic v) => (v as num).toDouble()).toList(),
        );
      },
      onError: (Object error) {
        // **A platform with no plugin behind the channel is not an error the
        // caller can act on**, and it is the ordinary case on desktop, on the
        // web and on iOS: the pose simply stays where it was, the scene draws,
        // and stereo is still stereo — it just does not follow a head. Said
        // once rather than per frame, because the channel reports it on every
        // listen attempt.
        if (error is MissingPluginException) {
          debugPrint(
            'flutter3d_stereo: no rotation sensor on this platform, so the '
            'head stays where it is. Point it yourself through StereoRig.',
          );
          return;
        }
        debugPrint('flutter3d_stereo: the rotation sensor failed: $error');
      },
    );
  }

  @override
  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  void dispose() {
    unawaited(stop());
    _pose.dispose();
  }
}
