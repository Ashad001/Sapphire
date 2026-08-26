//
//  SubscriptionShims.swift — FORK-ONLY SHIM
//  Stand-in for closed-source upstream module Sapphire/SubscriptionKit, which is gitignored in
//  cshariq/Sapphire and therefore absent from this repo. These definitions exist ONLY so the fork
//  compiles. They are inert. Delete this whole folder before proposing anything upstream.
//
//  Entitlement checks are deliberately permissive (always true): the fork cannot render the real
//  paywall, so gating behind one would dead-end the UI.
//

import SwiftUI
import Combine

// MARK: - Feature / tier vocabulary

/// Only the seven features actually referenced in open-source call sites. No exhaustive switch over
/// this type exists in-repo, so upstream's real (larger) case set is not needed to compile.
enum AppFeature: String, Hashable, CaseIterable {
    case sportsWidget
    case financeWidget
    case liveSports
    case financeLiveActivity
    case geminiLive
    case betaSoftwareUpdates
    case advancedFileConversion
}

/// Exactly four cases — OnboardingView.onboardingTierRank switches over these with no `default:`,
/// so adding or removing one breaks the build.
enum SubscriptionTier: String, Hashable, CaseIterable {
    case free
    case basic
    case pro
    case ultra
}

// MARK: - Entitlements

struct SubscriptionEntitlements: Equatable {
    // ponytail: every feature granted; the fork has no server to ask and no paywall to render.
    var features: Set<AppFeature> = Set(AppFeature.allCases)
}

struct SubscriptionTierHighlight {
    let tier: SubscriptionTier
    let features: [String]
}

// MARK: - Manager

/// Deliberately NOT @MainActor: read synchronously from non-isolated code (SettingsModel, the
/// `Settings` struct's mutating helpers) as well as from MainActor views.
final class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()

    @Published var entitlements = SubscriptionEntitlements()
    @Published var activeTier: SubscriptionTier = .ultra

    private init() {}

    var isSignedIn: Bool { false }
    var userDisplayName: String { "Local Build" }
    var userInitials: String { "LB" }
    var tierLabel: String { "Fork build" }
    var tierGradientColors: [Color] { [.purple, .indigo] }
    var hasBetaSoftwareAccess: Bool { true }

    func hasAccess(to feature: AppFeature) -> Bool { true }
    func isFeatureEnabled(_ feature: AppFeature) -> Bool { true }

    // ponytail: no network, no receipt validation. Upstream talks to the Sapphire account service.
    func bootstrap() async {}
    func validateSubscriptionStatus() async {}
}

/// Separate from `SubscriptionManager.hasAccess` — both symbols are referenced. Must stay
/// non-isolated: called from `Settings.disableUnavailablePremiumFeatures()` and from
/// `ReleaseChannelPolicy`, which UpdateChecker reaches from a background URLSession handler.
enum SubscriptionAccess {
    static func hasAccess(to feature: AppFeature) -> Bool { true }
}

enum SubscriptionFeatureCatalog {
    // ponytail: nil means "no tier requirement", so no settings section ever reports as locked.
    static func minimumTier(for feature: AppFeature) -> SubscriptionTier? { nil }

    static func features(for tier: SubscriptionTier) -> Set<AppFeature> { Set(AppFeature.allCases) }

    static func tierDisplayName(_ tier: SubscriptionTier) -> String {
        switch tier {
        case .free: return "Free"
        case .basic: return "Basic"
        case .pro: return "Pro"
        case .ultra: return "Ultra"
        }
    }

    static func marketingSubtitle(for tier: SubscriptionTier) -> String {
        "Plan details are unavailable in this build."
    }

    static func marketingTierHighlights() -> [SubscriptionTierHighlight] {
        // ponytail: static placeholder copy; upstream fetches live plan marketing.
        [SubscriptionTier.basic, .pro, .ultra].map {
            SubscriptionTierHighlight(tier: $0, features: ["Plan details unavailable in this build"])
        }
    }
}

enum SubscriptionRevocationReason: String {
    case sessionExpired

    var alertMessage: String {
        switch self {
        case .sessionExpired:
            return "Your Sapphire session expired. Sign in again to restore your subscription."
        }
    }
}

// MARK: - Beta gate

enum BetaEntitlementRuntime {
    /// false so `routeAfterLaunch()` skips the blocker and `ReleaseChannelPolicy` reports `.stable`.
    static var isBetaBuild: Bool { false }
    static func makeValidator() -> BetaEntitlementValidator { BetaEntitlementValidator() }
}

struct BetaEntitlementValidator {
    func validateBetaEntitlement() -> Bool { true }
}

// MARK: - Views

struct AccountSettingsView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("Account")
                .font(.title2.bold())
            ShimUnavailableView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct BetaBlockerView: View {
    let onValidationComplete: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.badge.clock")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("Beta validation")
                .font(.title2.bold())
            ShimUnavailableView()
            Button("Continue", action: onValidationComplete)
                .buttonStyle(.borderedProminent)
        }
        .frame(width: 520, height: 660)
    }
}

struct NativePaymentSheetView: View {
    let tier: SubscriptionTier
    let deviceCount: Int
    let isAddingOnly: Bool
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text("Checkout — \(SubscriptionFeatureCatalog.tierDisplayName(tier))")
                .font(.title2.bold())
            ShimUnavailableView()
            Button("Close", action: onDismiss)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Notification names

extension Notification.Name {
    static let sapphireOpenAccountPane = Notification.Name("sapphireOpenAccountPane")
    static let subscriptionPaywallRequested = Notification.Name("subscriptionPaywallRequested")
    static let subscriptionSessionRevoked = Notification.Name("subscriptionSessionRevoked")
    static let subscriptionEntitlementsDidChange = Notification.Name("subscriptionEntitlementsDidChange")
}
