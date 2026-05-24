package com.wgorski.podcastr

import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkInfo
import androidx.work.WorkManager
import androidx.work.workDataOf
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.schabi.newpipe.extractor.NewPipe

// audio_service / just_audio_background require the Activity to extend
// AudioServiceActivity rather than the plain FlutterActivity.
class MainActivity : AudioServiceActivity() {
    private val methodChannelName = "com.wgorski.podcastr/youtube"
    private val eventChannelName = "com.wgorski.podcastr/downloads"
    private val ioScope = CoroutineScope(Dispatchers.Default)
    private val observerJobs = mutableMapOf<String, Job>()
    private var downloadEventsSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // NewPipe needs a Downloader once per process.
        NewPipe.init(NewPipeDownloader.get())

        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, methodChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "resolve" -> handleResolve(call.argument<String>("url"), result)
                "enqueueDownload" -> handleEnqueue(call.arguments as? Map<*, *>, result)
                "cancelDownload" -> {
                    val id = (call.arguments as? Map<*, *>)?.get("videoId") as? String
                    if (id == null) result.error("ARG", "Missing videoId", null)
                    else {
                        WorkManager.getInstance(applicationContext).cancelUniqueWork(id)
                        result.success(null)
                    }
                }
                "abandonDownload" -> {
                    val id = (call.arguments as? Map<*, *>)?.get("videoId") as? String
                    if (id == null) result.error("ARG", "Missing videoId", null)
                    else {
                        // Tear down the observer first so the cancel doesn't
                        // emit a failed event for a row that's about to be
                        // deleted.
                        observerJobs.remove(id)?.cancel()
                        WorkManager.getInstance(applicationContext).cancelUniqueWork(id)
                        result.success(null)
                    }
                }
                "restoreDownload" -> handleRestore(
                    (call.arguments as? Map<*, *>)?.get("videoId") as? String,
                    result,
                )
                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, eventChannelName).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                downloadEventsSink = events
            }
            override fun onCancel(arguments: Any?) {
                downloadEventsSink = null
            }
        })
    }

    override fun onDestroy() {
        for (job in observerJobs.values) job.cancel()
        observerJobs.clear()
        ioScope.cancel()
        super.onDestroy()
    }

    private fun handleResolve(url: String?, result: MethodChannel.Result) {
        if (url == null) {
            result.error("ARG", "Missing url", null)
            return
        }
        ioScope.launch {
            try {
                val resolved = withContext(Dispatchers.IO) { resolveYoutube(url) }
                withContext(Dispatchers.Main) { result.success(resolved) }
            } catch (t: Throwable) {
                withContext(Dispatchers.Main) {
                    result.error("EXTRACT", t.message ?: t.javaClass.simpleName, null)
                }
            }
        }
    }

    private fun handleEnqueue(args: Map<*, *>?, result: MethodChannel.Result) {
        val videoId = args?.get("videoId") as? String
        val sourceUrl = args?.get("sourceUrl") as? String
        val tracksDir = args?.get("tracksDir") as? String
        if (videoId == null || sourceUrl == null || tracksDir == null) {
            result.error("ARG", "Missing videoId / sourceUrl / tracksDir", null)
            return
        }
        val title = args["title"] as? String ?: ""
        val channel = args["channel"] as? String ?: ""
        val data = workDataOf(
            DownloadWorker.KEY_VIDEO_ID to videoId,
            DownloadWorker.KEY_SOURCE_URL to sourceUrl,
            DownloadWorker.KEY_TRACKS_DIR to tracksDir,
            DownloadWorker.KEY_TITLE to title,
            DownloadWorker.KEY_CHANNEL to channel,
        )
        val request = OneTimeWorkRequestBuilder<DownloadWorker>()
            .setInputData(data)
            .addTag(TAG_PREFIX + videoId)
            .build()
        WorkManager.getInstance(applicationContext)
            .enqueueUniqueWork(videoId, ExistingWorkPolicy.REPLACE, request)
        observeUniqueWork(videoId)
        result.success(null)
    }

    private fun handleRestore(videoId: String?, result: MethodChannel.Result) {
        if (videoId == null) {
            result.error("ARG", "Missing videoId", null)
            return
        }
        ioScope.launch {
            val infos = try {
                withContext(Dispatchers.IO) {
                    WorkManager.getInstance(applicationContext)
                        .getWorkInfosForUniqueWork(videoId)
                        .get()
                }
            } catch (t: Throwable) {
                emptyList<WorkInfo>()
            }
            withContext(Dispatchers.Main) {
                val wi = infos.firstOrNull()
                if (wi == null) {
                    // No record — either never enqueued or WorkManager pruned
                    // it after the retention window. Dart should mark the row
                    // as failed.
                    downloadEventsSink?.success(
                        mapOf(
                            "type" to "failed",
                            "videoId" to videoId,
                            "message" to "Interrupted",
                        )
                    )
                    result.success("missing")
                } else {
                    // Emit the current snapshot, then keep observing (the
                    // observer no-ops if state is already terminal).
                    emit(videoId, wi)
                    if (!wi.state.isFinished) {
                        observeUniqueWork(videoId)
                    }
                    result.success("tracking")
                }
            }
        }
    }

    private fun observeUniqueWork(videoId: String) {
        observerJobs[videoId]?.cancel()
        val job = lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                WorkManager.getInstance(applicationContext)
                    .getWorkInfosForUniqueWorkFlow(videoId)
                    .collect { infos ->
                        val wi = infos.firstOrNull() ?: return@collect
                        emit(videoId, wi)
                        if (wi.state.isFinished) {
                            observerJobs.remove(videoId)?.cancel()
                        }
                    }
            }
        }
        observerJobs[videoId] = job
    }

    private fun emit(videoId: String, wi: WorkInfo) {
        val sink = downloadEventsSink ?: return
        val payload: Map<String, Any?> = when (wi.state) {
            WorkInfo.State.ENQUEUED, WorkInfo.State.BLOCKED -> mapOf(
                "type" to "queued",
                "videoId" to videoId,
            )
            WorkInfo.State.RUNNING -> mapOf(
                "type" to "progress",
                "videoId" to videoId,
                "bytesReceived" to wi.progress.getLong(DownloadWorker.KEY_BYTES_RECEIVED, 0L),
                "totalBytes" to wi.progress.getLong(DownloadWorker.KEY_TOTAL_BYTES, -1L),
            )
            WorkInfo.State.SUCCEEDED -> mapOf(
                "type" to "completed",
                "videoId" to videoId,
                "filePath" to wi.outputData.getString(DownloadWorker.KEY_FILE_PATH),
                "thumbnailPath" to wi.outputData.getString(DownloadWorker.KEY_THUMBNAIL_PATH),
                "subtitlePath" to wi.outputData.getString(DownloadWorker.KEY_SUBTITLE_PATH),
                "subtitleLanguage" to wi.outputData.getString(DownloadWorker.KEY_SUBTITLE_LANG),
                "subtitleAutoGenerated" to wi.outputData.getBoolean(DownloadWorker.KEY_SUBTITLE_AUTO, false),
                "title" to wi.outputData.getString(DownloadWorker.KEY_TITLE),
                "channel" to wi.outputData.getString(DownloadWorker.KEY_CHANNEL),
                "durationSeconds" to wi.outputData.getLong(DownloadWorker.KEY_DURATION_SECONDS, 0L),
                "bytesReceived" to wi.outputData.getLong(DownloadWorker.KEY_BYTES_RECEIVED, 0L),
            )
            WorkInfo.State.FAILED -> mapOf(
                "type" to "failed",
                "videoId" to videoId,
                "message" to (wi.outputData.getString(DownloadWorker.KEY_ERROR) ?: "Download failed"),
            )
            WorkInfo.State.CANCELLED -> mapOf(
                "type" to "failed",
                "videoId" to videoId,
                "message" to "Cancelled",
            )
        }
        sink.success(payload)
    }

    private fun resolveYoutube(url: String): Map<String, Any?> {
        val r = YoutubeResolver.resolve(url)
        return mapOf(
            "videoId" to r.videoId,
            "title" to r.title,
            "channel" to r.channel,
            "durationSeconds" to r.durationSeconds,
            "audioUrl" to r.audioUrl,
            "averageBitrate" to r.averageBitrate,
            "mimeType" to r.mimeType,
            "extension" to r.extension,
            "thumbnailUrl" to r.thumbnailUrl,
        )
    }

    companion object {
        const val TAG_PREFIX = "podcastr.download:"
    }
}
