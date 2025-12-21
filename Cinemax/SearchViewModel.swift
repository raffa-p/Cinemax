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
                        description: tmdbItem.overview,
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