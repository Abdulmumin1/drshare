import Foundation

enum LocalAddressResolver {
    static func baseURLs(port: UInt16) -> [String] {
        var urls = ipv4Addresses().map { "http://\($0):\(port)" }
        urls.append("http://127.0.0.1:\(port)")
        return Array(NSOrderedSet(array: urls)) as? [String] ?? urls
    }

    private static func ipv4Addresses() -> [String] {
        var addresses: [String] = []
        var pointer: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&pointer) == 0, let firstAddress = pointer else {
            return addresses
        }

        defer {
            freeifaddrs(pointer)
        }

        var current = firstAddress

        while true {
            let interface = current.pointee
            let flags = Int32(interface.ifa_flags)
            let isUp = (flags & IFF_UP) == IFF_UP
            let isLoopback = (flags & IFF_LOOPBACK) == IFF_LOOPBACK

            if
                isUp,
                !isLoopback,
                let address = interface.ifa_addr,
                address.pointee.sa_family == UInt8(AF_INET)
            {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let result = getnameinfo(
                    address,
                    socklen_t(address.pointee.sa_len),
                    &hostname,
                    socklen_t(hostname.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                )

                if result == 0 {
                    let bytes = hostname.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
                    let candidate = String(decoding: bytes, as: UTF8.self)
                    if !candidate.hasPrefix("169.254.") {
                        addresses.append(candidate)
                    }
                }
            }

            guard let next = interface.ifa_next else {
                break
            }

            current = next
        }

        return Array(NSOrderedSet(array: addresses)) as? [String] ?? addresses
    }
}
