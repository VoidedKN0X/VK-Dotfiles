pragma Singleton

// The notification daemon (replaces swaync): keeps the notifications for the
// control center's list and decides which ones pop up.

import QtQuick
import Quickshell
import Quickshell.Services.Notifications

Singleton {
    id: root

    // do not disturb: right-click the bell, or the control center's toggle
    property bool dnd: false

    // newest first
    readonly property var list: server.trackedNotifications.values.slice().reverse()
    readonly property int count: list.length

    // the ones on screen as popups right now, newest first
    property var popups: []

    // seconds a popup stays (the timeouts of the swaync config): normal 8,
    // low 6, critical stays until you close it
    readonly property int timeoutNormal: 8
    readonly property int timeoutLow: 6

    // when each notification arrived, by id, for "5 min" in the cards
    property var arrived: ({})

    NotificationServer {
        id: server
        keepOnReload: true
        persistenceSupported: true
        actionsSupported: true
        imageSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: false
        inlineReplySupported: false

        onNotification: n => {
            n.tracked = true;
            root.arrived[n.id] = Date.now();
            n.closed.connect(() => root.removePopup(n));
            // no popups while the control center is open (the list shows it)
            // or with do not disturb on; critical ones (a failing disk) always
            // pop up
            const quiet = BarState.controlCenterScreen !== null || (root.dnd && n.urgency !== NotificationUrgency.Critical);
            if (!quiet)
                root.popups = [n].concat(root.popups.filter(p => p !== n)).slice(0, 5);
        }
    }

    // seconds a popup stays; 0 = until it's closed
    function timeoutFor(n) {
        if (n.urgency === NotificationUrgency.Critical)
            return 0;
        return n.urgency === NotificationUrgency.Low ? timeoutLow : timeoutNormal;
    }

    // the popup's time is up: it stays in the list (a "transient" one, which
    // asks not to be kept, goes away)
    function hidePopup(n) {
        removePopup(n);
        if (n.transient)
            n.expire();
    }

    function removePopup(n) {
        if (popups.includes(n))
            popups = popups.filter(p => p !== n);
    }

    // clicking a notification runs its default action (if it has one) and
    // closes it, like swaync. invoke() closes it by itself (unless the app
    // marked it "resident"), so it isn't closed a second time.
    function activate(n) {
        // (a list property: Array methods through .call)
        const action = Array.prototype.find.call(n.actions, a => a.identifier === "default");
        if (action)
            action.invoke();
        else
            n.dismiss();
    }

    function invoke(n, action) {
        action.invoke();
    }

    function clearAll() {
        for (const n of server.trackedNotifications.values.slice())
            n.dismiss();
        popups = [];
    }

    // "now", "5 min", "2 h", "3 d"
    function age(n, now) {
        const since = (now - (arrived[n.id] ?? now)) / 60000;
        if (since < 1)
            return "now";
        if (since < 60)
            return `${Math.floor(since)} min`;
        if (since < 1440)
            return `${Math.floor(since / 60)} h`;
        return `${Math.floor(since / 1440)} d`;
    }

    // opening the control center hides the popups (they're in its list)
    Connections {
        target: BarState
        function onControlCenterScreenChanged() {
            if (BarState.controlCenterScreen !== null)
                root.popups = [];
        }
    }
}
