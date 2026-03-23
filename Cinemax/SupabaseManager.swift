//
//  SupabaseManager.swift
//  Cinemax
//
//

import Foundation
import Supabase

/// A singleton responsible for configuring and providing access to the Supabase client used across the app.
///
/// Usage:
/// - Access the shared instance via `SupabaseManager.shared`.
/// - Use `SupabaseManager.shared.client` to perform database, authentication, storage,
///   and edge function operations through the Supabase SDK.
class SupabaseManager {
    static let shared = SupabaseManager()
    let client: SupabaseClient
    
    private init() {
        self.client = SupabaseClient(supabaseURL: URL(string: config.databaseUrl)!, supabaseKey: config.databaseKey)
    }
}
