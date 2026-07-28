#!/bin/sh
# DesktopPet one-line installer for Linux (x86_64).
#   curl -fsSL https://github.com/Imzl-zl/desktop-pet/raw/main/web/public/install.sh | sh
# Downloads the latest AppImage to ~/.local/bin , no root, works on any distro.
set -eu

REPO="Imzl-zl/desktop-pet"
DEST="${HOME}/.local/bin"
APP="${DEST}/DesktopPet.AppImage"

case "$(uname -m)" in
  x86_64|amd64) ;;
  *) echo "DesktopPet Linux builds are x86_64 only for now (you have $(uname -m))." >&2; exit 1 ;;
esac

echo "Finding the latest DesktopPet Linux release..."
TAG=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases" \
  | grep -o '"tag_name": *"linux-v[^"]*"' | head -1 \
  | sed 's/.*: *"//; s/"//')
[ -n "${TAG:-}" ] || { echo "Could not find a linux-v* release." >&2; exit 1; }
VER="${TAG#linux-v}"
URL="https://github.com/${REPO}/releases/download/${TAG}/DesktopPet_${VER}_amd64.AppImage"

echo "Downloading DesktopPet ${VER}..."
mkdir -p "${DEST}"
curl -fL "${URL}" -o "${APP}"
chmod +x "${APP}"

echo "Installed to ${APP}"
case ":${PATH}:" in
  *":${DEST}:"*) ;;
  *) echo "Tip: add ${DEST} to your PATH to run 'DesktopPet.AppImage' from anywhere." ;;
esac
echo "Launching..."
( "${APP}" >/dev/null 2>&1 & )
echo "Done. DesktopPet ${VER} is running."
