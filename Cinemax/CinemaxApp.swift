//
//  CinemaxApp.swift
//  Cinemax
//
//

import SwiftUI
import Supabase

// MARK: - APP ENTRY POINT
@main
struct CinemaxApp: App {
    @AppStorage("isAuthenticated") private var isAuthenticated = false
    @AppStorage("selectedTheme") private var selectedTheme: Theme = .system
    
    var currentScheme: ColorScheme? {
        switch selectedTheme {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil // system settings
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if isAuthenticated {
                    ContentView()
                        .transition(.opacity)
                } else {
                    LoginView(isAuthenticated: $isAuthenticated)
                        .transition(.opacity)
                }
            }
            .preferredColorScheme(currentScheme)
            .task {
                // CONTROLLO SESSIONE ALL'AVVIO
                if let _ = try? await SupabaseManager.shared.client.auth.session.user {
                    isAuthenticated = true
                }
            }
        }
    }
}
