package com.tiernest.app.data

import android.content.Context
import android.util.AtomicFile
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

enum class ThemeStyle { MATERIAL, HYPER, CONSOLE }
enum class ColorMode { SYSTEM, LIGHT, DARK }
enum class DetectionMode { EVENT, HTTP }

data class HomeNetwork(val iface: String, val gateway: String, val mac: String, val target: String, val port: Int) {
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
)

class AppStore(context: Context) {
    private val prefs = context.getSharedPreferences("tiernest", Context.MODE_PRIVATE)
    private val config = AtomicFile(File(context.filesDir, "config.toml"))

    @Synchronized fun readConfig(): String = if (config.baseFile.exists()) config.openRead().bufferedReader().use { it.readText() } else ConfigCodec.template

    @Synchronized fun writeConfig(text: String) {
        val output = config.startWrite()
        try { output.write(text.toByteArray()); config.finishWrite(output) }
        catch (error: Throwable) { config.failWrite(output); throw error }
    }

    fun load(): Preferences {
        fun <T : Enum<T>> enum(key: String, default: T, values: Array<T>) = values.firstOrNull { it.name == prefs.getString(key, "") } ?: default
        val homes = runCatching {
            val array = JSONArray(prefs.getString("homes", "[]"))
            (0 until array.length()).map {
                val h = array.getJSONObject(it)
                HomeNetwork(h.getString("iface"), h.getString("gateway"), h.getString("mac"), h.getString("target"), h.getInt("port"))
            }
        }.getOrDefault(emptyList())
        return Preferences(enum("theme", ThemeStyle.CONSOLE, ThemeStyle.entries.toTypedArray()),
            enum("colors", ColorMode.SYSTEM, ColorMode.entries.toTypedArray()), prefs.getBoolean("dynamic", true),
            prefs.getBoolean("requested", false), prefs.getBoolean("boot", false), prefs.getBoolean("screen", false),
            prefs.getBoolean("automatic", false), enum("detection", DetectionMode.EVENT, DetectionMode.entries.toTypedArray()),
            prefs.getInt("interval", 30).coerceAtLeast(1), homes, prefs.getString("migrationReview", "").orEmpty(),
            prefs.getString("accent", "mint").orEmpty(), prefs.getBoolean("reduceMotion", false),
            ModePolicy.initial(prefs.getString("connectionMode", null), prefs.all.isNotEmpty() || config.baseFile.exists()))
    }

    @Synchronized fun update(change: (Preferences) -> Preferences): Preferences {
        val value = change(load())
        val homes = JSONArray().apply { value.homes.forEach { h -> put(JSONObject().apply {
            put("iface", h.iface); put("gateway", h.gateway); put("mac", h.mac); put("target", h.target); put("port", h.port)
        }) } }
        check(prefs.edit().putString("theme", value.theme.name).putString("colors", value.colors.name)
            .putBoolean("dynamic", value.dynamicColor).putBoolean("requested", value.requested).putBoolean("boot", value.boot)
            .putBoolean("screen", value.screenSuspend).putBoolean("automatic", value.automatic)
            .putString("detection", value.detection.name).putInt("interval", value.interval).putString("homes", homes.toString())
            .putString("migrationReview", value.migrationReview).putString("accent", value.accent)
            .putBoolean("reduceMotion", value.reduceMotion).putString("connectionMode", value.connectionMode.name)
            .commit()) { "偏好保存失败" }
        return value
    }
}
