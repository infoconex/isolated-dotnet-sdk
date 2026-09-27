#!/usr/bin/env bash
set -euo pipefail

REPOSITORY_RAW_BASE="https://raw.githubusercontent.com/infoconex/isolated-dotnet-sdk/main"
RELEASE_INDEX_URL="https://builds.dotnet.microsoft.com/dotnet/release-metadata/releases-index.json"
DOTNET_INSTALL_COMMIT="da3ce11ba63f3dbb0fb835d41bda2665d5c48e84"
DOTNET_INSTALL_SHA256="082f7685e156738a1b2e2ed8381a621870d4ce8e8c59278034556f05c186eb2e"
DOTNET_INSTALL_URL="https://raw.githubusercontent.com/dotnet/install-scripts/$DOTNET_INSTALL_COMMIT/src/dotnet-install.sh"
TOOL_NAME="isolated-dotnet-sdk.sh"
SDK_ROOT="$HOME/dotnet-sdks"
TOOL_PATH="$SDK_ROOT/$TOOL_NAME"
TOOL_INPUT=""

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

tool_info() {
    printf "%b%s%b %s\n" "$CYAN" "isolated-dotnet-sdk:" "$RESET" "$1"
}

tool_warn() {
    printf "%b%s%b %s\n" "$YELLOW" "isolated-dotnet-sdk:" "$RESET" "$1"
}

tool_success() {
    printf "%b%s%b %s\n" "$GREEN" "isolated-dotnet-sdk:" "$RESET" "$1"
}

tool_fail() {
    printf "%s %s\n" "isolated-dotnet-sdk:" "$1" >&2
    exit 1
}

read_tool_input() {
    local prompt="$1"
    TOOL_INPUT=""

    if ! IFS= read -r -p "$prompt" TOOL_INPUT; then
        tool_fail "Interactive input is unavailable."
    fi
}

bootstrap_if_needed() {
    mkdir -p "$SDK_ROOT"

    # File-based invocation preserves the exact executing script. If no source file
    # exists (for example, piped execution), bootstrap falls back to the main source.
    local current_source="${BASH_SOURCE[0]:-}"
    local current_path=""
    local expected_path
    local staged_path=""

    expected_path="$(cd "$SDK_ROOT" && pwd)/$TOOL_NAME"

    if [[ -n "$current_source" && -f "$current_source" ]]; then
        current_path="$(cd "$(dirname "$current_source")" && pwd)/$(basename "$current_source")"
    fi

    if [[ "$current_path" == "$expected_path" ]]; then
        return
    fi

    if [[ -d "$TOOL_PATH" ]]; then
        tool_fail "Tool path is a directory: $TOOL_PATH"
    fi

    tool_info "Installing tool to $TOOL_PATH"
    staged_path="$(mktemp "$SDK_ROOT/.${TOOL_NAME}.XXXXXX.tmp")"

    if [[ -n "$current_path" && -f "$current_path" ]]; then
        if cp "$current_path" "$staged_path"; then
            :
        else
            local status=$?
            rm -f "$staged_path" || true
            return "$status"
        fi
    else
        if curl -fsSL \
            "$REPOSITORY_RAW_BASE/$TOOL_NAME" \
            -o "$staged_path"; then
            :
        else
            local status=$?
            rm -f "$staged_path" || true
            return "$status"
        fi
    fi

    if chmod +x "$staged_path"; then
        :
    else
        local status=$?
        rm -f "$staged_path" || true
        return "$status"
    fi

    if mv "$staged_path" "$TOOL_PATH"; then
        :
    else
        local status=$?
        rm -f "$staged_path" || true
        return "$status"
    fi

    tool_success "Tool installed."

    if tty -s </dev/tty 2>/dev/null; then
        exec "$TOOL_PATH" "$@" </dev/tty
    fi

    exec "$TOOL_PATH" "$@"
}

confirm() {
    local prompt="$1"
    local response=""

    if [[ "$YES" == "true" ]]; then
        return 0
    fi

    read_tool_input "isolated-dotnet-sdk: $prompt [y/N] "
    response="$TOOL_INPUT"
    [[ "$response" =~ ^[Yy]$ ]]
}

validate_version() {
    [[ "$VERSION" =~ ^[0-9A-Za-z][0-9A-Za-z.+-]*$ ]] || \
        tool_fail "Invalid SDK version: $VERSION"
}

contains_line() {
    local lines="$1"
    local expected="$2"
    printf "%s\n" "$lines" | grep -Fxq "$expected"
}

get_system_sdk_versions() {
    if command -v dotnet >/dev/null 2>&1; then
        local sdk_output=""
        if sdk_output="$(dotnet --list-sdks)"; then
            printf "%s\n" "$sdk_output" | awk '{print $1}'
        else
            local status=$?
            tool_fail "Unable to list SDKs through the system dotnet host with exit code $status."
        fi
    fi
}

get_isolated_sdk_versions() {
    local path

    for path in "$SDK_ROOT"/*; do
        [[ -d "$path" && -x "$path/dotnet" ]] || continue
        basename "$path"
    done
}

format_phase() {
    case "$1" in
        preview) printf '%s' 'Preview' ;;
        go-live) printf '%s' 'Go Live' ;;
        active) printf '%s' 'Active' ;;
        maintenance) printf '%s' 'Maintenance' ;;
        eol) printf '%s' 'EOL' ;;
        *) printf '%s' "$1" ;;
    esac
}

looks_like_json_object() {
    local value="$1"
    [[ "$value" =~ ^[[:space:]]*\{ ]] && [[ "$value" =~ \}[[:space:]]*$ ]]
}

# Extract only the release-index fields needed by the interactive picker and emit
# them in a simple pipe-delimited form without adding a JSON-parser dependency.
parse_release_index() {
    awk '
        /"channel-version"[[:space:]]*:/ {
            channel=$0
            sub(/^[^:]*:[[:space:]]*"/, "", channel)
            sub(/".*$/, "", channel)
        }
        /"latest-sdk"[[:space:]]*:/ {
            latest=$0
            sub(/^[^:]*:[[:space:]]*"/, "", latest)
            sub(/".*$/, "", latest)
        }
        /"support-phase"[[:space:]]*:/ {
            phase=$0
            sub(/^[^:]*:[[:space:]]*"/, "", phase)
            sub(/".*$/, "", phase)
        }
        /"release-type"[[:space:]]*:/ {
            type=$0
            sub(/^[^:]*:[[:space:]]*"/, "", type)
            sub(/".*$/, "", type)
        }
        /"releases.json"[[:space:]]*:/ {
            url=$0
            sub(/^[^:]*:[[:space:]]*"/, "", url)
            sub(/".*$/, "", url)
            if (channel != "" && phase != "" && url != "") {
                print channel "|" latest "|" phase "|" type "|" url
            }
            channel=latest=phase=type=url=""
        }
    '
}

extract_sdk_versions() {
    grep -oE '/dotnet/Sdk/[^/"[:space:]]+' |
        sed 's#^.*/Sdk/##' |
        awk '!seen[$0]++'
}

select_action() {
    local selection=""

    while true; do
        tool_info "What would you like to do?"
        echo
        echo "  1. Install an SDK"
        echo "  2. Remove an isolated SDK"
        echo "  3. List isolated SDKs"
        echo "  4. Exit"
        echo
        read_tool_input "Selection: "
        selection="$TOOL_INPUT"

        case "$selection" in
            1) ACTION="install"; return 0 ;;
            2) ACTION="remove"; return 0 ;;
            3) ACTION="list"; return 0 ;;
            4|q|Q) tool_info "Exiting."; return 1 ;;
            *) tool_warn "Please choose 1, 2, 3, or 4." ;;
        esac
    done
}

select_install_version() {
    local index_json
    local channel_data
    local show_archived="false"
    local selection=""
    local channel=""
    local latest_sdk=""
    local phase=""
    local release_type=""
    local releases_url=""
    local metadata_file=""
    local metadata_json=""
    local versions=""
    local system_versions=""
    local isolated_versions=""
    local line=""
    local i=0

    tool_info "Loading available .NET SDK releases from Microsoft..."
    index_json="$(curl -fsSL "$RELEASE_INDEX_URL")" || \
        tool_fail "Unable to load .NET release metadata from Microsoft."

    if ! looks_like_json_object "$index_json" || \
       [[ "$index_json" != *'"releases-index"'* ]]; then
        tool_fail "Invalid .NET release metadata from Microsoft."
    fi

    channel_data="$(printf "%s\n" "$index_json" | parse_release_index)"
    [[ -n "$channel_data" ]] || \
        tool_fail "No selectable .NET channels were found in Microsoft release metadata."

    while true; do
        echo
        if [[ "$show_archived" == "true" ]]; then
            tool_info "Select an end-of-life .NET channel:"
        else
            tool_info "Select a supported or development .NET channel:"
        fi
        echo

        local channels=()
        local latest_sdks=()
        local phases=()
        local release_types=()
        local release_urls=()

        while IFS='|' read -r channel latest_sdk phase release_type releases_url; do
            [[ -n "$channel" ]] || continue

            if [[ "$show_archived" == "true" ]]; then
                [[ "$phase" == "eol" ]] || continue
            else
                [[ "$phase" != "eol" ]] || continue
            fi

            channels+=("$channel")
            latest_sdks+=("$latest_sdk")
            phases+=("$phase")
            release_types+=("$release_type")
            release_urls+=("$releases_url")
        done <<< "$channel_data"

        for ((i=0; i<${#channels[@]}; i++)); do
            printf "  %d. .NET %s  %s  %s  latest SDK %s\n" \
                "$((i + 1))" \
                "${channels[$i]}" \
                "$(printf '%s' "${release_types[$i]}" | tr '[:lower:]' '[:upper:]')" \
                "$(format_phase "${phases[$i]}")" \
                "${latest_sdks[$i]}"
        done

        echo
        if [[ "$show_archived" == "true" ]]; then
            echo "  S. Show supported/development channels"
        else
            echo "  A. Show end-of-life channels"
        fi
        echo "  M. Enter an exact SDK version manually"
        echo "  Q. Cancel"
        echo
        read_tool_input "Selection: "
        selection="$TOOL_INPUT"

        case "$selection" in
            [mM])
                read_tool_input "isolated-dotnet-sdk: .NET SDK version: "
                VERSION="$TOOL_INPUT"
                [[ -n "$VERSION" ]] || tool_fail "An SDK version is required."
                validate_version
                return 0
                ;;
            [qQ])
                return 1
                ;;
            [aA])
                if [[ "$show_archived" == "false" ]]; then
                    show_archived="true"
                    continue
                fi
                ;;
            [sS])
                if [[ "$show_archived" == "true" ]]; then
                    show_archived="false"
                    continue
                fi
                ;;
        esac

        if [[ "$selection" =~ ^[0-9]+$ ]] && \
           (( selection >= 1 && selection <= ${#channels[@]} )); then
            i=$((selection - 1))
            channel="${channels[$i]}"
            latest_sdk="${latest_sdks[$i]}"
            releases_url="${release_urls[$i]}"
        else
            tool_warn "Invalid selection."
            continue
        fi

        metadata_file="$(mktemp "$SDK_ROOT/.release-metadata.XXXXXX")"
        trap 'rm -f "$metadata_file" || true' EXIT
        trap 'rm -f "$metadata_file" || true; trap - TERM; kill -TERM "$$"' TERM
        trap 'rm -f "$metadata_file" || true; trap - INT; kill -INT "$$"' INT
        trap 'rm -f "$metadata_file" || true; trap - HUP; kill -HUP "$$"' HUP

        if ! curl -fsSL "$releases_url" -o "$metadata_file"; then
            trap - EXIT TERM INT HUP
            rm -f "$metadata_file" || true
            tool_fail "Unable to load release metadata for .NET $channel."
        fi

        metadata_json="$(cat "$metadata_file")"
        if ! looks_like_json_object "$metadata_json" || \
           [[ "$metadata_json" != *'"releases"'* ]]; then
            trap - EXIT TERM INT HUP
            rm -f "$metadata_file" || true
            tool_fail "Invalid release metadata for .NET $channel."
        fi

        # The channel-specific metadata supplies the exact SDK versions presented
        # to the user; latest-sdk from the index is only used as a display marker.
        versions="$(extract_sdk_versions < "$metadata_file" || true)"
        trap - EXIT TERM INT HUP
        rm -f "$metadata_file" || true
        metadata_file=""

        [[ -n "$versions" ]] || tool_fail "No SDK versions were found for .NET $channel."

        system_versions="$(get_system_sdk_versions)"
        isolated_versions="$(get_isolated_sdk_versions)"

        while true; do
            echo
            tool_info "Available .NET $channel SDKs:"
            echo

            local sdk_versions=()
            while IFS= read -r line; do
                [[ -n "$line" ]] || continue
                sdk_versions+=("$line")
            done <<< "$versions"

            for ((i=0; i<${#sdk_versions[@]}; i++)); do
                local markers=""
                line="${sdk_versions[$i]}"

                if [[ "$line" == "$latest_sdk" ]]; then
                    markers="latest"
                fi
                if contains_line "$system_versions" "$line"; then
                    markers="${markers:+$markers, }system"
                fi
                if contains_line "$isolated_versions" "$line"; then
                    markers="${markers:+$markers, }isolated"
                fi

                if [[ -n "$markers" ]]; then
                    printf "  %d. %s (%s)\n" "$((i + 1))" "$line" "$markers"
                else
                    printf "  %d. %s\n" "$((i + 1))" "$line"
                fi
            done

            echo
            echo "  B. Back to .NET channels"
            echo "  M. Enter an exact SDK version manually"
            echo "  Q. Cancel"
            echo
            read_tool_input "Selection: "
            selection="$TOOL_INPUT"

            case "$selection" in
                [bB]) break ;;
                [mM])
                    read_tool_input "isolated-dotnet-sdk: .NET SDK version: "
                    VERSION="$TOOL_INPUT"
                    [[ -n "$VERSION" ]] || tool_fail "An SDK version is required."
                    validate_version
                    return 0
                    ;;
                [qQ]) return 1 ;;
            esac

            if [[ "$selection" =~ ^[0-9]+$ ]] && \
               (( selection >= 1 && selection <= ${#sdk_versions[@]} )); then
                VERSION="${sdk_versions[$((selection - 1))]}"
                validate_version
                return 0
            fi

            tool_warn "Invalid selection."
        done
    done
}

select_remove_version() {
    local versions
    local selection=""
    local line=""
    local i=0
    local sdk_versions=()

    versions="$(get_isolated_sdk_versions)"

    if [[ -z "$versions" ]]; then
        tool_info "No isolated SDKs are installed under $SDK_ROOT."
        return 1
    fi

    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        sdk_versions+=("$line")
    done <<< "$versions"

    while true; do
        tool_info "Select an isolated SDK to remove:"
        echo

        for ((i=0; i<${#sdk_versions[@]}; i++)); do
            printf "  %d. %s\n" "$((i + 1))" "${sdk_versions[$i]}"
        done

        echo
        echo "  Q. Cancel"
        echo
        read_tool_input "Selection: "
        selection="$TOOL_INPUT"

        case "$selection" in
            [qQ]) return 1 ;;
        esac

        if [[ "$selection" =~ ^[0-9]+$ ]] && \
           (( selection >= 1 && selection <= ${#sdk_versions[@]} )); then
            VERSION="${sdk_versions[$((selection - 1))]}"
            validate_version
            return 0
        fi

        tool_warn "Invalid selection."
    done
}

resolve_install_version() {
    if [[ -n "$VERSION" ]]; then
        validate_version
        return 0
    fi

    if ! select_install_version; then
        tool_info "Installation cancelled."
        return 1
    fi
}

resolve_remove_version() {
    if [[ -n "$VERSION" ]]; then
        validate_version
        return 0
    fi

    if ! select_remove_version; then
        tool_info "Removal cancelled."
        return 1
    fi
}

list_isolated_sdks() {
    local versions
    local line
    versions="$(get_isolated_sdk_versions)"

    tool_info "Isolated SDKs under $SDK_ROOT:"

    if [[ -z "$versions" ]]; then
        printf "  %s\n" "None"
        return
    fi

    while IFS= read -r line; do
        [[ -n "$line" ]] && printf "  %s\n" "$line"
    done <<< "$versions"
}

cleanup_install_transaction() {
    local helper_path="${1:-}"
    local staging_path="${2:-}"
    local cleanup_failed="false"

    if [[ -n "$helper_path" && ( -e "$helper_path" || -L "$helper_path" ) ]]; then
        if ! rm -f "$helper_path"; then
            tool_warn "Unable to clean install helper: $helper_path"
            cleanup_failed="true"
        fi
    fi

    if [[ -n "$staging_path" && ( -e "$staging_path" || -L "$staging_path" ) ]]; then
        if ! rm -rf "$staging_path"; then
            tool_warn "Unable to clean install staging directory: $staging_path"
            cleanup_failed="true"
        fi
    fi

    [[ "$cleanup_failed" == "false" ]]
}

calculate_sha256() {
    local path="$1"

    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$path" | awk '{print $1}'
        return
    fi

    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$path" | awk '{print $1}'
        return
    fi

    return 1
}

install_sdk() {
    resolve_install_version || return 0

    local install_dir="$SDK_ROOT/$VERSION"
    local isolated_dotnet="$install_dir/dotnet"
    local installed_sdks=""
    local installed_versions=""
    local isolated_sdks=""
    local install_script=""
    local staging_dir=""
    local staged_dotnet=""
    local actual_install_script_hash=""
    local status=0

    tool_info "Target SDK: $VERSION"
    tool_info "Isolated install directory: $install_dir"
    echo

    tool_info "Checking SDKs installed through the normal dotnet host..."

    if command -v dotnet >/dev/null 2>&1; then
        if installed_sdks="$(dotnet --list-sdks)"; then
            :
        else
            status=$?
            tool_fail "Unable to list SDKs through the system dotnet host with exit code $status."
        fi
        printf "%s\n" "$installed_sdks"
        echo

        installed_versions="$(printf "%s\n" "$installed_sdks" | awk '{print $1}')"
    else
        tool_warn "No system dotnet installation was found."
        echo
    fi

    tool_info "Checking for an existing isolated SDK..."

    if [[ -x "$isolated_dotnet" ]]; then
        if isolated_sdks="$("$isolated_dotnet" --list-sdks)"; then
            :
        else
            status=$?
            tool_fail "Unable to inspect existing isolated SDK $VERSION with exit code $status."
        fi

        if printf "%s\n" "$isolated_sdks" | awk '{print $1}' | grep -Fxq "$VERSION"; then
            tool_success "Isolated SDK $VERSION is already installed."
            tool_info "Location: $install_dir"
            return
        fi
    fi

    if [[ -e "$install_dir" || -L "$install_dir" ]]; then
        tool_fail "Isolated SDK destination already exists and cannot be replaced: $install_dir"
    fi

    tool_info "No existing isolated copy was found."
    echo

    if printf "%s\n" "$installed_versions" | grep -Fxq "$VERSION"; then
        tool_warn ".NET SDK $VERSION is already installed normally."

        if ! confirm "Install an isolated copy too?"; then
            tool_info "Installation cancelled."
            return
        fi

        echo
    fi

    install_script="$(mktemp "$SDK_ROOT/dotnet-install.sh.XXXXXX")"
    trap 'cleanup_install_transaction "$install_script" "$staging_dir" || true' EXIT

    tool_info "Downloading Microsoft's pinned dotnet-install.sh script..."
    if curl -fsSL "$DOTNET_INSTALL_URL" -o "$install_script"; then
        :
    else
        status=$?
        tool_fail "Unable to download Microsoft's dotnet-install.sh script with exit code $status."
    fi

    if ! actual_install_script_hash="$(calculate_sha256 "$install_script")"; then
        tool_fail "Unable to verify Microsoft's dotnet-install.sh script because no SHA-256 utility is available."
    fi

    if [[ "$actual_install_script_hash" != "$DOTNET_INSTALL_SHA256" ]]; then
        tool_fail "Integrity verification failed for Microsoft's dotnet-install.sh script."
    fi

    staging_dir="$(mktemp -d "$SDK_ROOT/.install-$VERSION.XXXXXX")"
    staged_dotnet="$staging_dir/dotnet"

    tool_info "Installing .NET SDK $VERSION..."
    if bash "$install_script" \
        --version "$VERSION" \
        --install-dir "$staging_dir" \
        --no-path; then
        :
    else
        status=$?
        tool_fail "dotnet-install failed for SDK $VERSION with exit code $status."
    fi

    echo
    tool_info "Verifying the isolated SDK..."

    if [[ ! -x "$staged_dotnet" ]]; then
        tool_fail "The isolated dotnet executable was not found at $staged_dotnet"
    fi

    if isolated_sdks="$("$staged_dotnet" --list-sdks)"; then
        :
    else
        status=$?
        tool_fail "Unable to verify isolated SDK $VERSION with exit code $status."
    fi
    printf "%s\n" "$isolated_sdks"

    if ! printf "%s\n" "$isolated_sdks" | awk '{print $1}' | grep -Fxq "$VERSION"; then
        tool_fail "SDK $VERSION was not found after installation."
    fi

    if [[ -e "$install_dir" || -L "$install_dir" ]]; then
        tool_fail "Isolated SDK destination already exists and cannot be replaced: $install_dir"
    fi

    if mv "$staging_dir" "$install_dir"; then
        staging_dir=""
    else
        status=$?
        tool_fail "Unable to promote isolated SDK $VERSION into $install_dir with exit code $status."
    fi

    if ! cleanup_install_transaction "$install_script" "$staging_dir"; then
        install_script=""
        staging_dir=""
        trap - EXIT
        tool_fail "Isolated SDK $VERSION was installed, but transaction cleanup failed."
    fi

    install_script=""
    staging_dir=""
    trap - EXIT

    echo
    tool_success "Isolated SDK installation completed successfully."
    tool_info "Location: $install_dir"
}

remove_sdk() {
    resolve_remove_version || return 0

    # Removal is intentionally scoped to the selected version directory under SDK_ROOT.
    local install_dir="$SDK_ROOT/$VERSION"
    local isolated_dotnet="$install_dir/dotnet"
    local status=0

    if [[ ! -x "$isolated_dotnet" ]]; then
        tool_fail "Isolated SDK $VERSION was not found at $install_dir"
    fi

    tool_warn "Isolated SDK $VERSION will be removed from $install_dir"

    if ! confirm "Continue?"; then
        tool_info "Removal cancelled."
        return
    fi

    tool_info "Shutting down build servers for SDK $VERSION..."
    if "$isolated_dotnet" build-server shutdown; then
        :
    else
        status=$?
        tool_fail "Build-server shutdown failed for SDK $VERSION with exit code $status."
    fi

    tool_info "Removing $install_dir..."
    rm -rf "$install_dir"

    [[ ! -d "$install_dir" ]] || tool_fail "SDK directory still exists after removal."

    tool_success "Isolated SDK $VERSION was removed."
}

usage() {
    cat <<'USAGE'
Isolated .NET SDK

Install and manage exact .NET SDK versions under ~/dotnet-sdks without modifying the system-wide .NET installation or PATH.

Usage:
  isolated-dotnet-sdk.sh
  isolated-dotnet-sdk.sh install [version] [--yes|-y]
  isolated-dotnet-sdk.sh remove [version] [--yes|-y]
  isolated-dotnet-sdk.sh list
  isolated-dotnet-sdk.sh [version] [--yes|-y]
  isolated-dotnet-sdk.sh --help|-h

Commands:
  install [version]  Install an isolated SDK. Without a version, show the SDK picker.
  remove [version]   Remove an isolated SDK. Without a version, choose an installed SDK.
  list               List isolated SDKs under ~/dotnet-sdks.

Options:
  --yes, -y          Skip confirmation prompts that support automatic confirmation.
  --help, -h         Show this help text.

Behavior:
  No command         Show the interactive action menu.
  Bare version       Treat the version as an install request.

Project:
  https://github.com/infoconex/isolated-dotnet-sdk
USAGE
}

bootstrap_if_needed "$@"

mkdir -p "$SDK_ROOT"
# Run from SDK_ROOT so caller-directory state such as a repository global.json does
# not influence SDK resolution during the tool's work.
cd "$SDK_ROOT"

ACTION=""
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
        --yes|-y)
            ;;
        *)
            ACTION="install"
            VERSION="$1"
            shift
            ;;
    esac
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
            if [[ "$ACTION" != "list" && -z "$VERSION" ]]; then
                VERSION="$1"
            else
                tool_fail "Unknown argument: $1"
            fi
            ;;
    esac
    shift
done

if [[ -z "$ACTION" ]]; then
    if ! select_action; then
        exit 0
    fi
fi

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
        tool_fail "Unknown action: $ACTION"
        ;;
esac