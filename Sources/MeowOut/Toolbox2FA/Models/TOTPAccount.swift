import Foundation

public enum TOTPAlgorithm: String, Codable {
    case SHA1 = "SHA1"
    case SHA256 = "SHA256"
    case SHA512 = "SHA512"
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self).uppercased()
        if let alg = TOTPAlgorithm(rawValue: value) {
            self = alg
        } else {
            self = .SHA1
        }
    }
}

public struct TOTPAccount: Codable, Identifiable, Equatable, CustomDebugStringConvertible, CustomStringConvertible {
    public let uuid: String
    public var name: String
    public var issuer: String
    public var group: String
    public var secret: String
    public var icon: String
    public var algorithm: TOTPAlgorithm?
    public var period: Int?
    public var digits: Int?
    
    public var id: String { uuid }
    
    public init(uuid: String = UUID().uuidString, name: String, issuer: String = "", group: String = "", secret: String, icon: String = "", algorithm: TOTPAlgorithm? = .SHA1, period: Int? = 30, digits: Int? = 6) {
        self.uuid = uuid
        self.name = name
        self.issuer = issuer
        self.group = group
        self.secret = secret
        self.icon = icon
        self.algorithm = algorithm
        self.period = period
        self.digits = digits
    }
    
    public var debugDescription: String {
        return description
    }
    
    public var description: String {
        return "TOTPAccount(uuid: \(uuid), name: \(name), issuer: \(issuer), group: \(group), secret: <REDACTED>, icon: \(icon), algorithm: \(algorithm?.rawValue ?? "nil"), period: \(period ?? 30), digits: \(digits ?? 6))"
    }
}
