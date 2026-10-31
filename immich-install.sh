#!/usr/bin/env bash
#
# Immich installer / uninstaller (Docker Compose)
# Detects distro, ensures Docker + Compose, downloads official compose + .env,
# prompts for custom values, starts the stack, and prints the URL.
#
# Usage:
#   bash immich-install.sh            # install
#   bash immich-install.sh uninstall  # stop and optionally remove data
#

set -euo pipefail

START_TIME=$(date +%s)
DEFAULT_DIR="/opt/immich"
SERVICE_PORT=2283
COMPOSE_URL="https://github.com/immich-app/immich/releases/latest/download/docker-compose.yml"
ENV_URL="https://github.com/immich-app/immich/releases/latest/download/example.env"

# ── helpers (logs to stderr) ───────────────────────────────────────────────
die() { echo -e "\n\033[1;31mError:\033[0m $*" >&2; exit 1; }
info() { echo -e "\033[1;34m==>\033[0m $*" >&2; }
ok() { echo -e "\033[1;32m==>\033[0m $*" >&2; }
warn() { echo -e "\033[1;33m==>\033[0m $*" >&2; }
prompt() { local var="$1" msg="$2" default="$3"; read -rp "$msg [$default]: " input; printf -v "$var" '%s' "${input:-$default}"; }
ask_yn() { local msg="$1" default="${2:-n}"; local ans; read -rp "$msg [y/N]: " ans; ans="${ans:-$default}"; [[ "$ans" =~ ^[Yy] ]]; }

elapsed() {
  local end=$(date +%s)
  local secs=$((end - START_TIME))
  printf '%dm %ds' $((secs/60)) $((secs%60))
}

# ── distro detection ───────────────────────────────────────────────────────
detect_distro() {
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    ID="${ID:-}"
    ID_LIKE="${ID_LIKE:-}"
  else
    die "Cannot detect distro (/etc/os-release missing)."
  fi

  case "$ID" in
    debian|ubuntu|linuxmint|pop|elementary|zorin) PKG="apt" ;;
    fedora|rhel|rocky|almalinux|centos|ol)         PKG="dnf" ;;
    arch|manjaro|endeavouros|garuda)               PKG="pacman" ;;
    opensuse*|sles)                                PKG="zypper" ;;
    alpine)                                        PKG="apk" ;;
    *)
      case "$ID_LIKE" in
        *debian*|*ubuntu*) PKG="apt" ;;
        *rhel*|*fedora*)   PKG="dnf" ;;
        *arch*)            PKG="pacman" ;;
        *suse*)            PKG="zypper" ;;
        *) die "Unsupported distro: $ID (ID_LIKE=$ID_LIKE). Supported: Debian/Ubuntu, Fedora/RHEL, Arch, openSUSE, Alpine." ;;
      esac
      ;;
  esac
  info "Detected: $ID ($PKG)"
}

# ── docker ─────────────────────────────────────────────────────────────────
install_docker() {
  info "Checking Docker..."

  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    ok "Docker + Compose already available"
  else
    info "Installing Docker..."
    case "$PKG" in
      apt)
        sudo apt-get update -qq
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io docker-compose-v2 curl ca-certificates
        ;;
      dnf)
        if ! command -v docker >/dev/null 2>&1; then
          sudo dnf install -y docker docker-compose curl ca-certificates || \
          sudo dnf install -y moby-engine docker-compose curl ca-certificates
        else
          sudo dnf install -y docker-compose curl ca-certificates || true
        fi
        ;;
      pacman)
        sudo pacman -Sy --noconfirm docker docker-compose curl ca-certificates
        ;;
      zypper)
        sudo zypper --non-interactive install docker docker-compose curl ca-certificates
        ;;
      apk)
        sudo apk add --no-cache docker docker-cli-compose curl ca-certificates
        ;;
    esac
  fi

  if command -v systemctl >/dev/null 2>&1; then
    sudo systemctl enable --now docker 2>/dev/null || true
  elif command -v rc-service >/dev/null 2>&1; then
    sudo rc-update add docker default 2>/dev/null || true
    sudo rc-service docker start 2>/dev/null || true
  fi

  # ensure compose plugin works
  if ! docker compose version >/dev/null 2>&1; then
    die "Docker Compose plugin not available. Install docker-compose-v2 / docker-compose and re-run."
  fi
  ok "Docker ready."
}

# ── prompts ────────────────────────────────────────────────────────────────
ask_config() {
  echo
  prompt INSTALL_DIR "Install directory" "$DEFAULT_DIR"
  prompt UPLOAD_LOCATION "Photo upload location" "$INSTALL_DIR/library"
  prompt DB_DATA_LOCATION "Database location" "$INSTALL_DIR/postgres"
  prompt TZ "Timezone (e.g. America/New_York, leave blank for UTC)" "Etc/UTC"
  prompt IMMICH_VERSION "Immich version" "v3"
  prompt DB_PASSWORD "Postgres password (A-Za-z0-9 only)" "postgres"

  # basic password check
  if [[ ! "$DB_PASSWORD" =~ ^[A-Za-z0-9]+$ ]]; then
    die "DB_PASSWORD must contain only A-Za-z0-9 (no spaces or special characters)."
  fi
}

# ── install ────────────────────────────────────────────────────────────────
setup_files() {
  info "Setting up $INSTALL_DIR ..."
  sudo mkdir -p "$INSTALL_DIR" "$UPLOAD_LOCATION" "$DB_DATA_LOCATION"
  sudo chown -R "$USER:$USER" "$INSTALL_DIR" "$UPLOAD_LOCATION" "$DB_DATA_LOCATION" 2>/dev/null || true

  info "Downloading docker-compose.yml..."
  curl -fsSL -o "$INSTALL_DIR/docker-compose.yml" "$COMPOSE_URL"

  info "Creating .env..."
  cat > "$INSTALL_DIR/.env" <<ENV
# Immich environment (generated by installer)
UPLOAD_LOCATION=$UPLOAD_LOCATION
DB_DATA_LOCATION=$DB_DATA_LOCATION
TZ=$TZ
IMMICH_VERSION=$IMMICH_VERSION
DB_PASSWORD=$DB_PASSWORD
DB_USERNAME=postgres
DB_DATABASE_NAME=immich
ENV

  ok "Files ready."
}

start_stack() {
  info "Starting Immich (docker compose up -d)..."
  cd "$INSTALL_DIR"
  if docker info >/dev/null 2>&1; then
    docker compose up -d
  else
    sudo docker compose up -d
  fi
  ok "Containers started."
}

# ── uninstall ──────────────────────────────────────────────────────────────
uninstall() {
  echo "Immich uninstaller"
  echo "=================="
  detect_distro

  echo
  prompt INSTALL_DIR "Install directory" "$DEFAULT_DIR"

  if [[ -f "$INSTALL_DIR/docker-compose.yml" ]]; then
    info "Stopping containers..."
    cd "$INSTALL_DIR"
    if docker info >/dev/null 2>&1; then
      docker compose down || true
    else
      sudo docker compose down || true
    fi
    ok "Containers stopped."
  else
    warn "No docker-compose.yml found in $INSTALL_DIR"
  fi

  if ask_yn "Remove install directory $INSTALL_DIR (includes .env and compose file)?"; then
    sudo rm -rf "$INSTALL_DIR"
    ok "Install directory removed."
  fi

  if ask_yn "Also remove uploaded photos and database folders (if outside install dir)?"; then
    # try to read from .env if it still exists, otherwise skip
    if [[ -f "$INSTALL_DIR/.env" ]]; then
      # already removed above in most cases
      :
    fi
    warn "If your library/db were outside $INSTALL_DIR, remove them manually."
  fi

  if ask_yn "Also remove Docker packages? (may affect other containers)"; then
    info "Removing Docker packages..."
    case "$PKG" in
      apt)    sudo apt-get remove -y docker.io docker-compose-v2 || true ;;
      dnf)    sudo dnf remove -y docker docker-compose moby-engine || true ;;
      pacman) sudo pacman -Rns --noconfirm docker docker-compose || true ;;
      zypper) sudo zypper --non-interactive remove docker docker-compose || true ;;
      apk)    sudo apk del docker docker-cli-compose || true ;;
    esac
    ok "Package removal finished."
  fi

  echo
  ok "Uninstall finished in $(elapsed)"
}

# ── main ───────────────────────────────────────────────────────────────────
main() {
  local mode="${1:-install}"

  case "$mode" in
    uninstall|remove|--uninstall|-u)
      uninstall
      ;;
    install|"")
      echo "Immich installer (Docker Compose)"
      echo "================================="
      detect_distro
      install_docker
      ask_config
      setup_files
      start_stack

      local ip
      ip=$(hostname -I 2>/dev/null | awk '{print $1}') || ip="localhost"

      echo
      ok "Done in $(elapsed)"
      echo
      echo "  Open:  http://${ip:-localhost}:$SERVICE_PORT"
      echo "  Dir:   $INSTALL_DIR"
      echo "  Photos:$UPLOAD_LOCATION"
      echo
      echo "Useful commands (run from $INSTALL_DIR):"
      echo "  docker compose ps"
      echo "  docker compose logs -f"
      echo "  docker compose down"
      echo
      echo "To uninstall later: bash $0 uninstall"
      ;;
    *)
      die "Unknown option: $mode. Use: $0 [install|uninstall]"
      ;;
  esac
}

main "$@"
