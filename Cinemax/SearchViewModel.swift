//
//  SearchViewModel.swift
//  Cinemax
//
//
import SwiftUI

/// A view model responsible for handling search functionality within the Cinemax app.
/// 
/// SearchViewModel orchestrates the search flow for movies and TV series by:
/// - Debouncing user input using a cancellable Task to avoid firing excessive network requests
/// - Querying the remote TMDB-backed MovieService for mixed media results
/// - Converting raw TMDB results into the app’s `MediaItem` model, enriching each item with:
///   - Watched status (for movies) derived from `LibraryViewModel`’s `watchedSet`
///   - Presence in the user’s personal list via `LibraryViewModel`’s `personalList`
/// - Publishing loading state and results to drive the UI
///
/// It is annotated with `@Observable`, enabling SwiftUI to react to changes in its published properties.
///
/// Usage:
/// - Initialize with an instance of `LibraryViewModel`.
/// - Bind `query` to a SwiftUI `.searchable` modifier.
/// - Call `performSearch()` on query changes to trigger a debounced search.
///
/// Properties:
/// - `libraryViewModel`: The shared library state used to compute watched/list membership.
/// - `query`: The current search text; trimmed empty queries clear results and stop loading.
/// - `results`: The latest array of `MediaItem` mapped from TMDB responses.
/// - `isLoading`: Indicates whether a search is in progress; suitable for showing a spinner.
/// - `searchTask`: The current cancellable search task used for debouncing.
///
/// Behavior:
/// - Empty or whitespace-only queries reset `results` and set `isLoading` to false.
/// - On successful fetch, results are mapped and published on the main actor.
/// - On failure, results are cleared, loading is reset, and the error is logged.
///
/// Dependencies:
/// - `LibraryViewModel` for personal list and watched state
/// - `MovieService.shared.searchMedia(query:)` for remote search
/// - `MediaItem` model for UI consumption
///
/// Notes:
/// - Watched status is currently computed only for movies using the key format `movie_<tmdbId>`.
/// - Media type inference prefers TMDB’s `mediaType == "movie"` or presence of a `title`.
/// - If a poster URL is unavailable, `imageName` is set to an empty string.
/// - If an overview is missing, a localized fallback description is provided ("Nessuna trama disponibile").
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
    
    /// Performs a debounced search against TMDB and updates published state accordingly.
    ///
    /// Behavior:
    /// - Queries `MovieService.shared.searchMedia(query:)` with the current `query`.
    /// - Converts TMDB results into `MediaItem` values, enriching each with:
    ///   - `inMyList` by checking `libraryViewModel.personalList`
    ///   - `isWatched` for movies using `libraryViewModel.watchedSet` with key format `movie_<tmdbId>`
    /// - Publishes `results` and `isLoading` updates on the main actor.
    ///
    /// Cancellation:
    /// - The previous `searchTask` is cancelled before starting a new one.
    /// - The task checks `Task.isCancelled` after the debounce delay to early-exit if needed.
    ///
    /// Error handling:
    /// - On error, clears results, stops loading, and logs the underlying error.
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

/// A SwiftUI view that provides a searchable interface for discovering movies and TV series.
/// 
/// SearchView composes the search UI and binds it to a `SearchViewModel` to handle:
/// - Debounced querying of TMDB-backed content
/// - Presenting results in a responsive grid with navigation to a detail screen
///
/// Responsibilities:
/// - Hosts a `NavigationStack` with a search field via `.searchable`
/// - Displays a `ProgressView` when `searchVM.isLoading` is true
/// - Renders search results in a `LazyVGrid` with three flexible columns
/// - Navigates to `DetailView` when a result is selected
///
/// Dependencies:
/// - `LibraryViewModel`: Shared state for personal list and watched status, passed to both the view and its internal `SearchViewModel`
/// - `SearchViewModel`: Manages the search query, loading state, and mapped `MediaItem` results
/// - `PosterImage`: Asynchronously loads and displays poster images
/// - `DetailView`: Destination view for presenting detailed information about a selected item
///
/// Initialization:
/// - Requires a `LibraryViewModel` instance
/// - Initializes an internal `SearchViewModel` using the provided `LibraryViewModel`
///
/// User Interaction:
/// - The search text is bound to `searchVM.query`
/// - Changes to the query trigger `searchVM.performSearch()` with debounce behavior handled by the view model
///
/// Notes:
/// - The view model is stored in `@State` to maintain its lifecycle within the view.
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
