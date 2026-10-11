# Source this file to get the toolchain used to build Gymmie.
#   source tool/env.sh
export DEV_ROOT="${DEV_ROOT:-$HOME/development}"
export JAVA_HOME="$DEV_ROOT/jdk-21/Contents/Home"
export ANDROID_HOME="$DEV_ROOT/android-sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$DEV_ROOT/flutter/bin:$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"

# On the development machine Java's default IPv6-first resolution timed out fetching the
# Gradle distribution from GitHub's release CDN (curl worked). Prefer IPv4 for all JVM tools.
export JAVA_TOOL_OPTIONS="${JAVA_TOOL_OPTIONS:--Djava.net.preferIPv4Stack=true}"
