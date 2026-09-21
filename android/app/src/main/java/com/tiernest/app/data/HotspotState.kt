package com.tiernest.app.data

enum class HotspotState(val wire: String, val label: String) {
    DISABLED("disabled", "共享已关闭"), ACTIVE("active", "热点设备可访问组网"),
    WAITING_CORE("waiting_core", "等待组网连接"), WAITING_HOTSPOT("waiting_hotspot", "请先开启系统 Wi-Fi 热点"),
    WAITING_ROUTES("waiting_routes", "等待可用的组网路由"), UNAVAILABLE("unavailable", "无法读取系统热点状态，共享未启用"),
    AMBIGUOUS("ambiguous", "检测到多个热点接口，暂未启用共享"),
    FORWARDING_OFF("forwarding_off", "系统热点尚未启用 IPv4 转发"),
    CONFLICT("conflict", "热点网段与组网或本机发布子网冲突，共享未启用"),
    TOO_MANY_ROUTES("too_many_routes", "组网目标超过共享上限（128 个）"), ERROR("error", "热点共享规则未能生效");

    companion object { fun parse(value: String?) = if (value == null) DISABLED else entries.firstOrNull { it.wire == value } ?: ERROR }
}
