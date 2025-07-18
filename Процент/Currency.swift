import Foundation

struct Currency: Identifiable, Equatable {
    var id: String { code }
    let code: String
    let name: String
    let flagName: String
    var rate: Double
}
