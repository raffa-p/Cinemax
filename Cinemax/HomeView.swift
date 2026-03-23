//
//  HomeView.swift
//  Cinemax
//
//

import SwiftUI

/// `HomeView` serves as the main entry point for displaying movie content within the Cinemax application.
/// It utilizes a `LibraryViewModel` to manage and present different categories of movies,
/// including a hero movie, trending titles, "keep watching" items, and a personal list.
/// The view orchestrates various UI components like `HeroSection` and `CategoryRow`
/// to provide a comprehensive browsing experience for the user.
///
/// - Important: This view relies heavily on `LibraryViewModel` for all its data.
///
/// - Properties:
///   - `viewModel`: An instance of `LibraryViewModel` responsible for providing movie data and handling user interactions.
///
/// - Body:
///   - Displays a `NavigationStack` for navigation capabilities.
///   - Uses a `ZStack` to layer a background color behind the scrollable content.
///   - A `ScrollView` contains a `VStack` that lays out the different sections:
///     - A `HeroSection` displaying a prominent movie, if available from `viewModel.heroMovie`.
///     - A `CategoryRow` for "Di tendenza ora" (Trending now), populated by `viewModel.viewTrendings`.
///     - An optional `CategoryRow` for "Continua a guardare" (Keep watching), shown only if `viewModel.keepWatching` is not empty.
///     - An optional `CategoryRow` for "La tua lista" (Your list), shown if either `viewModel.personalList` or `viewModel.personalListSet` is not empty.
///   - Includes a `Spacer` at the bottom to provide visual padding.
struct HomeView: View {
    var viewModel: LibraryViewModel
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(UIColor.systemBackground).ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        
                        if let hero = viewModel.heroMovie {
                            HeroSection(item: hero, viewModel: viewModel) {
                                viewModel.toggleItemWatched(itemId: hero.id)
                            }
                        }
                        
                        CategoryRow(title: "Di tendenza ora", items: viewModel.viewTrendings, viewModel: viewModel)
                        if !viewModel.keepWatching.isEmpty {
                            CategoryRow(title: "Continua a guardare", items: viewModel.keepWatching, viewModel: viewModel)
                                .animation(.default, value: viewModel.keepWatching)
                        }
                        if !viewModel.personalList.isEmpty || !viewModel.personalListSet.isEmpty {
                            CategoryRow(title: "La tua lista", items: viewModel.personalList, viewModel: viewModel)
                                .animation(.default, value: viewModel.keepWatching)
                        }
                        
                        Spacer(minLength: 100)
                    }
                }
                .ignoresSafeArea(edges: .top)
            }
        }
    }
}
