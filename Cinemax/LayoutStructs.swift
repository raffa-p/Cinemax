//
//  LayoutStructs.swift
//  Cinemax
//
//

import SwiftUI

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
