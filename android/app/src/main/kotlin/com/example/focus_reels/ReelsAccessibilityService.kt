package com.example.focus_reels

import android.accessibilityservice.AccessibilityService
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Rect
import android.os.CountDownTimer
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

/**
 * Counts reels (not raw scrolls) and enforces the block rules.
 * A reel counts when a page-swipe scroll happens on a recognised reel surface.
 * Surface ids are heuristics and may need tuning per app version; see Diagnostics in the app.
 */
class ReelsAccessibilityService : AccessibilityService() {
    private var lastCountAt = 0L
    private var lastCheckAt = 0L
    private var lastBlockShownAt = 0L
    private var screenOn = true
    private var lastSurfaceAt = 0L
    private var sessionCount = 0
    private val handler = Handler(Looper.getMainLooper())

    /** Runs 3 minutes after the last reel: if the session was long, ask the user to reflect on it. */
    private val endSession = Runnable {
        if (sessionCount >= 10 && Store.config(this).optBoolean("reflect", true)) {
            Notifier.post(this, 3, "Session over", "You just watched $sessionCount reels. Can you name three of them?")
        }
        sessionCount = 0
    }

    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(c: Context?, i: Intent?) {
            screenOn = i?.action != Intent.ACTION_SCREEN_OFF
            if (!screenOn) curPkg = null
        }
    }

    /**
     * View ids that mean "a reel is on screen" for an app: the built-in ones plus any you added under
     * Detection rules. Null means the app has none (it then uses its own special detector or the heuristic).
     */
    private fun detectorIds(pkg: String): List<String>? {
        val custom = Store.obj(this, "detectors", "{}").optJSONArray(pkg)
        val extra = if (custom == null) emptyList() else (0 until custom.length()).map { custom.getString(it) }
        val all = (extra + (Engine.DEFAULT_DETECTORS[pkg] ?: emptyList())).distinct()
        return all.ifEmpty { null }
    }

    /**
     * A swipe of the full-screen reel pager itself, upwards (to the next reel). Scrolling the comments, a carousel,
     * a list inside the reel or the feed does not count: those scroll containers are smaller than the pager, so the
     * scrolling view must fill nearly the whole screen. When Android reports scroll distances, the swipe must also be
     * mostly vertical and go to the next reel.
     */
    private fun reelPagerSwipe(e: AccessibilityEvent): Boolean {
        val src = e.source ?: return false
        val r = Rect()
        src.getBoundsInScreen(r)
        val dm = resources.displayMetrics
        if (r.height() < dm.heightPixels * 0.75 || r.width() < dm.widthPixels * 0.9) return false
        if (!verticalSwipe(e)) return false
        if (android.os.Build.VERSION.SDK_INT >= 28 && e.scrollDeltaY < 0) return false // swiping back to a previous reel
        return true
    }

    /** A real vertical swipe: when Android reports scroll distances, vertical must win over horizontal. */
    private fun verticalSwipe(e: AccessibilityEvent): Boolean {
        if (android.os.Build.VERSION.SDK_INT < 28) return true
        val dy = e.scrollDeltaY
        val dx = e.scrollDeltaX
        if (dy == 0 && dx == 0) return true // not reported, so we cannot tell
        return Math.abs(dy) >= Math.abs(dx)
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        screenOn = (getSystemService(Context.POWER_SERVICE) as PowerManager).isInteractive
        instance = this
        applyScope()
        handler.removeCallbacks(screenTick)
        handler.postDelayed(screenTick, 5000)
        registerReceiver(
            screenReceiver,
            IntentFilter().apply {
                addAction(Intent.ACTION_SCREEN_ON)
                addAction(Intent.ACTION_SCREEN_OFF)
            },
            Context.RECEIVER_NOT_EXPORTED
        )
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        removeCover()
        removeQuick()
        removeBubble()
        frictionTimer?.cancel()
        frictionView?.let {
            try { (getSystemService(Context.WINDOW_SERVICE) as WindowManager).removeView(it) } catch (_: Exception) {}
        }
        handler.removeCallbacksAndMessages(null)
        try { unregisterReceiver(screenReceiver) } catch (_: Exception) {}
        super.onDestroy()
    }

    override fun onAccessibilityEvent(e: AccessibilityEvent?) {
        e ?: return
        val pkg = e.packageName?.toString() ?: return
        trackScreen(pkg, e.eventType)
        if (screenOn && checkTimer(pkg)) return
        if (pkg in Engine.BROWSERS) {
            if (screenOn) checkBrowser(pkg)
            return
        }
        if (pkg !in Engine.TARGETS || !screenOn) return
        val type = e.eventType
        // Instagram's reel pager reports which page it is on, so the direction of a swipe is known: a lower page number
        // than before means you went back.
        if (pkg == IG && e.eventType == AccessibilityEvent.TYPE_VIEW_SCROLLED &&
            e.className?.toString()?.contains("ViewPager") == true
        ) {
            val idx = e.fromIndex
            if (idx >= 0) {
                if (igIdx >= 0) {
                    if (idx < igIdx) igBack = true else if (idx > igIdx) igBack = false
                }
                igIdx = idx
            }
        }
        val nowIdle = System.currentTimeMillis()
        val idleMs = nowIdle - (lastSeenApp[pkg] ?: 0L)
        lastSeenApp[pkg] = nowIdle
        // The first event after 30+ seconds away means the app is being (re)started; arm the safe-page redirect.
        if (idleMs >= 30_000) launchArmedAt[pkg] = nowIdle
        if (type == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) launchSafe(pkg, e, nowIdle)
        if (type != AccessibilityEvent.TYPE_VIEW_SCROLLED &&
            type != AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED &&
            type != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
        ) return
        val now = System.currentTimeMillis()
        // Throttle the expensive tree lookups.
        if (type != AccessibilityEvent.TYPE_VIEW_SCROLLED && now - lastCheckAt < 100) return
        lastCheckAt = now

        val cfg = Store.config(this)
        updateCover(pkg, cfg)
        if (!Engine.appEnabled(cfg, pkg)) return
        val onSurface = onReelSurface(pkg, e)
        if (now - lastDumpAt > 1500) { lastDumpAt = now; dumpIds(pkg) }
        Store.putString(this, "lastEvent", "${eventName(type)} $pkg ${e.className} surface=$onSurface")
        // Netflix: read the clip title shortly after activity settles (see nfSettle); no per-event decision.
        if (pkg == NETFLIX) {
            // Throttle, don't debounce: Netflix emits events constantly, so a debounce would never fire.
            if (!nfPending) { nfPending = true; handler.postDelayed(nfSettle, 350) }
        }
        if (!onSurface) {
            if (pkg == YT) { ytOnSurface = false; ytLastLength = null; ytSpinnerSeen = false; ytRow = -1; ytMax = -1 }
            if (pkg == IG) { igOnSurface = false; igSig = null; igLastCap = ""; igSeen.clear(); igIdx = -1; igBack = false }
            if (pkg == SNAP) { snapSig = null; snapSeen.clear() }
            removeBubble()
            return
        }
        if (pkg == SNAP && !snapPending) { snapPending = true; handler.postDelayed(snapSettle, 350) }
        // No live counter where reels are always blocked: nothing is being watched.
        if (!Engine.appFlag(cfg, pkg, "alwaysBlock")) showBubble()

        val sinceSurface = now - lastSurfaceAt
        lastSurfaceAt = now

        val reason = Engine.blockReason(this, pkg, now)
        if (reason != null) {
            showBlock(reason, now, pkg = pkg)
            return
        }
        // Friction: after 5+ minutes away from reels, make the user pause before scrolling again.
        val frictionSeconds = cfg.optInt("frictionSeconds", 0)
        if (frictionSeconds > 0 && sinceSurface > 300_000) showFriction(frictionSeconds)

        // YouTube Shorts rarely sends scroll events, so detect a page change from the player itself.
        val isNewReel = if (pkg == YT) {
            val changed = youtubePageChanged()
            // The first look after entering Shorts only sets the baseline; it is not a swipe.
            if (!ytOnSurface) { ytOnSurface = true; false } else changed
        } else if (pkg == IG) {
            // Instagram labels each reel ("Reel by <author>. ..."); a reel counts when that label changes, so
            // scrolling comments, an ad that will not move, or random scroll events never count.
            val changed = instagramReelChanged()
            if (!igOnSurface) { igOnSurface = true; false } else changed
        } else if (pkg == NETFLIX) {
            false // counted by nfSettle once the new clip's title is readable
        } else if (pkg == SNAP) {
            false // counted by snapSettle once the new video's labels are readable
        } else type == AccessibilityEvent.TYPE_VIEW_SCROLLED && reelPagerSwipe(e)
        if (isNewReel && now - lastCountAt >= 700) countReel(pkg, now)
    }

    // ---- Screen time and scroll bursts for every app (package name + event type only) ----
    private var curPkg: String? = null
    private val lastScrollAt = HashMap<String, Long>()
    private var tickCount = 0
    private val screenTick = object : Runnable {
        override fun run() {
            val p = curPkg
            if (p != null && screenOn) ScreenTime.addTime(this@ReelsAccessibilityService, p, 5000)
            // Keep the permanent all-app usage history topped up even if the app is never opened.
            if (++tickCount % 360 == 1) Thread { AppUsage.refresh(this@ReelsAccessibilityService) }.start()
            handler.postDelayed(this, 5000)
        }
    }

    private fun trackScreen(pkg: String, type: Int) {
        if (!screenOn || !Store.config(this).optBoolean("screenTime", false)) return
        if (ScreenTime.isLauncher(this, pkg)) { curPkg = null; return }
        if (ScreenTime.ignored(this, pkg)) return
        curPkg = pkg
        if (type == AccessibilityEvent.TYPE_VIEW_SCROLLED) {
            val now = System.currentTimeMillis()
            if (now - (lastScrollAt[pkg] ?: 0L) > 600) {
                lastScrollAt[pkg] = now
                ScreenTime.addScroll(this, pkg)
            }
        }
    }


    // ---- Hide the Reels / Shorts tab: a solid, tap-blocking cover drawn over that tab button ----
    private var cover: View? = null
    private var coverPkg: String? = null
    private var lastCoverAt = 0L

    private val coverWatch = object : Runnable {
        override fun run() {
            // The cover must disappear as soon as that app is no longer on screen.
            if (rootInActiveWindow?.packageName?.toString() != coverPkg) removeCover()
            else handler.postDelayed(this, 700)
        }
    }

    private fun removeCover() {
        handler.removeCallbacks(coverWatch)
        cover?.let {
            try { (getSystemService(Context.WINDOW_SERVICE) as WindowManager).removeView(it) } catch (_: Exception) {}
        }
        cover = null
        coverPkg = null
    }

    /** Screen rectangle of the Reels (Instagram) or Shorts (YouTube) tab button, or null if not visible. */
    private fun findTabRect(pkg: String): Rect? {
        val root = rootInActiveWindow ?: return null
        val h = resources.displayMetrics.heightPixels
        val w = resources.displayMetrics.widthPixels
        val candidates = ArrayList<AccessibilityNodeInfo>()
        if (pkg == "com.instagram.android") {
            candidates += root.findAccessibilityNodeInfosByViewId("$pkg:id/clips_tab")
        }
        val word = if (pkg == "com.instagram.android") "Reels" else "Shorts"
        candidates += root.findAccessibilityNodeInfosByText(word)
        for (n in candidates) {
            var node: AccessibilityNodeInfo? = n
            val r = Rect()
            // Climb to the clickable tab container, but never to something wider than a third of the screen.
            while (node != null) {
                node.getBoundsInScreen(r)
                if (node.isClickable && r.width() in 1..(w / 3)) break
                node = node.parent
            }
            if (node == null) { n.getBoundsInScreen(r) }
            if (r.width() <= 0 || r.height() <= 0 || r.width() > w / 2) continue
            // Only the bottom navigation bar counts, not a "Reels" heading higher up the screen.
            if (r.top < h * 0.8) continue
            return Rect(r)
        }
        return null
    }

    private fun updateCover(pkg: String, cfg: org.json.JSONObject) {
        if (!Engine.appFlag(cfg, pkg, "hideTab")) {
            if (coverPkg == pkg) removeCover()
            return
        }
        val now = System.currentTimeMillis()
        if (now - lastCoverAt < 150) return
        lastCoverAt = now
        val r = findTabRect(pkg) ?: return
        val night = (resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK) ==
            android.content.res.Configuration.UI_MODE_NIGHT_YES
        val color = when {
            !night -> Color.WHITE
            pkg == "com.google.android.youtube" -> Color.parseColor("#0F0F0F")
            else -> Color.parseColor("#0C1014")
        }
        val wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val lp = WindowManager.LayoutParams(
            r.width() + 6, r.height() + 6,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.OPAQUE
        ).apply { gravity = Gravity.TOP or Gravity.START; x = r.left - 3; y = r.top - 3 }
        val v = cover
        if (v == null) {
            val nv = View(this).apply { setBackgroundColor(color) }
            try { wm.addView(nv, lp) } catch (_: Exception) { return }
            cover = nv
            coverPkg = pkg
            handler.removeCallbacks(coverWatch)
            handler.postDelayed(coverWatch, 700)
        } else {
            v.setBackgroundColor(color)
            try { wm.updateViewLayout(v, lp) } catch (_: Exception) {}
        }
    }

    // ---- Per-app daily timers (any app): usage comes from Android's usage log, re-read every 15 s ----
    private val timerUsed = HashMap<String, Long>()
    private val timerCheckedAt = HashMap<String, Long>()

    /** True when [pkg] has a daily timer that has run out, after showing the block screen. */
    private fun checkTimer(pkg: String): Boolean {
        val timers = Store.config(this).optJSONObject("appTimers") ?: return false
        val minutes = timers.optInt(pkg, 0)
        if (minutes <= 0) return false
        val now = System.currentTimeMillis()
        val st = Store.status(this)
        if (!Store.config(this).optBoolean("strict", false) && st.optLong("pausedUntil") > now) return false
        if (now - (timerCheckedAt[pkg] ?: 0L) > 15_000) {
            timerCheckedAt[pkg] = now
            timerUsed[pkg] = AppUsage.todayMs(this, pkg)
        }
        Store.putString(this, "lastTimer", "$pkg used=${timerUsed[pkg]} limitMin=$minutes at=$now")
        if ((timerUsed[pkg] ?: 0L) < minutes * 60_000L) return false
        showBlock("apptimer", now, reelApp = false, pkg = pkg)
        return true
    }

    /** Single tap in the middle of the screen: pauses the playing video just before a block exits it. */
    private fun tapCenter() {
        try {
            val dm = resources.displayMetrics
            val path = android.graphics.Path().apply { moveTo(dm.widthPixels / 2f, dm.heightPixels / 2f) }
            val g = android.accessibilityservice.GestureDescription.Builder()
                .addStroke(android.accessibilityservice.GestureDescription.StrokeDescription(path, 0, 40)).build()
            dispatchGesture(g, null, null)
        } catch (_: Exception) {}
    }

    /** Records one reel and handles everything that follows from it (counter, session, new blocks). */
    private fun countReel(pkg: String, now: Long) {
        lastCountAt = now
        Engine.registerReel(this, pkg, now)
        showBubble()
        sessionCount++
        handler.removeCallbacks(endSession)
        handler.postDelayed(endSession, 180_000)
        // A cooldown may have just started because the window allowance was exceeded.
        Engine.blockReason(this, pkg, now)?.let { showBlock(it, now, pkg = pkg) }
    }

    /**
     * Netflix Clips sends no scroll events and its screen flickers during a swipe, so the only reliable
     * evidence of a new clip is its title, read once the screen has settled 600 ms after the last event.
     * Coming back after more than 5 s away only re-sets the baseline, so re-entering never counts.
     */
    private var nfPending = false
    private val nfSettle = Runnable {
        nfPending = false
        val now = System.currentTimeMillis()
        val title = netflixClipTitle() ?: return@Runnable
        val fresh = nfTitle != null && now - nfLastSeenAt < 5000
        if (!fresh) nfSeen.clear()
        val changed = fresh && title != nfTitle
        nfTitle = title
        nfLastSeenAt = now
        // A clip already seen in this visit is not counted again when you go back to it.
        val seenBefore = !nfSeen.add(title)
        if (nfSeen.size > 80) nfSeen.remove(nfSeen.first())
        val newClip = !seenBefore || Store.config(this).optBoolean("countBack", false)
        if (changed && newClip && now - lastCountAt >= 700 && Engine.blockReason(this, NETFLIX, now) == null) {
            countReel(NETFLIX, now)
        }
    }

    private fun onReelSurface(pkg: String, e: AccessibilityEvent): Boolean {
        val ids = detectorIds(pkg)
        if (ids != null) {
            val root = rootInActiveWindow ?: return false
            if (pkg == IG) {
                // Instagram's feed and search also contain small reel rows (for example "Suggested reels"). Only the
                // full-screen reel viewer counts as the reels screen.
                val dm = resources.displayMetrics
                return ids.any { id ->
                    root.findAccessibilityNodeInfosByViewId("$pkg:id/$id").any { n ->
                        val r = Rect()
                        n.getBoundsInScreen(r)
                        r.height() >= dm.heightPixels * 0.7 && r.width() >= dm.widthPixels * 0.9
                    }
                }
            }
            return ids.any { root.findAccessibilityNodeInfosByViewId("$pkg:id/$it").isNotEmpty() }
        }
        // Facebook hides its view ids and its feed shares labels with Reels, and Snapchat Spotlight has
        // no tested detector. Counting nothing beats blocking people for scrolling a normal feed.
        if (pkg == "com.facebook.katana") return false
        // Netflix Clips: only that screen has both a "Seek bar" and a "More details for <title>" control.
        if (pkg == NETFLIX) return netflixClipTitle() != null
        // Snapchat Spotlight videos have a like ("favorite") button; the chat list and camera do not.
        if (pkg == SNAP) {
            val root = rootInActiveWindow ?: return false
            return root.findAccessibilityNodeInfosByViewId("$SNAP:id/favorite").isNotEmpty()
        }
        // Generic (TikTok): a scrolling node that fills most of the screen, e.g. a vertical video pager.
        val src: AccessibilityNodeInfo = e.source ?: return false
        val r = Rect()
        src.getBoundsInScreen(r)
        val dm = resources.displayMetrics
        return r.height() >= dm.heightPixels * 0.8 && r.width() >= dm.widthPixels * 0.9
    }

    /** Counter position: bubbleX is the horizontal centre (0 left .. 1 right, default 0.5), bubbleY the top (0..1 of the screen height). */
    private fun applyBubblePosition(lp: WindowManager.LayoutParams, cfg: org.json.JSONObject) {
        val dm = resources.displayMetrics
        val x = cfg.optDouble("bubbleX", 0.5).coerceIn(0.05, 0.95)
        lp.gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
        lp.x = ((x - 0.5) * dm.widthPixels).toInt()
        lp.y = if (cfg.has("bubbleY")) (cfg.optDouble("bubbleY").coerceIn(0.0, 0.93) * dm.heightPixels).toInt() else 58
    }

    private var bubble: CounterView? = null
    private val hideBubble = Runnable { removeBubble() }

    private fun removeBubble() {
        if (bubble?.isDragging == true) return
        handler.removeCallbacks(hideBubble)
        bubble?.let {
            try { (getSystemService(Context.WINDOW_SERVICE) as WindowManager).removeView(it) } catch (_: Exception) {}
        }
        bubble = null
    }

    /**
     * The live counter over a reel app: a pill with a progress ring and a short caption. The ring tracks the daily
     * limit (or the "curious" timer) and shifts green, amber, red as you near it; in track-only mode it is a plain
     * ring captioned "today". It hides itself 4 seconds after the last reel-screen event, so it disappears when
     * you leave the app (we only receive events from reel apps, so there is no "left the app" event).
     */
    private fun showBubble() {
        val cfg = Store.config(this)
        if (!cfg.optBoolean("bubble", true)) { removeBubble(); return }
        val total = Store.today(this).optInt("total")
        val track = Engine.trackOnly(cfg)
        val plan = cfg.optString("plan", "none")
        val limit = if (track) 0 else cfg.optInt("dailyLimit", 0)
        val calm = Color.parseColor("#FFB59F")
        val good = Color.parseColor("#7FDDB0")
        val warn = Color.parseColor("#FFC46B")
        val bad = Color.parseColor("#FF7A7A")
        var frac = -1f
        var caption = "today"
        var color = calm
        if (!track && plan == "oneReel") {
            caption = "one reel"; color = warn
        } else if (!track && plan == "curious") {
            val st = Store.status(this)
            val start = st.optLong("curiousStart")
            val on = cfg.optInt("curiousOn", 5) * 60_000L
            if (start > 0) {
                val left = maxOf(0L, start + on - System.currentTimeMillis())
                frac = 1f - left.toFloat() / on
                caption = "${(left + 59_999) / 60_000}m left"
                color = if (frac < 0.6f) good else if (frac < 0.9f) warn else bad
            } else { caption = "${cfg.optInt("curiousOn", 5)}m on"; color = good }
        } else if (limit > 0) {
            frac = total.toFloat() / limit
            caption = if (total >= limit) "limit reached" else "${limit - total} left"
            color = if (frac < 0.6f) good else if (frac < 0.9f) warn else bad
        }
        val wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val view = bubble ?: CounterView(this).also {
            val lp = WindowManager.LayoutParams(
                WindowManager.LayoutParams.WRAP_CONTENT, WindowManager.LayoutParams.WRAP_CONTENT,
                WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
                // Touchable on purpose: press and hold the counter, then drag it to move it. Taps on the small
                // pill itself do not reach the app underneath.
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
                PixelFormat.TRANSLUCENT
            )
            applyBubblePosition(lp, cfg)
            try { wm.addView(it, lp) } catch (_: Exception) { return }
            bubble = it
            it.mover = object : CounterView.Mover {
                // The position is tracked here, not read back from the window, which may be adjusted by the system.
                private var px = 0
                private var py = 0
                private var started = false

                override fun onMove(dx: Float, dy: Float) {
                    val dm = resources.displayMetrics
                    val l = it.layoutParams as? WindowManager.LayoutParams ?: return
                    if (!started) { px = l.x; py = l.y; started = true }
                    px = (px + dx.toInt()).coerceIn(-(dm.widthPixels * 0.45).toInt(), (dm.widthPixels * 0.45).toInt())
                    py = (py + dy.toInt()).coerceIn(0, (dm.heightPixels * 0.93).toInt())
                    l.x = px; l.y = py
                    try { wm.updateViewLayout(it, l) } catch (_: Exception) {}
                    handler.removeCallbacks(hideBubble)
                }

                override fun onDrop() {
                    if (!started) return
                    started = false
                    val dm = resources.displayMetrics
                    val c = Store.config(this@ReelsAccessibilityService)
                    c.put("bubbleX", ((px.toDouble() / dm.widthPixels) + 0.5).coerceIn(0.05, 0.95))
                    c.put("bubbleY", (py.toDouble() / dm.heightPixels).coerceIn(0.0, 0.93))
                    Store.put(this@ReelsAccessibilityService, "config", c)
                    handler.removeCallbacks(hideBubble)
                    handler.postDelayed(hideBubble, 4000)
                }
            }
        }
        // Follow a change of position made in the app while the counter is showing.
        if (!view.isDragging) (view.layoutParams as? WindowManager.LayoutParams)?.let { lp ->
            val ox = lp.x; val oy = lp.y
            applyBubblePosition(lp, cfg)
            if (lp.x != ox || lp.y != oy) try { wm.updateViewLayout(view, lp) } catch (_: Exception) {}
        }
        view.set(total, frac, caption, color)
        handler.removeCallbacks(hideBubble)
        handler.postDelayed(hideBubble, 4000)
    }

    private var frictionView: View? = null
    private var frictionTimer: CountDownTimer? = null

    /**
     * Draws the "take a breath" screen as an accessibility overlay on top of the reel app. Unlike a
     * separate activity, this keeps the app in the foreground (so it does not shrink to a mini-player)
     * and Continue simply removes the overlay.
     */
    private fun showFriction(seconds: Int) {
        if (frictionView != null) return
        val wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        fun label(t: String, sp: Float, c: String) = TextView(this).apply {
            text = t; textSize = sp; gravity = Gravity.CENTER; setTextColor(Color.parseColor(c))
        }
        val clock = label("", 40f, "#B79CFF")
        val cont = Button(this).apply { text = "Continue"; isEnabled = false }
        val home = Button(this).apply { text = "Go home" }
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(Color.parseColor("#F014111F"))
            setPadding(64, 64, 64, 64)
            addView(label("Take a breath", 28f, "#FFFFFF"))
            addView(label("Do you really want to scroll right now?", 16f, "#B8B2D0"))
            addView(clock)
            addView(home)
            addView(cont)
        }
        fun dismiss() {
            frictionTimer?.cancel()
            frictionTimer = null
            frictionView?.let { try { wm.removeView(it) } catch (_: Exception) {} }
            frictionView = null
        }
        cont.setOnClickListener { dismiss() }
        home.setOnClickListener { dismiss(); performGlobalAction(GLOBAL_ACTION_HOME) }
        val lp = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT, WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN, PixelFormat.TRANSLUCENT
        )
        try { wm.addView(root, lp) } catch (_: Exception) { return }
        frictionView = root
        frictionTimer = object : CountDownTimer(seconds * 1000L, 1000) {
            override fun onTick(ms: Long) { clock.text = "0:%02d".format(ms / 1000) }
            override fun onFinish() { clock.text = "0:00"; cont.isEnabled = true }
        }.start()
    }

    private var lastDumpAt = 0L
    private var ytLastLength: String? = null
    private var ytSpinnerSeen = false
    private var ytOnSurface = false
    private var snapSig: String? = null
    private val snapSeen = LinkedHashSet<String>()
    private var nfTitle: String? = null
    private val nfSeen = LinkedHashSet<String>()
    private var nfLastSeenAt = 0L

    /** The current clip's title if the Netflix Clips feed is showing, else null. */
    private fun netflixClipTitle(): String? {
        val root = rootInActiveWindow ?: return null
        var seek = false
        var title: String? = null
        var seen = 0
        fun walk(n: AccessibilityNodeInfo?, depth: Int) {
            if (n == null || depth > 30 || seen++ > 600) return
            val d = (n.contentDescription ?: n.text)?.toString()
            if (d != null) {
                if (d == "Seek bar") seek = true
                if (d.startsWith("More details for ")) title = d.removePrefix("More details for ")
            }
            for (i in 0 until n.childCount) walk(n.getChild(i), depth + 1)
        }
        walk(root, 0)
        return if (seek) title else null
    }

    private var igSig: String? = null
    private var igLastCap = ""
    private var igIdx = -1
    private var igBack = false
    private val igSeen = LinkedHashSet<String>()
    private var igOnSurface = false

    /** True when the reel showing in Instagram's pager is a different one from the last time we looked. */
    private fun instagramReelChanged(): Boolean {
        val root = rootInActiveWindow ?: return false
        val dm = resources.displayMetrics
        // The pager keeps neighbouring reels alive, so take the one that is mostly on screen.
        var bestDesc: String? = null
        var bestArea = 0
        for (n in root.findAccessibilityNodeInfosByViewId("$IG:id/clips_media_component")) {
            val r = Rect()
            n.getBoundsInScreen(r)
            val visibleH = minOf(r.bottom, dm.heightPixels) - maxOf(r.top, 0)
            val area = if (visibleH > 0) visibleH * r.width() else 0
            if (area > bestArea) {
                bestArea = area
                bestDesc = n.contentDescription?.toString()
            }
        }
        // Two reels by the same account share the first label, so the caption is added to tell them apart.
        var cap = ""
        var capArea = 0
        for (n in root.findAccessibilityNodeInfosByViewId("$IG:id/clips_caption_component")) {
            val r = Rect()
            n.getBoundsInScreen(r)
            val visibleH = minOf(r.bottom, dm.heightPixels) - maxOf(r.top, 0)
            val area = if (visibleH > 0) visibleH * r.width() else 0
            if (area > capArea) {
                capArea = area
                var text: String? = null
                fun walk(x: AccessibilityNodeInfo?, depth: Int) {
                    if (x == null || text != null || depth > 4) return
                    val d = x.contentDescription?.toString()
                    if (!d.isNullOrBlank()) { text = d; return }
                    for (i in 0 until x.childCount) walk(x.getChild(i), depth + 1)
                }
                walk(n, 0)
                cap = text ?: ""
            }
        }
        // While the comments sheet or another panel covers the reel its caption is not readable; keep the last one
        // so that opening comments is never mistaken for a new reel.
        if (cap.isEmpty()) cap = igLastCap else igLastCap = cap
        val sig = (bestDesc?.take(80) ?: return false) + "|" + cap.take(60)
        val first = igSig == null
        val changed = !first && sig != igSig
        igSig = sig
        // Reels already seen in this visit are not counted again when you swipe back to them, unless the
        // "Count reels you go back to" option is on.
        val seenBefore = !igSeen.add(sig)
        if (igSeen.size > 80) igSeen.remove(igSeen.first())
        if (!changed) return false
        val countBack = Store.config(this).optBoolean("countBack", false)
        // Swiping back (even fast, through reels we never got to read) is not a new reel.
        if (igBack && !countBack) return false
        return countBack || !seenBefore
    }

    private var snapPending = false

    /**
     * Snapchat Spotlight keeps neighbouring videos in its tree and shows no page number, so the video is identified
     * once the screen has settled (350 ms after the last event) from the labels in the info area at the bottom of the
     * page that is actually on screen: creator, sound and caption. A video already seen in this visit is not counted
     * again when you swipe back to it.
     */
    private val snapSettle = Runnable {
        snapPending = false
        val now = System.currentTimeMillis()
        val root = rootInActiveWindow ?: return@Runnable
        val dm = resources.displayMetrics
        val labels = LinkedHashSet<String>()
        var seen = 0
        fun walk(n: AccessibilityNodeInfo?, depth: Int) {
            if (n == null || depth > 30 || seen++ > 700 || labels.size >= 3) return
            val t = (n.text ?: n.contentDescription)?.toString()?.trim()
            if (!t.isNullOrEmpty() && t.length > 2 && t != "Spotlight") {
                val r = Rect()
                n.getBoundsInScreen(r)
                // The info block of the visible video: lower part of the page, fully inside the screen.
                if (r.top >= dm.heightPixels * 0.55 && r.bottom <= dm.heightPixels * 0.93 && r.width() > 0) labels.add(t.take(60))
            }
            for (i in 0 until n.childCount) walk(n.getChild(i), depth + 1)
        }
        walk(root, 0)
        if (labels.isEmpty()) return@Runnable
        val sig = labels.joinToString("|")
        val first = snapSig == null
        val changed = !first && sig != snapSig
        snapSig = sig
        val seenBefore = !snapSeen.add(sig)
        if (snapSeen.size > 80) snapSeen.remove(snapSeen.first())
        val newVideo = !seenBefore || Store.config(this).optBoolean("countBack", false)
        if (changed && newVideo && now - lastCountAt >= 700 && Engine.blockReason(this, SNAP, now) == null) {
            countReel(SNAP, now)
        }
    }

    private var ytRow = -1
    private var ytMax = -1

    /** Finds "... of 0 minutes 17 seconds" on the bar or any descendant and returns the part after " of ". */
    private fun lengthText(n: AccessibilityNodeInfo, depth: Int): String? {
        val d = (n.contentDescription ?: n.text)?.toString()
        if (d != null && d.contains(" of ")) return d.substringAfter(" of ").takeIf { it.isNotEmpty() }
        if (depth > 4) return null
        for (i in 0 until n.childCount) {
            val r = n.getChild(i)?.let { lengthText(it, depth + 1) }
            if (r != null) return r
        }
        return null
    }

    /**
     * True when the Shorts player moved to a NEW Short. The pager reports each page's number, so going back to an
     * earlier Short is never counted (unless "Count reels you go back to" is on). Without a page number it falls
     * back to the progress bar length and the loading spinner.
     */
    private fun youtubePageChanged(): Boolean {
        val root = rootInActiveWindow ?: return false
        val dm = resources.displayMetrics
        // The pager keeps neighbouring pages around, so take the one that is mostly on screen.
        var row = -1
        var best = 0
        for (n in root.findAccessibilityNodeInfosByViewId("$YT:id/reel_player_page_container")) {
            val r = Rect()
            n.getBoundsInScreen(r)
            val visibleH = minOf(r.bottom, dm.heightPixels) - maxOf(r.top, 0)
            val area = if (visibleH > 0) visibleH * r.width() else 0
            val idx = n.collectionItemInfo?.rowIndex ?: -1
            if (area > best && idx >= 0) { best = area; row = idx }
        }
        val bar = root.findAccessibilityNodeInfosByViewId("$YT:id/reel_time_bar").firstOrNull()
        val length = bar?.let { lengthText(it, 0) }
        if (row >= 0) {
            if (length != null) ytLastLength = length
            val first = ytRow < 0
            val moved = !first && row != ytRow
            ytRow = row
            val frontier = row > ytMax
            if (frontier) ytMax = row
            if (!moved) return false
            return frontier || Store.config(this).optBoolean("countBack", false)
        }
        val spinner = root.findAccessibilityNodeInfosByViewId("$YT:id/reel_playback_loading_spinner").isNotEmpty()
        var changed = false
        if (length != null) {
            if (ytLastLength != null && length != ytLastLength) changed = true
            ytLastLength = length
        }
        if (spinner && !ytSpinnerSeen) changed = true
        ytSpinnerSeen = spinner
        return changed
    }

    /** Diagnostics: remember the view ids (and scrollable classes) currently on screen for this app. */
    private fun dumpIds(pkg: String) {
        val root = rootInActiveWindow ?: return
        val ids = linkedSetOf<String>()
        fun walk(n: AccessibilityNodeInfo?, depth: Int) {
            if (n == null || depth > 25 || ids.size > 80) return
            val label = (n.text ?: n.contentDescription)?.toString()?.take(80)
            val id = n.viewIdResourceName?.substringAfter(":id/")
            if (id != null || label != null) {
                ids.add((id ?: "-") + (if (n.isScrollable) "*" else "") + (if (n.isSelected) "^" else "") +
                    (if (label != null) "=\"$label\"" else ""))
            }
            for (i in 0 until n.childCount) walk(n.getChild(i), depth + 1)
        }
        walk(root, 0)
        Store.putString(this, "lastIds", "$pkg: " + ids.joinToString(","))
    }

    private fun showBlock(reason: String, now: Long, reelApp: Boolean = true, pkg: String = "", browser: Boolean = false) {
        if (now - lastBlockShownAt < 1500) return
        lastBlockShownAt = now
        removeBubble()
        val cfg = Store.config(this)
        // What to do when a block fires: go back (default), go home, or lock the screen. Timers always go home.
        var action = if (reelApp) Engine.blockAction(cfg, pkg) else "home"
        if (action == "lock" && android.os.Build.VERSION.SDK_INT < 28) action = "home"
        Engine.noteBlock(this, pkg, reason, action)
        when (action) {
            "lock" -> performGlobalAction(GLOBAL_ACTION_LOCK_SCREEN)
            "home" -> performGlobalAction(GLOBAL_ACTION_HOME)
            else -> if (reelApp) {
                // Leave the reel player first so the video stops instead of lingering in a mini-player.
                // The block only fires while on a reel surface, so this cannot repeat and exit the app.
                // "Always block" goes to the app's Home tab so you stay in the app; Back from a reel that is the app's
                // first screen would close the whole app. No tap is made first: tapping the middle of the Home feed
                // would open a post. If there is no Home tab to tap, fall back to pausing the video and pressing Back.
                if (reason == "always" && !browser && clickHomeTab(pkg)) {
                    // done
                } else {
                    if (!browser) tapCenter()
                    handler.postDelayed({ performGlobalAction(GLOBAL_ACTION_BACK) }, if (browser) 0 else 120)
                }
            } else {
                performGlobalAction(GLOBAL_ACTION_HOME)
            }
        }
        // Locking the screen is the whole block: there is nothing to show until you unlock.
        if (action == "lock") return
        // "Always block" is a standing choice, so a short message is enough: you stay in the app (for example on
        // its home feed) instead of landing on a full-screen block page that asks you to go home.
        if (reason == "always" && reelApp) {
            handler.postDelayed({ showQuickMessage("Reels are turned off in this app") }, 350)
            return
        }
        // The exit is applied asynchronously; open the block screen after it so it can't close the screen.
        handler.postDelayed({
            try {
                startActivity(
                    Intent(this, BlockActivity::class.java)
                        .putExtra("reason", reason)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                )
            } catch (_: Exception) {
                performGlobalAction(GLOBAL_ACTION_HOME)
            }
        }, 650)
    }

    /** Taps the Home tab of the bottom navigation bar. True if a tab was found and tapped. */
    private fun clickHomeTab(pkg: String): Boolean {
        val root = rootInActiveWindow ?: return false
        val h = resources.displayMetrics.heightPixels
        val cands = ArrayList<AccessibilityNodeInfo>()
        if (pkg == "com.instagram.android") cands += root.findAccessibilityNodeInfosByViewId("$pkg:id/feed_tab")
        cands += root.findAccessibilityNodeInfosByText("Home")
        for (n in cands) {
            var node: AccessibilityNodeInfo? = n
            val r = Rect()
            while (node != null && !node.isClickable) node = node.parent
            if (node == null) continue
            node.getBoundsInScreen(r)
            // Only the bottom navigation bar counts, not some other "Home" label.
            if (r.top < h * 0.8 || r.width() <= 0) continue
            if (node.performAction(AccessibilityNodeInfo.ACTION_CLICK)) return true
        }
        return false
    }

    private var quickView: TextView? = null
    private val hideQuick = Runnable { removeQuick() }

    private fun removeQuick() {
        handler.removeCallbacks(hideQuick)
        quickView?.let {
            try { (getSystemService(Context.WINDOW_SERVICE) as WindowManager).removeView(it) } catch (_: Exception) {}
        }
        quickView = null
    }

    /** A small dark message near the bottom of the screen that fades after a couple of seconds. Does not take touches. */
    private fun showQuickMessage(text: String) {
        removeQuick()
        val d = resources.displayMetrics.density
        val tv = TextView(this).apply {
            this.text = text
            textSize = 14f
            setTextColor(Color.parseColor("#EDE0D8"))
            setPadding((18 * d).toInt(), (11 * d).toInt(), (18 * d).toInt(), (11 * d).toInt())
            background = android.graphics.drawable.GradientDrawable().apply {
                cornerRadius = 100f * d
                setColor(0xF2221C19.toInt())
                setStroke((1 * d).toInt().coerceAtLeast(1), 0x33FFFFFF)
            }
        }
        val lp = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT, WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        ).apply { gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL; y = (120 * d).toInt() }
        try { (getSystemService(Context.WINDOW_SERVICE) as WindowManager).addView(tv, lp) } catch (_: Exception) { return }
        quickView = tv
        handler.postDelayed(hideQuick, 2600)
    }

    // ---- Browser Shorts / Reels (opt-in): only the address bar text is read ----
    private var lastBrowserCheck = 0L
    private var browserSig: String? = null
    private val browserSeen = LinkedHashSet<String>()
    private val shortsUrl = Regex("(youtube[.]com/shorts/|instagram[.]com/reels?/|facebook[.]com/reel/)([a-z0-9_-]+)")

    /**
     * In a browser, every Short has its own address (youtube.com/shorts/<id>), so a swipe to the next one changes the
     * address bar. With "Block Shorts in browsers" on that is blocked; with "Count Shorts in browsers" on, each new
     * Short is counted (going back to one you already saw is not).
     */
    private fun checkBrowser(pkg: String) {
        val cfg = Store.config(this)
        val block = cfg.optBoolean("blockBrowser", false)
        val count = cfg.optBoolean("countBrowser", false)
        if (!block && !count) return
        val now = System.currentTimeMillis()
        if (now - lastBrowserCheck < 300) return
        lastBrowserCheck = now
        val root = rootInActiveWindow ?: return
        var url = ""
        for (id in Engine.BROWSERS[pkg] ?: emptyList()) {
            val n = root.findAccessibilityNodeInfosByViewId("$pkg:id/$id").firstOrNull() ?: continue
            // Browsers do not announce address changes, so the cached node is refreshed before it is read.
            n.refresh()
            url = (n.text ?: n.contentDescription)?.toString()?.lowercase() ?: ""
            if (url.isNotEmpty()) break
        }
        Store.putString(this, "lastEvent", "BROWSER $pkg url=${url.take(80)}")
        val m = shortsUrl.find(url)
        if (m == null) {
            browserSig = null; browserSeen.clear()
            return
        }
        if (block) {
            showBlock("browser", now, reelApp = true, pkg = pkg, browser = true)
            return
        }
        val key = m.groupValues[1] + m.groupValues[2]
        val first = browserSig == null
        val changed = !first && key != browserSig
        browserSig = key
        val seenBefore = !browserSeen.add(key)
        if (browserSeen.size > 80) browserSeen.remove(browserSeen.first())
        showBubble()
        val newOne = !seenBefore || cfg.optBoolean("countBack", false)
        if (changed && newOne && now - lastCountAt >= 700 && Engine.blockReason(this, pkg, now) == null) {
            countReel(pkg, now)
        }
    }

    // ---- Open a safe page when an app starts (opt-in per app) ----
    private val lastSeenApp = HashMap<String, Long>()
    private val launchArmedAt = HashMap<String, Long>()
    private val safeUrls = mapOf(
        "com.google.android.youtube" to "https://m.youtube.com/feed/subscriptions",
        "com.instagram.android" to "https://www.instagram.com/direct/inbox/",
    )

    private fun launchSafe(pkg: String, e: AccessibilityEvent, now: Long) {
        val cfg = Store.config(this)
        if (!Engine.appFlag(cfg, pkg, "safeLaunch")) return
        val url = safeUrls[pkg] ?: return
        val cls = e.className?.toString() ?: ""
        Store.putString(this, "lastLaunch", "STATE $pkg $cls armedAgo=${now - (launchArmedAt[pkg] ?: 0L)}")
        // Only the app's main screen coming up right after the app was started counts, and only once per start.
        val main = cls.endsWith("MainTabActivity") || cls.endsWith("WatchWhileActivity") ||
            cls.endsWith("MainActivity") || cls.endsWith("HomeActivity")
        if (!main || now - (launchArmedAt[pkg] ?: 0L) > 8_000) return
        launchArmedAt[pkg] = 0
        try {
            startActivity(
                Intent(Intent.ACTION_VIEW, android.net.Uri.parse(url)).setPackage(pkg).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        } catch (_: Exception) {}
    }

    private fun eventName(t: Int) = when (t) {
        AccessibilityEvent.TYPE_VIEW_SCROLLED -> "SCROLL"
        AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED -> "CONTENT"
        else -> "STATE"
    }

    override fun onInterrupt() {}

    /**
     * The service only listens to the reel apps, plus any app you set a daily timer for. Nothing else is
     * seen: usage for the Apps tab comes from Android's usage log, not from accessibility.
     */
    fun applyScope() {
        val info = serviceInfo ?: return
        val timers = Store.config(this).optJSONObject("appTimers")
        val extra = timers?.keys()?.asSequence()?.filter { timers.optInt(it, 0) > 0 }?.toList() ?: emptyList()
        val bc = Store.config(this)
        val browsers = if (bc.optBoolean("blockBrowser", false) || bc.optBoolean("countBrowser", false)) Engine.BROWSERS.keys.toList() else emptyList()
        info.packageNames = (Engine.TARGETS + extra + browsers).distinct().toTypedArray()
        serviceInfo = info
        timerCheckedAt.clear()
        curPkg = null
    }

    companion object {
        @Volatile var instance: ReelsAccessibilityService? = null
        private const val IG = "com.instagram.android"
        private const val YT = "com.google.android.youtube"
        private const val SNAP = "com.snapchat.android"
        private const val NETFLIX = "com.netflix.mediaclient"
    }
}
