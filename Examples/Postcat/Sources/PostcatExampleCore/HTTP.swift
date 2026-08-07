import Foundation

public enum RequestError: LocalizedError {
  case invalidURL(String)
  case nonHTTPResponse

  public var errorDescription: String? {
    switch self {
    case .invalidURL(let value): "Invalid URL: \(value)"
    case .nonHTTPResponse: "The server did not return an HTTP response."
    }
  }
}

private func reasonPhrase(for status: Int) -> String {
  switch status {
  case 200: "OK"
  case 201: "Created"
  case 202: "Accepted"
  case 204: "No Content"
  case 400: "Bad Request"
  case 401: "Unauthorized"
  case 403: "Forbidden"
  case 404: "Not Found"
  case 500: "Internal Server Error"
  default: HTTPURLResponse.localizedString(forStatusCode: status).capitalized
  }
}

public func liveRequestSender(session: URLSession = .shared) -> RequestSender {
  { request in
    guard let url = URL(string: request.url), url.scheme != nil else {
      throw RequestError.invalidURL(request.url)
    }
    var urlRequest = URLRequest(url: url)
    urlRequest.httpMethod = request.method.rawValue
    if !request.body.isEmpty, request.method != .get {
      urlRequest.httpBody = Data(request.body.utf8)
      urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }

    let clock = ContinuousClock()
    let started = clock.now
    let (data, response) = try await session.data(for: urlRequest)
    guard let response = response as? HTTPURLResponse else { throw RequestError.nonHTTPResponse }
    let elapsed = started.duration(to: clock.now)
    let milliseconds =
      Int(elapsed.components.seconds * 1_000)
      + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
    let headers = response.allHeaderFields.compactMap { key, value -> (String, String)? in
      guard let key = key as? String else { return nil }
      return (key, String(describing: value))
    }.sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
    return APIResponse(
      status: response.statusCode,
      reason: reasonPhrase(for: response.statusCode),
      headers: headers,
      body: String(decoding: data, as: UTF8.self),
      durationMilliseconds: milliseconds,
      size: data.count
    )
  }
}
