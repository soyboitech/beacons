import Combine
import SwiftUI

/// Full-screen hot/cold view for walking a tracker or a network camera down, opened from the
/// dossier's SIGNAL panel ("Find it"). The live dBm is big enough to read at arm's length, the dial
/// pulls the dot toward the middle as the signal strengthens, the history line is the dossier's
/// own fixed-scale Sparkline, and the screen stays awake while it is open (auto-lock mid-search was
/// the reason to leave the dossier for this). Signal strength only: nothing here claims a direction.
///
/// The board delivers every tracker sighting, so a tracker's number moves as you walk. A network
/// camera is a firehose row whose repeats the board drops, so for a camera this view holds the
/// board's finder focus ({"focus"}, ble-protocol.md *Finder focus*) while it is open, and the
/// SIGNAL panel offers it only on a board that reports one (BLEManager.finderFocusSupported). For
/// its first ~12 s a camera's number moves in bursts while the board's Wi-Fi hop learns its
/// channel; then the board holds Wi-Fi on that channel and the number steadies. finderCameraNote
/// tells the user what that hold costs.
/// TWIN: android DetailScreen.kt `FinderScreen`.
struct FinderView: View {
    let detection: Detection
    @EnvironmentObject var ble: BLEManager
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .largeTitle) private var readoutSize: CGFloat = 88
    /// Same 1 s clock as the dossier's staleTick, so LIVE turns STALE when the tag goes quiet.
    @State private var now = Date()
    @State private var tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// The live row, as in the dossier: the captured copy can never update.
    private var d: Detection { ble.detection(for: detection.id) ?? detection }

    var body: some View {
        let stale = dossierSignalIsStale(isDemoMode: ble.demoMode,
                                         storeIsStale: ble.isStale(for: d.id, asOf: now))
        let tint = stale ? ACABTheme.dim : d.type.tint
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    Circle().fill(d.type.tint).frame(width: 12, height: 12).accessibilityHidden(true)
                    Text(d.type.inlineCategory)
                        .font(ACABTheme.font(.title2, weight: .semibold)).foregroundStyle(ACABTheme.text)
                    Spacer(minLength: 8)
                    Text(d.source.label)
                        .font(ACABTheme.telemetry(.subheadline, weight: .regular)).foregroundStyle(ACABTheme.dim)
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(ACABTheme.font(.body, weight: .semibold)).foregroundStyle(ACABTheme.text)
                            .frame(width: 44, height: 44)
                            .background(ACABTheme.bg2, in: Circle())
                    }
                    .accessibilityLabel("Close")
                }
                Text("\(d.titleName) · \(dossierHeroSubtitle(node: d.nodeName, makerOrVendor: d.maker ?? d.vendor, headline: d.titleName))")
                    .font(ACABTheme.telemetry(.subheadline, weight: .regular)).foregroundStyle(ACABTheme.dim)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .center, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(d.rssi)")
                            .font(ACABTheme.telemetryFixed(min(readoutSize, 132), weight: .bold))
                            .foregroundStyle(stale ? ACABTheme.dim : ACABTheme.text)
                            .minimumScaleFactor(0.5).lineLimit(1)
                        Text("dBm").font(ACABTheme.telemetry(.title3, weight: .regular)).foregroundStyle(ACABTheme.dim)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Signal strength \(d.rssi) decibels relative to one milliwatt")
                    .accessibilityAddTraits(.updatesFrequently)
                    Spacer(minLength: 0)
                    FinderDial(rssi: d.rssi, tint: tint).frame(width: 96, height: 96)
                }
                Text(dossierSignalWord(isDemoMode: ble.demoMode, stale: stale))
                    .font(ACABTheme.telemetry(.footnote, weight: .semibold))
                    .tracking(ACABTheme.telemetryTracking)
                    .foregroundStyle(stale ? ACABTheme.dim : ACABTheme.text)

                // The dossier's graph, edge words and all, just taller.
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("STRONG")
                        Spacer(minLength: 0)
                        Text("WEAK")
                    }
                    .font(ACABTheme.telemetry(.caption2)).foregroundStyle(ACABTheme.dim)
                    .tracking(ACABTheme.telemetryTracking)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .accessibilityHidden(true)
                    Sparkline(values: ble.rssiTrend(for: d.id), tint: tint)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Signal history")
                        .accessibilityValue("Strong at the top, weak at the bottom")
                }
                .frame(height: 140)
                .padding(14)
                .background(ACABTheme.bg2, in: RoundedRectangle(cornerRadius: 16))

                Kicker(DashboardView.noDirectionCaptionText)
                Text(finderHint)
                    .font(ACABTheme.font(.callout)).foregroundStyle(ACABTheme.dim)
                    .fixedSize(horizontal: false, vertical: true)
                if d.type == .networkCamera {
                    Text(finderCameraNote)
                        .font(ACABTheme.font(.callout)).foregroundStyle(ACABTheme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)
        }
        .background(ACABTheme.bg.ignoresSafeArea())
        .onReceive(tick) { now = $0 }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        // A camera's focus: re-sent every 10 s because the board forgets it 30 s after the last
        // write, and cleared by the same task as it ends, so no late re-send can follow the clear.
        .task {
            guard detection.type == .networkCamera else { return }
            defer { ble.setFinderFocus(nil) }
            while !Task.isCancelled {
                ble.setFinderFocus(detection.mac)
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }
}

/// The finder's one instruction. The beacon, not the phone, measures the signal, so walking the
/// phone around on its own changes nothing. TWIN: android DetailScreen.kt `FINDER_HINT`.
let finderHint = "Carry the beacon as you walk. It hears the signal, not your phone. The number climbs toward 0 as you get closer."

/// A camera hunt holds the beacon's Wi-Fi on that camera's channel (ble-protocol.md *Finder focus*),
/// so it hears no other Wi-Fi meanwhile. TWIN: android DetailScreen.kt `FINDER_CAMERA_NOTE`.
let finderCameraNote = "After a few seconds the beacon listens only to the Wi-Fi channel this camera uses, until you close this. Bluetooth detection carries on."

/// Rings with the device's dot nearer the middle the stronger it reads, on the dossier graph's
/// fixed scale (signalGraphFraction). The dot's angle is fixed: the beacon hears strength only,
/// so no angle on this dial means anything. TWIN: android DetailScreen.kt `FinderDial`.
private struct FinderDial: View {
    let rssi: Int
    let tint: Color
    var body: some View {
        Canvas { ctx, size in
            let r = min(size.width, size.height) / 2
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            for f in [1.0, 0.66, 0.33] as [CGFloat] {
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r * f, y: c.y - r * f, width: 2 * r * f, height: 2 * r * f)),
                           with: .color(ACABTheme.line), lineWidth: 1)
            }
            let dist = r * 0.85 * CGFloat(1 - signalGraphFraction(rssi: rssi))
            let p = CGPoint(x: c.x + dist * 0.7071, y: c.y - dist * 0.7071)   // fixed 45 degrees
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - 7, y: p.y - 7, width: 14, height: 14)), with: .color(tint))
        }
        .accessibilityHidden(true)
    }
}
