#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Labforge installer.
#
#   curl -fsSL https://labforge.sh/install | bash
#
# Downloads the latest release, verifies its checksum, installs it, and adds it
# to the applications menu. Works on Ubuntu, Debian, Mint, Pop!_OS, Fedora and
# Arch. Asks for sudo only when installing a .deb system-wide.
# ---------------------------------------------------------------------------
set -euo pipefail

REPO="${LABFORGE_REPO:-vedantterse/labforge-dist}"
LIST_API="https://api.github.com/repos/${REPO}/releases?per_page=20"

BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GREEN=$'\033[32m'; CYAN=$'\033[36m'; OFF=$'\033[0m'

say()  { printf '%s==>%s %s\n' "$CYAN" "$OFF" "$1"; }
ok()   { printf '%s  ok%s %s\n' "$GREEN" "$OFF" "$1"; }
warn() { printf '%s  !%s  %s\n' "$RED" "$OFF" "$1"; }
die()  { printf '\n%serror:%s %s\n\n' "$RED" "$OFF" "$1" >&2; exit 1; }

cleanup() { [ -n "${TMP:-}" ] && rm -rf "$TMP"; }
trap cleanup EXIT

printf '\n%sLabforge%s  -  college lab environments, one click\n\n' "$BOLD" "$OFF"

# --- preflight --------------------------------------------------------------

[ "$(id -u)" -eq 0 ] && die "Do not run this installer as root. It will ask for sudo only if it needs to."

for tool in curl grep sed; do
  command -v "$tool" >/dev/null 2>&1 || die "'$tool' is required but not installed."
done

case "$(uname -m)" in
  x86_64 | amd64) ARCH="x64" ;;
  aarch64 | arm64) die "arm64 builds are not published yet. Build from source, or use an x86_64 machine." ;;
  *) die "Unsupported CPU architecture: $(uname -m)" ;;
esac

[ "$(uname -s)" = "Linux" ] || die "This installer is for Linux. On Windows, download the .exe from the releases page."

# --- pick a package format --------------------------------------------------

FORMAT="appimage"
if command -v apt-get >/dev/null 2>&1 && command -v dpkg >/dev/null 2>&1; then
  FORMAT="deb"
fi
[ "${LABFORGE_FORMAT:-}" = "appimage" ] && FORMAT="appimage"

say "Looking up the latest release"

if [ "$FORMAT" = "deb" ]; then
  PATTERN="\.deb"
else
  PATTERN="\.AppImage"
fi

# Ask for the release list rather than /latest. A release with no installers
# attached - a draft published early, or one created by hand - would otherwise
# be chosen as "latest" and the install would fail with nothing to download.
# Walk the list and take the newest release that actually carries a build.
RELEASES_JSON="$(curl -fsSL "$LIST_API")" || die "Could not reach GitHub. Check your internet connection."

CANDIDATES="$(printf '%s' "$RELEASES_JSON" \
  | grep -o '"browser_download_url": *"[^"]*"' \
  | sed -E 's/.*"(https[^"]+)".*/\1/')"

URL="$(printf '%s\n' "$CANDIDATES" | grep -iE "$PATTERN$" | grep -iE "$ARCH|amd64|x86_64" | head -1)"

# Fall back to any build of the right type if the file name carries no arch.
[ -z "$URL" ] && URL="$(printf '%s\n' "$CANDIDATES" | grep -iE "$PATTERN$" | head -1)"

if [ -z "$URL" ]; then
  printf '\n'
  warn "No $FORMAT installer has been published yet."
  printf '    Check https://github.com/%s/releases\n' "$REPO"
  printf '    A release marked "Draft" is not published - only the person who\n'
  printf '    maintains Labforge can publish it.\n\n'
  exit 1
fi

# The download URL carries the version: .../download/v0.2.1/<file>
VERSION="$(printf '%s' "$URL" | sed -E 's#.*/download/v?([^/]+)/.*#\1#')"
[ -n "$VERSION" ] || VERSION="unknown"
ok "Latest published version is $VERSION"

# Look for the checksums beside the installer we actually chose.
SUMS_URL="$(dirname "$URL")/SHA256SUMS"

TMP="$(mktemp -d)"
FILE="$TMP/$(basename "$URL")"

say "Downloading $(basename "$URL")"
curl -fL --progress-bar "$URL" -o "$FILE" || die "Download failed."

# --- verify -----------------------------------------------------------------

if command -v sha256sum >/dev/null 2>&1; then
  say "Verifying checksum"
  curl -fsSL "$SUMS_URL" -o "$TMP/SHA256SUMS" 2>/dev/null || warn "No SHA256SUMS published for this release."
  EXPECTED="$(grep -F "$(basename "$FILE")" "$TMP/SHA256SUMS" 2>/dev/null | awk '{print $1}' | head -1)"
  ACTUAL="$(sha256sum "$FILE" | awk '{print $1}')"
  [ -n "$EXPECTED" ] || warn "No checksum listed for $(basename "$FILE") — skipping verification."
  if [ -n "$EXPECTED" ]; then
    [ "$EXPECTED" = "$ACTUAL" ] || die "Checksum mismatch. The download may be corrupt or tampered with."
    ok "Checksum verified"
  fi
else
  warn "No checksum file published for this release - skipping verification."
fi

# --- install ----------------------------------------------------------------

if [ "$FORMAT" = "deb" ]; then
  say "Installing (you will be asked for your password)"

  # --reinstall matters: without it apt silently skips when the same version is
  # already registered, which leaves a half-installed or previously removed
  # package looking like a success while writing nothing.
  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get install -y --reinstall --allow-downgrades "$FILE" \
      || sudo apt-get install -y "$FILE" \
      || die "Installation failed."
  else
    sudo dpkg -i --force-confnew "$FILE" || sudo apt-get -f install -y || die "Installation failed."
  fi

  # Ask dpkg where the files actually went rather than assuming a path.
  PKG_FILES="$(dpkg -L labforge 2>/dev/null || true)"

  LAUNCH="$(printf '%s\n' "$PKG_FILES" | grep -E '^/usr/(local/)?bin/' | head -1)"

  if [ -z "$LAUNCH" ]; then
    # The package did not ship a launcher on PATH. Find the executable under
    # /opt and link it ourselves so `labforge` works from a terminal.
    TARGET="$(printf '%s\n' "$PKG_FILES" | grep -E '^/opt/[^/]+/[^/]+$' \
      | while IFS= read -r f; do [ -f "$f" ] && [ -x "$f" ] && echo "$f"; done | head -1)"

    if [ -n "$TARGET" ]; then
      sudo mkdir -p /usr/local/bin
      sudo ln -sf "$TARGET" /usr/local/bin/labforge
      LAUNCH="/usr/local/bin/labforge"
      ok "Linked $TARGET to /usr/local/bin/labforge"
    fi
  fi

  INSTALL_ROOT="$(printf '%s\n' "$PKG_FILES" | grep -E '^/opt/[^/]+$' | head -1)"
  ok "Installed to ${INSTALL_ROOT:-/opt/Labforge}"

  if [ -z "$LAUNCH" ]; then
    warn "Installed, but no launcher was found on PATH."
    warn "Start it from your applications menu, or run: $(printf '%s\n' "$PKG_FILES" | grep -E '^/opt/.*' | head -1)"
    LAUNCH="(applications menu)"
  fi
else
  INSTALL_DIR="$HOME/.local/bin"
  APP_DIR="$HOME/.local/share/labforge"
  mkdir -p "$INSTALL_DIR" "$APP_DIR" "$HOME/.local/share/applications" "$HOME/.local/share/icons"

  say "Installing to $APP_DIR"
  install -m 755 "$FILE" "$APP_DIR/Labforge.AppImage"
  ln -sf "$APP_DIR/Labforge.AppImage" "$INSTALL_DIR/labforge"

  # Pull the icon out of the AppImage so the menu entry is not blank.
  ( cd "$TMP" && "$APP_DIR/Labforge.AppImage" --appimage-extract 'labforge.png' >/dev/null 2>&1 || true )
  if [ -f "$TMP/squashfs-root/labforge.png" ]; then
    cp "$TMP/squashfs-root/labforge.png" "$HOME/.local/share/icons/labforge.png"
    ICON="$HOME/.local/share/icons/labforge.png"
  else
    ICON="applications-development"
  fi

  cat > "$HOME/.local/share/applications/labforge.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Labforge
Comment=Run your college lab environments in one click
Exec=$APP_DIR/Labforge.AppImage %U
Icon=$ICON
Terminal=false
Categories=Development;Education;IDE;
StartupWMClass=Labforge
DESKTOP

  update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true
  ok "Installed and added to your applications menu"

  case ":$PATH:" in
    *":$INSTALL_DIR:"*) ;;
    *) warn "$INSTALL_DIR is not on your PATH. Add it to run 'labforge' from a terminal." ;;
  esac
  LAUNCH="$INSTALL_DIR/labforge"
fi

# --- done -------------------------------------------------------------------

cat <<DONE

${GREEN}Labforge $VERSION is installed.${OFF}

  Launch it from your applications menu, or run:

      ${BOLD}${LAUNCH}${OFF}

  ${DIM}On first launch, open the Environment tab and press the fix buttons.
  Labforge will install and configure Docker for you - it asks for your
  password once, and never again.${OFF}

DONE
