#!/usr/bin/env bash
# Build smokenot and lay the pieces out the way a snap wants them.
#
#   stage.sh <install-dir>
#
# <install-dir> is the part's install directory, which becomes the root of the
# snap. Everything written here has to be reachable from inside a strict snap:
# the binary in bin, its compiler runtime in lib, and the launcher files in the
# places snapd looks for them.
set -euo pipefail

INSTALL="${1:?usage: stage.sh <install-dir>}"
# The managed builder pushes the project directory somewhere of its own
# choosing, so the sources are found from this script rather than from $PWD.
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="${CRAFT_PART_BUILD:-/tmp}/smokenot-build"
# Pinned so a rebuild of the same sources gives the same binary.
MOJO_VERSION="1.1.0"
LINKS=(
  -Xlinker=-lgtk-4
  -Xlinker=-lcairo
  -Xlinker=-lgobject-2.0
  -Xlinker=-lgio-2.0
  -Xlinker=-lglib-2.0
)

mkdir -p "$BUILD" "$INSTALL/bin" "$INSTALL/lib" "$INSTALL/usr/share/applications" \
  "$INSTALL/usr/share/icons/hicolor/512x512/apps"

# The compiler is a native binary, so it is installed into a throwaway
# environment rather than the build environment itself.
python3 -m venv "$BUILD/venv"
"$BUILD/venv/bin/pip" install --quiet --disable-pip-version-check \
  "mojo_compiler==$MOJO_VERSION" "mojo_compiler_mojo_libs==$MOJO_VERSION"

echo "==> building the app"
"$BUILD/venv/bin/mojo" build "$SRC/src/main.mojo" -o "$INSTALL/bin/smokenot" "${LINKS[@]}"

# The compiler leaves three runtime libraries behind that the binary needs at
# run time. They are copied next to it and given a path that holds inside the
# snap, where nothing is installed on the system.
echo "==> staging the compiler runtime"
find "$BUILD/venv" -path "*/modular/lib/*.so" -exec cp {} "$INSTALL/lib/" \;
for library in "$INSTALL"/lib/*.so; do
  patchelf --set-rpath '$ORIGIN/../lib' "$INSTALL/bin/smokenot" "$library"
done

# The desktop file, the icon and the AppStream metadata. snapcraft moves the
# desktop file into the snap's own metadata area and rewrites the command, so
# the path here is only the starting point.
echo "==> staging the launcher files"
cp "$SRC/snap/assets/smokenot.desktop" "$INSTALL/usr/share/applications/smokenot.desktop"
# The icon is named after the binary, which is also what GTK asks the icon
# theme for when the window has no application to name it after.
cp "$SRC/snap/assets/smokenot.png" \
  "$INSTALL/usr/share/icons/hicolor/512x512/apps/smokenot.png"
mkdir -p "$INSTALL/usr/share/metainfo"
cp "$SRC/snap/assets/com.gatochalupa.smokenot.metainfo.xml" \
  "$INSTALL/usr/share/metainfo/com.gatochalupa.smokenot.metainfo.xml"

# The venv is not part of the app.
rm -rf "$BUILD/venv"

echo "==> staged:"
find "$INSTALL" -type f -o -type l | sort
