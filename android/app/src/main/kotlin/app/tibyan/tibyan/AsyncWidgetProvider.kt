package app.tibyan.tibyan

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import es.antonborri.home_widget.HomeWidgetProvider
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * A home screen widget whose broadcasts are answered off the main thread.
 *
 * Drawing a widget (WidgetLooks: decoding its picture, loading the Uthmanic
 * and Changa fonts from the APK, laying out its text) used to run in
 * onReceive on the main thread, four providers per update the app asks for,
 * and for a widget's first update in a process started just for it (a cold
 * start in the background). That main-thread time counts toward the
 * broadcast's ANR budget (GlitchTip 18, "Background ANR"). goAsync() keeps
 * the broadcast open while one shared worker draws, one widget at a time
 * (WidgetLooks caches its fonts in plain fields).
 */
abstract class AsyncWidgetProvider : HomeWidgetProvider() {
  final override fun onReceive(context: Context, intent: Intent) {
    val pending: BroadcastReceiver.PendingResult? = goAsync()
    worker.execute {
      try {
        handle(context.applicationContext, intent)
      } catch (e: Exception) {
        android.util.Log.w("TibyanWidget", "widget update failed", e)
      } finally {
        pending?.finish()
      }
    }
  }

  /** What onReceive did, on the worker thread. */
  open fun handle(context: Context, intent: Intent) = super.onReceive(context, intent)

  companion object {
    val worker: ExecutorService = Executors.newSingleThreadExecutor()
  }
}
