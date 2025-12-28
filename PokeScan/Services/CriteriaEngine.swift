import Foundation

struct CatchProfile: Codable {
    let name: String?
    let species: [String]?
    let requiredNatures: [String]?
    let minIVs: [String: Int]?
    let minIVTotal: Int?       // Minimum IV sum (0-186)
    let minIVPercent: Int?     // Minimum IV percentage (0-100)
    let notes: String?
}

struct CatchCriteria: Codable {
    var activeProfile: String
    var alwaysAlertShiny: Bool
    var alertSoundEnabled: Bool
    var profiles: [String: CatchProfile]
}

enum CatchVerdict {
    case catchIt(reason: String)
    case skip(reason: String)
    case shiny
}

final class CriteriaEngine: ObservableObject {
    @Published private(set) var criteria: CatchCriteria
    let fileURL: URL

    init() {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("PokeScan", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        fileURL = dir.appendingPathComponent("catch_criteria.json")
        if !fileManager.fileExists(atPath: fileURL.path) {
            if let bundled = Bundle.module.url(forResource: "catch_criteria", withExtension: "json") {
                do {
                    try fileManager.copyItem(at: bundled, to: fileURL)
                } catch {
                    print("PokeScan: Failed to copy bundled criteria: \(error)")
                    try? CriteriaEngine.writeDefaultCriteria(to: fileURL)
                }
            } else {
                print("PokeScan: Bundled catch_criteria.json not found, writing default criteria")
                try? CriteriaEngine.writeDefaultCriteria(to: fileURL)
            }
        }
        criteria = CriteriaEngine.loadCriteria(from: fileURL)
            ?? (CriteriaEngine.defaultCriteria())
    }

    private static func loadCriteria(from url: URL) -> CatchCriteria? {
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(CatchCriteria.self, from: data)
        } catch {
            print("PokeScan: Failed to load criteria: \(error)")
            return nil
        }
    }

    private static func defaultCriteria() -> CatchCriteria {
        let profile = CatchProfile(
            name: "High IVs",
            species: nil,
            requiredNatures: nil,
            minIVs: nil,
            minIVTotal: nil,
            minIVPercent: 80,
            notes: "Catch any Pokemon with 80%+ IVs"
        )
        return CatchCriteria(
            activeProfile: "high_ivs",
            alwaysAlertShiny: true,
            alertSoundEnabled: true,
            profiles: ["high_ivs": profile]
        )
    }

    private static func writeDefaultCriteria(to url: URL) throws {
        let data = try JSONEncoder().encode(defaultCriteria())
        try data.write(to: url)
    }

    func reload() {
        if let loaded = CriteriaEngine.loadCriteria(from: fileURL) {
            criteria = loaded
        }
    }

    func setActiveProfile(_ name: String) {
        criteria.activeProfile = name
        save()
    }

    func setSoundEnabled(_ enabled: Bool) {
        criteria.alertSoundEnabled = enabled
        save()
    }

    func save() {
        do {
            let data = try JSONEncoder().encode(criteria)
            try data.write(to: fileURL)
        } catch {
            print("PokeScan: Failed to save criteria: \(error)")
        }
    }

    func profileKeys() -> [String] {
        criteria.profiles.keys.sorted()
    }

    func evaluate(pokemon: PokemonData) -> CatchVerdict {
        // Always alert on shiny if enabled
        if criteria.alwaysAlertShiny, pokemon.shiny {
            return .shiny
        }

        guard let profile = criteria.profiles[criteria.activeProfile] else {
            return .skip(reason: "No active profile")
        }

        // Check species filter (if specified)
        if let species = profile.species, !species.isEmpty {
            if !species.map({ $0.lowercased() }).contains(pokemon.speciesName.lowercased()) {
                return .skip(reason: "Species mismatch")
            }
        }

        // Check nature filter (if specified)
        if let natures = profile.requiredNatures, !natures.isEmpty {
            if let nature = pokemon.nature?.lowercased() {
                if !natures.map({ $0.lowercased() }).contains(nature) {
                    return .skip(reason: "Nature mismatch")
                }
            } else {
                return .skip(reason: "Missing nature")
            }
        }

        // Check individual IV minimums (if specified)
        if let minIVs = profile.minIVs {
            for (key, minValue) in minIVs {
                guard let actual = ivValue(for: key, ivs: pokemon.ivs) else { continue }
                if actual < minValue {
                    return .skip(reason: "IV \(key) too low")
                }
            }
        }

        // Check IV total (if specified)
        let ivTotal = pokemon.ivs.hp + pokemon.ivs.atk + pokemon.ivs.def +
                      pokemon.ivs.spa + pokemon.ivs.spd + pokemon.ivs.spe

        if let minTotal = profile.minIVTotal {
            if ivTotal < minTotal {
                return .skip(reason: "IV total \(ivTotal) < \(minTotal)")
            }
        }

        // Check IV percentage (if specified)
        if let minPercent = profile.minIVPercent {
            let percent = Int((Double(ivTotal) / 186.0) * 100)
            if percent < minPercent {
                return .skip(reason: "IV \(percent)% < \(minPercent)%")
            }
        }

        return .catchIt(reason: profile.notes ?? "Meets criteria")
    }

    private func ivValue(for key: String, ivs: IVs) -> Int? {
        switch key.lowercased() {
        case "hp": return ivs.hp
        case "atk": return ivs.atk
        case "def": return ivs.def
        case "spa": return ivs.spa
        case "spd": return ivs.spd
        case "spe": return ivs.spe
        default: return nil
        }
    }
}
