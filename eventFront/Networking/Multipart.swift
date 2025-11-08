import Foundation

struct Multipart {
    static func request(path: String, fileData: Data, fileName: String, field: String = "file") -> URLRequest {
        let boundary = "boundary-\(UUID().uuidString)"
        var req = APIConfig.authedRequest(path, method: "POST",
                                          headers: ["Content-Type":"multipart/form-data; boundary=\(boundary)"])
        var body = Data()
        func append(_ s: String) { body.append(s.data(using: .utf8)!) }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(field)\"; filename=\"\(fileName)\"\r\n")
        append("Content-Type: application/octet-stream\r\n\r\n")
        body.append(fileData)
        append("\r\n--\(boundary)--\r\n")
        req.httpBody = body
        return req
    }
}
