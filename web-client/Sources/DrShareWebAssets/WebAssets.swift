import Foundation

public enum DrShareWebAssets {
    public struct Asset {
        public let data: Data
        public let contentType: String

        public init(data: Data, contentType: String) {
            self.data = data
            self.contentType = contentType
        }
    }

    public static func asset(for requestPath: String) -> Asset? {
        let normalizedPath = normalize(requestPath)

        switch normalizedPath {
        case "/":
            return load(name: "index", extension: "html", contentType: "text/html; charset=utf-8")
        case "/app.css":
            return load(name: "app", extension: "css", contentType: "text/css; charset=utf-8")
        case "/app.js":
            return load(name: "app", extension: "js", contentType: "application/javascript; charset=utf-8")
        case "/manifest.json":
            return load(name: "manifest", extension: "json", contentType: "application/manifest+json; charset=utf-8")
        case "/sw.js":
            return load(name: "sw", extension: "js", contentType: "application/javascript; charset=utf-8")
        case "/icon.svg":
            return load(name: "icon", extension: "svg", contentType: "image/svg+xml")
        default:
            return nil
        }
    }

    private static func normalize(_ requestPath: String) -> String {
        if requestPath == "/index.html" {
            return "/"
        }

        return requestPath
    }

    private static func load(name: String, extension: String, contentType: String) -> Asset? {
        guard let url = Bundle.module.url(forResource: name, withExtension: `extension`) else {
            return nil
        }

        guard let data = try? Data(contentsOf: url) else {
            return nil
        }

        return Asset(data: data, contentType: contentType)
    }
}
