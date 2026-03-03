//
//  TMDBModels.swift
//  Cinemax
//
//  Created by Raffaele Prota on 17/12/25.
//

import Foundation

// Risposta generica per le liste (es. Trending, Search)
struct TMDBResponse: Codable {
    let results: [TMDBItem]
}

// Il singolo film/serie come arriva dall'API
struct TMDBItem: Codable, Identifiable {
    let id: Int
    let title: String?        // I film hanno 'title'
    let name: String?         // Le serie hanno 'name'
    let overview: String?
    let posterPath: String?   // es: "/abc1234.jpg"
    let backdropPath: String? // Immagine grande orizzontale
    let voteAverage: Double?
    let releaseDate: String?  // Film
    let firstAirDate: String? // Serie
    let mediaType: String?
    
    // MARK: SERIE
    let seasons: [TMDBSeasonMetadata]?
    let episodes: [TMDBEpisode]?
    
    // MARK: MOVIE
    let runtime: Int? // Durata in minuti
    
    // Mappatura dei nomi JSON ai nomi Swift
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
        
        // Rimuove eventuali slash iniziali doppi o singoli per evitare //abc.jpg
        let cleanPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        
        return URL(string: "https://image.tmdb.org/t/p/w500/\(cleanPath)")
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
