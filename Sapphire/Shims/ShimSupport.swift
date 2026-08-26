//
//  ShimSupport.swift — FORK-ONLY SHIM
//  Stand-in for closed-source upstream modules (SubscriptionKit, Widgets/*, Services/*), which are
//  gitignored in cshariq/Sapphire and therefore absent from this repo. These definitions exist ONLY
//  so the fork compiles. They are inert. Delete this whole folder before proposing anything upstream.
//

import SwiftUI

/// Shared placeholder body for every withheld view. Deliberately visible rather than EmptyView so a
/// reachable stub reads as "missing upstream module", not as a rendering bug.
struct ShimUnavailableView: View {
    var body: some View {
        Text("Unavailable in this build")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
