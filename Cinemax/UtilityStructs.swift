//
//  UtilityStructs.swift
//  Cinemax
//
//

import Foundation

// Structs to describe tv series/film
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

struct Season: Identifiable, Hashable {
    let id = UUID()
    let number: Int
    var episodes: [Episode]
}

enum MediaType: String, CaseIterable {
    case movie = "Film"
    case series = "Serie TV"
}

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
        guard type == .series else { return false } // a film can be only watched or not. Will not store info about the remaining time
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

// corrisponds to keepWatching on DB
struct watchingItem: Identifiable, Hashable, Codable {
    var id = UUID()
    let tmdb_id: Int?
    let user: UUID?
    
    enum CodingKeys: String, CodingKey {
        case tmdb_id = "tmdb_id"
        case user
    }
}

// corrisponds to personalList on DB
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

// corrisponds to watched_items on DB
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
