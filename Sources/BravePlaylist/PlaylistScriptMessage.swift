import Foundation

public struct PlaylistReadyState: Codable, Hashable, Sendable {
    public let state: String

    public init(state: String) {
        self.state = state
    }

    public var isCancellation: Bool {
        state == "cancel"
    }

    public static func decode(from body: Any) -> PlaylistReadyState? {
        guard JSONSerialization.isValidJSONObject(body),
              let data = try? JSONSerialization.data(withJSONObject: body, options: [.fragmentsAllowed])
        else {
            return nil
        }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
}

public enum PlaylistScriptMessage: Hashable, Sendable {
    case readyState(PlaylistReadyState)
    case media(PlaylistInfo)
}

public enum PlaylistScriptMessageDecoder {
    public static func decode(
        body: Any,
        expectingSecurityToken securityToken: String? = nil
    ) -> PlaylistScriptMessage? {
        guard let payload = body as? [String: Any] else {
            return nil
        }

        if let securityToken,
           payload["securityToken"] as? String != securityToken {
            return nil
        }

        if payload["state"] != nil,
           let readyState = PlaylistReadyState.decode(from: payload) {
            return .readyState(readyState)
        }

        if let info = PlaylistInfo.decode(from: payload) {
            return .media(info)
        }

        return nil
    }

}
