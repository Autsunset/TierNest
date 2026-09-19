package com.tiernest.app.data

enum class ConfigTab(val label: String) { IDENTITY("基本"), ENDPOINTS("节点"), FEATURES("参数"), SOURCE("TOML") }

/** ViewModel-held draft: navigation and rotation never serialize secrets into savedInstanceState. */
data class ConfigDraft(
    val savedText: String, val document: String, val form: NetworkForm,
    val documentForm: NetworkForm?, val tab: ConfigTab = ConfigTab.IDENTITY, val revision: Long = 0,
) {
    val dirty get() = document != savedText || (tab != ConfigTab.SOURCE && form != documentForm)
    fun payload(): String = if (tab == ConfigTab.SOURCE || form == documentForm) document else ConfigCodec.updateForm(document, form)
    fun edit(change: (NetworkForm) -> NetworkForm) = copy(form = change(form), revision = revision + 1)
    fun editText(text: String) = copy(document = text, revision = revision + 1)
    fun renameEntry(group: String, old: String, replacement: String, index: Int = -1): ConfigDraft {
        val text = ConfigCodec.renameEntry(payload(), group, old, replacement, index)
        val parsed = ConfigCodec.form(text)
        return copy(document = text, form = parsed, documentForm = parsed, revision = revision + 1)
    }
    fun select(next: ConfigTab): ConfigDraft {
        if (next == tab) return this
        if (tab == ConfigTab.SOURCE || next == ConfigTab.SOURCE) {
            val text = payload()
            val parsed = ConfigCodec.form(text) // A parse error keeps the current editor intact.
            return copy(document = text, form = parsed, documentForm = parsed, tab = next, revision = revision + 1)
        }
        return copy(tab = next)
    }
    fun acknowledge(text: String, savedRevision: Long): ConfigDraft =
        if (revision == savedRevision) load(text, tab).copy(revision = revision + 1)
        else copy(savedText = text) // A late save response cannot overwrite newer edits.

    companion object {
        fun load(text: String, tab: ConfigTab = ConfigTab.IDENTITY): ConfigDraft {
            val parsed = runCatching { ConfigCodec.form(text) }.getOrNull()
            return ConfigDraft(text, text, parsed ?: NetworkForm(), parsed, if (parsed == null) ConfigTab.SOURCE else tab)
        }
    }
}
