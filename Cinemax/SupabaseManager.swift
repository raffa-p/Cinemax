//
//  SupabaseManager.swift
//  Cinemax
//
//  Created by Raffaele Prota on 17/12/25.
//

import Foundation
import Supabase

class SupabaseManager {
    // SINGLETON: Usiamo un'unica istanza in tutta l'app
    static let shared = SupabaseManager()
    
    let client: SupabaseClient
    
    private init() {
        // SOSTITUISCI CON I TUOI DATI PRESI DALLA DASHBOARD DI SUPABASE
        let databaseURL = URL(string: "https://zggjpzfjrqmyoryulyoa.supabase.co")!
        let databaseKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpnZ2pwemZqcnFteW9yeXVseW9hIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjU5ODgwMDYsImV4cCI6MjA4MTU2NDAwNn0.q2B8KMfStAYYiCHTzuNLpjWiIycPs2epVXFhK6g4v7w"
        
        self.client = SupabaseClient(supabaseURL: databaseURL, supabaseKey: databaseKey)
    }
}
