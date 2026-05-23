package com.example.podcastr

import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.schabi.newpipe.extractor.NewPipe
import org.schabi.newpipe.extractor.ServiceList
import org.schabi.newpipe.extractor.stream.AudioStream
import org.schabi.newpipe.extractor.stream.Stream
import org.schabi.newpipe.extractor.stream.VideoStream

// audio_service / just_audio_background require the Activity to extend
// AudioServiceActivity rather than the plain FlutterActivity.
class MainActivity : AudioServiceActivity() {
    private val channelName = "com.example.podcastr/youtube"
    private val scope = CoroutineScope(Dispatchers.Default)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // NewPipe needs a Downloader once per process.
        NewPipe.init(NewPipeDownloader.get())

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "resolve" -> {
                    val url = call.argument<String>("url")
                    if (url == null) {
                        result.error("ARG", "Missing url", null)
                        return@setMethodCallHandler
                    }
                    scope.launch {
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
                else -> result.notImplemented()
            }
        }
    }

    private fun resolveYoutube(url: String): Map<String, Any?> {
        val extractor = ServiceList.YouTube.getStreamExtractor(url)
        extractor.fetchPage()

        // Prefer audio-only DASH streams (smaller, no video to throw away).
        val audioStreams: List<AudioStream> = extractor.audioStreams
        android.util.Log.d("Podcastr", "Streams for $url: audio=${audioStreams.size} video=${extractor.videoStreams.size} videoOnly=${extractor.videoOnlyStreams.size}")
        val (chosen: Stream, bitrate: Int) = when {
            audioStreams.isNotEmpty() -> {
                val best = audioStreams.maxByOrNull { it.averageBitrate.takeIf { b -> b > 0 } ?: 0 }!!
                best to best.averageBitrate
            }
            else -> {
                // Fallback: some videos only expose muxed video+audio streams.
                // just_audio will play the audio track from a video container fine.
                val videoStreams: List<VideoStream> = extractor.videoStreams
                if (videoStreams.isEmpty()) {
                    throw IllegalStateException("No playable streams available for this video.")
                }
                // Smallest video (lowest resolution) — we only care about the audio track.
                val smallest = videoStreams.minByOrNull {
                    it.resolution?.removeSuffix("p")?.removeSuffix("60")?.toIntOrNull() ?: Int.MAX_VALUE
                } ?: videoStreams.first()
                smallest to 0
            }
        }
        android.util.Log.d("Podcastr", "Chosen stream: type=${if (chosen is AudioStream) "audio" else "video"} mime=${chosen.format?.mimeType} url=${chosen.content?.take(120)}")
        val mime = (chosen.format?.mimeType ?: "video/mp4")
        val ext = when {
            mime.contains("mp4") && chosen is AudioStream -> "m4a"
            mime.contains("mp4") -> "mp4"
            mime.contains("webm") -> "webm"
            mime.contains("opus") -> "opus"
            else -> "bin"
        }
        // Pick highest-resolution thumbnail (Image.estimatedResolutionLevel orders large→small).
        val thumbnailUrl = extractor.thumbnails
            ?.maxByOrNull { (it.width.takeIf { w -> w > 0 } ?: 0) * (it.height.takeIf { h -> h > 0 } ?: 0) }
            ?.url
        return mapOf(
            "videoId" to extractor.id,
            "title" to extractor.name,
            "channel" to (extractor.uploaderName ?: ""),
            "durationSeconds" to extractor.length,
            "audioUrl" to chosen.content,
            "averageBitrate" to bitrate,
            "mimeType" to mime,
            "extension" to ext,
            "thumbnailUrl" to thumbnailUrl
        )
    }
}
