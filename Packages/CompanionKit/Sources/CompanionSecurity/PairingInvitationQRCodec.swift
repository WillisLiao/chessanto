import CompanionDomain
import Foundation

public enum PairingInvitationQRCodecError: Error {
    case invalidURL
    case invalidPayload
}

public enum PairingInvitationQRCodec {
    public static func encode(_ invitation: PairingInvitation) throws -> String {
        let payload = try CanonicalCoding.encode(invitation)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "chessanto://pair?v=1&invitation=\(payload)"
    }

    public static func decode(_ value: String) throws -> PairingInvitation {
        guard
            let components = URLComponents(string: value),
            components.scheme == "chessanto",
            components.host == "pair",
            components.queryItems?.first(where: { $0.name == "v" })?.value == "1",
            let payload = components.queryItems?
                .first(where: { $0.name == "invitation" })?.value
        else {
            throw PairingInvitationQRCodecError.invalidURL
        }
        var base64 = payload
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - base64.count % 4) % 4
        base64.append(String(repeating: "=", count: padding))
        guard let data = Data(base64Encoded: base64) else {
            throw PairingInvitationQRCodecError.invalidPayload
        }
        return try CanonicalCoding.decode(PairingInvitation.self, from: data)
    }
}
