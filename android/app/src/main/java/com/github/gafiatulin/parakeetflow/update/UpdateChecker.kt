package com.github.gafiatulin.parakeetflow.update

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import okhttp3.OkHttpClient
import okhttp3.Request
import java.util.concurrent.TimeUnit

object UpdateChecker {
    @Serializable
    private data class Release(
        val tag_name: String = "",
        val html_url: String = "",
    )

    data class AvailableUpdate(val version: String, val url: String)

    private const val URL =
        "https://api.github.com/repos/gafiatulin/parakeet-flow/releases/latest"
    private val json = Json { ignoreUnknownKeys = true }
    private val client = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(10, TimeUnit.SECONDS)
        .build()

    suspend fun check(currentVersion: String): Result<AvailableUpdate?> = withContext(Dispatchers.IO) {
        runCatching {
            val request = Request.Builder()
                .url(URL)
                .header("Accept", "application/vnd.github+json")
                .header("User-Agent", "ParakeetFlow-Android")
                .build()
            client.newCall(request).execute().use { response ->
                if (!response.isSuccessful) error("HTTP ${response.code}")
                val body = response.body.string().ifBlank { error("Empty response") }
                val release = json.decodeFromString<Release>(body)
                val version = release.tag_name.removePrefix("v")
                if (version.isNotBlank() && isNewer(version, currentVersion)) {
                    AvailableUpdate(version, release.html_url)
                } else {
                    null
                }
            }
        }
    }

    fun isNewer(candidate: String, current: String): Boolean {
        val left = parts(candidate)
        val right = parts(current)
        for (index in 0 until maxOf(left.size, right.size)) {
            val a = left.getOrElse(index) { 0 }
            val b = right.getOrElse(index) { 0 }
            if (a != b) return a > b
        }
        return false
    }

    private fun parts(value: String): List<Int> =
        value.trim().removePrefix("v")
            .substringBefore('-')
            .split('.')
            .map { it.takeWhile(Char::isDigit).toIntOrNull() ?: 0 }
}
