//
//  MovieService.swift
//  Cinemax
//
//

import Foundation

/// `MovieService` is a singleton class responsible for making API requests to The Movie Database (TMDB)
/// to fetch various movie and TV show data. It provides methods for fetching trending items, searching
/// for media, and retrieving detailed information about movies, TV shows, and their episodes.
///
/// It uses a shared `URLSession` for network requests and `JSONDecoder` for decoding responses.
/// The `apiKey` is retrieved from a global `config` object.
class MovieService {
    static let shared = MovieService()
    private let apiKey = config.apiKey
    
    /// Fetches a list of trending movies and TV shows for the current week.
    /// - Returns: An array of `TMDBItem` representing the trending media.
    /// - Throws: `URLError` if the URL is invalid, or `DecodingError` if the response
    ///   data cannot be decoded into `TMDBResponse`.
    func fetchTrending() async throws -> [TMDBItem] {
        let urlString = "https://api.themoviedb.org/3/trending/all/week?api_key=\(apiKey)&language=it-IT"
        guard let url = URL(string: urlString) else { return [] }
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(TMDBResponse.self, from: data)
        return response.results
    }
    
    /// Searches for movies and TV shows based on a given query string.
    /// This method is an older version; `searchMedia(query:)` is preferred for filtering out persons.
    /// - Parameter query: The search query string.
    /// - Returns: An array of `TMDBItem` matching the search query.
    /// - Throws: `URLError` if the URL is invalid (e.g., query encoding fails), or `DecodingError`
    ///   if the response data cannot be decoded into `TMDBResponse`.
    func search(query: String) async throws -> [TMDBItem] {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "https://api.themoviedb.org/3/search/multi?api_key=\(apiKey)&language=it-IT&query=\(encodedQuery)"
        guard let url = URL(string: urlString) else { return [] }
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(TMDBResponse.self, from: data)
        return response.results
    }
    
    /// Fetches detailed information for a specific TV show.
    /// - Parameter id: The unique identifier of the TV show.
    /// - Returns: A `TMDBItem` containing the detailed information of the TV show.
    /// - Throws: `URLError.badURL` if the URL cannot be constructed, or `DecodingError`
    ///   if the response data cannot be decoded into `TMDBItem`.
    func fetchShowDetails(id: Int) async throws -> TMDBItem {
        let urlString = "https://api.themoviedb.org/3/tv/\(id)?api_key=\(apiKey)&language=it-IT"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(TMDBItem.self, from: data)
    }
    
    /// Fetches the episodes for a specific season of a TV show.
    /// - Parameters:
    ///   - showId: The unique identifier of the TV show.
    ///   - seasonNumber: The season number for which to fetch episodes.
    /// - Returns: An array of `TMDBEpisode` for the specified season.
    /// - Throws: `URLError.badURL` if the URL cannot be constructed, or `DecodingError`
    ///   if the response data cannot be decoded, or if the `episodes` property of the decoded `TMDBItem` is `nil`.
    func fetchSeasonEpisodes(showId: Int, seasonNumber: Int) async throws -> [TMDBEpisode] {
        let urlString = "https://api.themoviedb.org/3/tv/\(showId)/season/\(seasonNumber)?api_key=\(apiKey)&language=it-IT"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(TMDBItem.self, from: data).episodes!
    }

    /// Fetches detailed information for a specific movie.
    /// - Parameter id: The unique identifier of the movie.
    /// - Returns: A `TMDBItem` containing the detailed information of the movie.
    /// - Throws: `URLError.badURL` if the URL cannot be constructed, or `DecodingError`
    ///   if the response data cannot be decoded into `TMDBItem`.
    func fetchMovieDetails(id: Int) async throws -> TMDBItem {
        let urlString = "https://api.themoviedb.org/3/movie/\(id)?api_key=\(apiKey)&language=it-IT"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(TMDBItem.self, from: data)
    }

    /// Searches for movies and TV shows based on a given query string, excluding results for "person" media types.
    /// This is the preferred search method.
    /// - Parameter query: The search query string.
    /// - Returns: An array of `TMDBItem` matching the search query, excluding persons.
    /// - Throws: `URLError.badURL` if the URL cannot be constructed (e.g., query encoding fails),
    ///   or `DecodingError` if the response data cannot be decoded into `TMDBResponse`.
    func searchMedia(query: String) async throws -> [TMDBItem] {
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw URLError(.badURL)
        }
        let urlString = "https://api.themoviedb.org/3/search/multi?api_key=\(apiKey)&language=it-IT&query=\(encodedQuery)&include_adult=false"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        let (data, _) = try await URLSession.shared.data(from: url)
        let decodedResponse = try JSONDecoder().decode(TMDBResponse.self, from: data)
        return decodedResponse.results.filter { $0.mediaType != "person" }
    }
    
    /// Fetches detailed information for a specific media item (movie or TV show).
    /// - Parameters:
    ///   - id: The unique identifier of the media item.
    ///   - type: The type of media, either "movie" or "tv".
    /// - Returns: A `TMDBItem` containing the detailed information of the media item.
    /// - Throws: `URLError.badURL` if the URL cannot be constructed, or `DecodingError`
    ///   if the response data cannot be decoded into `TMDBItem`.
    func fetchMediaDetails(id: Int, type: String) async throws -> TMDBItem {
        let endpoint = (type == "movie") ? "movie" : "tv"
        let urlString = "https://api.themoviedb.org/3/\(endpoint)/\(id)?api_key=\(apiKey)&language=it-IT"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(TMDBItem.self, from: data)
    }
}
