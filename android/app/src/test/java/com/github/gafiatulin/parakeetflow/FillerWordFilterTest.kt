package com.github.gafiatulin.parakeetflow

import com.github.gafiatulin.parakeetflow.core.util.FillerWordFilter
import org.junit.Assert.assertEquals
import org.junit.Test

class FillerWordFilterTest {

    @Test
    fun `removes simple fillers`() {
        assertEquals("I think this is great", FillerWordFilter.filter("I um think this is uh great"))
    }

    @Test
    fun `removes multi-word fillers`() {
        assertEquals("I was thinking", FillerWordFilter.filter("you know I was kind of thinking"))
    }

    @Test
    fun `preserves clean text`() {
        assertEquals("This is a clean sentence.", FillerWordFilter.filter("This is a clean sentence."))
    }

    @Test
    fun `handles empty string`() {
        assertEquals("", FillerWordFilter.filter(""))
    }

    @Test
    fun `is case insensitive`() {
        assertEquals("I think this is great", FillerWordFilter.filter("UM I think UH this is LIKE great"))
    }

    @Test
    fun `collapses multiple spaces`() {
        assertEquals("I think", FillerWordFilter.filter("I  um  uh  think"))
    }

    @Test
    fun `removes repeated words`() {
        assertEquals("I think this works", FillerWordFilter.filter("I I think this this works"))
    }

    @Test
    fun `cleans up spacing before punctuation`() {
        assertEquals("Hello, world.", FillerWordFilter.filter("Hello , world ."))
    }

    @Test
    fun `handles multiple fillers in sequence`() {
        val result = FillerWordFilter.filter("so like basically I was thinking")
        assertEquals("I was thinking", result)
    }
}
