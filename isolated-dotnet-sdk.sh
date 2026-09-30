#!/usr/bin/env bash
set -euo pipefail

REPOSITORY_RAW_BASE="https://raw.githubusercontent.com/infoconex/isolated-dotnet-sdk/main"
RELEASE_INDEX_URL="https://builds.dotnet.microsoft.com/dotnet/release-metadata/releases-index.json"
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

confirm_action() {
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

get_system_sdk_inventory() {
    if command -v dotnet >/dev/null 2>&1; then
        local sdk_output=""
        if sdk_output="$(dotnet --list-sdks)"; then
            if [[ -n "$sdk_output" ]]; then
                printf "%s\n" "$sdk_output"
            fi
        else
            local status=$?
            tool_fail "Unable to list SDKs through the system dotnet host with exit code $status."
        fi
    fi
    return 0
}

get_system_sdk_versions() {
    local sdk_output=""
    sdk_output="$(get_system_sdk_inventory)"
    if [[ -n "$sdk_output" ]]; then
        printf "%s\n" "$sdk_output" | awk '{print $1}'
    fi
    return 0
}

get_isolated_sdk_versions() {
    local path

    for path in "$SDK_ROOT"/*; do
        [[ -d "$path" && -x "$path/dotnet" ]] || continue
        basename "$path"
    done
}

format_support_phase() {
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

sdk_version_sort_key() {
    local version="$1"
    local core="${version%%-*}"
    local prerelease=""
    local major=0
    local minor=0
    local patch=0
    local rank=9
    local sequence=0
    local build=0
    local revision=0

    if [[ "$version" == *-* ]]; then
        prerelease="${version#*-}"
        rank=1
    fi

    IFS='.' read -r major minor patch <<< "$core"
    [[ "$major" =~ ^[0-9]+$ ]] || major=0
    [[ "$minor" =~ ^[0-9]+$ ]] || minor=0
    [[ "$patch" =~ ^[0-9]+$ ]] || patch=0

    if [[ -n "$prerelease" ]]; then
        local label=""
        IFS='.' read -r label sequence build revision <<< "$prerelease"
        [[ "$sequence" =~ ^[0-9]+$ ]] || sequence=0
        [[ "$build" =~ ^[0-9]+$ ]] || build=0
        [[ "$revision" =~ ^[0-9]+$ ]] || revision=0

        case "$label" in
            rc) rank=8 ;;
            preview) rank=7 ;;
        esac
    fi

    printf '%09d.%09d.%09d.%d.%09d.%09d.%09d' \
        "$major" "$minor" "$patch" "$rank" "$sequence" "$build" "$revision"
}

sort_sdk_versions() {
    local version
    local key
    local index=0
    local tab=$'\t'

    for version in "$@"; do
        key="$(sdk_version_sort_key "$version")"
        printf '%s\t%09d\t%s\n' "$key" "$index" "$version"
        index=$((index + 1))
    done | LC_ALL=C sort -t "$tab" -k1,1r -k2,2n | cut -f3-
}

sdk_feature_band() {
    local version="$1"
    local core="${version%%-*}"
    local major=0
    local minor=0
    local patch=0

    IFS='.' read -r major minor patch <<< "$core"
    if [[ ! "$major" =~ ^[0-9]+$ || ! "$minor" =~ ^[0-9]+$ || ! "$patch" =~ ^[0-9]+$ ]]; then
        printf '%s' "$core"
        return
    fi

    printf '%s.%s.%dxx' "$major" "$minor" "$((patch / 100))"
}

build_compact_sdk_versions() {
    local all_versions="$1"
    local latest_sdk="$2"
    local latest_band=""
    local seen_bands='|'
    local version
    local band

    if [[ -n "$latest_sdk" ]] && contains_line "$all_versions" "$latest_sdk"; then
        printf '%s\n' "$latest_sdk"
        latest_band="$(sdk_feature_band "$latest_sdk")"
        seen_bands="${seen_bands}${latest_band}|"
    fi

    while IFS= read -r version; do
        [[ -n "$version" ]] || continue
        [[ "$version" == "$latest_sdk" ]] && continue

        band="$(sdk_feature_band "$version")"
        if [[ "$seen_bands" == *"|${band}|"* ]]; then
            continue
        fi

        printf '%s\n' "$version"
        seen_bands="${seen_bands}${band}|"
    done <<< "$all_versions"
}

select_action() {
    local selection=""

    while true; do
        tool_info "What would you like to do?"
        echo
        echo "  1. Install an SDK"
        echo "  2. Remove an isolated SDK"
        echo "  3. List installed SDKs"
        echo
        echo "  E. Exit"
        echo
        read_tool_input "Selection: "
        selection="$TOOL_INPUT"

        case "$selection" in
            1) ACTION="install"; return 0 ;;
            2) ACTION="remove"; return 0 ;;
            3) ACTION="list"; return 0 ;;
            e|E) tool_info "Exiting."; return 1 ;;
            *) tool_warn "Please choose 1, 2, 3, or E." ;;
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
    local all_versions=""
    local compact_versions=""
    local display_versions=""
    local show_all_versions="false"
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
            if [[ -n "${latest_sdks[$i]}" ]]; then
                printf "  %d. .NET %s  %s  %s  latest SDK %s\n" \
                    "$((i + 1))" \
                    "${channels[$i]}" \
                    "$(printf '%s' "${release_types[$i]}" | tr '[:lower:]' '[:upper:]')" \
                    "$(format_support_phase "${phases[$i]}")" \
                    "${latest_sdks[$i]}"
            else
                printf "  %d. .NET %s  %s  %s\n" \
                    "$((i + 1))" \
                    "${channels[$i]}" \
                    "$(printf '%s' "${release_types[$i]}" | tr '[:lower:]' '[:upper:]')" \
                    "$(format_support_phase "${phases[$i]}")"
            fi
        done

        echo
        if [[ "$show_archived" == "true" ]]; then
            echo "  S. Show supported/development channels"
        else
            echo "  S. Show end-of-life channels"
        fi
        if [[ "$INTERACTIVE_SESSION" == "true" ]]; then
            echo "  B. Back to Main"
        fi
        echo "  M. Enter an exact SDK version manually"
        if [[ "$INTERACTIVE_SESSION" == "true" ]]; then
            echo "  E. Exit"
        else
            echo "  Q. Cancel"
        fi
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
            [eE])
                if [[ "$INTERACTIVE_SESSION" == "true" ]]; then
                    EXIT_REQUESTED="true"
                    tool_info "Exiting."
                    return 1
                fi
                ;;
            [qQ])
                if [[ "$INTERACTIVE_SESSION" != "true" ]]; then
                    return 1
                fi
                ;;
            [bB])
                if [[ "$INTERACTIVE_SESSION" == "true" ]]; then
                    return 2
                fi
                ;;
            [sS])
                if [[ "$show_archived" == "true" ]]; then
                    show_archived="false"
                else
                    show_archived="true"
                fi
                continue
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

        versions="$(extract_sdk_versions < "$metadata_file" || true)"
        trap - EXIT TERM INT HUP
        rm -f "$metadata_file" || true
        metadata_file=""

        [[ -n "$versions" ]] || tool_fail "No SDK versions were found for .NET $channel."

        local discovered_versions=()
        while IFS= read -r line; do
            [[ -n "$line" ]] || continue
            discovered_versions+=("$line")
        done <<< "$versions"

        all_versions="$(sort_sdk_versions "${discovered_versions[@]}")"
        compact_versions="$(build_compact_sdk_versions "$all_versions" "$latest_sdk")"
        show_all_versions="false"

        system_versions="$(get_system_sdk_versions)"
        isolated_versions="$(get_isolated_sdk_versions)"

        while true; do
            echo
            tool_info "Available .NET $channel SDKs:"
            echo

            if [[ "$show_all_versions" == "true" ]]; then
                display_versions="$all_versions"
            else
                display_versions="$compact_versions"
            fi

            local sdk_versions=()
            while IFS= read -r line; do
                [[ -n "$line" ]] || continue
                sdk_versions+=("$line")
            done <<< "$display_versions"

            for ((i=0; i<${#sdk_versions[@]}; i++)); do
                local markers=""
                line="${sdk_versions[$i]}"

                if [[ -n "$latest_sdk" && "$line" == "$latest_sdk" ]]; then
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
            if [[ "$compact_versions" != "$all_versions" ]]; then
                if [[ "$show_all_versions" == "true" ]]; then
                    echo "  S. Show featured versions"
                else
                    echo "  S. Show all versions"
                fi
            fi
            echo "  B. Back to .NET channels"
            echo "  M. Enter an exact SDK version manually"
            if [[ "$INTERACTIVE_SESSION" == "true" ]]; then
                echo "  E. Exit"
            else
                echo "  Q. Cancel"
            fi
            echo
            read_tool_input "Selection: "
            selection="$TOOL_INPUT"

            case "$selection" in
                [bB]) break ;;
                [sS])
                    if [[ "$compact_versions" != "$all_versions" ]]; then
                        if [[ "$show_all_versions" == "true" ]]; then
                            show_all_versions="false"
                        else
                            show_all_versions="true"
                        fi
                        continue
                    fi
                    ;;
                [mM])
                    read_tool_input "isolated-dotnet-sdk: .NET SDK version: "
                    VERSION="$TOOL_INPUT"
                    [[ -n "$VERSION" ]] || tool_fail "An SDK version is required."
                    validate_version
                    return 0
                    ;;
                [eE])
                    if [[ "$INTERACTIVE_SESSION" == "true" ]]; then
                        EXIT_REQUESTED="true"
                        tool_info "Exiting."
                        return 1
                    fi
                    ;;
                [qQ])
                    if [[ "$INTERACTIVE_SESSION" != "true" ]]; then
                        return 1
                    fi
                    ;;
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
        if [[ "$INTERACTIVE_SESSION" == "true" ]]; then
            echo "  B. Back to Main"
            echo "  E. Exit"
        else
            echo "  Q. Cancel"
        fi
        echo
        read_tool_input "Selection: "
        selection="$TOOL_INPUT"

        case "$selection" in
            [bB])
                if [[ "$INTERACTIVE_SESSION" == "true" ]]; then
                    return 2
                fi
                ;;
            [eE])
                if [[ "$INTERACTIVE_SESSION" == "true" ]]; then
                    EXIT_REQUESTED="true"
                    tool_info "Exiting."
                    return 1
                fi
                ;;
            [qQ])
                if [[ "$INTERACTIVE_SESSION" != "true" ]]; then
                    return 1
                fi
                ;;
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
    local status=0

    if [[ -n "$VERSION" ]]; then
        validate_version
        return 0
    fi

    if select_install_version; then
        return 0
    else
        status=$?
    fi

    if (( status == 2 )); then
        return 2
    fi

    if [[ "$EXIT_REQUESTED" != "true" ]]; then
        tool_info "Installation cancelled."
    fi
    return 1
}

resolve_remove_version() {
    local status=0

    if [[ -n "$VERSION" ]]; then
        validate_version
        return 0
    fi

    if select_remove_version; then
        return 0
    else
        status=$?
    fi

    if (( status == 2 )); then
        return 2
    fi

    if [[ "$EXIT_REQUESTED" != "true" ]]; then
        tool_info "Removal cancelled."
    fi
    return 1
}

list_installed_sdks() {
    local isolated_versions=""
    local system_inventory=""
    local line=""
    local version=""
    local sdk_path=""

    isolated_versions="$(get_isolated_sdk_versions)"
    system_inventory="$(get_system_sdk_inventory)"

    tool_info "Installed .NET SDKs"
    echo
    echo "Isolated SDKs:"

    if [[ -z "$isolated_versions" ]]; then
        printf "  %s\n" "None"
    else
        while IFS= read -r line; do
            [[ -n "$line" ]] && printf "  %s  %s\n" "$line" "$SDK_ROOT/$line"
        done <<< "$isolated_versions"
    fi

    echo
    echo "System SDKs:"

    if [[ -z "$system_inventory" ]]; then
        printf "  %s\n" "None"
        return
    fi

    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        if [[ "$line" =~ ^([^[:space:]]+)[[:space:]]+\[(.*)\]$ ]]; then
            version="${BASH_REMATCH[1]}"
            sdk_path="${BASH_REMATCH[2]}"
            printf "  %s  %s\n" "$version" "$sdk_path"
        else
            printf "  %s\n" "$line"
        fi
    done <<< "$system_inventory"
}

cleanup_install_transaction() {
    local metadata_path="${1:-}"
    local archive_path="${2:-}"
    local staging_path="${3:-}"
    local cleanup_failed="false"

    if [[ -n "$metadata_path" && ( -e "$metadata_path" || -L "$metadata_path" ) ]]; then
        if ! rm -f "$metadata_path"; then
            tool_warn "Unable to clean SDK release metadata: $metadata_path"
            cleanup_failed="true"
        fi
    fi

    if [[ -n "$archive_path" && ( -e "$archive_path" || -L "$archive_path" ) ]]; then
        if ! rm -f "$archive_path"; then
            tool_warn "Unable to clean SDK payload archive: $archive_path"
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

calculate_sha512() {
    local path="$1"

    if command -v sha512sum >/dev/null 2>&1; then
        sha512sum "$path" | awk '{print tolower($1)}'
        return
    fi

    if command -v shasum >/dev/null 2>&1; then
        shasum -a 512 "$path" | awk '{print tolower($1)}'
        return
    fi

    return 1
}

get_sdk_channel() {
    local core="${VERSION%%-*}"
    local major=""
    local minor=""
    local rest=""

    IFS='.' read -r major minor rest <<< "$core"
    if [[ ! "$major" =~ ^[0-9]+$ || ! "$minor" =~ ^[0-9]+$ ]]; then
        tool_fail "Unable to determine the .NET release channel for SDK $VERSION."
    fi

    printf '%s.%s' "$major" "$minor"
}

get_sdk_rid() {
    local os=""
    local arch=""
    local machine=""

    case "$(uname -s)" in
        Linux)
            os="linux"
            if [[ -f /etc/alpine-release ]] || \
               { command -v ldd >/dev/null 2>&1 && ldd --version 2>&1 | grep -qi musl; }; then
                os="linux-musl"
            fi
            ;;
        Darwin) os="osx" ;;
        *) tool_fail "Unable to map the current operating system to a Microsoft SDK artifact." ;;
    esac

    machine="$(uname -m)"
    case "$machine" in
        x86_64|amd64) arch="x64" ;;
        aarch64|arm64) arch="arm64" ;;
        armv7l|armv8l) arch="arm" ;;
        s390x) arch="s390x" ;;
        ppc64le) arch="ppc64le" ;;
        *) tool_fail "Unable to map architecture $machine to a Microsoft SDK artifact." ;;
    esac

    printf '%s-%s' "$os" "$arch"
}

extract_sdk_artifact_metadata() {
    local expected_url="$1"

    awk -v expected="$expected_url" '
        /"url"[[:space:]]*:/ {
            value=$0
            sub(/^[^:]*:[[:space:]]*"/, "", value)
            sub(/".*$/, "", value)
            if (value == expected) {
                candidate=value
            }
            next
        }
        candidate != "" && /"hash"[[:space:]]*:/ {
            hash=$0
            sub(/^[^:]*:[[:space:]]*"/, "", hash)
            sub(/".*$/, "", hash)
            print candidate "|" hash
            candidate=""
        }
    ' | awk '!seen[$0]++'
}

install_isolated_sdk() {
    resolve_install_version || return 0

    local install_dir="$SDK_ROOT/$VERSION"
    local isolated_dotnet="$install_dir/dotnet"
    local installed_sdks=""
    local installed_versions=""
    local isolated_sdks=""
    local metadata_file=""
    local archive_file=""
    local staging_dir=""
    local staged_dotnet=""
    local channel=""
    local rid=""
    local metadata_url=""
    local expected_artifact_url=""
    local artifact_data=""
    local artifact_count=0
    local artifact_url=""
    local expected_hash=""
    local actual_hash=""
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

        if ! confirm_action "Install an isolated copy too?"; then
            tool_info "Installation cancelled."
            return
        fi

        echo
    fi

    channel="$(get_sdk_channel)"
    rid="$(get_sdk_rid)"
    metadata_url="https://builds.dotnet.microsoft.com/dotnet/release-metadata/$channel/releases.json"
    expected_artifact_url="https://builds.dotnet.microsoft.com/dotnet/Sdk/$VERSION/dotnet-sdk-$VERSION-$rid.tar.gz"
    metadata_file="$(mktemp "$SDK_ROOT/.release-metadata-$VERSION.XXXXXX")"
    archive_file="$(mktemp "$SDK_ROOT/.sdk-payload-$VERSION.XXXXXX")"
    trap 'cleanup_install_transaction "$metadata_file" "$archive_file" "$staging_dir" || true' EXIT

    tool_info "Loading Microsoft release metadata for SDK $VERSION..."
    if curl -fsSL "$metadata_url" -o "$metadata_file"; then
        :
    else
        status=$?
        tool_fail "Unable to load Microsoft release metadata for SDK $VERSION with exit code $status."
    fi

    if ! looks_like_json_object "$(cat "$metadata_file")" || \
       [[ "$(cat "$metadata_file")" != *'"releases"'* ]]; then
        tool_fail "Invalid Microsoft release metadata for SDK $VERSION."
    fi

    artifact_data="$(extract_sdk_artifact_metadata "$expected_artifact_url" < "$metadata_file")"
    artifact_count="$(printf '%s\n' "$artifact_data" | awk 'NF { count++ } END { print count + 0 }')"
    if (( artifact_count != 1 )); then
        tool_fail "Microsoft release metadata did not contain exactly one SDK archive for $VERSION and $rid."
    fi

    IFS='|' read -r artifact_url expected_hash <<< "$artifact_data"
    if [[ "$artifact_url" != "$expected_artifact_url" ]]; then
        tool_fail "Microsoft release metadata returned an unexpected SDK archive URL for $VERSION and $rid."
    fi
    if [[ ! "$expected_hash" =~ ^[0-9A-Fa-f]{128}$ ]]; then
        tool_fail "Microsoft release metadata contained an invalid SHA-512 hash for SDK $VERSION and $rid."
    fi
    expected_hash="$(printf '%s' "$expected_hash" | tr '[:upper:]' '[:lower:]')"

    tool_info "Downloading .NET SDK $VERSION payload..."
    if curl -fsSL "$artifact_url" -o "$archive_file"; then
        :
    else
        status=$?
        tool_fail "Unable to download the .NET SDK $VERSION payload with exit code $status."
    fi

    if ! actual_hash="$(calculate_sha512 "$archive_file")"; then
        tool_fail "Unable to verify the .NET SDK $VERSION payload because no SHA-512 utility is available."
    fi

    if [[ "$actual_hash" != "$expected_hash" ]]; then
        tool_fail "Integrity verification failed for the .NET SDK $VERSION payload."
    fi

    staging_dir="$(mktemp -d "$SDK_ROOT/.install-$VERSION.XXXXXX")"
    staged_dotnet="$staging_dir/dotnet"

    tool_info "Extracting verified .NET SDK $VERSION payload..."
    if tar -xzf "$archive_file" -C "$staging_dir"; then
        :
    else
        status=$?
        tool_fail "Unable to extract the verified .NET SDK $VERSION payload with exit code $status."
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

    if ! cleanup_install_transaction "$metadata_file" "$archive_file" "$staging_dir"; then
        metadata_file=""
        archive_file=""
        staging_dir=""
        trap - EXIT
        tool_fail "Isolated SDK $VERSION was installed, but transaction cleanup failed."
    fi

    metadata_file=""
    archive_file=""
    staging_dir=""
    trap - EXIT

    echo
    tool_success "Isolated SDK installation completed successfully."
    tool_info "Location: $install_dir"
}

verify_isolated_sdk() {
    [[ -n "$VERSION" ]] || tool_fail "An exact SDK version is required with verify."
    validate_version

    local install_dir="$SDK_ROOT/$VERSION"
    local isolated_dotnet="$install_dir/dotnet"
    local isolated_sdks=""
    local status=0

    if [[ ! -d "$install_dir" ]]; then
        tool_fail "Isolated SDK $VERSION is not installed under $SDK_ROOT."
    fi

    if [[ ! -e "$isolated_dotnet" && ! -L "$isolated_dotnet" ]]; then
        tool_fail "Isolated SDK $VERSION is incomplete: expected dotnet host was not found at $isolated_dotnet."
    fi

    if [[ ! -x "$isolated_dotnet" ]]; then
        tool_fail "Isolated SDK $VERSION host is not executable: $isolated_dotnet"
    fi

    if isolated_sdks="$("$isolated_dotnet" --list-sdks)"; then
        :
    else
        status=$?
        tool_fail "Unable to verify isolated SDK $VERSION with exit code $status."
    fi

    if ! printf "%s\n" "$isolated_sdks" | awk '{print $1}' | grep -Fxq "$VERSION"; then
        tool_fail "Isolated SDK $VERSION failed verification: the host did not report SDK $VERSION."
    fi

    tool_success "Isolated SDK $VERSION is healthy."
    tool_info "Location: $install_dir"
}

remove_isolated_sdk() {
    resolve_remove_version || return 0

    # Removal is intentionally scoped to the selected version directory under SDK_ROOT.
    local install_dir="$SDK_ROOT/$VERSION"
    local isolated_dotnet="$install_dir/dotnet"
    local status=0

    if [[ ! -x "$isolated_dotnet" ]]; then
        tool_fail "Isolated SDK $VERSION was not found at $install_dir"
    fi

    tool_warn "Isolated SDK $VERSION will be removed from $install_dir"

    if ! confirm_action "Continue?"; then
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

run_selected_action() {
    case "$ACTION" in
        install)
            install_isolated_sdk
            ;;
        remove)
            remove_isolated_sdk
            ;;
        list)
            list_installed_sdks
            ;;
        verify)
            verify_isolated_sdk
            ;;
        *)
            tool_fail "Unknown action: $ACTION"
            ;;
    esac
}

usage() {
    cat <<'USAGE'
Isolated .NET SDK

Install and manage exact .NET SDK versions under ~/dotnet-sdks without modifying the system-wide .NET installation or PATH.

Supported platform:
  Linux and macOS with Bash. Windows uses the PowerShell implementation.

Usage:
  isolated-dotnet-sdk.sh
  isolated-dotnet-sdk.sh install [version] [--yes|-y]
  isolated-dotnet-sdk.sh remove [version] [--yes|-y]
  isolated-dotnet-sdk.sh list
  isolated-dotnet-sdk.sh verify <version>
  isolated-dotnet-sdk.sh [version] [--yes|-y]
  isolated-dotnet-sdk.sh --help|-h

Commands:
  install [version]  Install an isolated SDK. Without a version, show the SDK picker.
  remove [version]   Remove an isolated SDK. Without a version, choose an installed SDK.
  list               List isolated SDKs and SDKs visible through the normal dotnet host. A version is invalid with list.
  verify <version>   Read-only health check for one exact installed isolated SDK.

Options:
  --yes, -y          Skip supported confirmation prompts. It does not choose a missing action or version.
  --help, -h         Show this help text.

Behavior:
  No command         Start a persistent interactive session that returns to Main after normal operations.
  Bare version       Treat the version as a one-shot install request.
  Explicit actions   Run once and exit without entering the persistent Main loop.
  List               Shows isolated ownership first, then read-only SDKs reported by the normal dotnet --list-sdks host.
  Verify <version>   Requires one exact version and checks only the existing isolated installation.
  Exact-version installs bypass release-metadata discovery.
  Interactive install selection uses Microsoft's published release metadata.
  Required interactive input that is unavailable is an operational failure.
  Explicit cancellation is a successful no-change result.
  Operational failures return a nonzero exit status.

Isolation:
  SDKs remain under ~/dotnet-sdks and are not added to PATH.
  Invoke ~/dotnet-sdks/<version>/dotnet directly to use an installed isolated SDK.

Documentation:
  https://github.com/infoconex/isolated-dotnet-sdk#readme
  https://github.com/infoconex/isolated-dotnet-sdk/blob/main/docs/behavioral-parity.md
  https://github.com/infoconex/isolated-dotnet-sdk/blob/main/docs/cross-platform-support.md
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
INTERACTIVE_SESSION="false"
EXIT_REQUESTED="false"

if [[ $# -gt 0 ]]; then
    case "$1" in
        install|remove|list|verify)
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

if [[ -z "$ACTION" && -z "$VERSION" ]]; then
    INTERACTIVE_SESSION="true"
fi

if [[ "$INTERACTIVE_SESSION" == "true" ]]; then
    while true; do
        ACTION=""
        VERSION=""
        EXIT_REQUESTED="false"

        if ! select_action; then
            exit 0
        fi

        echo
        run_selected_action
        if [[ "$EXIT_REQUESTED" == "true" ]]; then
            exit 0
        fi
        echo
    done
fi

run_selected_action