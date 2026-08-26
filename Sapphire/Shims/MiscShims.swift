//
//  MiscShims.swift — FORK-ONLY SHIM
//  Stand-in for closed-source upstream modules Sapphire/Services/{CircleToSearch,Monitoring,
//  ConnectedAccounts}, Sapphire/Widgets/CircleToSearch and Sapphire/Services/Weather/WeatherAPIKey,
//  which are gitignored in cshariq/Sapphire and therefore absent from this repo. These definitions
//  exist ONLY so the fork compiles. They are inert. Delete this whole folder before proposing
//  anything upstream.
//

import SwiftUI
import AppKit
import CryptoKit

// MARK: - Circle to Search

/// Non-isolated so it is callable from every existing call site without isolation churn.
/// AppDelegate forces `.shared` to init at launch; upstream installs a hotkey + screen capture
/// monitor there, so this init must stay empty — no event taps, no recording permission prompt.
final class CircleToSearchManager {
    static let shared = CircleToSearchManager()
    private init() {}

    func endResultsPresentation() {}
}

struct CircleToSearchResultsView: View {
    let navigationStack: Binding<[NotchWidgetMode]>

    var body: some View {
        ShimUnavailableView()
            .frame(width: 380, height: 160)
    }
}

extension Notification.Name {
    /// Only observed in-repo (NotchController); the poster lived in the withheld module.
    static let sapphireOpenCircleToSearch = Notification.Name("sapphireOpenCircleToSearch")
}

// MARK: - Smart inbox (OTP + parcel tracking)

struct OTPEvent: Equatable, Identifiable {
    let id: String
    let code: String
    let source: String
    let title: String
    let body: String
    let date: Date
}

enum ParcelCarrier: String, Codable, CaseIterable {
    case ups, fedex, usps, dhl, amazon, other

    var displayName: String {
        switch self {
        case .ups: return "UPS"
        case .fedex: return "FedEx"
        case .usps: return "USPS"
        case .dhl: return "DHL"
        case .amazon: return "Amazon"
        case .other: return "Carrier"
        }
    }
}

struct ParcelShipment: Identifiable, Equatable {
    let id: String
    let carrier: ParcelCarrier
    let title: String
    let status: String
    let trackingNumber: String
    let trackingURL: URL?
    let detail: String
    let isDelivered: Bool
}

/// Non-isolated: reached from @MainActor LiveActivityManager, from a `Task { @MainActor }` in
/// NotificationManager, and from a SwiftUI view's dispatch closure. Nothing ever populates
/// `latestOTP` or `activeParcels` here — the two `@Published`s exist because their `$` publishers
/// are wired into LiveActivityManager's Combine trigger list.
final class SmartInboxMonitor: ObservableObject {
    static let shared = SmartInboxMonitor()
    private init() {}

    @Published var latestOTP: OTPEvent?
    @Published var activeParcels: [ParcelShipment] = []

    private var consumedCodes = Set<String>()

    // ponytail: no Mail scraping, no carrier lookup. Only the consumed-code set is real, so the
    // notification-derived OTP path in LiveActivityManager still de-dupes instead of looping.
    func presentOTP(code: String, source: String, title: String, body: String) {}
    func consumeOTP(_ code: String) { consumedCodes.insert(code) }
    func hasConsumedOTP(_ code: String) -> Bool { consumedCodes.contains(code) }
    func dismissOTP() { latestOTP = nil }
}

enum VerificationCodeDetector {
    /// ponytail: detection disabled — returns nil, so `NotificationPayload.verificationCode` is
    /// always nil and the OTP live activity never fires. Add a pattern match here to re-enable.
    static func find(in text: String) -> String? { nil }
}

// MARK: - Monitoring / data viewer

enum MonitorType: String, CaseIterable {
    case unavailable

    var icon: String { "questionmark.circle" }
    var displayName: String { "Unavailable" }
}

struct DataSummary: Sendable {
    let totalDataPoints: Int
    let databaseSizeMB: Double
    let countsByMonitorType: [String: Int]
    let oldestEntry: Date?
    let newestEntry: Date?
}

/// Non-isolated: `MemorySystemManager.shared` is a stored-property initializer on a plain struct
/// view, and `getDataSummary()` is called (sync + throwing) from inside `Task.detached`.
final class MemorySystemManager {
    static let shared = MemorySystemManager()
    private init() {}

    // ponytail: no monitoring database exists in the fork, so the viewer renders an empty summary
    // (its by-monitor-type and date-range sections guard on emptiness and are skipped).
    func getDataSummary() throws -> DataSummary {
        DataSummary(
            totalDataPoints: 0,
            databaseSizeMB: 0,
            countsByMonitorType: [:],
            oldestEntry: nil,
            newestEntry: nil
        )
    }
}

// MARK: - Encryption

/// Non-isolated: used from `Task.detached` inside UserProfileManager with no `await`.
/// NOTE: identity passthrough — this fork stores the personal profile UNENCRYPTED in UserDefaults.
final class EncryptionManager {
    static let shared = EncryptionManager()
    private init() {}

    // ponytail: no key material to shim. Round-trips correctly with the JSONEncoder/Decoder pair
    // in UserProfileManager; swap in real AES-GCM (and a Keychain-held key) to restore at-rest
    // encryption.
    func encrypt(_ data: Data) throws -> Data { data }
    func decrypt(_ data: Data) throws -> Data { data }
}

enum ModelSecurity {
    /// ponytail: throwaway key. The only consumer decrypts
    /// Sapphire/Services/FaceID/Models/PassiveLiveness.enc, which is itself gitignored and absent,
    /// so that code path is unreachable and returns nil on failure.
    static let encryptionKey = SymmetricKey(size: .bits256)
}

// MARK: - Weather

enum WeatherAPIKey {
    /// Never ship a key here. WeatherService already prefers $WEATHER_API_KEY and
    /// ~/.sapphire/WeatherConfig.plist, and guards on `!isEmpty` before calling api.weather.com.
    static let value = ""
}

// MARK: - Image encoding

/// `jpegData(maxPixel:quality:)` is called by GeminiLiveManager's screen-share path but is declared
/// in one of the withheld modules. Unlike the rest of this folder this one is real: it is a pure
/// pixel helper with no upstream secret in it.
extension NSImage {
    func jpegData(maxPixel: CGFloat, quality: CGFloat) -> Data? {
        guard var cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

        let longEdge = CGFloat(max(cgImage.width, cgImage.height))
        if longEdge > maxPixel, longEdge > 0 {
            let scale = maxPixel / longEdge
            let width = max(1, Int((CGFloat(cgImage.width) * scale).rounded()))
            let height = max(1, Int((CGFloat(cgImage.height) * scale).rounded()))
            if let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) {
                context.interpolationQuality = .high
                context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
                if let scaled = context.makeImage() { cgImage = scaled }
            }
        }

        return NSBitmapImageRep(cgImage: cgImage)
            .representation(using: .jpeg, properties: [.compressionFactor: quality])
    }
}
