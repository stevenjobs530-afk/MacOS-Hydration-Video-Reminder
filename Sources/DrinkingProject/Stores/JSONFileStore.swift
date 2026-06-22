import Foundation

enum JSONFileStore {
    static func load<T: Decodable>(_ type: T.Type, from url: URL, fallback: @autoclosure () -> T) -> T {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return fallback()
        }
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(type, from: data)
        } catch {
            backupCorruptFile(at: url, error: error)
            return fallback()
        }
    }

    private static func backupCorruptFile(at url: URL, error: Error) {
        let timestamp = backupDateFormatter.string(from: Date())
        let backupURL = url.deletingLastPathComponent()
            .appendingPathComponent("\(url.lastPathComponent).corrupt-\(timestamp)")
        do {
            try FileManager.default.copyItem(at: url, to: backupURL)
            print("[DrinkingProject] json_corrupt_backup path=\(url.path) backup=\(backupURL.path) error=\(error)")
        } catch {
            print("[DrinkingProject] json_corrupt_backup_failed path=\(url.path) error=\(error)")
        }
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

    private static let backupDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}
