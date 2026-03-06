//
//  SearchViewModel.swift
//  Cinemax
//
//  Created by Raffaele Prota on 19/12/25.
//
import SwiftUI

@Observable
class SearchViewModel {
    var libraryViewModel: LibraryViewModel
    var query: String = ""
    var results: [MediaItem] = []
    var isLoading: Bool = false
    
    // Task di ricerca per gestire il "debounce" (ritardo mentre scrivi)
    private var searchTask: Task<Void, Never>?
    
    init(libraryViewModel: LibraryViewModel) {
        self.libraryViewModel = libraryViewModel
    }
    
    func performSearch() {
            // Annulla la ricerca precedente se stai ancora scrivendo
            searchTask?.cancel()
            
            // Se la query è vuota, pulisci i risultati e spegni il caricamento
            guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
                results = []
                isLoading = false
                return
            }
            
            isLoading = true // Accendiamo la rotellina!
            
            searchTask = Task {
                // Aspetta 0.5 secondi (debounce)
                try? await Task.sleep(nanoseconds: 500_000_000)
                
                if Task.isCancelled { return }
                
                do {
                    let tmdbResults = try await MovieService.shared.searchMedia(query: query)
                    
                    // Convertiamo i risultati in MediaItem (sincronizzando i dati!)
                    let convertedItems = tmdbResults.map { tmdbItem in
                        let tmdbId = tmdbItem.id
                        let isMovie = tmdbItem.mediaType == "movie" || tmdbItem.title != nil
                        
                        // A. Controlliamo se è già nella nostra Lista Personale
                        let inList = self.libraryViewModel.personalList.contains(where: { $0.tmdbId == tmdbId })
                        
                        // B. Controlliamo se è un Film che abbiamo già visto
                        var isWatched = false
                        if isMovie {
                            let key = "movie_\(tmdbId)"
                            isWatched = self.libraryViewModel.watchedSet.contains(key)
                        }
                        
                        return MediaItem(
                            tmdbId: tmdbId,
                            title: tmdbItem.displayTitle,
                            imageName: tmdbItem.fullPosterURL?.absoluteString ?? "",
                            type: isMovie ? .movie : .series,
                            matchPercentage: Int((tmdbItem.voteAverage ?? 0) * 10),
                            year: tmdbItem.displayYear,
                            description: tmdbItem.overview ?? "Nessuna trama disponibile",
                            isWatched: isWatched,
                            inMyList: inList,
                            seasons: []
                        )
                    }
                    
                    await MainActor.run {
                        self.results = convertedItems
                        self.isLoading = false // 🛑 SPEGNIAMO LA ROTELLA QUI! (Ricerca completata)
                    }
                } catch {
                    await MainActor.run {
                        self.results = []
                        self.isLoading = false // 🛑 SPEGNIAMO LA ROTELLA ANCHE QUI! (Ricerca fallita)
                        print("Errore ricerca TMDB: \(error)")
                    }
                }
            }
        }
}
struct SearchView: View {
    // ViewModel della Home (per gestire i dettagli e i 'visti')
    var libraryViewModel: LibraryViewModel
    
    // ViewModel locale per la ricerca
    @State private var searchVM: SearchViewModel
    
    // Layout a griglia (3 colonne flessibili)
    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    init(libraryViewModel: LibraryViewModel) {
        self.libraryViewModel = libraryViewModel
        _searchVM = State(initialValue: SearchViewModel(libraryViewModel: libraryViewModel))
    }
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                ScrollView {
                    // SE STA CARICANDO
                    if searchVM.isLoading {
                        ProgressView()
                            .padding(.top, 50)
                            .controlSize(.large)
                    }
                    
                    // GRIGLIA RISULTATI
                    LazyVGrid(columns: columns, spacing: 15) {
                        ForEach(searchVM.results) { item in
                            NavigationLink(destination: DetailView(item: item, viewModel: libraryViewModel)) {
                                VStack {
                                    // Usiamo la nostra nuova PosterImage robusta
                                    PosterImage(urlString: item.imageName)
                                        .frame(height: 160)
                                        .cornerRadius(8)
                                        .clipped()
                                    
                                    Text(item.title)
                                        .font(.caption)
                                        .foregroundStyle(.gray)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Cerca")
            .preferredColorScheme(.dark)
            // BARRA DI RICERCA NATIVA
            .searchable(text: $searchVM.query, prompt: "Film, serie, generi...")
            // QUANDO IL TESTO CAMBIA -> CERCA
            .onChange(of: searchVM.query) {
                searchVM.performSearch()
            }
        }
    }
    
}
