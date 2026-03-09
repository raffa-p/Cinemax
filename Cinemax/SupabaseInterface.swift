//
//  SupabaseInterface.swift
//  Cinemax
//
//  Created by Raffaele Prota on 02/03/26.
//

import Foundation
import SwiftUI
import Supabase

class SupabaseInterface {
    public var cacheWatching: [MediaItem]?
    public var cacheList: [MediaItem]?
    
    /// Utility function to make easier the comunication with API
    /// Downloads the trending contents for Italy
    /// - Returns: array of MediaItem
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
    
    /// Utility function to make easier the comunication with DB and API
    /// Downloads all elements from table keepWatching in DB
    /// Retrieve also additional information (seasons, episodes, ecc) from API
    /// - Returns: Array of MediaItem containing elements from keepWatching table with all details
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
    
    /// Utility function to make easier the comunication with DB and API
    /// Downloads all elements from table PersonalList in DB
    /// Retrieve also additional information (seasons, episodes, ecc) from API
    /// - Returns: Array of MediaItem containing elements from PersonalList table with all details
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
