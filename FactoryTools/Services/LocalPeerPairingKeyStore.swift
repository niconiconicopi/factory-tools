import CryptoKit
import Foundation
import Security

enum LocalPeerPairingKeyStore {
    private static let service = "FactoryTools.LocalPeer.PairingKey.v1"
    private static let account = "paired-peer-secret"

    static func loadCode() -> String? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query(returnData: true) as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data,
              let code = String(data: data, encoding: .utf8) else { return nil }
        do {
            _ = try keyData(from: code)
            return code
        } catch {
            return nil
        }
    }

    static func generateCode() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else { throw LocalPeerPairingKeyStoreError.randomGenerationFailed }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    static func save(code: String) throws {
        _ = try keyData(from: code)
        let attributes: [String: Any] = [
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: Data(code.utf8)
        ]
        let updateStatus = SecItemUpdate(query(returnData: false) as CFDictionary, attributes as CFDictionary)
        let status = upsertStatus(updateStatus: updateStatus, itemNotFoundStatus: errSecItemNotFound) {
            var item = query(returnData: false)
            for (key, value) in attributes {
                item[key] = value
            }
            return SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw LocalPeerPairingKeyStoreError.keychainFailure(status) }
    }

    static func upsertStatus(
        updateStatus: OSStatus,
        itemNotFoundStatus: OSStatus,
        insert: () -> OSStatus
    ) -> OSStatus {
        updateStatus == itemNotFoundStatus ? insert() : updateStatus
    }

    static func remove() throws {
        let status = SecItemDelete(query(returnData: false) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw LocalPeerPairingKeyStoreError.keychainFailure(status)
        }
    }

    static func keyData(from code: String) throws -> Data {
        let bytes = Array(code.utf8)
        guard bytes.count == 64 else { throw LocalPeerPairingKeyStoreError.invalidCode }
        var result = Data(capacity: 32)
        for index in stride(from: 0, to: bytes.count, by: 2) {
            guard let high = hexValue(bytes[index]), let low = hexValue(bytes[index + 1]) else {
                throw LocalPeerPairingKeyStoreError.invalidCode
            }
            result.append((high << 4) | low)
        }
        return result
    }

    static func identity(for keyData: Data) -> String {
        SHA256.hash(data: keyData)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func query(returnData: Bool) -> [String: Any] {
        var value: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if returnData {
            value[kSecReturnData as String] = true
            value[kSecMatchLimit as String] = kSecMatchLimitOne
        }
        return value
    }

    private static func hexValue(_ value: UInt8) -> UInt8? {
        switch value {
        case 48...57: value - 48
        case 65...70: value - 55
        case 97...102: value - 87
        default: nil
        }
    }
}

enum LocalPeerPairingKeyStoreError: Error, Equatable {
    case invalidCode
    case randomGenerationFailed
    case keychainFailure(OSStatus)
}

enum LocalPeerPairingCodeChangePolicy {
    static func requiresConfirmation(currentCode: String?, proposedCode: String, pendingCommandCount: Int) -> Bool {
        currentCode != proposedCode && pendingCommandCount > 0
    }

    static func requiresConfirmationBeforeReset(currentCode: String?) -> Bool {
        currentCode != nil
    }

    static func requiresConfirmationBeforeAuthorityCodeChange(currentCode: String?, proposedCode: String) -> Bool {
        currentCode != nil && currentCode != proposedCode
    }
}

enum PairingSecretVisibilityPolicy {
    static func shouldRedact(sceneIsActive: Bool, isScreenCaptured: Bool) -> Bool {
        !sceneIsActive || isScreenCaptured
    }
}
