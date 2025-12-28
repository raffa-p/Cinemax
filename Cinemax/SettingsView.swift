//
//  SettingsView.swift
//  Cinemax
//
//  Created by Raffaele Prota on 28/12/25.
//
import SwiftUI
import Foundation

struct SettingsView: View {
    // Questa variabile salva la preferenza in modo permanente
    @AppStorage("isDarkMode") private var isDarkMode = true
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    
    // Per gestire la pulizia della cache
    @State private var showingCacheAlert = false
    
    var body: some View {
        Form {
            // SEZIONE ASPETTO
            Section(header: Text("Aspetto")) {
                Toggle(isOn: $isDarkMode) {
                    HStack {
                        Image(systemName: isDarkMode ? "moon.fill" : "sun.max.fill")
                            .foregroundColor(isDarkMode ? .purple : .orange)
                        Text("Modalità Scura")
                    }
                }
            }
            
            // SEZIONE NOTIFICHE (Simulata)
            Section(header: Text("Preferenze")) {
                Toggle("Notifiche Push", isOn: $notificationsEnabled)
            }
            
            // SEZIONE MANUTENZIONE
            Section(header: Text("Manutenzione")) {
                Button(action: {
                    showingCacheAlert = true
                }) {
                    HStack {
                        Text("Svuota Cache Immagini")
                            .foregroundColor(.red)
                        Spacer()
                        Text("Libera spazio")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                .alert("Cache Svuotata", isPresented: $showingCacheAlert) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text("Tutte le immagini temporanee sono state rimosse per liberare spazio.")
                }
            }
            
            // SEZIONE INFO
            Section(footer: Text("Cinemax v1.0.0\nCreated by You")) {
                // Vuota, serve solo per il footer
            }
        }
        .navigationTitle("Impostazioni")
        .preferredColorScheme(isDarkMode ? .dark : .light) // Anteprima live
    }
}
