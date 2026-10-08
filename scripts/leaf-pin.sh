#!/usr/bin/env bash
# Print the SHA-256 (base64) of a server's leaf TLS certificate, the form
# CertificatePinningConfig expects. Computed per run because the dev server's
# Let's Encrypt certificate renews every 90 days.
#   usage: scripts/leaf-pin.sh https://host:port
set -euo pipefail
url="${1:?usage: leaf-pin.sh https://host:port}"
hostport="${url#*://}"
hostport="${hostport%%/*}"
host="${hostport%%:*}"
[ "$host" = "$hostport" ] && hostport="$host:443"
pin=$(openssl s_client -connect "$hostport" -servername "$host" </dev/null 2>/dev/null \
  | openssl x509 -outform DER \
  | openssl dgst -sha256 -binary \
  | base64)
[ -n "$pin" ] || { echo "leaf-pin: could not read the certificate from $hostport" >&2; exit 1; }
echo "$pin"
