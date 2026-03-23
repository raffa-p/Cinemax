//
//  TMDBModels.swift
//  Cinemax
//
//

import Foundation

/// Generic response from DB
struct TMDBResponse: Codable {
    let results: [TMDBItem]
}


/// A unified model representing either a movie or a TV show item returned by TMDB.
///
/// TMDBItem encapsulates common fields shared between movies and TV series as returned
/// by The Movie Database (TMDB) API. Some properties are specific to one media type:
/// - For movies: `title`, `releaseDate`, and `runtime`
/// - For TV series: `name`, `firstAirDate`, `seasons`, and `episodes`
///
/// Properties:
/// - `id`: The unique TMDB identifier for the item.
/// - `title`: The movie title, present only for movie items.
/// - `name`: The TV series name, present only for TV items.
/// - `overview`: A synopsis or description of the item, when available.
/// - `posterPath`: Relative path to the poster image on TMDB’s CDN (use `fullPosterURL` to build a full URL).
/// - `backdropPath`: Relative path to the backdrop image on TMDB’s CDN.
/// - `voteAverage`: The average user rating for the item (0–10 scale).
/// - `releaseDate`: The movie’s release date in ISO 8601 format (e.g., "2024-03-15"); movies only.
/// - `firstAirDate`: The TV series’ first air date in ISO 8601 format; TV only.
/// - `mediaType`: The type of the media as returned by TMDB (e.g., "movie", "tv").
/// - `seasons`: Lightweight metadata for the TV show’s seasons; TV only.
/// - `episodes`: Episodes included in certain TV detail responses; TV only.
/// - `runtime`: The duration in minutes; present for movies when available.
///
/// Computed properties:
/// - `displayTitle`: A user-friendly title, preferring `title` (movies) then `name` (TV);
///   falls back to "Sconosciuto" if neither is available.
/// - `displayYear`: The four-digit year extracted from `releaseDate` or `firstAirDate`,
///   whichever is available first. Empty if no date is present.
/// - `fullPosterURL`: A complete URL to the poster image using TMDB’s w500 size, or `nil`
///   if `posterPath` is missing or empty. Leading slashes in `posterPath` are trimmed.
///
/// Coding keys:
/// - Maps snake_case TMDB fields to Swift properties:
///   - `poster_path` -> `posterPath`
///   - `backdrop_path` -> `backdropPath`
///   - `vote_average` -> `voteAverage`
///   - `release_date` -> `releaseDate`
///   - `first_air_date` -> `firstAirDate`
///   - `media_type` -> `mediaType`
///
/// Conforms to:
/// - `Codable` for JSON decoding/encoding with TMDB responses.
/// - `Identifiable` to support usage in SwiftUI lists and collections.
///
/// Notes:
/// - Not all fields are present in every TMDB endpoint or for every media type.
///   Use optional handling to accommodate missing data.
/// - Image paths are relative; use TMDB’s image base URL to construct full URLs.
struct TMDBItem: Codable, Identifiable {
    let id: Int
    let title: String?
    let name: String?
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let voteAverage: Double?
    let releaseDate: String?
    let firstAirDate: String?
    let mediaType: String?
    let seasons: [TMDBSeasonMetadata]?
    let episodes: [TMDBEpisode]?
    let runtime: Int? 
    

    enum CodingKeys: String, CodingKey {
        case id, title, name, overview
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case voteAverage = "vote_average"
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
        case mediaType = "media_type"
        case seasons
        case episodes
        case runtime
    }
    
    var displayTitle: String { title ?? name ?? "Sconosciuto" }
    var displayYear: String {
        let date = releaseDate ?? firstAirDate ?? ""
        return String(date.prefix(4))
    }
    var fullPosterURL: URL? {
        guard let path = posterPath, !path.isEmpty else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w500/\(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))")
    }
}

/// A lightweight model representing metadata for a single TV season from TMDB.
///
/// This struct is used to decode season-related information returned by TMDB's API,
/// typically as part of a TV show's details response. It focuses on the season's
/// ordinal position within the series.
///
/// Properties:
/// - `seasonNumber`: The zero- or one-based index of the season as provided by TMDB,
///   mapped from the `season_number` field in the API response. Most series use 1-based
///   numbering (e.g., Season 1, Season 2), but some special collections may use 0 for
///   specials or pilot episodes.
///
/// Conforms to:
/// - `Codable` to support JSON decoding/encoding from TMDB's API.
///
/// Coding keys:
/// - Maps `seasonNumber` to the `season_number` JSON key.
struct TMDBSeasonMetadata: Codable {
    let seasonNumber: Int
    
    enum CodingKeys: String, CodingKey {
        case seasonNumber = "season_number"
    }
}

/// A model representing a single episode from The Movie Database (TMDB).
///
/// This struct is used to decode episode data returned by TMDB's API and to
/// uniquely identify episodes within the app.
///
/// Properties:
/// - `id`: The unique identifier for the episode as provided by TMDB.
/// - `episodeNumber`: The episode's number within its season (e.g., 1 for the season premiere).
/// - `name`: The title of the episode.
/// - `overview`: A brief synopsis or description of the episode. May be an empty string if not provided by TMDB.
/// - `runtime`: The duration of the episode in minutes, if available.
/// - `stillPath`: The relative path to the episode's still image on TMDB's image CDN, if available.
/// - `showId`: The identifier of the parent TV show, if included in the API response.
///
/// Coding keys:
/// - Maps `episodeNumber` to the `episode_number` field in the JSON.
/// - Maps `stillPath` to the `still_path` field in the JSON.
/// - Maps `showId` to the `show_id` field in the JSON.
///
/// Conforms to:
/// - `Codable` for JSON encoding/decoding.
/// - `Identifiable` to allow use in SwiftUI lists and collections.
struct TMDBEpisode: Codable, Identifiable {
    let id: Int
    let episodeNumber: Int
    let name: String
    let overview: String
    let runtime: Int?
    let stillPath: String?
    let showId: Int?
    
    enum CodingKeys: String, CodingKey {
        case id, name, overview, runtime
        case episodeNumber = "episode_number"
        case stillPath = "still_path"
        case showId = "show_id"
    }
}
