import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

/// What `ext.flutter3d.timeline.preview` answers.
typedef TimelinePreview = ({bool found, int? step});

/// What `ext.flutter3d.timeline.frameTimes` answers — `StepTimeTrace.toJson`,
/// read back without this application needing to depend on `flutter3d_sim`
/// for the one shape it reads out of it.
typedef StepCosts = ({List<int> steps, List<double> millis});

/// What a running game's `RunTimeline` looks like from outside it.
///
/// An interface rather than [VmServiceTimelineClient] directly, so
/// `timeline_attach_screen_test.dart` can drive the screen against a fake
/// that answers in a microtask instead of over a real socket —
/// `WidgetSurfacePipeline`'s tests took the same shape, mechanism proven for
/// real once and a fast, deterministic double for everything drawn on top of
/// it after that.
abstract interface class TimelineClient {
  /// Whether the timeline is currently paused.
  Future<bool> status();

  Future<void> pause();
  Future<void> resume();

  /// Throws if the remote timeline refuses — see `RunTimeline.stepOnce`,
  /// which only runs while paused.
  Future<void> stepOnce();

  /// Where a rewind to [secondsAgo] would land, without moving anything.
  Future<TimelinePreview> preview(double secondsAgo);

  /// Rewinds to [step] and lets the run continue from there. Returns whether
  /// the buffer still reached that far back.
  Future<bool> releaseAtStep(int step);

  /// Every command the remote timeline has carried out, oldest first, each
  /// as the short string `run_timeline_extensions.dart` writes —
  /// `"paused"`, `"stepped"`, `"branched:118"`.
  Future<List<String>> history();

  /// `rp-06`'s strip: every step timed so far, and what it cost. Throws if
  /// the running game registered no `StepTimeTrace` to answer from.
  Future<StepCosts> frameTimes();

  /// `rp-04`'s "send this run", asked for remotely. Whatever shape the
  /// running game's own callback returns; throws if it registered none, or
  /// if that callback itself threw (nothing recorded yet, most likely).
  Future<Map<String, Object?>> bugReport();

  /// Closes the connection. Safe to call more than once.
  Future<void> dispose();
}

/// [TimelineClient] over a real VM service connection — `rp-02`'s door onto
/// a running game, opened from the editor's side of it.
///
/// **The same channel DevTools and `flutter attach` use, and nothing else.**
/// This does not start a game, does not know what a genre is, and does not
/// hold a level document — it only speaks the seven
/// `ext.flutter3d.timeline.*` extensions `registerTimelineExtensions`
/// registers on the other end, over a plain WebSocket that every desktop
/// platform this application ships to already has through `dart:io`.
final class VmServiceTimelineClient implements TimelineClient {
  VmServiceTimelineClient._(this._service, this._isolateId);

  final VmService _service;
  final String _isolateId;

  /// Connects to a running game's VM service, given the URI it printed —
  /// the same one a person pastes into DevTools, `http://` or `ws://`,
  /// with or without a trailing slash.
  static Future<VmServiceTimelineClient> connect(String uri) async {
    final service = await vmServiceConnectUri(_asWebSocket(uri));
    final vm = await service.getVM();
    final isolates = vm.isolates;
    if (isolates == null || isolates.isEmpty) {
      await service.dispose();
      throw StateError('the VM at $uri reports no isolates to attach to');
    }
    return VmServiceTimelineClient._(service, isolates.first.id!);
  }

  static String _asWebSocket(String uri) {
    final withScheme = uri
        .replaceFirst('http://', 'ws://')
        .replaceFirst('https://', 'wss://');
    return withScheme.endsWith('/ws')
        ? withScheme
        : '${withScheme.replaceFirst(RegExp(r'/$'), '')}/ws';
  }

  Future<Map<String, Object?>> _call(
    String verb, [
    Map<String, String>? args,
  ]) async {
    final response = await _service.callServiceExtension(
      'ext.flutter3d.timeline.$verb',
      isolateId: _isolateId,
      args: args,
    );
    final json = response.json;
    if (json is! Map<String, Object?>) {
      throw StateError('ext.flutter3d.timeline.$verb answered with no body');
    }
    return json;
  }

  @override
  Future<bool> status() async => (await _call('status'))['paused']! as bool;

  @override
  Future<void> pause() => _call('pause');

  @override
  Future<void> resume() => _call('resume');

  @override
  Future<void> stepOnce() => _call('stepOnce');

  @override
  Future<TimelinePreview> preview(double secondsAgo) async {
    final json = await _call('preview', <String, String>{
      'secondsAgo': '$secondsAgo',
    });
    final found = json['found']! as bool;
    return (found: found, step: found ? json['step']! as int : null);
  }

  @override
  Future<bool> releaseAtStep(int step) async =>
      (await _call('releaseAtStep', <String, String>{
            'step': '$step',
          }))['released']!
          as bool;

  @override
  Future<List<String>> history() async =>
      ((await _call('history'))['commands']! as List<Object?>).cast<String>();

  @override
  Future<StepCosts> frameTimes() async {
    final json = await _call('frameTimes');
    return (
      steps: (json['steps']! as List<Object?>).cast<int>(),
      millis: (json['millis']! as List<Object?>)
          .map((entry) => (entry! as num).toDouble())
          .toList(),
    );
  }

  @override
  Future<Map<String, Object?>> bugReport() => _call('bugReport');

  @override
  Future<void> dispose() => _service.dispose();
}
