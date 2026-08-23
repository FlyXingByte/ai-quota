#!/bin/bash
# Creates the local code-signing identity that build.sh uses.
#
# Why not ad-hoc: TCC (系统设置 → 隐私与安全性) keys a permission grant to the
# app's designated requirement. Ad-hoc signing has no identity, so the
# requirement degrades to the cdhash — which changes on every rebuild, so every
# `./install.sh` silently revokes whatever you had granted. With this cert the
# requirement becomes
#     identifier "com.local.aiquota" and certificate root = H"..."
# which survives rebuilds.
#
# The cert is NOT installed as a trusted root — codesign does not need that, and
# adding one is a system-wide change we have no business making.
set -euo pipefail

NAME="${AIQUOTA_SIGN_IDENTITY:-AI Quota Local Signing}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$NAME" >/dev/null 2>&1; then
  echo "==> 证书 \"$NAME\" 已存在，无需重建"
  echo "    (重建会换掉 certificate root，之前授过的权限要重新授权)"
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> 生成自签名代码签名证书"
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
  -subj "/CN=$NAME/O=AI Quota/C=US" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null

openssl pkcs12 -export -out "$TMP/id.p12" \
  -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" \
  -passout pass:aiquota \
  -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1

echo "==> 导入登录钥匙串"
# -A lets codesign use the private key without a keychain prompt on every build.
security import "$TMP/id.p12" -k "$KEYCHAIN" -P aiquota -T /usr/bin/codesign -A

echo "==> 完成。现在跑 ./install.sh"
