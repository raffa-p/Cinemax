//
//  ContentView.swift
//  Cinemax
//
//  Created by Raffaele Prota on 17/12/25.
//

import SwiftUI
import Observation
import Foundation
import Supabase

// MARK: - 1. MODELS COMPLESSI

struct Episode: Identifiable, Hashable {
    let id = UUID()
    let number: Int
    let title: String
    let duration: String
    let plot: String
    let imageURL: URL?
    var isWatched: Bool = false
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
    
    // Helper per ottenere l'episodio corrente o statistiche
    var totalEpisodes: Int {
        seasons.reduce(0) { $0 + $1.episodes.count }
    }
    
    var watchedEpisodes: Int {
        seasons.reduce(0) { seasonCount, season in
            seasonCount + season.episodes.filter { $0.isWatched }.count
        }
    }
}

// MARK: - 3. VIEWMODEL

@Observable
class LibraryViewModel {
    var items: [MediaItem] = []
    var heroMovie: MediaItem?
    
    var trendingMedia: [MediaItem] { items }
    
    // Filtro: Serie iniziate (almeno 1 episodio visto, ma non tutti)
    var keepWatching: [MediaItem] {
        return items.filter { item in
            if item.type == .series {
                return item.isInProgress
            } else {
                return false // O true se vuoi includere anche i film visti
            }
        }
    }
    
    var personalList_: [MediaItem] {
        return items.filter { $0.inMyList }
    }
    
    // Cache locale degli ID visti
    private var watchedSet: Set<String> = []
    private var personalListSet: Set<String> = []
    
    init() {
            Task {
                // 1. Scarichiamo Storico e Lista Personale in parallelo
                // Usiamo async let per farli partire insieme e risparmiare tempo
                async let historyTask: () = fetchUserHistory()
                async let listTask: () = fetchUserPersonalList()
                
                _ = await (historyTask, listTask)
                
                // 2. Ora scarichiamo i contenuti (Trending/Popular)
                await loadRealDataAndEnrich()
            }
        }
    
    // MARK: - CARICAMENTO MASSIVO (EAGER LOADING)
    func fetchUserPersonalList() async {
        do {
            // Chiamata a Supabase
            let entries: [PersonalListEntry] = try await SupabaseManager.shared.client
                .from("PersonalList")
                .select()
                .execute()
                .value
            
            // Aggiorniamo il Set locale
            self.personalListSet = Set(entries.map { "\($0.mediaType)_\($0.tmdbId)" })
            
            print("Lista personale caricata: \(self.personalListSet.count) elementi")
            
        } catch {
            print("Errore fetch PersonalList: \(error)")
        }
    }
    
    func fetchMissingPersonalListItems() async {
        let loadedIds = Set(items.compactMap { item -> String? in
            guard let id = item.tmdbId else { return nil }
            return "\(item.type.rawValue)_\(id)"
        })
        
        let missingKeys = personalListSet.subtracting(loadedIds)
        
        guard !missingKeys.isEmpty else { return }
        print("Recupero \(missingKeys.count) elementi della lista personale non presenti in home...")
        
        // 3. Scarichiamo i dati mancanti in parallelo
        await withTaskGroup(of: MediaItem?.self) { group in
            for key in missingKeys {
                group.addTask {
                    let components = key.components(separatedBy: "_")
                    guard components.count == 2,
                          let id = Int(components[1]) else { return nil }
                    let typeRaw = components[0] // "movie" o "tv"
                    
                    do {
                        
                        let tmdbItem = try await MovieService.shared.fetchMediaDetails(id: id, type: typeRaw)
                            
                        
                        var newItem = MediaItem(
                            tmdbId: tmdbItem.id,
                            title: tmdbItem.displayTitle,
                            imageName: tmdbItem.fullPosterURL?.absoluteString ?? "",
                            type: typeRaw == "movie" ? .movie : .series,
                            matchPercentage: Int((tmdbItem.voteAverage ?? 0) * 10),
                            year: tmdbItem.displayYear,
                            description: tmdbItem.overview ?? "",
                            isWatched: false,
                            seasons: []
                        )
                        
                        
                        newItem.inMyList = true
                        
                        return newItem

                    } catch {
                        print("Errore fetch dettaglio mancante \(key): \(error)")
                    }
                    return nil
                }
            }
            
            // 4. Raccogliamo i risultati e aggiorniamo la UI
            var newItems: [MediaItem] = []
            for await item in group {
                if let item = item {
                    newItems.append(item)
                }
            }
            
            if !newItems.isEmpty {
                await MainActor.run {
                    // Aggiungiamo i nuovi elementi alla lista esistente
                    self.items.append(contentsOf: newItems)
                    
                }
            }
        }
    }
    
    func loadRealDataAndEnrich() async {
            do {
                // A. SCARICAMENTO BASE (Locandine)
                let tmdbResults = try await MovieService.shared.fetchTrending()
                
                var initialItems = tmdbResults.map { tmdbItem in
                    MediaItem(
                        tmdbId: tmdbItem.id,
                        title: tmdbItem.displayTitle,
                        imageName: tmdbItem.fullPosterURL?.absoluteString ?? "",
                        type: tmdbItem.title != nil ? .movie : .series,
                        matchPercentage: Int((tmdbItem.voteAverage ?? 0) * 10),
                        year: tmdbItem.displayYear,
                        description: tmdbItem.overview ?? "Nessuna trama disponibile",
                        isWatched: false,
                        seasons: []
                    )
                }
                
                // --- PARTE MANCANTE AGGIUNTA QUI SOTTO ---
                
                // Applichiamo i flag "Visto" e "In Lista" PRIMA di mostrare la UI
                for i in 0..<initialItems.count {
                    guard let tmdbId = initialItems[i].tmdbId else { continue }
                    
                    // 1. SINCRONIZZAZIONE LISTA PERSONALE
                    // Creiamo la chiave come salvata nel database (es. "movie_550" o "tv_123")
                    // Nota: Usiamo "tv" se è series, per compatibilità con Supabase
                    let typeString = (initialItems[i].type == .movie) ? "movie" : "tv"
                    let listKey = "\(typeString)_\(tmdbId)"
                    
                    // Se la chiave è nel Set scaricato da Supabase, accendiamo il flag
                    if personalListSet.contains(listKey) {
                        initialItems[i].inMyList = true
                    }
                    
                    // 2. SINCRONIZZAZIONE VISTI (Solo Film per ora)
                    if initialItems[i].type == .movie {
                        let watchedKey = generateKey(id: tmdbId, season: nil, episode: nil)
                        if watchedSet.contains(watchedKey) {
                            initialItems[i].isWatched = true
                        }
                    }
                }
                
                // ------------------------------------------
                
                // Mostriamo subito le locandine all'utente (UI veloce)
                await MainActor.run {
                    self.items = initialItems
                    self.heroMovie = initialItems.first
                }
                
                // B. SCARICAMENTO EPISODI (Background Parallelo)
                await withTaskGroup(of: MediaItem?.self) { group in
                    for item in initialItems {
                        group.addTask {
                            if item.type == .series {
                                return await self.fetchFullSeriesData(for: item)
                            } else if item.type == .movie {
                                return await self.fetchMovieData(for: item)
                            }
                            return nil
                        }
                    }
                    
                    // Man mano che i download finiscono, aggiorniamo la lista
                    for await enrichedItem in group {
                        if var newItem = enrichedItem {
                            await MainActor.run {
                                if let index = self.items.firstIndex(where: { $0.id == newItem.id }) {
                                    
                                    // IMPORTANTE: Manteniamo lo stato "inMyList" che abbiamo settato prima!
                                    // Altrimenti quando arrivano i dettagli, la spunta sparirebbe.
                                    newItem.inMyList = self.items[index].inMyList
                                    newItem.isWatched = self.items[index].isWatched
                                    
                                    self.items[index] = newItem
                                }
                                
                                if self.heroMovie?.id == newItem.id {
                                    // Manteniamo lo stato anche per l'hero
                                    var heroUpdate = newItem
                                    heroUpdate.inMyList = self.heroMovie?.inMyList ?? false
                                    self.heroMovie = heroUpdate
                                }
                            }
                        }
                    }
                }
                
                // C. RECUPERO GHOST ITEMS (Film in lista ma non in tendenza)
                await fetchMissingPersonalListItems()
                
            } catch { print("Errore caricamento massivo: \(error)") }
        }
    
    // Funzione Helper: Scarica Episodi e applica i visti
    private func fetchFullSeriesData(for item: MediaItem) async -> MediaItem? {
        guard let tmdbId = item.tmdbId else { return nil }
        var updatedItem = item
        
        do {
            let details = try await MovieService.shared.fetchShowDetails(id: tmdbId)
            var newSeasons: [Season] = []
            
            // Scarichiamo le prime 3 stagioni (per non esagerare con le API)
            for seasonMeta in details.seasons.prefix(3) where seasonMeta.seasonNumber > 0 {
                let episodes = try await MovieService.shared.fetchSeasonEpisodes(showId: tmdbId, seasonNumber: seasonMeta.seasonNumber)
                
                let convertedEpisodes = episodes.map { ep in
                    let key = generateKey(id: tmdbId, season: seasonMeta.seasonNumber, episode: ep.episodeNumber)
                    return Episode(
                        number: ep.episodeNumber,
                        title: ep.name,
                        duration: "\(ep.runtime ?? 30)m",
                        plot: ep.overview.isEmpty ? "Nessuna trama." : ep.overview,
                        imageURL: ep.stillPath != nil ? URL(string: "https://image.tmdb.org/t/p/w300\(ep.stillPath!)") : nil,
                        isWatched: watchedSet.contains(key) // APPLICA SUBITO LO STORICO
                    )
                }
                newSeasons.append(Season(number: seasonMeta.seasonNumber, episodes: convertedEpisodes))
            }
            updatedItem.seasons = newSeasons
            return updatedItem
            
        } catch {
            return nil
        }
    }
    
    // Funzione Helper: Scarica durata Film
    private func fetchMovieData(for item: MediaItem) async -> MediaItem? {
        guard let tmdbId = item.tmdbId else { return nil }
        var updatedItem = item
        do {
            let details = try await MovieService.shared.fetchMovieDetails(id: tmdbId)
            if let minutes = details.runtime, minutes > 0 {
                let hours = minutes / 60
                let mins = minutes % 60
                updatedItem.duration = "\(hours)h \(mins)m"
            }
            return updatedItem
        } catch { return nil }
    }
    
    // MARK: - FIX RICERCA E AGGIORNAMENTO LISTA
        func updateEpisodeStatus(tmdbId: Int, season: Int, episode: Int, isWatched: Bool, sourceItem: MediaItem? = nil) {
            let key = generateKey(id: tmdbId, season: season, episode: episode)
            
            // 1. Aggiorna la Cache veloce
            if isWatched { watchedSet.insert(key) } else { watchedSet.remove(key) }
            
            // 2. Aggiorna la lista 'items' (che alimenta la Home e 'La mia lista')
            if let index = items.firstIndex(where: { $0.tmdbId == tmdbId }) {
                // CASO A: La serie è già in lista -> Aggiorniamo l'episodio esistente
                if let sIndex = items[index].seasons.firstIndex(where: { $0.number == season }) {
                    if let eIndex = items[index].seasons[sIndex].episodes.firstIndex(where: { $0.number == episode }) {
                        items[index].seasons[sIndex].episodes[eIndex].isWatched = isWatched
                    }
                }
            } else if isWatched, var newItem = sourceItem {
                // CASO B (NUOVO): La serie NON è in lista (viene dalla Ricerca) e l'abbiamo appena iniziata.
                // Dobbiamo aggiungerla manualmente all'array 'items' così appare in "La mia lista".
                
                // Assicuriamoci che l'episodio specifico sia segnato come visto nel nuovo oggetto
                if let sIndex = newItem.seasons.firstIndex(where: { $0.number == season }),
                   let eIndex = newItem.seasons[sIndex].episodes.firstIndex(where: { $0.number == episode }) {
                    newItem.seasons[sIndex].episodes[eIndex].isWatched = true
                    
                    // Aggiungiamo alla lista principale!
                    items.append(newItem)
                }
            }
            
            // 3. Salva su Supabase
            Task {
                do {
                    if isWatched {
                        let log = WatchedLog(tmdbId: tmdbId, mediaType: "episode", seasonNumber: season, episodeNumber: episode)
                        try await SupabaseManager.shared.client.from("watched_items").insert(log).execute()
                    } else {
                        try await SupabaseManager.shared.client.from("watched_items").delete()
                            .eq("tmdb_id", value: tmdbId).eq("media_type", value: "episode")
                            .eq("season_number", value: season).eq("episode_number", value: episode).execute()
                    }
                } catch {
                    print("Errore salvataggio episodio DB: \(error)")
                }
            }
        }
    
    // MARK: - GESTIONE SUPABASE
    
    func fetchUserHistory() async {
        guard let _ = try? await SupabaseManager.shared.client.auth.session.user else { return }
        do {
            let history: [WatchedLog] = try await SupabaseManager.shared.client
                .from("watched_items").select().execute().value
            
            // Riempiamo il set per ricerche veloci O(1)
            var newSet = Set<String>()
            for log in history {
                newSet.insert(generateKey(id: log.tmdbId, season: log.seasonNumber, episode: log.episodeNumber))
            }
            self.watchedSet = newSet
            
        } catch { print("Errore storico: \(error)") }
    }
    
    private func generateKey(id: Int, season: Int?, episode: Int?) -> String {
        if let s = season, let e = episode { return "episode_\(id)_S\(s)_E\(e)" }
        return "movie_\(id)"
    }
    
    // MARK: - AZIONI UTENTE (Toggle)
    
    func toggleItemWatched(itemId: UUID) {
        guard let index = items.firstIndex(where: { $0.id == itemId }), let tmdbId = items[index].tmdbId else { return }
        
        items[index].isWatched.toggle()
        if heroMovie?.id == itemId { heroMovie?.isWatched = items[index].isWatched }
        let isNowWatched = items[index].isWatched
        
        Task {
            do {
                if isNowWatched {
                    let log = WatchedLog(tmdbId: tmdbId, mediaType: "movie", seasonNumber: nil, episodeNumber: nil)
                    try await SupabaseManager.shared.client.from("watched_items").insert(log).execute()
                    watchedSet.insert(generateKey(id: tmdbId, season: nil, episode: nil))
                } else {
                    try await SupabaseManager.shared.client.from("watched_items").delete()
                        .eq("tmdb_id", value: tmdbId).eq("media_type", value: "movie").execute()
                    watchedSet.remove(generateKey(id: tmdbId, season: nil, episode: nil))
                }
            } catch { print("Errore save film: \(error)") }
        }
    }
    
    func toggleInMyList(itemId: UUID) {
        guard let index = items.firstIndex(where: { $0.id == itemId }), let tmdbId = items[index].tmdbId else { return }
        
        items[index].inMyList.toggle()
        if heroMovie?.id == itemId { heroMovie?.inMyList = items[index].inMyList }
        let nowInList = items[index].inMyList
        
        Task {
            do {
                if nowInList {
                    let log = PersonalList(tmdbId: tmdbId, mediaType: items[index].type.rawValue)
                    try await SupabaseManager.shared.client.from("PersonalList").insert(log).execute()
                    personalListSet.insert("content_\(tmdbId)")
                } else {
                    try await SupabaseManager.shared.client.from("PersonalList").delete()
                        .eq("tmdb_id", value: tmdbId).eq("media_type", value: items[index].type.rawValue).execute()
                    personalListSet.remove("\(items[index].type.rawValue)_\(tmdbId)")
                }
            } catch { print("Errore aggiunta alla lista: \(error)") }
        }
    }
    
    func toggleEpisodeWatched(itemId: UUID, seasonId: UUID, episodeId: UUID) {
        guard let itemIndex = items.firstIndex(where: { $0.id == itemId }),
              let seasonIndex = items[itemIndex].seasons.firstIndex(where: { $0.id == seasonId }),
              let episodeIndex = items[itemIndex].seasons[seasonIndex].episodes.firstIndex(where: { $0.id == episodeId }),
              let tmdbSeriesId = items[itemIndex].tmdbId else { return }
        
        let seasonNum = items[itemIndex].seasons[seasonIndex].number
        let episodeNum = items[itemIndex].seasons[seasonIndex].episodes[episodeIndex].number
        
        // Toggle UI
        items[itemIndex].seasons[seasonIndex].episodes[episodeIndex].isWatched.toggle()
        let isNowWatched = items[itemIndex].seasons[seasonIndex].episodes[episodeIndex].isWatched
        let key = generateKey(id: tmdbSeriesId, season: seasonNum, episode: episodeNum)
        
        // Aggiorna cache locale e DB
        if isNowWatched { watchedSet.insert(key) } else { watchedSet.remove(key) }
        
        Task {
            do {
                if isNowWatched {
                    let log = WatchedLog(tmdbId: tmdbSeriesId, mediaType: "episode", seasonNumber: seasonNum, episodeNumber: episodeNum)
                    try await SupabaseManager.shared.client.from("watched_items").insert(log).execute()
                } else {
                    try await SupabaseManager.shared.client.from("watched_items").delete()
                        .eq("tmdb_id", value: tmdbSeriesId).eq("media_type", value: "episode")
                        .eq("season_number", value: seasonNum).eq("episode_number", value: episodeNum).execute()
                }
            } catch { print("Errore save ep: \(error)") }
        }
    }
    
    
    // 1. Modifica questa funzione per restituire MediaItem
    @discardableResult
    func loadEpisodes(for item: MediaItem) async -> MediaItem {
        // Se abbiamo già le stagioni o manca l'ID, restituiamo l'item così com'è
        guard item.type == .series, item.seasons.isEmpty, let tmdbId = item.tmdbId else { return item }
        
        var updatedItem = item
        
        do {
            let details = try await MovieService.shared.fetchShowDetails(id: tmdbId)
            var newSeasons: [Season] = []
            
            // Scarichiamo le prime 5 stagioni
            for seasonMeta in details.seasons.prefix(5) where seasonMeta.seasonNumber > 0 {
                let episodes = try await MovieService.shared.fetchSeasonEpisodes(showId: tmdbId, seasonNumber: seasonMeta.seasonNumber)
                
                let convertedEpisodes = episodes.map { ep in
                    let key = generateKey(id: tmdbId, season: seasonMeta.seasonNumber, episode: ep.episodeNumber)
                    return Episode(
                        number: ep.episodeNumber,
                        title: ep.name,
                        duration: "\(ep.runtime ?? 30)m",
                        plot: ep.overview.isEmpty ? "Nessuna trama." : ep.overview,
                        imageURL: ep.stillPath != nil ? URL(string: "https://image.tmdb.org/t/p/w300\(ep.stillPath!)") : nil,
                        isWatched: watchedSet.contains(key)
                    )
                }
                newSeasons.append(Season(number: seasonMeta.seasonNumber, episodes: convertedEpisodes))
            }
            
            updatedItem.seasons = newSeasons
            
            // Aggiorniamo ANCHE la lista Home se l'item esiste lì (per coerenza)
            await MainActor.run {
                if let index = items.firstIndex(where: { $0.id == item.id }) {
                    items[index] = updatedItem
                }
            }
            
        } catch {
            print("Errore caricamento episodi: \(error)")
        }
        
        return updatedItem
    }
    
    // 2. Modifica anche questa
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
                    if let index = items.firstIndex(where: { $0.id == item.id }) {
                        items[index] = updatedItem
                    }
                }
            }
        } catch {
            print("Errore durata film: \(error)")
        }
        
        return updatedItem // <--- IMPORTANTE
    }
}
// MARK: - 4. VIEWS

struct ContentView: View {
    @State private var viewModel = LibraryViewModel()
    @AppStorage("isDarkMode") private var isDarkMode = true

    var body: some View {
        TabView {
            HomeView(viewModel: viewModel)
                .tabItem { Label("Home", systemImage: "house.fill") }
            
            SearchView(libraryViewModel: viewModel)
                .tabItem { Label("Cerca", systemImage: "magnifyingglass") }
        }
        .accentColor(isDarkMode ? .white : .blue)
        .preferredColorScheme(isDarkMode ? .dark : .light)
    }
}

struct HomeView: View {
    var viewModel: LibraryViewModel
    @State private var showProfile = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(UIColor.systemBackground).ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        
                        if let hero = viewModel.heroMovie {
                            HeroSection(item: hero, viewModel: viewModel) {
                                viewModel.toggleItemWatched(itemId: hero.id)
                            }
                        }
                        
                        CategoryRow(title: "Di tendenza ora", items: viewModel.trendingMedia, viewModel: viewModel)
                        CategoryRow(title: "Continua a guardare", items: viewModel.keepWatching, viewModel: viewModel) .animation(.default, value: viewModel.keepWatching)
                        CategoryRow(title: "La tua lista", items: viewModel.personalList_, viewModel: viewModel) .animation(.default, value: viewModel.keepWatching)
                        
                        Spacer(minLength: 100)
                    }
                }
                .ignoresSafeArea(edges: .top)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showProfile = true
                    }) {
                        Image(systemName: "person.crop.circle")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                }
            }
            .sheet(isPresented: $showProfile) {
                ProfileView(libraryViewModel: viewModel)
            }
        }
    }
}

struct HeroSection: View {
    let item: MediaItem
    var viewModel: LibraryViewModel
    var onToggleWatched: () -> Void
    
    var body: some View {
        ZStack(alignment: .bottom) {
            
            // 1. NAVIGAZIONE (Rende l'immagine cliccabile)
            NavigationLink(destination: DetailView(item: item, viewModel: viewModel)) {
                ZStack(alignment: .bottom) {
                    // Immagine di Sfondo
                    GeometryReader { geo in
                        if let url = URL(string: item.imageName) {
                            AsyncImage(url: url) { phase in
                                if let image = phase.image {
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: geo.size.width, height: 550)
                                        .clipped()
                                } else {
                                    LinearGradient(colors: [.blue.opacity(0.3), .black], startPoint: .top, endPoint: .bottom)
                                }
                            }
                        }
                    }
                    .frame(height: 550)
                    
                    // Sfumatura nera (Parte del link, così anche cliccando in basso apri i dettagli)
                    LinearGradient(colors: [.clear, .black.opacity(0.8), .black], startPoint: .center, endPoint: .bottom)
                }
            }
            .buttonStyle(PlainButtonStyle()) // Rimuove l'effetto blu/grigio del link standard
            
            // 2. CONTENUTO TESTUALE (Sopra l'immagine)
            VStack(spacing: 16) {
                Text(item.type.rawValue.uppercased())
                    .font(.caption).bold().tracking(2).foregroundColor(.gray)
                    .allowsHitTesting(false) // Il tocco passa attraverso il testo per andare al Link
                
                Text(item.title)
                    .font(.system(size: 40, weight: .heavy))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .shadow(color: .black, radius: 10)
                    .padding(.horizontal)
                    .allowsHitTesting(false) // Il tocco passa attraverso il titolo
                
                // 3. BOTTONE (Solo per i FILM)
                if item.type == .movie {
                    Button(action: onToggleWatched) {
                        HStack {
                            Image(systemName: item.isWatched ? "checkmark.circle.fill" : "circle")
                            Text(item.isWatched ? "Visto" : "Segna come visto")
                                .bold()
                        }
                        .padding(.vertical, 12).padding(.horizontal, 30)
                        .background(item.isWatched ? Color.green : Color.white)
                        .foregroundColor(item.isWatched ? .white : .black)
                        .cornerRadius(8)
                    }
                } else {
                    // Per le serie, aggiungiamo un testo "Vedi Episodi" o solo spazio vuoto
                    // che invita a cliccare sull'immagine
                    Text("Tocca per gli episodi")
                        .font(.caption)
                        .foregroundColor(.gray.opacity(0.8))
                        .padding(.top, 5)
                }
            }
            .padding(.bottom, 40)
        }
    }
}

struct CategoryRow: View {
    let title: String
    let items: [MediaItem]
    var viewModel: LibraryViewModel
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(title).font(.headline).bold().foregroundStyle(.primary).padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(items) { item in
                        NavigationLink(destination: DetailView(item: item, viewModel: viewModel)) {
                            MediaCard(item: item)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

// 1. NUOVA VISTA ROBUSTA PER LE IMMAGINI
struct PosterImage: View {
    let urlString: String
    
    @State private var image: Image? // L'immagine caricata
    @State private var isLoading = false // Stato caricamento
    
    var body: some View {
        ZStack {
            // Sfondo grigio fisso
            Rectangle()
                .fill(Color(UIColor.systemGray6))
            
            if let image = image {
                // SE L'IMMAGINE C'È, LA MOSTRIAMO
                image
                    .resizable()
                    .scaledToFill()
            } else if isLoading {
                // SE STA CARICANDO, MOSTRA LA ROTELLINA
                ProgressView()
            } else {
                // FALLBACK SE FALLISCE O URL VUOTO
                Image(systemName: "photo")
                    .foregroundColor(.gray.opacity(0.3))
            }
        }
        // QUESTO È IL TRUCCO: .task è molto più stabile di AsyncImage
        // Ricarica solo se cambia l'URL, non se cambia la lista.
        .task(id: urlString) {
            await loadImage()
        }
    }
    
    // Funzione di scaricamento manuale
    private func loadImage() async {
        // Se abbiamo già l'immagine o l'URL è vuoto, non facciamo nulla
        guard let url = URL(string: urlString), image == nil else { return }
        
        isLoading = true
        
        do {
            // Scarichiamo i dati grezzi
            let (data, _) = try await URLSession.shared.data(from: url)
            
            // Convertiamo in immagine
            if let uiImage = UIImage(data: data) {
                // Animazione dolce all'apparizione
                withAnimation(.easeIn(duration: 0.2)) {
                    self.image = Image(uiImage: uiImage)
                }
            }
        } catch {
            // Se fallisce (es. cancellato), stampiamo l'errore ma l'UI resta pulita
            if (error as NSError).code != -999 { // Ignoriamo i "cancelled" normali
                print("⚠️ Errore download manuale [\(urlString)]: \(error.localizedDescription)")
            }
        }
        
        isLoading = false
    }
}

// 2. LA TUA CARD AGGIORNATA
struct MediaCard: View {
    let item: MediaItem
    
    var body: some View {
        VStack {
            // Usiamo la vista isolata
            PosterImage(urlString: item.imageName)
                .frame(width: 110, height: 160)
                .clipped()
                .cornerRadius(4)
                .overlay(
                    VStack {
                        Spacer()
                        if item.imageName.isEmpty || item.imageName == "film" {
                            Text(item.title)
                                .font(.caption2)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                                .padding(.bottom, 5)
                        }
                    }
                )
            
            // Barra progresso (Questa si aggiorna, ma non disturba l'immagine sopra!)
            if item.type == .series && item.watchedEpisodes > 0 {
                ProgressView(value: Double(item.watchedEpisodes), total: Double(item.totalEpisodes))
                    .progressViewStyle(LinearProgressViewStyle(tint: .red))
                    .frame(width: 110, height: 2)
                    .padding(.top, 4)
            }
        }
    }
    
}

// MARK: - DETAIL VIEW (Con gestione episodi)

    struct DetailView: View {
        let item: MediaItem
        var viewModel: LibraryViewModel
        
        // Per gestire lo stato del picker stagioni localmente
        @State private var selectedSeasonId: UUID?
        
        @State private var enrichedItem: MediaItem?
        
        // Troviamo l'item aggiornato dal ViewModel per avere lo stato "live" (reattivo)
        var liveItem: MediaItem {
            if let homeItem = viewModel.items.first(where: { $0.id == item.id }) {
                return homeItem
            } else {
                return enrichedItem ?? item // <--- Se non è in home, usa quello scaricato o l'originale
            }
        }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                
                // MARK: - HEADER (Immagine Locandina)
                ZStack(alignment: .bottom) {
                    if let url = URL(string: liveItem.imageName) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(height: 300)
                                    .clipped()
                                    .overlay(
                                        LinearGradient(colors: [.clear, .black.opacity(0.8), .black], startPoint: .center, endPoint: .bottom)
                                    )
                            case .failure:
                                Rectangle().fill(Color.gray.opacity(0.3)).frame(height: 300)
                            case .empty:
                                Rectangle().fill(Color.gray.opacity(0.3)).frame(height: 300)
                                    .overlay(ProgressView())
                            @unknown default:
                                EmptyView()
                            }
                        }
                    } else {
                        Rectangle().fill(Color.gray.opacity(0.3)).frame(height: 300)
                    }
                }
                .frame(height: 300)
                
                // MARK: - INFO E AZIONI
                VStack(alignment: .leading, spacing: 15) {
                    Text(liveItem.title)
                        .font(.largeTitle)
                        .bold()
                        .foregroundStyle(.primary)
                        .shadow(color: .black, radius: 10)
                    
                    // Metadati (Match, Anno, Durata)
                    HStack {
                        Text("\(liveItem.matchPercentage)% Match").foregroundStyle(.green).bold()
                        Text(liveItem.year).foregroundStyle(.gray)
                        if liveItem.type == .series {
                            Text("\(liveItem.seasons.count) Stagioni").foregroundStyle(.gray)
                        } else {
                            Text(liveItem.duration ?? "Caricamento...").foregroundStyle(.gray)
                        }
                        Text("HD").font(.caption).padding(2).border(Color.gray).foregroundStyle(.gray)
                    }.font(.subheadline)
                    
                    // MARK: - PULSANTE CHECKBOX "VISTO" + AGGIUNGI ALLA LISTA
                    if liveItem.type == .movie {
                        HStack(spacing: 12){
                            // bottone per aggiunta alla lista
                            Button(action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                    viewModel.toggleInMyList(itemId: liveItem.id)
                                }
                            }) {
                                Image(systemName: liveItem.inMyList ? "checkmark.circle.fill" : "plus")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                    .frame(width: 25, height: 25)
                                    .padding()
                                    .background(liveItem.inMyList ? Color.green : Color.gray.opacity(0.15))
                                    .clipShape(Circle())
                                    
                            }
                            .padding(.vertical, 5)
                            
                            // bottone per segnare come visto
                            Button(action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                    viewModel.toggleItemWatched(itemId: liveItem.id)
                                }
                            }) {
                                HStack {
                                    Image(systemName: liveItem.isWatched ? "checkmark.circle.fill" : "circle")
                                        .font(.title3)
                                    
                                    Text(liveItem.isWatched ? "Già visto" : "Segna come visto")
                                        .fontWeight(.bold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(liveItem.isWatched ? Color.green : Color.white)
                                .foregroundColor(liveItem.isWatched ? .white : .black)
                                .cornerRadius(8)
                            }
                            .padding(.vertical, 5)
                        }
                    }
                    else{
                        // bottone per aggiunta alla lista
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                viewModel.toggleInMyList(itemId: liveItem.id)
                            }
                        }) {
                            Image(systemName: liveItem.inMyList ? "checkmark.circle.fill" : "plus")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .frame(width: 25, height: 25)
                                .padding()
                                .background(liveItem.inMyList ? Color.green : Color.gray.opacity(0.15))
                                .clipShape(Circle())
                                
                        }
                        .padding(.vertical, 5)
                    }
                    
                    // Descrizione Trama
                    Text(liveItem.description)
                        .foregroundStyle(.primary)
                        .lineSpacing(4)
                        .padding(.top, 5)
                    
                    // --- LOGICA EPISODI SERIE TV ---
                    if liveItem.type == .series && !liveItem.seasons.isEmpty {
                        Divider().background(Color.gray).padding(.vertical)
                        
                        // Selettore Stagioni
                        if liveItem.seasons.count > 1 {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack {
                                    ForEach(liveItem.seasons) { season in
                                        Button(action: { selectedSeasonId = season.id }) {
                                            Text("Stagione \(season.number)")
                                                .bold()
                                                .padding(.vertical, 8)
                                                .padding(.horizontal, 16)
                                                .background((selectedSeasonId ?? liveItem.seasons.first?.id) == season.id ? Color.white : Color.gray.opacity(0.3))
                                                .foregroundColor((selectedSeasonId ?? liveItem.seasons.first?.id) == season.id ? .black : .white)
                                                .cornerRadius(20)
                                        }
                                    }
                                }
                            }
                            .padding(.bottom, 10)
                        }
                        
                        // Lista Episodi
                        let currentSeason = liveItem.seasons.first(where: { $0.id == (selectedSeasonId ?? liveItem.seasons.first?.id) })
                        
                        if let season = currentSeason {
                            ForEach(season.episodes) { episode in
                                HStack(alignment: .center, spacing: 12) {
                                    
                                    // Thumbnail Episodio
                                    ZStack(alignment: .bottomLeading) {
                                        Rectangle().fill(Color.gray.opacity(0.3))
                                        
                                        if let url = episode.imageURL {
                                            AsyncImage(url: url) { phase in
                                                if let image = phase.image {
                                                    image.resizable().aspectRatio(contentMode: .fill)
                                                } else { ProgressView() }
                                            }
                                        } else {
                                            Image(systemName: "film").foregroundStyle(.gray)
                                        }
                                    }
                                    .frame(width: 130, height: 75)
                                    .clipped()
                                    .cornerRadius(6)
                                    .overlay(
                                        Text(episode.duration)
                                            .font(.caption2).bold().foregroundColor(.white)
                                            .padding(4).background(Color.black.opacity(0.7)).cornerRadius(2).padding(4),
                                        alignment: .bottomLeading
                                    )
                                    
                                    // Testo Episodio
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("\(episode.number). \(episode.title)")
                                            .font(.subheadline).bold().foregroundStyle(.primary).lineLimit(1)
                                        Text(episode.plot)
                                            .font(.caption).foregroundStyle(.gray).lineLimit(2).multilineTextAlignment(.leading)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    
                                    // Checkbox Singolo Episodio
                                    Button(action: {
                                        // 1. Calcoliamo il nuovo stato (opposto di quello attuale)
                                        let newState = !episode.isWatched
                                        
                                        // 2. AGGIORNAMENTO LOCALE (Per la Ricerca)
                                        // Se stiamo visualizzando enrichedItem (Ricerca), dobbiamo aggiornarlo manualmente
                                        // altrimenti la spunta verde non appare
                                        if var enriched = enrichedItem, enriched.id == liveItem.id {
                                            if let sIndex = enriched.seasons.firstIndex(where: { $0.id == season.id }),
                                               let eIndex = enriched.seasons[sIndex].episodes.firstIndex(where: { $0.id == episode.id }) {
                                                
                                                // Modifichiamo la copia locale per feedback istantaneo
                                                enrichedItem?.seasons[sIndex].episodes[eIndex].isWatched = newState
                                            }
                                        }
                                        
                                        // 3. AGGIORNAMENTO LOGICO (Database + Home)
                                        // Usiamo la nuova funzione che accetta ID diretti
                                        if let tmdbId = item.tmdbId {
                                            viewModel.updateEpisodeStatus(
                                                tmdbId: tmdbId,
                                                season: season.number,
                                                episode: episode.number,
                                                isWatched: newState,
                                                sourceItem: liveItem 
                                            )
                                        }
                                        
                                    }) {
                                        Image(systemName: episode.isWatched ? "checkmark.circle.fill" : "circle")
                                            .font(.title2)
                                            .foregroundColor(episode.isWatched ? .red : .gray) // Ho visto che usavi .red, ottimo
                                            .padding(.leading, 4)
                                    }
                                }
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .background(Color.black)
        .toolbarRole(.editor)
        .onAppear {
            if selectedSeasonId == nil {
                selectedSeasonId = item.seasons.first?.id
            }
        }
        .task {
            // 1. Se è una SERIE
            if item.type == .series {
                // Scarichiamo e CATTURIAMO il risultato nella variabile 'updated'
                let updated = await viewModel.loadEpisodes(for: item)
                
                await MainActor.run {
                    // Salviamo il risultato nello stato locale della vista
                    self.enrichedItem = updated
                    
                    // Selezioniamo la prima stagione automaticamente
                    if selectedSeasonId == nil {
                        selectedSeasonId = updated.seasons.first?.id
                    }
                }
            }
            // 2. Se è un FILM
            else if item.type == .movie {
                let updated = await viewModel.loadMovieDuration(for: item)
                
                await MainActor.run {
                    // Salviamo la durata scaricata
                    self.enrichedItem = updated
                }
            }
        }
    }
}


// MARK: PROFILE VIEW
struct ProfileView: View {
    // ViewModel dedicato
    @State private var vm: ProfileViewModel
    @Environment(\.dismiss) var dismiss
    
    // Inizializzatore personalizzato
    init(libraryViewModel: LibraryViewModel) {
        _vm = State(initialValue: ProfileViewModel(libraryViewModel: libraryViewModel))
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(UIColor.systemBackground).ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 30) {
                        
                        // MARK: - HEADER UTENTE
                        VStack(spacing: 15) {
                            // Avatar
                            ZStack {
                                Circle()
                                    .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 100, height: 100)
                                
                                Text(String(vm.userEmail.prefix(1)).uppercased())
                                    .font(.system(size: 40, weight: .bold))
                                    .foregroundStyle(.primary)
                            }
                            .shadow(color: .blue.opacity(0.5), radius: 10)
                            
                            // Email
                            Text(vm.userEmail)
                                .font(.title3)
                                .bold()
                                .foregroundStyle(.primary)
                            
                            Text("Membro Standard")
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.gray.opacity(0.3))
                                .cornerRadius(5)
                                .foregroundStyle(.gray)
                        }
                        .padding(.top, 40)
                        
                        Divider().background(Color.gray.opacity(0.5))
                        
                        // MARK: - STATISTICHE
                        HStack(spacing: 40) {
                            StatBox(number: vm.watchedMoviesCount, label: "Film Visti")
                            StatBox(number: vm.watchedEpisodesCount, label: "Episodi")
                        }
                        .padding(.vertical)
                        
                        // MARK: - IMPOSTAZIONI / LOGOUT
                        VStack(spacing: 0) {
                            NavigationLink(destination: SettingsView()) {
                                SettingsRow(icon: "gear", title: "Impostazioni App")
                            }
                            Divider().background(Color.gray.opacity(0.2))
                            SettingsRow(icon: "info.circle", title: "Versione App", value: vm.appVersion)
                            
                            Color.clear.frame(height: 40)
                            
                            // Tasto Logout
                            Button(action: {
                                Task {
                                    let success = await vm.performLogout()
                                    if success {
                                        dismiss()
                                        // Qui puoi gestire il reset della root view se necessario
                                    }
                                }
                            }) {
                                HStack {
                                    Image(systemName: "rectangle.portrait.and.arrow.right")
                                    Text("Esci dall'account")
                                }
                                .bold()
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.red.opacity(0.9))
                                .foregroundColor(.white)
                                .cornerRadius(10)
                            }
                        }
                        .padding(.horizontal)
                        
                    }
                    .padding(.bottom, 50)
                }
            }
            .navigationTitle("Profilo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Chiudi") { dismiss() }
                        .foregroundStyle(.primary)
                }
            }
            .task {
                await vm.fetchUser()
            }
        }
    }
}

// Helper Components per il Profilo
struct StatBox: View {
    let number: Int
    let label: String
    
    var body: some View {
        VStack {
            Text("\(number)")
                .font(.title).bold()
                .foregroundStyle(.primary)
            Text(label)
                .font(.caption)
                .foregroundStyle(.gray)
        }
    }
}

struct SettingsRow: View {
    let icon: String
    let title: String
    var value: String? = nil
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.gray)
                .frame(width: 30)
            Text(title)
                .foregroundStyle(.primary)
            Spacer()
            if let v = value {
                Text(v).foregroundStyle(.gray).font(.caption)
            } else {
                Image(systemName: "chevron.right").foregroundStyle(.gray)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
    }
}
#Preview {
    ContentView().preferredColorScheme(.dark)
}

