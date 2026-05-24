package com.wgorski.podcastr

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.pm.ServiceInfo
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.work.CoroutineWorker
import androidx.work.ForegroundInfo
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.schabi.newpipe.extractor.NewPipe
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.TimeUnit

/**
 * Resolves a YouTube URL via NewPipe and streams the audio to disk.
 *
 * Runs as a foreground service so the OS doesn't kill it when the app
 * leaves the foreground or the user swipes the task away. The URL is
 * re-resolved every time the worker runs — googlevideo signed stream
 * URLs expire within hours, so passing a stale URL across an app
 * restart wouldn't work.
 */
class DownloadWorker(appContext: Context, params: WorkerParameters) :
    CoroutineWorker(appContext, params) {

    private val client by lazy {
        OkHttpClient.Builder()
            .connectTimeout(30, TimeUnit.SECONDS)
            .readTimeout(60, TimeUnit.SECONDS)
            .build()
    }

    // Throttle notification updates: percent-grained, plus a soft 250 ms
    // floor. Updating the foreground notification thousands of times a
    // second causes the system shade to stutter and bloats the binder
    // queue.
    private var lastForegroundPercent: Int = -1
    private var lastForegroundAtMs: Long = 0L

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        val videoId = inputData.getString(KEY_VIDEO_ID)
            ?: return@withContext failure("Missing video id")
        val sourceUrl = inputData.getString(KEY_SOURCE_URL)
            ?: return@withContext failure("Missing source URL")
        val tracksDir = inputData.getString(KEY_TRACKS_DIR)
            ?: return@withContext failure("Missing tracks directory")
        val titleHint = inputData.getString(KEY_TITLE) ?: "Downloading audio"
        val channelHint = inputData.getString(KEY_CHANNEL) ?: ""

        // NewPipe.init is process-wide static. MainActivity also calls it,
        // but the worker can run in a fresh process where MainActivity
        // never started.
        NewPipe.init(NewPipeDownloader.get())

        setForeground(buildForegroundInfo(titleHint, channelHint, null))

        val resolved = try {
            YoutubeResolver.resolve(sourceUrl)
        } catch (t: Throwable) {
            return@withContext failure(shortError(t))
        }

        val outFile = File(tracksDir, "$videoId.${resolved.extension}")
        outFile.parentFile?.mkdirs()
        if (outFile.exists()) outFile.delete()

        var received: Long = 0
        var totalBytes: Long = -1

        try {
            FileOutputStream(outFile).use { sink ->
                downloadLoop@ while (totalBytes < 0 || received < totalBytes) {
                    if (isStopped) {
                        outFile.delete()
                        return@withContext Result.failure(failureData("Cancelled"))
                    }
                    val endByte = received + CHUNK_SIZE - 1
                    val req = Request.Builder()
                        .url(resolved.audioUrl)
                        .addHeader("Range", "bytes=$received-$endByte")
                        .build()
                    client.newCall(req).execute().use { res ->
                        when (res.code) {
                            200 -> {
                                // Server doesn't honour Range — fall back to a
                                // single full-stream copy. The googlevideo CDN
                                // will likely kill this if another download from
                                // the same client opens, but better to try than
                                // to abort.
                                totalBytes = res.body?.contentLength() ?: -1L
                                res.body?.byteStream()?.let { stream ->
                                    val buf = ByteArray(BUFFER_SIZE)
                                    while (true) {
                                        if (isStopped) {
                                            outFile.delete()
                                            return@withContext Result.failure(failureData("Cancelled"))
                                        }
                                        val n = stream.read(buf)
                                        if (n <= 0) break
                                        sink.write(buf, 0, n)
                                        received += n
                                        emitProgress(received, totalBytes, titleHint, channelHint)
                                    }
                                }
                                if (totalBytes < 0) totalBytes = received
                            }
                            206 -> {
                                if (totalBytes < 0) {
                                    val cr = res.header("Content-Range")
                                    if (cr != null) {
                                        val slash = cr.indexOf('/')
                                        if (slash > 0) {
                                            totalBytes = cr.substring(slash + 1).trim().toLongOrNull() ?: -1L
                                        }
                                    }
                                }
                                var chunkBytes = 0L
                                res.body?.byteStream()?.let { stream ->
                                    val buf = ByteArray(BUFFER_SIZE)
                                    while (true) {
                                        if (isStopped) {
                                            outFile.delete()
                                            return@withContext Result.failure(failureData("Cancelled"))
                                        }
                                        val n = stream.read(buf)
                                        if (n <= 0) break
                                        sink.write(buf, 0, n)
                                        received += n
                                        chunkBytes += n
                                        emitProgress(received, totalBytes, titleHint, channelHint)
                                    }
                                }
                                if (chunkBytes == 0L) break@downloadLoop
                                if (totalBytes < 0) break@downloadLoop
                            }
                            else -> {
                                throw java.io.IOException("Audio stream returned HTTP ${res.code}")
                            }
                        }
                    }
                }
            }
        } catch (t: Throwable) {
            outFile.delete()
            return@withContext failure(shortError(t))
        }

        if (received <= 0L) {
            outFile.delete()
            return@withContext failure(
                "Download returned no audio bytes. The stream URL is likely invalid for this video."
            )
        }

        // Thumbnail — best effort; the procedural artwork still works.
        val thumbnailPath = if (!resolved.thumbnailUrl.isNullOrEmpty()) {
            try {
                val tFile = File(tracksDir, "$videoId.jpg")
                tFile.parentFile?.mkdirs()
                client.newCall(Request.Builder().url(resolved.thumbnailUrl).build()).execute().use { r ->
                    if (r.isSuccessful) {
                        val body = r.body
                        if (body != null) {
                            FileOutputStream(tFile).use { it.write(body.bytes()) }
                            tFile.absolutePath
                        } else null
                    } else null
                }
            } catch (_: Throwable) {
                null
            }
        } else null

        // Subtitles — best effort, same as thumbnail. WebVTT is small.
        val subtitlePath = if (!resolved.subtitleUrl.isNullOrEmpty()) {
            try {
                val sFile = File(tracksDir, "$videoId.vtt")
                sFile.parentFile?.mkdirs()
                client.newCall(Request.Builder().url(resolved.subtitleUrl).build()).execute().use { r ->
                    if (r.isSuccessful) {
                        val body = r.body
                        if (body != null) {
                            FileOutputStream(sFile).use { it.write(body.bytes()) }
                            sFile.absolutePath
                        } else null
                    } else null
                }
            } catch (_: Throwable) {
                null
            }
        } else null

        Result.success(
            workDataOf(
                KEY_VIDEO_ID to resolved.videoId,
                KEY_FILE_PATH to outFile.absolutePath,
                KEY_THUMBNAIL_PATH to thumbnailPath,
                KEY_SUBTITLE_PATH to subtitlePath,
                KEY_SUBTITLE_LANG to resolved.subtitleLanguageTag,
                KEY_SUBTITLE_AUTO to resolved.subtitleIsAutoGenerated,
                KEY_TITLE to resolved.title,
                KEY_CHANNEL to resolved.channel,
                KEY_DURATION_SECONDS to resolved.durationSeconds,
                KEY_BYTES_RECEIVED to received,
            )
        )
    }

    private suspend fun emitProgress(received: Long, total: Long, title: String, channel: String) {
        setProgress(
            workDataOf(
                KEY_BYTES_RECEIVED to received,
                KEY_TOTAL_BYTES to total,
            )
        )
        val percent = if (total > 0) ((received * 100) / total).toInt().coerceIn(0, 100) else -1
        val now = System.currentTimeMillis()
        val shouldRefresh = percent != lastForegroundPercent && (now - lastForegroundAtMs) > 250
        if (shouldRefresh) {
            lastForegroundPercent = percent
            lastForegroundAtMs = now
            setForeground(buildForegroundInfo(title, channel, if (percent >= 0) percent else null))
        }
    }

    override suspend fun getForegroundInfo(): ForegroundInfo {
        val title = inputData.getString(KEY_TITLE) ?: "Downloading audio"
        val channel = inputData.getString(KEY_CHANNEL) ?: ""
        return buildForegroundInfo(title, channel, null)
    }

    private fun buildForegroundInfo(title: String, channel: String, percent: Int?): ForegroundInfo {
        ensureNotificationChannel()
        val cancelIntent = WorkManager.getInstance(applicationContext)
            .createCancelPendingIntent(id)
        val builder = NotificationCompat.Builder(applicationContext, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(if (channel.isEmpty()) "Downloading audio" else channel)
            .setSmallIcon(R.drawable.ic_stat_music)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setShowWhen(false)
            .setSilent(true)
            .addAction(0, "Cancel", cancelIntent)
        if (percent != null) {
            builder.setProgress(100, percent, false)
        } else {
            builder.setProgress(0, 0, true)
        }
        val notification = builder.build()
        val notificationId = id.toString().hashCode() and 0x7fffffff
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            ForegroundInfo(
                notificationId,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            ForegroundInfo(notificationId, notification)
        }
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = applicationContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(CHANNEL_ID) != null) return
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_LOW).apply {
                description = "Audio download progress"
                setShowBadge(false)
                enableVibration(false)
                setSound(null, null)
            }
        )
    }

    private fun failure(message: String) = Result.failure(failureData(message))
    private fun failureData(message: String) = workDataOf(KEY_ERROR to message)

    private fun shortError(t: Throwable): String {
        val raw = t.message ?: t.javaClass.simpleName
        val cut = raw.indexOf(", uri=")
        return if (cut > 0) raw.substring(0, cut) else raw
    }

    companion object {
        const val CHANNEL_ID = "podcastr.downloads"
        const val CHANNEL_NAME = "Downloads"

        const val KEY_VIDEO_ID = "videoId"
        const val KEY_SOURCE_URL = "sourceUrl"
        const val KEY_TRACKS_DIR = "tracksDir"
        const val KEY_TITLE = "title"
        const val KEY_CHANNEL = "channel"
        const val KEY_FILE_PATH = "filePath"
        const val KEY_THUMBNAIL_PATH = "thumbnailPath"
        const val KEY_SUBTITLE_PATH = "subtitlePath"
        const val KEY_SUBTITLE_LANG = "subtitleLanguage"
        const val KEY_SUBTITLE_AUTO = "subtitleAutoGenerated"
        const val KEY_DURATION_SECONDS = "durationSeconds"
        const val KEY_BYTES_RECEIVED = "bytesReceived"
        const val KEY_TOTAL_BYTES = "totalBytes"
        const val KEY_ERROR = "error"

        private const val CHUNK_SIZE = 2L * 1024L * 1024L
        private const val BUFFER_SIZE = 64 * 1024
    }
}
