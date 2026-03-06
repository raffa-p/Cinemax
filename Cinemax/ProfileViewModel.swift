//
//  ProfileViewModel.swift
//  Cinemax
//
//  Created by Raffaele Prota on 28/12/25.
//

import Foundation
import Observation
import Supabase

@Observable
class ProfileViewModel {
    var libraryViewModel: LibraryViewModel
    var userEmail: String = "Caricamento..."
    var appVersion: String = "1.0.0"
    
    init(libraryViewModel: LibraryViewModel) {
        self.libraryViewModel = libraryViewModel
    }
    
    // MARK: - STATISTICHE OTTIMIZZATE
    
    // Conta semplicemente quante chiavi in memoria iniziano con "movie_"
    var watchedMoviesCount: Int {
        libraryViewModel.watchedSet.filter { $0.hasPrefix("movie_") }.count
    }
    
    // Conta semplicemente quante chiavi in memoria iniziano con "episode_"
    var watchedEpisodesCount: Int {
        libraryViewModel.watchedSet.filter { $0.hasPrefix("episode_") }.count
    }
    
    // MARK: - LOGICA UTENTE
    
    func fetchUser() async {
        do {
            let session = try await SupabaseManager.shared.client.auth.session
            await MainActor.run {
                self.userEmail = session.user.email ?? "Utente sconosciuto"
            }
        } catch {
            await MainActor.run {
                self.userEmail = "Ospite"
            }
        }
    }
    
    func performLogout() async -> Bool {
        do {
            try await SupabaseManager.shared.client.auth.signOut()
            return true
        } catch {
            print("Errore logout: \(error)")
            return false
        }
    }
}
