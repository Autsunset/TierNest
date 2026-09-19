package com.tiernest.app.data

import org.junit.Assert.*
import org.junit.Test

class ConfigDraftTest {
    private val original = """
        # keep comment and unknown options
        instance_name = "synthetic"
        dhcp = true
        listeners = ["udp://0.0.0.0:11010"]
        [network_identity]
        network_name = "synthetic"
        network_secret = "synthetic-test"
        [[peer]]
        uri = "tcp://relay.example.com:11010"
        custom_option = "keep"
        [flags]
        mtu = 1420
        custom_flag = "keep"
    """.trimIndent().replace("\n", "\r\n") + "\r\n"

    @Test fun browsingAllTabsPreservesOriginalBytesAndComments() {
        var draft = ConfigDraft.load(original)
        for (tab in ConfigTab.entries + ConfigTab.IDENTITY) {
            draft = draft.select(tab)
            assertFalse(draft.dirty)
            assertEquals(original, draft.payload())
        }
    }

    @Test fun editsSurviveSourceSwitchAndPreserveUnrelatedFields() {
        val draft = ConfigDraft.load(original).edit { it.copy(listeners = it.listeners + "tcp://0.0.0.0:11010",
            features = it.features + ("enable_kcp_proxy" to true)) }.select(ConfigTab.SOURCE).select(ConfigTab.IDENTITY)
        val data = ConfigCodec.parse(draft.payload())
        assertTrue(draft.dirty)
        assertEquals(2, (data["listeners"] as List<*>).size)
        assertEquals(ConfigCodec.parse(original)["peer"], data["peer"])
        val flags = data["flags"] as Map<*, *>
        assertEquals("keep", flags["custom_flag"])
        assertEquals(1420L, flags["mtu"])
        assertEquals(true, flags["enable_kcp_proxy"])
        assertFalse(flags.containsKey("bind_device")) // Viewing defaults doesn't rewrite them.
    }

    @Test fun malformedSourceDoesNotReplaceTheVisualDraft() {
        val draft = ConfigDraft.load(original).select(ConfigTab.SOURCE).editText("network = [")
        assertThrows(IllegalArgumentException::class.java) { draft.select(ConfigTab.IDENTITY) }
        assertEquals("network = [", draft.document)
        assertEquals(ConfigTab.SOURCE, draft.tab)
    }

    @Test fun lateSavePreservesNewerTyping() {
        val submitted = ConfigDraft.load(original).edit { it.copy(hostname = "submitted") }
        val later = submitted.edit { it.copy(hostname = "newer-input") }
        val result = later.acknowledge(submitted.payload(), submitted.revision)
        assertEquals("newer-input", result.form.hostname)
        assertTrue(result.dirty)
        assertEquals("newer-input", ConfigCodec.form(result.payload()).hostname)
    }

    @Test fun successfulSaveClearsDirtyButKeepsSelectedTab() {
        val draft = ConfigDraft.load(original).edit { it.copy(mtu = "1380") }.select(ConfigTab.FEATURES)
        val result = draft.acknowledge(draft.payload(), draft.revision)
        assertFalse(result.dirty)
        assertEquals(ConfigTab.FEATURES, result.tab)
        assertEquals("1380", result.form.mtu)
    }

    @Test fun editingAnAddressPreservesItsExtraOptionsAndOtherPendingEdits() {
        val draft = ConfigDraft.load(original).edit { it.copy(hostname = "pending-edit") }
            .renameEntry("peer", "tcp://relay.example.com:11010", "udp://relay.example.com:11010")
        val document = ConfigCodec.parse(draft.payload())
        val peer = (document["peer"] as List<*>).single() as Map<*, *>
        assertEquals("udp://relay.example.com:11010", peer["uri"])
        assertEquals("keep", peer["custom_option"])
        assertEquals("pending-edit", document["hostname"])
        assertTrue(draft.dirty)
    }

    @Test fun duplicateLegacyUrisOnlyChangeTheSelectedRow() {
        val document = ConfigCodec.parse(original)
        document["peer"] = listOf(
            mapOf("uri" to "tcp://relay.example.com:11010", "custom" to "first"),
            mapOf("uri" to "tcp://relay.example.com:11010", "custom" to "second"))
        val draft = ConfigDraft.load(ConfigCodec.encode(document)).renameEntry("peer",
            "tcp://relay.example.com:11010", "udp://relay.example.com:11010", index = 1)
        val peers = ConfigCodec.parse(draft.payload())["peer"] as List<*>
        assertEquals("tcp://relay.example.com:11010", (peers[0] as Map<*, *>)["uri"])
        assertEquals("udp://relay.example.com:11010", (peers[1] as Map<*, *>)["uri"])
        assertEquals("second", (peers[1] as Map<*, *>)["custom"])
    }
}
