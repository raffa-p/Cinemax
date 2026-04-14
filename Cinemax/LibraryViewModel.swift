//
//  LibraryViewModel.swift
//  Cinemax
//
//


import Observation
import Foundation
import Supabase

// MARK: - 1. LibraryViewModel
/// `LibraryViewModel` manages the data and business logic for the main library view of the Cinemax application.
/// It handles fetching trending media, user's "Continue Watching" list, personal list, and watched history from Supabase,
/// as well as updating the watch status and personal list status of media items.
///
/// This view model is an `@Observable` class, making its properties suitable for SwiftUI views to react to changes.
@Observable
class LibraryViewModel {
    let apiSupabase = SupabaseInterface()
    var viewTrendings: [MediaItem] = []
    var heroMovie: MediaItem?
    var generalCacheContents: [MediaItem] = []
    
    var keepWatching: [MediaItem] = []
    var personalList: [MediaItem] = []
    var watchedItems: [MediaItem] = []
    var history: [MediaItem] = []
    
    // Set per le ricerche rapide in memoria
    var watchedSet: Set<String> = []
    var personalListSet: Set<String> = []
    
    // Gestione episodi precedenti visti in automatico
    var showCatchUpAlert: Bool = false
    var pendingEpisodeData: (itemId: UUID, seasonId: UUID, episodeId: UUID)? = nil
    
    init() {
        Task {
            await loadUserHistory()
            await viewWatchingMethod()
            await viewPersonalList()
            await viewTrendingsMethod()
            await syncAllData()
        }
    }
    
    /// Asynchronously loads the user's personal list from Supabase and updates the `personalList` property
    /// and `generalCacheContents`.
    func viewPersonalList() async {
        do {
            let temp = try await apiSupabase.loadPersonalList()
            await MainActor.run {
                self.generalCacheContents.append(contentsOf: temp)
                self.personalList = temp
            }
        } catch { print("Errore recupero personal list: \(error)") }
    }
    
    /// Asynchronously loads media items the user is currently watching from Supabase.
    /// Enriches series with episode details and movies with duration if not already present.
    func viewWatchingMethod() async {
        do {
            let temp = try await apiSupabase.loadWatching()
            var enrichedTemp: [MediaItem] = []
            
            for item in temp {
                if item.type == .series {
                    let enriched = await loadEpisodes(for: item)
                    
                    let isFullyWatched = enriched.totalEpisodes > 0 && enriched.watchedEpisodes == enriched.totalEpisodes
                    let hasZeroWatched = enriched.watchedEpisodes == 0
                    
                    if !isFullyWatched && !hasZeroWatched {
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
    
    /// Asynchronously loads trending media items from Supabase and updates the `viewTrendings` property.
    /// The first item in the trendings list is also set as the `heroMovie`.
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

    /// Asynchronously loads the user's entire watched history from Supabase and populates the `watchedSet`
    /// for quick lookup of watched movies and episodes.
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
    
    /// Generates a unique key string for a given media item or episode to be used in `watchedSet` or `personalListSet`.
    /// - Parameters:
    ///   - id: The TMDB ID of the media item (movie or series).
    ///   - season: The season number for an episode, or `nil` for a movie.
    ///   - episode: The episode number for an episode, or `nil` for a movie.
    /// - Returns: A string key in the format "episode_ID_S_E" for episodes or "movie_ID" for movies.
    private func generateKey(id: Int, season: Int?, episode: Int?) -> String {
        if let s = season, let e = episode { return "episode_\(id)_S\(s)_E\(e)" }
        return "movie_\(id)"
    }
    
    /// Toggles the watched status of a movie identified by its `itemId`.
    /// Updates the `isWatched` property in `generalCacheContents` and `heroMovie` (if applicable),
    /// and persists the change to the Supabase "watched_items" table.
    /// Also updates the `watchedSet`.
    /// - Parameter itemId: The `UUID` of the `MediaItem` to toggle.
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
                    try await SupabaseManager.shared.client.from("fullyWatched").insert(log).execute()
                    watchedSet.insert(key)
                } else {
                    try await SupabaseManager.shared.client.from("fullyWatched").delete()
                        .eq("tmdb_id", value: tmdbId).eq("media_type", value: "movie").execute()
                    watchedSet.remove(key)
                }
            } catch { print("Errore aggiornamento flag visto: \(error)") }
        }
    }
    
    /// Toggles whether a media item (movie or series) is in the user's personal list.
    /// Updates the `inMyList` property across `generalCacheContents`, `viewTrendings`, `keepWatching`,
    /// and `heroMovie` (if applicable). It also modifies the `personalList` array and persists the change
    /// to the Supabase "PersonalList" table, updating `personalListSet`.
    /// - Parameter itemId: The `UUID` of the `MediaItem` to toggle.
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
                let log = personalListItem(tmdb_id: tmdbId, media_type: mediaTypeStr)
                if newState {
                    try await SupabaseManager.shared.client.from("PersonalList").insert(log).execute()
                    personalListSet.insert("content_\(tmdbId)")
                    print("Inserito elemento \(log.media_type ?? "") con id \(tmdbId) in PersonalList")
                } else {
                    try await SupabaseManager.shared.client.from("PersonalList").delete().match(["tmdb_id": tmdbId, "media_type": mediaTypeStr]).execute()
                    personalListSet.remove("\(mediaTypeStr)_\(tmdbId)")
                    print("Rimosso elemento \(log.media_type ?? "") con id \(tmdbId) da PersonalList")
                }
            } catch let error as PostgrestError where error.code == "23505" {
                print("L'elemento era già presente in lista")
            } catch {
                let errorString = String(describing: error)
                if errorString.contains("23505") {
                    print("L'elemento era già presente in lista")
                } else {
                    print("Errore aggiunta/rimozione elemento \(tmdbId) da PersonalList: \(error)")
                }
            }
        }
    }
    
    // 1. IL CONTROLLORE
        func toggleEpisodeWatched(itemId: UUID, seasonId: UUID, episodeId: UUID) {
            guard let itemIndex = generalCacheContents.firstIndex(where: { $0.id == itemId }),
                  let seasonIndex = generalCacheContents[itemIndex].seasons.firstIndex(where: { $0.id == seasonId }),
                  let episodeIndex = generalCacheContents[itemIndex].seasons[seasonIndex].episodes.firstIndex(where: { $0.id == episodeId }) else { return }
            
            let item = generalCacheContents[itemIndex]
            let targetSeasonNum = item.seasons[seasonIndex].number
            let targetEpisodeNum = item.seasons[seasonIndex].episodes[episodeIndex].number
            let isNowWatched = !item.seasons[seasonIndex].episodes[episodeIndex].isWatched
            
            // Se stiamo segnando come "Visto", controlliamo i precedenti
            if isNowWatched {
                var hasUnwatchedPrevious = false
                
                for season in item.seasons {
                    if season.number < targetSeasonNum {
                        // Stagioni precedenti: c'è un episodio non visto?
                        if season.episodes.contains(where: { !$0.isWatched }) {
                            hasUnwatchedPrevious = true
                            break
                        }
                    } else if season.number == targetSeasonNum {
                        // Stessa stagione: c'è un episodio precedente non visto?
                        if season.episodes.contains(where: { $0.number < targetEpisodeNum && !$0.isWatched }) {
                            hasUnwatchedPrevious = true
                            break
                        }
                    }
                }
                
                // Se ci sono episodi saltati, blocchiamo tutto e mostriamo l'avviso
                if hasUnwatchedPrevious {
                    self.pendingEpisodeData = (itemId, seasonId, episodeId)
                    self.showCatchUpAlert = true
                    return
                }
            }
            
            // Se tutto è in regola (o stiamo togliendo la spunta), procediamo normalmente
            executeToggleEpisodeWatched(itemId: itemId, seasonId: seasonId, episodeId: episodeId)
        }

        // 2. IL TUO CODICE ORIGINALE (Rinominato)
        func executeToggleEpisodeWatched(itemId: UUID, seasonId: UUID, episodeId: UUID) {
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
                let log = watchedItem(tmdb_id: tmdbSeriesId, media_type: "episode", season_number: seasonNum, episode_number: episodeNum)
                do {
                    if isNowWatched {
                        try await SupabaseManager.shared.client.from("watched_items").insert(log).execute()
                        print("Inserito in WATCHED_ITEMS \(tmdbSeriesId), episodio: \(episodeNum), stagione: \(seasonNum)")
                    }
                    else {
                        try await SupabaseManager.shared.client.from("watched_items").delete().match(["tmdb_id": tmdbSeriesId, "season_number": seasonNum, "episode_number": episodeNum]).execute()
                        print("Rimosso da WATCHED_ITEMS \(tmdbSeriesId), episodio: \(episodeNum), stagione: \(seasonNum)")
                        try await SupabaseManager.shared.client.from("fullyWatched").delete().match(["tmdb_id": tmdbSeriesId]).execute()
                        print("Rimosso da fullyWatched \(tmdbSeriesId)")
                    }
                } catch { print("Errore aggiornamento episodio: \(error)") }
                do{
                    if isInProgress && !isFullyWatched {
                        try await SupabaseManager.shared.client.from("keepWatching").insert(["tmdb_id": tmdbSeriesId]).execute()
                        print("Inserito in keepWatching \(tmdbSeriesId)")
                    }
                    else {
                        try await SupabaseManager.shared.client.from("keepWatching").delete().match(["tmdb_id": tmdbSeriesId]).execute()
                        print("Rimosso da keepWatching \(tmdbSeriesId)")
                        try await SupabaseManager.shared.client.from("fullyWatched").insert(FullyWatchedInsert(tmdb_id: log.tmdb_id!, media_type: "Serie_TV")).execute()
                        print("Inserito in fullyWatched \(tmdbSeriesId)")
                    }
                } catch let error as PostgrestError where error.code == "23505" {
                    print("L'elemento era già presente in keepWatching")
                } catch {
                    let errorString = String(describing: error)
                    if errorString.contains("23505") {
                        print("L'elemento era già presente in keepWatching")
                    } else {
                        print("Errore aggiunta/rimozione elemento \(tmdbSeriesId) da keepWatching: \(error)")
                    }
                }
            }
        }

        // 3. LA FUNZIONE CHE SEGNA TUTTI I PRECEDENTI IN BATCH
        func markEpisodeAndAllPreviousAsWatched() {
            guard let data = pendingEpisodeData,
                  let itemIndex = generalCacheContents.firstIndex(where: { $0.id == data.itemId }),
                  let targetSeasonIndex = generalCacheContents[itemIndex].seasons.firstIndex(where: { $0.id == data.seasonId }),
                  let targetEpisodeIndex = generalCacheContents[itemIndex].seasons[targetSeasonIndex].episodes.firstIndex(where: { $0.id == data.episodeId }),
                  let tmdbSeriesId = generalCacheContents[itemIndex].tmdbId else { return }

            let targetSeasonNum = generalCacheContents[itemIndex].seasons[targetSeasonIndex].number
            let targetEpisodeNum = generalCacheContents[itemIndex].seasons[targetSeasonIndex].episodes[targetEpisodeIndex].number

            var episodesToInsert: [watchedItem] = []

            // 1. Aggiornamento Locale
            for sIdx in generalCacheContents[itemIndex].seasons.indices {
                let sNum = generalCacheContents[itemIndex].seasons[sIdx].number
                
                if sNum <= targetSeasonNum {
                    for eIdx in generalCacheContents[itemIndex].seasons[sIdx].episodes.indices {
                        let eNum = generalCacheContents[itemIndex].seasons[sIdx].episodes[eIdx].number
                        
                        // Selettore: Episodio precedente o uguale a quello cliccato
                        if sNum < targetSeasonNum || (sNum == targetSeasonNum && eNum <= targetEpisodeNum) {
                            if !generalCacheContents[itemIndex].seasons[sIdx].episodes[eIdx].isWatched {
                                
                                // Segna come visto localmente
                                generalCacheContents[itemIndex].seasons[sIdx].episodes[eIdx].isWatched = true
                                let key = generateKey(id: tmdbSeriesId, season: sNum, episode: eNum)
                                watchedSet.insert(key)
                                
                                // Prepara il log per il DB
                                episodesToInsert.append(watchedItem(tmdb_id: tmdbSeriesId, media_type: "episode", season_number: sNum, episode_number: eNum))
                            }
                        }
                    }
                }
            }
            
            // Sincronizza l'item aggiornato nelle altre liste
            let updatedItem = generalCacheContents[itemIndex]
            if let idx = keepWatching.firstIndex(where: { $0.id == data.itemId }) { keepWatching[idx] = updatedItem }
            if let idx = personalList.firstIndex(where: { $0.id == data.itemId }) { personalList[idx] = updatedItem }
            if let idx = viewTrendings.firstIndex(where: { $0.id == data.itemId }) { viewTrendings[idx] = updatedItem }
            if heroMovie?.id == data.itemId { heroMovie = updatedItem }
            
            // 2. Inserimento di massa in Supabase
            Task {
                do {
                    if !episodesToInsert.isEmpty {
                        try await SupabaseManager.shared.client.from("watched_items").insert(episodesToInsert).execute()
                        print("Inseriti \(episodesToInsert.count) episodi precedenti in WATCHED_ITEMS")
                    }
                } catch {
                    print("Errore aggiornamento di massa: \(error)")
                }
                do{
                    let isFullyWatched = updatedItem.watchedEpisodes == updatedItem.totalEpisodes
                    print("Serie \(tmdbSeriesId) conclusa? \(isFullyWatched)")
                    if isFullyWatched {
                        try await SupabaseManager.shared.client.from("fullyWatched").insert(FullyWatchedInsert(tmdb_id: tmdbSeriesId, media_type: "Serie_TV")).execute()
                        try await SupabaseManager.shared.client.from("keepWatching").delete().match(["tmdb_id": tmdbSeriesId]).execute()
                        print("Rimosso da keepWatching \(tmdbSeriesId)")
                    } else {
                        // Forza il riavvio della serie in keep watching
                        try await SupabaseManager.shared.client.from("keepWatching").insert(["tmdb_id": tmdbSeriesId]).execute()
                    }
                } catch { print("Errore aggiornamento serie conclusa: \(error)") }
            }
            
            // Pulisci i dati temporanei
            pendingEpisodeData = nil
        }
    
    // MARK: - DOWNLOAD DETAILS
    /// Asynchronously loads detailed season and episode information for a given series `MediaItem` from an external movie service.
    /// Only loads if the item is a series and its seasons are empty.
    /// Populates the `seasons` property of the `MediaItem` and updates all cached instances of the item.
    /// - Parameter item: The `MediaItem` representing the series.
    /// - Returns: The updated `MediaItem` with season and episode details.
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

    /// Asynchronously loads the duration for a given movie `MediaItem` from an external movie service.
    /// Only loads if the item is a movie and its duration is not already set.
    /// Populates the `duration` property of the `MediaItem` and updates cached instances.
    /// - Parameter item: The `MediaItem` representing the movie.
    /// - Returns: The updated `MediaItem` with duration details.
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
    
    /// Synchronizes the `inMyList` and `isWatched` flags across all `MediaItem` collections
    /// (`viewTrendings`, `keepWatching`, `generalCacheContents`, `heroMovie`)
    /// based on the current state of `personalList` and `watchedSet`.
    /// This method ensures UI consistency after initial data loading.
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
