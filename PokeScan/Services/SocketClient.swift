import Foundation
import Network

// Simple file logger for automated testing
private func log(_ message: String) {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    let timestamp = formatter.string(from: Date())
    let formatted = "[\(timestamp)] \(message)\n"

    // Print to stderr (more reliable for GUI apps)
    fputs(formatted, stderr)

    // Also append to log file if path is set
    if let logPath = ProcessInfo.processInfo.environment["POKESCAN_LOG"],
       let data = formatted.data(using: .utf8) {
        if let handle = FileHandle(forWritingAtPath: logPath) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else if FileManager.default.createFile(atPath: logPath, contents: data) {
            // File created with initial content
        }
    }
}

final class SocketClient: ObservableObject, @unchecked Sendable {
    @Published var currentPokemon: PokemonData?
    @Published var connectionState: ConnectionState = .disconnected

    enum ConnectionState {
        case disconnected
        case connecting
        case connected
    }

    private var connection: NWConnection?
    private var buffer = Data()
    private let registry = GameAdapterRegistry()
    private let dex: PokemonDex
    private let host: String
    private let port: UInt16
    private var reconnectTask: Task<Void, Never>?
    private let networkQueue = DispatchQueue(label: "pokescan.network", qos: .userInitiated)

    init(dex: PokemonDex, host: String = "127.0.0.1", port: UInt16 = 9876) {
        self.dex = dex
        self.host = host

        // Try to read port from file (set by Lua server)
        let portFilePath = ProcessInfo.processInfo.environment["POKESCAN_PORT_FILE"]
            ?? (FileManager.default.currentDirectoryPath + "/dev/logs/port")
        if let portStr = try? String(contentsOfFile: portFilePath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           let filePort = UInt16(portStr) {
            self.port = filePort
            log("PokeScan: Using port \(filePort) from port file")
        } else {
            self.port = port
        }
    }

    func start() {
        log("PokeScan: Starting client, connecting to \(host):\(port)")
        connect()
    }

    func stop() {
        reconnectTask?.cancel()
        reconnectTask = nil
        connection?.cancel()
        connection = nil
        connectionState = .disconnected
    }

    private func connect() {
        connection?.cancel()

        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!
        )

        let conn = NWConnection(to: endpoint, using: .tcp)
        self.connection = conn
        connectionState = .connecting

        conn.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    log("PokeScan: CONNECTED to mGBA")
                    self.connectionState = .connected
                    self.buffer = Data()
                    self.receiveData()
                case .failed(let error):
                    log("PokeScan: Connection FAILED - \(error)")
                    self.connectionState = .disconnected
                    self.scheduleReconnect()
                case .cancelled:
                    log("PokeScan: Connection cancelled")
                    self.connectionState = .disconnected
                    self.scheduleReconnect()
                case .waiting(let error):
                    log("PokeScan: Waiting - \(error)")
                    self.connectionState = .connecting
                default:
                    break
                }
            }
        }

        conn.start(queue: networkQueue)
    }

    private func scheduleReconnect() {
        reconnectTask?.cancel()
        reconnectTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if !Task.isCancelled {
                self.connect()
            }
        }
    }

    private func receiveData() {
        guard let conn = connection else { return }

        conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            DispatchQueue.main.async {
                if let data = data, !data.isEmpty {
                    self.buffer.append(data)
                    self.processBuffer()
                }

                if isComplete || error != nil {
                    self.connectionState = .disconnected
                    self.scheduleReconnect()
                } else {
                    self.receiveData()
                }
            }
        }
    }

    private func processBuffer() {
        let newline = Data([0x0A])
        while let range = buffer.range(of: newline) {
            let lineData = buffer.subdata(in: 0..<range.lowerBound)
            buffer.removeSubrange(0..<range.upperBound)
            if lineData.isEmpty { continue }
            decodeMessage(lineData)
        }
    }

    private func decodeMessage(_ data: Data) {
        do {
            let raw = try JSONDecoder().decode(RawPokemonPayload.self, from: data)

            // Handle clear message
            if raw.clear == true {
                log("PokeScan: RECV clear")
                currentPokemon = nil
                return
            }

            log("PokeScan: RECV species_id=\(raw.species_id ?? -1) exp=\(raw.exp ?? -1)")
            if let normalized = registry.normalize(raw, dex: dex) {
                log("PokeScan: Pokemon: \(normalized.speciesName) Lv.\(normalized.level ?? 0) IVs=\(normalized.ivs.hp)/\(normalized.ivs.atk)/\(normalized.ivs.def)/\(normalized.ivs.spa)/\(normalized.ivs.spd)/\(normalized.ivs.spe)")
                currentPokemon = normalized
            } else {
                log("PokeScan: Failed to normalize payload")
            }
        } catch {
            log("PokeScan: JSON decode error: \(error)")
            if let str = String(data: data, encoding: .utf8) {
                log("PokeScan: Raw JSON: \(str)")
            }
        }
    }
}
