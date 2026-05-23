#!/usr/bin/env bash
# Source this file to enter the Android dev environment for this project:
#   source ./setup-env.sh

export JAVA_HOME="/Users/ket/Library/Java/JavaVirtualMachines/corretto-17.0.9/Contents/Home"
export ANDROID_HOME="/opt/homebrew/share/android-commandlinetools"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export GRADLE_USER_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.gradle-home"

export PATH="$JAVA_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/build-tools/35.0.0:/opt/homebrew/opt/gradle@8/bin:$PATH"

mkdir -p "$GRADLE_USER_HOME"
