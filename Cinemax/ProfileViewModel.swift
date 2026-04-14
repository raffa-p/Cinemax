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
import Playgrounds

/// A view model responsible for managing the user's profile data and actions within the app.
/// 
/// Responsibilities:
/// - Fetching and exposing the authenticated user's display information (nickname/email) and avatar URL
/// - Computing profile-related statistics sourced from the library (e.g., watched movies/episodes)
/// - Handling profile updates such as changing the nickname and uploading a new avatar
/// - Managing authentication-related actions including logout and account deletion
/// - Surfacing user-facing state such as loading indicators and error messages
///
/// Dependencies:
/// - Depends on `LibraryViewModel` to compute watched counts
/// - Uses `SupabaseManager` to interact with Supabase Auth and Storage
/// - Uses Swift Concurrency to ensure UI updates occur on the main actor
///
/// Key Properties:
/// - `libraryViewModel`: Source for watched content data
/// - `userEmail`: Displays the user's nickname (or email as fallback)
/// - `appVersion`: App version string from configuration
/// - `isUpdatingNickname`: Indicates an in-flight nickname update
/// - `errorMessage` / `showError`: Error reporting state
/// - `avatarURL`: Public URL to the user's avatar image
/// - `isUploadingAvatar`: Indicates an in-flight avatar upload
///
/// Computed Statistics:
/// - `watchedMoviesCount`: Number of watched items with "movie_" prefix
/// - `watchedEpisodesCount`: Number of watched items with "episode_" prefix
///
/// Async Methods:
/// - `fetchUser()`: Loads the current user's metadata (nickname and avatar URL)
/// - `uploadAvatar(imageData:)`: Uploads an avatar to Supabase Storage, updates user metadata,
///   and appends a cache-busting query to the public URL
/// - `updateNickname(newName:)`: Validates and updates the user's nickname in Supabase metadata
/// - `performLogout()`: Signs out the current user and updates local authentication state
/// - `deleteUserAccount()`: Calls a Supabase RPC to delete the account, then signs out
///
/// Threading:
/// - Uses `MainActor.run` to safely update observable properties that drive the UI
///
/// Error Handling:
/// - Catches and stores errors for display to the user
/// - Provides boolean return values to signal operation success/failure to the caller
///
/// Usage:
/// - Instantiate with a `LibraryViewModel`
/// - Bind UI to observable properties for live updates
/// - Call async methods from UI actions within `Task` contexts
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
    let apiSupabase = SupabaseInterface()

    
    init(libraryViewModel: LibraryViewModel) {
        self.libraryViewModel = libraryViewModel
    }
        
    /// Fetches the authenticated user's display information (nickname or email) and avatar URL from Supabase.
    ///
    /// This method performs the following steps:
    /// 1. Attempts to retrieve the current user session from `SupabaseManager.shared.client.auth`.
    /// 2. If a session is found, it updates the `userEmail` with the user's nickname (if available in `userMetadata`),
    ///    falling back to the email, or "Utente sconosciuto" if neither is present.
    /// 3. It also attempts to parse an `avatar_url` from the user's metadata and sets the `avatarURL` property.
    /// 4. All UI-related updates (`userEmail`, `avatarURL`) are performed on the `MainActor` to ensure thread safety.
    /// 5. In case of an error during session retrieval, `userEmail` is set to "Ospite".
    ///
    /// - Important: This method modifies the observable properties `userEmail` and `avatarURL`.
    /// - Throws: An error if there's an issue fetching the Supabase session, though it's caught internally.
    /// - Returns: `Void`. The observable properties are updated directly.
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
    
    /// Uploads an avatar image to Supabase Storage, updates the user's metadata with the new avatar URL,
    /// and incorporates a cache-busting parameter to ensure fresh image retrieval.
    ///
    /// This method performs the following steps:
    /// 1. Sets `isUploadingAvatar` to `true` to indicate an ongoing upload operation.
    /// 2. Retrieves the current user's ID to construct a unique file path in the `avatars` bucket.
    ///    The path is typically `userId/profile.jpg`.
    /// 3. Uploads the provided `imageData` to Supabase Storage, specifying `image/jpeg` content type
    ///    and enabling `upsert` to overwrite existing files.
    /// 4. Once the upload is successful, it retrieves the public URL for the uploaded image.
    /// 5. Appends a cache-busting query parameter (`?t=timestamp`) to the public URL to ensure
    ///    that SwiftUI's `AsyncImage` reloads the image after an update.
    /// 6. Updates the user's metadata in Supabase Auth, setting the `avatar_url` to the new cache-busted URL.
    /// 7. Updates the observable `avatarURL` property with the new URL and sets `isUploadingAvatar` to `false`.
    /// 8. All UI-related updates (`isUploadingAvatar`, `avatarURL`, `errorMessage`, `showError`)
    ///    are performed on the `MainActor` to ensure thread safety.
    ///
    /// - Parameter imageData: The `Data` representation of the image to be uploaded, preferably JPEG.
    ///
    /// - Important: If the `imageData` cannot be converted to JPEG within the `PhotosPicker` `onChange` handler,
    ///   the original data is sent. It's recommended to ensure `imageData` is in a suitable format (e.g., JPEG)
    ///   before calling this method for optimal storage and display.
    /// - Throws: An error if there's an issue with fetching the user session, uploading to Supabase Storage,
    ///   retrieving the public URL, or updating user metadata. Errors are caught internally and
    ///   `errorMessage` and `showError` are updated for UI feedback.
    /// - Returns: `Void`. Observable properties are updated directly.
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

    /// Updates the authenticated user's nickname in Supabase and locally within the view model.
    ///
    /// This method performs the following steps:
    /// 1. Trims leading and trailing whitespace from the `newName`.
    /// 2. Validates that the `newName` is not empty after trimming; if empty, the update is not performed.
    /// 3. Sets `isUpdatingNickname` to `true` to indicate an ongoing operation.
    /// 4. Constructs `UserAttributes` with the new nickname.
    /// 5. Calls `SupabaseManager.shared.client.auth.update` to persist the nickname change in Supabase.
    /// 6. Upon successful update, it updates the observable `userEmail` property with the new nickname
    ///    and sets `isUpdatingNickname` to `false`.
    /// 7. All UI-related updates (`isUpdatingNickname`, `userEmail`, `errorMessage`, `showError`)
    ///    are performed on the `MainActor` to ensure thread safety.
    ///
    /// - Parameter newName: The desired new nickname as a `String`.
    /// - Returns: `true` if the nickname was successfully updated, `false` otherwise (e.g., if the new name is empty
    ///   or an error occurs during the Supabase call).
    /// - Throws: An error if there's an issue with updating the user's metadata in Supabase. Errors are caught
    ///   internally, and `errorMessage` and `showError` are updated for UI feedback.
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
    
    /// Performs a logout operation, signing out the current user from Supabase and updating local authentication state.
    ///
    /// This method performs the following steps:
    /// 1. Calls `SupabaseManager.shared.client.auth.signOut()` to terminate the user's session with Supabase.
    /// 2. Upon successful sign-out, it updates `UserDefaults.standard` to set the `isAuthenticated` flag to `false`,
    ///    ensuring that the application's local state reflects the user's logged-out status. This update is performed
    ///    on the `MainActor` for thread safety.
    /// 3. If any error occurs during the sign-out process, the error is caught, printed to the console,
    ///    and the method returns `false`.
    ///
    /// - Returns: `true` if the logout operation was successful, `false` otherwise.
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
    
    /// Deletes the authenticated user's account from Supabase and subsequently signs out the user.
    ///
    /// This method performs the following steps:
    /// 1. Invokes a Supabase Remote Procedure Call (RPC) named `"delete_user_account"`. This RPC
    ///    is assumed to handle the server-side logic for account deletion (e.g., removing user data,
    ///    profiles, etc.).
    /// 2. If the RPC call is successful, it then performs a sign-out operation using
    ///    `SupabaseManager.shared.client.auth.signOut()` to terminate the user's local session.
    /// 3. In case of any error during the RPC execution or sign-out process, the error is caught,
    ///    printed to the console, and the method returns `false`.
    ///
    /// - Important: The successful execution of the `"delete_user_account"` RPC is crucial for
    ///   the complete removal of the user's data. This client-side function relies on that RPC
    ///   to handle the actual deletion logic on the backend.
    ///
    /// - Returns: `true` if both the account deletion RPC and the subsequent sign-out operation
    ///   were successful, `false` otherwise.
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
    
    @discardableResult
    func loadHistory() async -> Bool {
        do {
            let downloadedHistory = try await apiSupabase.loadWatched()
            print("Cronologia scaricata! Trovati: \(downloadedHistory.count) elementi.")
            await MainActor.run {
                self.libraryViewModel.history = downloadedHistory
            }
            return true
        } catch {
            print("Errore caricamento cronologia visioni: \(error)")
            return false
        }
    }
}

// MARK: - PROFILE PAGE LAYOUT
/// A SwiftUI `View` that displays the user's profile information, allows for editing
/// their nickname and avatar, and provides options for viewing statistics,
/// app settings, logging out, and deleting the account.
///
/// This view acts as the main interface for user profile management. It observes
/// changes in `ProfileViewModel` to display dynamic content such as the user's
/// nickname, avatar, and watched content counts.
///
/// **Features:**
/// - **User Avatar:** Displays the user's profile picture, with a fallback to a
///   gradient circle showing the first letter of their nickname. Users can tap
///   to select a new image from `PhotosPicker`.
/// - **Nickname Editing:** Allows users to edit their nickname directly within
///   the view. The changes are saved via `ProfileViewModel`.
/// - **Watched Statistics:** Shows the count of watched movies and episodes,
///   sourced from the `ProfileViewModel`.
/// - **App Information:** Displays the app version and provides a link to the
///   privacy policy.
/// - **Account Actions:** Includes buttons for logging out and deleting the user's
///   account, which trigger corresponding actions in `ProfileViewModel`.
///
/// **Dependencies:**
/// - Relies on `ProfileViewModel` (injected via `@Environment`) for all business
///   logic, data fetching, and state management.
/// - Uses `PhotosPicker` for avatar image selection.
/// - Uses `UIImage` for image processing before uploading.
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
                        
                        if vm.libraryViewModel.history.count > 0 {
                            VStack(alignment: .leading, spacing: 15) {
                                Text("Cronologia Visioni")
                                    .font(.title3)
                                    .bold()
                                    .padding(.horizontal)
                                
                                ScrollView(.horizontal, showsIndicators: false) {
                                    LazyHStack(spacing: 15) {
                                        ForEach(vm.libraryViewModel.history) { item in
                                            VStack(alignment: .leading) {
                                                
                                                AsyncImage(url: URL(string: item.imageName)) { image in
                                                    image.resizable().scaledToFill()
                                                } placeholder: {
                                                    Rectangle().fill(Color.gray.opacity(0.3))
                                                }
                                                .frame(width: 110, height: 160)
                                                .cornerRadius(10)
                                                
                                                Text(item.title)
                                                    .font(.caption)
                                                    .lineLimit(1)
                                                    .frame(width: 110, alignment: .leading)
                                            }
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                            }
                            .padding(.bottom, 20)
                        }
                        
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
            .task {
                await vm.fetchUser()
                await vm.loadHistory()
            }
        }
    }
    
    
}

/// A SwiftUI `View` that displays a numerical statistic with a corresponding label.
/// - Returns: A `View` displaying the number and label.
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

/// A SwiftUI `View` that displays a single row item for a settings or profile section.
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


#Playground {
let libraryVM = LibraryViewModel()
    let profileViewModel = ProfileViewModel(libraryViewModel: libraryVM)
    let sampleImageData = UIImage(systemName: "photo")!.jpegData(compressionQuality: 0.8)!
    
    Task {
        await profileViewModel.uploadAvatar(imageData: sampleImageData)
    }
}

