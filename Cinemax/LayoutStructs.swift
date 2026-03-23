//
//  LayoutStructs.swift
//  Cinemax
//
//

import SwiftUI

/// A view that displays a horizontal scrollable row of media items under a category title.
///
/// This view is designed to showcase a collection of `MediaItem` instances,
/// typically representing a specific category or genre, within a horizontal scroll view.
/// Each item in the row is presented using a `MediaCard` and is wrapped in a `NavigationLink`
/// to a `DetailView`.
struct CategoryRow: View {
    let title: String
    let items: [MediaItem]
    var viewModel: LibraryViewModel
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.headline)
                .bold()
                .foregroundStyle(.primary)
                .padding(.horizontal)
            
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

/// A view that asynchronously loads and displays an image from a given URL.
///
/// This view handles the entire process of fetching an image from a remote URL,
/// displaying a placeholder while loading, and then presenting the fetched image.
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
                Image(systemName: "photo")
                    .foregroundColor(.gray.opacity(0.3))
            }
        }
        .task(id: urlString) {
            await loadImage()
        }
    }
    
    /// Asynchronously loads the image from the `urlString`.
    ///
    /// This method performs a network request to fetch image data.
    /// Upon successful download, it updates the `image` state variable,
    /// triggering a view refresh. It handles network errors by printing them
    /// to the console, excluding cancellation errors.
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
                print("Errore download manuale [\(urlString)]: \(error.localizedDescription)")
            }
        }
        isLoading = false
    }
}

/// A view that displays a media item as a card, including its poster image and optional progress.
///
/// This view is responsible for rendering a `MediaItem` in a compact card format,
/// suitable for display within collections like `CategoryRow`. It uses `PosterImage`
/// to load and display the media item's poster and can optionally show a progress bar
/// for series items.
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
