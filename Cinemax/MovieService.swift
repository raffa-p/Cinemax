//
//  MovieService.swift
//  Cinemax
//
//

import Foundation

class MovieService {
    static let shared = MovieService()
    private let apiKey = config.apiKey
    
    // Funzione generica per scaricare film o serie
    func fetchTrending() async throws -> [TMDBItem] {
        // URL per i trend settimanali (film e serie misti) in italiano
        let urlString = "https://api.themoviedb.org/3/trending/all/week?api_key=\(apiKey)&language=it-IT"
        
        guard let url = URL(string: urlString) else { return [] }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(TMDBResponse.self, from: data)
        
        return response.results
    }
    
    // Funzione per cercare (bonus)
    func search(query: String) async throws -> [TMDBItem] {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "https://api.themoviedb.org/3/search/multi?api_key=\(apiKey)&language=it-IT&query=\(encodedQuery)"
        
        guard let url = URL(string: urlString) else { return [] }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(TMDBResponse.self, from: data)
        return response.results
    }
    // Ottieni i dettagli della serie (per sapere le stagioni)
    func fetchShowDetails(id: Int) async throws -> TMDBItem {
        let urlString = "https://api.themoviedb.org/3/tv/\(id)?api_key=\(apiKey)&language=it-IT"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(TMDBItem.self, from: data)
    }
    
    // Ottieni gli episodi di una specifica stagione
    func fetchSeasonEpisodes(showId: Int, seasonNumber: Int) async throws -> [TMDBEpisode] {
        let urlString = "https://api.themoviedb.org/3/tv/\(showId)/season/\(seasonNumber)?api_key=\(apiKey)&language=it-IT"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(TMDBItem.self, from: data).episodes!
    }

    // Recupera i dettagli del singolo film (durata)
    func fetchMovieDetails(id: Int) async throws -> TMDBItem {
        let urlString = "https://api.themoviedb.org/3/movie/\(id)?api_key=\(apiKey)&language=it-IT"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(TMDBItem.self, from: data)
    }

    func searchMedia(query: String) async throws -> [TMDBItem] {
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw URLError(.badURL)
        }
        
        let urlString = "https://api.themoviedb.org/3/search/multi?api_key=\(apiKey)&language=it-IT&query=\(encodedQuery)&include_adult=false"
        
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        
        // Usiamo lo stesso wrapper TMDBResponse che usiamo per i trending
        let decodedResponse = try JSONDecoder().decode(TMDBResponse.self, from: data)
        
        // Filtriamo via le persone (l'API search/multi restituisce anche attori, ma noi vogliamo solo film/serie)
        return decodedResponse.results.filter { $0.mediaType != "person" }
    }
    
    func fetchMediaDetails(id: Int, type: String) async throws -> TMDBItem {
        let endpoint = (type == "movie") ? "movie" : "tv"
        
        let urlString = "https://api.themoviedb.org/3/\(endpoint)/\(id)?api_key=\(apiKey)&language=it-IT"
        
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        
        return try JSONDecoder().decode(TMDBItem.self, from: data)
    }
}
