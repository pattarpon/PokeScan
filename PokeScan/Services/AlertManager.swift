import SwiftUI
import AudioToolbox

@MainActor
final class AlertManager: ObservableObject {
    @Published var borderColor: Color = .clear

    private var soundID: SystemSoundID = 0

    init() {
        loadSound()
    }

    deinit {
        if soundID != 0 {
            AudioServicesDisposeSystemSoundID(soundID)
        }
    }

    private func loadSound() {
        guard let url = Bundle.module.url(forResource: "pokemon_alert", withExtension: "aiff") else {
            print("PokeScan: pokemon_alert.aiff not found in bundle")
            return
        }
        AudioServicesCreateSystemSoundID(url as CFURL, &soundID)
    }

    func playSound() {
        guard soundID != 0 else { return }
        AudioServicesPlaySystemSound(soundID)
    }

    func flash() {
        withAnimation(.easeInOut(duration: 0.15).repeatCount(5, autoreverses: true)) {
            borderColor = .yellow
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            self.borderColor = .clear
        }
    }

    func clearFlash() {
        borderColor = .clear
    }
}
