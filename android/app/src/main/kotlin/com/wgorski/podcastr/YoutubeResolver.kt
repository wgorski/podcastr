package com.wgorski.podcastr

import android.util.Log
import org.schabi.newpipe.extractor.ServiceList
import org.schabi.newpipe.extractor.stream.AudioStream
import org.schabi.newpipe.extractor.stream.AudioTrackType
import org.schabi.newpipe.extractor.stream.VideoStream

/**
 * Single source of truth for "given a YouTube URL, what should we
 * download?" — used by both the resolve MethodChannel call (for the
 * download sheet's metadata preview) and the foreground download worker
 * (which re-resolves at run time because googlevideo URLs expire).
 *
 * Critically: YouTube now ships AI-dubbed audio tracks for many videos
 * (e.g. an English video also has Hindi / Portuguese / Spanish dubs).
 * Picking by highest bitrate alone can land on a dub — we explicitly
 * prefer the [AudioTrackType.ORIGINAL] track first, then the unlabelled
 * single-track case, and only fall back to "whatever's available" as a
 * last resort.
 */
object YoutubeResolver {
    data class Resolved(
        val videoId: String,
        val title: String,
        val channel: String,
        val durationSeconds: Long,
        val audioUrl: String,
        val averageBitrate: Int,
        val mimeType: String,
        val extension: String,
        val thumbnailUrl: String?,
    )

    fun resolve(url: String): Resolved {
        val extractor = ServiceList.YouTube.getStreamExtractor(url)
        extractor.fetchPage()

        val audios: List<AudioStream> = extractor.audioStreams
        Log.d(
            TAG,
            "Streams for $url: audio=${audios.size} video=${extractor.videoStreams.size} " +
                "videoOnly=${extractor.videoOnlyStreams.size}"
        )
        if (audios.isNotEmpty()) {
            Log.d(
                TAG,
                "Audio tracks: " + audios.joinToString { a ->
                    "${a.audioTrackType ?: "—"}:${a.audioLocale ?: "—"}@${a.averageBitrate}"
                }
            )
        }

        val chosenContent: String
        val mime: String
        val bitrate: Int
        val isAudioOnly: Boolean

        if (audios.isNotEmpty()) {
            val best = pickOriginalAudio(audios)
            chosenContent = best.content ?: ""
            mime = best.format?.mimeType ?: "audio/mp4"
            bitrate = best.averageBitrate
            isAudioOnly = true
            Log.d(
                TAG,
                "Chosen audio: trackType=${best.audioTrackType} locale=${best.audioLocale} " +
                    "bitrate=${best.averageBitrate} mime=$mime"
            )
        } else {
            // Some videos only expose muxed video+audio streams. just_audio
            // will play the audio track from a video container fine.
            val videos: List<VideoStream> = extractor.videoStreams
            if (videos.isEmpty()) {
                throw IllegalStateException("No playable streams available for this video.")
            }
            val smallest = videos.minByOrNull {
                it.resolution?.removeSuffix("p")?.removeSuffix("60")?.toIntOrNull() ?: Int.MAX_VALUE
            } ?: videos.first()
            chosenContent = smallest.content ?: ""
            mime = smallest.format?.mimeType ?: "video/mp4"
            bitrate = 0
            isAudioOnly = false
        }

        if (chosenContent.isEmpty()) {
            throw IllegalStateException("Extractor produced an empty stream URL.")
        }

        val ext = when {
            mime.contains("mp4") && isAudioOnly -> "m4a"
            mime.contains("mp4") -> "mp4"
            mime.contains("webm") -> "webm"
            mime.contains("opus") -> "opus"
            else -> "bin"
        }

        // Pick the highest-resolution thumbnail (NewPipe's `Image` list is
        // ordered large→small, but be explicit).
        val thumbnailUrl = extractor.thumbnails
            ?.maxByOrNull { (it.width.takeIf { w -> w > 0 } ?: 0) * (it.height.takeIf { h -> h > 0 } ?: 0) }
            ?.url

        return Resolved(
            videoId = extractor.id,
            title = extractor.name,
            channel = extractor.uploaderName ?: "",
            durationSeconds = extractor.length,
            audioUrl = chosenContent,
            averageBitrate = bitrate,
            mimeType = mime,
            extension = ext,
            thumbnailUrl = thumbnailUrl,
        )
    }

    /**
     * Prefer [AudioTrackType.ORIGINAL]. Falls back to streams with no
     * track type (single-language videos don't tag their audio) and only
     * uses dubbed / descriptive tracks as a last resort when the
     * extractor returns nothing else.
     */
    private fun pickOriginalAudio(streams: List<AudioStream>): AudioStream {
        val original = streams.filter { it.audioTrackType == AudioTrackType.ORIGINAL }
        if (original.isNotEmpty()) return bestByBitrate(original)
        val untyped = streams.filter { it.audioTrackType == null }
        if (untyped.isNotEmpty()) return bestByBitrate(untyped)
        return bestByBitrate(streams)
    }

    private fun bestByBitrate(streams: List<AudioStream>): AudioStream =
        streams.maxByOrNull { it.averageBitrate.takeIf { b -> b > 0 } ?: 0 } ?: streams.first()

    private const val TAG = "Podcastr"
}
