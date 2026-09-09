#!/usr/bin/env bash
# Create a self-signed PDF signing certificate and import it into NSS
# for use with Okular on Linux (Kubuntu/Ubuntu/Debian).
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: create-okular-pdf-signing-cert.sh [options]

Creates a self-signed X.509 certificate, packs it as PKCS#12, and
imports it into an NSS database that Okular can use.

Options:
  -n, --name NAME          Common Name / display name (required unless prompted)
  -e, --email ADDRESS      Email address (required unless prompted)
  -d, --days N             Validity in days (default: 3650)
  -b, --bits N             RSA key size (default: 4096)
  --nss-dir DIR            NSS database directory (default: ~/.pki/nssdb)
  --out-dir DIR            Where to write key/cert/p12 (default: ~/.pki/pdf-signing)
  --nickname NAME          NSS nickname (default: same as --name)
  --force                  Overwrite existing key/cert/p12 files
  -h, --help               Show this help

The script can be run from any directory. Output always goes to
--out-dir / --nss-dir (defaults under $HOME/.pki), not the current
working directory.

If openssl or libnss3-tools are missing, the script tries to install
them with apt.

Passwords are prompted interactively and are not stored in the script.
Self-signed certificates are not trusted by third parties unless they
explicitly trust your cert.
EOF
}

die() {
  echo "error: $*" >&2
  exit 1
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

abs_path() {
  local path="$1"
  case "$path" in
    ~) path="$HOME" ;;
    ~/*) path="${HOME}/${path#~/}" ;;
  esac
  if command -v realpath >/dev/null 2>&1; then
    # realpath -m allows a path that does not exist yet
    realpath -m "$path"
  else
    # Fallback: resolve relative paths against $PWD
    if [[ "$path" != /* ]]; then
      path="${PWD}/${path}"
    fi
    printf '%s\n' "$path"
  fi
}

ensure_packages() {
  local missing_cmds=()
  have_cmd openssl   || missing_cmds+=(openssl)
  have_cmd certutil  || missing_cmds+=(certutil)
  have_cmd pk12util  || missing_cmds+=(pk12util)

  if [[ ${#missing_cmds[@]} -eq 0 ]]; then
    return 0
  fi

  echo "Missing tools: ${missing_cmds[*]}"

  if ! have_cmd apt-get; then
    die "install openssl and libnss3-tools, then re-run this script"
  fi

  local pkgs=()
  have_cmd openssl || pkgs+=(openssl)
  if ! have_cmd certutil || ! have_cmd pk12util; then
    pkgs+=(libnss3-tools)
  fi

  echo "Trying to install: ${pkgs[*]}"
  if [[ "${EUID}" -eq 0 ]]; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y "${pkgs[@]}"
  elif have_cmd sudo; then
    sudo apt-get update
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${pkgs[@]}"
  else
    die "need root or sudo to install: ${pkgs[*]}"
  fi

  have_cmd openssl  || die "openssl is still missing after install"
  have_cmd certutil || die "certutil is still missing after install (package libnss3-tools)"
  have_cmd pk12util || die "pk12util is still missing after install (package libnss3-tools)"
}

umask 077

NAME=""
EMAIL=""
DAYS=3650
BITS=4096
NSS_DIR="${HOME}/.pki/nssdb"
OUT_DIR="${HOME}/.pki/pdf-signing"
NICKNAME=""
FORCE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--name)      NAME="${2:-}"; shift 2 ;;
    -e|--email)     EMAIL="${2:-}"; shift 2 ;;
    -d|--days)      DAYS="${2:-}"; shift 2 ;;
    -b|--bits)      BITS="${2:-}"; shift 2 ;;
    --nss-dir)      NSS_DIR="${2:-}"; shift 2 ;;
    --out-dir)      OUT_DIR="${2:-}"; shift 2 ;;
    --nickname)     NICKNAME="${2:-}"; shift 2 ;;
    --force)        FORCE=1; shift ;;
    -h|--help)      usage; exit 0 ;;
    *)              die "unknown option: $1" ;;
  esac
done

NSS_DIR="$(abs_path "$NSS_DIR")"
OUT_DIR="$(abs_path "$OUT_DIR")"

ensure_packages

if [[ -z "$NAME" ]]; then
  read -r -p "Full name (CN): " NAME
fi
if [[ -z "$EMAIL" ]]; then
  read -r -p "Email address: " EMAIL
fi

[[ -n "$NAME" ]]  || die "name is required"
[[ -n "$EMAIL" ]] || die "email is required"
[[ "$DAYS" =~ ^[0-9]+$ ]] || die "days must be a number"
[[ "$BITS" =~ ^[0-9]+$ ]] || die "bits must be a number"
[[ "$BITS" -ge 2048 ]]    || die "use at least 2048-bit RSA"

NICKNAME="${NICKNAME:-$NAME}"

mkdir -p "$OUT_DIR" "$NSS_DIR"
chmod 700 "$OUT_DIR" "$NSS_DIR" "$(dirname "$OUT_DIR")" 2>/dev/null || true

KEY="$OUT_DIR/signing.key"
CRT="$OUT_DIR/signing.crt"
P12="$OUT_DIR/signing-certificate.p12"

if [[ -e "$KEY" || -e "$CRT" || -e "$P12" ]]; then
  if [[ "$FORCE" -ne 1 ]]; then
    die "output files already exist in $OUT_DIR (pass --force to overwrite)"
  fi
  rm -f "$KEY" "$CRT" "$P12"
fi

echo "Generating $BITS-bit self-signed certificate for:"
echo "  CN=$NAME"
echo "  email=$EMAIL"
echo "  valid $DAYS days"
echo

openssl req -x509 -newkey "rsa:${BITS}" -sha256 -days "$DAYS" -nodes \
  -keyout "$KEY" -out "$CRT" \
  -subj "/CN=${NAME}/emailAddress=${EMAIL}" \
  -addext "subjectAltName=email:${EMAIL}" \
  -addext "keyUsage=critical,digitalSignature,nonRepudiation" \
  -addext "extendedKeyUsage=emailProtection,clientAuth"

echo
echo "Create a PKCS#12 export password."
echo "This protects signing-certificate.p12 and is separate from the NSS password."
openssl pkcs12 -export \
  -in "$CRT" -inkey "$KEY" \
  -out "$P12" \
  -name "$NICKNAME"

chmod 600 "$KEY" "$CRT" "$P12"

NSS_SPEC="sql:${NSS_DIR}"

if [[ ! -f "${NSS_DIR}/cert9.db" && ! -f "${NSS_DIR}/cert8.db" ]]; then
  echo
  echo "No NSS database found. Creating ${NSS_DIR}"
  echo "Choose an NSS password (Okular will ask for this when signing)."
  certutil -N -d "$NSS_SPEC"
else
  echo
  echo "Using existing NSS database: ${NSS_DIR}"
fi

echo
echo "Importing PKCS#12 into NSS."
echo "You will be asked for the PKCS#12 password, then the NSS password."
pk12util -d "$NSS_SPEC" -i "$P12"

echo
echo "Certificates in NSS database:"
certutil -L -d "$NSS_SPEC" || true
echo
echo "Private keys in NSS database:"
certutil -K -d "$NSS_SPEC" || true

cat <<EOF

Done.

Files:
  $KEY
  $CRT
  $P12

NSS database:
  $NSS_DIR

In Okular:
  Settings → Configure Backends… → PDF
  Certificate database → Custom → $NSS_DIR
  Quit Okular completely, reopen it, then Tools → Digitally Sign…

Keep $P12 as a backup if you want one. You can delete $KEY after a
successful import if you do not want a loose private key on disk.
EOF
