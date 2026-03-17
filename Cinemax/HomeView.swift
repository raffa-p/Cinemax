//
//  HomeView.swift
//  Cinemax
//
//

import SwiftUI

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
                        CategoryRow(title: "Continua a guardare", items: viewModel.keepWatching, viewModel: viewModel)
                            .animation(.default, value: viewModel.keepWatching)
                        CategoryRow(title: "La tua lista", items: viewModel.personalList, viewModel: viewModel)
                            .animation(.default, value: viewModel.keepWatching)
                        
                        Spacer(minLength: 100)
                    }
                }
                .ignoresSafeArea(edges: .top)
            }
        }
    }
}
