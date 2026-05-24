package com.wgorski.podcastr

import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.schabi.newpipe.extractor.downloader.Downloader
import org.schabi.newpipe.extractor.downloader.Request as NPRequest
import org.schabi.newpipe.extractor.downloader.Response
import java.util.concurrent.TimeUnit

/**
 * OkHttp-backed Downloader for NewPipe Extractor.
 *
 * The defaults from NewPipe's own DownloaderImpl matter here — without a
 * realistic User-Agent and YouTube's consent cookie the extractor will get
 * "The page needs to be reloaded" responses.
 */
class NewPipeDownloader private constructor() : Downloader() {
    private val client: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .followRedirects(true)
        .followSslRedirects(true)
        .build()

    override fun execute(request: NPRequest): Response {
        val builder = Request.Builder().url(request.url())
        // Apply caller headers first…
        for ((name, values) in request.headers()) {
            builder.removeHeader(name)
            for (v in values) builder.addHeader(name, v)
        }
        // …then fill in defaults NewPipe expects when the caller didn't set them.
        if (request.headers()["User-Agent"].isNullOrEmpty()) {
            builder.header("User-Agent", USER_AGENT)
        }
        if (request.headers()["Accept-Language"].isNullOrEmpty()) {
            builder.header("Accept-Language", "en-GB,en;q=0.5")
        }
        // YouTube shows a consent wall in EU/UK unless this cookie is set.
        val host = request.url().lowercase()
        if (host.contains("youtube.com") || host.contains("youtu.be") || host.contains("googlevideo.com")) {
            val existing = request.headers()["Cookie"]?.joinToString("; ") ?: ""
            val merged = if (existing.isEmpty()) YT_CONSENT_COOKIE else "$existing; $YT_CONSENT_COOKIE"
            builder.header("Cookie", merged)
        }

        val body = request.dataToSend()
        val method = request.httpMethod()
        if (body != null) {
            builder.method(method, body.toRequestBody())
        } else if (method != "GET") {
            builder.method(method, null)
        }

        client.newCall(builder.build()).execute().use { res ->
            if (res.code == 429) {
                throw org.schabi.newpipe.extractor.exceptions.ReCaptchaException(
                    "reCaptcha challenge requested from " + res.request.url,
                    res.request.url.toString()
                )
            }
            val responseHeaders = mutableMapOf<String, List<String>>()
            for (name in res.headers.names()) {
                responseHeaders[name] = res.headers.values(name)
            }
            val bodyString = res.body?.string() ?: ""
            return Response(
                res.code,
                res.message,
                responseHeaders,
                bodyString,
                res.request.url.toString()
            )
        }
    }

    companion object {
        // Pinned, recent Firefox UA — what NewPipe's reference impl ships.
        private const val USER_AGENT =
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:128.0) Gecko/20100101 Firefox/128.0"
        // CONSENT cookie: bypasses YouTube's EU consent wall.
        private const val YT_CONSENT_COOKIE = "CONSENT=YES+cb.20210328-17-p0.en+FX+000"

        @Volatile private var instance: NewPipeDownloader? = null
        fun get(): NewPipeDownloader = instance ?: synchronized(this) {
            instance ?: NewPipeDownloader().also { instance = it }
        }
    }
}

