//
//  SettingsView.swift
//  Cinemax
//
//

import SwiftUI
import Foundation

enum Theme: String, CaseIterable, Identifiable {
    case light = "Chiaro"
    case dark = "Scuro"
    case system = "Sistema"
    var id: String { self.rawValue }
}

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
