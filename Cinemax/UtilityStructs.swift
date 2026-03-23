//
//  UtilityStructs.swift
//  Cinemax
//
//

import Foundation


/// A model representing a single TV episode within a season.
///
/// Conforms to:
/// - `Identifiable`: Each episode has a stable, unique `id`.
/// - `Hashable`: Episodes can be stored in sets and used as dictionary keys.
///
/// Properties:
/// - `id`: A unique identifier generated for the episode instance.
/// - `number`: The episode number within its season (e.g., 1 for S01E01).
/// - `title`: The localized or display title of the episode.
/// - `duration`: A human-readable duration string (e.g., "45m").
/// - `plot`: A short synopsis or description of the episode.
/// - `imageURL`: An optional URL to a promotional still or thumbnail for the episode.
/// - `isWatched`: Indicates whether the user has marked this episode as watched. Defaults to `false`.
/// - `show_id`: An optional identifier referencing the parent show in a remote database (e.g., TMDB).
struct Episode: Identifiable, Hashable {
    let id = UUID()
    let number: Int
    let title: String
    let duration: String
    let plot: String
    let imageURL: URL?
    var isWatched: Bool = false
    let show_id: Int?
}

/// A model representing a TV season, containing an ordered collection of episodes.
///
/// Conforms to:
/// - `Identifiable`: Each season has a stable, unique `id`.
/// - `Hashable`: Seasons can be compared, stored in sets, and used as dictionary keys.
///
/// Properties:
/// - `id`: A unique identifier generated for the season instance.
/// - `number`: The season number within the series (e.g., 1 for Season 1).
/// - `episodes`: The list of `Episode` items that belong to this season, in viewing order.
struct Season: Identifiable, Hashable {
    let id = UUID()
    let number: Int
    var episodes: [Episode]
}

/// Represents the kind of media supported by the app.
///
/// Used to distinguish between different content types when displaying,
/// filtering, or applying logic specific to films or TV series.
///
/// - Note: The raw values are localized display names used in the UI.
/// - Important: Prefer using the enum cases (`.movie`, `.series`) in code
///   rather than relying on the raw string values.
///
/// Cases:
/// - `movie`: A feature-length film. Raw value: "Film".
/// - `series`: A television series composed of seasons and episodes. Raw value: "Serie TV".
///
/// Conforms to:
/// - `RawRepresentable` (String): Provides a user-facing display label via `rawValue`.
/// - `CaseIterable`: Enables iteration over all supported media types (e.g., for pickers).
enum MediaType: String, CaseIterable {
    case movie = "Film"
    case series = "Serie TV"
}

/// A unified model representing either a film or a TV series used throughout the app.
///
/// MediaItem encapsulates the common properties needed to render items in lists,
/// detail views, and to track user interactions such as watch progress and list membership.
/// It supports both movies and series via the `type` property and provides convenience
/// computed properties for episode progress when the item is a series.
///
/// Conforms to:
/// - `Identifiable`: Provides a stable, unique `id` for use in lists and diffing.
/// - `Hashable`: Enables use in sets, dictionary keys, and efficient collection updates.
///
/// Properties:
/// - `id`: A unique identifier for this media item instance.
/// - `tmdbId`: Optional identifier referencing the item in a remote database (e.g., TMDB).
/// - `title`: The localized or display title of the media.
/// - `imageName`: The asset name or path used to display the media’s poster/thumbnail.
/// - `type`: The kind of media, either `.movie` or `.series`.
/// - `matchPercentage`: A heuristic “match” score (0–100) used for personalization displays.
/// - `year`: A string representation of the release year or first-air year.
/// - `description`: A synopsis or overview of the media content.
/// - `duration`: Optional runtime string (e.g., "2h 10m" for movies); not typically used for series.
/// - `isWatched`: Indicates whether the user has fully watched the item. For series, this typically
///   implies all episodes have been watched.
/// - `inMyList`: Whether the user has added this item to their personal list.
/// - `isInProgress`: True when the item is a series and at least one episode is watched but not all.
///   Always false for movies.
/// - `seasons`: For series, the ordered collection of seasons and their episodes. Empty for movies.
/// - `totalEpisodes`: The total number of episodes across all seasons (series only).
/// - `watchedEpisodes`: The number of episodes marked as watched across all seasons (series only).
///
/// Usage Notes:
/// - For movies, `isInProgress` is always false and `duration` is the primary runtime indicator.
struct MediaItem: Identifiable, Hashable {
    let id = UUID()
    let tmdbId: Int?
    let title: String
    let imageName: String
    let type: MediaType
    let matchPercentage: Int
    let year: String
    let description: String
    var duration: String?
    var isWatched: Bool = false
    var inMyList: Bool = false
    var isInProgress: Bool {
        guard type == .series else { return false }
        return watchedEpisodes > 0 && watchedEpisodes < totalEpisodes
    }
    var seasons: [Season] = []
    var totalEpisodes: Int { seasons.reduce(0) { $0 + $1.episodes.count } }
    var watchedEpisodes: Int {
        seasons.reduce(0) { seasonCount, season in
            seasonCount + season.episodes.filter { $0.isWatched }.count
        }
    }
}

// MARK: - DATABASE MODELS
// each struct represents a specific table of DB

/// A database model representing an entry in the "keep watching" list.
///
/// This struct maps to the keepWatching table in the app’s backend
/// and tracks which titles a user is currently watching or should resume.
///
/// Conforms to:
/// - `Identifiable`: Provides a stable `id` for use in SwiftUI lists and diffing.
/// - `Hashable`: Allows use in sets and as dictionary keys.
/// - `Codable`: Supports JSON encoding/decoding for network and persistence operations.
///
/// Properties:
/// - `id`: A locally generated UUID used for SwiftUI identity. Not persisted remotely.
/// - `tmdb_id`: The remote TMDB identifier of the media item to resume (movie or TV show).
/// - `user`: The unique identifier of the user who is watching the item.
///
/// Coding:
/// - Uses `CodingKeys` to ensure the `tmdb_id` key maps directly to the backend field name.
struct watchingItem: Identifiable, Hashable, Codable {
    var id = UUID()
    let tmdb_id: Int?
    let user: UUID?
    
    enum CodingKeys: String, CodingKey {
        case tmdb_id = "tmdb_id"
        case user
    }
}

/// A database model representing an item saved in a user’s personal list.
///
/// This struct mirrors a row in the personalList table on the backend and is used to
/// persist which titles a user has explicitly added to their list, along with metadata
/// about when the item was added.
///
/// Conforms to:
/// - `Identifiable`: Provides a stable, locally generated `id` for SwiftUI identity and diffing.
/// - `Hashable`: Enables use in sets and as dictionary keys.
/// - `Codable`: Supports encoding/decoding for network transport and local persistence.
///
/// Properties:
/// - `id`: A locally generated UUID used only for app-side identity; not persisted remotely.
/// - `tmdb_id`: The TMDB identifier of the media item added to the list (movie or TV show).
/// - `media_type`: A string describing the media type for the item (e.g., "movie", "tv").
/// - `user_id`: The unique identifier of the user who owns this list entry (if provided by backend).
/// - `created_at`: A timestamp string indicating when the entry was created on the backend.
///
/// Coding:
/// - Uses `CodingKeys` to map properties to the exact backend field names for compatibility.
///
/// Usage:
/// - Decode from server responses to populate the user’s list.
/// - Encode when creating/removing entries on the backend.
/// - Combine with `MediaItem` data to render the user’s personal list in the UI.
struct personalListItem: Identifiable, Hashable, Codable {
    var id = UUID()
    let tmdb_id: Int?
    let media_type: String?
    
    var user_id: UUID?
    var created_at: String?
    
    enum CodingKeys: String, CodingKey {
        case tmdb_id
        case media_type
        case user_id
        case created_at
    }
}

/// A database model representing a single "watched" entry for a user.
///
/// This struct mirrors a row in the watched_items table on the backend and records
/// that a user has watched a specific movie or a specific episode of a TV series.
/// For movies, only `tmdb_id` and `media_type` are typically set; for TV episodes,
/// `season_number`, `episode_number`, and optionally `show_id` are also populated.
///
/// Conforms to:
/// - `Identifiable`: Provides a stable, locally generated `id` for SwiftUI lists and diffing.
/// - `Hashable`: Enables storage in sets and use as dictionary keys.
/// - `Codable`: Supports JSON encoding/decoding for network communication and persistence.
///
/// Properties:
/// - `id`: A locally generated UUID used only for app-side identity; not persisted remotely.
/// - `tmdb_id`: The TMDB identifier of the watched media (movie or TV show).
/// - `media_type`: The type of media ("movie" or "tv") associated with the watched entry.
/// - `season_number`: For TV entries, the season number of the watched episode; nil for movies.
/// - `episode_number`: For TV entries, the episode number within the season; nil for movies.
/// - `user_id`: The unique identifier of the user who watched the item (if provided by backend).
/// - `created_at`: A timestamp string indicating when this watch was recorded on the backend.
/// - `show_id`: Optional identifier for the parent TV show (e.g., TMDB show ID), useful for episode context.
///
/// Coding:
/// - Uses `CodingKeys` to map properties to backend field names exactly, ensuring compatibility
///   with the watched_items API schema.
///
/// Usage:
/// - Decode entries from the server to reconstruct a user’s watch history and progress.
/// - Encode entries when marking a movie or episode as watched.
/// - Combine with `MediaItem`, `Season`, and `Episode` models to compute progress (e.g., watched counts).
struct watchedItem: Identifiable, Hashable, Codable {
    var id = UUID()
    let tmdb_id: Int?
    var media_type: String?
    let season_number: Int?
    let episode_number: Int?
    
    var user_id: UUID?
    var created_at: String?
    var show_id: Int?
    
    enum CodingKeys: String, CodingKey {
        case tmdb_id
        case media_type
        case season_number
        case episode_number
        case user_id
        case created_at
        case show_id
    }
}
