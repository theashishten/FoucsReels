package com.example.focus_reels

import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.provider.Settings
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

/**
 * Quick Settings tile that switches reel counting (the Accessibility service) on and off, for banking apps that
 * refuse to open while it is on. Without the one-time adb permission it can only open the Accessibility screen.
 */
class CountingTile : TileService() {
    override fun onStartListening() = refresh()

    override fun onClick() {
        if (AccessSwitch.canWrite(this)) {
            val turnOn = !AccessSwitch.isOn(this)
            // A manual choice replaces any automatic pause.
            Store.putString(this, "guardPaused", "")
            AccessSwitch.set(this, turnOn)
            refresh(turnOn)
        } else {
            val i = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (Build.VERSION.SDK_INT >= 34) {
                startActivityAndCollapse(PendingIntent.getActivity(this, 0, i, PendingIntent.FLAG_IMMUTABLE))
            } else {
                @Suppress("DEPRECATION") startActivityAndCollapse(i)
            }
        }
    }

    private fun refresh(on: Boolean = AccessSwitch.isOn(this)) {
        val tile = qsTile ?: return
        tile.state = if (on) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.label = "Reel counting"
        if (Build.VERSION.SDK_INT >= 29) {
            tile.subtitle = when {
                on -> "On"
                Guard.pausedFor(this).isNotEmpty() -> "Paused for bank"
                else -> "Off"
            }
        }
        tile.updateTile()
    }
}
