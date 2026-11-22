package com.example.focus_reels

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

/** Home-screen widget showing today's reel count against the daily limit. */
class FocusWidget : AppWidgetProvider() {
    override fun onUpdate(ctx: Context, mgr: AppWidgetManager, ids: IntArray) {
        for (id in ids) mgr.updateAppWidget(id, build(ctx))
    }

    companion object {
        fun build(ctx: Context): RemoteViews {
            val total = Store.today(ctx).optInt("total")
            val cfg = Store.config(ctx)
            val limit = if (Engine.trackOnly(cfg)) 0 else cfg.optInt("dailyLimit", 0)
            val v = RemoteViews(ctx.packageName, R.layout.focus_widget)
            v.setTextViewText(R.id.widget_count, "$total")
            v.setTextViewText(R.id.widget_sub, if (limit > 0) "of $limit reels" else "reels today")
            val open = PendingIntent.getActivity(
                ctx, 0, Intent(ctx, MainActivity::class.java),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            v.setOnClickPendingIntent(R.id.widget_root, open)
            return v
        }

        fun refresh(ctx: Context) {
            val mgr = AppWidgetManager.getInstance(ctx)
            val ids = mgr.getAppWidgetIds(ComponentName(ctx, FocusWidget::class.java))
            for (id in ids) mgr.updateAppWidget(id, build(ctx))
        }
    }
}
