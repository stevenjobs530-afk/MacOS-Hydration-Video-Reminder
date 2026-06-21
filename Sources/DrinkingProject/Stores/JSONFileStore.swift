import Foundation

enum JSONFileStore {
    static func load<T: Decodable>(_ type: T.Type, from url: URL, fallback: @autoclosure () -> T) -> T {
        guard
            let data = try? Data(contentsOf: url),
            let decoded = try? decoder.decode(type, from: data)
        else {
            return fallback()
        }
        return decoded
    }

    static func save<T: Encodable>(_ value: T, to url: URL) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(value)
            try data.write(to: url, options: [.atomic])
        } catch {
            print("[DrinkingProject] json_save_error path=\(url.path) error=\(error)")
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
