//
//  SupabaseInterface.swift
//  Cinemax
//
//

import Foundation
import SwiftUI
import Supabase

/// A façade responsible for integrating Supabase-backed user data with TMDB metadata
/// and exposing high-level, app-ready models (`MediaItem`) to the UI.
///
/// Responsibilities:
/// - Reads lists from Supabase (e.g., "Continue Watching", "Personal List").
/// - Fetches complementary details from TMDB for each entry to provide rich metadata.
/// - Provides convenience loading for trending titles directly from TMDB.
/// - Performs lightweight mapping into the app’s `MediaItem` model, normalizing fields
///   such as type, match percentage, release year, description, and poster URL.
///
/// Key behaviors and conventions:
/// - Match percentage is derived from TMDB’s `voteAverage * 10` and cast to `Int`.
/// - Year values are normalized to a 4-character string when available.
/// - Descriptions fall back to a localized default when not provided by TMDB.
/// - Seasons are currently returned as an empty array for all items.
/// - Image URLs rely on TMDB’s `fullPosterURL?.absoluteString` when available.
/// - TMDB lookups prefer TV show details first, then fall back to movie details when needed.
///
/// Caching:
/// - `cacheWatching` and `cacheList` are optional in-memory caches for previously
///   fetched "Continue Watching" and "Personal List" content, respectively. They are
///   not automatically hydrated or persisted; populate and consume them as needed.
///
/// Error handling:
/// - Supabase fetch errors are generally caught and result in empty arrays, allowing the
///   UI to remain responsive while logging the failure.
/// - TMDB fetch failures for individual items are logged and skipped; processing continues
///   for remaining items.
/// - Public APIs are `async` and may throw; call sites should use `await` and handle errors.
///
/// Dependencies:
/// - SupabaseManager: Provides the configured Supabase client.
/// - MovieService: Provides TMDB fetching utilities for trending, movie details, and TV details.
/// - MediaItem: The app’s unified media model used for rendering in the UI.
///
/// Platform:
/// - Designed for Apple platforms using Swift Concurrency and SwiftUI-friendly models.
///
/// Notes:
/// - Ensure the Supabase tables ("keepWatching", "PersonalList") and their fields
///   (e.g., `tmdb_id`, `media_type`) match the expected schema.
/// - The mapping logic assumes Italian localization for some fallbacks (e.g., description).
///   Adjust strings to your localization strategy as needed.
class SupabaseInterface {
    public var cacheWatching: [MediaItem]?
    public var cacheList: [MediaItem]?
    
    /// Loads trending media items from TMDB and maps them into `MediaItem` models.
    ///
    /// This method:
    /// - Calls `MovieService.shared.fetchTrending()` to retrieve the current trending titles from TMDB.
    /// - Transforms each TMDB result into a `MediaItem`, inferring whether it is a movie or a series:
    ///   - `type` is `.movie` if `title` is present, otherwise `.series`.
    ///   - `matchPercentage` is computed as `voteAverage * 10` and cast to `Int`.
    ///   - `year` uses `displayYear` from the TMDB result.
    ///   - `description` falls back to "Nessuna trama disponibile" if unavailable.
    ///   - `imageName` uses the absolute string of `fullPosterURL` when available.
    ///   - `seasons` is currently an empty array for all items.
    ///
    /// - Returns: An array of `MediaItem` representing trending content enriched with essential metadata.
    /// - Throws: Rethrows any error encountered while fetching trending data from TMDB.
    func loadTrendings() async throws -> [MediaItem] {
        let tmdbResults = try await MovieService.shared.fetchTrending()
        
        let trendings = tmdbResults.map{elem in MediaItem(
            tmdbId: elem.id,
            title: elem.displayTitle,
            imageName: elem.fullPosterURL?.absoluteString ?? "",
            type: elem.title != nil ? .movie : .series,
            matchPercentage: Int((elem.voteAverage ?? 0) * 10),
            year: elem.displayYear,
            description: elem.overview ?? "Nessuna trama disponibile",
            isWatched: false,
            seasons: []
        )}
        return trendings
    }
    
    /// Fetches the "Continue Watching" list from Supabase and enriches each entry with TMDB details.
    ///
    /// This method:
    /// - Queries the "keepWatching" table in Supabase to retrieve entries (as `watchingItem` records).
    /// - For each entry with a valid `tmdb_id`, attempts to load detailed metadata from TMDB:
    ///   - First tries to fetch as a TV show via `MovieService.shared.fetchShowDetails(id:)`.
    ///   - If that fails, falls back to fetching as a movie via `MovieService.shared.fetchMovieDetails(id:)`.
    /// - Maps each successful TMDB response into a `MediaItem` with:
    ///   - `type` set to `.series` for TV shows or `.movie` for movies
    ///   - `matchPercentage` derived from `voteAverage * 10`
    ///   - `year` taken from `firstAirDate` (TV) or `releaseDate` (Movie), truncated to the first 4 characters
    ///   - `description` defaulting to "Nessuna trama disponibile" when missing
    ///   - `seasons` currently set to an empty array
    ///
    /// Error handling:
    /// - If a Supabase query error occurs, the function logs the error and returns an empty array.
    /// - If a TMDB fetch for a specific entry fails, it logs the failure and continues processing the remaining entries.
    ///
    /// - Returns: An array of `MediaItem` representing the user's "Continue Watching" items enriched with TMDB details.
    /// - Throws: Propagates errors only if thrown by the async context; internally, Supabase errors are caught and result in an empty array, while individual TMDB errors are logged and skipped.
    ///
    /// Notes:
    /// - Entries with a missing `tmdb_id` are skipped.
    /// - Poster image URLs are taken from `fullPosterURL?.absoluteString` when available.
    func loadWatching() async throws -> [MediaItem] {
        do {
            let entries: [watchingItem] = try await SupabaseManager.shared.client
                .from("keepWatching")
                .select()
                .execute()
                .value
            
            var detailedList: [MediaItem] = []
            
            // download details
            for entry in entries {
                guard let safeId = entry.tmdb_id else { continue }
                
                do {
                    // first try to download as tv show. if not it's a film (catch statement)
                    let tvDetails = try await MovieService.shared.fetchShowDetails(id: safeId)
                    
                    let item = MediaItem(
                        tmdbId: tvDetails.id,
                        title: tvDetails.name ?? tvDetails.title ?? "Sconosciuto",
                        imageName: tvDetails.fullPosterURL?.absoluteString ?? "",
                        type: .series,
                        matchPercentage: Int((tvDetails.voteAverage ?? 0) * 10),
                        year: String((tvDetails.firstAirDate ?? "").prefix(4)),
                        description: tvDetails.overview ?? "Nessuna trama disponibile",
                        isWatched: false,
                        seasons: []
                    )
                    detailedList.append(item)
                    
                } catch {
                    do {
                        let movieDetails = try await MovieService.shared.fetchMovieDetails(id: safeId)
                        
                        let item = MediaItem(
                            tmdbId: movieDetails.id,
                            title: movieDetails.name ?? movieDetails.title ?? "Sconosciuto",
                            imageName: movieDetails.fullPosterURL?.absoluteString ?? "",
                            type: .movie,
                            matchPercentage: Int((movieDetails.voteAverage ?? 0) * 10),
                            year: String((movieDetails.releaseDate ?? "").prefix(4)),
                            description: movieDetails.overview ?? "Nessuna trama disponibile",
                            isWatched: false,
                            seasons: []
                        )
                        detailedList.append(item)
                        
                    } catch {
                        print("ID \(safeId) inesistente.")
                    }
                }
            }
            
            return detailedList
            
        } catch {
            print("Errore caricamento Continua a Guardare da TMDB: \(error)")
            return []
        }
    }
    
    /// Fetches the user's personal list from the Supabase "PersonalList" table and enriches each entry with full details from TMDB.
    ///
    /// This method performs two steps:
    /// 1. Reads all rows from the "PersonalList" table via Supabase.
    /// 2. For each entry, fetches complete metadata from TMDB (either TV show or movie, based on `media_type`)
    ///    and maps it into a `MediaItem` with `inMyList` set to `true`.
    ///
    /// Behavior:
    /// - If `media_type` equals "Serie TV", the item is treated as a TV show and fetched via `fetchShowDetails`.
    /// - Otherwise, it is treated as a movie and fetched via `fetchMovieDetails`.
    /// - If a row is missing `tmdb_id`, it is skipped.
    /// - Individual TMDB fetch failures are logged and skipped; the method continues processing remaining items.
    /// - If the Supabase query fails, an empty array is returned.
    ///
    /// - Returns: An array of `MediaItem` representing the user's personal list, enriched with TMDB details.
    /// - Throws: Rethrows only if the function signature requires it; internally catches most errors and returns an empty array on Supabase failure.
    ///
    /// Notes:
    /// - `matchPercentage` is derived from TMDB `voteAverage` multiplied by 10 and converted to `Int`.
    /// - `year` is extracted as the first 4 characters of `firstAirDate` (for TV) or `displayYear` (for movies).
    /// - `description` falls back to "Nessuna trama disponibile" when missing.
    /// - `seasons` is currently returned as an empty array for both movies and TV shows.
    func loadPersonalList() async throws -> [MediaItem] {
        do {
            let entries: [personalListItem] = try await SupabaseManager.shared.client
                .from("PersonalList").select().execute().value

            var detailedList: [MediaItem] = []
            for entry in entries {
                do {
                    guard let safeId = entry.tmdb_id else { continue }
                    
                    if entry.media_type == "Serie TV" {
                        let tvDetails = try await MovieService.shared.fetchShowDetails(id: safeId)
                        let item = MediaItem(
                            tmdbId: tvDetails.id,
                            title: tvDetails.name ?? tvDetails.title ?? "Sconosciuto",
                            imageName: tvDetails.fullPosterURL?.absoluteString ?? "",
                            type: .series,
                            matchPercentage: Int((tvDetails.voteAverage ?? 0) * 10),
                            year: String((tvDetails.firstAirDate ?? "").prefix(4)),
                            description: tvDetails.overview ?? "Nessuna trama disponibile",
                            isWatched: false,
                            inMyList: true,
                            seasons: []
                        )
                        detailedList.append(item)
                    } else {
                        let movieDetails = try await MovieService.shared.fetchMovieDetails(id: safeId)
                        let item = MediaItem(
                            tmdbId: movieDetails.id,
                            title: movieDetails.name ?? movieDetails.title ?? "Sconosciuto",
                            imageName: movieDetails.fullPosterURL?.absoluteString ?? "",
                            type: .movie,
                            matchPercentage: Int((movieDetails.voteAverage ?? 0) * 10),
                            year: String((movieDetails.displayYear).prefix(4)),
                            description: movieDetails.overview ?? "Nessuna trama disponibile",
                            isWatched: false,
                            inMyList: true,
                            seasons: []
                        )
                        detailedList.append(item)
                    }
                } catch { print("Errore TMDB: \(error)") }
            }
            return detailedList
        } catch { return [] }
    }
}
