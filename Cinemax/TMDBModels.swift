//
//  TMDBModels.swift
//  Cinemax
//
//

import Foundation

// Generic response from DB
struct TMDBResponse: Codable {
    let results: [TMDBItem]
}

// struct to translate info from API
struct TMDBItem: Codable, Identifiable {
    let id: Int
    let title: String?        // only for film
    let name: String?         // only for tv serie
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let voteAverage: Double?
    let releaseDate: String?  // only for film
    let firstAirDate: String? // only for tv serie
    let mediaType: String?
    let seasons: [TMDBSeasonMetadata]? // only for tv serie
    let episodes: [TMDBEpisode]? // only for tv serie
    let runtime: Int? // only for films
    

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

struct TMDBSeasonMetadata: Codable {
    let seasonNumber: Int
    
    enum CodingKeys: String, CodingKey {
        case seasonNumber = "season_number"
    }
}

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
