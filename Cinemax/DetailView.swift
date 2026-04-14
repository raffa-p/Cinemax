//
//  DetailView.swift
//  Cinemax
//
//

import SwiftUI
import Observation
import Foundation
import Supabase

/// A view that displays the detailed information for a specific `MediaItem`.
///
/// This view handles displaying media details such as title, description, image,
/// match percentage, release year, duration or season count.
/// It also provides functionality to interact with the item, like adding to "My List"
/// or marking as watched, and for series, it allows browsing through seasons and episodes.
///
/// The view dynamically updates its content based on fetched enriched data and user interactions.
struct DetailView: View {
    let item: MediaItem
    @Bindable var viewModel: LibraryViewModel
    
    @State private var selectedSeasonId: UUID?
    @State private var enrichedItem: MediaItem?
    @AppStorage("selectedTheme") private var selectedTheme: Theme = .system
    
    /// A computed property that provides the most up-to-date `MediaItem` for display.
    /// It prioritizes an item found in the `viewModel`'s `generalCacheContents`
    /// (which might reflect real-time updates) or the `enrichedItem` if available,
    /// falling back to the initial `item` if no enriched data is present.
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
        .preferredColorScheme(currentScheme)
        .toolbarRole(.editor)
        .onAppear {
            if selectedSeasonId == nil {
                selectedSeasonId = item.seasons.first?.id
            }
            if !viewModel.generalCacheContents.contains(where: { $0.tmdbId == item.tmdbId }) {
                viewModel.generalCacheContents.append(item)
            }
        }
        .alert("Episodi precedenti saltati", isPresented: $viewModel.showCatchUpAlert) {
            Button("Segna tutti come visti") {
                viewModel.markEpisodeAndAllPreviousAsWatched()
            }
            Button("Solo questo episodio") {
                if let data = viewModel.pendingEpisodeData {
                    viewModel.executeToggleEpisodeWatched(itemId: data.itemId, seasonId: data.seasonId, episodeId: data.episodeId)
                }
            }
            Button("Annulla", role: .cancel) {
                viewModel.pendingEpisodeData = nil
            }
        } message: {
            Text("Sembra che tu non abbia segnato alcuni episodi precedenti come visti. Vuoi aggiornarli automaticamente?")
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
    
    
    /// A computed property that determines the `ColorScheme?` based on the `selectedTheme`.
    /// Returns `.light` for light theme, `.dark` for dark theme, and `nil` for system theme.
    var currentScheme: ColorScheme? {
        switch selectedTheme {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }
    
    /// A private `View` builder that displays the header image for the `MediaItem`.
    /// It fetches the image asynchronously and displays a placeholder if the image fails to load.
    /// It includes an overlay gradient for better text readability.
    private var headerImage: some View {
        ZStack(alignment: .bottom) {
            if let url = URL(string: liveItem.imageName) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 300)
                            .clipped()
                            .overlay(LinearGradient(colors: [.clear, .black.opacity(0.8), .black], startPoint: .center, endPoint: .bottom))
                    case .failure, .empty:
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 300)
                    @unknown default: EmptyView()
                    }
                }
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 300)
            }
        }
        .frame(height: 300)
    }
    
    /// A private `View` builder that displays the title and essential metadata of the `MediaItem`.
    /// This includes the title, match percentage, release year, and either the number of seasons
    /// (for series) or the duration (for movies).
    private var titleAndMetadata: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(liveItem.title)
                .font(.largeTitle)
                .bold()
                .foregroundStyle(.primary)
                .shadow(color: .black, radius: 10)
            
            HStack {
                Text("\(liveItem.matchPercentage)% Match")
                    .foregroundStyle(.green)
                    .bold()
                Text(liveItem.year)
                    .foregroundStyle(.gray)
                if liveItem.type == .series {
                    Text("\(liveItem.seasons.count) Stagioni")
                        .foregroundStyle(.gray)
                } else {
                    Text(liveItem.duration ?? "Caricamento...")
                        .foregroundStyle(.gray)
                }
            }
            .font(.subheadline)
        }
    }
    
    /// A private `View` builder that presents interactive action buttons for the `MediaItem`.
    /// Includes a button to toggle the item's presence in "My List" and, for movies,
    /// a button to toggle its watched status.
    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 12) {
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
                    .background(liveItem.inMyList ? Color.green : Color.gray.opacity(0.2))
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
                        Image(systemName: liveItem.isWatched ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                        Text(liveItem.isWatched ? "Già visto" : "Segna come visto")
                            .fontWeight(.bold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        liveItem.isWatched ? Color.green :
                        (currentScheme == .light ? Color.gray.opacity(0.2) : Color.white.opacity(0.1))
                    )
                    .foregroundColor(liveItem.isWatched ? .white : .black)
                    .cornerRadius(8)
                }
                .padding(.vertical, 5)
            }
        }
    }
    
    /// A private `View` builder that displays the episodes section for `series` type `MediaItem`.
    /// If the item is a series and has seasons, it provides a scrollable list of season buttons
    /// and then lists the episodes for the selected season.
    @ViewBuilder
    private var episodesSection: some View {
        if liveItem.type == .series && !liveItem.seasons.isEmpty {
            Divider()
                .background(.ultraThinMaterial)
                .padding(.vertical)
            
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
            
            if let season = liveItem.seasons.first(where: { $0.id == (selectedSeasonId ?? liveItem.seasons.first?.id) }) {
                ForEach(season.episodes) { episode in
                    episodeRow(season: season, episode: episode)
                }
            }
        }
    }
    
    /// A private helper function that constructs a view for a single episode row.
    /// Displays the episode's image, duration, number, title, plot, and a button
    /// to toggle its watched status.
    ///
    /// - Parameters:
    ///   - season: The `Season` object to which the episode belongs.
    ///   - episode: The `Episode` object to be displayed in the row.
    /// - Returns: A `View` representing a single episode row.
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
                Text(episode.duration)
                    .font(.caption2)
                    .bold()
                    .foregroundColor(.white)
                    .padding(4)
                    .background(.ultraThinMaterial)
                    .cornerRadius(2)
                    .padding(4),
                    alignment: .bottomLeading
            )
            
            VStack(alignment: .leading, spacing: 4) {
                Text("\(episode.number). \(episode.title)")
                    .font(.subheadline)
                    .bold()
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(episode.plot)
                    .font(.caption)
                    .foregroundStyle(.gray)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Button(action: {
                let newState = !episode.isWatched
                if let enriched = enrichedItem, enriched.id == liveItem.id {
                    if let sIndex = enriched.seasons.firstIndex(where: { $0.id == season.id }),
                       let eIndex = enriched.seasons[sIndex].episodes.firstIndex(where: { $0.id == episode.id }) {
                        enrichedItem?.seasons[sIndex].episodes[eIndex].isWatched = newState
                    }
                }
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
