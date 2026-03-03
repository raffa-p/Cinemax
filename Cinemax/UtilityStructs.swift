//
//  UtilityStructs.swift
//  Cinemax
//
//  Created by Raffaele Prota on 02/03/26.
//

import Foundation

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
            guard type == .series else { return false }
            return watchedEpisodes > 0 && watchedEpisodes < totalEpisodes
        }
    
    var seasons: [Season] = []
    
    // Helper per ottenere l'episodio corrente
    var totalEpisodes: Int {
        seasons.reduce(0) { $0 + $1.episodes.count }
    }
    
    var watchedEpisodes: Int {
        seasons.reduce(0) { seasonCount, season in
            seasonCount + season.episodes.filter { $0.isWatched }.count
        }
    }
}

struct watchingItem: Identifiable, Hashable, Codable{
    var id = UUID()
    let tmdbId: Int?
    let user: UUID?
}

/// Describes rows of table PersonalList(id, user_id,tmdb_id,media_type,season_number,episode_number,created_at,show_id)
struct personalListItem: Identifiable, Hashable, Codable{
    var id = UUID()
    let created_at: String?
    let user_id: UUID?
    let tmdb_id: Int?
    let media_type: String?
    let episode_number: Int?
    let season_number: Int?
}

struct watchedItem: Identifiable, Hashable, Codable{
    var id: UUID?
    var user_id = UUID()
    let tmdb_id: Int?
    var media_type: String?
    let season_number: Int?
    let episode_number: Int?
}
