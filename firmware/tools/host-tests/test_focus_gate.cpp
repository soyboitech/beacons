// Host regression test for the finder focus gate (focus_gate.h).
//
// The gate is what lets the app's full-screen finder walk a network camera down by signal: the one
// focused MAC's repeat sightings pass the firehose gate, capped, and only while the app keeps the
// focus alive, and the Wi-Fi hop parks on the camera's strongest channel once it has learned it.
// Pinned here: the cap, the MAC match, the timeout (a crashed app must not leave the board streaming
// or parked), the refresh, the clear, the channel pin, and - by source - that acab_scanner.cpp's
// deliver line and hop task consult the gate and that a disconnect clears the focus.
#include "../../lib/acab_core/focus_gate.h"
#include <cstdio>
#include <string>

static int gFail = 0, gRun = 0;
static void chk(const char* name, bool got, bool want) {
    gRun++; if (got != want) gFail++;
    printf("  %-62s %s\n", name, got == want ? "PASS" : "**FAIL**");
}

static std::string slurp(const char* path) {
    FILE* f = fopen(path, "rb");
    if (!f) return std::string();
    std::string s; char b[8192]; size_t n;
    while ((n = fread(b, 1, sizeof(b), f)) > 0) s.append(b, n);
    fclose(f);
    return s;
}

int main() {
    printf("\n=== finder focus gate ===\n");
    const uint8_t cam[6]   = {0x44, 0x19, 0xb6, 0x01, 0x02, 0x03};
    const uint8_t other[6] = {0x44, 0x19, 0xb6, 0x01, 0x02, 0x04};
    const uint64_t t0 = 5000000;   // 5 s after boot
    const uint64_t learned = t0 + ACAB_FOCUS_LEARN_US;

    AcabFocus f{};
    chk("no focus: nothing is admitted", acabFocusAdmit(f, cam, 6, -60, t0), false);
    chk("no focus: not live", acabFocusLive(f, t0), false);

    acabFocusSet(f, cam, t0);
    chk("focused MAC: first sighting admitted", acabFocusAdmit(f, cam, 6, -60, t0), true);
    chk("focused MAC: a frame 1 ms later is held", acabFocusAdmit(f, cam, 6, -60, t0 + 1000), false);
    chk("another MAC is never admitted", acabFocusAdmit(f, other, 6, -60, t0 + 600000), false);
    chk("focused MAC: admitted again once the gap has passed",
        acabFocusAdmit(f, cam, 6, -60, t0 + ACAB_FOCUS_MIN_GAP_US), true);
    chk("a sighting stamped before the last one is held, not wrapped",
        acabFocusAdmit(f, cam, 6, -60, t0 + ACAB_FOCUS_MIN_GAP_US - 1), false);

    // The cap: a camera streaming 1000 frames/s for 10 s yields 2..4 rows a second.
    {
        AcabFocus g{};
        acabFocusSet(g, cam, t0);
        int n = 0;
        for (uint64_t t = t0; t < t0 + 10000000; t += 1000)
            if (acabFocusAdmit(g, cam, 6, -60, t)) n++;
        char name[96];
        snprintf(name, sizeof(name), "1 kHz stream for 10 s: %d rows (2-4 per second)", n);
        chk(name, n >= 20 && n <= 40, true);
    }

    // Timeout: no refresh for ACAB_FOCUS_TIMEOUT_US and the focus is gone for good.
    {
        AcabFocus g{};
        acabFocusSet(g, cam, t0);
        chk("live just before the timeout", acabFocusLive(g, t0 + ACAB_FOCUS_TIMEOUT_US - 1), true);
        chk("timed out: not admitted", acabFocusAdmit(g, cam, 6, -60, t0 + ACAB_FOCUS_TIMEOUT_US), false);
        chk("timed out: cleared, not merely skipped", g.untilUs == 0, true);
        chk("a timeout stays timed out far later",
            acabFocusAdmit(g, cam, 6, -60, t0 + 50ULL * 86400 * 1000000), false);
    }

    // Refresh: re-sending the same MAC pushes the deadline out.
    {
        AcabFocus g{};
        acabFocusSet(g, cam, t0);
        acabFocusSet(g, cam, t0 + 20000000);
        chk("refreshed at 20 s: still live at 45 s", acabFocusLive(g, t0 + 45000000), true);
        chk("refreshed at 20 s: gone at 50 s", acabFocusLive(g, t0 + 50000000), false);
    }

    // Clear, and switching target.
    {
        AcabFocus g{};
        acabFocusSet(g, cam, t0);
        acabFocusSet(g, nullptr, t0 + 1000);
        chk("cleared: not live", acabFocusLive(g, t0 + 2000), false);
        chk("cleared: not admitted", acabFocusAdmit(g, cam, 6, -60, t0 + 2000), false);
        acabFocusSet(g, other, t0 + 3000);
        chk("new target admitted", acabFocusAdmit(g, other, 6, -60, t0 + 3000), true);
        chk("old target no longer admitted", acabFocusAdmit(g, cam, 6, -60, t0 + 900000), false);
    }

    printf("\n=== channel pin ===\n");
    // A camera on channel 1, heard through one sweep: weaker from channels 2 and 3, strongest on 1.
    {
        AcabFocus g{};
        acabFocusSet(g, cam, t0);
        acabFocusAdmit(g, cam, 3, -78, t0 + 1000000);
        acabFocusAdmit(g, cam, 1, -61, t0 + 2000000);
        acabFocusAdmit(g, cam, 2, -66, t0 + 3000000);
        acabFocusAdmit(g, cam, 0, -40, t0 + 4000000);   // a BLE row (no channel) never pins
        chk("no pin inside the learn window", acabFocusPinChannel(g, learned - 1) == 0, true);
        chk("after the window: pinned to the strongest channel", acabFocusPinChannel(g, learned) == 1, true);
        acabFocusSet(g, cam, learned + 5000000);   // the app's refresh
        chk("a refresh keeps the pin", acabFocusPinChannel(g, learned + 5000000) == 1, true);
    }
    // The strongest reading counts even when the rate cap held that row back.
    {
        AcabFocus g{};
        acabFocusSet(g, cam, t0);
        acabFocusAdmit(g, cam, 11, -70, t0);
        chk("a capped row is still held back",
            acabFocusAdmit(g, cam, 10, -55, t0 + 1000), false);
        chk("...but its stronger channel wins the pin", acabFocusPinChannel(g, learned) == 10, true);
    }
    // Never heard on Wi-Fi: keep hopping. Timed out or cleared: keep hopping.
    {
        AcabFocus g{};
        acabFocusSet(g, cam, t0);
        chk("never heard on Wi-Fi: no pin", acabFocusPinChannel(g, learned) == 0, true);
        acabFocusAdmit(g, cam, 6, -60, t0 + 1000000);
        chk("heard: pinned", acabFocusPinChannel(g, learned) == 6, true);
        chk("timed out: the pin is released",
            acabFocusPinChannel(g, t0 + ACAB_FOCUS_TIMEOUT_US) == 0, true);
        acabFocusSet(g, cam, learned);
        acabFocusAdmit(g, cam, 6, -60, learned);
        acabFocusSet(g, nullptr, learned + 1);
        chk("cleared: the pin is released", acabFocusPinChannel(g, learned + ACAB_FOCUS_LEARN_US) == 0, true);
    }
    // A new target learns its own channel from scratch, with its own window.
    {
        AcabFocus g{};
        acabFocusSet(g, cam, t0);
        acabFocusAdmit(g, cam, 6, -50, t0 + 1000000);
        acabFocusSet(g, other, learned);
        acabFocusAdmit(g, other, 11, -70, learned + 1000000);
        chk("new target: no pin until its own window passes", acabFocusPinChannel(g, learned + 1) == 0, true);
        chk("new target: pinned to its own channel",
            acabFocusPinChannel(g, learned + ACAB_FOCUS_LEARN_US) == 11, true);
    }

    // The firmware wiring this pure gate cannot see. run.sh runs from firmware/tools/host-tests.
    {
        const std::string scanner = slurp("../../lib/acab_core/acab_scanner.cpp");
        const std::string ble = slurp("../../lib/acab_core/acab_ble_service.cpp");
        chk("sources readable", !scanner.empty() && !ble.empty(), true);
        chk("every firehose sighting reaches the focus gate",
            scanner.find("const bool focused = firehose && focusNotifyAllowed(d);") != std::string::npos,
            true);
        chk("handleDetection's deliver line takes the focus verdict",
            scanner.find("bool deliver = !firehose || desertNotifyAllowed(isNew, now) || focused;")
                != std::string::npos, true);
        const size_t hop = scanner.find("static void wifiHopTask(void*)");
        const size_t pin = hop == std::string::npos ? hop
                         : scanner.find("if (const uint8_t pin = focusPinChannel())", hop);
        const size_t seq = hop == std::string::npos ? hop
                         : scanner.find("esp_wifi_set_channel(WIFI_HOP_SEQ[idx]", hop);
        chk("the hop task checks the pin before it hops", pin != std::string::npos && pin < seq, true);
        chk("eco sleep stands down while a focus is live",
            scanner.find("if (eco > 0 && gWifiEnabled && !gFocusOn)") != std::string::npos, true);
        const size_t disc = ble.find("void disconnectBody()");
        const size_t clear = disc == std::string::npos ? disc
                           : ble.find("acabScannerSetFocus(nullptr);", disc);
        const size_t end = disc == std::string::npos ? disc : ble.find("\n    }\n", disc);
        chk("a disconnect clears the focus", clear != std::string::npos && clear < end, true);
    }

    printf(gFail ? "\n  REGRESSION DETECTED (%d of %d)\n\n" : "\n  all good (0 failures of %d)\n\n",
           gFail ? gFail : gRun, gFail ? gRun : 0);
    return gFail ? 1 : 0;
}
