package com.tiernest.app.data

import org.junit.Assert.*
import org.junit.Test

class DeviceNameTest {
    @Test fun systemNameWinsAndSupportsUnicode() {
        assertEquals("我的平板", DeviceName.choose(" 我的平板 ", "Acme", "Slate 7"))
    }

    @Test fun missingOrGenericSystemNameFallsBackToModelWithoutDuplicatingBrand() {
        for (missing in listOf(null, "", "  ", "localhost", "unknown", "Android")) {
            assertEquals("Acme Slate 7", DeviceName.choose(missing, "Acme", "Slate 7"))
        }
        assertEquals("ACME Slate 7", DeviceName.choose(null, "Acme", "ACME Slate 7"))
        assertEquals("Slate 7", DeviceName.choose(null, "unknown", "Slate 7"))
        assertEquals("TierNest Android", DeviceName.choose(null, null, "unknown"))
    }

    @Test fun automaticNameMatchesCoreLengthWithoutSplittingUnicode() {
        val name = DeviceName.choose("📱".repeat(40), null, null)
        assertEquals("📱".repeat(32), name)
        assertEquals("Test Phone", DeviceName.choose("Test\nPhone", null, null))
    }

    @Test fun automaticNameIsOnlyAddedToTheRuntimeCopyInBothModes() {
        val source = "# Preserve this exact source\n" + ConfigCodec.updateForm(ConfigCodec.template,
            NetworkForm(name = "synthetic-mesh", secret = "fixture-secret", dhcp = true))
        for (mode in ConnectionMode.entries) {
            val effective = ConfigCodec.parse(ConfigCodec.effective(source, mode, "我的平板 \"test\""))
            assertEquals("我的平板 \"test\"", effective["hostname"])
            assertFalse(ConfigCodec.parse(source).containsKey("hostname"))
            assertTrue(source.startsWith("# Preserve this exact source\n"))
        }
    }

    @Test fun explicitNamesIncludingLocalhostAreNeverReplaced() {
        for (name in listOf("chosen-name", "localhost")) {
            val source = ConfigCodec.updateForm(ConfigCodec.template,
                NetworkForm(name = "synthetic-mesh", secret = "fixture-secret", hostname = name, dhcp = true))
            assertEquals(name, ConfigCodec.form(ConfigCodec.effective(source, defaultHostname = "Acme Slate 7")).hostname)
        }
    }

    @Test fun explicitlyEmptyTomlNameUsesDeviceNameWithoutChangingIdentity() {
        val source = ConfigCodec.updateForm(ConfigCodec.template,
            NetworkForm(name = "synthetic-mesh", secret = "fixture-secret", dhcp = true)) + "hostname = \"  \"\n"
        val before = ConfigCodec.parse(source)
        val effective = ConfigCodec.parse(ConfigCodec.effective(source, defaultHostname = "Acme Slate 7"))
        assertEquals("Acme Slate 7", effective["hostname"])
        assertEquals(before["network_identity"], effective["network_identity"])
        assertEquals("  ", ConfigCodec.parse(source)["hostname"])
    }

    @Test fun invalidExplicitHostnameIsNotSilentlyReplaced() {
        val source = ConfigCodec.updateForm(ConfigCodec.template,
            NetworkForm(name = "synthetic-mesh", secret = "fixture-secret", dhcp = true)) + "hostname = 123\n"
        assertThrows(IllegalArgumentException::class.java) {
            ConfigCodec.effective(source, defaultHostname = "Acme Slate 7")
        }
    }
}
