//
//  ContentView.swift
//  Cinemax
//
//

import SwiftUI
    
/// `ContentView` serves as the root view of the Cinemax application, orchestrating the primary navigation through a `TabView`.
/// It manages the main data models (`LibraryViewModel` and `ProfileViewModel`) and applies the user's selected theme.
///
/// This view initializes and provides access to shared view models across different tabs,
/// ensuring a consistent data flow for content display, search, and user profile management.
///
struct ContentView: View {
    @State private var viewModel = LibraryViewModel()
    @State private var profileVM: ProfileViewModel
    @AppStorage("selectedTheme") private var selectedTheme: Theme = .system
    
    init() {
        let sharedLibrary = LibraryViewModel()
        _profileVM = State(initialValue: ProfileViewModel(libraryViewModel: sharedLibrary))
    }
    
    /// The main content and layout for `ContentView`.
    ///
    /// This body defines a `TabView` with three main sections:
    /// - `HomeView`: Displays featured content.
    /// - `SearchView`: Allows users to search the content library.
    /// - `ProfileView`: Manages user-specific information and settings.
    ///
    /// It also applies the global color scheme based on `selectedTheme` and
    /// makes `profileVM` available to child views via the environment.
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
    
    /// Computes the appropriate `ColorScheme` to apply to the application.
    ///
    /// This property translates the `selectedTheme` preference into a `ColorScheme?` value:
    /// - `.light` maps to `.light`
    /// - `.dark` maps to `.dark`
    /// - `.system` maps to `nil`, indicating the system's default color scheme should be used.
    var currentScheme: ColorScheme? {
        switch selectedTheme {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }
}
