#!/usr/bin/env bash
set -euo pipefail

REPOSITORY_RAW_BASE="https://raw.githubusercontent.com/infoconex/isolated-dotnet-sdk/main"
TOOL_NAME="isolated-dotnet-sdk.sh"
SDK_ROOT="$HOME/dotnet-sdks"
TOOL_PATH="$SDK_ROOT/$TOOL_NAME"
INSTALL_SCRIPT="$SDK_ROOT/dotnet-install.sh"

if [[ -t 1 ]]; then
    CYAN='\033[0;36m'
    YELLOW='\033[0;33m'
    GREEN='\033[0;32m'
    RESET='\033[0m'
else
    CYAN=''
    YELLOW=''
    GREEN=''
    RESET=''
fi

info() {
    printf "%b%s%b %s\n" "$CYAN" "isolated-dotnet-sdk:" "$RESET" "$1"
}

warn() {
    printf "%b%s%b %s\n" "$YELLOW" "isolated-dotnet-sdk:" "$RESET" "$1"
}

success() {
    printf "%b%s%b %s\n" "$GREEN" "isolated-dotnet-sdk:" "$RESET" "$1"
}

fail() {
    printf "%s %s\n" "isolated-dotnet-sdk:" "$1" >&2
    exit 1
}

bootstrap_if_needed() {
    mkdir -p "$SDK_ROOT"

    local current_source="${BASH_SOURCE[0]:-}"
    local current_path=""
    local expected_path

    expected_path="$(cd "$SDK_ROOT" && pwd)/$TOOL_NAME"

    if [[ -n "$current_source" && -f "$current_source" ]]; then
        current_path="$(cd "$(dirname "$current_source")" && pwd)/$(basename "$current_source")"
    fi

    if [[ "$current_path" == "$expected_path" ]]; then
        return
    fi

    info "Installing tool to $TOOL_PATH"

    curl -fsSL \
        "$REPOSITORY_RAW_BASE/$TOOL_NAME" \
        -o "$TOOL_PATH.tmp"

    chmod +x "$TOOL_PATH.tmp"
    mv "$TOOL_PATH.tmp" "$TOOL_PATH"

    success "Tool installed."

    if [[ -t 1 ]]; then
        exec "$TOOL_PATH" "$@" </dev/tty
    fi

    exec "$TOOL_PATH" "$@"
}

confirm() {
    local prompt="$1"

    if [[ "$YES" == "true" ]]; then
        return 0
    fi

    local response=""
    read -r -p "isolated-dotnet-sdk: $prompt [y/N] " response || true
    [[ "$response" =~ ^[Yy]$ ]]
}

validate_version() {
    [[ "$VERSION" =~ ^[0-9A-Za-z][0-9A-Za-z.+-]*$ ]] || \
        fail "Invalid SDK version: $VERSION"
}

get_version_if_needed() {
    if [[ -z "$VERSION" ]]; then
        read -r -p "isolated-dotnet-sdk: .NET SDK version: " VERSION || true
        [[ -n "$VERSION" ]] || fail "An SDK version is required."
    fi

    validate_version
}

list_isolated_sdks() {
    local found="false"
    local path

    info "Isolated SDKs under $SDK_ROOT:"

    for path in "$SDK_ROOT"/*; do
        [[ -d "$path" && -x "$path/dotnet" ]] || continue
        printf "  %s\n" "$(basename "$path")"
        found="true"
    done

    if [[ "$found" == "false" ]]; then
        printf "  %s\n" "None"
    fi
}

install_sdk() {
    get_version_if_needed

    local install_dir="$SDK_ROOT/$VERSION"
    local isolated_dotnet="$install_dir/dotnet"
    local installed_sdks=""
    local installed_versions=""

    info "Target SDK: $VERSION"
    info "Isolated install directory: $install_dir"
    echo

    info "Checking SDKs installed through the normal dotnet host..."

    if command -v dotnet >/dev/null 2>&1; then
        installed_sdks="$(dotnet --list-sdks)"
        printf "%s\n" "$installed_sdks"
        echo

        installed_versions="$(printf "%s\n" "$installed_sdks" | awk '{print $1}')"
    else
        warn "No system dotnet installation was found."
        echo
    fi

    info "Checking for an existing isolated SDK..."

    if [[ -x "$isolated_dotnet" ]] && \
       "$isolated_dotnet" --list-sdks | awk '{print $1}' | grep -Fxq "$VERSION"; then
        success "Isolated SDK $VERSION is already installed."
        info "Location: $install_dir"
        return
    fi

    info "No existing isolated copy was found."
    echo

    if printf "%s\n" "$installed_versions" | grep -Fxq "$VERSION"; then
        warn ".NET SDK $VERSION is already installed normally."

        if ! confirm "Install an isolated copy too?"; then
            info "Installation cancelled."
            return
        fi

        echo
    fi

    info "Downloading Microsoft's dotnet-install.sh script..."
    curl -fsSL https://dot.net/v1/dotnet-install.sh -o "$INSTALL_SCRIPT"

    info "Installing .NET SDK $VERSION..."
    bash "$INSTALL_SCRIPT" \
        --version "$VERSION" \
        --install-dir "$install_dir" \
        --no-path

    echo
    info "Verifying the isolated SDK..."

    local isolated_sdks
    isolated_sdks="$("$isolated_dotnet" --list-sdks)"
    printf "%s\n" "$isolated_sdks"

    if ! printf "%s\n" "$isolated_sdks" | awk '{print $1}' | grep -Fxq "$VERSION"; then
        fail "SDK $VERSION was not found after installation."
    fi

    echo
    success "Isolated SDK installation completed successfully."
    info "Location: $install_dir"
}

remove_sdk() {
    get_version_if_needed

    local install_dir="$SDK_ROOT/$VERSION"
    local isolated_dotnet="$install_dir/dotnet"

    if [[ ! -x "$isolated_dotnet" ]]; then
        fail "Isolated SDK $VERSION was not found at $install_dir"
    fi

    warn "Isolated SDK $VERSION will be removed from $install_dir"

    if ! confirm "Continue?"; then
        info "Removal cancelled."
        return
    fi

    info "Shutting down build servers for SDK $VERSION..."
    "$isolated_dotnet" build-server shutdown

    info "Removing $install_dir..."
    rm -rf "$install_dir"

    [[ ! -d "$install_dir" ]] || fail "SDK directory still exists after removal."

    success "Isolated SDK $VERSION was removed."
}

usage() {
    cat <<'USAGE'
Usage:
  isolated-dotnet-sdk.sh [install] [version] [--yes]
  isolated-dotnet-sdk.sh remove [version] [--yes]
  isolated-dotnet-sdk.sh list

Examples:
  isolated-dotnet-sdk.sh 11.0.100-rc.1.26425.128
  isolated-dotnet-sdk.sh install 11.0.100-rc.1.26425.128
  isolated-dotnet-sdk.sh remove 11.0.100-rc.1.26425.128
  isolated-dotnet-sdk.sh list
USAGE
}

bootstrap_if_needed "$@"

mkdir -p "$SDK_ROOT"
cd "$SDK_ROOT"

ACTION="install"
VERSION=""
YES="false"

if [[ $# -gt 0 ]]; then
    case "$1" in
        install|remove|list)
            ACTION="$1"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            VERSION="$1"
            shift
            ;;
    esac
fi

if [[ "$ACTION" != "list" && -z "$VERSION" && $# -gt 0 && "$1" != "--yes" ]]; then
    VERSION="$1"
    shift
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        --yes|-y)
            YES="true"
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            fail "Unknown argument: $1"
            ;;
    esac
    shift
done

case "$ACTION" in
    install)
        install_sdk
        ;;
    remove)
        remove_sdk
        ;;
    list)
        list_isolated_sdks
        ;;
    *)
        fail "Unknown action: $ACTION"
        ;;
esac
