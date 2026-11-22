pragma Singleton

// The YubiKey waiting for a touch: yubikey-touch-detector (a user service,
// started by its socket) tells everyone connected to its socket
// ($XDG_RUNTIME_DIR/yubikey-touch-detector.socket), in 5-letter messages:
//   U2F_1 / U2F_0   a FIDO request (sudo or a login with pam-u2f, a website,
//                   SSH with a FIDO2 key) started / stopped waiting
//   GPG_1 / GPG_0   a GPG operation on the key (signing, decrypting, SSH
//                   through gpg-agent)
//   MAC_1 / MAC_0   a challenge-response (HMAC)
// "Stopped" means touched, cancelled or timed out: the detector can't tell
// which. popups/YubikeyTouch.qml shows the panel, the bar a key icon.
// Without the detector it quietly tries again every 30 seconds.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool u2f: false
    property bool gpg: false
    property bool mac: false
    readonly property bool waiting: u2f || gpg || mac

    // what's asking, for the panel
    readonly property string reason: u2f ? "sudo, a login or a website (FIDO)" : gpg ? "GPG: signing, decrypting or SSH" : mac ? "Challenge-response (HMAC)" : ""

    Socket {
        id: socket
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/yubikey-touch-detector.socket"
        connected: true
        // the messages come without a separator: everything as it arrives
        parser: SplitParser {
            splitMarker: ""
            onRead: data => root.handle(data)
        }
        onConnectionStateChanged: {
            if (!connected) {
                root.u2f = false;
                root.gpg = false;
                root.mac = false;
                retry.restart();
            }
        }
        onError: retry.restart()
    }
    Timer {
        id: retry
        interval: 30000
        onTriggered: socket.connected = true
    }

    // one or more messages ("U2F_1", "GPG_0U2F_1", ...)
    function handle(data) {
        const pattern = /(U2F|GPG|MAC)_([01])/g;
        let m;
        while ((m = pattern.exec(data)) !== null) {
            const on = m[2] === "1";
            if (m[1] === "U2F")
                u2f = on;
            else if (m[1] === "GPG")
                gpg = on;
            else
                mac = on;
        }
    }
}
