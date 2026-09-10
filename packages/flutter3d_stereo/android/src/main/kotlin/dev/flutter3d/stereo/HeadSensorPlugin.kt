package dev.flutter3d.stereo

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.hardware.display.DisplayManager
import android.view.Display
import android.view.Surface

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel

/**
 * Forwards the device's rotation vector, and how far the screen is turned.
 *
 * ## What is deliberately not here
 *
 * **No quaternion arithmetic.** The sensor's values describe a rotation from
 * the device's axes into east-north-up, the engine has Y up and a camera
 * looking down its own −Z, and the screen is a quarter turn from the device
 * when the phone is held in landscape. Reconciling those three is exactly the
 * kind of thing that is wrong by a sign and looks almost right on screen, so it
 * lives in `lib/src/head_pose.dart` where `flutter test` can hold it to
 * numbers. This file sends four floats and an angle.
 *
 * **No sensor choice either.** `TYPE_ROTATION_VECTOR` is the fused one —
 * gyroscope, accelerometer and magnetometer already combined by the platform —
 * and a package that offered a choice of raw gyroscope would be offering a
 * choice of drift.
 *
 * ## Why the display rotation travels with every event
 *
 * Because it can change between two of them, and a pose that was correct for
 * the previous orientation is a picture that snaps sideways for one frame. It
 * is one integer next to four floats.
 */
class HeadSensorPlugin : FlutterPlugin, EventChannel.StreamHandler, SensorEventListener {

    private companion object {
        const val EVENT_CHANNEL = "dev.flutter3d/stereo/head"
    }

    private var channel: EventChannel? = null
    private var sensors: SensorManager? = null
    private var rotationVector: Sensor? = null
    private var context: Context? = null
    private var events: EventChannel.EventSink? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        sensors = binding.applicationContext
            .getSystemService(Context.SENSOR_SERVICE) as SensorManager
        rotationVector = sensors?.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
        channel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL).also {
            it.setStreamHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setStreamHandler(null)
        channel = null
        sensors?.unregisterListener(this)
        sensors = null
        context = null
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
        val sensor = rotationVector
        if (sensor == null) {
            sink?.error("no-sensor", "This device has no rotation vector sensor", null)
            return
        }
        events = sink
        // Game rate rather than the fastest: the fastest delivers more samples
        // than there are frames to show them in, and every one of them costs a
        // channel message.
        sensors?.registerListener(this, sensor, SensorManager.SENSOR_DELAY_GAME)
    }

    override fun onCancel(arguments: Any?) {
        sensors?.unregisterListener(this)
        events = null
    }

    override fun onSensorChanged(event: SensorEvent) {
        val sink = events ?: return
        // Three values on older devices, four on newer ones. Both are sent as
        // they came: the missing scalar is reconstructed in Dart, where the
        // clamp against a rounding error can be tested.
        val count = if (event.values.size >= 4) 4 else 3
        val payload = DoubleArray(count + 1)
        for (i in 0 until count) payload[i] = event.values[i].toDouble()
        payload[count] = displayRotationDegrees().toDouble()
        sink.success(payload.toList())
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit

    /**
     * How far the screen is turned, asked of the display manager.
     *
     * **Not `context.display`.** The context a plugin is given is the
     * application's, which is not associated with a display, and asking it for
     * one throws — inside a sensor callback, where the exception reaches JNI as
     * a pending throwable and aborts the process. `DisplayManager` answers from
     * any context, which is the whole reason it exists.
     */
    private fun displayRotationDegrees(): Int {
        val displays = context?.getSystemService(Context.DISPLAY_SERVICE)
            as? DisplayManager
        val rotation = displays?.getDisplay(Display.DEFAULT_DISPLAY)?.rotation
        return when (rotation) {
            Surface.ROTATION_90 -> 90
            Surface.ROTATION_180 -> 180
            Surface.ROTATION_270 -> 270
            else -> 0
        }
    }
}
