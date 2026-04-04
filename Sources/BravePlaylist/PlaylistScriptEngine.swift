import Foundation

public enum PlaylistScriptError: Error, LocalizedError {
    case missingResource(String)

    public var errorDescription: String? {
        switch self {
        case .missingResource(let name):
            "Missing bundled Brave playlist script resource: \(name)"
        }
    }
}

public struct PlaylistScriptConfiguration: Hashable, Sendable {
    public let messageHandlerName: String
    public let securityToken: String
    public let tagAttributeName: String
    public let sendMessageTimeoutName: String
    public let longPressFunctionName: String
    public let processDocumentLoadFunctionName: String
    public let currentTimeFunctionName: String
    public let stopPlaybackFunctionName: String
    public let telemetryAttachedName: String
    public let telemetryHeartbeatName: String

    public init(
        messageHandlerName: String,
        securityToken: String = UUID().uuidString,
        namespaceToken: String = UUID().uuidString.replacingOccurrences(of: "-", with: "")
    ) {
        self.messageHandlerName = messageHandlerName
        self.securityToken = securityToken
        self.tagAttributeName = "tagId_\(namespaceToken)"
        self.sendMessageTimeoutName = "smt_\(namespaceToken)"
        self.longPressFunctionName = "playlistLongPressed_\(namespaceToken)"
        self.processDocumentLoadFunctionName = "playlistProcessDocumentLoad_\(namespaceToken)"
        self.currentTimeFunctionName = "mediaCurrentTimeFromTag_\(namespaceToken)"
        self.stopPlaybackFunctionName = "stopMediaPlayback_\(namespaceToken)"
        self.telemetryAttachedName = "playlistTelemetryAttached_\(namespaceToken)"
        self.telemetryHeartbeatName = "playlistTelemetryHeartbeat_\(namespaceToken)"
    }
}

public struct PlaylistBuiltScriptSet: Sendable {
    public let configuration: PlaylistScriptConfiguration
    public let firefoxShimSource: String
    public let mediaSourceOverrideSource: String
    public let detectorSource: String

    public var processDocumentLoadJavaScript: String {
        "window.__firefox__.\(configuration.processDocumentLoadFunctionName)()"
    }
}

public enum PlaylistScriptEngine {
    public static func makeScriptSet(
        configuration: PlaylistScriptConfiguration
    ) throws -> PlaylistBuiltScriptSet {
        let firefoxShimSource = try loadResource(named: "__firefox__")
        let swizzler = try loadResource(named: "PlaylistSwizzlerScript")
        let detector = try loadResource(named: "PlaylistScript")

        let detectorSource = secureScript(
            handlerNamesMap: [
                "$<message_handler>": configuration.messageHandlerName,
                "$<tagUUID>": configuration.tagAttributeName,
                "$<sendMessageTimeout>": configuration.sendMessageTimeoutName,
                "$<playlistLongPressed>": configuration.longPressFunctionName,
                "$<playlistProcessDocumentLoad>": configuration.processDocumentLoadFunctionName,
                "$<mediaCurrentTimeFromTag>": configuration.currentTimeFunctionName,
                "$<stopMediaPlayback>": configuration.stopPlaybackFunctionName,
                "$<telemetryAttached>": configuration.telemetryAttachedName,
                "$<telemetryHeartbeat>": configuration.telemetryHeartbeatName,
            ],
            securityToken: configuration.securityToken,
            script: detector
        )

        let mediaSourceOverrideSource = secureScript(
            handlerNamesMap: [:],
            securityToken: "",
            script: swizzler
        )

        return PlaylistBuiltScriptSet(
            configuration: configuration,
            firefoxShimSource: firefoxShimSource,
            mediaSourceOverrideSource: mediaSourceOverrideSource,
            detectorSource: detectorSource
        )
    }

    public static func secureScript(
        handlerNamesMap: [String: String],
        securityToken: String,
        script: String
    ) -> String {
        guard !script.isEmpty else {
            return script
        }

        let substituted = handlerNamesMap.reduce(script) { partial, pair in
            partial.replacingOccurrences(of: pair.key, with: pair.value)
        }

        let messageHandlers: String = {
            guard !handlerNamesMap.isEmpty else {
                return ""
            }
            let handlers = handlerNamesMap.values.map { "'\($0)'" }.joined(separator: ", ")
            return """
            [\(handlers)].forEach((handlerName) => {
              if (handlerName && handlerName.length > 0 && window.webkit?.messageHandlers?.[handlerName]) {
                Object.freeze(window.webkit.messageHandlers[handlerName]);
                Object.freeze(window.webkit.messageHandlers[handlerName].postMessage);
              }
            });
            """
        }()

        return """
        (function() {
          const SECURITY_TOKEN = '\(securityToken)';

          \(messageHandlers)

          \(substituted)
        })();
        """
    }

    private static func loadResource(named name: String) throws -> String {
        let url =
            Bundle.module.url(forResource: name, withExtension: "js", subdirectory: "UserScripts")
            ?? Bundle.module.url(forResource: name, withExtension: "js")
        guard let url,
              let source = try? String(contentsOf: url)
        else {
            throw PlaylistScriptError.missingResource(name)
        }
        return source
    }
}
