package com.github.gafiatulin.parakeetflow.model

import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.coroutines.coroutineContext

/**
 * OkHttp-based file downloader with resume support and progress reporting.
 *
 * Downloads are written to a temporary file first, then atomically renamed
 * to the destination path on success. If a partial temp file exists from a
 * previous interrupted download, it resumes from where it left off.
 */
@Singleton
class ModelDownloader @Inject constructor(
    private val client: OkHttpClient
) {
    companion object {
        private const val TAG = "ModelDownloader"
        private const val BUFFER_SIZE = 8192
        private const val TEMP_SUFFIX = ".download"
    }

    /**
     * Downloads a file from [url] to [destination] with resume support.
     *
     * @param url The URL to download from.
     * @param destination The final file path.
     * @param onProgress Called with progress in the range [0.0, 1.0].
     *                   May receive -1f if content length is unknown.
     * @throws IOException If the download fails.
     */
    suspend fun downloadFile(
        url: String,
        destination: File,
        onProgress: (Float) -> Unit,
        authToken: String? = null
    ) = withContext(Dispatchers.IO) {
        // If the destination already exists, skip download
        if (destination.exists() && destination.length() > 0) {
            Log.d(TAG, "File already exists: ${destination.name}")
            onProgress(1f)
            return@withContext
        }

        val tempFile = File(destination.parentFile, destination.name + TEMP_SUFFIX)
        val existingBytes = if (tempFile.exists()) tempFile.length() else 0L

        val requestBuilder = Request.Builder().url(url)

        // Add auth header for gated models (e.g., HuggingFace Gemma)
        if (!authToken.isNullOrBlank()) {
            requestBuilder.addHeader("Authorization", "Bearer $authToken")
        }

        // Add Range header for resume if partial file exists
        if (existingBytes > 0) {
            requestBuilder.addHeader("Range", "bytes=$existingBytes-")
            Log.d(TAG, "Resuming download of ${destination.name} from byte $existingBytes")
        } else {
            Log.d(TAG, "Starting download of ${destination.name}")
        }

        val request = requestBuilder.build()
        val response = client.newCall(request).execute()

        if (!response.isSuccessful && response.code != 206) {
            response.close()
            throw IOException("Download failed: HTTP ${response.code} for $url")
        }

        val responseBody = response.body

        val isResumed = response.code == 206
        val contentLength = responseBody.contentLength()
        val totalBytes = if (isResumed && contentLength > 0) {
            existingBytes + contentLength
        } else if (contentLength > 0) {
            contentLength
        } else {
            -1L
        }

        try {
            val outputStream = FileOutputStream(tempFile, isResumed)
            val buffer = ByteArray(BUFFER_SIZE)
            var bytesWritten = if (isResumed) existingBytes else 0L

            responseBody.byteStream().use { inputStream ->
                outputStream.use { output ->
                    while (true) {
                        // Check for coroutine cancellation
                        coroutineContext.ensureActive()

                        val bytesRead = inputStream.read(buffer)
                        if (bytesRead == -1) break

                        output.write(buffer, 0, bytesRead)
                        bytesWritten += bytesRead

                        // Report progress
                        if (totalBytes > 0) {
                            val progress = bytesWritten.toFloat() / totalBytes.toFloat()
                            onProgress(progress.coerceIn(0f, 1f))
                        } else {
                            onProgress(-1f)
                        }
                    }
                    output.flush()
                    output.fd.sync()
                }
            }

            // Atomic rename: temp file -> destination
            if (!tempFile.renameTo(destination)) {
                // If rename fails (e.g., cross-filesystem), copy and delete
                tempFile.copyTo(destination, overwrite = true)
                tempFile.delete()
            }

            Log.i(TAG, "Download complete: ${destination.name} ($bytesWritten bytes)")
            onProgress(1f)
        } catch (e: Exception) {
            // Leave temp file in place for resume on next attempt
            Log.e(TAG, "Download interrupted: ${destination.name}, ${tempFile.length()} bytes saved", e)
            throw e
        } finally {
            response.close()
        }
    }
}
