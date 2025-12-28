import Foundation

struct IVs: Codable {
    let hp: Int
    let atk: Int
    let def: Int
    let spa: Int
    let spd: Int
    let spe: Int
}

struct RawPokemonPayload: Codable {
    let clear: Bool?  // When true, clears the current Pokemon display
    let type: String?
    let game: String?
    let pid: UInt32?
    let species: String?
    let species_id: Int?
    let level: Int?
    let exp: Int?
    let nature: String?
    let ability: String?
    let ability_slot: Int?
    let gender: String?
    let ivs: IVs?
    let hp_type: String?
    let hp_power: Int?
    let shiny: Bool?
    let shiny_type: String?
}

struct PokemonSpeciesData: Codable {
    let id: Int
    let name: String
    let types: [String]
    let baseStats: [String: Int]
    let abilities: [String]
    let growthRateId: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case types
        case baseStats = "base_stats"
        case abilities
        case growthRateId = "growth_rate_id"
    }
}

struct BaseStats {
    let hp: Int
    let atk: Int
    let def: Int
    let spa: Int
    let spd: Int
    let spe: Int
}

struct PokemonData: Identifiable {
    let id = UUID()
    let pid: UInt32?
    let speciesId: Int
    let speciesName: String
    let level: Int?
    let nature: String?
    let abilityName: String?
    let abilitySlot: Int?
    let gender: String?
    let ivs: IVs
    let baseStats: BaseStats?
    let hpType: String?
    let hpPower: Int?
    let shiny: Bool
    let shinyType: String?
    let game: String?
}

final class PokemonDex: ObservableObject {
    private var byId: [Int: PokemonSpeciesData] = [:]
    private var byName: [String: PokemonSpeciesData] = [:]
    private var growthRates: [Int: [Int]] = [:]

    init() {
        load()
    }

    private func load() {
        // SwiftPM uses Bundle.module for resources
        guard let url = Bundle.module.url(forResource: "pokemon_data", withExtension: "json") else {
            print("PokeScan: pokemon_data.json not found in bundle")
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let list = try JSONDecoder().decode([PokemonSpeciesData].self, from: data)
            byId = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
            byName = Dictionary(uniqueKeysWithValues: list.map { ($0.name.lowercased(), $0) })
            print("PokeScan: Loaded \(byId.count) Pokemon from dex")
        } catch {
            print("PokeScan: Failed to load pokemon_data.json: \(error)")
        }

        if let url = Bundle.module.url(forResource: "growth_rates", withExtension: "json") {
            do {
                let data = try Data(contentsOf: url)
                growthRates = try JSONDecoder().decode([Int: [Int]].self, from: data)
                print("PokeScan: Loaded \(growthRates.count) growth rates")
            } catch {
                print("PokeScan: Failed to load growth_rates.json: \(error)")
            }
        } else {
            print("PokeScan: growth_rates.json not found in bundle")
        }
    }

    func species(id: Int) -> PokemonSpeciesData? {
        return byId[id]
    }

    func species(name: String) -> PokemonSpeciesData? {
        return byName[name.lowercased()]
    }

    func level(forExp exp: Int, speciesId: Int) -> Int? {
        guard let rateId = byId[speciesId]?.growthRateId, let table = growthRates[rateId] else {
            return nil
        }
        var bestLevel = 1
        for level in 1..<table.count {
            if exp >= table[level] {
                bestLevel = level
            } else {
                break
            }
        }
        return bestLevel
    }
}
