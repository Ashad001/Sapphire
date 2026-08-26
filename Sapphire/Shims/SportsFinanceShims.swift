//
//  SportsFinanceShims.swift — FORK-ONLY SHIM
//  Stand-in for closed-source upstream modules Sapphire/Widgets/{Sports,Finance} and the
//  Sapphire/Services sports/finance sources (SportsAPIService, FinanceAPIService,
//  SportsFinanceContentProvider, SportsTeamCatalog, SportLayoutRegistry), which are gitignored in
//  cshariq/Sapphire and therefore absent from this repo. These definitions exist ONLY so the fork
//  compiles. They are inert. Delete this whole folder before proposing anything upstream.
//

import SwiftUI

// MARK: - Services

/// Non-isolated by design: called synchronously from AppDelegate launch and from LiveActivityManager
/// timers, and awaited from @MainActor code. Only the two awaited methods are `async`.
final class SportsAPIService {
    static let shared = SportsAPIService()
    private init() {}

    // ponytail: no ESPN scoreboard polling, no cache. Every lookup misses.
    func bootstrapIfNeeded() {}
    func cachedLiveEvent(for teamOrLeague: String) -> LiveSportsEvent? { nil }
    func peekLatestCommentary(for event: LiveSportsEvent) -> SportsComment? { nil }
    func prefetchLiveScoreboards(for teams: [String]) async {}
    func fetchLiveEvent(for teamOrLeague: String, forceRefresh: Bool) async -> LiveSportsEvent? { nil }
}

/// Opaque to open-source code: it only ever flows `cachedQuote` -> `makePayload`.
struct FinanceQuote {}

final class FinanceAPIService {
    static let shared = FinanceAPIService()
    private init() {}

    // ponytail: no quote provider. `makePayload` returns an em-dash placeholder payload.
    func cachedQuote(symbol: String) -> FinanceQuote? { nil }
    func fetchQuote(symbol: String) async -> FinanceQuote? { nil }

    func makePayload(symbol: String, index: Int, quote: FinanceQuote?) -> FinancePayload {
        FinancePayload(
            symbol: symbol,
            price: "—",
            change: "—",
            changePercent: "—",
            isPositive: true,
            name: symbol,
            isAfterHours: true,
            closingPrice: nil
        )
    }
}

enum SportsFinanceContentProvider {
    /// Maps a real event straight through. `status` must read "Live" when the event is live —
    /// that string is what gates the commentary branch and the `_live` activity-id suffix.
    static func makeSportsPayload(from event: LiveSportsEvent) -> SportsPayload {
        SportsPayload(
            league: event.leagueRoute.displayName,
            homeTeam: event.homeTeam,
            awayTeam: event.awayTeam,
            homeScore: event.homeScore,
            awayScore: event.awayScore,
            status: event.isLive ? "Live" : event.status,
            time: event.clock,
            homeLogoURL: event.homeLogoURL,
            awayLogoURL: event.awayLogoURL
        )
    }

    /// ponytail: no team catalog, so the scheduled-game path has nothing to describe.
    static func makeSportsPayload(for teamOrLeague: String, index: Int) -> SportsPayload {
        SportsPayload(
            league: "",
            homeTeam: teamOrLeague,
            awayTeam: "",
            homeScore: 0,
            awayScore: 0,
            status: "Unavailable",
            time: ""
        )
    }
}

enum SportLayoutRegistry {
    /// ponytail: always `.generic` — upstream maps ~18 league families to bespoke scoreboard
    /// layouts. Do NOT call `SportLayoutKind.from(league:)` here; that would recurse forever.
    static func resolve(league: String) -> SportLayoutKind { .generic }
}

// MARK: - Notch widgets

struct SportsWidgetView: View {
    var body: some View {
        ShimUnavailableView()
            .frame(minWidth: 190, minHeight: 90)
            .fixedSize()
    }
}

struct FinanceWidgetView: View {
    var body: some View {
        ShimUnavailableView()
            .frame(minWidth: 190, minHeight: 90)
            .fixedSize()
    }
}

// MARK: - Expanded players

struct SportsPlayerView: View {
    @Binding var navigationStack: [NotchWidgetMode]

    var body: some View {
        ShimUnavailableView()
            .frame(width: 380, height: 160)
    }
}

struct FinancePlayerView: View {
    @Binding var navigationStack: [NotchWidgetMode]

    var body: some View {
        ShimUnavailableView()
            .frame(width: 380, height: 160)
    }
}

// MARK: - Settings panes

struct SportsSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sports").font(.largeTitle.bold())
            ShimUnavailableView()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
    }
}

struct FinanceSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Finance").font(.largeTitle.bold())
            ShimUnavailableView()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
    }
}

// MARK: - Live activity content
//
// Static-func namespaces, matching the house pattern in LiveActivityComponents.swift
// (WeatherActivityView, DesktopActivityView, ...). These are NOT Views themselves.

struct SportsLiveActivityView {
    static func left(for payload: SportsPayload, preferLogo: Bool) -> some View {
        Text(payload.homeTeam).font(.caption).foregroundStyle(.secondary)
    }

    static func right(for payload: SportsPayload, preferLogo: Bool) -> some View {
        Text(payload.status).font(.caption).foregroundStyle(.secondary)
    }
}

struct FinanceLiveActivityView {
    static func left(for payload: FinancePayload) -> some View {
        Text(payload.symbol).font(.caption).foregroundStyle(.secondary)
    }

    static func right(for payload: FinancePayload) -> some View {
        Text(payload.price).font(.caption).foregroundStyle(.secondary)
    }
}
