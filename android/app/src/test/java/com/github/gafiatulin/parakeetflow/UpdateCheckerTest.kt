package com.github.gafiatulin.parakeetflow

import com.github.gafiatulin.parakeetflow.update.UpdateChecker
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class UpdateCheckerTest {
    @Test
    fun compares_numeric_versions() {
        assertTrue(UpdateChecker.isNewer("1.2.0", "1.1.9"))
        assertTrue(UpdateChecker.isNewer("v2.0.0", "1.99.99"))
        assertFalse(UpdateChecker.isNewer("1.0.0", "1.0.0"))
        assertFalse(UpdateChecker.isNewer("1.0.0-beta", "1.0.0"))
    }
}
