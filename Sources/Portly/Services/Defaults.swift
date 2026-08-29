import Foundation

/// Typed access to the handful of UserDefaults shapes Portly persists, so the
/// encode/decode pairs live in one place instead of being rewritten per setting.
enum Defaults {

    static func bool(_ key: String, default fallback: Bool = false) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? fallback
    }

    static func set(_ value: Bool, for key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    static func intSet(_ key: String) -> Set<Int> {
        Set(UserDefaults.standard.array(forKey: key) as? [Int] ?? [])
    }

    static func set(_ value: Set<Int>, for key: String) {
        UserDefaults.standard.set(Array(value), forKey: key)
    }

    static func stringSet(_ key: String) -> Set<String> {
        Set(UserDefaults.standard.array(forKey: key) as? [String] ?? [])
    }

    static func set(_ value: Set<String>, for key: String) {
        UserDefaults.standard.set(Array(value), forKey: key)
    }

    /// Int-keyed dictionaries have to round-trip through String keys, since plists
    /// only allow string keys.
    static func intKeyedStrings(_ key: String) -> [Int: String] {
        let raw = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
        return Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in
            Int(key).map { ($0, value) }
        })
    }

    static func set(_ value: [Int: String], for key: String) {
        UserDefaults.standard.set(
            Dictionary(uniqueKeysWithValues: value.map { (String($0.key), $0.value) }),
            forKey: key
        )
    }
}
