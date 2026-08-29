package dev.flutter3d.gamepad

import android.app.Activity
import android.app.Application
import android.hardware.input.InputManager
import android.os.Bundle
import android.view.InputDevice
import android.view.MotionEvent
import android.view.View

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel

/**
 * Forwards a gamepad's stick and trigger motion, and says which pad is attached.
 *
 * ## What is deliberately not here
 *
 * **No arithmetic and no decisions.** Which axis a trigger is on, whether the
 * d-pad is a hat or a pair of keys, what "pressed" means for an analogue
 * control: all of it is in `lib/src/android_mapping.dart`, in Dart, where a unit
 * test can reach it. This file reports the axes a device admits to having and the
 * values it sends, and nothing else.
 *
 * That split is the reason an Android backend could be written here at all. The
 * specification records that an earlier gamepad backend was deleted rather than
 * finished, because one written without a controller in hand is wrong in a way no
 * test shows — and the way to survive that rule is to leave native code with
 * nothing in it that a test would have caught.
 *
 * **No buttons either.** Android delivers a gamepad's buttons as `KeyEvent`s, and
 * Flutter's own embedding already maps their key codes to `gameButtonA` and its
 * neighbours and hands them to the framework. Catching them again here would be a
 * second source of truth for one event, and the two would disagree the first time
 * either was wrong.
 *
 * ## Why a listener on the decor view
 *
 * Flutter turns pointer and scroll motion into `PointerEvent`s and drops the
 * rest, so a joystick's `MotionEvent` never reaches Dart. A plugin cannot
 * override `Activity.onGenericMotionEvent`, but `View.setOnGenericMotionListener`
 * is consulted before a view handles an event itself, and the window's decor view
 * sees what the activity sees. That is the whole hook.
 */
class GamepadPlugin :
    FlutterPlugin,
    ActivityAware,
    EventChannel.StreamHandler,
    InputManager.InputDeviceListener {

  private companion object {
    const val EVENT_CHANNEL = "dev.flutter3d/gamepad/events"

    /**
     * The axes Dart asks about, in the order it will read them.
     *
     * Kept in sync with `AndroidAxis.all` by hand, and that is on purpose: the
     * alternative is a channel call at startup to fetch a list, which is a round
     * trip and a failure mode in exchange for a list that changes when a mapping
     * changes and not otherwise.
     */
    val AXES = intArrayOf(
      MotionEvent.AXIS_X,
      MotionEvent.AXIS_Y,
      MotionEvent.AXIS_Z,
      MotionEvent.AXIS_RZ,
      MotionEvent.AXIS_HAT_X,
      MotionEvent.AXIS_HAT_Y,
      MotionEvent.AXIS_LTRIGGER,
      MotionEvent.AXIS_RTRIGGER,
      MotionEvent.AXIS_GAS,
      MotionEvent.AXIS_BRAKE,
    )
  }

  private var eventChannel: EventChannel? = null
  private var sink: EventChannel.EventSink? = null
  private var activity: Activity? = null
  private var inputManager: InputManager? = null

  /** The pad being reported, or null. One at a time, as the package promises. */
  private var deviceId: Int? = null

  /** The axes [deviceId] said it has, so a sample carries only those. */
  private var deviceAxes: IntArray = IntArray(0)

  private val sample = DoubleArray(1 + AXES.size * 2)

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    eventChannel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL).also {
      it.setStreamHandler(this)
    }
    inputManager =
      binding.applicationContext.getSystemService(Application.INPUT_SERVICE)
          as? InputManager
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    // The same teardown onCancel does, because the engine can go while the
    // stream is still listening — a hot restart never cancels it — and this
    // object would otherwise stay registered with the InputManager and on the
    // decor view for as long as the process lives. Both calls are no-ops when
    // onCancel already ran.
    inputManager?.unregisterInputDeviceListener(this)
    detachMotionListener()
    sink = null
    eventChannel?.setStreamHandler(null)
    eventChannel = null
    inputManager = null
  }

  // MARK: - Listening

  override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
    sink = events
    inputManager?.registerInputDeviceListener(this, null)
    attachMotionListener()
    // Whatever is already plugged in, because a controller connected before the
    // game started produces no event and would otherwise be invisible until the
    // player unplugged and replugged it.
    adopt(findGamepad())
  }

  override fun onCancel(arguments: Any?) {
    inputManager?.unregisterInputDeviceListener(this)
    detachMotionListener()
    sink = null
  }

  // MARK: - Devices

  override fun onInputDeviceAdded(id: Int) {
    if (isGamepad(InputDevice.getDevice(id))) adopt(id)
  }

  override fun onInputDeviceRemoved(id: Int) {
    if (id != deviceId) return
    deviceId = null
    deviceAxes = IntArray(0)
    // Told after the fact, and the Dart side zeroes before it passes the news on:
    // a pad whose battery dies mid-corner must not leave the throttle where it
    // was.
    sink?.success(mapOf("event" to "disconnected"))
  }

  override fun onInputDeviceChanged(id: Int) {
    // A device that gained or lost axes is a different device as far as the
    // mapping is concerned — a keyboard with a joystick dock, in practice.
    if (id == deviceId) adopt(id)
  }

  /** The first attached controller, or null. */
  private fun findGamepad(): Int? =
    InputDevice.getDeviceIds().firstOrNull { isGamepad(InputDevice.getDevice(it)) }

  /**
   * Whether this is something a player holds.
   *
   * Both source bits, because they disagree: a pad with only a d-pad and buttons
   * reports `SOURCE_GAMEPAD` without `SOURCE_JOYSTICK`, and a flight stick the
   * other way round. Requiring both would refuse half the hardware.
   */
  private fun isGamepad(device: InputDevice?): Boolean {
    if (device == null || device.isVirtual) return false
    val sources = device.sources
    val gamepad = sources and InputDevice.SOURCE_GAMEPAD == InputDevice.SOURCE_GAMEPAD
    val joystick = sources and InputDevice.SOURCE_JOYSTICK == InputDevice.SOURCE_JOYSTICK
    return gamepad || joystick
  }

  private fun adopt(id: Int?) {
    if (id == null) return
    val device = InputDevice.getDevice(id) ?: return
    // What it actually has, asked rather than assumed. This is the answer Dart
    // needs to know whether a trigger is on `AXIS_LTRIGGER` or on `AXIS_BRAKE`,
    // and the two are the same physical control under different drivers.
    deviceAxes = AXES.filter { device.getMotionRange(it, device.sources) != null }
      .toIntArray()
    deviceId = id
    sink?.success(
      mapOf(
        "event" to "connected",
        "device" to id,
        "name" to (device.name ?: ""),
        "axes" to deviceAxes.toList(),
      )
    )
  }

  // MARK: - Motion

  private val motionListener = View.OnGenericMotionListener { _, event ->
    forward(event)
    // **False, always.** Claiming the event would stop it reaching anything else
    // that wanted it, and this plugin is a listener rather than an owner. It also
    // costs nothing: nothing else in a Flutter application reads joystick motion.
    false
  }

  private fun attachMotionListener() {
    activity?.window?.decorView?.setOnGenericMotionListener(motionListener)
  }

  private fun detachMotionListener() {
    activity?.window?.decorView?.setOnGenericMotionListener(null)
  }

  private fun forward(event: MotionEvent) {
    val sink = this.sink ?: return
    if (event.deviceId != deviceId) return
    if (event.source and InputDevice.SOURCE_CLASS_JOYSTICK == 0) return

    sample[0] = event.deviceId.toDouble()
    var at = 1
    for (axis in deviceAxes) {
      sample[at++] = axis.toDouble()
      sample[at++] = event.getAxisValue(axis).toDouble()
    }
    // One typed list rather than a map, because this is the hot path: a stick in
    // motion sends a sample per frame and a `HashMap` per frame with it would be
    // the only allocation in the whole package that scales with play. The Dart
    // side tells the messages apart by type, as `pointer_lock` does.
    sink.success(sample.copyOfRange(0, at))
  }

  // MARK: - Activity, and losing it

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    activity = binding.activity
    if (sink != null) attachMotionListener()
    binding.activity.application
      .registerActivityLifecycleCallbacks(lifecycle)
  }

  override fun onDetachedFromActivity() {
    detachMotionListener()
    activity?.application?.unregisterActivityLifecycleCallbacks(lifecycle)
    activity = null
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
    onAttachedToActivity(binding)

  override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

  /**
   * Releases everything when the application goes to the background.
   *
   * Handled natively, as `pointer_lock` handles focus loss, and for its reason:
   * the last event before the window went away is the state the pad stays in
   * otherwise, so a stick left half over keeps walking behind whatever is now on
   * screen. The pad is reported as still attached, because it is — the player is
   * what has gone.
   */
  private val lifecycle = object : Application.ActivityLifecycleCallbacks {
    override fun onActivityPaused(paused: Activity) {
      if (paused == activity) sink?.success(mapOf("event" to "relaxed"))
    }

    override fun onActivityCreated(a: Activity, state: Bundle?) {}
    override fun onActivityStarted(a: Activity) {}
    override fun onActivityResumed(a: Activity) {}
    override fun onActivityStopped(a: Activity) {}
    override fun onActivitySaveInstanceState(a: Activity, state: Bundle) {}
    override fun onActivityDestroyed(a: Activity) {}
  }
}
