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
            // 1. Scarica la lista di base da Supabase
            let temp = try await apiSupabase.loadWatching()
            var enrichedTemp: [MediaItem] = []
            
            // 2. Arricchiamo e FILTRIAMO ogni elemento
            for item in temp {
                if item.type == .series {
                    let enriched = await loadEpisodes(for: item)
                    
                    // CALCOLO DELLO STATO REALE DELLA SERIE
                    let isFullyWatched = enriched.totalEpisodes > 0 && enriched.watchedEpisodes == enriched.totalEpisodes
                    let hasZeroWatched = enriched.watchedEpisodes == 0
                    
                    if isFullyWatched || hasZeroWatched {
                        // 🛑 ZOMBIE DATA TROVATO: La serie è finita (o azzerata),
                        // ma Supabase la teneva ancora in ostaggio in "keepWatching".
                        
                        if let tmdbId = enriched.tmdbId {
                            // A. Puliamo il Database in background per tenerlo ordinato
                            Task {
                                do {
                                    try await SupabaseManager.shared.client.from("keepWatching")
                                        .delete().eq("tmdb_id", value: tmdbId).execute()
                                    print("🧹 Pulizia zombie eseguita per ID: \(tmdbId)")
                                } catch {
                                    print("❌ Errore pulizia zombie: \(error)")
                                }
                                
                                // Se è finita, ci assicuriamo che sia tra i "Visti" definitivi
                                if isFullyWatched {
                                    let seriesLog = watchedItem(tmdb_id: tmdbId, media_type: "Serie TV", season_number: nil, episode_number: nil)
                                    try? await SupabaseManager.shared.client.from("watched_items").insert(seriesLog).execute()
                                }
                            }
                        }
                        // B. NON la aggiungiamo a `enrichedTemp`, così scompare dalla UI!
                        
                    } else {
                        // ✅ Tutto regolare, la serie è in corso!
                        enrichedTemp.append(enriched)
                    }
                } else {
                    // I Film passano lisci (non avendo stagioni non si bloccano)
                    let enriched = await loadMovieDuration(for: item)
                    enrichedTemp.append(enriched)
                }
            }
            
            // 3. Mostriamo la lista pulita e filtrata sulla Home Page
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
            print("✅ Storico caricato: \(newWatchedSet.count) elementi visti trovati.")
            
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
            // 1. Troviamo l'ID universale (tmdbId) per non confondere le copie
            guard let originalItem = generalCacheContents.first(where: { $0.id == itemId }),
                  let tmdbId = originalItem.tmdbId else { return }
            
            let newState = !originalItem.inMyList
            let mediaTypeStr = originalItem.type.rawValue
            
            // 2. SINCRONIZZAZIONE UNIVERSALE: Aggiorniamo TUTTE le copie in TUTTI gli array!
            for i in generalCacheContents.indices where generalCacheContents[i].tmdbId == tmdbId {
                generalCacheContents[i].inMyList = newState
            }
            for i in viewTrendings.indices where viewTrendings[i].tmdbId == tmdbId {
                viewTrendings[i].inMyList = newState
            }
            for i in keepWatching.indices where keepWatching[i].tmdbId == tmdbId {
                keepWatching[i].inMyList = newState // La copia qui mantiene i suoi episodi intatti!
            }
            
            // 3. Aggiorniamo la riga orizzontale "La tua lista"
            if newState {
                // Se lo aggiungiamo, peschiamo la copia più "ricca" (magari ha già le stagioni caricate)
                if let bestCopy = keepWatching.first(where: { $0.tmdbId == tmdbId }) ?? generalCacheContents.first(where: { $0.tmdbId == tmdbId }) {
                    personalList.insert(bestCopy, at: 0)
                }
            } else {
                // Rimuoviamo in base al tmdbId per essere sicuri al 100%
                personalList.removeAll(where: { $0.tmdbId == tmdbId })
            }
            
            if heroMovie?.tmdbId == tmdbId { heroMovie?.inMyList = newState }
            
            // 4. Salva su Supabase (rimasto invariato)
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
            // 1. Troviamo le info base dalla cache generale
            guard let itemIndex = generalCacheContents.firstIndex(where: { $0.id == itemId }),
                  let seasonIndex = generalCacheContents[itemIndex].seasons.firstIndex(where: { $0.id == seasonId }),
                  let episodeIndex = generalCacheContents[itemIndex].seasons[seasonIndex].episodes.firstIndex(where: { $0.id == episodeId }),
                  let tmdbSeriesId = generalCacheContents[itemIndex].tmdbId else { return }
            
            let seasonNum = generalCacheContents[itemIndex].seasons[seasonIndex].number
            let episodeNum = generalCacheContents[itemIndex].seasons[seasonIndex].episodes[episodeIndex].number
            
            // 2. Calcoliamo il nuovo stato (visto / non visto)
            let isNowWatched = !generalCacheContents[itemIndex].seasons[seasonIndex].episodes[episodeIndex].isWatched
            let key = generateKey(id: tmdbSeriesId, season: seasonNum, episode: episodeNum)
            
            // 3. AGGIORNAMENTO STORICO IN MEMORIA (Fondamentale per i futuri download!)
            if isNowWatched {
                watchedSet.insert(key)
            } else {
                watchedSet.remove(key)
            }
            
            // 4. SINCRONIZZAZIONE UNIVERSALE: Aggiorniamo la spunta su TUTTE le copie della serie!
            
            // Helper interno per non ripetere il codice
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
            
            // Aggiorniamo l'Hero Movie se necessario
            if heroMovie?.tmdbId == tmdbSeriesId {
                if let sIdx = heroMovie?.seasons.firstIndex(where: { $0.number == seasonNum }),
                   let eIdx = heroMovie?.seasons[sIdx].episodes.firstIndex(where: { $0.number == episodeNum }) {
                    heroMovie?.seasons[sIdx].episodes[eIdx].isWatched = isNowWatched
                }
            }
            
            // 5. PRENDIAMO L'OGGETTO AGGIORNATO (per calcolare il progresso della serie)
            guard let updatedItemIndex = generalCacheContents.firstIndex(where: { $0.tmdbId == tmdbSeriesId }) else { return }
            let updatedMediaItem = generalCacheContents[updatedItemIndex]
            
            let isFullyWatched = updatedMediaItem.watchedEpisodes == updatedMediaItem.totalEpisodes
            let isInProgress = updatedMediaItem.watchedEpisodes > 0 && !isFullyWatched
            
            // 6. GESTIONE "CONTINUA A GUARDARE"
            if isInProgress {
                if let localIndex = keepWatching.firstIndex(where: { $0.tmdbId == tmdbSeriesId }) {
                    keepWatching[localIndex] = updatedMediaItem // Aggiorna barra progresso
                } else {
                    keepWatching.insert(updatedMediaItem, at: 0) // Aggiunge alla riga
                }
            } else {
                // Rimuove la serie se è finita o se togli la spunta al primo episodio
                keepWatching.removeAll(where: { $0.tmdbId == tmdbSeriesId })
            }
            
            // 7. AGGIORNAMENTO DATABASE SUPABASE
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
                    
                    // Usiamo il nome esatto della colonna: tmdbId
                    struct KeepWatchInsert: Codable { let tmdbId: Int }
                    
                    if isFullyWatched {
                        // CANCELLAZIONE: Usiamo "tmdbId"
                        do {
                            try await SupabaseManager.shared.client.from("keepWatching").delete()
                                .eq("tmdbId", value: tmdbSeriesId).execute()
                            print("✅ Serie completata: cancellata da keepWatching!")
                        } catch { print("❌ Errore delete keepWatching: \(error)") }
                        
                        let seriesLog = watchedItem(tmdb_id: tmdbSeriesId, media_type: "Serie TV", season_number: nil, episode_number: nil)
                        try? await SupabaseManager.shared.client.from("watched_items").insert(seriesLog).execute()
                        
                    } else if isInProgress {
                        try? await SupabaseManager.shared.client.from("keepWatching").delete()
                            .eq("tmdbId", value: tmdbSeriesId).execute()
                        
                        // INSERIMENTO: Usiamo "tmdbId"
                        let keepLog = KeepWatchInsert(tmdbId: tmdbSeriesId)
                        try await SupabaseManager.shared.client.from("keepWatching").insert(keepLog).execute()
                        
                        try? await SupabaseManager.shared.client.from("watched_items").delete()
                            .eq("tmdb_id", value: tmdbSeriesId).eq("media_type", value: "Serie TV").execute()
                        
                    } else {
                        try? await SupabaseManager.shared.client.from("keepWatching").delete()
                            .eq("tmdbId", value: tmdbSeriesId).execute()
                        try? await SupabaseManager.shared.client.from("watched_items").delete()
                            .eq("tmdb_id", value: tmdbSeriesId).eq("media_type", value: "Serie TV").execute()
                    }
                } catch { print("Errore salvataggio Supabase: \(error)") }
            }
        }
    
    // MARK: - DOWNLOAD DETTAGLI EPISODI E DURATA
        
        @discardableResult
        func loadEpisodes(for item: MediaItem) async -> MediaItem {
            // Controlla se è una serie e se non abbiamo già scaricato le stagioni
            guard item.type == .series, item.seasons.isEmpty, let tmdbId = item.tmdbId else { return item }
            
            var updatedItem = item
            
            do {
                // 1. Chiediamo a TMDB i dettagli della serie (per sapere quante stagioni ha)
                let details = try await MovieService.shared.fetchShowDetails(id: tmdbId)
                var newSeasons: [Season] = []
                
                // 2. Scarichiamo le prime 5 stagioni (evitando la stagione 0 che di solito sono gli "Speciali")
                for seasonMeta in details.seasons?.prefix(5) ?? [] where seasonMeta.seasonNumber > 0 {
                    let episodes = try await MovieService.shared.fetchSeasonEpisodes(showId: tmdbId, seasonNumber: seasonMeta.seasonNumber)
                    
                    let convertedEpisodes = episodes.map { ep in
                        let key = generateKey(id: tmdbId, season: seasonMeta.seasonNumber, episode: ep.episodeNumber)
                        return Episode(
                            number: ep.episodeNumber,
                            title: ep.name,
                            duration: "\(ep.runtime ?? 30)m",
                            plot: ep.overview.isEmpty ? "Nessuna trama." : ep.overview,
                            imageURL: ep.stillPath != nil ? URL(string: "https://image.tmdb.org/t/p/w300\(ep.stillPath!)") : nil,
                            isWatched: watchedSet.contains(key), // Mette la spunta se l'avevamo già visto!
                            show_id: ep.showId
                        )
                    }
                    newSeasons.append(Season(number: seasonMeta.seasonNumber, episodes: convertedEpisodes))
                }
                
                updatedItem.seasons = newSeasons
                
                // 3. Aggiorniamo la cache generale
                await MainActor.run {
                    // Distribuiamo le stagioni scaricate a TUTTE le copie nell'app!
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
            // 1. Creiamo un Set veloce degli ID presenti nella lista personale
            let personalIds = Set(self.personalList.compactMap { $0.tmdbId })
            
            // 2. Sincronizziamo i Trendings
            for i in self.viewTrendings.indices {
                if let id = self.viewTrendings[i].tmdbId {
                    // Allinea la spunta verde per la lista
                    self.viewTrendings[i].inMyList = personalIds.contains(id)
                    
                    // Allinea il "Già visto" se è un Film
                    if self.viewTrendings[i].type == .movie {
                        let key = generateKey(id: id, season: nil, episode: nil)
                        self.viewTrendings[i].isWatched = self.watchedSet.contains(key)
                    }
                }
            }
            
            // 3. Sincronizziamo Continua a Guardare
            for i in self.keepWatching.indices {
                if let id = self.keepWatching[i].tmdbId {
                    self.keepWatching[i].inMyList = personalIds.contains(id)
                }
            }
            
            // 4. Sincronizziamo la Cache Generale (che alimenta le schede di dettaglio)
            for i in self.generalCacheContents.indices {
                if let id = self.generalCacheContents[i].tmdbId {
                    self.generalCacheContents[i].inMyList = personalIds.contains(id)
                    
                    if self.generalCacheContents[i].type == .movie {
                        let key = generateKey(id: id, season: nil, episode: nil)
                        self.generalCacheContents[i].isWatched = self.watchedSet.contains(key)
                    }
                }
            }
            
            // 5. Aggiorna anche l'Hero Movie gigante in alto!
            if let heroId = self.heroMovie?.tmdbId {
                self.heroMovie?.inMyList = personalIds.contains(heroId)
                if self.heroMovie?.type == .movie {
                    let key = generateKey(id: heroId, season: nil, episode: nil)
                    self.heroMovie?.isWatched = self.watchedSet.contains(key)
                }
            }
            
            print("🔄 Sincronizzazione iniziale completata con successo!")
        }
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
                        
                        CategoryRow(title: "Di tendenza ora", items: viewModel.viewTrendings, viewModel: viewModel)
                        CategoryRow(title: "Continua a guardare", items: viewModel.keepWatching, viewModel: viewModel)
                            .animation(.default, value: viewModel.keepWatching)
                        CategoryRow(title: "La tua lista", items: viewModel.personalList, viewModel: viewModel)
                            .animation(.default, value: viewModel.keepWatching)
                        
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
            
            NavigationLink(destination: DetailView(item: item, viewModel: viewModel)) {
                ZStack(alignment: .bottom) {
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
                    LinearGradient(colors: [.clear, .black.opacity(0.8), .black], startPoint: .center, endPoint: .bottom)
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            VStack(spacing: 16) {
                Text(item.type.rawValue.uppercased())
                    .font(.caption).bold().tracking(2).foregroundColor(.gray)
                    .allowsHitTesting(false)
                Text(item.title)
                    .font(.system(size: 40, weight: .heavy))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .shadow(color: .black, radius: 10)
                    .padding(.horizontal)
                    .allowsHitTesting(false)
                
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

struct PosterImage: View {
    let urlString: String
    @State private var image: Image?
    @State private var isLoading = false
    
    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color(UIColor.systemGray6))
            
            if let image = image {
                image.resizable().scaledToFill()
            } else if isLoading {
                ProgressView()
            } else {
                Image(systemName: "photo").foregroundColor(.gray.opacity(0.3))
            }
        }
        .task(id: urlString) {
            await loadImage()
        }
    }
    
    private func loadImage() async {
        guard let url = URL(string: urlString), image == nil else { return }
        isLoading = true
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let uiImage = UIImage(data: data) {
                withAnimation(.easeIn(duration: 0.2)) {
                    self.image = Image(uiImage: uiImage)
                }
            }
        } catch {
            if (error as NSError).code != -999 {
                print("⚠️ Errore download manuale [\(urlString)]: \(error.localizedDescription)")
            }
        }
        isLoading = false
    }
}

struct MediaCard: View {
    let item: MediaItem
    
    var body: some View {
        VStack {
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
            
            if item.type == .series && item.watchedEpisodes > 0 {
                ProgressView(value: Double(item.watchedEpisodes), total: Double(item.totalEpisodes))
                    .progressViewStyle(LinearProgressViewStyle(tint: .red))
                    .frame(width: 110, height: 2)
                    .padding(.top, 4)
            }
        }
    }
}

// MARK: - DETAIL VIEW RISTRUTTURATA PER IL COMPILATORE
struct DetailView: View {
    let item: MediaItem
    var viewModel: LibraryViewModel
    
    @State private var selectedSeasonId: UUID?
    @State private var enrichedItem: MediaItem?
    
    var liveItem: MediaItem {
        if let homeItem = viewModel.generalCacheContents.first(where: { $0.tmdbId == item.tmdbId }) {
            return homeItem
        } else {
            return enrichedItem ?? item
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                headerImage
                
                VStack(alignment: .leading, spacing: 15) {
                    titleAndMetadata
                    actionButtons
                    
                    Text(liveItem.description)
                        .foregroundStyle(.primary)
                        .lineSpacing(4)
                        .padding(.top, 5)
                    
                    episodesSection
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
            if !viewModel.generalCacheContents.contains(where: { $0.tmdbId == item.tmdbId }) {
                viewModel.generalCacheContents.append(item)
            }
        }
        .task {
            if item.type == .series {
                let updated = await viewModel.loadEpisodes(for: item)
                await MainActor.run {
                    self.enrichedItem = updated
                    if selectedSeasonId == nil { selectedSeasonId = updated.seasons.first?.id }
                }
            } else if item.type == .movie {
                let updated = await viewModel.loadMovieDuration(for: item)
                await MainActor.run { self.enrichedItem = updated }
            }
        }
    }
    
    // MARK: - Sub-Components
    private var headerImage: some View {
        ZStack(alignment: .bottom) {
            if let url = URL(string: liveItem.imageName) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill).frame(height: 300).clipped()
                            .overlay(LinearGradient(colors: [.clear, .black.opacity(0.8), .black], startPoint: .center, endPoint: .bottom))
                    case .failure, .empty:
                        Rectangle().fill(Color.gray.opacity(0.3)).frame(height: 300)
                    @unknown default: EmptyView()
                    }
                }
            } else {
                Rectangle().fill(Color.gray.opacity(0.3)).frame(height: 300)
            }
        }
        .frame(height: 300)
    }
    
    private var titleAndMetadata: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(liveItem.title)
                .font(.largeTitle).bold().foregroundStyle(.primary).shadow(color: .black, radius: 10)
            
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
        }
    }
    
    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    viewModel.toggleInMyList(itemId: liveItem.id)
                }
            }) {
                Image(systemName: liveItem.inMyList ? "checkmark.circle.fill" : "plus")
                    .font(.title3).fontWeight(.semibold).frame(width: 25, height: 25).padding()
                    .background(liveItem.inMyList ? Color.green : Color.gray.opacity(0.15))
                    .clipShape(Circle())
            }
            .padding(.vertical, 5)
            
            if liveItem.type == .movie {
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        viewModel.toggleItemWatched(itemId: liveItem.id)
                    }
                }) {
                    HStack {
                        Image(systemName: liveItem.isWatched ? "checkmark.circle.fill" : "circle").font(.title3)
                        Text(liveItem.isWatched ? "Già visto" : "Segna come visto").fontWeight(.bold)
                    }
                    .frame(maxWidth: .infinity).padding()
                    .background(liveItem.isWatched ? Color.green : Color.white)
                    .foregroundColor(liveItem.isWatched ? .white : .black)
                    .cornerRadius(8)
                }
                .padding(.vertical, 5)
            }
        }
    }
    
    @ViewBuilder
    private var episodesSection: some View {
        if liveItem.type == .series && !liveItem.seasons.isEmpty {
            Divider().background(Color.gray).padding(.vertical)
            
            if liveItem.seasons.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(liveItem.seasons) { season in
                            Button(action: { selectedSeasonId = season.id }) {
                                Text("Stagione \(season.number)")
                                    .bold().padding(.vertical, 8).padding(.horizontal, 16)
                                    .background((selectedSeasonId ?? liveItem.seasons.first?.id) == season.id ? Color.white : Color.gray.opacity(0.3))
                                    .foregroundColor((selectedSeasonId ?? liveItem.seasons.first?.id) == season.id ? .black : .white)
                                    .cornerRadius(20)
                            }
                        }
                    }
                }
                .padding(.bottom, 10)
            }
            
            if let season = liveItem.seasons.first(where: { $0.id == (selectedSeasonId ?? liveItem.seasons.first?.id) }) {
                ForEach(season.episodes) { episode in
                    episodeRow(season: season, episode: episode)
                }
            }
        }
    }
    
    private func episodeRow(season: Season, episode: Episode) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack(alignment: .bottomLeading) {
                Rectangle().fill(Color.gray.opacity(0.3))
                if let url = episode.imageURL {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image { image.resizable().aspectRatio(contentMode: .fill) }
                        else { ProgressView() }
                    }
                } else {
                    Image(systemName: "film").foregroundStyle(.gray)
                }
            }
            .frame(width: 130, height: 75).clipped().cornerRadius(6)
            .overlay(
                Text(episode.duration).font(.caption2).bold().foregroundColor(.white)
                    .padding(4).background(Color.black.opacity(0.7)).cornerRadius(2).padding(4),
                alignment: .bottomLeading
            )
            
            VStack(alignment: .leading, spacing: 4) {
                Text("\(episode.number). \(episode.title)").font(.subheadline).bold().foregroundStyle(.primary).lineLimit(1)
                Text(episode.plot).font(.caption).foregroundStyle(.gray).lineLimit(2).multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Button(action: {
                let newState = !episode.isWatched
                if var enriched = enrichedItem, enriched.id == liveItem.id {
                    if let sIndex = enriched.seasons.firstIndex(where: { $0.id == season.id }),
                       let eIndex = enriched.seasons[sIndex].episodes.firstIndex(where: { $0.id == episode.id }) {
                        enrichedItem?.seasons[sIndex].episodes[eIndex].isWatched = newState
                    }
                }
                // CHIAMATA CORRETTA AL VIEW MODEL
                viewModel.toggleEpisodeWatched(itemId: liveItem.id, seasonId: season.id, episodeId: episode.id)
            }) {
                Image(systemName: episode.isWatched ? "checkmark.circle.fill" : "circle")
                    .font(.title2).foregroundColor(episode.isWatched ? .red : .gray).padding(.leading, 4)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - PROFILE VIEW
struct ProfileView: View {
    @State private var vm: ProfileViewModel
    @Environment(\.dismiss) var dismiss
    
    init(libraryViewModel: LibraryViewModel) {
        _vm = State(initialValue: ProfileViewModel(libraryViewModel: libraryViewModel))
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(UIColor.systemBackground).ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 30) {
                        
                        VStack(spacing: 15) {
                            ZStack {
                                Circle().fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 100, height: 100)
                                Text(String(vm.userEmail.prefix(1)).uppercased())
                                    .font(.system(size: 40, weight: .bold)).foregroundStyle(.primary)
                            }.shadow(color: .blue.opacity(0.5), radius: 10)
                            
                            Text(vm.userEmail).font(.title3).bold().foregroundStyle(.primary)
                            Text("Membro Standard").font(.caption).padding(.horizontal, 10).padding(.vertical, 4)
                                .background(Color.gray.opacity(0.3)).cornerRadius(5).foregroundStyle(.gray)
                        }.padding(.top, 40)
                        
                        Divider().background(Color.gray.opacity(0.5))
                        
                        HStack(spacing: 40) {
                            StatBox(number: vm.watchedMoviesCount, label: "Film Visti")
                            StatBox(number: vm.watchedEpisodesCount, label: "Episodi")
                        }.padding(.vertical)
                        
                        VStack(spacing: 0) {
                            NavigationLink(destination: SettingsView()) { SettingsRow(icon: "gear", title: "Impostazioni App") }
                            Divider().background(Color.gray.opacity(0.2))
                            SettingsRow(icon: "info.circle", title: "Versione App", value: vm.appVersion)
                            Color.clear.frame(height: 40)
                            
                            Button(action: {
                                Task {
                                    if await vm.performLogout() { dismiss() }
                                }
                            }) {
                                HStack {
                                    Image(systemName: "rectangle.portrait.and.arrow.right")
                                    Text("Esci dall'account")
                                }.bold().frame(maxWidth: .infinity).padding()
                                .background(Color.red.opacity(0.9)).foregroundColor(.white).cornerRadius(10)
                            }
                        }.padding(.horizontal)
                    }.padding(.bottom, 50)
                }
            }
            .navigationTitle("Profilo").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Chiudi") { dismiss() }.foregroundStyle(.primary) }
            }
            .task { await vm.fetchUser() }
        }
    }
}

// Helper Components per il Profilo
struct StatBox: View {
    let number: Int
    let label: String
    var body: some View {
        VStack {
            Text("\(number)").font(.title).bold().foregroundStyle(.primary)
            Text(label).font(.caption).foregroundStyle(.gray)
        }
    }
}

struct SettingsRow: View {
    let icon: String
    let title: String
    var value: String? = nil
    var body: some View {
        HStack {
            Image(systemName: icon).foregroundStyle(.gray).frame(width: 30)
            Text(title).foregroundStyle(.primary)
            Spacer()
            if let v = value { Text(v).foregroundStyle(.gray).font(.caption) }
            else { Image(systemName: "chevron.right").foregroundStyle(.gray) }
        }
        .padding().background(Color.gray.opacity(0.1))
    }
}

#Preview {
    ContentView().preferredColorScheme(.dark)
}
