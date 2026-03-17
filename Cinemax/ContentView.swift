//
//  ContentView.swift
//  Cinemax
//
//

import SwiftUI
    
struct ContentView: View {
    @State private var viewModel = LibraryViewModel()
    @State private var profileVM: ProfileViewModel
    @AppStorage("selectedTheme") private var selectedTheme: Theme = .system
    
    init() {
        let sharedLibrary = LibraryViewModel()
        _profileVM = State(initialValue: ProfileViewModel(libraryViewModel: sharedLibrary))
    }
    
    var body: some View {
        TabView {
            HomeView(viewModel: viewModel)
                .tabItem { Label("Home", systemImage: "house.fill") }
            
            SearchView(libraryViewModel: viewModel)
                .tabItem { Label("Cerca", systemImage: "magnifyingglass") }

            ProfileView()
                .tabItem { Label("Profilo", systemImage: "person.crop.circle") }

        }
        .preferredColorScheme(currentScheme)
        .environment(profileVM)
    }
    var currentScheme: ColorScheme? {
        switch selectedTheme {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }

}





