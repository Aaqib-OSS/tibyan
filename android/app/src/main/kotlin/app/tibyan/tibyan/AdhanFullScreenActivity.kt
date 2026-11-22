package app.tibyan.tibyan

import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import android.util.TypedValue
import android.view.Gravity
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

/**
 * The full-screen adhan over the lock screen, opened by the adhan
 * notification's full-screen intent. Only the FULLSCREEN_ADHAN build
 * declares USE_FULL_SCREEN_INTENT, so only it can open this.
 */
class AdhanFullScreenActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val title = intent.getStringExtra("title") ?: ""
        val body = intent.getStringExtra("body") ?: ""
        val payload = intent.getStringExtra("payload") ?: ""
        val pad = (24 * resources.displayMetrics.density).toInt()
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(pad, pad, pad, pad)
            setBackgroundColor(Color.parseColor("#2A1D4C"))
        }
        root.addView(TextView(this).apply {
            text = title
            setTextColor(Color.parseColor("#FFD889"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 30f)
            gravity = Gravity.CENTER
        })
        root.addView(TextView(this).apply {
            text = body
            setTextColor(Color.parseColor("#FFF2E4"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            gravity = Gravity.CENTER
            setPadding(0, pad / 2, 0, pad)
        })
        root.addView(Button(this).apply {
            text = getString(R.string.adhan_stop)
            minHeight = (56 * resources.displayMetrics.density).toInt()
            setOnClickListener {
                AdhanService.stop(this@AdhanFullScreenActivity)
                finish()
            }
        })
        root.addView(Button(this).apply {
            text = getString(R.string.adhan_open_app)
            minHeight = (48 * resources.displayMetrics.density).toInt()
            setOnClickListener {
                val open = Intent(this@AdhanFullScreenActivity, MainActivity::class.java)
                    .setAction(Intent.ACTION_VIEW)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                if (payload.isNotEmpty()) open.data = android.net.Uri.parse(payload)
                startActivity(open)
                finish()
            }
        })
        setContentView(root)
        // The adhan ends: the screen closes.
        AdhanService.onFinished = { runOnUiThread { finish() } }
    }

    override fun onDestroy() {
        AdhanService.onFinished = null
        super.onDestroy()
    }
}
