#!/bin/bash
set -euo pipefail
umask 077

configDir="$HOME/.config/cmd-tab-pro"
identityFile="$configDir/signing-identity"
certificateName="CmdTabPro Local Development"
keychain="$(security default-keychain -d user | tr -d '"' | sed 's/^[[:space:]]*//')"

if [ -f "$identityFile" ]; then
  identity="$(cat "$identityFile")"
  if [[ "$identity" =~ ^[[:xdigit:]]{40}$ && "$(security find-identity -v -p codesigning "$keychain")" == *"$identity"* ]]; then
    echo "Reusing local signing identity: $identity"
    exit 0
  fi
  echo "Configured signing identity is unavailable. Restore it instead of creating a replacement." >&2
  exit 1
fi
if security find-certificate -c "$certificateName" "$keychain" >/dev/null 2>&1; then
  echo "A local certificate already exists. Configure its fingerprint instead of creating a duplicate." >&2
  exit 1
fi

temporaryDir="$(mktemp -d "${TMPDIR:-/tmp}/cmd-tab-pro-signing.XXXXXX")"
trap 'rm -rf "$temporaryDir"' EXIT
/usr/bin/openssl genrsa -out "$temporaryDir/key.pem" 3072 2>"$temporaryDir/openssl.log"
/usr/bin/openssl req -new -x509 -key "$temporaryDir/key.pem" -sha256 -days 3650 \
  -subj "/CN=$certificateName" \
  -addext 'basicConstraints=critical,CA:FALSE' \
  -addext 'keyUsage=critical,digitalSignature' \
  -addext 'extendedKeyUsage=critical,codeSigning' \
  -out "$temporaryDir/certificate.pem" 2>"$temporaryDir/openssl.log"
security import "$temporaryDir/key.pem" -k "$keychain" -t priv -f openssl -T /usr/bin/codesign
security import "$temporaryDir/certificate.pem" -k "$keychain" -t cert
security add-trusted-cert -r trustRoot -p codeSign -k "$keychain" "$temporaryDir/certificate.pem"
identity="$(/usr/bin/openssl x509 -in "$temporaryDir/certificate.pem" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d ':')"
[[ "$(security find-identity -v -p codesigning "$keychain")" == *"$identity"* ]]
mkdir -p "$configDir"
printf '%s\n' "$identity" > "$identityFile"
echo "Configured local signing identity: $identity"
echo "Certificate and private key remain in the login keychain; temporary key files were removed."
