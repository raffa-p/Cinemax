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
    var viewTrendings: [MediaItem]?
    var heroMovie: MediaItem?
    var generalCacheContents: [MediaItem]?
    
    
    // lista "Continua a guardare"
    var keepWatching: [MediaItem] = []
    
    // lista "La tua lista"
    var personalList: [MediaItem] = []
    
    // lista "visti"
    var watchedItems: [MediaItem] = []
    
    
    init() {
            Task {
                await viewWatchingMethod()
                await viewPersonalList()
                await viewTrendingsMethod()
            }
        }
    
    // MARK: DOWNLOADS
    func viewPersonalList() async {
        do {
            let temp = try await apiSupabase.loadPersonalList()
            generalCacheContents?.append(contentsOf: temp)
            
            await MainActor.run {
                self.personalList = temp
            }
        } catch {
            print("Errore recupero personal list: \(error.localizedDescription)")
        }
    }
    
    func viewWatchingMethod() async {
        do {
            let temp = try await apiSupabase.loadWatching()
            generalCacheContents?.append(contentsOf: temp)

            await MainActor.run {
                self.keepWatching = temp
            }
        } catch {
            print("Errore recupero continuna a guardare: \(error.localizedDescription)")
        }
    }
    
    func viewTrendingsMethod() async {
        do {
            let temp = try await apiSupabase.loadTrendings()
            generalCacheContents?.append(contentsOf: temp)

            await MainActor.run {
                self.viewTrendings = temp
                self.heroMovie = temp.first
            }
        } catch {
            print("Errore recupero trendings: \(error.localizedDescription)")
        }
    }

    
    // MARK: - GESTIONE SUPABASE
    
    private func generateKey(id: Int, season: Int?, episode: Int?) -> String {
        if let s = season, let e = episode { return "episode_\(id)_S\(s)_E\(e)" }
        return "movie_\(id)"
    }
    
    // MARK: - AZIONI UTENTE (Toggle)
    
    func toggleItemWatched(itemId: UUID) {
        guard let index = generalCacheContents!.firstIndex(where: { $0.id == itemId }), let tmdbId = generalCacheContents![index].tmdbId else { return }
        
        generalCacheContents![index].isWatched.toggle()
        if heroMovie?.id == itemId { heroMovie?.isWatched = generalCacheContents![index].isWatched }
        let isNowWatched = generalCacheContents![index].isWatched
        
        Task {
            do {
                if isNowWatched {
                    let log = watchedItem(tmdb_id: tmdbId, mediaType: "movie", seasonNumber: nil, episodeNumber: nil)
                    try await SupabaseManager.shared.client.from("watched_items").insert(log).execute()
                    watchedItem.insert(generateKey(id: tmdbId, season: nil, episode: nil))
                } else {
                    try await SupabaseManager.shared.client.from("watched_items").delete()
                        .eq("tmdb_id", value: tmdbId).eq("media_type", value: "movie").execute()
                    watchedItem.remove(generateKey(id: tmdbId, season: nil, episode: nil))
                }
            } catch { print("Errore aggiornamento flag visto: \(error)") }
        }
    }
    
    // add item to personal list
    func toggleInMyList(itemId: UUID) {
        guard let index = generalCacheContents!.firstIndex(where: { $0.id == itemId }), let tmdbId = generalCacheContents![index].tmdbId else { return }
        
        generalCacheContents![index].inMyList.toggle()
        if heroMovie?.id == itemId { heroMovie?.inMyList = generalCacheContents![index].inMyList }
        let nowInList = generalCacheContents![index].inMyList
        
        Task {
            do {
                if nowInList {
                    let log = personalListItem(tmdb_id: tmdbId, mediaType: generalCacheContents[index].type.rawValue)
                    try await SupabaseManager.shared.client
                        .from("PersonalList")
                        .insert(log)
                        .execute()
                    viewPersonalList().insert("content_\(tmdbId)")
                } else {
                    try await SupabaseManager.shared.client
                        .from("PersonalList")
                        .delete()
                        .eq("tmdb_id", value: tmdbId)
                        .eq("media_type", value: generalCacheContents[index].type.rawValue)
                        .execute()
                    viewPersonalList().remove("\(generalCacheContents[index].type.rawValue)_\(tmdbId)")
                }
            } catch { print("Errore aggiunta/rimozione in lista: \(error)") }
        }
    }
    
    func toggleEpisodeWatched(itemId: UUID, seasonId: UUID, episodeId: UUID) {
        // 1. Troviamo gli indici nella cache principale
        guard let itemIndex = generalCacheContents?.firstIndex(where: { $0.id == itemId }),
              let seasonIndex = generalCacheContents![itemIndex].seasons.firstIndex(where: { $0.id == seasonId }),
              let episodeIndex = generalCacheContents![itemIndex].seasons[seasonIndex].episodes.firstIndex(where: { $0.id == episodeId }),
              let tmdbSeriesId = generalCacheContents![itemIndex].tmdbId else { return }
        
        let seasonNum = generalCacheContents![itemIndex].seasons[seasonIndex].number
        let episodeNum = generalCacheContents![itemIndex].seasons[seasonIndex].episodes[episodeIndex].number
        
        // 2. Toggle UI nella cache principale
        generalCacheContents![itemIndex].seasons[seasonIndex].episodes[episodeIndex].isWatched.toggle()
        let isNowWatched = generalCacheContents![itemIndex].seasons[seasonIndex].episodes[episodeIndex].isWatched
        let key = generateKey(id: tmdbSeriesId, season: seasonNum, episode: episodeNum)
        
        // 3. Estraiamo l'intero MediaItem già aggiornato
        // (Questo oggetto ha già l'episodio con isWatched corretto!)
        let updatedMediaItem = generalCacheContents![itemIndex]
        
        // 4. AGGIORNAMENTO LOGICA KEEP WATCHING
        if let localIndex = keepWatching.firstIndex(where: { $0.id == itemId }) {
            // CASO A: È già in keepWatching.
            // Sostituiamo il vecchio elemento con quello nuovo aggiornato.
            keepWatching[localIndex] = updatedMediaItem
            
            // Opzionale ma consigliato: se toglie la spunta e gli episodi visti tornano a 0,
            // lo rimuoviamo da Continua a Guardare?
            if !isNowWatched && updatedMediaItem.watchedEpisodes == 0 {
                keepWatching.remove(at: localIndex)
            }
            
        } else {
            // CASO B: Non c'è in keepWatching.
            // Se lo ha appena segnato come visto, aggiungiamo l'intera serie (aggiornata).
            if isNowWatched {
                // Lo mettiamo all'inizio della lista (indice 0) perché è il più recente!
                keepWatching.insert(updatedMediaItem, at: 0)
            }
        }
        
        // 5. Aggiornamento Database Supabase (in background)
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
            } catch {
                print("Errore salvataggio episodio DB: \(error)")
            }
        }
    }
    
    /*
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
                        isWatched: watchedSet.contains(key),
                        show_id: ep.showId
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
    
    /// Metodo generale per recuperare i dettagli da Supabase e convertirli in MediaItem
    func fetchDetailedMediaFromDatabase(table: String) async throws -> [MediaItem] {
        
        // 1. Scarichiamo gli "scontrini" da Supabase
        let entries: [PersonalListEntry] = try await SupabaseManager.shared.client
            .from(table)
            .select()
            .execute()
            .value
        
        guard !entries.isEmpty else { return [] }
        
        // 2. Scarichiamo i dettagli da TMDB in parallelo
        let detailedItems = await withTaskGroup(of: MediaItem?.self) { group in
            for entry in entries {
                group.addTask {
                    do {
                        if entry.mediaType == "Film" {
                            // A. Scarica il modello TMDB specifico per i film
                            let movieDetails = try await MovieService.fetchMovieDetails(id: entry.tmdbId)
                            
                            // B. Convertilo nel tuo modello MediaItem per la UI
                            // (Dovrai usare l'inizializzatore corretto che hai creato nella tua struct MediaItem)
                            return MediaItem(movie: movieDetails)
                            
                        } else {
                            // A. Scarica il modello TMDB specifico per le serie (presumo tu abbia una funzione simile)
                            let tvDetails = try await self.movieService.fetchTVDetails(id: entry.tmdbId)
                            
                            // B. Convertilo nel tuo modello MediaItem per la UI
                            return MediaItem(tvShow: tvDetails)
                        }
                    } catch {
                        print("Errore fetch TMDB per ID \(entry.tmdbId): \(error)")
                        return nil // Ignora questo elemento e prosegue con gli altri
                    }
                }
            }
            
            // 3. Raccogliamo tutti i risultati che non sono falliti
            var results: [MediaItem] = []
            for await item in group {
                if let item = item {
                    results.append(item)
                }
            }
            return results
        }
        
        return detailedItems
    }
     */}
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
                                //viewModel.toggleItemWatched(itemId: hero.id)
                            }
                        }
                        
                        CategoryRow(title: "Di tendenza ora", items: viewModel.viewTrendings, viewModel: viewModel)
                        CategoryRow(title: "Continua a guardare", items: viewModel.keepWatching, viewModel: viewModel) .animation(.default, value: viewModel.keepWatching)
                        CategoryRow(title: "La tua lista", items: viewModel.personalList, viewModel: viewModel) .animation(.default, value: viewModel.keepWatching)
                        
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
    
    @State private var image: Image? // L'immagine caricata
    @State private var isLoading = false // Stato caricamento
    
    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color(UIColor.systemGray6))
            
            if let image = image {
                image
                    .resizable()
                    .scaledToFill()
            } else if isLoading {
                ProgressView()
            } else {
                Image(systemName: "photo")
                    .foregroundColor(.gray.opacity(0.3))
            }
        }
        .task(id: urlString) {
            await loadImage()
        }
    }
    
    // Funzione di scaricamento manuale
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

// MARK: - DETAIL VIEW (Con gestione episodi)

    struct DetailView: View {
        let item: MediaItem
        var viewModel: LibraryViewModel
        
        @State private var selectedSeasonId: UUID?
        
        @State private var enrichedItem: MediaItem?
        
        // Troviamo l'item aggiornato dal ViewModel per avere lo stato "live" (reattivo)
        var liveItem: MediaItem {
            if let homeItem = viewModel.viewTrendings.first(where: { $0.id == item.id }) {
                return homeItem
            } else {
                return enrichedItem ?? item //
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
                                    //viewModel.toggleInMyList(itemId: liveItem.id)
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
                                    //viewModel.toggleItemWatched(itemId: liveItem.id)
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
                                //viewModel.toggleInMyList(itemId: liveItem.id)
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
