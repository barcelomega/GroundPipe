package com.barcelomega.groundpipe.player

import androidx.media3.datasource.cache.SimpleCache

/**
 * Process-wide handle to ExoPlayer's temporary media cache. The player keeps
 * only the currently playing track there, so seeking and replaying does not
 * issue fresh network requests.
 */
object PlaybackCache {
    @Volatile
    var cache: SimpleCache? = null

    fun clearExcept(keepKey: String) {
        val active = cache ?: return
        for (key in active.keys.toList()) {
            if (key == keepKey) continue
            runCatching { active.removeResource(key) }
        }
    }

    fun clearAll() {
        val active = cache ?: return
        for (key in active.keys.toList()) {
            runCatching { active.removeResource(key) }
        }
    }
}
