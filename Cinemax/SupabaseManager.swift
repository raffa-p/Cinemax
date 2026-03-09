//
//  SupabaseManager.swift
//  Cinemax
//
//

import Foundation
import Supabase

class SupabaseManager {
    static let shared = SupabaseManager()
    let client: SupabaseClient
    
    private init() {
        self.client = SupabaseClient(supabaseURL: URL(string: config.databaseUrl)!, supabaseKey: config.databaseKey)
    }
}
