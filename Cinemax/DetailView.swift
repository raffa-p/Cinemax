//
//  DetailView.swift
//  Cinemax
//
//

import SwiftUI
import Observation
import Foundation
import Supabase

struct DetailView: View {
    let item: MediaItem
    var viewModel: LibraryViewModel
    
    @State private var selectedSeasonId: UUID?
    @State private var enrichedItem: MediaItem?
    @AppStorage("selectedTheme") private var selectedTheme: Theme = .system
    
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
    
    var currentScheme: ColorScheme? {
        switch selectedTheme {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }
    
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
                if var enriched = enrichedItem, enriched.id == liveItem.id {
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
