package com.github.gafiatulin.parakeetflow.core.util

object FillerWordFilter {

    private val FILLER_PATTERN = Regex(
        """\b(uh|um|erm|ah|er|like|you know|I mean|sort of|kind of|basically|actually|literally|right|so|well|okay so)\b""",
        RegexOption.IGNORE_CASE
    )

    private val REPEATED_WORD_PATTERN = Regex(
        """\b(\w+)\s+\1\b""",
        RegexOption.IGNORE_CASE
    )

    fun filter(text: String): String {
        var result = text
        result = FILLER_PATTERN.replace(result, "")
        result = REPEATED_WORD_PATTERN.replace(result, "$1")
        result = result.replace(Regex("""\s{2,}"""), " ").trim()
        result = result.replace(Regex("""\s+([.,!?;:])"""), "$1")
        return result
    }
}
