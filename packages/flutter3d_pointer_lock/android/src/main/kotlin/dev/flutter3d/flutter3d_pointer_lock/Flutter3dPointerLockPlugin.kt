package dev.flutter3d.flutter3d_pointer_lock

import android.app.Activity
import android.content.Context
import android.hardware.input.InputManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.Choreographer
import android.view.InputDevice
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.ViewTreeObserver

import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Captures the mouse on the Flutter view and reports its motion as relative
 * deltas.
 *
 * ## The technique
 *
 * `View.requestPointerCapture`, which Android has had since API 26 for exactly
 * this: the cursor disappears, and the mouse's motion arrives on the view's
 * `OnCapturedPointerListener` as `SOURCE_MOUSE_RELATIVE` events whose `x` and
 * `y` are the motion itself rather than a position. The view has to belong to
 * the focused window, and the system takes the capture away when the window
 * loses focus, which is the release a game is meant to pause on.
 *
 * ## Supported only while a mouse is connected
 *
 * A phone with no mouse has no pointer to capture, and a game there shows its
 * touch controls. So the answer to "supported" is sent to Dart, as a `bool` on
 * the event channel, when the stream is listened to and again whenever an input
 * device comes or goes. Below API 26 the answer is always false.
 *
 * ## Clicks while captured
 *
 * A captured mouse's buttons arrive on the same listener as its motion, and
 * Flutter's view never sees them: the trigger of a first-person game would do
 * nothing. They are handed to the view as mouse touches at its centre, the
 * point a locked pointer is understood to be at, which is what the browser and
 * the desktops do.
 *
 * ## Coalesced per frame
 *
 * A mouse polled at 1000 Hz sends a thousand events a second, and the Dart side
 * only drains once per step. The motion is summed here and sent once per display
 * frame, which keeps the channel at the frame rate without losing a count.
 */
class Flutter3dPointerLockPlugin :
    FlutterPlugin,
    ActivityAware,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler,
    InputManager.InputDeviceListener {

  companion object {
    const val METHOD_CHANNEL = "dev.flutter3d/flutter3d_pointer_lock"
    const val EVENT_CHANNEL = "dev.flutter3d/flutter3d_pointer_lock/events"

    /** State codes shared with the Dart side, as on every other platform. */
    const val STATE_RELEASED = 0
    const val STATE_CAPTURED = 1

    /** `Build.VERSION_CODES.O`, the first release with pointer capture. */
    const val FIRST_API = 26

    /** How long a capture may take to be granted before it counts as refused. */
    private const val CONFIRM_ATTEMPTS = 20
    private const val CONFIRM_INTERVAL_MS = 16L

    /** Whether this device can capture a pointer at all. */
    fun supports(sdk: Int, mouseConnected: Boolean): Boolean =
        sdk >= FIRST_API && mouseConnected

    /**
     * The motion one captured event carries, in logical pixels.
     *
     * [xs] and [ys] are the event's historical samples followed by its current
     * one: a relative event batches the motion since the previous frame into
     * its history, and each sample is a delta of its own, so all of them are
     * summed rather than only the last. Divided by [density] because Dart
     * counts logical pixels, and a desktop's deltas are already in them.
     */
    fun motion(xs: FloatArray, ys: FloatArray, density: Float): DoubleArray {
      val scale = if (density > 0f) density.toDouble() else 1.0
      return doubleArrayOf(xs.sumOf { it.toDouble() } / scale, ys.sumOf { it.toDouble() } / scale)
    }
  }

  private var methodChannel: MethodChannel? = null
  private var eventChannel: EventChannel? = null
  private var sink: EventChannel.EventSink? = null
  private var inputManager: InputManager? = null
  private var activity: Activity? = null

  /** The view holding the capture, so release asks the same one. */
  private var capturedView: View? = null

  /** Created on first use: the unit tests run where there is no main looper. */
  private val handler: Handler by lazy { Handler(Looper.getMainLooper()) }

  var captured = false
    private set

  private var pendingDx = 0.0
  private var pendingDy = 0.0
  private var flushScheduled = false

  private val flush = Choreographer.FrameCallback { flushMotion() }

  private val focusListener = ViewTreeObserver.OnWindowFocusChangeListener { hasFocus ->
    // Release rather than pause: the system has already taken the capture
    // away, and Dart must hear it was not asked for.
    if (!hasFocus) release(notify = true)
  }

  // FlutterPlugin

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL).also {
      it.setMethodCallHandler(this)
    }
    eventChannel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL).also {
      it.setStreamHandler(this)
    }
    inputManager =
        binding.applicationContext.getSystemService(Context.INPUT_SERVICE) as InputManager?
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    release(notify = false)
    inputManager?.unregisterInputDeviceListener(this)
    methodChannel?.setMethodCallHandler(null)
    eventChannel?.setStreamHandler(null)
    methodChannel = null
    eventChannel = null
    inputManager = null
  }

  // ActivityAware

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    activity = binding.activity
  }

  override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
      onAttachedToActivity(binding)

  override fun onDetachedFromActivity() {
    release(notify = true)
    activity = null
  }

  // Method channel

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "capture" -> {
        capture()
        result.success(null)
      }
      // Reset is called by Dart on first use, and after a hot restart it is
      // what gives the cursor back.
      "release", "reset" -> {
        release(notify = false)
        result.success(null)
      }
      "isCaptured" -> result.success(captured)
      else -> result.notImplemented()
    }
  }

  // Event channel

  override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
    sink = events
    // A new listener is a new Dart side: whatever the old one captured is
    // nobody's now.
    release(notify = false)
    inputManager?.registerInputDeviceListener(this, handler)
    reportSupport()
  }

  override fun onCancel(arguments: Any?) {
    release(notify = false)
    inputManager?.unregisterInputDeviceListener(this)
    sink = null
  }

  // Input devices

  override fun onInputDeviceAdded(deviceId: Int) = reportSupport()

  override fun onInputDeviceRemoved(deviceId: Int) {
    reportSupport()
    // The mouse that held the capture is gone; the capture goes with it.
    if (captured && !mouseConnected()) release(notify = true)
  }

  override fun onInputDeviceChanged(deviceId: Int) = reportSupport()

  private fun mouseConnected(): Boolean =
      InputDevice.getDeviceIds().any { id ->
        val device = InputDevice.getDevice(id)
        device != null && !device.isVirtual && device.supportsSource(InputDevice.SOURCE_MOUSE)
      }

  private fun reportSupport() {
    sink?.success(supports(Build.VERSION.SDK_INT, mouseConnected()))
  }

  // Capture

  private fun capture() {
    if (captured || Build.VERSION.SDK_INT < FIRST_API) return
    val view = activity?.window?.decorView?.let(::findFlutterView) ?: return

    view.setOnCapturedPointerListener { _, event -> onCapturedEvent(view, event) }
    view.viewTreeObserver.addOnWindowFocusChangeListener(focusListener)
    capturedView = view
    pendingDx = 0.0
    pendingDy = 0.0
    view.requestPointerCapture()
    confirm(view, CONFIRM_ATTEMPTS)
  }

  /**
   * Reports the capture once the system has granted it.
   *
   * The request is asynchronous and can be refused, by a window without focus
   * for one, and a refusal says nothing. So Dart hears "captured" only when the
   * view says it holds the pointer, and a refused capture leaves the state
   * released instead of pretending it succeeded.
   */
  private fun confirm(view: View, attemptsLeft: Int) {
    handler.postDelayed({
      if (capturedView !== view || captured) return@postDelayed
      if (view.hasPointerCapture()) {
        captured = true
        sink?.success(STATE_CAPTURED)
      } else if (attemptsLeft > 0) {
        confirm(view, attemptsLeft - 1)
      } else {
        release(notify = false)
      }
    }, CONFIRM_INTERVAL_MS)
  }

  /** @param notify whether Dart is told; false when Dart asked for it itself. */
  private fun release(notify: Boolean) {
    val view = capturedView
    capturedView = null
    if (view != null) {
      if (Build.VERSION.SDK_INT >= FIRST_API) {
        view.setOnCapturedPointerListener(null)
        view.releasePointerCapture()
      }
      if (view.viewTreeObserver.isAlive) {
        view.viewTreeObserver.removeOnWindowFocusChangeListener(focusListener)
      }
    }
    // Motion summed but not yet sent goes before the state, so a release
    // between two steps does not lose the last fragment.
    flushMotion()
    val wasCaptured = captured
    captured = false
    if (notify && wasCaptured) sink?.success(STATE_RELEASED)
  }

  private fun onCapturedEvent(view: View, event: MotionEvent): Boolean {
    if (event.source and InputDevice.SOURCE_MOUSE_RELATIVE != InputDevice.SOURCE_MOUSE_RELATIVE) {
      return false
    }
    when (event.actionMasked) {
      MotionEvent.ACTION_MOVE -> accumulate(view, event)
      MotionEvent.ACTION_DOWN, MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL ->
          forwardButton(view, event)
    }
    return true
  }

  private fun accumulate(view: View, event: MotionEvent) {
    val samples = event.historySize
    val xs = FloatArray(samples + 1) { if (it < samples) event.getHistoricalX(it) else event.x }
    val ys = FloatArray(samples + 1) { if (it < samples) event.getHistoricalY(it) else event.y }
    val (dx, dy) = motion(xs, ys, view.resources.displayMetrics.density)
    pendingDx += dx
    pendingDy += dy
    if (!flushScheduled) {
      flushScheduled = true
      Choreographer.getInstance().postFrameCallback(flush)
    }
  }

  private fun flushMotion() {
    if (flushScheduled) {
      Choreographer.getInstance().removeFrameCallback(flush)
      flushScheduled = false
    }
    if (pendingDx == 0.0 && pendingDy == 0.0) return
    val values = doubleArrayOf(pendingDx, pendingDy)
    pendingDx = 0.0
    pendingDy = 0.0
    sink?.success(values)
  }

  /** A captured button, handed to Flutter as a mouse touch at the view's centre. */
  private fun forwardButton(view: View, event: MotionEvent) {
    val properties = MotionEvent.PointerProperties().apply {
      id = 0
      toolType = MotionEvent.TOOL_TYPE_MOUSE
    }
    val coords = MotionEvent.PointerCoords().apply {
      x = view.width / 2f
      y = view.height / 2f
    }
    val forwarded = MotionEvent.obtain(
        event.downTime,
        SystemClock.uptimeMillis(),
        event.actionMasked,
        1,
        arrayOf(properties),
        arrayOf(coords),
        event.metaState,
        event.buttonState,
        1f,
        1f,
        event.deviceId,
        0,
        InputDevice.SOURCE_MOUSE,
        0,
    )
    view.onTouchEvent(forwarded)
    forwarded.recycle()
  }

  private fun findFlutterView(view: View): FlutterView? {
    if (view is FlutterView) return view
    if (view is ViewGroup) {
      for (index in 0 until view.childCount) {
        findFlutterView(view.getChildAt(index))?.let { return it }
      }
    }
    return null
  }
}
