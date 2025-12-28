import Foundation

protocol GameAdapter {
    var id: String { get }
    func normalize(_ raw: RawPokemonPayload, dex: PokemonDex) -> PokemonData?
}

struct DefaultAdapter: GameAdapter {
    let id: String

    func normalize(_ raw: RawPokemonPayload, dex: PokemonDex) -> PokemonData? {
        let speciesId = raw.species_id
        let speciesData = speciesId.flatMap { dex.species(id: $0) }
        let speciesName = raw.species ?? speciesData?.name ?? "Unknown"

        let abilityName: String?
        if let direct = raw.ability {
            abilityName = direct
        } else if let slot = raw.ability_slot, let abilities = speciesData?.abilities, slot >= 0, slot < abilities.count {
            abilityName = abilities[slot]
        } else {
            abilityName = nil
        }

        let ivs = raw.ivs ?? IVs(hp: 0, atk: 0, def: 0, spa: 0, spd: 0, spe: 0)

        guard let sid = speciesId ?? dex.species(name: speciesName)?.id else {
            return nil
        }

        let level = raw.level ?? (raw.exp.flatMap { dex.level(forExp: $0, speciesId: sid) })

        // Extract base stats from species data
        let baseStats: BaseStats?
        if let stats = speciesData?.baseStats {
            baseStats = BaseStats(
                hp: stats["hp"] ?? 0,
                atk: stats["atk"] ?? 0,
                def: stats["def"] ?? 0,
                spa: stats["spa"] ?? 0,
                spd: stats["spd"] ?? 0,
                spe: stats["spe"] ?? 0
            )
        } else {
            baseStats = nil
        }

        return PokemonData(
            pid: raw.pid,
            speciesId: sid,
            speciesName: speciesName,
            level: level,
            nature: raw.nature,
            abilityName: abilityName,
            abilitySlot: raw.ability_slot,
            gender: raw.gender,
            ivs: ivs,
            baseStats: baseStats,
            hpType: raw.hp_type,
            hpPower: raw.hp_power,
            shiny: raw.shiny ?? false,
            shinyType: raw.shiny_type,
            game: raw.game
        )
    }
}

final class GameAdapterRegistry {
    private var adapters: [String: GameAdapter] = [:]
    private let defaultAdapter: GameAdapter

    init() {
        let emerald = DefaultAdapter(id: "emerald_us_eu")
        self.defaultAdapter = emerald
        adapters[emerald.id] = emerald
    }

    func normalize(_ raw: RawPokemonPayload, dex: PokemonDex) -> PokemonData? {
        let gameId = raw.game ?? defaultAdapter.id
        let adapter = adapters[gameId] ?? defaultAdapter
        return adapter.normalize(raw, dex: dex)
    }
}
