//
//  SearchViewModel.swift
//  Cinemax
//
//  Created by Raffaele Prota on 19/12/25.
//
import SwiftUI

@Observable
class SearchViewModel {
    var query: String = ""
    var results: [MediaItem] = []
    var isLoading: Bool = false
    
    // Task di ricerca per gestire il "debounce" (ritardo mentre scrivi)
    private var searchTask: Task<Void, Never>?
    
    func performSearch() {
        // Annulla la ricerca precedente se stai ancora scrivendo
        searchTask?.cancel()
        
        // Se la query è vuota, pulisci i risultati
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            results = []
            isLoading = false
            return
        }
        
        isLoading = true
        
        searchTask = Task {
            // Aspetta 0.5 secondi. Se l'utente scrive ancora, questo task viene cancellato
            // e non facciamo la chiamata API (risparmiamo batteria e dati)
            try? await Task.sleep(nanoseconds: 500_000_000)
            
            if Task.isCancelled { return }
            
            do {
                let tmdbResults = try await MovieService.shared.searchMedia(query: query)
                
                // Convertiamo i risultati in MediaItem (stessa logica della Home)
                let convertedItems = tmdbResults.map { tmdbItem in
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
                
                await MainActor.run {
                    self.results = convertedItems
                    self.isLoading = false
                }
            } catch {
                print("Errore ricerca: \(error)")
                await MainActor.run { self.isLoading = false }
            }
        }
    }
}
struct SearchView: View {
    // ViewModel della Home (per gestire i dettagli e i 'visti')
    var libraryViewModel: LibraryViewModel
    
    // ViewModel locale per la ricerca
    @State private var searchVM = SearchViewModel()
    
    // Layout a griglia (3 colonne flessibili)
    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
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
    
    init(libraryViewModel: LibraryViewModel) {
        self.libraryViewModel = libraryViewModel
    }
}
