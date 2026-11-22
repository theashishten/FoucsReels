package com.example.focus_reels

import android.content.Context
import android.os.Handler
import android.os.Looper
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/**
 * Pushes daily reel totals (and nothing else) to the user's Focus Reels server so friends can see them.
 * Does nothing until the user has joined a server in the Friends tab.
 */
object Sync {
    private var lastPush = 0L
    private var trailingScheduled = false

    fun push(ctx: Context, force: Boolean = false) {
        val social = Store.obj(ctx, "social", "{}")
        val url = social.optString("url")
        val token = social.optString("token")
        if (token.isEmpty() || !(url.startsWith("https://") || url.startsWith("http://"))) return
        val now = System.currentTimeMillis()
        if (!force && now - lastPush < 60_000) {
            // Too soon: schedule one trailing push so the latest count is not left behind.
            if (!trailingScheduled) {
                trailingScheduled = true
                Handler(Looper.getMainLooper()).postDelayed({
                    trailingScheduled = false
                    push(ctx.applicationContext, force = true)
                }, 60_000 - (now - lastPush) + 500)
            }
            return
        }
        lastPush = now

        // Last 7 days: today from the live counter, earlier days from history.
        val days = JSONObject()
        val hist = Store.history(ctx)
        for (k in hist.keys().asSequence().sorted().toList().takeLast(6)) days.put(k, hist.optInt(k))
        val today = Store.today(ctx)
        days.put(today.optString("day"), today.optInt("total"))
        val body = JSONObject().put("days", days).toString()

        Thread {
            try {
                val c = URL("$url/sync").openConnection() as HttpURLConnection
                c.requestMethod = "POST"
                c.connectTimeout = 5000
                c.readTimeout = 5000
                c.doOutput = true
                c.setRequestProperty("Authorization", "Bearer $token")
                c.setRequestProperty("Content-Type", "application/json")
                c.outputStream.use { it.write(body.toByteArray()) }
                c.responseCode
                c.disconnect()
            } catch (_: Exception) {
                // Offline or server down: the next counted reel tries again.
            }
        }.start()
    }
}
