#!/bin/sh
# What the first-start wizard needs to know before the token is stored.
# Prints key=value lines (setupWizard.js assess() reads them):
#
#   secretTool=yes|no        secret-tool (libsecret) installed: stores the token
#   secretService=yes|no|unknown
#                            a Secret Service (KWallet, GNOME Keyring) runs or
#                            can be started on the session bus; unknown without dbus-send
#   notifySend=yes|no        notify-send (libnotify) installed: reminders
#   osId=…  osLike=…         /etc/os-release ID and ID_LIKE, for the install command

set -u

SECRETS_NAME="org.freedesktop.secrets"

has() {
    command -v "$1" >/dev/null 2>&1
}

yes_no() {
    if has "$1"; then
        echo yes
    else
        echo no
    fi
}

# One D-Bus call to the bus daemon; prints the reply or nothing.
bus_call() {
    dbus-send --session --print-reply --dest=org.freedesktop.DBus \
        /org/freedesktop/DBus "org.freedesktop.DBus.$1" ${2:+"$2"} 2>/dev/null
}

# Owned now (KWallet, gnome-keyring running) or activatable (started on first use).
# No answer from the bus at all (no dbus-send, no session bus) proves nothing: unknown.
secret_service() {
    if ! has dbus-send; then
        echo unknown
        return
    fi
    if ! bus_call GetId | grep -q "string"; then
        echo unknown
        return
    fi
    if bus_call NameHasOwner "string:$SECRETS_NAME" | grep -q "boolean true"; then
        echo yes
        return
    fi
    if bus_call ListActivatableNames | grep -q "\"$SECRETS_NAME\""; then
        echo yes
        return
    fi
    echo no
}

# os-release value without quotes; the file is shell syntax, but is not sourced.
os_value() {
    for f in /etc/os-release /usr/lib/os-release; do
        if [ -r "$f" ]; then
            sed -n "s/^$1=//p" "$f" | head -n 1 | tr -d "\"'"
            return
        fi
    done
}

echo "secretTool=$(yes_no secret-tool)"
echo "secretService=$(secret_service)"
echo "notifySend=$(yes_no notify-send)"
echo "osId=$(os_value ID)"
echo "osLike=$(os_value ID_LIKE)"
