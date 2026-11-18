#!/bin/sh

# Smartt's Xcode Cloud setup, run by ci_post_clone.sh instead of Signal's steps. The Podfile takes
# LibSignalClient from Smartt's libsignal fork in ../libsignal, so the library is built here with
# Rust, and `pod install` runs here because its result can't be committed to Signal-Pods.

set -eux

cd "$(dirname "$0")/.."

make dependencies

git clone --depth 1 --branch smartt-0.77.1 https://github.com/SmarttMessengerOrganization/libsignal.git ../libsignal

export HOMEBREW_NO_AUTO_UPDATE=1
brew install protobuf cmake ruby@3.3

curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain none
. "$HOME/.cargo/env"
rustup toolchain install "$(cat ../libsignal/rust-toolchain)" --profile minimal --target aarch64-apple-ios
(cd ../libsignal && CARGO_BUILD_TARGET=aarch64-apple-ios swift/build_ffi.sh --release)

# CocoaPods at the version in Podfile.lock; it doesn't run on Ruby 4.
export PATH="$(brew --prefix ruby@3.3)/bin:$PATH"
export GEM_HOME="$HOME/.gem/smartt"
export PATH="$GEM_HOME/bin:$PATH"
gem install --no-document cocoapods -v "$(sed -n 's/^COCOAPODS: //p' Podfile.lock)"
pod install

# Signal 7.71 with Xcode 26: the iOS 26 SDK makes this header private, and Xcode 26's new warnings
# would fail the build.
sed -i '' '/#import <netinet6\/in6.h>/d' Pods/Reachability/Reachability.m
cp Config/User.xcconfig.sample Config/User.xcconfig
echo 'GCC_TREAT_WARNINGS_AS_ERRORS = NO' >> Config/User.xcconfig
