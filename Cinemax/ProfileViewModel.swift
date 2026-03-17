//
//  ProfileViewModel.swift
//  Cinemax
//
//

import Foundation
import Observation
import Supabase
import SwiftUI

@Observable
class ProfileViewModel {
    var libraryViewModel: LibraryViewModel
    var userEmail: String = "Caricamento..."
    var appVersion: String = config.appVersion
    
    init(libraryViewModel: LibraryViewModel) {
        self.libraryViewModel = libraryViewModel
    }
    
    // MARK: - CALCULATED DATA
    
    // Conta semplicemente quante chiavi in memoria iniziano con "movie_"
    var watchedMoviesCount: Int {
        libraryViewModel.watchedSet.filter { $0.hasPrefix("movie_") }.count
    }
    
    // Conta semplicemente quante chiavi in memoria iniziano con "episode_"
    var watchedEpisodesCount: Int {
        libraryViewModel.watchedSet.filter { $0.hasPrefix("episode_") }.count
    }
        
    func fetchUser() async {
        do {
            let session = try await SupabaseManager.shared.client.auth.session
            await MainActor.run {
                let nickname = session.user.userMetadata["nickname"]?.stringValue ?? session.user.email ?? "Utente sconosciuto"
                self.userEmail = nickname
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
            
            await MainActor.run{
                UserDefaults.standard.set(false, forKey: "isAuthenticated")            }
            
            return true
            
        } catch {
            print("Errore logout: \(error)")
            return false
        }
    }
    
    func deleteUserAccount() async -> Bool {
            do {
                try await SupabaseManager.shared.client.rpc("delete_user_account").execute()
                
                try await SupabaseManager.shared.client.auth.signOut()
                
                return true
            } catch {
                print("Errore durante eliminazione account: \(error)")
                return false
            }
        }
}

// MARK: - PROFILE PAGE LAYOUT
struct ProfileView: View {
    @Environment(ProfileViewModel.self) var vm
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(UIColor.systemBackground).ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 30) {
                        
                        VStack(spacing: 15) {
                            ZStack {
                                Circle().fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 100, height: 100)
                                Text(String(vm.userEmail.prefix(1)).uppercased())
                                    .font(.system(size: 40, weight: .bold)).foregroundStyle(.primary)
                            }.shadow(color: .blue.opacity(0.5), radius: 10)
                            
                            Text(vm.userEmail).font(.title3).bold().foregroundStyle(.primary)
                            Text("Membro Standard").font(.caption).padding(.horizontal, 10).padding(.vertical, 4)
                                .background(.ultraThinMaterial)
                                .cornerRadius(5)
                                .foregroundStyle(.gray)
                        }.padding(.top, 40)
                        
                        Divider().background(Color.gray.opacity(0.5))
                        
                        HStack(spacing: 40) {
                            StatBox(number: vm.watchedMoviesCount, label: "Film Visti")
                            StatBox(number: vm.watchedEpisodesCount, label: "Episodi")
                        }
                        .padding(.vertical)
                        
                        VStack(spacing: 0) {
                            NavigationLink(destination: SettingsView()) { SettingsRow(icon: "gear", title: "Impostazioni App") }
                            Divider().background(Color.gray.opacity(0.2))
                            SettingsRow(icon: "info.circle", title: "Versione App", value: vm.appVersion)
                            Color.clear.frame(height: 40)
                            
                            Button(action: {
                                Task {
                                    if await vm.performLogout() { dismiss() }
                                }
                            }) {
                                HStack {
                                    Image(systemName: "rectangle.portrait.and.arrow.right")
                                    Text("Esci dall'account")
                                }
                                .bold()
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.red.opacity(0.9))
                                .foregroundColor(.white)
                                .cornerRadius(10)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.bottom, 50)
                }
            }
            .navigationTitle("Profilo")
            .navigationBarTitleDisplayMode(.inline)
            .task { await vm.fetchUser() }
        }
    }
}

struct StatBox: View {
    let number: Int
    let label: String
    var body: some View {
        VStack {
            Text("\(number)").font(.title).bold().foregroundStyle(.primary)
            Text(label).font(.caption).foregroundStyle(.gray)
        }
    }
}

struct SettingsRow: View {
    let icon: String
    let title: String
    var value: String? = nil
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.gray)
                .frame(width: 30)
            Text(title)
                .foregroundStyle(.primary)
            Spacer()
            if let v = value {
                Text(v)
                    .foregroundStyle(.gray)
                    .font(.caption)
            }
            else {
                Image(systemName: "chevron.right")
                    .foregroundStyle(.gray)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
    }
}

