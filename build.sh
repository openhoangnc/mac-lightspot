#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
APP_BUNDLE="$BUILD_DIR/Lightspot.app"
CONTENTS="$APP_BUNDLE/Contents"
DSYM="$BUILD_DIR/Lightspot.app.dSYM"
WORK="$BUILD_DIR/intermediates"

# Any failing step stops the build (set -e), and says so once, whatever failed.
trap 'status=$?; [ $status -eq 0 ] || echo "❌ Build failed (exit $status)." >&2' EXIT

# --thin: also write build/<arch>/Lightspot.app for each architecture of a universal
# build, the release's per-architecture downloads (CLAUDE.md, "Release assets").
THIN_BUNDLES=0
for arg in "$@"; do
    case "$arg" in
        --thin) THIN_BUNDLES=1 ;;
        *) echo "❌ Unknown option '$arg' (expected --thin)." >&2; exit 1 ;;
    esac
done

echo "🔨 Building Lightspot..."

# From the macOS 27 SDK on, `@State` is a SwiftUI macro whose implementation ships with
# Xcode only, so it breaks every Command Line Tools build. Xcode (and so CI) builds it
# fine, which is why this is checked here rather than left to the compiler.
if grep -rnE '@State([^A-Za-z0-9_]|$)' "$SCRIPT_DIR/Sources" --include='*.swift' | grep -v '/UI/ViewState.swift:'; then
    echo "❌ Write @ViewState instead of @State (see Sources/Lightspot/UI/ViewState.swift)."
    exit 1
fi

# The architectures: ARCH_FLAGS takes SwiftPM's spelling ("--arch arm64 --arch x86_64",
# as CI passes it); without it, this Mac's own.
ARCHS=()
set -- ${ARCH_FLAGS:-}
while [ $# -gt 0 ]; do
    case "$1" in
        --arch) [ $# -ge 2 ] || { echo "❌ ARCH_FLAGS: --arch needs a value." >&2; exit 1; }
                ARCHS+=("$2"); shift 2 ;;
        *) echo "❌ ARCH_FLAGS: unknown flag '$1' (expected --arch <arch> ...)." >&2; exit 1 ;;
    esac
done
[ ${#ARCHS[@]} -gt 0 ] || ARCHS=("$(uname -m)")
if [ "$THIN_BUNDLES" = 1 ] && [ ${#ARCHS[@]} -lt 2 ]; then
    echo "❌ --thin needs a universal build: ARCH_FLAGS=\"--arch arm64 --arch x86_64\"." >&2
    exit 1
fi

SOURCES=()
while IFS= read -r file; do SOURCES+=("$file"); done < <(find "$SCRIPT_DIR/Sources/Lightspot" -name '*.swift' | sort)
SDK="$(xcrun --sdk macosx --show-sdk-path)"

# Not `swift build`: neither SwiftPM build system links LTO objects. Package.swift stays the
# development build. The release flags, each for size (CLAUDE.md, "Release binary"):
# - full LTO lets LLVM (and on arm64 the machine outliner) work on the whole program;
# - no -cross-module-optimization: it only helps modules importing this one, and gave
#   thousands of internal symbols public linkage;
# - -no_exported_symbols: nothing loads or looks up symbols in this executable;
# - -g with -object_path_lto keeps the debug info dsymutil needs for the dSYM.
# The app and its dSYM go together: a failed build leaves neither behind, nor thin
# bundles cut from an earlier build.
rm -rf "$WORK" "$DSYM" "$APP_BUNDLE" "$BUILD_DIR/arm64" "$BUILD_DIR/x86_64"
THIN=()
for arch in "${ARCHS[@]}"; do
    echo "🚀 Compiling for $arch (whole module, -Osize, full LTO)..."
    mkdir -p "$WORK/$arch"
    # swiftc writes its bitcode into the working directory, so it runs inside $WORK.
    (cd "$WORK/$arch" && xcrun swiftc \
        -parse-as-library -module-name Lightspot -swift-version 6 \
        -target "$arch-apple-macos13.0" -sdk "$SDK" \
        -Osize -whole-module-optimization -num-threads "$(sysctl -n hw.ncpu)" \
        -enforce-exclusivity=unchecked -lto=llvm-full -g \
        -module-cache-path "$WORK/ModuleCache" \
        -Xlinker -dead_strip -Xlinker -no_exported_symbols \
        -Xlinker -object_path_lto -Xlinker "$WORK/$arch/Lightspot-lto.o" \
        "${SOURCES[@]}" -o "$WORK/$arch/Lightspot")
    THIN+=("$WORK/$arch/Lightspot")
done

BINARY="$WORK/Lightspot"
if [ ${#THIN[@]} -eq 1 ]; then
    cp "${THIN[0]}" "$BINARY"
else
    lipo -create "${THIN[@]}" -output "$BINARY"
fi

# The dSYM is made from the unstripped binary while the LTO objects still exist. Keep it
# with each release: crash reports from the stripped binary need it for names and lines.
echo "🧾 Writing $DSYM..."
dsymutil "$BINARY" -o "$DSYM"

echo "📦 Creating app bundle..."

# Create .app bundle structure
mkdir -p "$CONTENTS/MacOS"
mkdir -p "$CONTENTS/Resources"

# Copy binary
cp "$BINARY" "$CONTENTS/MacOS/Lightspot"

# Every symbol but what dyld needs: local names are half the binary, and the dSYM has them.
echo "🔪 Stripping symbols..."
strip -x "$CONTENTS/MacOS/Lightspot"

# Copy Info.plist
cp "$SCRIPT_DIR/Resources/Info.plist" "$CONTENTS/Info.plist"

# Copy app icon if it exists
if [ -f "$SCRIPT_DIR/Resources/AppIcon.icns" ]; then
    cp "$SCRIPT_DIR/Resources/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
fi

# cdm's rule files: what Clean Dev Mac uses when GitHub cannot be reached
cp -R "$SCRIPT_DIR/Resources/cdm-rules" "$CONTENTS/Resources/cdm-rules"

# Write PkgInfo
echo -n "APPL????" > "$CONTENTS/PkgInfo"

# Ad-hoc codesign
echo "🔏 Signing..."
codesign --force --deep --sign - "$APP_BUNDLE"
codesign --verify --strict "$APP_BUNDLE"

# The dSYM only helps if it matches the binary that ships, architecture by architecture.
uuids() { dwarfdump --uuid "$1" | awk '{print $2, $3}' | sort; }
if [ "$(uuids "$CONTENTS/MacOS/Lightspot")" != "$(uuids "$DSYM")" ]; then
    echo "❌ The dSYM's UUIDs don't match the app's binary." >&2
    exit 1
fi

rm -rf "$WORK"

# Each thin bundle is the signed universal app with one slice kept, signed again the same
# way (lipo rewrites the binary). A slice keeps its UUID, so the one dSYM serves all three.
if [ "$THIN_BUNDLES" = 1 ]; then
    DSYM_UUIDS="$(uuids "$DSYM")"
    for arch in "${ARCHS[@]}"; do
        THIN_APP="$BUILD_DIR/$arch/Lightspot.app"
        THIN_BINARY="$THIN_APP/Contents/MacOS/Lightspot"
        echo "✂️ Writing $THIN_APP..."
        mkdir -p "$BUILD_DIR/$arch"
        ditto "$APP_BUNDLE" "$THIN_APP"
        lipo "$CONTENTS/MacOS/Lightspot" -thin "$arch" -output "$THIN_BINARY"
        codesign --force --deep --sign - "$THIN_APP"
        codesign --verify --strict "$THIN_APP"
        if [ "$(lipo -archs "$THIN_BINARY")" != "$arch" ]; then
            echo "❌ $THIN_BINARY holds $(lipo -archs "$THIN_BINARY"), not $arch alone." >&2
            exit 1
        fi
        if ! grep -qxF "$(uuids "$THIN_BINARY")" <<< "$DSYM_UUIDS"; then
            echo "❌ The dSYM has no UUID matching $THIN_BINARY." >&2
            exit 1
        fi
    done
fi

echo "✅ Build complete: $APP_BUNDLE ($(lipo -archs "$CONTENTS/MacOS/Lightspot")), dSYM: $DSYM"
if [ "$THIN_BUNDLES" = 1 ]; then
    for arch in "${ARCHS[@]}"; do echo "   and $BUILD_DIR/$arch/Lightspot.app ($arch)"; done
fi
