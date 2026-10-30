import CryptoKit
import Foundation

/// CI startup check for the packaged executable; never opens windows, requests a camera, or loads user records.
enum BundleVerification {
    static func run() -> Int32 {
        do {
            let bundle = Bundle.main
            guard bundle.bundleIdentifier == "local.still.app",
                  let model = bundle.url(forResource: "StillPose", withExtension: "mlmodel"),
                  let source = bundle.url(forResource: "PoseModelSource", withExtension: "json"),
                  let license = bundle.url(forResource: "LICENSE-OpenPose", withExtension: "txt") else {
                throw NSError(domain: "Still.Bundle", code: 1, userInfo: [NSLocalizedDescriptionKey: "Incomplete app bundle"])
            }
            let metadata = try JSONSerialization.jsonObject(with: Data(contentsOf: source)) as? [String: Any]
            let digest = SHA256.hash(data: try Data(contentsOf: model)).map { String(format: "%02x", $0) }.joined()
            guard metadata?["modelSHA256"] as? String == digest, !(try Data(contentsOf: license)).isEmpty else {
                throw NSError(domain: "Still.Bundle", code: 2, userInfo: [NSLocalizedDescriptionKey: "Model digest or license is invalid"])
            }
            let cache = FileManager.default.temporaryDirectory.appendingPathComponent("Still-BundleCheck-" + UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: cache) }
            try OpenPoseDetector(source: model, cache: cache).prepare()
            #if arch(arm64)
            let architecture = "arm64"
            #else
            let architecture = "x86_64"
            #endif
            let report: [String: Any] = [
                "bundleIdentifier": bundle.bundleIdentifier!,
                "version": bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
                "build": bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
                "minimumSystemVersion": bundle.object(forInfoDictionaryKey: "LSMinimumSystemVersion") as? String ?? "",
                "runtimeArchitecture": architecture,
                "operatingSystem": ProcessInfo.processInfo.operatingSystemVersionString,
                "postureModel": "loaded", "modelSHA256": digest
            ]
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data("\n".utf8))
            return 0
        } catch {
            FileHandle.standardError.write(Data("Bundle verification failed: \(error.localizedDescription)\n".utf8))
            return 1
        }
    }
}
