import Foundation
import Security
import CryptoKit

struct Identity: Codable {
    var token: String
    var proof: String
    var mac: String
    var key: String {
        let digest = SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
        return String(format: "%06llu", (UInt64(digest.prefix(12), radix: 16) ?? 0) % 1_000_000)
    }
    static func new() throws -> Identity {
        let token = try Keychain.random(32).map { String(format: "%02x", $0) }.joined()
        let proof = try Keychain.random(32).map { String(format: "%02x", $0) }.joined()
        let bytes = Array(SHA256.hash(data: Data(("AADRI-IOS|" + token).utf8)))
        let mac = bytes.prefix(6).map { String(format: "%02X", $0) }.joined(separator: ":")
        return Identity(token: token, proof: proof, mac: mac)
    }
}
enum Keychain {
    static let service = "com.aadripro.ios.identity.v1"
    static func random(_ size: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: size)
        guard SecRandomCopyBytes(kSecRandomDefault, size, &bytes) == errSecSuccess else { throw AppFailure("Secure random unavailable") }
        return Data(bytes)
    }
    static func read(_ name: String) throws -> Data? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: name, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let code = SecItemCopyMatching(query as CFDictionary, &result)
        if code == errSecItemNotFound { return nil }
        guard code == errSecSuccess, let data = result as? Data else { throw AppFailure("تعذر فتح التخزين الآمن؛ افتح قفل الجهاز / Keychain unavailable") }
        return data
    }
    static func put(_ name: String, _ data: Data) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: name]
        let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let code = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if code == errSecItemNotFound {
            var add = query; attributes.forEach { add[$0.key] = $0.value }
            guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw AppFailure("Keychain save failed") }
        } else if code != errSecSuccess { throw AppFailure("Keychain update failed") }
    }
}
actor Vault {
    private let root: URL
    private let key: SymmetricKey
    init() throws {
        let manager = FileManager.default
        root = try manager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("AADRIPro", isDirectory: true)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        if let data = try Keychain.read("storage-key") { key = SymmetricKey(data: data) }
        else {
            // Never reset a profile whose encryption key is missing.
            guard !manager.fileExists(atPath: root.appendingPathComponent("profile.aes").path) else { throw AppFailure("مفتاح التخزين غير متاح؛ لم نغيّر بياناتك / Missing storage key") }
            let data = try Keychain.random(32); try Keychain.put("storage-key", data); key = SymmetricKey(data: data)
        }
        var url = root; var values = URLResourceValues(); values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
    func identity() throws -> Identity {
        if let data = try Keychain.read("identity") { return try JSONDecoder().decode(Identity.self, from: data) }
        let identity = try Identity.new()
        try saveIdentity(identity); return identity
    }
    func saveIdentity(_ value: Identity) throws { try Keychain.put("identity", JSONEncoder().encode(value)) }
    private func read<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
        let data = try Data(contentsOf: root.appendingPathComponent(name))
        let plain = try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key)
        return try JSONDecoder().decode(type, from: plain)
    }
    private func write<T: Encodable>(_ name: String, value: T) throws {
        let data = try JSONEncoder().encode(value)
        guard let encrypted = try AES.GCM.seal(data, using: key).combined else { throw AppFailure("Encryption failed") }
        try encrypted.write(to: root.appendingPathComponent(name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    func profile() throws -> Profile {
        if !FileManager.default.fileExists(atPath: root.appendingPathComponent("profile.aes").path) { return Profile() }
        let value = try read("profile.aes", as: Profile.self)
        guard value.schema == 1 else { throw AppFailure("Unsupported profile version") }
        return value
    }
    func save(_ profile: Profile) throws { try write("profile.aes", value: profile) }
    func catalog(_ id: String) throws -> [Media] { try read("catalog-\(id).aes", as: [Media].self) }
    func put(_ id: String, items: [Media]) throws { try write("catalog-\(id).aes", value: items) }
    func remove(_ id: String) throws {
        let url = root.appendingPathComponent("catalog-\(id).aes")
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}
