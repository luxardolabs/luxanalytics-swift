import Foundation

/// Configuration for certificate pinning
public struct CertificatePinningConfig: Sendable, CustomDebugStringConvertible {
    /// SHA256 hashes of pinned certificates (in base64)
    public let pinnedCertificateHashes: Set<String>

    /// Whether to allow self-signed certificates
    public let allowSelfSigned: Bool

    /// Whether to validate the entire certificate chain
    public let validateChain: Bool

    public init(
        pinnedCertificateHashes: Set<String>,
        allowSelfSigned: Bool = false,
        validateChain: Bool = true
    ) {
        self.pinnedCertificateHashes = pinnedCertificateHashes
        self.allowSelfSigned = allowSelfSigned
        self.validateChain = validateChain
    }

    public var debugDescription: String {
        let hashes = pinnedCertificateHashes.sorted().prefix(3).joined(separator: ",")
        return "pins:\(hashes)-selfSigned:\(allowSelfSigned)-chain:\(validateChain)"
    }
}
