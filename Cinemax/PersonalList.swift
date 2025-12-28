//
//  PersonalList.swift
//  Cinemax
//
//  Created by Raffaele Prota on 28/12/25.
//




import Foundation

struct PersonalList: Codable {
    var id: Int?
    let tmdbId: Int
    let mediaType: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case tmdbId = "tmdb_id"
        case mediaType = "media_type"
    }
}
