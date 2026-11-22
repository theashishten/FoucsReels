package com.example.focus_reels

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.view.View

/**
 * The live counter drawn over a reel app: a small dark pill with a progress ring holding today's count and a
 * short caption ("12 left", "today", "3m left"). The ring and number change colour as you near a limit, and the
 * pill gives a quick pop each time a reel is counted. It is flat on purpose: no gradient, no shadow.
 */
class CounterView(ctx: Context) : View(ctx) {
    private val d0 = ctx.resources.displayMetrics.density
    private var d = d0            // density times the user's size setting
    private var count = "0"
    private var label = ""
    private var frac = -1f
    private var accent = Color.parseColor("#FFB59F")

    // Look chosen by the user (Counter style page): dark, light, glass, clear or colour.
    private var style = "dark"
    private var opacity = 0.92f
    private var showLabel = true
    private var showRing = true
    private var textColor = Color.WHITE
    private var subColor = Color.parseColor("#CFC4BD")
    private var edgeColor = Color.parseColor("#33FFFFFF")

    private val edge = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE }
    private val rim = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE }
    private val sheen = Paint(Paint.ANTI_ALIAS_FLAG)
    private val under = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; color = 0x73000000 }
    private val track = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE }
    private val arc = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE; strokeCap = Paint.Cap.ROUND
    }
    private val num = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD); textAlign = Paint.Align.CENTER
    }
    private val lab = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        typeface = Typeface.create(Typeface.DEFAULT, Typeface.NORMAL)
    }

    /** Lets the service move the window while the counter is held and dragged, and save where it was dropped. */
    interface Mover {
        fun onMove(dx: Float, dy: Float)
        fun onDrop()
    }

    var mover: Mover? = null
    private var holding = false
    private var lastX = 0f
    private var lastY = 0f
    private var downX = 0f
    private var downY = 0f
    private val longPress = Runnable {
        holding = true
        performHapticFeedback(android.view.HapticFeedbackConstants.LONG_PRESS)
        animate().cancel()
        animate().scaleX(1.12f).scaleY(1.12f).setDuration(120).start()
        hint = true
        invalidate()
    }
    private var hint = false

    override fun onTouchEvent(e: android.view.MotionEvent): Boolean {
        when (e.actionMasked) {
            android.view.MotionEvent.ACTION_DOWN -> {
                downX = e.rawX; downY = e.rawY; lastX = e.rawX; lastY = e.rawY
                holding = false
                postDelayed(longPress, 450)
                return true
            }
            android.view.MotionEvent.ACTION_MOVE -> {
                if (!holding) {
                    // Moving before the hold time is up is a normal touch, so cancel the pending hold.
                    if (Math.hypot((e.rawX - downX).toDouble(), (e.rawY - downY).toDouble()) > 12 * d) removeCallbacks(longPress)
                } else {
                    mover?.onMove(e.rawX - lastX, e.rawY - lastY)
                    lastX = e.rawX; lastY = e.rawY
                }
                return true
            }
            android.view.MotionEvent.ACTION_UP, android.view.MotionEvent.ACTION_CANCEL -> {
                removeCallbacks(longPress)
                if (holding) {
                    holding = false
                    hint = false
                    animate().scaleX(1f).scaleY(1f).setDuration(120).start()
                    invalidate()
                    mover?.onDrop()
                }
                return true
            }
        }
        return super.onTouchEvent(e)
    }

    val isDragging: Boolean get() = holding

    private var ring = 32f * d
    private var margin = 8f * d // room around the pill so the pop animation is not clipped by the window

    init {
        // Some phones (Samsung) auto-darken light overlays, which would turn the Light, Glass and Colour looks dark.
        if (android.os.Build.VERSION.SDK_INT >= 29) isForceDarkAllowed = false
        applyStyle("dark", 92, 100, true, true)
    }

    /** Applies the user's look. [opacityPct] 20..100, [sizePct] 70..150. */
    fun applyStyle(styleName: String, opacityPct: Int, sizePct: Int, label: Boolean, ringOn: Boolean) {
        style = styleName
        opacity = opacityPct.coerceIn(20, 100) / 100f
        showLabel = label
        showRing = ringOn
        d = d0 * sizePct.coerceIn(70, 150) / 100f
        ring = 32f * d
        margin = 8f * d
        fun a(base: Int) = Color.argb((Color.alpha(base) * opacity).toInt(), Color.red(base), Color.green(base), Color.blue(base))
        var fill = 0xFF151114.toInt()
        when (style) {
            "light" -> { fill = 0xFFFFFFFF.toInt(); textColor = Color.parseColor("#1B1B1F"); subColor = Color.parseColor("#5F5A63"); edgeColor = 0x22000000 }
            "glass" -> { fill = 0x4D000000; textColor = Color.WHITE; subColor = Color.parseColor("#F2F2F7"); edgeColor = 0x66FFFFFF }
            "liquid" -> { fill = 0x7A0E0E12; textColor = Color.WHITE; subColor = Color.parseColor("#F2F2F7"); edgeColor = 0 }
            "clear" -> { fill = 0; textColor = Color.WHITE; subColor = Color.WHITE; edgeColor = 0 }
            "colour" -> { fill = accent; textColor = Color.parseColor("#151110"); subColor = Color.parseColor("#2B2220"); edgeColor = 0 }
            else -> { textColor = Color.WHITE; subColor = Color.parseColor("#CFC4BD"); edgeColor = 0x33FFFFFF }
        }
        num.color = textColor
        lab.color = subColor
        lab.textSize = 12f * d
        // Text sits straight on the video in these looks, so give it a dark halo that works on light and dark scenes.
        val halo = when (style) { "clear" -> 5f * d; "glass", "liquid" -> 2.5f * d; else -> 0f }
        num.setShadowLayer(halo, 0f, 1f * d, 0xFF000000.toInt())
        lab.setShadowLayer(halo, 0f, 1f * d, 0xFF000000.toInt())
        track.strokeWidth = 3f * d
        track.color = if (style == "light") 0x1F000000 else if (style == "colour") 0x33000000 else 0x2EFFFFFF
        arc.strokeWidth = 3f * d
        edge.strokeWidth = 1f * d
        fun shape() = android.graphics.drawable.GradientDrawable().apply {
            this.shape = android.graphics.drawable.GradientDrawable.RECTANGLE
            cornerRadius = 100f * d
        }
        val pill: android.graphics.drawable.Drawable = when (style) {
            // Smoky base keeps white text readable on any video, with a light sheen on top for the glass look.
            "glass" -> android.graphics.drawable.LayerDrawable(arrayOf(
                shape().apply { setColor(a(fill)) },
                shape().apply { setColor(a(0x33FFFFFF)); setStroke((1f * d).toInt().coerceAtLeast(1), a(edgeColor)) }
            ))
            "liquid" -> android.graphics.drawable.LayerDrawable(arrayOf(
                shape().apply { setColor(a(fill)) },
                shape().apply {
                    orientation = android.graphics.drawable.GradientDrawable.Orientation.TOP_BOTTOM
                    colors = intArrayOf(a(0x4DFFFFFF), a(0x0DFFFFFF))
                }
            ))
            else -> shape().apply {
                setColor(a(fill))
                if (edgeColor != 0) setStroke((1f * d).toInt().coerceAtLeast(1), a(edgeColor))
            }
        }
        val m = margin.toInt()
        background = android.graphics.drawable.InsetDrawable(pill, m, m, m, m)
        requestLayout()
        invalidate()
    }

    /** [fraction] is 0..1 for a limit/plan progress ring, or negative for a plain full ring. */
    fun set(total: Int, fraction: Float, caption: String, color: Int) {
        val text = total.toString()
        val changed = text != count
        count = text
        frac = fraction
        label = if (showLabel) caption else ""
        accent = color
        if (style == "colour") applyStyle(style, (opacity * 100).toInt(), (d / d0 * 100).toInt(), showLabel, showRing)
        requestLayout()
        invalidate()
        if (changed) pop()
    }

    private fun pop() {
        animate().cancel()
        scaleX = 1f; scaleY = 1f
        animate().scaleX(1.16f).scaleY(1.16f).setDuration(110).withEndAction {
            animate().scaleX(1f).scaleY(1f).setDuration(160).start()
        }.start()
    }

    override fun onMeasure(w: Int, h: Int) {
        val labelW = if (label.isEmpty()) 0f else lab.measureText(label) + 8f * d
        val pillW = 5f * d + ring + labelW + 11f * d
        setMeasuredDimension((pillW + margin * 2).toInt(), (ring + 10f * d + margin * 2).toInt())
    }

    override fun onDraw(c: Canvas) {
        val pillH = ring + 10f * d
        val labelW = if (label.isEmpty()) 0f else lab.measureText(label) + 8f * d
        val pillW = 5f * d + ring + labelW + 11f * d
        val r = RectF(margin, margin, margin + pillW, margin + pillH)

        val cx = r.left + 5f * d + ring / 2
        val cy = r.centerY()
        val ringRect = RectF(cx - ring / 2 + 2f * d, cy - ring / 2 + 2f * d, cx + ring / 2 - 2f * d, cy + ring / 2 - 2f * d)
        if (style == "liquid") {
            // Bright edge that fades around the pill, plus a soft highlight along the top: the "liquid glass" look.
            val al = (255 * opacity).toInt()
            rim.strokeWidth = 1.3f * d
            rim.shader = android.graphics.LinearGradient(
                r.left, r.top, r.right, r.bottom,
                intArrayOf(0xF2FFFFFF.toInt(), 0x24FFFFFF, 0x33FFFFFF, 0xB8FFFFFF.toInt()),
                floatArrayOf(0f, 0.42f, 0.62f, 1f), android.graphics.Shader.TileMode.CLAMP
            )
            rim.alpha = al
            val ri = RectF(r).apply { inset(0.7f * d, 0.7f * d) }
            c.drawRoundRect(ri, pillH / 2, pillH / 2, rim)
            sheen.shader = android.graphics.LinearGradient(
                0f, r.top, 0f, r.top + pillH * 0.5f,
                intArrayOf(0x66FFFFFF, 0x00FFFFFF), null, android.graphics.Shader.TileMode.CLAMP
            )
            sheen.alpha = al
            c.drawRoundRect(RectF(r.left + 5f * d, r.top + 1.8f * d, r.right - 5f * d, r.top + pillH * 0.5f), pillH / 3, pillH / 3, sheen)
        }
        if (hint) c.drawCircle(cx, cy, ring / 2 + 3f * d, edge.apply { color = accent; strokeWidth = 2f * d })
        if (showRing) {
            if (style == "clear") {
                // Dark underlay so the ring stays visible on bright scenes.
                under.strokeWidth = 5f * d
                c.drawArc(ringRect, 0f, 360f, false, under)
            }
            c.drawArc(ringRect, 0f, 360f, false, track)
            arc.color = if (style == "colour") textColor else accent
            c.drawArc(ringRect, -90f, if (frac < 0f) 360f else 360f * frac.coerceIn(0.02f, 1f), false, arc)
        }

        num.textSize = when {
            !showRing && count.length <= 2 -> 17f * d
            count.length <= 2 -> 13f * d
            count.length == 3 -> 11f * d
            else -> 9f * d
        }
        val reps = if (style == "clear") 2 else 1 // drawing twice thickens the dark halo behind the text
        repeat(reps) { c.drawText(count, cx, cy - (num.descent() + num.ascent()) / 2, num) }

        if (label.isNotEmpty()) {
            repeat(reps) { c.drawText(label, cx + ring / 2 + 8f * d, cy - (lab.descent() + lab.ascent()) / 2, lab) }
        }
    }
}
