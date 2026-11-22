package com.example.focus_reels

import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

/** Quick Settings tile: one tap starts a 30-minute hard block. Tapping again ends it, unless strict or PIN-locked. */
class FocusTile : TileService() {
    override fun onStartListening() = refresh()

    override fun onClick() {
        val now = System.currentTimeMillis()
        val active = Store.status(this).optLong("hardBlockUntil") > now
        if (!active) {
            Engine.hardBlock(this, 30, now)
        } else {
            val cfg = Store.config(this)
            val locked = cfg.optBoolean("strict", false) || cfg.optString("buddyPin").isNotEmpty()
            if (!locked) Store.put(this, "status", Store.status(this).put("hardBlockUntil", 0))
        }
        refresh()
    }

    private fun refresh() {
        val tile = qsTile ?: return
        val active = Store.status(this).optLong("hardBlockUntil") > System.currentTimeMillis()
        tile.state = if (active) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.label = "Block reels 30m"
        tile.updateTile()
    }
}
