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
API="https://api.github.com/repos/${REPO}/releases/latest"

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

RELEASE_JSON="$(curl -fsSL "$API")" || die "Could not reach GitHub. Check your internet connection."
VERSION="$(printf '%s' "$RELEASE_JSON" | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name": *"v?([^"]+)".*/\1/')"
[ -n "$VERSION" ] || die "Could not determine the latest version."
ok "Latest version is $VERSION"

if [ "$FORMAT" = "deb" ]; then
  PATTERN="\.deb"
else
  PATTERN="\.AppImage"
fi

URL="$(printf '%s' "$RELEASE_JSON" \
  | grep -o '"browser_download_url": *"[^"]*"' \
  | sed -E 's/.*"(https[^"]+)".*/\1/' \
  | grep -iE "$PATTERN$" | grep -i "$ARCH\|amd64" | head -1)"

# Fall back to any artifact of the right type if the name has no arch in it.
[ -z "$URL" ] && URL="$(printf '%s' "$RELEASE_JSON" \
  | grep -o '"browser_download_url": *"[^"]*"' \
  | sed -E 's/.*"(https[^"]+)".*/\1/' \
  | grep -iE "$PATTERN$" | head -1)"

[ -n "$URL" ] || die "No $FORMAT build found in release $VERSION."

TMP="$(mktemp -d)"
FILE="$TMP/$(basename "$URL")"

say "Downloading $(basename "$URL")"
curl -fL --progress-bar "$URL" -o "$FILE" || die "Download failed."

# --- verify -----------------------------------------------------------------

SUMS_URL="$(printf '%s' "$RELEASE_JSON" \
  | grep -o '"browser_download_url": *"[^"]*SHA256SUMS[^"]*"' \
  | sed -E 's/.*"(https[^"]+)".*/\1/' | head -1)"

if [ -n "$SUMS_URL" ] && command -v sha256sum >/dev/null 2>&1; then
  say "Verifying checksum"
  curl -fsSL "$SUMS_URL" -o "$TMP/SHA256SUMS" || die "Could not download SHA256SUMS."
  EXPECTED="$(grep -F "$(basename "$FILE")" "$TMP/SHA256SUMS" | awk '{print $1}' | head -1)"
  ACTUAL="$(sha256sum "$FILE" | awk '{print $1}')"
  [ -n "$EXPECTED" ] || die "No checksum published for $(basename "$FILE")."
  [ "$EXPECTED" = "$ACTUAL" ] || die "Checksum mismatch. The download may be corrupt or tampered with."
  ok "Checksum verified"
else
  warn "No checksum file published for this release - skipping verification."
fi

# --- install ----------------------------------------------------------------

if [ "$FORMAT" = "deb" ]; then
  say "Installing (you will be asked for your password)"
  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get install -y "$FILE" || die "Installation failed."
  else
    sudo dpkg -i "$FILE" || sudo apt-get -f install -y || die "Installation failed."
  fi
  ok "Installed to /opt/Labforge"
  LAUNCH="labforge"
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
