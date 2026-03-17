//
//  LibraryViewModel.swift
//  Cinemax
//
//


import Observation
import Foundation
import Supabase

// MARK: - 1. LibraryViewModel
@Observable
class LibraryViewModel {
    let apiSupabase = SupabaseInterface()
    var viewTrendings: [MediaItem] = []
    var heroMovie: MediaItem?
    var generalCacheContents: [MediaItem] = []
    
    var keepWatching: [MediaItem] = []
    var personalList: [MediaItem] = []
    var watchedItems: [MediaItem] = []
    
    // Set per le ricerche rapide in memoria
    var watchedSet: Set<String> = []
    var personalListSet: Set<String> = []
    
    init() {
        Task {
            await loadUserHistory()
            await viewWatchingMethod()
            await viewPersonalList()
            await viewTrendingsMethod()
            await syncAllData()
        }
    }
    
    func viewPersonalList() async {
        do {
            let temp = try await apiSupabase.loadPersonalList()
            await MainActor.run {
                self.generalCacheContents.append(contentsOf: temp)
                self.personalList = temp
            }
        } catch { print("Errore recupero personal list: \(error)") }
    }
    
    func viewWatchingMethod() async {
        do {
            let temp = try await apiSupabase.loadWatching()
            var enrichedTemp: [MediaItem] = []
            
            for item in temp {
                if item.type == .series {
                    let enriched = await loadEpisodes(for: item)
                    
                    let isFullyWatched = enriched.totalEpisodes > 0 && enriched.watchedEpisodes == enriched.totalEpisodes
                    let hasZeroWatched = enriched.watchedEpisodes == 0
                    
                    if isFullyWatched || hasZeroWatched {
                        
                        if let tmdbId = enriched.tmdbId {
                            Task {
                                do {
                                    try await SupabaseManager.shared.client.from("keepWatching")
                                        .delete().eq("tmdb_id", value: tmdbId).execute()
                                    print("Pulizia zombie eseguita per ID: \(tmdbId)")
                                } catch {
                                    print("Errore pulizia zombie: \(error)")
                                }
                                
                                if isFullyWatched {
                                    let seriesLog = watchedItem(tmdb_id: tmdbId, media_type: "Serie TV", season_number: nil, episode_number: nil)
                                    do{
                                        try await SupabaseManager.shared.client.from("watched_items").insert(seriesLog).execute()
                                    } catch{
                                        print("Errore inserimento in watched_items: \(error)")
                                    }
                                }
                            }
                        }
                    } else {
                        enrichedTemp.append(enriched)
                    }
                } else {
                    let enriched = await loadMovieDuration(for: item)
                    enrichedTemp.append(enriched)
                }
            }
            
            await MainActor.run {
                self.generalCacheContents.append(contentsOf: enrichedTemp)
                self.keepWatching = enrichedTemp
            }
        } catch {
            print("Errore recupero continua a guardare: \(error)")
        }
    }
    
    func viewTrendingsMethod() async {
        do {
            let temp = try await apiSupabase.loadTrendings()
            await MainActor.run {
                self.generalCacheContents.append(contentsOf: temp)
                self.viewTrendings = temp
                self.heroMovie = temp.first
            }
        } catch { print("Errore recupero trendings: \(error)") }
    }

    func loadUserHistory() async {
        do {
            let history: [watchedItem] = try await SupabaseManager.shared.client
                .from("watched_items")
                .select()
                .execute()
                .value
            
            var newWatchedSet = Set<String>()
            
            for log in history {
                if let tmdbId = log.tmdb_id {
                    let key = generateKey(id: tmdbId, season: log.season_number, episode: log.episode_number)
                    newWatchedSet.insert(key)
                }
            }
            
            await MainActor.run {
                self.watchedSet = newWatchedSet
            }
            print("Storico caricato: \(newWatchedSet.count) elementi visti trovati.")
            
        } catch {
            print("Errore caricamento storico visti: \(error)")
        }
    }
    
    private func generateKey(id: Int, season: Int?, episode: Int?) -> String {
        if let s = season, let e = episode { return "episode_\(id)_S\(s)_E\(e)" }
        return "movie_\(id)"
    }
    
    func toggleItemWatched(itemId: UUID) {
        guard let index = generalCacheContents.firstIndex(where: { $0.id == itemId }),
              let tmdbId = generalCacheContents[index].tmdbId else { return }
        
        generalCacheContents[index].isWatched.toggle()
        if heroMovie?.id == itemId { heroMovie?.isWatched = generalCacheContents[index].isWatched }
        let isNowWatched = generalCacheContents[index].isWatched
        let key = generateKey(id: tmdbId, season: nil, episode: nil)
        
        Task {
            do {
                if isNowWatched {
                    let log = watchedItem(tmdb_id: tmdbId, media_type: "movie", season_number: nil, episode_number: nil)
                    try await SupabaseManager.shared.client.from("watched_items").insert(log).execute()
                    watchedSet.insert(key)
                } else {
                    try await SupabaseManager.shared.client.from("watched_items").delete()
                        .eq("tmdb_id", value: tmdbId).eq("media_type", value: "movie").execute()
                    watchedSet.remove(key)
                }
            } catch { print("Errore aggiornamento flag visto: \(error)") }
        }
    }
    
    func toggleInMyList(itemId: UUID) {
            guard let originalItem = generalCacheContents.first(where: { $0.id == itemId }),
                  let tmdbId = originalItem.tmdbId else { return }
            
            let newState = !originalItem.inMyList
            let mediaTypeStr = originalItem.type.rawValue
            
            for i in generalCacheContents.indices where generalCacheContents[i].tmdbId == tmdbId {
                generalCacheContents[i].inMyList = newState
            }
            for i in viewTrendings.indices where viewTrendings[i].tmdbId == tmdbId {
                viewTrendings[i].inMyList = newState
            }
            for i in keepWatching.indices where keepWatching[i].tmdbId == tmdbId {
                keepWatching[i].inMyList = newState
            }
            
            // Updating "La tua lista"
            if newState {
                if let bestCopy = keepWatching.first(where: { $0.tmdbId == tmdbId }) ?? generalCacheContents.first(where: { $0.tmdbId == tmdbId }) {
                    personalList.insert(bestCopy, at: 0)
                }
            } else {
                personalList.removeAll(where: { $0.tmdbId == tmdbId })
            }
            
            if heroMovie?.tmdbId == tmdbId { heroMovie?.inMyList = newState }
            
            // Update DB
            Task {
                do {
                    if newState {
                        let log = personalListItem(tmdb_id: tmdbId, media_type: mediaTypeStr)
                        try await SupabaseManager.shared.client.from("PersonalList").insert(log).execute()
                        personalListSet.insert("content_\(tmdbId)")
                    } else {
                        try await SupabaseManager.shared.client.from("PersonalList").delete()
                            .eq("tmdb_id", value: tmdbId)
                            .eq("media_type", value: mediaTypeStr).execute()
                        personalListSet.remove("\(mediaTypeStr)_\(tmdbId)")
                    }
                } catch { print("Errore aggiunta in lista: \(error)") }
            }
        }
    
    func toggleEpisodeWatched(itemId: UUID, seasonId: UUID, episodeId: UUID) {
            guard let itemIndex = generalCacheContents.firstIndex(where: { $0.id == itemId }),
                  let seasonIndex = generalCacheContents[itemIndex].seasons.firstIndex(where: { $0.id == seasonId }),
                  let episodeIndex = generalCacheContents[itemIndex].seasons[seasonIndex].episodes.firstIndex(where: { $0.id == episodeId }),
                  let tmdbSeriesId = generalCacheContents[itemIndex].tmdbId else { return }
            
            let seasonNum = generalCacheContents[itemIndex].seasons[seasonIndex].number
            let episodeNum = generalCacheContents[itemIndex].seasons[seasonIndex].episodes[episodeIndex].number
            
            let isNowWatched = !generalCacheContents[itemIndex].seasons[seasonIndex].episodes[episodeIndex].isWatched
            let key = generateKey(id: tmdbSeriesId, season: seasonNum, episode: episodeNum)
            
            if isNowWatched {
                watchedSet.insert(key)
            } else {
                watchedSet.remove(key)
            }
            
            
            func updateEpisodes(in array: inout [MediaItem]) {
                for i in array.indices where array[i].tmdbId == tmdbSeriesId {
                    if let sIdx = array[i].seasons.firstIndex(where: { $0.number == seasonNum }),
                       let eIdx = array[i].seasons[sIdx].episodes.firstIndex(where: { $0.number == episodeNum }) {
                        array[i].seasons[sIdx].episodes[eIdx].isWatched = isNowWatched
                    }
                }
            }
            
            updateEpisodes(in: &generalCacheContents)
            updateEpisodes(in: &keepWatching)
            updateEpisodes(in: &personalList)
            updateEpisodes(in: &viewTrendings)
            
            if heroMovie?.tmdbId == tmdbSeriesId {
                if let sIdx = heroMovie?.seasons.firstIndex(where: { $0.number == seasonNum }),
                   let eIdx = heroMovie?.seasons[sIdx].episodes.firstIndex(where: { $0.number == episodeNum }) {
                    heroMovie?.seasons[sIdx].episodes[eIdx].isWatched = isNowWatched
                }
            }
            
            guard let updatedItemIndex = generalCacheContents.firstIndex(where: { $0.tmdbId == tmdbSeriesId }) else { return }
            let updatedMediaItem = generalCacheContents[updatedItemIndex]
            
            let isFullyWatched = updatedMediaItem.watchedEpisodes == updatedMediaItem.totalEpisodes
            let isInProgress = updatedMediaItem.watchedEpisodes > 0 && !isFullyWatched
            
            // Managing "CONTINUA A GUARDARE"
            if isInProgress {
                if let localIndex = keepWatching.firstIndex(where: { $0.tmdbId == tmdbSeriesId }) {
                    keepWatching[localIndex] = updatedMediaItem // Aggiorna barra progresso
                } else {
                    keepWatching.insert(updatedMediaItem, at: 0) // Aggiunge alla riga
                }
            } else {
                keepWatching.removeAll(where: { $0.tmdbId == tmdbSeriesId })
            }
            
            // Updating DB
            Task {
                do {
                    if isNowWatched {
                        let log = watchedItem(tmdb_id: tmdbSeriesId, media_type: "episode", season_number: seasonNum, episode_number: episodeNum)
                        try await SupabaseManager.shared.client.from("watched_items").insert(log).execute()
                    } else {
                        try await SupabaseManager.shared.client.from("watched_items").delete()
                            .eq("tmdb_id", value: tmdbSeriesId).eq("media_type", value: "episode")
                            .eq("season_number", value: seasonNum).eq("episode_number", value: episodeNum).execute()
                    }
                    
                    struct KeepWatchInsert: Codable { let tmdb_id: Int }
                    
                    if isFullyWatched {
                        do {
                            try await SupabaseManager.shared.client.from("keepWatching").delete()
                                .eq("tmdb_id", value: tmdbSeriesId).execute()
                            print("Serie completata: cancellata da keepWatching!")
                        } catch { print("Errore delete keepWatching: \(error)") }
                        
                        let seriesLog = watchedItem(tmdb_id: tmdbSeriesId, media_type: "Serie TV", season_number: nil, episode_number: nil)
                        do{
                            try await SupabaseManager.shared.client.from("watched_items").insert(seriesLog).execute()
                        } catch{
                            print("Errore inserimento in watched_items: \(error)")
                        }
                        
                    } else if isInProgress {
                        do{
                            try await SupabaseManager.shared.client.from("keepWatching").delete()
                            .eq("tmdb_id", value: tmdbSeriesId).execute()
                        } catch{
                            print("Errore inserimento SERIE TV in keepWatching: \(error)")
                        }
                        
                        let keepLog = KeepWatchInsert(tmdb_id: tmdbSeriesId)
                        try await SupabaseManager.shared.client.from("keepWatching").insert(keepLog).execute()
                        
                        do{
                            try await SupabaseManager.shared.client.from("watched_items").delete()
                            .eq("tmdb_id", value: tmdbSeriesId).eq("media_type", value: "Serie TV").execute()
                        } catch{
                            print("Errore rimozione SERIE TV da watched_items: \(error)")
                        }
                        
                    } else {
                        do{
                            try await SupabaseManager.shared.client.from("keepWatching").delete()
                            .eq("tmdb_id", value: tmdbSeriesId).execute()
                        } catch{
                            print("Errore rimozione SERIE TV da keepWatching: \(error)")
                        }
                        do{
                            try await SupabaseManager.shared.client.from("watched_items").delete()
                            .eq("tmdb_id", value: tmdbSeriesId).eq("media_type", value: "Serie TV").execute()
                        } catch{
                            print("Errore rimozione SERIE TV da watched_items: \(error)")
                        }
                    }
                } catch { print("Errore salvataggio Supabase: \(error)") }
            }
        }
    
    // MARK: - DOWNLOAD DETAILS
        
        @discardableResult
        func loadEpisodes(for item: MediaItem) async -> MediaItem {
            guard item.type == .series, item.seasons.isEmpty, let tmdbId = item.tmdbId else { return item }
            
            var updatedItem = item
            
            do {
                let details = try await MovieService.shared.fetchShowDetails(id: tmdbId)
                var newSeasons: [Season] = []
                
                for seasonMeta in details.seasons ?? [] where seasonMeta.seasonNumber > 0 {
                    let episodes = try await MovieService.shared.fetchSeasonEpisodes(showId: tmdbId, seasonNumber: seasonMeta.seasonNumber)
                    
                    let convertedEpisodes = episodes.map { ep in
                        let key = generateKey(id: tmdbId, season: seasonMeta.seasonNumber, episode: ep.episodeNumber)
                        return Episode(
                            number: ep.episodeNumber,
                            title: ep.name,
                            duration: "\(ep.runtime ?? 30)m",
                            plot: ep.overview.isEmpty ? "Nessuna trama." : ep.overview,
                            imageURL: ep.stillPath != nil ? URL(string: "https://image.tmdb.org/t/p/w300\(ep.stillPath!)") : nil,
                            isWatched: watchedSet.contains(key),
                            show_id: ep.showId
                        )
                    }
                    newSeasons.append(Season(number: seasonMeta.seasonNumber, episodes: convertedEpisodes))
                }
                
                updatedItem.seasons = newSeasons
                
                // Updating cache
                await MainActor.run {
                    for i in self.generalCacheContents.indices where self.generalCacheContents[i].tmdbId == tmdbId {
                        self.generalCacheContents[i].seasons = newSeasons
                    }
                    for i in self.keepWatching.indices where self.keepWatching[i].tmdbId == tmdbId {
                        self.keepWatching[i].seasons = newSeasons
                    }
                    for i in self.personalList.indices where self.personalList[i].tmdbId == tmdbId {
                        self.personalList[i].seasons = newSeasons
                    }
                    for i in self.viewTrendings.indices where self.viewTrendings[i].tmdbId == tmdbId {
                        self.viewTrendings[i].seasons = newSeasons
                    }
                }
            } catch {
                print("Errore caricamento episodi: \(error)")
            }
            
            return updatedItem
        }

        @discardableResult
        func loadMovieDuration(for item: MediaItem) async -> MediaItem {
            guard item.type == .movie, item.duration == nil, let tmdbId = item.tmdbId else { return item }
            
            var updatedItem = item
            do {
                let details = try await MovieService.shared.fetchMovieDetails(id: tmdbId)
                if let minutes = details.runtime, minutes > 0 {
                    let hours = minutes / 60
                    let mins = minutes % 60
                    updatedItem.duration = "\(hours)h \(mins)m"
                    
                    await MainActor.run {
                        if let index = generalCacheContents.firstIndex(where: { $0.id == item.id }) {
                            generalCacheContents[index] = updatedItem
                        }
                    }
                }
            } catch { print("Errore durata film: \(error)") }
            
            return updatedItem
        }
    
    // MARK: - Sincronizzazione Universale
    func syncAllData() async {
        await MainActor.run {
            let personalIds = Set(self.personalList.compactMap { $0.tmdbId })
            
            // Sync Trendings
            for i in self.viewTrendings.indices {
                if let id = self.viewTrendings[i].tmdbId {
                    self.viewTrendings[i].inMyList = personalIds.contains(id)
                    
                    if self.viewTrendings[i].type == .movie {
                        let key = generateKey(id: id, season: nil, episode: nil)
                        self.viewTrendings[i].isWatched = self.watchedSet.contains(key)
                    }
                }
            }
            
            // Sync Continua a Guardare
            for i in self.keepWatching.indices {
                if let id = self.keepWatching[i].tmdbId {
                    self.keepWatching[i].inMyList = personalIds.contains(id)
                }
            }
            
            // Sync cache
            for i in self.generalCacheContents.indices {
                if let id = self.generalCacheContents[i].tmdbId {
                    self.generalCacheContents[i].inMyList = personalIds.contains(id)
                    
                    if self.generalCacheContents[i].type == .movie {
                        let key = generateKey(id: id, season: nil, episode: nil)
                        self.generalCacheContents[i].isWatched = self.watchedSet.contains(key)
                    }
                }
            }
            
            // Sync Hero Movie
            if let heroId = self.heroMovie?.tmdbId {
                self.heroMovie?.inMyList = personalIds.contains(heroId)
                if self.heroMovie?.type == .movie {
                    let key = generateKey(id: heroId, season: nil, episode: nil)
                    self.heroMovie?.isWatched = self.watchedSet.contains(key)
                }
            }
            
            print("Sincronizzazione iniziale completata")
        }
    }
}
