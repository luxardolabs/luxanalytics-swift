import CryptoKit
import Foundation
import Synchronization

/// The SDK's network layer: the only code that touches `URLSession`.
///
/// It builds the ingest request for an already-encoded payload and returns the
/// raw HTTP status and body. Deciding what a status means (retry, drop, record)
/// stays with the caller.
enum NetworkTransport {
    /// Send one payload to the project's ingest endpoint.
    /// - Parameters:
    ///   - payload: The request body, already compressed when `deflated` is true.
    ///   - deflated: Whether to mark the body `Content-Encoding: deflate`.
    ///   - config: Endpoint, credentials, timeout and pinning.
    /// - Returns: The HTTP status code and response body.
    /// - Throws: A transport error, or `URLError(.badServerResponse)` when the
    ///   response is not HTTP.
    static func send(
        _ payload: Data,
        deflated: Bool,
        config: LuxAnalyticsConfiguration
    ) async throws -> (statusCode: Int, body: Data) {
        var request = URLRequest(url: config.apiURL.appendingPathComponent(config.projectId))
        request.httpMethod = "POST"
        request.httpBody = payload
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(LuxAnalyticsVersion.fullVersion, forHTTPHeaderField: "User-Agent")
        if deflated {
            request.setValue("deflate", forHTTPHeaderField: "Content-Encoding")
        }
        // The DSN's public id is the Basic-auth user, with an empty password.
        let credentials = Data("\(config.publicId):".utf8).base64EncodedString()
        request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = config.requestTimeout

        let session = URLSession.analyticsSession(with: config.certificatePinning)
        let (body, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (http.statusCode, body)
    }
}

/// URLSession delegate for certificate pinning
final class CertificatePinningDelegate: NSObject, URLSessionDelegate {
    private let config: CertificatePinningConfig?

    init(config: CertificatePinningConfig?) {
        self.config = config
        super.init()
    }

    deinit {
        SecureLogger.log("CertificatePinningDelegate deinit", category: .general, level: .debug)
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard let config = config,
            challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
            let serverTrust = challenge.protectionSpace.serverTrust
        else {
            // No pinning configured or not a server trust challenge
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Evaluate server trust
        var error: CFError?
        let isValid = SecTrustEvaluateWithError(serverTrust, &error)

        if !isValid && !config.allowSelfSigned {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Get certificate chain
        var certificateHashes: Set<String> = []

        if let certificates = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate] {
            for (index, certificate) in certificates.enumerated() {

                // Get certificate data
                let certificateData = SecCertificateCopyData(certificate) as Data

                // Calculate SHA256 hash
                let hash = SHA256.hash(data: certificateData)
                let hashBase64 = Data(hash).base64EncodedString()
                certificateHashes.insert(hashBase64)

                // If we're not validating the chain, only check the leaf certificate
                if !config.validateChain && index == 0 {
                    break
                }
            }
        }

        // Check if any pinned certificate matches
        if !config.pinnedCertificateHashes.isEmpty {
            let matchFound = !config.pinnedCertificateHashes.isDisjoint(with: certificateHashes)

            if matchFound {
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
            } else {
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
        } else {
            // No pins configured, accept if trust evaluation passed
            if isValid || config.allowSelfSigned {
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
            } else {
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
        }
    }
}

// MARK: - URLSession Extension

extension URLSession {
    private static let sessionCache = Mutex<[String: URLSession]>([:])

    /// Create or reuse a URLSession with certificate pinning
    static func analyticsSession(with config: CertificatePinningConfig?) -> URLSession {
        let cacheKey = config?.debugDescription ?? "no-pinning"

        return sessionCache.withLock { cache in
            if let cached = cache[cacheKey] {
                return cached
            }

            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 60

            let delegate = config != nil ? CertificatePinningDelegate(config: config) : nil
            let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)

            cache[cacheKey] = session
            return session
        }
    }
}
