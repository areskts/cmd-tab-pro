import Foundation

@main
private enum CodeSignatureTests {
    static func main() {
        let arguments = CommandLine.arguments
        precondition(arguments.count == 6)
        let original = URL(fileURLWithPath: arguments[1])
        let updated = URL(fileURLWithPath: arguments[2])
        let adhoc = URL(fileURLWithPath: arguments[3])
        let tampered = URL(fileURLWithPath: arguments[4])
        guard let signature = CodeSignature(original), let updatedSignature = CodeSignature(updated),
              let adhocSignature = CodeSignature(adhoc) else { fatalError("fixture signature unavailable") }
        precondition(signature.identity == arguments[5], "certificate fingerprint selects the existing signing key")
        precondition(updatedSignature.identity == signature.identity, "updates retain the same signing identity")
        let executable = "Contents/MacOS/CmdTabPro"
        precondition(try! Data(contentsOf: original.appendingPathComponent(executable)) != Data(contentsOf: updated.appendingPathComponent(executable)), "fixtures must contain different signed binaries")
        precondition(signature.matches(original) && signature.matches(updated), "the original designated requirement accepts both versions")
        precondition(adhocSignature.identity == "-" && adhocSignature.matches(adhoc), "existing ad-hoc builds remain identifiable")
        precondition(!signature.matches(adhoc), "ad-hoc re-signing cannot impersonate the certificate build")
        precondition(!adhocSignature.matches(original), "ad-hoc identity is tied to the specific binary")
        precondition(CodeSignature(tampered) == nil && !signature.matches(tampered), "modified bundle resources fail signature validation")
        precondition(CodeSignature(URL(fileURLWithPath: "/nonexistent/CmdTabPro.app")) == nil, "unavailable code never selects an ad-hoc fallback")
        print("code signing tests passed (9 checks)")
    }
}
