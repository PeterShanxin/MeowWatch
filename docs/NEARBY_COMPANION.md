# Nearby MeowWatch companion

Nearby lets MeowWatch Mobile control the current Windows desktop session. The
desktop remains the room participant and media player; the phone relays controls,
chat and reactions through the approved desktop connection.

## Pair a phone

1. Connect Windows and Android to the same trusted Wi-Fi or Ethernet LAN.
2. Enter a desktop room or Local Player Mode, then open the player menu and
   choose **Nearby MeowWatch**.
3. Select an eligible interface and enable Nearby. Windows must report that
   actual interface as **Private**. Public, Domain, unknown, VPN and loopback
   interfaces are not eligible. Only change a network's trust setting if it is
   your trusted network; MeowWatch never changes it or opens a firewall rule.
4. Choose **Pair a phone**. In MeowWatch Mobile's playback target chooser, open
   **Nearby MeowWatch** and scan the desktop's QR invitation. If discovery or the
   camera is unavailable, copy and paste the complete invitation instead.
5. Approve the named phone on the desktop within the displayed deadline. An
   invitation expires after two minutes and can be consumed only once.

An existing paired desktop can be selected again while Nearby is enabled.
Discovery is a convenience hint: the app authenticates the stored identity over
a pinned, encrypted connection before exposing state or controls. A discovery
failure leaves the complete QR/paste fallback available.

## Control and disconnect

The phone displays the desktop's media title, playback position and duration,
room participants and chat. Playback commands operate the desktop's existing
player. Choose media on the desktop; this feature does not copy a desktop file
to Android or disclose its local path to the phone.

Only one active phone controls a desktop at a time. Changing or leaving the
desktop room, disabling Nearby, an interface/profile change, heartbeat expiry,
or revocation closes control. Commands waiting on the player cannot continue
after their session, lease or media is replaced. Returning to phone playback is
an explicit mobile action, so losing Wi-Fi does not unexpectedly start sound.

Use the paired-device list to revoke a phone. Credentials and durable revocation
records are stored using the operating system's protected storage and isolated
by the canonical MeowWatch data profile. If protected storage fails, Nearby
fails closed. Resolve that error before re-enabling; a failed persistence write
cannot prove revocation will survive a restart.

## Developer validation

The portable protocol and native storage/discovery adapters are pinned to a
public commit of `PeterShanxin/MeowWatch-Mobile` in `pubspec.yaml`. No sibling
checkout or local path dependency is required. Protocol details and adversarial
transport tests live in that repository's `docs/NEARBY_PROTOCOL.md` and
`packages/nearby_bridge`.

This desktop branch includes tests for native-interface filtering, redacted
snapshots, command invalidation, service lifetime, pairing approval and the
Private-network UI. `tool/nearby_native_smoke.dart` is an explicitly configured
Release probe for protected credentials and cross-process revocation. It does
not start a listener or claim cross-device discovery.

`tool/nearby_player_smoke.dart` exercises the real Release MediaKit player via
the companion session: native playback advancement, stable pause, exact seek,
EOF and replay. It requires an explicit fixture path and an isolated output
directory. It does not replace authenticated phone-to-desktop acceptance.

Before release, verify the normal Release application with a physical Android
phone on a trusted LAN: discover, approve, control, chat, disconnect, reconnect,
revoke, restart and reject the revoked pairing. Current local native evidence
on a Public Windows network proves profile rejection and protected-storage
persistence, not that physical mobile-to-desktop acceptance has passed.
