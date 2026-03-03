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
                do {
                    let tvDetails = try await MovieService.shared.fetchShowDetails(id: entry.tmdbId!)
                    
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
                    print("Errore scaricamento TMDB per ID \(String(describing: entry.tmdbId)): \(error)")
                }
            }
            
            return detailedList
            
        } catch {
            print("Errore caricamento Continua a Guardare da Supabase: \(error)")
            return []
        }
    }
    
    func loadPersonalList() async throws -> [MediaItem] {
        do{
            let entries: [personalListItem] = try await SupabaseManager.shared.client
                .from("PersonalList")
                .select()
                .execute()
                .value

            var detailedList: [MediaItem] = []

            // download details
            for entry in entries {
                do {
                    if(entry.media_type == "Serie TV"){
                        let tvDetails = try await MovieService.shared.fetchShowDetails(id: entry.tmdb_id!)
                        
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
                    }
                    else{
                        let movieDetails = try await MovieService.shared.fetchMovieDetails(id: entry.tmdb_id!)
                        
                        let item = MediaItem(
                            tmdbId: movieDetails.id,
                            title: movieDetails.name ?? movieDetails.title ?? "Sconosciuto",
                            imageName: movieDetails.fullPosterURL?.absoluteString ?? "",
                            type: .movie,
                            matchPercentage: Int((movieDetails.voteAverage ?? 0) * 10),
                            year: String((movieDetails.displayYear).prefix(4)),
                            description: movieDetails.overview ?? "Nessuna trama disponibile",
                            isWatched: false,
                            seasons: []
                        )
                        detailedList.append(item)
                    }
                    
                } catch {
                    print("Errore scaricamento TMDB per ID \(String(describing: entry.id)): \(error)")
                }
            }
            return detailedList
        }
        catch {
            print("Errore caricamento lista personale")
            return []
        }
    }
}
