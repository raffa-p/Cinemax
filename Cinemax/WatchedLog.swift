//
//  WatchedLog.swift
//  Cinemax
//
//  Created by Raffaele Prota on 19/12/25.
//


import Foundation

struct WatchedLog: Codable {
    let tmdbId: Int
    let mediaType: String // "movie" o "episode"
    let seasonNumber: Int?
    let episodeNumber: Int?
    
    enum CodingKeys: String, CodingKey {
        case tmdbId = "tmdb_id"
        case mediaType = "media_type"
        case seasonNumber = "season_number"
        case episodeNumber = "episode_number"
    }
}