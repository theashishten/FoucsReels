package com.example.focus_reels

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.os.Bundle
import android.os.CountDownTimer
import android.text.InputType
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast

/**
 * Full-screen block screen shown over a reel app, built in code with no layout resources.
 * Reasons: hard, cooldown, schedule, limit, applimit. (The friction pause is an overlay, see the service.)
 */
class BlockActivity : Activity() {
    private var timer: CountDownTimer? = null

    private fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()

    override fun onCreate(b: Bundle?) {
        super.onCreate(b)
        val reason = intent.getStringExtra("reason") ?: "limit"
        val now = System.currentTimeMillis()
        val st = Store.status(this)
        val cfg = Store.config(this)
        // With a remote buddy, pausing needs their approval, which is requested from inside the app.
        val strict = cfg.optBoolean("strict", false) || cfg.optBoolean("remoteBuddy", false)
        val until = when (reason) {
            "hard" -> st.optLong("hardBlockUntil")
            "cooldown" -> st.optLong("blockedUntil")
            else -> 0L
        }
        val today = Store.today(this)
        val total = today.optInt("total")
        val limit = cfg.optInt("dailyLimit", 0)

        val (icon, title, detail) = when (reason) {
            "plan" -> Triple("🛡️", "Reels are blocked", "Your plan is Block all. Change the plan in Focus Reels to watch.")
            "browser" -> Triple("🌐", "Shorts are blocked here too", "Short videos are blocked in your browser as well.")
            "always" -> Triple("🚫", "Reels are turned off", "You switched reels off for this app.")
            "hard" -> Triple("🔒", "Hard block is on", "Reels are locked until the timer ends.")
            "cooldown" -> Triple("⏳", "Time for a breather",
                "You used your reels for this window. They unlock when the timer ends.")
            "schedule" -> Triple("🌙", "Focus time", "Reels are blocked during your scheduled hours.")
            "apptimer" -> Triple("⏱️", "App timer finished", "You've used up today's time for this app.")
            "applimit" -> Triple("📵", "App limit reached", "You've used up this app's reels for today.")
            else -> Triple("🎯", "That's your limit",
                if (limit > 0) "You've watched $total of $limit reels today. Nice work stopping here."
                else "You've reached your daily limit.")
        }

        window.statusBarColor = Color.parseColor("#151110")
        window.navigationBarColor = Color.parseColor("#151110")

        // Outer view paints the gradient and respects system bars; inner view holds the padded content.
        // (fitsSystemWindows replaces a view's own padding, so the two jobs must be on different views.)
        val outer = LinearLayout(this).apply {
            fitsSystemWindows = true
            background = GradientDrawable(
                GradientDrawable.Orientation.TOP_BOTTOM,
                intArrayOf(Color.parseColor("#151110"), Color.parseColor("#151110"))
            )
        }
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(dp(32), dp(24), dp(32), dp(24))
        }
        outer.addView(root, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))

        // Soft circular badge with an icon.
        val badge = TextView(this).apply {
            text = icon
            textSize = 44f
            gravity = Gravity.CENTER
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor("#2C2420"))
            }
        }
        root.addView(badge, LinearLayout.LayoutParams(dp(112), dp(112)).apply { bottomMargin = dp(28) })

        root.addView(label(title, 28f, "#EDE0D8", bold = true).apply { gravity = Gravity.CENTER })
        root.addView(
            label(detail, 15f, "#B5A89E").apply { gravity = Gravity.CENTER },
            lp().apply { topMargin = dp(10); bottomMargin = dp(8) }
        )

        val clock = label("", 52f, "#FFB59F", bold = true).apply {
            gravity = Gravity.CENTER
            typeface = Typeface.create("sans-serif-light", Typeface.BOLD)
        }
        if (until > now) root.addView(clock, lp().apply { topMargin = dp(12); bottomMargin = dp(4) })

        root.addView(View(this), LinearLayout.LayoutParams(1, dp(28)))

        root.addView(
            pill("Go home", filled = true) { goHome() },
            lp(dp(56)).apply { bottomMargin = dp(14) }
        )
        if (!strict && reason != "hard" && reason != "always" && reason != "plan" && reason != "browser") {
            val hasPin = cfg.optString("buddyPin").isNotEmpty()
            root.addView(
                pill(if (hasPin) "Pause for 5 min  (PIN)" else "Pause for 5 min", filled = false) {
                    askPinThen { doPause() }
                },
                lp(dp(56))
            )
        }
        root.addView(
            label("Your time is worth more than the next reel.", 12f, "#857A71").apply { gravity = Gravity.CENTER },
            lp().apply { topMargin = dp(36) }
        )
        setContentView(outer)

        if (until > now) {
            timer = object : CountDownTimer(until - now, 1000) {
                override fun onTick(ms: Long) {
                    val s = ms / 1000
                    clock.text = "%d:%02d".format(s / 60, s % 60)
                }

                override fun onFinish() { finish() }
            }.start()
        }
    }

    private fun lp(h: Int = ViewGroup.LayoutParams.WRAP_CONTENT) =
        LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, h)

    private fun label(t: String, sp: Float, color: String, bold: Boolean = false) = TextView(this).apply {
        text = t
        textSize = sp
        setTextColor(Color.parseColor(color))
        if (bold) typeface = Typeface.DEFAULT_BOLD
        setLineSpacing(0f, 1.15f)
    }

    /** A rounded pill button: solid lilac when [filled], outlined otherwise. */
    private fun pill(text: String, filled: Boolean, onClick: () -> Unit): TextView {
        val shape = GradientDrawable().apply {
            cornerRadius = dp(28).toFloat()
            if (filled) setColor(Color.parseColor("#FFB59F"))
            else {
                setColor(Color.TRANSPARENT)
                setStroke(dp(2), Color.parseColor("#3A312B"))
            }
        }
        return TextView(this).apply {
            this.text = text
            textSize = 16f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setTextColor(Color.parseColor(if (filled) "#5A1503" else "#FFB59F"))
            background = RippleDrawable(ColorStateList.valueOf(Color.parseColor("#33FFFFFF")), shape, null)
            isClickable = true
            setOnClickListener { onClick() }
        }
    }

    private fun doPause() {
        Engine.pause(this, 5, System.currentTimeMillis())
        finish()
    }

    /** Runs [action] right away, or after the buddy PIN is entered correctly when one is set. */
    private fun askPinThen(action: () -> Unit) {
        val pin = Store.config(this).optString("buddyPin")
        if (pin.isEmpty()) { action(); return }
        val input = EditText(this).apply {
            inputType = InputType.TYPE_CLASS_NUMBER or InputType.TYPE_NUMBER_VARIATION_PASSWORD
        }
        AlertDialog.Builder(this)
            .setTitle("Buddy PIN")
            .setMessage("Ask your buddy for the PIN to pause blocking.")
            .setView(input)
            .setPositiveButton("OK") { _, _ ->
                if (input.text.toString() == pin) action()
                else Toast.makeText(this, "Wrong PIN", Toast.LENGTH_SHORT).show()
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    private fun goHome() {
        startActivity(
            Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
        finish()
    }

    @Deprecated("Back always goes home so the block can't be dodged")
    override fun onBackPressed() = goHome()

    override fun onDestroy() {
        timer?.cancel()
        super.onDestroy()
    }
}
