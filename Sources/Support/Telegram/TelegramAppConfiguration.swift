import Foundation

struct TelegramAppConfiguration {
    let apiID: Int
    let apiHash: String
    let useTestDC: Bool

    static func load(bundle: Bundle = .main) -> TelegramAppConfiguration? {
        guard
            let rawAPIID = bundle.stringValue(forInfoDictionaryKey: "UniOSTelegramAPIID"),
            let apiID = Int(rawAPIID),
            let apiHash = bundle.stringValue(forInfoDictionaryKey: "UniOSTelegramAPIHash")
        else {
            return nil
        }

        let useTestDC = bundle.boolValue(forInfoDictionaryKey: "UniOSTelegramUseTestDC")
        return TelegramAppConfiguration(apiID: apiID, apiHash: apiHash, useTestDC: useTestDC)
    }
}

private extension Bundle {
    func stringValue(forInfoDictionaryKey key: String) -> String? {
        guard let rawValue = object(forInfoDictionaryKey: key) else {
            return nil
        }

        let stringValue = String(describing: rawValue).trimmingCharacters(in: .whitespacesAndNewlines)
        return stringValue.isEmpty ? nil : stringValue
    }

    func boolValue(forInfoDictionaryKey key: String) -> Bool {
        guard let rawValue = object(forInfoDictionaryKey: key) else {
            return false
        }

        switch rawValue {
        case let value as NSNumber:
            return value.boolValue
        case let value as NSString:
            return ["1", "true", "yes"].contains(value.lowercased)
        case let value as String:
            return ["1", "true", "yes"].contains(value.lowercased())
        default:
            return false
        }
    }
}
