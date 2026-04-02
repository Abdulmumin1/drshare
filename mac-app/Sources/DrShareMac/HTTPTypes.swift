import Foundation

import DrShareShared

struct HTTPRequestHead {
    let method: String
    let target: String
    let path: String
    let query: [String: String]
    let headers: [String: String]
    let contentLength: Int
}

struct HTTPRequest {
    let method: String
    let target: String
    let path: String
    let query: [String: String]
    let headers: [String: String]
    let body: Data
}

struct HTTPResponse {
    let statusCode: Int
    let reasonPhrase: String
    let headers: [String: String]
    let body: Data

    func serialized() -> Data {
        var response = "HTTP/1.1 \(statusCode) \(reasonPhrase)\r\n"

        for (header, value) in headers {
            response += "\(header): \(value)\r\n"
        }

        response += "Content-Length: \(body.count)\r\n"
        response += "Connection: close\r\n"
        response += "\r\n"

        var data = Data(response.utf8)
        data.append(body)
        return data
    }

    static func json<T: Encodable>(_ payload: T, statusCode: Int = 200, reasonPhrase: String = "OK") -> HTTPResponse {
        let body = (try? JSONCodec.makeEncoder().encode(payload)) ?? Data()
        return HTTPResponse(
            statusCode: statusCode,
            reasonPhrase: reasonPhrase,
            headers: [
                "Content-Type": "application/json; charset=utf-8",
            ],
            body: body
        )
    }

    static func html(_ body: Data) -> HTTPResponse {
        HTTPResponse(
            statusCode: 200,
            reasonPhrase: "OK",
            headers: [
                "Content-Type": "text/html; charset=utf-8",
            ],
            body: body
        )
    }

    static func asset(_ body: Data, contentType: String) -> HTTPResponse {
        HTTPResponse(
            statusCode: 200,
            reasonPhrase: "OK",
            headers: [
                "Content-Type": contentType,
            ],
            body: body
        )
    }

    static func binary(
        _ body: Data,
        contentType: String,
        contentDisposition: String? = nil
    ) -> HTTPResponse {
        var headers = [
            "Content-Type": contentType,
        ]

        if let contentDisposition {
            headers["Content-Disposition"] = contentDisposition
        }

        return HTTPResponse(
            statusCode: 200,
            reasonPhrase: "OK",
            headers: headers,
            body: body
        )
    }

    static func empty(statusCode: Int, reasonPhrase: String) -> HTTPResponse {
        HTTPResponse(
            statusCode: statusCode,
            reasonPhrase: reasonPhrase,
            headers: [:],
            body: Data()
        )
    }
}

enum HTTPRequestParser {
    private static let separator = Data("\r\n\r\n".utf8)

    static func parse(from buffer: inout Data) -> HTTPRequest? {
        if buffer.range(of: separator) != nil, parseHead(from: buffer) == nil {
            buffer.removeAll()
            return nil
        }

        guard let (head, bodyStart) = parseHead(from: buffer) else {
            return nil
        }

        let totalLength = bodyStart + head.contentLength
        guard buffer.count >= totalLength else {
            return nil
        }

        let body = Data(buffer[bodyStart..<totalLength])
        buffer.removeSubrange(0..<totalLength)

        return HTTPRequest(
            method: head.method,
            target: head.target,
            path: head.path,
            query: head.query,
            headers: head.headers,
            body: body
        )
    }

    static func parseHead(from buffer: Data) -> (HTTPRequestHead, Int)? {
        guard let headerRange = buffer.range(of: separator) else {
            return nil
        }

        let headerData = buffer[..<headerRange.lowerBound]
        guard let headerString = String(data: headerData, encoding: .utf8) else {
            return nil
        }

        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            return nil
        }

        let requestLineParts = requestLine.split(separator: " ")
        guard requestLineParts.count == 3 else {
            return nil
        }

        let headers = parseHeaders(Array(lines.dropFirst()))
        let contentLength = Int(headers["content-length"] ?? "") ?? 0
        let bodyStart = headerRange.upperBound

        let target = String(requestLineParts[1])
        let components = URLComponents(string: "http://localhost\(target)")
        let queryItems = components?.queryItems ?? []
        let query = Dictionary(uniqueKeysWithValues: queryItems.map { ($0.name, $0.value ?? "") })

        let head = HTTPRequestHead(
            method: String(requestLineParts[0]).uppercased(),
            target: target,
            path: components?.path ?? target,
            query: query,
            headers: headers,
            contentLength: max(contentLength, 0)
        )

        return (head, bodyStart)
    }

    private static func parseHeaders(_ lines: [String]) -> [String: String] {
        var result: [String: String] = [:]

        for line in lines {
            guard let separatorIndex = line.firstIndex(of: ":") else {
                continue
            }

            let name = line[..<separatorIndex]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let value = line[line.index(after: separatorIndex)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            result[name] = value
        }

        return result
    }
}
