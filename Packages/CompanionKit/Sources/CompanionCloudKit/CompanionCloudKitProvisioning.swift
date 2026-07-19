import Foundation

public enum CompanionCloudKitProvisioning {
    public static let infoDictionaryKey =
        "ChessantoCloudKitContainerIdentifier"

    public static func containerIdentifier(
        bundle: Bundle = .main
    ) -> String? {
        containerIdentifier(infoDictionary: bundle.infoDictionary ?? [:])
    }

    public static func containerIdentifier(
        infoDictionary: [String: Any]
    ) -> String? {
        guard
            let identifier =
                infoDictionary[infoDictionaryKey] as? String,
            identifier.hasPrefix("iCloud."),
            !identifier.isEmpty
        else {
            return nil
        }
        return identifier
    }
}
