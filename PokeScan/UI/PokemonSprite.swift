import SwiftUI

struct PokemonSprite: View {
    let speciesId: Int
    let isShiny: Bool
    let size: CGFloat

    init(speciesId: Int, isShiny: Bool = false, size: CGFloat = 48) {
        self.speciesId = speciesId
        self.isShiny = isShiny
        self.size = size
    }

    var body: some View {
        Group {
            if let image = loadSprite() {
                Image(nsImage: image)
                    .interpolation(.none)  // Keep pixel art crisp
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
            } else {
                // Fallback placeholder
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.1))
                    .frame(width: size, height: size)
                    .overlay(
                        Text("?")
                            .font(.system(size: size * 0.5, weight: .bold))
                            .foregroundStyle(.white.opacity(0.3))
                    )
            }
        }
    }

    private func loadSprite() -> NSImage? {
        // Validate species ID (Gen 1-3: 1-386)
        guard speciesId >= 1 && speciesId <= 386 else { return nil }

        let prefix = isShiny ? "s_" : "r_"
        let filename = "\(prefix)\(speciesId)"

        // Try to load from bundle (resources are flattened by .process())
        if let url = Bundle.module.url(forResource: filename, withExtension: "png") {
            return NSImage(contentsOf: url)
        }

        return nil
    }
}

// Preview for development
#if DEBUG
struct PokemonSprite_Previews: PreviewProvider {
    static var previews: some View {
        HStack(spacing: 20) {
            PokemonSprite(speciesId: 25, isShiny: false)  // Pikachu
            PokemonSprite(speciesId: 25, isShiny: true)   // Shiny Pikachu
            PokemonSprite(speciesId: 261, isShiny: false) // Poochyena
        }
        .padding()
        .background(Color.black)
    }
}
#endif
