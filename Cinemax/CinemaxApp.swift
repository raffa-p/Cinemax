//
//  CinemaxApp.swift
//  Cinemax
//
//  Created by Raffaele Prota on 17/12/25.
//

import SwiftUI
import Supabase

// MARK: - APP ENTRY POINT
@main
struct CinemaxApp: App {
    @State private var isAuthenticated = false
    
    init() {
        // ... (configurazione estetica UI rimasta uguale) ...
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
            .preferredColorScheme(.dark)
            .task {
                // CONTROLLO SESSIONE ALL'AVVIO
                // Se c'è un utente loggato, salta il login
                if let _ = try? await SupabaseManager.shared.client.auth.session.user {
                    isAuthenticated = true
                }
            }
        }
    }
}

// MARK: - LOGIN VIEW DESIGN
struct LoginView: View {
    @Binding var isAuthenticated: Bool
    
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var showError = false
    
    // Switch tra Login e Registrazione
    @State private var isSignUpMode = false
    
    @FocusState private var focusedField: Field?
    enum Field { case email, password }
    
    var body: some View {
        ZStack {
            // Sfondo
            Color.black.ignoresSafeArea()
            
            // Texture
            GeometryReader { geo in
                Image(systemName: "film.stack.fill")
                    .resizable().scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .foregroundStyle(.gray.opacity(0.1))
                    .blur(radius: 10)
                    .rotationEffect(.degrees(-15))
                    .scaleEffect(1.2)
                    .offset(x: -50, y: -50)
            }
            .ignoresSafeArea()
            
            LinearGradient(colors: [.black.opacity(0.6), .black, .black], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            
            VStack(spacing: 30) {
                Spacer()
                
                Text("CINEMAX")
                    .font(.system(size: 50, weight: .black, design: .rounded))
                    .foregroundStyle(.red)
                    .shadow(color: .red.opacity(0.5), radius: 20, x: 0, y: 0)
                
                // Form
                VStack(spacing: 16) {
                    // Email
                    HStack {
                        Image(systemName: "envelope.fill").foregroundColor(.gray)
                        TextField("", text: $email, prompt: Text("Email").foregroundColor(.gray))
                            .focused($focusedField, equals: .email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .foregroundColor(.white)
                    }
                    .padding()
                    .background(Color(UIColor.systemGray6).opacity(0.2))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(focusedField == .email ? Color.white.opacity(0.5) : Color.clear, lineWidth: 1))
                    
                    // Password
                    HStack {
                        Image(systemName: "lock.fill").foregroundColor(.gray)
                        SecureField("", text: $password, prompt: Text("Password").foregroundColor(.gray))
                            .focused($focusedField, equals: .password)
                            .textContentType(.password)
                            .foregroundColor(.white)
                    }
                    .padding()
                    .background(Color(UIColor.systemGray6).opacity(0.2))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(focusedField == .password ? Color.white.opacity(0.5) : Color.clear, lineWidth: 1))
                    
                    // Button Action
                    Button(action: performAuthAction) {
                        ZStack {
                            if isLoading {
                                ProgressView().tint(.white)
                            } else {
                                Text(isSignUpMode ? "Registrati" : "Accedi")
                                    .font(.headline).bold()
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .disabled(isLoading || email.isEmpty || password.isEmpty)
                    .padding(.top, 10)
                    
                    // Toggle Login/Signup
                    Button(action: {
                        withAnimation { isSignUpMode.toggle() }
                    }) {
                        Text(isSignUpMode ? "Hai già un account? Accedi" : "Non hai un account? Registrati")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                            .underline()
                    }
                    .padding(.top, 5)
                }
                .padding(.horizontal, 30)
                
                Spacer()
            }
        }
        .onTapGesture { focusedField = nil }
        .alert("Errore", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "Si è verificato un errore sconosciuto.")
        }
    }
    
    // MARK: - LOGICA SUPABASE
    func performAuthAction() {
        focusedField = nil
        isLoading = true
        
        Task {
            do {
                if isSignUpMode {
                    // REGISTRAZIONE
                    // Nota: Se "Email Confirm" è attivo su Supabase, l'utente non sarà loggato subito
                    // ma dovrà controllare la mail. Se l'hai disattivato, il login è automatico.
                    let _ = try await SupabaseManager.shared.client.auth.signUp(
                        email: email,
                        password: password
                    )
                    // Dopo la registrazione, facciamo il login automatico (se auto-confirm è attivo)
                    // o mostriamo un messaggio
                     isAuthenticated = true
                } else {
                    // LOGIN
                    let _ = try await SupabaseManager.shared.client.auth.signIn(
                        email: email,
                        password: password
                    )
                    isAuthenticated = true
                }
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
            
            await MainActor.run {
                isLoading = false
            }
        }
    }
}

#Preview {
    LoginView(isAuthenticated: .constant(false))
        .preferredColorScheme(.dark)
}
