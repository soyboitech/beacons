/*
 * ACAB - finder focus gate (pure, no platform deps).
 *
 * The two per-frame firehoses (a Desert nearby device, a network camera) reach the app only on
 * their `new` edge: desertNotifyAllowed (acab_scanner.cpp) drops every repeat inside the 60 s dedup
 * window. That is right for a crowd and wrong for the one device a user is walking down with the
 * app's full-screen finder, whose live number would freeze on the first sighting.
 *
 * {"focus":"<mac>"} names that one device. Its repeat sightings then pass the gate, at most one per
 * ACAB_FOCUS_MIN_GAP_US, until {"focus":""}, a disconnect, or ACAB_FOCUS_TIMEOUT_US with no
 * refresh, whichever comes first. The timeout is what keeps a crashed or frozen app from leaving
 * the board streaming: the apps re-send the key every ~10 s while the finder is open. Focused rows
 * are still firehose rows at the sink queue (acabSinkAdmitsFirehose), so a hunt can never crowd out
 * a Flock, drone or body-cam alert.
 *
 * CHANNEL PIN. The Wi-Fi hop visits a camera's channel for one 300 ms dwell per sweep, so on its
 * own the finder would get a burst every few seconds. Every Wi-Fi sighting of the focused device
 * therefore records the channel it was heard on, and once ACAB_FOCUS_LEARN_US has passed the hop
 * sits on the channel of the STRONGEST one (acabFocusPinChannel). Strongest, not latest: on
 * 2.4 GHz a transmitter is also heard, weaker, from neighbouring channels, so the learn window
 * spans a whole sweep before it commits. While pinned the board hears no other Wi-Fi channel.
 *
 * Timed on the 64-bit microsecond clock (esp_timer_get_time), so a deadline cannot come back around
 * the way a millis() one does every 49.7 days. Pure so test_focus_gate.cpp can pin it; run.sh's
 * header-only branch picks this file up by its stem.
 */
#ifndef ACAB_FOCUS_GATE_H
#define ACAB_FOCUS_GATE_H

#include <stdint.h>
#include <string.h>

// Calibration knobs. 250 ms = at most 4 notifies/s, enough for a live number and a trend line and a
// rounding error beside the 20/s Desert bucket. 30 s = three missed app refreshes. 12 s = one whole
// hop sweep with margin (7.2 s on the S3, 9.9 s on the C5 with its 5 GHz pass); acab_scanner.cpp
// static_asserts that it still covers the sweep it is built with.
#ifndef ACAB_FOCUS_MIN_GAP_US
#define ACAB_FOCUS_MIN_GAP_US 250000ULL
#endif
#ifndef ACAB_FOCUS_TIMEOUT_US
#define ACAB_FOCUS_TIMEOUT_US 30000000ULL
#endif
#ifndef ACAB_FOCUS_LEARN_US
#define ACAB_FOCUS_LEARN_US 12000000ULL
#endif

struct AcabFocus {
    uint8_t  mac[6];
    uint64_t untilUs;    // 0 = no focus
    uint64_t lastUs;     // when the last focused sighting was let through; 0 = none yet
    uint64_t sinceUs;    // when this hunt began; a refresh of the same MAC keeps it
    int16_t  bestRssi;   // strongest Wi-Fi sighting so far ...
    uint8_t  bestCh;     // ... and the channel it was heard on; 0 = none yet
};

// A focus is set and has not timed out. An expired one is cleared here.
inline bool acabFocusLive(AcabFocus& f, uint64_t nowUs) {
    if (f.untilUs && nowUs >= f.untilUs) f = AcabFocus{};
    return f.untilUs != 0;
}

// Set (mac) or clear (nullptr) the focus. Setting the same mac again is the refresh: it extends the
// deadline and keeps what the hunt has learned. A new mac starts a new hunt.
inline void acabFocusSet(AcabFocus& f, const uint8_t* mac, uint64_t nowUs) {
    if (!mac) { f = AcabFocus{}; return; }
    if (!acabFocusLive(f, nowUs) || memcmp(f.mac, mac, 6) != 0) {
        f = AcabFocus{};
        memcpy(f.mac, mac, 6);
        f.sinceUs = nowUs;
    }
    f.untilUs = nowUs + ACAB_FOCUS_TIMEOUT_US;
}

// One firehose sighting of `mac`, heard on Wi-Fi channel `ch` (0 = not Wi-Fi). Records the channel
// for the pin, then says whether the row may pass the firehose gate as the focused device, spending
// the slot if so. `nowUs < lastUs + gap`, not a subtraction: the radio tasks read the clock before
// taking the lock, so a sighting can arrive stamped a hair earlier than the one just let through.
inline bool acabFocusAdmit(AcabFocus& f, const uint8_t mac[6], uint8_t ch, int rssi, uint64_t nowUs) {
    if (!acabFocusLive(f, nowUs) || memcmp(f.mac, mac, 6) != 0) return false;
    if (ch && (!f.bestCh || rssi > f.bestRssi)) { f.bestCh = ch; f.bestRssi = (int16_t)rssi; }
    if (f.lastUs && nowUs < f.lastUs + ACAB_FOCUS_MIN_GAP_US) return false;
    f.lastUs = nowUs;
    return true;
}

// The channel the Wi-Fi hop should sit on, or 0 to keep hopping: none until the learn window has
// passed, and none if the focused device has not been heard on Wi-Fi at all.
inline uint8_t acabFocusPinChannel(AcabFocus& f, uint64_t nowUs) {
    if (!acabFocusLive(f, nowUs) || nowUs < f.sinceUs + ACAB_FOCUS_LEARN_US) return 0;
    return f.bestCh;
}

#endif // ACAB_FOCUS_GATE_H
