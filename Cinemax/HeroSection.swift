//
//  HeroSection.swift
//  Cinemax
//
//

import SwiftUI

/// A SwiftUI view that displays a large "hero" section for a `MediaItem`,
/// typically at the top of a screen. It features the item's image, title, type,
/// and an action button or text depending on the media type.
///
/// This section serves as an entry point to the `DetailView` for the media item.
struct HeroSection: View {
    let item: MediaItem
    var viewModel: LibraryViewModel
    var onToggleWatched: () -> Void
    
    var body: some View {
        ZStack(alignment: .bottom) {
            
            NavigationLink(destination: DetailView(item: item, viewModel: viewModel)) {
                ZStack(alignment: .bottom) {
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
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.4), // Inizia a sfumare da metà
                            .init(color: .black.opacity(0.6), location: 0.7),
                            .init(color: .black, location: 1.0)  // Nero solido in fondo
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            VStack(spacing: 16) {
                Text(item.type.rawValue.uppercased())
                    .font(.caption).bold().tracking(2)
                    .foregroundColor(.gray)
                    .allowsHitTesting(false)
                Text(item.title)
                    .font(.system(size: 40, weight: .heavy))
                    .foregroundStyle(.white) // 2. FORZATO IL BIANCO (Il .primary su sfondi chiari in Light Mode diventerebbe nero e illeggibile sul gradiente)
                    .multilineTextAlignment(.center)
                    // 3. DOPPIA OMBRA PER LEGGIBILITÀ ASSOLUTA
                    .shadow(color: .black, radius: 2, x: 0, y: 1) // Ombra netta
                    .shadow(color: .black.opacity(0.8), radius: 15, x: 0, y: 5) // Ombra diffusa
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
