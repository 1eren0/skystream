package dev.akash.cs3engine

import com.lagradost.cloudstream3.AnimeLoadResponse
import com.lagradost.cloudstream3.AnimeSearchResponse
import com.lagradost.cloudstream3.Episode
import com.lagradost.cloudstream3.LiveStreamLoadResponse
import com.lagradost.cloudstream3.LoadResponse
import com.lagradost.cloudstream3.MainAPI
import com.lagradost.cloudstream3.MovieLoadResponse
import com.lagradost.cloudstream3.MovieSearchResponse
import com.lagradost.cloudstream3.SearchResponse
import com.lagradost.cloudstream3.SubtitleFile
import com.lagradost.cloudstream3.TorrentLoadResponse
import com.lagradost.cloudstream3.TvSeriesLoadResponse
import com.lagradost.cloudstream3.TvSeriesSearchResponse
import com.lagradost.cloudstream3.utils.DrmExtractorLink
import com.lagradost.cloudstream3.utils.ExtractorLink
import java.io.File

/** CloudStream model objects → plain maps for the JSON protocol. */
internal object Mappers {
    fun provider(api: MainAPI): Map<String, Any?> = mapOf(
        "name" to api.name,
        "mainUrl" to api.mainUrl,
        "lang" to api.lang,
        "types" to api.supportedTypes.map { it.name },
        "hasMainPage" to api.hasMainPage,
        "sections" to api.mainPage.map { it.name }.filter { it.isNotBlank() },
        "plugin" to api.sourcePlugin?.let { File(it).nameWithoutExtension },
    )

    fun searchItem(item: SearchResponse): Map<String, Any?> = mapOf(
        "name" to item.name,
        "url" to item.url,
        "type" to item.type?.name,
        "posterUrl" to item.posterUrl,
        "posterHeaders" to item.posterHeaders,
        "year" to when (item) {
            is MovieSearchResponse -> item.year
            is TvSeriesSearchResponse -> item.year
            is AnimeSearchResponse -> item.year
            else -> null
        },
    )

    fun loadResponse(response: LoadResponse): Map<String, Any?> {
        val out = linkedMapOf<String, Any?>(
            "name" to response.name,
            "url" to response.url,
            "type" to response.type.name,
            "plot" to response.plot,
            "posterUrl" to response.posterUrl,
            "backgroundPosterUrl" to response.backgroundPosterUrl,
            "year" to response.year,
            "tags" to response.tags,
            "duration" to response.duration,
        )
        when (response) {
            is MovieLoadResponse -> out["dataUrl"] = response.dataUrl
            is LiveStreamLoadResponse -> out["dataUrl"] = response.dataUrl
            is TvSeriesLoadResponse -> out["episodes"] = response.episodes.map { episode(it, null) }
            is AnimeLoadResponse -> out["episodes"] =
                response.episodes.flatMap { (dub, episodes) -> episodes.map { episode(it, dub.name) } }
            is TorrentLoadResponse -> {
                out["magnet"] = response.magnet
                out["torrent"] = response.torrent
            }
        }
        return out
    }

    private fun episode(episode: Episode, dub: String?): Map<String, Any?> = mapOf(
        "name" to episode.name,
        "season" to episode.season,
        "episode" to episode.episode,
        "data" to episode.data,
        "posterUrl" to episode.posterUrl,
        "description" to episode.description,
        "dub" to dub,
    )

    fun link(link: ExtractorLink): Map<String, Any?> {
        val out = linkedMapOf<String, Any?>(
            "source" to link.source,
            "name" to link.name,
            "url" to link.url,
            "type" to link.type.name,
            "quality" to link.quality,
            "referer" to link.referer,
            "headers" to link.headers,
        )
        if (link is DrmExtractorLink) {
            out["drm"] = mapOf(
                "kid" to link.kid,
                "key" to link.key,
                "uuid" to link.uuid.toString(),
                "licenseUrl" to link.licenseUrl,
            )
        }
        return out
    }

    fun subtitle(subtitle: SubtitleFile): Map<String, Any?> = mapOf(
        "lang" to subtitle.lang,
        "url" to subtitle.url,
        "headers" to subtitle.headers,
    )
}
