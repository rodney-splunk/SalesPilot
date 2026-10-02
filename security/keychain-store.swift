import Foundation
import Security
// Credentials arrive through stdin, never command arguments or logs.
let input = FileHandle.standardInput.readDataToEndOfFile()
guard let value = try? JSONSerialization.jsonObject(with: input) as? [String: String], value["client_secret"] != nil else { exit(2) }
let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.salespilot.circuit", kSecAttrAccount as String: "credentials"]
let data = try JSONSerialization.data(withJSONObject: value)
let result = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
if result == errSecItemNotFound {
    var add = query; add[kSecValueData as String] = data
    guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { exit(3) }
} else if result != errSecSuccess { exit(4) }
print("stored")
