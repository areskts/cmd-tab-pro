import CryptoKit
import Foundation
import Security

struct CodeSignature {
    let identity: String
    private let requirement: SecRequirement

    init?(_ url: URL) {
        var code: SecStaticCode?
        var information: CFDictionary?
        var requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess,
              let code,
              SecStaticCodeCheckValidity(code, [], nil) == errSecSuccess,
              SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let information = information as? [String: Any],
              let flags = information[kSecCodeInfoFlags as String] as? UInt32,
              SecCodeCopyDesignatedRequirement(code, [], &requirement) == errSecSuccess,
              let requirement else { return nil }
        self.requirement = requirement
        if SecCodeSignatureFlags(rawValue: flags).contains(.adhoc) {
            identity = "-"
            return
        }
        guard let certificates = information[kSecCodeInfoCertificates as String] as? [SecCertificate],
              let certificate = certificates.first else { return nil }
        // codesign selects keychain identities by their certificate's SHA-1 fingerprint.
        identity = Insecure.SHA1.hash(data: SecCertificateCopyData(certificate) as Data)
            .map { String(format: "%02X", $0) }.joined()
    }

    func matches(_ url: URL) -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess,
              let code else { return false }
        return SecStaticCodeCheckValidity(code, [], requirement) == errSecSuccess
    }
}
