import Foundation

public enum ConfirmationPolicy: String, Codable, CaseIterable, Sendable {
    case always
    case riskyOnly
    case never
}

public struct ActionRoute: Codable, Sendable, Identifiable {
    public var id: UUID
    public var pattern: String
    public var actionType: String
    public var payload: String

    public init(id: UUID = UUID(), pattern: String, actionType: String, payload: String) {
        self.id = id
        self.pattern = pattern
        self.actionType = actionType
        self.payload = payload
    }
}

public struct ActionProfile: Codable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var confirmationPolicy: ConfirmationPolicy
    public var routes: [ActionRoute]

    public init(
        id: UUID = UUID(),
        name: String,
        confirmationPolicy: ConfirmationPolicy = .riskyOnly,
        routes: [ActionRoute] = []
    ) {
        self.id = id
        self.name = name
        self.confirmationPolicy = confirmationPolicy
        self.routes = routes
    }
}
