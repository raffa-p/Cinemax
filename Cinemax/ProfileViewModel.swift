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
    // Riferimento al ViewModel principale per calcolare le statistiche
    var libraryViewModel: LibraryViewModel
    
    // Dati dell'utente
    var userEmail: String = "Caricamento..."
    var appVersion: String = "1.0.0"
    
    // Inizializzatore
    init(libraryViewModel: LibraryViewModel) {
        self.libraryViewModel = libraryViewModel
    }
    
    // MARK: - Computed Properties (Statistiche)
    
    var watchedMoviesCount: Int {
        libraryViewModel.items.filter { $0.type == .movie && $0.isWatched }.count
    }
    
    var watchedEpisodesCount: Int {
        libraryViewModel.items.reduce(0) { total, item in
            total + item.watchedEpisodes
        }
    }
    
    // MARK: - Funzioni
    
    func fetchUser() async {
        do {
            let session = try await SupabaseManager.shared.client.auth.session
            // Aggiorniamo l'UI sul thread principale
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
