/// What every registry hands back: the way to take the thing registered out
/// again.
///
/// The host keeps these for a plugin, so switching the plugin off cancels
/// everything it registered without the plugin keeping a list of its own.
/// Cancelling twice is not an error — a plugin torn down twice should not
/// be.
final class Registration {
  /// A registration that runs [onCancel] the first time it is cancelled.
  Registration(void Function() onCancel) : _onCancel = onCancel;

  final void Function() _onCancel;
  bool _cancelled = false;

  bool get isCanceled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _onCancel();
  }
}
