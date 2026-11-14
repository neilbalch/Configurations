#!/usr/bin/env bash
# First install of the ChatGPT and Grok Bot .deb packages for this machine.
# ChatGPT publishes a stable latest package from https://chatgpt.com/download/.
# Grok Bot's download link embeds a build id, so it is read from
# https://cursor.com/download/bot each time.
set -euo pipefail

CHATGPT_LATEST="https://persistent.oaistatic.com/codex-app-prod/linux/deb/latest"
GROK_PAGE="https://cursor.com/download/bot"

die() {
  echo "$*" >&2
  exit 1
}

as_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

command -v curl >/dev/null 2>&1 || die "Missing required command: curl"
command -v apt-get >/dev/null 2>&1 || die "This installer needs apt."
command -v dpkg >/dev/null 2>&1 || die "This installer needs dpkg."

arch="$(dpkg --print-architecture)"
case "$arch" in
  amd64) grok_arch="x64" ;;
  arm64) grok_arch="arm64" ;;
  *) die "Unsupported dpkg architecture: ${arch}" ;;
esac

if [[ "$(id -u)" -ne 0 ]]; then
  sudo -v
fi

workdir="$(mktemp -d /var/tmp/chatgpt-grok.XXXXXX)"
trap 'rm -rf "$workdir"' EXIT

chatgpt_deb="${workdir}/chatgpt_${arch}.deb"
chatgpt_url="${CHATGPT_LATEST}/chatgpt_${arch}.deb"
echo "Downloading ${chatgpt_url}"
curl --proto '=https' --tlsv1.2 -fL --retry 3 --retry-delay 2 -o "$chatgpt_deb" "$chatgpt_url"

echo "Finding the Grok Bot package on ${GROK_PAGE}"
grok_page="$(curl --proto '=https' --tlsv1.2 -fsSL "$GROK_PAGE")"
# The page repeats each link. Keep the first, and drop a trailing backslash from JS-escaped copies.
grok_url="$(printf '%s\n' "$grok_page" | grep -oE \
  "https://downloads\\.cursor\\.com/grokbot/[^\"' ]+/linux/${grok_arch}/[^\"' ]+_${arch}\\.deb" || true)"
grok_url="${grok_url%%$'\n'*}"
grok_url="${grok_url%\\}"
[[ -n "$grok_url" ]] || die "Could not find a Grok Bot .deb for ${arch} on ${GROK_PAGE}"

grok_deb="${workdir}/$(basename "$grok_url")"
echo "Downloading ${grok_url}"
curl --proto '=https' --tlsv1.2 -fL --retry 3 --retry-delay 2 -o "$grok_deb" "$grok_url"

for deb in "$chatgpt_deb" "$grok_deb"; do
  [[ "$(head -c 8 "$deb")" == '!<arch>' ]] || die "Download is not a Debian package: ${deb}"
done

echo "Installing the downloaded packages."
as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y "$chatgpt_deb" "$grok_deb"
echo "Installed ChatGPT and Grok Bot."
