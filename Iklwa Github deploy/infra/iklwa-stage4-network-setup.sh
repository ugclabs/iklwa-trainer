#!/usr/bin/env bash
#
# iklwa-stage4-network-setup.sh
#
# One-time network setup for Iklwa Terminal Trainer, stage 4.
# Points this Kali box's DNS resolver at the Iklwa lab DNS server so the
# dig / ping / nmap tasks in stage 4 resolve against the lab zone instead of
# whatever DNS this machine normally uses.
#
# iklwa-trainer.sh runs this itself, via sudo, the first time a learner
# reaches stage 4 on a machine that isn't configured yet -- nobody normally
# needs to run this by hand. It's still here as a standalone script for
# batch pre-provisioning a set of machines ahead of time, or for --restore.
#
# Manual run, once per Kali box, as root:
#   sudo bash iklwa-stage4-network-setup.sh
#
# To put this machine's original DNS settings back:
#   sudo bash iklwa-stage4-network-setup.sh --restore

set -euo pipefail

# ---- Fill these in once for your lab network, before handing this out ----
LAB_DNS_IP="10.0.0.53"                    # the dnsmasq box's address on the lab network
LAB_DOMAIN="isipingofreight.internal"    # the lab zone's domain
# ----------------------------------------------------------------------

RESOLV_CONF="/etc/resolv.conf"
BACKUP_CONF="/etc/resolv.conf.iklwa-original"

if [[ "${EUID}" -ne 0 ]]; then
    echo "This needs root, since it changes system DNS settings."
    echo "Try: sudo ./iklwa-stage4-network-setup.sh"
    exit 1
fi

if [[ "${1:-}" == "--restore" ]]; then
    if [[ -f "$BACKUP_CONF" ]]; then
        cp "$BACKUP_CONF" "$RESOLV_CONF"
        echo "Restored this machine's original DNS settings from $BACKUP_CONF."
    else
        echo "No backup found at $BACKUP_CONF — nothing to restore."
        echo "(This machine may never have run the setup, or the backup was removed.)"
    fi
    exit 0
fi

if [[ ! -f "$BACKUP_CONF" ]]; then
    cp "$RESOLV_CONF" "$BACKUP_CONF"
    echo "Backed up this machine's original DNS settings to $BACKUP_CONF."
else
    echo "Backup already exists at $BACKUP_CONF, leaving it alone."
fi

cat > "$RESOLV_CONF" <<EOF
# Managed by iklwa-stage4-network-setup.sh for Iklwa Terminal Trainer, stage 4.
# Original settings backed up at $BACKUP_CONF — restore with --restore.
search $LAB_DOMAIN
nameserver $LAB_DNS_IP
EOF

echo "Resolver pointed at the Iklwa lab DNS server ($LAB_DNS_IP)."

if command -v dig >/dev/null 2>&1; then
    if [[ -n "$(dig +short +time=3 +tries=1 "$LAB_DOMAIN" 2>/dev/null)" ]]; then
        echo "Lookup check passed — $LAB_DOMAIN resolves. This box is ready for stage 4."
    else
        echo "Lookup check didn't get an answer for $LAB_DOMAIN."
        echo "That's fine if the lab DNS server isn't running yet — just confirm it's up before training starts."
    fi
else
    echo "dig isn't on this machine to check with, skipping the lookup test. It should already be on Kali by default."
fi

echo
echo "Note: if this box uses NetworkManager and its DNS settings get reset on reboot or reconnect,"
echo "just re-run this script. Nothing else about the trainer or sandbox is affected either way."
