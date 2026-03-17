//
//  SearchViewModel.swift
//  Cinemax
//
//
import SwiftUI

@Observable
class SearchViewModel {
    var libraryViewModel: LibraryViewModel
    var query: String = ""
    var results: [MediaItem] = []
    var isLoading: Bool = false
    
    private var searchTask: Task<Void, Never>?
    
    init(libraryViewModel: LibraryViewModel) {
        self.libraryViewModel = libraryViewModel
    }
    
    func performSearch() {
            searchTask?.cancel()
            
            guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
                results = []
                isLoading = false
                return
            }
            
            isLoading = true
            
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 500_000_000)
                
                if Task.isCancelled { return }
                
                do {
                    let tmdbResults = try await MovieService.shared.searchMedia(query: query)
                    
                    let convertedItems = tmdbResults.map { tmdbItem in
                        let tmdbId = tmdbItem.id
                        let isMovie = tmdbItem.mediaType == "movie" || tmdbItem.title != nil
                        
                        let inList = self.libraryViewModel.personalList.contains(where: { $0.tmdbId == tmdbId })
                        
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
                        self.isLoading = false
                    }
                } catch {
                    await MainActor.run {
                        self.results = []
                        self.isLoading = false
                        print("Errore ricerca TMDB: \(error)")
                    }
                }
            }
        }
}
struct SearchView: View {
    var libraryViewModel: LibraryViewModel
    
    @State private var searchVM: SearchViewModel
    
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
                Color(UIColor.systemBackground).ignoresSafeArea()
                
                ScrollView {
                    if searchVM.isLoading {
                        ProgressView()
                            .padding(.top, 50)
                            .controlSize(.large)
                    }
                    
                    LazyVGrid(columns: columns, spacing: 15) {
                        ForEach(searchVM.results) { item in
                            NavigationLink(destination: DetailView(item: item, viewModel: libraryViewModel)) {
                                VStack {
                                    PosterImage(urlString: item.imageName)
                                        .frame(height: 160)
                                        .cornerRadius(8)
                                        .clipped()
                                    
                                    Text(item.title)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Cerca")
            .searchable(text: $searchVM.query, prompt: "Film, serie, generi...")
            .onChange(of: searchVM.query) {
                searchVM.performSearch()
            }
        }
    }
    
}
