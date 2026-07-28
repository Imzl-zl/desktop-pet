import Foundation

public struct ProjectPetMapping: Codable, Equatable, Sendable {
    public var projectPath: String
    public var petID: String
    public init(projectPath: String, petID: String) {
        self.projectPath = projectPath
        self.petID = petID
    }
}
