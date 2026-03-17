//
//  HeroSection.swift
//  Cinemax
//
//

import SwiftUI

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
                    LinearGradient(colors: [.clear, .black.opacity(0.8), .black], startPoint: .center, endPoint: .bottom)
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
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .shadow(color: .black, radius: 10)
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
