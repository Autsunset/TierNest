package com.tiernest.app.data

import android.content.Context
import android.util.AtomicFile
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

enum class ThemeStyle { MATERIAL, HYPER, CONSOLE }
enum class ColorMode { SYSTEM, LIGHT, DARK }
enum class DetectionMode { EVENT, HTTP }

data class HomeNetwork(val iface: String, val gateway: String, val mac: String, val target: String, val port: Int,
                       val wifiVerified: Boolean = false) {
    val id get() = "$iface|$gateway|$mac"
}

data class Preferences(
    val theme: ThemeStyle = ThemeStyle.CONSOLE, val colors: ColorMode = ColorMode.SYSTEM,
    val dynamicColor: Boolean = true, val requested: Boolean = false, val boot: Boolean = false,
    val screenSuspend: Boolean = false, val automatic: Boolean = false,
    val detection: DetectionMode = DetectionMode.EVENT, val interval: Int = 30,
    val homes: List<HomeNetwork> = emptyList(), val migrationReview: String = "",
    val accent: String = "mint", val reduceMotion: Boolean = false,
    val connectionMode: ConnectionMode = ConnectionMode.VPN,
    val lastConnectionError: String = "", val sessionStartedAt: Long = 0, val sessionProcessId: Int = 0,
    val hotspotAccess: Boolean = false,
)

class AppStore(context: Context) {
    private val prefs = context.getSharedPreferences("tiernest", Context.MODE_PRIVATE)
    private val config = AtomicFile(File(context.filesDir, "config.toml"))
    private val requestedState = MutableStateFlow(prefs.getBoolean("requested", false))
    val requested = requestedState.asStateFlow()
    // Every writer of this store invalidates the cache under the same monitor,
    // so hot readers (service reconcile, sampling, the tile) avoid re-parsing
    // the home-network JSON and copying the preference map on each call.
    @Volatile private var cached: Preferences? = null

    @Synchronized fun readConfig(): String = if (config.baseFile.exists()) config.openRead().bufferedReader().use { it.readText() } else ConfigCodec.template

    @Synchronized fun writeConfig(text: String) {
        val bytes = text.toByteArray(Charsets.UTF_8)
        val output = config.startWrite()
        try {
            output.write(bytes)
            // AtomicFile logs some sync/rename failures instead of throwing.
            // Surface a failed durable write before reporting a successful save.
            output.fd.sync()
            config.finishWrite(output)
            check(config.openRead().use { bytes.contentEquals(it.readBytes()) }) { "配置写入校验失败，未确认保存成功" }
        }
        catch (error: Throwable) { config.failWrite(output); throw error }
        finally { cached = null } // The default connection mode depends on the file's existence.
    }

    fun load(): Preferences = cached ?: synchronized(this) { cached ?: read().also { cached = it } }

    private fun read(): Preferences {
        fun <T : Enum<T>> enum(key: String, default: T, values: Array<T>) = values.firstOrNull { it.name == prefs.getString(key, "") } ?: default
        val homes = runCatching {
            val array = JSONArray(prefs.getString("homes", "[]"))
            (0 until array.length()).map {
                val h = array.getJSONObject(it)
                HomeNetwork(h.getString("iface"), h.getString("gateway"), h.getString("mac"), h.getString("target"), h.getInt("port"),
                    h.optBoolean("wifiVerified", false))
            }
        }.getOrDefault(emptyList())
        return Preferences(enum("theme", ThemeStyle.CONSOLE, ThemeStyle.entries.toTypedArray()),
            enum("colors", ColorMode.SYSTEM, ColorMode.entries.toTypedArray()), prefs.getBoolean("dynamic", true),
            prefs.getBoolean("requested", false), prefs.getBoolean("boot", false), prefs.getBoolean("screen", false),
            prefs.getBoolean("automatic", false), enum("detection", DetectionMode.EVENT, DetectionMode.entries.toTypedArray()),
            prefs.getInt("interval", 30).coerceAtLeast(1), homes, prefs.getString("migrationReview", "").orEmpty(),
            prefs.getString("accent", "mint").orEmpty(), prefs.getBoolean("reduceMotion", false),
            ModePolicy.initial(prefs.getString("connectionMode", null), prefs.all.isNotEmpty() || config.baseFile.exists()),
            prefs.getString("lastConnectionError", "").orEmpty(), prefs.getLong("sessionStartedAt", 0), prefs.getInt("sessionProcessId", 0),
            prefs.getBoolean("hotspotAccess", false))
    }

    @Synchronized fun update(change: (Preferences) -> Preferences): Preferences {
        val value = change(load())
        cached = null // In-memory preferences change even when the disk commit fails.
        val homes = JSONArray().apply { value.homes.forEach { h -> put(JSONObject().apply {
            put("iface", h.iface); put("gateway", h.gateway); put("mac", h.mac); put("target", h.target); put("port", h.port)
            put("wifiVerified", h.wifiVerified)
        }) } }
        check(prefs.edit().putString("theme", value.theme.name).putString("colors", value.colors.name)
            .putBoolean("dynamic", value.dynamicColor).putBoolean("requested", value.requested).putBoolean("boot", value.boot)
            .putBoolean("screen", value.screenSuspend).putBoolean("automatic", value.automatic)
            .putString("detection", value.detection.name).putInt("interval", value.interval).putString("homes", homes.toString())
            .putString("migrationReview", value.migrationReview).putString("accent", value.accent)
            .putBoolean("reduceMotion", value.reduceMotion).putString("connectionMode", value.connectionMode.name)
            .putString("lastConnectionError", value.lastConnectionError)
            .putLong("sessionStartedAt", value.sessionStartedAt).putInt("sessionProcessId", value.sessionProcessId)
            .putBoolean("hotspotAccess", value.hotspotAccess)
            .commit()) { "偏好保存失败" }
        requestedState.value = value.requested
        return value
    }
}
