//
//  SettingsView.swift
//  Cinemax
//
//

import SwiftUI
import Foundation

/// Represents the visual appearance options available in the app.
///
/// Users can select a specific theme or inherit the system-wide setting.
///
/// - Note: The raw values are localized (Italian) labels used for display:
///   - `light`: "Chiaro"
///   - `dark`: "Scuro"
///   - `system`: "Sistema"
///
/// Conforms to:
/// - `CaseIterable` to allow iterating over all themes (e.g., for pickers).
/// - `Identifiable` to uniquely identify each case via its localized raw value.
/// - `RawRepresentable` with `String` raw values for display and persistence.
///
/// Cases:
/// - `light`: Forces a light appearance throughout the app.
/// - `dark`: Forces a dark appearance throughout the app.
/// - `system`: Follows the device’s current appearance setting.
enum Theme: String, CaseIterable, Identifiable {
    case light = "Chiaro"
    case dark = "Scuro"
    case system = "Sistema"
    var id: String { self.rawValue }
}

/// A SwiftUI view that presents the app's settings organized into sections, including appearance, preferences, and account management.
///
/// Features:
/// - Appearance:
///   - Users can choose a visual theme for the app using a picker:
///     - Light ("Chiaro")
///     - Dark ("Scuro")
///     - System ("Sistema")
///   - The selection is persisted using `@AppStorage("selectedTheme")`.
///
/// - Preferences:
///   - Displays a placeholder toggle for push notifications (currently disabled and non-functional).
///   - Informs users that notifications will be available in future updates.
///
/// - Account:
///   - Provides a destructive action to delete the user account.
///   - Shows a confirmation alert before proceeding with deletion.
///   - On successful deletion, updates authentication state (`@AppStorage("isAuthenticated")`) to sign the user out.
///   - Uses `ProfileViewModel` from the environment to perform the deletion asynchronously.
///
/// - Footer:
///   - Displays the app version and creator information.
///
/// Behavior and State:
/// - `selectedTheme`: The currently selected app theme, stored persistently via `@AppStorage`.
/// - `notificationsEnabled`: Reserved for future use; not currently utilized.
/// - `showingDeleteAlert`: Controls the visibility of the account deletion confirmation alert.
/// - `profileVM`: Environment-provided view model responsible for account operations.
/// - `isAuthenticated`: Persisted flag reflecting the user's authentication state; set to `false` after successful deletion.
///
/// Dependencies:
/// - Requires a `ProfileViewModel` injected into the environment that implements `deleteUserAccount()` returning a `Bool` indicating success.
///
/// Platform:
/// - Built with SwiftUI and leverages Swift Concurrency (`Task`, `MainActor`) for async operations.
struct SettingsView: View {
    @AppStorage("selectedTheme") private var selectedTheme: Theme = .system
    @AppStorage("notificationsEnabled") private var notificationsEnabled = false
    @State private var showingDeleteAlert = false
    @Environment(ProfileViewModel.self) var profileVM
    @AppStorage("isAuthenticated") private var isAuthenticated = true
    
    var body: some View {
        Form {
            Section(header: Text("Aspetto")) {
                Picker("Tema", selection: $selectedTheme) {
                    ForEach(Theme.allCases) { theme in
                        Text(theme.rawValue).tag(theme)
                    }
                }
                .pickerStyle(.navigationLink)
            }
            Section(header: Text("Preferenze")) { // notifications not implemented
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Notifiche Push", isOn: .constant(false))
                        .disabled(true)
                    
                    Text("Le notifiche saranno disponibili nei prossimi aggiornamenti")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Section(header: Text("Account"), footer: Text("L'eliminazione dell'account è irreversibile e comporterà la perdita di tutti i progressi.")) {
                Button(role: .destructive, action: {
                    showingDeleteAlert = true
                }) {
                    HStack {
                        Image(systemName: "person.badge.minus")
                        Text("Elimina Account")
                    }
                }
                .alert("Sei assolutamente sicuro?", isPresented: $showingDeleteAlert) {
                    Button("Annulla", role: .cancel) { }
                    Button("Elimina definitivamente", role: .destructive) {
                        Task {
                            let success = await profileVM.deleteUserAccount()
                            if success {
                                await MainActor.run{
                                    isAuthenticated = false
                                }
                            }
                        }
                    }
                } message: {
                    Text("Tutti i tuoi dati verranno rimossi dai nostri server.")
                }
            }
            
            Section(footer: Text("Cinemax v1.0.0\nCreated by ProtaDev")) {
            }
            
        }
        .navigationTitle("Impostazioni")
        
    }
}
