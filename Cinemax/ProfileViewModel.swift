//
//  ProfileViewModel.swift
//  Cinemax
//
//

import Foundation
import Observation
import Supabase
import SwiftUI
import PhotosUI
import UIKit

@Observable
class ProfileViewModel {
    var libraryViewModel: LibraryViewModel
    var userEmail: String = "Caricamento..."
    var appVersion: String = config.appVersion
    var isUpdatingNickname: Bool = false
    var errorMessage: String? = nil
    var showError: Bool = false
    var avatarURL: URL? = nil
    var isUploadingAvatar: Bool = false
    
    init(libraryViewModel: LibraryViewModel) {
        self.libraryViewModel = libraryViewModel
    }
    
    // MARK: - CALCULATED DATA
    
    var watchedMoviesCount: Int {
        libraryViewModel.watchedSet.filter { $0.hasPrefix("movie_") }.count
    }
    
    var watchedEpisodesCount: Int {
        libraryViewModel.watchedSet.filter { $0.hasPrefix("episode_") }.count
    }
        
    func fetchUser() async {
        do {
            let session = try await SupabaseManager.shared.client.auth.session
            await MainActor.run {
                let nickname = session.user.userMetadata["nickname"]?.stringValue ?? session.user.email ?? "Utente sconosciuto"
                self.userEmail = nickname
                
                if let avatarString = session.user.userMetadata["avatar_url"]?.stringValue,
                   let url = URL(string: avatarString) {
                    self.avatarURL = url
                }
            }
        } catch {
            await MainActor.run { self.userEmail = "Ospite" }
        }
    }
    
    func uploadAvatar(imageData: Data) async {
            await MainActor.run { isUploadingAvatar = true }
            
            do {
                let user = try await SupabaseManager.shared.client.auth.session.user
                let userId = user.id.uuidString
                let filePath = "\(userId)/profile.jpg"
                
                print("⏳ 2. Inizio upload nel bucket 'avatars' al percorso: \(filePath)...")
                try await SupabaseManager.shared.client.storage
                    .from("avatars")
                    .upload(
                        filePath,
                        data: imageData,
                        options: FileOptions(contentType: "image/jpeg", upsert: true)
                    )
                
                print("Upload fisico riuscito! Generazione URL pubblico...")
                let publicURL = try SupabaseManager.shared.client.storage.from("avatars").getPublicURL(path: filePath)
                let cacheBusterURL = URL(string: "\(publicURL.absoluteString)?t=\(Date().timeIntervalSince1970)")!
                
                print("Salvataggio URL nei metadati dell'utente...")
                let attributes = UserAttributes(data: ["avatar_url": .string(cacheBusterURL.absoluteString)])
                try await SupabaseManager.shared.client.auth.update(user: attributes)
                
                await MainActor.run {
                    self.avatarURL = cacheBusterURL
                    self.isUploadingAvatar = false
                    print("Caricamento completato")
                }
                
            } catch {
                print("ERRORE SUPABASE: \(error)")
                await MainActor.run {
                    self.errorMessage = "Errore caricamento foto: \(error.localizedDescription)"
                    self.showError = true
                    self.isUploadingAvatar = false
                }
            }
        }

    func updateNickname(newName: String) async -> Bool {
        let cleanName = newName.trimmingCharacters(in: .whitespaces)
        guard !cleanName.isEmpty else { return false }
        
        await MainActor.run { isUpdatingNickname = true }
        
        do {
            let attributes = UserAttributes(
                data: ["nickname": .string(cleanName)]
            )
            
            try await SupabaseManager.shared.client.auth.update(user: attributes)
            
            await MainActor.run {
                self.userEmail = cleanName
                self.isUpdatingNickname = false
            }
            return true
            
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.showError = true
                self.isUpdatingNickname = false
            }
            return false
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
    @State private var isEditingNickname = false
    @State private var editNicknameText = ""
    @State private var avatarItem: PhotosPickerItem?
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(UIColor.systemBackground).ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 30) {
                        VStack(spacing: 15) {
                            ZStack {
                                PhotosPicker(selection: $avatarItem, matching: .images) {
                                    ZStack {
                                        if let url = vm.avatarURL {
                                            AsyncImage(url: url) { image in
                                                image
                                                    .resizable()
                                                    .scaledToFill()
                                            } placeholder: {
                                                ProgressView()
                                            }
                                            .frame(width: 100, height: 100)
                                            .clipShape(Circle())
                                            
                                        } else {
                                            ZStack {
                                                Circle()
                                                    .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                                                
                                                Text(String(vm.userEmail.prefix(1)).uppercased())
                                                    .font(.system(size: 40, weight: .bold))
                                                    .foregroundStyle(.white)
                                            }
                                            .frame(width: 100, height: 100)
                                        }
                                        
                                        VStack {
                                            Spacer()
                                            HStack {
                                                Spacer()
                                                Image(systemName: "camera.circle.fill")
                                                    .resizable()
                                                    .frame(width: 30, height: 30)
                                                    .foregroundStyle(.white)
                                                    .background(Color.blue)
                                                    .clipShape(Circle())
                                                    .overlay(Circle().stroke(Color(UIColor.systemBackground), lineWidth: 2))
                                            }
                                        }
                                        .frame(width: 100, height: 100)
                                        
                                        if vm.isUploadingAvatar {
                                            ZStack {
                                                Circle().fill(Color.black.opacity(0.5))
                                                ProgressView().tint(.white)
                                            }
                                            .frame(width: 100, height: 100)
                                        }
                                    }
                                    .shadow(color: .blue.opacity(0.4), radius: 10)
                                }
                                .buttonStyle(.plain)
                                .disabled(vm.isUploadingAvatar)
                                .onChange(of: avatarItem) { oldValue, newValue in
                                    Task {
                                        print("Inizio elaborazione foto...")
                                        guard let item = newValue else { return }
                                        
                                        do {
                                            if let data = try await item.loadTransferable(type: Data.self) {
                                                if let uiImage = UIImage(data: data),
                                                   let jpegData = uiImage.jpegData(compressionQuality: 0.8) {
                                                    print("Immagine convertita in JPEG. Avvio upload a Supabase...")
                                                    await vm.uploadAvatar(imageData: jpegData)
                                                } else {
                                                    print("Impossibile convertire in JPEG. Invio dati originali...")
                                                    await vm.uploadAvatar(imageData: data)
                                                }
                                            } else {
                                                print("Il picker non ha fornito dati.")
                                            }
                                        } catch {
                                            print("Errore PhotosPicker: \(error.localizedDescription)")
                                        }
                                    }
                                }
                            }.shadow(color: .blue.opacity(0.5), radius: 10)
                            
                            if isEditingNickname {
                                HStack {
                                    TextField("Il tuo nickname", text: $editNicknameText)
                                        .textFieldStyle(.roundedBorder)
                                        .autocorrectionDisabled()
                                        .textInputAutocapitalization(.words)
                                    
                                    if vm.isUpdatingNickname {
                                        ProgressView().padding(.horizontal, 5)
                                    } else {
                                        Button("Salva") {
                                            Task {
                                                let success = await vm.updateNickname(newName: editNicknameText)
                                                if success {
                                                    withAnimation { isEditingNickname = false }
                                                }
                                            }
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .tint(.blue)
                                        .disabled(editNicknameText.trimmingCharacters(in: .whitespaces).isEmpty)
                                        
                                        Button("Annulla") {
                                            withAnimation { isEditingNickname = false }
                                        }
                                        .foregroundStyle(.gray)
                                    }
                                }
                                .padding(.horizontal, 40)
                            } else {
                                HStack {
                                    Text(vm.userEmail)
                                        .font(.title3).bold().foregroundStyle(.primary)
                                    
                                    Button {
                                        editNicknameText = vm.userEmail
                                        withAnimation { isEditingNickname = true }
                                    } label: {
                                        Image(systemName: "pencil.circle.fill")
                                            .foregroundStyle(.gray)
                                            .font(.title3)
                                    }
                                }
                            }
                            /*Text("Membro Standard").font(.caption).padding(.horizontal, 10).padding(.vertical, 4)
                                .background(.ultraThinMaterial)
                                .cornerRadius(5)
                                .foregroundStyle(.gray)*/
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
                            Divider().background(Color.gray.opacity(0.2))
                            Link(destination: URL(string: "https://cinemax.netsons.org/privacy")!) {
                                    SettingsRow(icon: "lock.shield", title: "Privacy Policy")
                                }
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

