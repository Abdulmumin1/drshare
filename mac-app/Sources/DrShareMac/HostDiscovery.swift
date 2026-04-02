import Foundation
import Network

enum HostDiscovery {
    static let serviceType = "_drshare._tcp"
    static let serviceLabel = "Bonjour"

    static var defaultServiceName: String {
        let machineName = Host.current().localizedName?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let machineName, !machineName.isEmpty {
            return "drshare on \(machineName)"
        }

        return "drshare"
    }

    static func makeService() -> NWListener.Service {
        let txtRecord = NWTXTRecord([
            "app": "drshare",
            "cap": "text,file",
            "ver": "0.1.0",
        ])

        return NWListener.Service(
            name: defaultServiceName,
            type: serviceType,
            domain: nil,
            txtRecord: txtRecord
        )
    }

    static func fallbackStatusDescription() -> String {
        "\(defaultServiceName) \(serviceType)"
    }
}
