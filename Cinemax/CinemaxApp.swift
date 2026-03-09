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

// MARK: - LOGIN VIEW
struct LoginView: View {
    @Binding var isAuthenticated: Bool
    @State private var email = ""
    @State private var password = ""
    
    // 🟢 1. NUOVE VARIABILI PER LA REGISTRAZIONE
    @State private var nickname = ""
    @State private var confirmPassword = ""
    
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var showError = false
    @State private var isSignUpMode = false
    
    @FocusState private var focusedField: Field?
    // 🟢 2. AGGIUNTI I NUOVI CAMPI AL FOCUS
    enum Field { case nickname, email, password, confirmPassword }
    
    // Controlla se i campi base sono compilati per sbloccare il bottone
    var isFormFilled: Bool {
        if isSignUpMode {
            return !nickname.isEmpty && !email.isEmpty && !password.isEmpty && !confirmPassword.isEmpty
        }
        return !email.isEmpty && !password.isEmpty
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
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
                
                VStack(spacing: 16) {
                    // 🟢 3. CAMPO NICKNAME (Visibile solo in registrazione)
                    if isSignUpMode {
                        HStack {
                            Image(systemName: "person.fill").foregroundColor(.gray)
                            TextField("", text: $nickname, prompt: Text("Nickname").foregroundColor(.gray))
                                .focused($focusedField, equals: .nickname)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.words)
                                .foregroundColor(.white)
                        }
                        .padding()
                        .background(Color(UIColor.systemGray6).opacity(0.2))
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(focusedField == .nickname ? Color.white.opacity(0.5) : Color.clear, lineWidth: 1))
                        // Animazione fluida quando appare
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    
                    // Email (Sempre visibile)
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
                    
                    // Password (Sempre visibile)
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
                    
                    // 🟢 4. CAMPO CONFERMA PASSWORD (Visibile solo in registrazione)
                    if isSignUpMode {
                        HStack {
                            Image(systemName: "lock.shield.fill").foregroundColor(.gray)
                            SecureField("", text: $confirmPassword, prompt: Text("Conferma Password").foregroundColor(.gray))
                                .focused($focusedField, equals: .confirmPassword)
                                .textContentType(.password)
                                .foregroundColor(.white)
                        }
                        .padding()
                        .background(Color(UIColor.systemGray6).opacity(0.2))
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(focusedField == .confirmPassword ? Color.white.opacity(0.5) : Color.clear, lineWidth: 1))
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    
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
                    .disabled(isLoading || !isFormFilled)
                    .padding(.top, 10)
                    
                    // Toggle Login/Signup
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isSignUpMode.toggle()
                            // Resetta i campi di errore quando si cambia modalità
                            errorMessage = nil
                            showError = false
                        }
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
            
            // CONTROLLO VALIDITÀ PASSWORD
            if isSignUpMode && password != confirmPassword {
                errorMessage = "Le password non coincidono. Riprova."
                showError = true
                return
            }
            
            isLoading = true
            
            Task {
                do {
                    if isSignUpMode {
                        // REGISTRAZIONE
                        let response = try await SupabaseManager.shared.client.auth.signUp(
                            email: email,
                            password: password,
                            data: ["nickname": .string(nickname)]
                        )
                        
                        await MainActor.run {
                            // Se la sessione è 'nil', significa che Supabase aspetta la conferma email!
                            if response.session == nil {
                                errorMessage = "Registrazione completata con successo! 🎉\n\nTi abbiamo inviato una mail per confermare l'account."
                                showError = true
                                
                                isSignUpMode = false
                                password = ""
                                confirmPassword = ""
                            } else {
                                isAuthenticated = true
                            }
                        }
                    } else {
                        // LOGIN
                        let _ = try await SupabaseManager.shared.client.auth.signIn(
                            email: email,
                            password: password
                        )
                        
                        await MainActor.run {
                            isAuthenticated = true
                        }
                    }
                } catch {
                    await MainActor.run {
                        let errorMsg = error.localizedDescription
                        
                        if errorMsg.lowercased().contains("email not confirmed") {
                            errorMessage = "Devi prima confermare il tuo indirizzo email. Controlla la tua casella di posta!"
                        } else {
                            errorMessage = errorMsg
                        }
                        
                        showError = true
                    }
                }
                
                await MainActor.run {
                    isLoading = false
                }
            }
        }
}
