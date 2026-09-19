package com.tiernest.app.data

import org.junit.Assert.*
import org.junit.Test

class ConfigCodecTest {
    private fun configured() = ConfigCodec.updateForm(ConfigCodec.template,
        NetworkForm("synthetic-mesh", "synthetic-secret", "test-phone", "", true, "tcp://relay.example.com:11010"))

    @Test fun effectiveCopyPreservesIdentityAndUnknownFields() {
        val source = "# Keep this comment\n" + configured() + "custom = { nested = [1, 2, 3] }\n"
        val parsed = ConfigCodec.parse(source)
        val effective = ConfigCodec.parse(ConfigCodec.effective(source))
        assertEquals(parsed["network_identity"], effective["network_identity"])
        assertEquals(parsed["custom"], effective["custom"])
        assertTrue(source.startsWith("# Keep this comment"))
        val namedDefault = ConfigCodec.updateForm(configured(), ConfigCodec.form(configured()).copy(name = "default"))
        assertEquals("default", ConfigCodec.form(ConfigCodec.effective(namedDefault)).name)
    }

    @Test fun secretsStayDataThroughRoundTrip() {
        val secret = "quo\"te'\n\u0001\t$(touch /tmp/not-executed) `id` # [] \\ 雪"
        val value = ConfigCodec.updateForm(configured(), ConfigCodec.form(configured()).copy(secret = secret))
        assertEquals(secret, ConfigCodec.form(value).secret)
        assertEquals(secret, ConfigCodec.form(ConfigCodec.effective(value)).secret)
    }

    @Test fun invalidConfigurationAndExitNodesCannotStart() {
        assertThrows(IllegalArgumentException::class.java) { ConfigCodec.effective(ConfigCodec.template) }
        assertThrows(IllegalArgumentException::class.java) { ConfigCodec.parse("broken = [") }
        assertThrows(IllegalArgumentException::class.java) { ConfigCodec.effective(configured() + "exit_nodes = [\"10.77.0.3\"]") }
        assertThrows(IllegalArgumentException::class.java) { ConfigCodec.effective(configured() + "ipv6 = \"fd00::1\"") }
    }

    @Test fun parserErrorsDoNotRevealSecretText() {
        val error = assertThrows(IllegalArgumentException::class.java) { ConfigCodec.parse("network_secret = synthetic-do-not-disclose") }
        assertFalse(error.message!!.contains("synthetic-do-not-disclose"))
    }

    @Test fun unchangedPeerOptionsSurviveFormSave() {
        val config = ConfigCodec.parse(configured())
        config["peer"] = listOf(mapOf("uri" to "tcp://relay.example.com:11010", "custom" to true))
        val text = ConfigCodec.encode(config)
        val changed = ConfigCodec.parse(ConfigCodec.updateForm(text, ConfigCodec.form(text).copy(hostname = "renamed")))
        assertEquals(config["peer"], changed["peer"])
    }

    @Test fun fullTomlScalarSyntaxSurvivesRuntimeCopy() {
        val text = configured() + "time = 12:30:00\ndate = 2026-01-01T12:30:00Z\ninfinity = inf\n"
        val before = ConfigCodec.parse(text)
        val after = ConfigCodec.parse(ConfigCodec.effective(text))
        for (key in listOf("time", "date", "infinity")) assertEquals(before[key], after[key])
    }
}
