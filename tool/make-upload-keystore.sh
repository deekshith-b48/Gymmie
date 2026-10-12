#!/bin/sh
# Creates the Play Store upload key and android/key.properties (both git-ignored). Run it ONCE, then back the .jks and
# the passwords up in two separate places: if you lose them you cannot ship updates under this key.
#   sh tool/make-upload-keystore.sh
set -eu
cd "$(dirname "$0")/.."
KS=android/upload-keystore.jks
[ ! -e "$KS" ] || { echo "$KS already exists; refusing to overwrite"; exit 1; }
printf 'Key alias [upload]: '; read -r ALIAS; ALIAS=${ALIAS:-upload}
printf 'Store password (min 8 chars): '; stty -echo; read -r PASS; stty echo; echo
[ ${#PASS} -ge 8 ] || { echo "password too short"; exit 1; }
keytool -genkeypair -v -keystore "$KS" -alias "$ALIAS" -keyalg RSA -keysize 2048 -validity 10000 \
  -storepass "$PASS" -keypass "$PASS" -dname "CN=Gymmie, O=Gymmie, C=IN"
printf 'storePassword=%s\nkeyPassword=%s\nkeyAlias=%s\nstoreFile=upload-keystore.jks\n' "$PASS" "$PASS" "$ALIAS" > android/key.properties
chmod 600 "$KS" android/key.properties
echo
echo "Created $KS and android/key.properties."
echo "CI secrets: UPLOAD_KEYSTORE_B64=\$(base64 < $KS | tr -d '\\n'), KEYSTORE_PASSWORD, KEY_PASSWORD, KEY_ALIAS, API_BASE_URL"
