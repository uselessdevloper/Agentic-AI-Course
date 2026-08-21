#!/bin/sh
#
# Unsloth Studio Installer
#
# Usage:  curl -fsSL https://unsloth.ai/install.sh | sh
#         wget  -qO- https://unsloth.ai/install.sh | sh
#         ./install.sh --local   (install from a cloned repo instead of PyPI)
#
# Piped installs take options as env vars after the pipe (a bare `| sh --no-torch`
# makes sh reject --no-torch as its own option). Flags still work via ./install.sh:
#   curl -fsSL https://unsloth.ai/install.sh | UNSLOTH_NO_TORCH=1 sh       # skip PyTorch (GGUF-only)
#   curl -fsSL https://unsloth.ai/install.sh | UNSLOTH_SKIP_AUTOSTART=1 sh # do not prompt to launch
#   curl -fsSL https://unsloth.ai/install.sh | UNSLOTH_PYTHON=3.12 sh      # pin Python version
#   curl -fsSL https://unsloth.ai/install.sh | UNSLOTH_STUDIO_HOME=/abs/path sh
# Equivalent flags: ./install.sh --no-torch --python 3.12  (or pipe them: sh -s -- --no-torch)
#
# Install dir priority: UNSLOTH_STUDIO_HOME > STUDIO_HOME (alias) > $HOME/.unsloth/studio
#
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright 2026-present the Unsloth AI Inc. team. All rights reserved. See /studio/LICENSE.AGPL-3.0
set -e

# ── Output style (aligned with studio/setup.sh) ──
RULE=""
_rule_i=0
while [ "$_rule_i" -lt 52 ]; do
    RULE="${RULE}─"
    _rule_i=$((_rule_i + 1))
done
if [ -n "${NO_COLOR:-}" ]; then
    C_TITLE= C_DIM= C_OK= C_WARN= C_ERR= C_RST=
elif [ -t 1 ] || [ -n "${FORCE_COLOR:-}" ]; then
    _ESC="$(printf '\033')"
    C_TITLE="${_ESC}[38;5;150m"
    C_DIM="${_ESC}[38;5;245m"
    C_OK="${_ESC}[38;5;108m"
    C_WARN="${_ESC}[38;5;136m"
    C_ERR="${_ESC}[91m"
    C_RST="${_ESC}[0m"
else
    C_TITLE= C_DIM= C_OK= C_WARN= C_ERR= C_RST=
fi

step()    { printf "  ${C_DIM}%-15.15s${C_RST}${3:-$C_OK}%s${C_RST}\n" "$1" "$2"; }
substep() { printf "  ${C_DIM}%-15s${2:-$C_DIM}%s${C_RST}\n" "" "$1"; }

# ── Parse flags ──
STUDIO_LOCAL_INSTALL=false
PACKAGE_NAME="unsloth"
TAURI_MODE=false
_USER_PYTHON=""
_NO_TORCH_FLAG=false
_SKIP_AUTOSTART=false
_VERBOSE=false
_SHORTCUTS_ONLY=false
_next_is_package=false
_next_is_python=false
_next_is_llama_cpp_dir=false
# Seed from the environment so a caller who exports UNSLOTH_LOCAL_LLAMA_CPP_DIR
# (the documented piped-install style) is honored; the --with-llama-cpp-dir
# flag below overrides it when given.
_WITH_LLAMA_CPP_DIR="${UNSLOTH_LOCAL_LLAMA_CPP_DIR:-}"
for arg in "$@"; do
    if [ "$_next_is_package" = true ]; then
        PACKAGE_NAME="$arg"
        _next_is_package=false
        continue
    fi
    if [ "$_next_is_python" = true ]; then
        _USER_PYTHON="$arg"
        _next_is_python=false
        continue
    fi
    if [ "$_next_is_llama_cpp_dir" = true ]; then
        _WITH_LLAMA_CPP_DIR="$arg"
        _next_is_llama_cpp_dir=false
        continue
    fi
    case "$arg" in
        --local) STUDIO_LOCAL_INSTALL=true ;;
        --package) _next_is_package=true ;;
        --tauri) TAURI_MODE=true ;;
        --python) _next_is_python=true ;;
        --no-torch) _NO_TORCH_FLAG=true ;;
        --verbose|-v) _VERBOSE=true ;;
        --shortcuts-only) _SHORTCUTS_ONLY=true ;;
        --with-llama-cpp-dir) _next_is_llama_cpp_dir=true ;;
    esac
done

# Env-var equivalents for piped installs; an explicit flag still wins.
case "${UNSLOTH_NO_TORCH:-}" in 1|true|TRUE|yes|YES|on|ON) _NO_TORCH_FLAG=true ;; esac
case "${UNSLOTH_SKIP_AUTOSTART:-}" in 1|true|TRUE|yes|YES|on|ON) _SKIP_AUTOSTART=true ;; esac
[ -z "$_USER_PYTHON" ] && [ -n "${UNSLOTH_PYTHON:-}" ] && _USER_PYTHON="$UNSLOTH_PYTHON"

if [ "$_VERBOSE" = true ]; then
    export UNSLOTH_VERBOSE=1
fi

# Custom Unsloth roots are not supported with --tauri (desktop app still
# resolves ~/.unsloth/studio). Pass through if the override == legacy default.
if [ "$TAURI_MODE" = true ]; then
    _tauri_override_var=""
    _tauri_override="${UNSLOTH_STUDIO_HOME:-}"
    if [ -n "$_tauri_override" ]; then
        _tauri_override_var="UNSLOTH_STUDIO_HOME"
    else
        _tauri_override="${STUDIO_HOME:-}"
        [ -n "$_tauri_override" ] && _tauri_override_var="STUDIO_HOME"
    fi
    # Strip whitespace so " " is treated as unset (matches Python .strip()).
    _tauri_override=$(printf '%s' "$_tauri_override" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    if [ -n "$_tauri_override" ]; then
        case "$_tauri_override" in
            "~") _tauri_override="$HOME" ;;
            "~/"*) _tauri_override="$HOME/${_tauri_override#'~/'}" ;;
        esac
        # Canonicalize both sides (CDPATH=, -P) so a CDPATH-set env or
        # symlinked $HOME doesn't break the legacy-equality comparison.
        if [ -d "$_tauri_override" ]; then
            _tauri_override_abs=$(CDPATH= cd -P -- "$_tauri_override" 2>/dev/null && pwd -P) \
                || _tauri_override_abs="$_tauri_override"
        else
            _tauri_override_abs="$_tauri_override"
        fi
        # Strip trailing separators so ".../studio/" matches ".../studio".
        while [ "$_tauri_override_abs" != "/" ] \
            && [ "${_tauri_override_abs%/}" != "$_tauri_override_abs" ]; do
            _tauri_override_abs=${_tauri_override_abs%/}
        done
        _tauri_legacy_root="$HOME/.unsloth/studio"
        if [ -d "$_tauri_legacy_root" ]; then
            _tauri_legacy_root=$(CDPATH= cd -P -- "$_tauri_legacy_root" 2>/dev/null && pwd -P) \
                || _tauri_legacy_root="$HOME/.unsloth/studio"
        fi
        while [ "$_tauri_legacy_root" != "/" ] \
            && [ "${_tauri_legacy_root%/}" != "$_tauri_legacy_root" ]; do
            _tauri_legacy_root=${_tauri_legacy_root%/}
        done
        if [ "$_tauri_override_abs" != "$_tauri_legacy_root" ]; then
            echo "ERROR: $_tauri_override_var is not supported with --tauri." >&2
            echo "       The desktop app still uses the legacy ~/.unsloth/studio root." >&2
            echo "       Run install.sh without --tauri for custom-root shell installs," >&2
            echo "       or unset the env var for default desktop installs." >&2
            exit 1
        fi
    fi
fi

_is_verbose() {
    [ "${UNSLOTH_VERBOSE:-0}" = "1" ]
}

run_maybe_quiet() {
    if _is_verbose; then
        "$@"
    else
        "$@" > /dev/null 2>&1
    fi
}

# Trim trailing slashes from the URL PATH only, preserving ?query / #fragment: a whole-URL
# strip corrupts a token ending in "/", a single strip leaves .../cu128// empty. Shared.
_trim_index_path_slashes() {
    _tips_v="$1"
    case "$_tips_v" in
        *[?#]*)
            _tips_head="${_tips_v%%[?#]*}"
            _tips_tail="${_tips_v#"$_tips_head"}"
            ;;
        *)
            _tips_head="$_tips_v"
            _tips_tail=""
            ;;
    esac
    while [ -n "$_tips_head" ] && [ "${_tips_head%/}" != "$_tips_head" ]; do
        _tips_head="${_tips_head%/}"
    done
    printf '%s%s' "$_tips_head" "$_tips_tail"
}

# Redact index-URL credentials (userinfo + ?query= + #fragment) from captured installer
# output before printing on failure; uv/pip errors echo the failing --index-url verbatim.
# Mirrors the other installers. Verbose mode streams uncaptured, so it isn't redacted.
_redact_install_output() {
    sed -E \
        -e 's#(https?://)[^/@[:space:]`]+@#\1<redacted>@#g' \
        -e 's#([?&][^=[:space:]&`]+)=[^&#[:space:]`]+#\1=<redacted>#g' \
        -e 's|(https?://[^[:space:]`#]+)#[^[:space:]`]+|\1#<redacted>|g' \
        "$@"
}

run_install_cmd() {
    _label="$1"
    shift
    # Installer-pinned index installs (torch) must beat an inherited uv mirror (#6898):
    # for --default-index, neutralize the uv index/backend/config vars (UV_TORCH_BACKEND
    # redirects torch; UV_NO_CONFIG=1 + dropping UV_CONFIG_FILE stops a uv.toml/pyproject
    # index outranking the CLI pin, uv 0.10).
    case " $* " in
        *" --default-index "*) set -- env -u UV_DEFAULT_INDEX -u UV_INDEX_URL -u UV_INDEX -u UV_EXTRA_INDEX_URL -u UV_TORCH_BACKEND -u UV_FIND_LINKS -u UV_CONFIG_FILE UV_NO_CONFIG=1 "$@" ;;
    esac
    if _is_verbose; then
        # Stream through the redactor: uv echoes index URLs (credentials and
        # all) in its errors, and verbose mode previously bypassed the
        # redaction the quiet path applies. The rc file preserves the
        # command's exit code across the pipe without relying on pipefail
        # (this script runs under plain sh).
        _rcf=$(mktemp)
        { "$@" 2>&1; printf '%s' "$?" > "$_rcf"; } | _redact_install_output
        _rc=$(cat "$_rcf" 2>/dev/null || echo 1)
        rm -f "$_rcf"
        [ "${_rc:-1}" -eq 0 ] 2>/dev/null && return 0
        step "error" "$_label failed (exit code $_rc)" "$C_ERR" >&2
        return "$_rc"
    fi
    _log=$(mktemp)
    "$@" >"$_log" 2>&1 && { rm -f "$_log"; return 0; }
    _rc=$?
    step "error" "$_label failed (exit code $_rc)" "$C_ERR" >&2
    _redact_install_output "$_log" >&2
    rm -f "$_log"
    return $_rc
}

# Retry run_install_cmd on transient uv download failures with backoff. Returns
# the last exit code on permanent failure so the set -e rollback trap still fires.
: "${UNSLOTH_INSTALL_RETRIES:=3}"
: "${UNSLOTH_INSTALL_RETRY_DELAY:=3}"
run_install_cmd_retry() {
    _ricr_label="$1"
    # Sanitize overrides to a default of 3 (a typo must not disable retries; =1 disables).
    # Length guard precedes the numeric test so a huge value can't overflow `[ -ge ]`.
    # 0?* rejects leading-zero delays ("08"/"09" break the later $((delay*2)) as octal);
    # bare "0" stays valid. Bounds: 1..100 retries, 0..3600s base delay.
    case "$UNSLOTH_INSTALL_RETRIES" in
        ''|*[!0-9]*|0) _ricr_max=3 ;;
        *) if [ "${#UNSLOTH_INSTALL_RETRIES}" -le 3 ] && [ "$UNSLOTH_INSTALL_RETRIES" -ge 1 ] 2>/dev/null && [ "$UNSLOTH_INSTALL_RETRIES" -le 100 ] 2>/dev/null; then _ricr_max=$UNSLOTH_INSTALL_RETRIES; else _ricr_max=3; fi ;;
    esac
    case "$UNSLOTH_INSTALL_RETRY_DELAY" in
        ''|*[!0-9]*|0?*) _ricr_delay=3 ;;
        *) if [ "${#UNSLOTH_INSTALL_RETRY_DELAY}" -le 4 ] && [ "$UNSLOTH_INSTALL_RETRY_DELAY" -ge 0 ] 2>/dev/null && [ "$UNSLOTH_INSTALL_RETRY_DELAY" -le 3600 ] 2>/dev/null; then _ricr_delay=$UNSLOTH_INSTALL_RETRY_DELAY; else _ricr_delay=3; fi ;;
    esac
    _ricr_attempt=1
    while :; do
        # AND-OR (not `if`) preserves the real failure code: $? after a non-taken
        # `if` is 0 in sh/dash/bash, which would break the rollback path.
        run_install_cmd "$@" && return 0
        _ricr_rc=$?
        if [ "$_ricr_attempt" -ge "$_ricr_max" ]; then
            return "$_ricr_rc"
        fi
        substep "retrying \"$_ricr_label\" after transient failure (attempt $((_ricr_attempt + 1))/$_ricr_max, waiting ${_ricr_delay}s)..." "$C_WARN"
        sleep "$_ricr_delay" || true
        _ricr_attempt=$((_ricr_attempt + 1))
        _ricr_delay=$((_ricr_delay * 2))
    done
}

# Install bitsandbytes on AMD ROCm hosts. Uses the continuous-release_main
# wheel for the ROCm 4-bit GEMV fix (bnb PR #1887, post-0.49.2); bnb <= 0.49.2
# NaNs at decode shape on every AMD GPU. Falls back to PyPI >=0.49.1 if the
# pre-release URL is unreachable. Drop the pin once bnb 0.50+ ships on PyPI.
_install_bnb_rocm() {
    _label="$1"
    _venv_py="$2"
    case "$_ARCH" in
        x86_64|amd64)
            _bnb_whl_url="https://github.com/bitsandbytes-foundation/bitsandbytes/releases/download/continuous-release_main/bitsandbytes-1.33.7.preview-py3-none-manylinux_2_24_x86_64.whl"
            ;;
        aarch64|arm64)
            _bnb_whl_url="https://github.com/bitsandbytes-foundation/bitsandbytes/releases/download/continuous-release_main/bitsandbytes-1.33.7.preview-py3-none-manylinux_2_24_aarch64.whl"
            ;;
        *)
            _bnb_whl_url=""
            ;;
    esac
    # uv rejects the continuous-release_main bitsandbytes wheel because the
    # filename version (1.33.7rc0) does not match the embedded metadata version
    # (0.50.0.dev0). pip accepts the mismatch, so bootstrap pip and use it.
    if ! "$_venv_py" -m pip --version >/dev/null 2>&1; then
        if ! run_maybe_quiet "$_venv_py" -m ensurepip --upgrade; then
            run_maybe_quiet uv pip install --python "$_venv_py" pip || \
                substep "[WARN] could not bootstrap pip; bitsandbytes install will likely fail" "$C_WARN"
        fi
    fi
    if [ -n "$_bnb_whl_url" ]; then
        substep "installing bitsandbytes for AMD ROCm (pre-release, PR #1887)..."
        _bnb_log=$(mktemp)
        if "$_venv_py" -m pip install \
            --disable-pip-version-check \
            --force-reinstall --no-cache-dir --no-deps \
            --retries 8 --timeout 90 \
            "$_bnb_whl_url" >"$_bnb_log" 2>&1; then
            rm -f "$_bnb_log"
            return 0
        fi
        _bnb_rc=$?
        if _is_verbose; then
            _redact_install_output "$_bnb_log" >&2
        fi
        rm -f "$_bnb_log"
        step "warning" "$_label (pre-release) failed (exit code $_bnb_rc)" "$C_WARN" >&2
        substep "[WARN] bnb pre-release install failed; falling back to PyPI (4-bit decode broken on ROCm)" "$C_WARN"
    fi
    run_install_cmd "$_label (pypi fallback)" "$_venv_py" -m pip install \
        --force-reinstall --no-cache-dir --no-deps "bitsandbytes>=0.49.1"
}

if [ "$_next_is_package" = true ]; then
    echo "❌ ERROR: --package requires an argument." >&2
    exit 1
fi
if [ "$_next_is_python" = true ]; then
    echo "❌ ERROR: --python requires a version argument (e.g. --python 3.12)." >&2
    exit 1
fi
if [ "$_next_is_llama_cpp_dir" = true ]; then
    echo "❌ ERROR: --with-llama-cpp-dir requires a path argument." >&2
    exit 1
fi

# Validate --package to prevent injection into shell/Python commands.
# Must start with a letter/digit (rejects leading dashes that uv would parse as flags).
case "$PACKAGE_NAME" in
    [!a-zA-Z0-9]*)
        echo "❌ ERROR: --package name must start with a letter or digit." >&2
        exit 1 ;;
    *[!a-zA-Z0-9._-]*)
        echo "❌ ERROR: --package name contains invalid characters (allowed: a-z A-Z 0-9 . _ -)" >&2
        exit 1 ;;
esac

# ── Tauri structured output ──
tauri_log() {
    if [ "$TAURI_MODE" = true ]; then
        echo "[TAURI:$1] $2"
    fi
}

tauri_diag_marker() {
    _diag_gpu_branch="${1:-unknown}"
    _diag_torch_index_family="${2:-none}"
    tauri_log "DIAG" "diag_schema=1 platform=${OS:-unknown} arch=${_ARCH:-unknown} python_version=${PYTHON_VERSION:-unknown} skip_torch=${SKIP_TORCH:-false} mac_intel=${MAC_INTEL:-false} gpu_branch=${_diag_gpu_branch} torch_index_family=${_diag_torch_index_family}"
}

_tauri_torch_index_family() {
    if [ "${SKIP_TORCH:-false}" = true ]; then
        echo "none"
        return
    fi
    _diag_url="${1:-}"
    # Strip query/fragment AND a trailing slash before classifying (like _torch_index_url_leaf):
    # a token isn't echoed into [TAURI:DIAG], and .../cu128/?token=x still classifies as cu128.
    _diag_url="${_diag_url%%\?*}"
    _diag_url="${_diag_url%%#*}"
    _diag_url="${_diag_url%/}"
    case "$_diag_url" in
        */cu118) echo "cu118" ;;
        */cu124) echo "cu124" ;;
        */cu126) echo "cu126" ;;
        */cu128) echo "cu128" ;;
        */cu130) echo "cu130" ;;
        */cpu) echo "cpu" ;;
        */rocm[0-9]*.[0-9]*)
            _diag_family=${_diag_url##*/}
            case "$_diag_family" in
                rocm[0-9]*.[0-9]*) echo "$_diag_family" ;;
                *) echo "auto" ;;
            esac ;;
        # AMD arch-specific index (e.g. repo.amd.com/rocm/whl/gfx1151/) --
        # used for Strix Halo/Point where torch 2.11+rocm7.13 has the real fix.
        *repo.amd.com/rocm/whl/gfx*|*rocm/whl/gfx*) echo "rocm7.13" ;;
        "") echo "none" ;;
        *) echo "auto" ;;
    esac
}

_tauri_gpu_branch() {
    _diag_family="${1:-unknown}"
    _diag_radeon="${2:-false}"
    if [ "${SKIP_TORCH:-false}" = true ]; then
        echo "no_torch"
        return
    fi
    if [ "${OS:-}" = "macos" ]; then
        echo "mac"
        return
    fi
    case "$_diag_family" in
        # Require a digit after cu so /current or /custom isn't branded CUDA (parity ^cu[0-9]).
        cu[0-9]*) echo "cuda" ;;
        rocm*)
            if [ "$_diag_radeon" = true ]; then
                echo "rocm_radeon"
            else
                echo "rocm"
            fi ;;
        radeon) echo "rocm_radeon" ;;
        cpu) echo "cpu" ;;
        none) echo "no_torch" ;;
        *) echo "unknown" ;;
    esac
}

PYTHON_VERSION=""  # resolved after platform detection

# Resolve install destinations: env override, HOME-redirect (best-effort
# via getent/dscl), or default. Env-var priority: UNSLOTH_STUDIO_HOME wins
# over STUDIO_HOME (the more specific signal beats the generic alias).
_resolve_studio_destinations() {
    _override_var=""
    _override="${UNSLOTH_STUDIO_HOME:-}"
    if [ -n "$_override" ]; then
        _override_var="UNSLOTH_STUDIO_HOME"
    else
        _override="${STUDIO_HOME:-}"
        [ -n "$_override" ] && _override_var="STUDIO_HOME"
    fi
    # Strip surrounding whitespace so " " is treated as unset (matches the
    # Python resolvers' .strip()), preventing install/runtime layout drift.
    _override=$(printf '%s' "$_override" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    # Tilde expansion: env vars are not subject to it when quoted on assignment.
    case "$_override" in
        "~") _override="$HOME" ;;
        "~/"*) _override="$HOME/${_override#'~/'}" ;;
    esac
    if [ -n "$_override" ]; then
        mkdir -p -- "$_override" 2>/dev/null || { echo "ERROR: $_override_var=$_override cannot be created." >&2; exit 1; }
        [ -w "$_override" ] || { echo "ERROR: $_override_var=$_override is not writable." >&2; exit 1; }
        STUDIO_HOME="$(CDPATH= cd -P -- "$_override" && pwd -P)" || exit 1
        DATA_DIR="$STUDIO_HOME/share"
        _LOCAL_BIN="$STUDIO_HOME/bin"
        _STUDIO_HOME_REDIRECT=env
        substep "custom $_override_var=$STUDIO_HOME"
        return 0
    fi
    _default_home=""
    if command -v getent >/dev/null 2>&1; then
        _default_home=$(getent passwd "${USER:-$(whoami)}" 2>/dev/null | cut -d: -f6)
    elif [ "$(uname)" = "Darwin" ] && command -v dscl >/dev/null 2>&1; then
        _default_home=$(dscl . -read "/Users/${USER:-$(whoami)}" NFSHomeDirectory 2>/dev/null | awk '{print $2}')
    fi
    # Canonicalize both sides so a trailing slash on $HOME (or symlink mismatch
    # with passwd-DB output) doesn't misfire the redirection branch.
    _home_canon="$HOME"
    if [ -d "$_home_canon" ]; then
        _home_canon=$(CDPATH= cd -P -- "$_home_canon" 2>/dev/null && pwd -P) || _home_canon="$HOME"
    fi
    _default_home_canon="$_default_home"
    if [ -n "$_default_home_canon" ] && [ -d "$_default_home_canon" ]; then
        _default_home_canon=$(CDPATH= cd -P -- "$_default_home_canon" 2>/dev/null && pwd -P) || _default_home_canon="$_default_home"
    fi
    if [ -n "$_default_home_canon" ] && [ "$_home_canon" != "$_default_home_canon" ]; then
        STUDIO_HOME="$HOME/.unsloth/studio"
        DATA_DIR="$HOME/.local/share/unsloth"
        _LOCAL_BIN="$HOME/.local/bin"
        _STUDIO_HOME_REDIRECT=home
        substep "HOME redirected ($HOME); install follows \$HOME"
        return 0
    fi
    STUDIO_HOME="$HOME/.unsloth/studio"
    DATA_DIR="$HOME/.local/share/unsloth"
    _LOCAL_BIN="$HOME/.local/bin"
    _STUDIO_HOME_REDIRECT=default
}
_resolve_studio_destinations
VENV_DIR="$STUDIO_HOME/unsloth_studio"
_VENV_ROLLBACK_DIR=""
_VENV_ROLLBACK_TARGET="$VENV_DIR"
_VENV_ROLLBACK_ACTIVE=false

_start_studio_venv_replacement() {
    _existing_dir="$1"
    _stamp=$(date +%Y%m%d%H%M%S 2>/dev/null || echo "time")
    _candidate="$STUDIO_HOME/unsloth_studio.rollback.$_stamp.$$"
    _suffix=0
    while [ -e "$_candidate" ] || [ -L "$_candidate" ]; do
        _suffix=$((_suffix + 1))
        _candidate="$STUDIO_HOME/unsloth_studio.rollback.$_stamp.$$.$_suffix"
    done
    _VENV_ROLLBACK_DIR="$_candidate"
    _VENV_ROLLBACK_TARGET="$_existing_dir"
    _VENV_ROLLBACK_ACTIVE=true
    # Publish the rollback state before the atomic rename so a signal cannot
    # land after mv but before the exit handlers know where the old venv went.
    if ! mv "$_existing_dir" "$_candidate"; then
        _VENV_ROLLBACK_ACTIVE=false
        _VENV_ROLLBACK_DIR=""
        return 1
    fi
    substep "previous environment preserved for rollback"
}

_restore_studio_venv_replacement() {
    [ "$_VENV_ROLLBACK_ACTIVE" = true ] || return 0
    [ -n "$_VENV_ROLLBACK_DIR" ] && [ -d "$_VENV_ROLLBACK_DIR" ] || {
        _VENV_ROLLBACK_ACTIVE=false
        return 0
    }
    substep "restoring previous environment after failed install..." "$C_WARN"
    rm -rf "$_VENV_ROLLBACK_TARGET"
    if mv "$_VENV_ROLLBACK_DIR" "$_VENV_ROLLBACK_TARGET"; then
        substep "restored previous environment"
        _VENV_ROLLBACK_ACTIVE=false
        _VENV_ROLLBACK_DIR=""
    else
        echo "⚠️  Could not restore previous environment from $_VENV_ROLLBACK_DIR to $_VENV_ROLLBACK_TARGET" >&2
    fi
}

_studio_venv_rollback_must_be_preserved() {
    _rollback_name=${1##*/}
    _rollback_metadata=${_rollback_name#unsloth_studio.rollback.}
    _rollback_stamp=${_rollback_metadata%%.*}
    _rollback_process=${_rollback_metadata#*.}
    # Preserve anything outside the installer's timestamp.PID[.suffix] format.
    [ "$_rollback_process" != "$_rollback_metadata" ] || return 0
    case "$_rollback_stamp" in
        time) ;;
        ''|*[!0-9]*) return 0 ;;
        *) [ "${#_rollback_stamp}" -eq 14 ] || return 0 ;;
    esac
    _rollback_pid=${_rollback_process%%.*}
    case "$_rollback_pid" in
        ''|*[!0-9]*) return 0 ;;
    esac
    _rollback_suffix=${_rollback_process#*.}
    if [ "$_rollback_suffix" != "$_rollback_process" ]; then
        case "$_rollback_suffix" in ''|*[!0-9]*) return 0 ;; esac
    fi
    kill -0 "$_rollback_pid" 2>/dev/null
}

_prune_stale_studio_venv_rollbacks() {
    for _stale_rollback in "$STUDIO_HOME"/unsloth_studio.rollback.*; do
        [ -d "$_stale_rollback" ] || continue
        if [ -L "$_stale_rollback" ]; then
            echo "⚠️  Refusing to remove rollback symlink $_stale_rollback" >&2
            continue
        fi
        # A concurrent installer may have moved its live venv aside. The PID in
        # the generated name keeps this successful run from deleting its rescue copy.
        _studio_venv_rollback_must_be_preserved "$_stale_rollback" && continue
        if rm -rf "$_stale_rollback"; then
            substep "removed stale environment rollback ${_stale_rollback##*/}"
        else
            echo "⚠️  Could not remove stale environment rollback $_stale_rollback" >&2
        fi
    done
}

_commit_studio_venv_replacement() {
    if [ "$_VENV_ROLLBACK_ACTIVE" = true ]; then
        _rollback_to_remove="$_VENV_ROLLBACK_DIR"
        # The new environment is already committed. Clear the restore state
        # before deletion so an interrupt cannot replace it with a half-deleted backup.
        _VENV_ROLLBACK_ACTIVE=false
        _VENV_ROLLBACK_DIR=""
        if [ -n "$_rollback_to_remove" ] && [ -d "$_rollback_to_remove" ]; then
            if ! rm -rf "$_rollback_to_remove"; then
                echo "⚠️  Could not remove environment rollback $_rollback_to_remove" >&2
            fi
        fi
    fi
    # Only prune older orphaned copies after the replacement has succeeded, so
    # an interrupted install never discards the last known-good environment.
    _prune_stale_studio_venv_rollbacks
}

_cleanup_install_temporaries() {
    [ -n "${_UV_OVERRIDE_TMPDIR:-}" ] && rm -rf "$_UV_OVERRIDE_TMPDIR" 2>/dev/null || true
    [ -n "${_UNSLOTH_TORCH_OVERRIDES:-}" ] && rm -f "$_UNSLOTH_TORCH_OVERRIDES" 2>/dev/null || true
}

_on_install_exit() {
    _status=$?
    if [ "$_status" -ne 0 ]; then
        _restore_studio_venv_replacement
    fi
    _cleanup_install_temporaries
    exit "$_status"
}

_on_install_signal() {
    _signal_status="$1"
    # EXIT is disabled to avoid a second cleanup pass. Ignore further termination
    # signals until the old environment is back in place.
    trap - EXIT
    trap '' HUP INT TERM
    _restore_studio_venv_replacement
    _cleanup_install_temporaries
    exit "$_signal_status"
}
# Empty so an inherited value never reaches the trap's rm; only temp paths this
# script creates below (spaced-path dir, torch-trio overrides) are removed.
_UV_OVERRIDE_TMPDIR=""
_UNSLOTH_TORCH_OVERRIDES=""
trap _on_install_exit EXIT
trap '_on_install_signal 129' HUP
trap '_on_install_signal 130' INT
trap '_on_install_signal 143' TERM

# ── Helper: download a URL to a file (supports curl and wget) ──
download() {
    if command -v curl >/dev/null 2>&1; then
        curl -LsSf "$1" -o "$2"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$2" "$1"
    else
        echo "Error: neither curl nor wget found. Install one and re-run."
        exit 1
    fi
}

# ── Helper: check if a single package is available on the system ──
_is_pkg_installed() {
    case "$1" in
        build-essential) command -v gcc >/dev/null 2>&1 ;;
        libcurl4-openssl-dev)
            command -v dpkg >/dev/null 2>&1 && dpkg -s "$1" >/dev/null 2>&1 ;;
        pciutils)
            command -v lspci >/dev/null 2>&1 ;;
        *) command -v "$1" >/dev/null 2>&1 ;;
    esac
}

# ── Helper: human-readable apt distro label for the sudo package prompt (#6207) ──
# Reads /etc/os-release so the Accept? prompt can say which distro we detected and
# that packages come from that distro's official apt repos (not a tarball).
_apt_distro_description() {
    # Plain ( ... ) subshell — not $() — so case/;; stays bash-3.2-safe on macOS.
    # Bash 3.2 misparses case arms inside command substitution and errors on `;;`.
    (
        if [ ! -r /etc/os-release ]; then
            printf 'a debian-like system'
            exit 0
        fi
        # shellcheck disable=SC1091
        . /etc/os-release 2>/dev/null || true
        if [ -n "${NAME:-}" ] && [ -n "${VERSION_ID:-}" ]; then
            _ad_label="$NAME $VERSION_ID"
        elif [ -n "${PRETTY_NAME:-}" ]; then
            _ad_label="$PRETTY_NAME"
        elif [ -n "${NAME:-}" ]; then
            _ad_label="$NAME"
        else
            printf 'a debian-like system'
            exit 0
        fi
        case " ${ID:-} ${ID_LIKE:-} " in
            *" debian "*|*" ubuntu "*) _ad_label="${_ad_label} (debian-like)" ;;
        esac
        printf '%s' "$_ad_label"
    )
}

# ── Helper: can the controlling terminal actually be opened for reading? ──
# `test -r` only checks permission bits, which look fine in containers and
# systemd units where open() then fails with ENXIO. Probe with a real open.
# The subshell is required: in dash a failed redirection on the special
# builtin `:` exits the whole script.
_can_read_tty() {
    ( : </dev/tty ) >/dev/null 2>&1
}

# ── Helper: install packages via apt, escalating to sudo only if needed ──
# Usage: _smart_apt_install pkg1 pkg2 pkg3 ...
_smart_apt_install() {
    _PKGS="$*"

    # Step 1: Try installing without sudo (works when already root)
    apt-get update -y </dev/null >/dev/null 2>&1 || true
    apt-get install -y $_PKGS </dev/null >/dev/null 2>&1 || true

    # Step 2: Check which packages are still missing
    _STILL_MISSING=""
    for _pkg in $_PKGS; do
        if ! _is_pkg_installed "$_pkg"; then
            _STILL_MISSING="$_STILL_MISSING $_pkg"
        fi
    done
    _STILL_MISSING=$(echo "$_STILL_MISSING" | sed 's/^ *//')

    if [ -z "$_STILL_MISSING" ]; then
        return 0
    fi

    # In Tauri mode, report needed packages and exit — Rust handles elevation
    if [ "$TAURI_MODE" = true ]; then
        tauri_log "NEED_SUDO" "$_STILL_MISSING"
        exit 2
    fi

    # Step 3: Escalate -- need elevated permissions for remaining packages
    if command -v sudo >/dev/null 2>&1; then
        _ad_desc="$(_apt_distro_description)"
        echo ""
        echo "    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        echo "    WARNING: We require sudo elevated permissions to install:"
        echo "    $_STILL_MISSING"
        echo "    Detected ${_ad_desc}."
        echo "    If you accept, we'll run sudo apt-get to install these packages"
        echo "    from your distro's official repositories (not a third-party tarball)."
        echo "    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        echo ""
        if _can_read_tty; then
            printf "    Accept? [Y/n] "
            # The device opened, so a failed read is EOF, not consent: decline,
            # as the autostart prompt below does. Enter is still yes (a
            # successful read of an empty line).
            read -r REPLY </dev/tty || REPLY="n"
            case "$REPLY" in
                [nN]*)
                    echo ""
                    echo "    Please install these packages first, then re-run Unsloth Studio setup:"
                    echo "    sudo apt-get update -y && sudo apt-get install -y $_STILL_MISSING"
                    exit 1
                    ;;
            esac
            # Mirror the headless branch: on a sudoers denial, a wrong password
            # or an apt error, say what to run by hand instead of letting set -e
            # abort on a bare sudo/apt message.
            if sudo apt-get update -y </dev/null &&
                sudo apt-get install -y $_STILL_MISSING </dev/null; then
                :
            else
                echo ""
                echo "    Could not install these packages: $_STILL_MISSING"
                echo "    See the error above."
                echo "    Please install them first, then re-run Unsloth Studio setup:"
                echo "    sudo apt-get update -y && sudo apt-get install -y $_STILL_MISSING"
                exit 1
            fi
        else
            # Nobody can answer a prompt or type a password here. -n makes sudo
            # refuse rather than prompt into a closed stdin, which is how #7307
            # died. Probe with the real commands: `sudo -l` answers whether they
            # are *authorized*, not whether running them needs authentication.
            # -k ignores any cached timestamp, so only a real NOPASSWD rule gets
            # through, not someone's sudo in another shell minutes ago. Per
            # sudo(8), -k alongside a command ignores the cached credentials and
            # "will not update" them, so other sessions keep theirs.
            echo "    No terminal to confirm on; trying passwordless sudo."
            if sudo -n -k apt-get update -y </dev/null &&
                sudo -n -k apt-get install -y $_STILL_MISSING </dev/null; then
                echo "    Installed with passwordless sudo."
            else
                echo ""
                echo "    Could not install these packages: $_STILL_MISSING"
                echo "    Detected ${_ad_desc}."
                # Either sudo refused, or apt failed on a bad repo, dpkg lock or
                # network outage. sudo exits 1 on an auth/config problem and
                # when the command cannot be executed, but otherwise passes the
                # command's own status through, so state both causes.
                echo "    Either sudo needs a password here, or apt-get itself"
                echo "    failed; see the error above. With no terminal to"
                echo "    authenticate on, this cannot be done unattended."
                echo "    Please install them first, then re-run Unsloth Studio setup:"
                echo "    sudo apt-get update -y && sudo apt-get install -y $_STILL_MISSING"
                exit 1
            fi
        fi
    else
        echo ""
        echo "    sudo is not available on this system."
        echo "    Please install these packages as root, then re-run Unsloth Studio setup:"
        echo "    apt-get update -y && apt-get install -y $_STILL_MISSING"
        exit 1
    fi
}

# ── Helper: create desktop shortcuts and launcher script ──
# Usage: create_studio_shortcuts <unsloth_exe> <os>
# Creates ~/.local/share/unsloth/launch-studio.sh (shared launcher),
# plus platform-specific shortcuts (Linux .desktop / macOS .app bundle /
# WSL Windows Desktop+Start Menu .lnk).
create_studio_shortcuts() {
    _css_exe="$1"
    _css_os="$2"

    # Validate exe
    if [ ! -x "$_css_exe" ]; then
        echo "[WARN] Cannot create shortcuts: unsloth not found at $_css_exe"
        return 0
    fi

    # Resolve absolute path
    _css_exe_dir=$(cd "$(dirname "$_css_exe")" && pwd)
    _css_exe="$_css_exe_dir/$(basename "$_css_exe")"

    _css_data_dir="$DATA_DIR"
    _css_launcher="$_css_data_dir/launch-studio.sh"
    _css_icon_png="$_css_data_dir/unsloth-studio.png"
    _css_gem_png="$_css_data_dir/unsloth-gem.png"

    mkdir -p "$_css_data_dir"

    # Same-install discriminator: per-install opaque id written once at install
    # time and read by both this launcher and the backend (/api/health). Replaces
    # the older sha256(canonical $STUDIO_HOME) scheme to (a) avoid leaking the
    # install path on -H 0.0.0.0 deployments and (b) sidestep launcher/backend
    # canonicalization drift (cd -P vs Path.resolve() symlink/junction handling).
    # Lives at $STUDIO_HOME/share/ (not $DATA_DIR) so the backend can find it
    # via _STUDIO_ROOT_RESOLVED / "share" / "studio_install_id" regardless of
    # mode (in env-mode $STUDIO_HOME/share == $DATA_DIR; in default mode they
    # diverge but the backend only knows the studio_root). 32 bytes of urandom
    # -> 64 hex chars, byte-compatible with the prior digest so launcher
    # placeholder, _check_health, and tests stay length-agnostic.
    _css_id_dir="$STUDIO_HOME/share"
    mkdir -p "$_css_id_dir"
    _css_id_file="$_css_id_dir/studio_install_id"
    if [ ! -s "$_css_id_file" ]; then
        if [ -r /dev/urandom ]; then
            _css_new_id=$(od -An -N32 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')
        fi
        if [ -z "${_css_new_id:-}" ] && command -v python3 >/dev/null 2>&1; then
            _css_new_id=$(python3 -c 'import secrets; print(secrets.token_hex(32))' 2>/dev/null)
        fi
        if [ -z "${_css_new_id:-}" ]; then
            echo "[WARN] Cannot create launcher: no entropy source for studio_install_id" >&2
            return 1
        fi
        # Atomic write so a partial install can't leave a half-written id.
        _css_id_tmp="$_css_id_file.$$.tmp"
        printf '%s' "$_css_new_id" > "$_css_id_tmp" \
            && mv "$_css_id_tmp" "$_css_id_file"
        chmod 600 "$_css_id_file" 2>/dev/null || true
        unset _css_new_id _css_id_tmp
    fi
    _css_studio_root_id=$(cat "$_css_id_file" 2>/dev/null)
    if [ -z "$_css_studio_root_id" ]; then
        echo "[WARN] Cannot create launcher: failed to read $_css_id_file" >&2
        return 1
    fi
    _css_is_env_mode=false
    [ "$_STUDIO_HOME_REDIRECT" = "env" ] && _css_is_env_mode=true

    # ── Write launcher script ──
    # Single-quoted heredoc; @@DATA_DIR@@, @@STUDIO_ROOT_ID@@, and
    # @@INSTALLED_IS_ENV_MODE@@ are substituted via sed below.
    cat > "$_css_launcher" << 'LAUNCHER_EOF'
#!/usr/bin/env bash
# Unsloth Studio Launcher
# Auto-generated by install.sh -- do not edit manually.
set -euo pipefail

DATA_DIR='@@DATA_DIR@@'
_EXPECTED_STUDIO_ROOT_ID='@@STUDIO_ROOT_ID@@'
_INSTALLED_IS_ENV_MODE='@@INSTALLED_IS_ENV_MODE@@'

# Read exe path from config written at install time.
# Sourcing is safe: the config file is written by install.sh, not user input.
if [ -f "$DATA_DIR/studio.conf" ]; then
    . "$DATA_DIR/studio.conf"
fi
if [ -z "${UNSLOTH_EXE:-}" ] || [ ! -x "${UNSLOTH_EXE:-}" ]; then
    echo "Error: UNSLOTH_EXE not set or not executable. Re-run the installer." >&2
    exit 1
fi

BASE_PORT=8888
MAX_PORT_OFFSET=20
TIMEOUT_SEC=60
POLL_INTERVAL_SEC=0.25
LOG_FILE="$DATA_DIR/studio.log"
# why: in env-override mode multiple installs share an OS user; namespace the
# lock and remember our own healthy port so we never attach to an unrelated
# Unsloth listening on the global 8888..8908 range.
LOCK_DIR="${XDG_RUNTIME_DIR:-/tmp}/unsloth-studio-launcher-$(id -u).lock"
PORT_FILE=""
# why: gate on the install-time mode (baked above) instead of the runtime env
# var; sourcing a custom-root studio.conf in shell must not flip a default-mode
# launcher into env-mode behavior with stale state.
if [ "$_INSTALLED_IS_ENV_MODE" = "true" ]; then
    if command -v cksum >/dev/null 2>&1; then
        _LOCK_KEY=$(printf '%s' "$DATA_DIR" | cksum | awk '{print $1}')
    else
        _LOCK_KEY=""
    fi
    [ -n "$_LOCK_KEY" ] && LOCK_DIR="${XDG_RUNTIME_DIR:-/tmp}/unsloth-studio-launcher-$(id -u)-${_LOCK_KEY}.lock"
    PORT_FILE="$DATA_DIR/studio.port"
fi

# ── HTTP GET helper (supports curl and wget) ──
_http_get() {
    _url="$1"
    if command -v curl >/dev/null 2>&1; then
        curl -fsS --max-time 1 "$_url" 2>/dev/null
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- --timeout=1 "$_url" 2>/dev/null
    else
        return 1
    fi
}

# ── Health check ──
_check_health() {
    _port=$1
    _resp=$(_http_get "http://127.0.0.1:$_port/api/health") || return 1
    case "$_resp" in
        *'"status"'*'"healthy"'*'"service"'*'"Unsloth UI Backend"'*) ;;
        *'"service"'*'"Unsloth UI Backend"'*'"status"'*'"healthy"'*) ;;
        *) return 1 ;;
    esac
    # why: verify the backend belongs to THIS install. Baked hex digest avoids
    # JSON-escape mismatches on paths with `\`/`"` and avoids leaking the raw
    # install path to unauthenticated callers.
    if [ -n "$_EXPECTED_STUDIO_ROOT_ID" ]; then
        case "$_resp" in
            *"\"studio_root_id\":\"$_EXPECTED_STUDIO_ROOT_ID\""*|*"\"studio_root_id\": \"$_EXPECTED_STUDIO_ROOT_ID\""*) return 0 ;;
            *) return 1 ;;
        esac
    fi
    return 0
}

# ── Port scanning ──
_candidate_ports() {
    echo "$BASE_PORT"
    _max_port=$((BASE_PORT + MAX_PORT_OFFSET))
    if command -v ss >/dev/null 2>&1; then
        ss -tlnH 2>/dev/null | awk '{print $4}' | grep -oE '[0-9]+$' | \
            awk -v lo="$BASE_PORT" -v hi="$_max_port" '$1 >= lo && $1 <= hi && $1 != lo {print}' || true
    elif command -v lsof >/dev/null 2>&1; then
        lsof -iTCP -sTCP:LISTEN -nP 2>/dev/null | awk '{print $9}' | grep -oE '[0-9]+$' | \
            awk -v lo="$BASE_PORT" -v hi="$_max_port" '$1 >= lo && $1 <= hi && $1 != lo {print}' || true
    else
        _offset=1
        while [ "$_offset" -le "$MAX_PORT_OFFSET" ]; do
            echo $((BASE_PORT + _offset))
            _offset=$((_offset + 1))
        done
    fi
}

_find_healthy_port() {
    if [ -n "$PORT_FILE" ] && [ -f "$PORT_FILE" ]; then
        # why: env-mode installs only attach to a port we previously launched
        # ourselves; never to a sibling Unsloth that happens to be healthy.
        _p=$(cat "$PORT_FILE" 2>/dev/null || true)
        case "$_p" in
            ''|*[!0-9]*) ;;
            *)
                if _check_health "$_p"; then
                    echo "$_p"
                    return 0
                fi
                rm -f "$PORT_FILE"
                ;;
        esac
        return 1
    fi
    if [ -n "$PORT_FILE" ]; then
        return 1
    fi
    for _p in $(_candidate_ports | sort -un); do
        if _check_health "$_p"; then
            echo "$_p"
            return 0
        fi
    done
    return 1
}

# ── Check if a port is busy ──
_is_port_busy() {
    _port=$1
    if command -v ss >/dev/null 2>&1; then
        ss -tlnH 2>/dev/null | awk '{print $4}' | grep -qE "[.:]$_port$"
    elif command -v lsof >/dev/null 2>&1; then
        lsof -iTCP:"$_port" -sTCP:LISTEN -nP >/dev/null 2>&1
    else
        return 1
    fi
}

# ── Find a free port in range ──
_find_launch_port() {
    _offset=0
    while [ "$_offset" -le "$MAX_PORT_OFFSET" ]; do
        _candidate=$((BASE_PORT + _offset))
        if ! _is_port_busy "$_candidate"; then
            echo "$_candidate"
            return 0
        fi
        _offset=$((_offset + 1))
    done
    return 1
}

# ── Open browser ──
_open_browser() {
    _url="$1"
    if [ "$(uname)" = "Darwin" ] && command -v open >/dev/null 2>&1; then
        open "$_url"
    elif grep -qi microsoft /proc/version 2>/dev/null; then
        # WSL: xdg-open is unreliable; use Windows browser via PowerShell or cmd
        if command -v powershell.exe >/dev/null 2>&1; then
            powershell.exe -NoProfile -Command "Start-Process '$_url'" >/dev/null 2>&1 &
        elif command -v cmd.exe >/dev/null 2>&1; then
            cmd.exe /c start "" "$_url" >/dev/null 2>&1 &
        elif command -v xdg-open >/dev/null 2>&1; then
            xdg-open "$_url" >/dev/null 2>&1 &
        else
            echo "Open in your browser: $_url" >&2
        fi
    elif command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$_url" >/dev/null 2>&1 &
    else
        echo "Open in your browser: $_url" >&2
    fi
}

# ── Spawn terminal with studio command ──
_spawn_terminal() {
    _cmd="$1"
    _os=$(uname)
    if [ "$_os" = "Darwin" ]; then
        # AppleEvents are TCC-denied from unsigned .app bundles; spawn
        # Terminal via a .command file + Launch Services instead. Server
        # is nohup'd so warm relaunches hit the fast-path; watcher + trap
        # in the .command couple Terminal close <-> server shutdown.
        # `exec` keeps the recorded PID equal to the studio process so
        # signals reach studio directly rather than a wrapper shell.
        nohup sh -c "exec $_cmd" >> "$LOG_FILE" 2>&1 &
        _server_pid=$!
        _pid_file="$DATA_DIR/studio-$_launch_port.pid"
        printf '%d\n' "$_server_pid" > "$_pid_file" 2>/dev/null || true

        _cmd_file="$DATA_DIR/launch-terminal.command"
        _logfile_q=$(printf '%s' "$LOG_FILE" | sed "s/'/'\\\\''/g")
        _pidfile_q=$(printf '%s' "$_pid_file" | sed "s/'/'\\\\''/g")
        if {
            {
                printf '#!/bin/bash\n'
                printf "SERVER_PID=%s\n" "$_server_pid"
                printf "PID_FILE='%s'\n" "$_pidfile_q"
                # Wait up to 12s for graceful shutdown before SIGKILL.
                printf 'shutdown_studio() {\n'
                printf '  kill -TERM "$SERVER_PID" 2>/dev/null\n'
                printf '  _i=0\n'
                printf '  while kill -0 "$SERVER_PID" 2>/dev/null && [ "$_i" -lt 24 ]; do\n'
                printf '    sleep 0.5\n'
                printf '    _i=$((_i + 1))\n'
                printf '  done\n'
                printf '  kill -0 "$SERVER_PID" 2>/dev/null && kill -KILL "$SERVER_PID" 2>/dev/null\n'
                printf '  rm -f "$PID_FILE" 2>/dev/null\n'
                printf '}\n'
                printf "tail -n 100 -F '%s' &\n" "$_logfile_q"
                printf 'TAIL_PID=$!\n'
                # Server gone -> kill tail so bash exits cleanly.
                printf '(\n'
                printf '  while kill -0 "$SERVER_PID" 2>/dev/null; do sleep 1; done\n'
                printf '  kill "$TAIL_PID" 2>/dev/null\n'
                printf ') &\n'
                printf 'WATCHER_PID=$!\n'
                printf "trap 'shutdown_studio; kill \"\$WATCHER_PID\" \"\$TAIL_PID\" 2>/dev/null; exit' HUP INT TERM\n"
                printf "trap 'rm -f \"\$PID_FILE\" 2>/dev/null' EXIT\n"
                printf 'wait "$TAIL_PID" 2>/dev/null\n'
            } > "$_cmd_file" 2>/dev/null \
                && chmod +x "$_cmd_file" 2>/dev/null \
                && open -a Terminal "$_cmd_file" 2>/dev/null
        }; then
            # Foreground Terminal (Launch Services spawns us backgrounded).
            osascript -e 'tell application "Terminal" to activate' >/dev/null 2>&1 || true
            return 0
        fi
        # .command/open failed: kill orphan, fall through to generic fallback.
        kill -TERM "$_server_pid" 2>/dev/null || true
        _i=0
        while kill -0 "$_server_pid" 2>/dev/null && [ "$_i" -lt 6 ]; do
            sleep 0.5
            _i=$((_i + 1))
        done
        kill -0 "$_server_pid" 2>/dev/null && kill -KILL "$_server_pid" 2>/dev/null || true
        rm -f "$_pid_file" 2>/dev/null || true
        echo "[WARN] Could not open Terminal; falling back to background launch" >&2
    else
        for _term in gnome-terminal konsole xfce4-terminal mate-terminal lxterminal xterm; do
            if command -v "$_term" >/dev/null 2>&1; then
                case "$_term" in
                    gnome-terminal) "$_term" -- sh -c "$_cmd" & return 0 ;;
                    konsole)        "$_term" -e sh -c "$_cmd" & return 0 ;;
                    xterm)          "$_term" -e sh -c "$_cmd" & return 0 ;;
                    *)              "$_term" -e sh -c "$_cmd" & return 0 ;;
                esac
            fi
        done
    fi
    # Fallback: background with log
    echo "No terminal emulator found; running in background. Logs: $LOG_FILE" >&2
    nohup sh -c "$_cmd" >> "$LOG_FILE" 2>&1 &
    return 0
}

# ── Atomic directory-based single-instance guard ──
_acquire_lock() {
    if mkdir "$LOCK_DIR" 2>/dev/null; then
        echo "$$" > "$LOCK_DIR/pid"
        return 0
    fi

    # Lock dir exists -- check if owner is still alive
    _old_pid=$(cat "$LOCK_DIR/pid" 2>/dev/null || true)
    if [ -n "$_old_pid" ] && kill -0 "$_old_pid" 2>/dev/null; then
        # Another launcher is running; wait for it to bring Unsloth up
        _deadline=$(($(date +%s) + TIMEOUT_SEC))
        while [ "$(date +%s)" -lt "$_deadline" ]; do
            _port=$(_find_healthy_port) && {
                _open_browser "http://localhost:$_port"
                exit 0
            }
            sleep "$POLL_INTERVAL_SEC"
        done
        echo "Timed out waiting for other launcher (PID $_old_pid)" >&2
        exit 0
    fi

    # Stale lock -- reclaim
    rm -rf "$LOCK_DIR"
    mkdir "$LOCK_DIR" 2>/dev/null || return 1
    echo "$$" > "$LOCK_DIR/pid"
}

_release_lock() {
    [ -d "$LOCK_DIR" ] || return 0
    [ "$(cat "$LOCK_DIR/pid" 2>/dev/null)" = "$$" ] || return 0
    rm -rf "$LOCK_DIR"
}

# ── Main ──
# Fast path: already healthy
_port=$(_find_healthy_port) && {
    _open_browser "http://localhost:$_port"
    exit 0
}

_acquire_lock
trap '_release_lock' EXIT INT TERM

# Post-lock re-check (handles race with another launcher)
_port=$(_find_healthy_port) && {
    _open_browser "http://localhost:$_port"
    exit 0
}

# Find a free port in range
_launch_port=$(_find_launch_port) || {
    echo "No free port found in range ${BASE_PORT}-$((BASE_PORT + MAX_PORT_OFFSET))" >&2
    exit 1
}

if [ -t 1 ]; then
    # ── Foreground mode (TTY available) ──
    # Background subshell: wait for studio to become healthy, release the
    # single-instance lock, then open the browser. The lock stays held until
    # health is confirmed so a second launcher cannot race during startup.
    (
        _obwr_deadline=$(($(date +%s) + TIMEOUT_SEC))
        while [ "$(date +%s)" -lt "$_obwr_deadline" ]; do
            if _check_health "$_launch_port"; then
                [ -n "$PORT_FILE" ] && printf '%s\n' "$_launch_port" > "$PORT_FILE" 2>/dev/null || true
                _release_lock
                _open_browser "http://localhost:$_launch_port"
                exit 0
            fi
            sleep "$POLL_INTERVAL_SEC"
        done
        # Timed out -- release the lock anyway so future launches are not blocked
        _release_lock
    ) &
    # Clear traps so exec does not trigger _release_lock (the subshell owns it)
    trap - EXIT INT TERM
    exec "$UNSLOTH_EXE" studio -p "$_launch_port"
else
    # ── Background mode (no TTY) ──
    # Used by macOS .app and headless invocations.
    _launch_cmd=$(printf '%q ' "$UNSLOTH_EXE" studio -p "$_launch_port")
    _launch_cmd=${_launch_cmd% }
    _spawn_terminal "$_launch_cmd"

    # Poll for health on the specific port we launched on
    _deadline=$(($(date +%s) + TIMEOUT_SEC))
    while [ "$(date +%s)" -lt "$_deadline" ]; do
        if _check_health "$_launch_port"; then
            [ -n "$PORT_FILE" ] && printf '%s\n' "$_launch_port" > "$PORT_FILE" 2>/dev/null || true
            _open_browser "http://localhost:$_launch_port"
            exit 0
        fi
        sleep "$POLL_INTERVAL_SEC"
    done

    echo "Unsloth Studio did not become healthy within ${TIMEOUT_SEC}s." >&2
    echo "Check logs at: $LOG_FILE" >&2
    exit 1
fi
LAUNCHER_EOF

    # why: bake non-user-controlled placeholders FIRST so a literal
    # `@@STUDIO_ROOT_ID@@` inside $DATA_DIR cannot be rewritten below.
    sed -e "s|@@STUDIO_ROOT_ID@@|$_css_studio_root_id|g" \
        -e "s|@@INSTALLED_IS_ENV_MODE@@|$_css_is_env_mode|g" \
        "$_css_launcher" > "$_css_launcher.tmp" \
        && mv "$_css_launcher.tmp" "$_css_launcher"

    # Env-mode bakes an absolute DATA_DIR (root fixed at install time);
    # default / HOME-redirect keeps the literal $HOME/.local/share/unsloth
    # so behavior is byte-identical to pre-override.
    if [ "$_STUDIO_HOME_REDIRECT" = "env" ]; then
        # Two-stage escape: (1) `'` -> `'\''` for shell single-quote embedding,
        # (2) backslash/&/| escape so the value survives the s|...|VALUE| sed
        # below. Verified end-to-end with apostrophes, spaces, &, |, $.
        _sq_escaped=$(printf '%s' "$DATA_DIR" | sed "s/'/'\\\\''/g")
        _sed_safe=$(printf '%s' "$_sq_escaped" | sed 's/[\\&|]/\\&/g')
        sed "s|@@DATA_DIR@@|$_sed_safe|g" "$_css_launcher" > "$_css_launcher.tmp" \
            && mv "$_css_launcher.tmp" "$_css_launcher"
    else
        sed "s|DATA_DIR='@@DATA_DIR@@'|DATA_DIR=\"\$HOME/.local/share/unsloth\"|" \
            "$_css_launcher" > "$_css_launcher.tmp" \
            && mv "$_css_launcher.tmp" "$_css_launcher"
    fi

    chmod +x "$_css_launcher"

    # studio.conf: exe path + (env-mode only) persisted env vars so fresh
    # shells launch the right install without re-exporting.
    _css_quoted_exe=$(printf '%s' "$_css_exe" | sed "s/'/'\\\\''/g")
    {
        printf '%s\n' "UNSLOTH_EXE='$_css_quoted_exe'"
        if [ "$_STUDIO_HOME_REDIRECT" = "env" ]; then
            # When an override resolves to the legacy default, llama.cpp
            # still lives at ~/.unsloth/llama.cpp (one shared build).
            # Canonicalize the legacy side so a symlinked $HOME doesn't
            # break the comparison.
            _css_legacy_studio="$HOME/.unsloth/studio"
            if [ -d "$_css_legacy_studio" ]; then
                _css_legacy_studio=$(CDPATH= cd -P -- "$_css_legacy_studio" 2>/dev/null && pwd -P) \
                    || _css_legacy_studio="$HOME/.unsloth/studio"
            fi
            if [ "$STUDIO_HOME" = "$_css_legacy_studio" ]; then
                _css_llama_path="$HOME/.unsloth/llama.cpp"
            else
                _css_llama_path="$STUDIO_HOME/llama.cpp"
            fi
            _css_quoted_home=$(printf '%s' "$STUDIO_HOME" | sed "s/'/'\\\\''/g")
            _css_quoted_llama=$(printf '%s' "$_css_llama_path" | sed "s/'/'\\\\''/g")
            printf '%s\n' "export UNSLOTH_STUDIO_HOME='$_css_quoted_home'"
            # UNSLOTH_LLAMA_CPP_PATH is a pre-existing user-controlled
            # llama.cpp dir override; only default it if unset.
            printf '%s\n' 'if [ -z "${UNSLOTH_LLAMA_CPP_PATH:-}" ]; then'
            printf '%s\n' "    export UNSLOTH_LLAMA_CPP_PATH='$_css_quoted_llama'"
            printf '%s\n' 'fi'
        fi
    } > "$_css_data_dir/studio.conf"

    # ── Icon: try bundled, then download ──
    # rounded-512.png used for both Linux and macOS icons
    _css_script_dir=""
    if [ -n "${0:-}" ] && [ -f "$0" ]; then
        _css_script_dir=$(cd "$(dirname "$0")" 2>/dev/null && pwd) || true
    fi

    # Try to find rounded-512.png from installed package (site-packages) or local repo
    _css_found_icon=""
    _css_venv_dir=$(dirname "$(dirname "$_css_exe")")
    # Check site-packages
    for _sp in "$_css_venv_dir"/lib/python*/site-packages/unsloth/studio/frontend/public; do
        if [ -f "$_sp/rounded-512.png" ]; then
            _css_found_icon="$_sp/rounded-512.png"
        fi
    done
    # Check local repo (when running from clone)
    if [ -z "$_css_found_icon" ] && [ -n "$_css_script_dir" ] && [ -f "$_css_script_dir/studio/frontend/public/rounded-512.png" ]; then
        _css_found_icon="$_css_script_dir/studio/frontend/public/rounded-512.png"
    fi

    # Copy or download rounded-512.png (used for both Linux icon and macOS icns)
    if [ -n "$_css_found_icon" ]; then
        cp "$_css_found_icon" "$_css_icon_png" 2>/dev/null || true
        cp "$_css_found_icon" "$_css_gem_png" 2>/dev/null || true
    else
        download "https://raw.githubusercontent.com/unslothai/unsloth/main/studio/frontend/public/rounded-512.png" "$_css_icon_png" 2>/dev/null || true
        cp "$_css_icon_png" "$_css_gem_png" 2>/dev/null || true
    fi

    # Validate PNG header (first 4 bytes: \x89PNG)
    _css_validate_png() {
        [ -f "$1" ] || return 1
        _hdr=$(od -An -tx1 -N4 "$1" 2>/dev/null | tr -d ' ')
        [ "$_hdr" = "89504e47" ]
    }
    if [ -f "$_css_icon_png" ] && ! _css_validate_png "$_css_icon_png"; then
        rm -f "$_css_icon_png"
    fi
    if [ -f "$_css_gem_png" ] && ! _css_validate_png "$_css_gem_png"; then
        rm -f "$_css_gem_png"
    fi

    # ── Platform-specific shortcuts ──
    # Env-mode installs are workspace-scoped: skip persistent desktop /
    # Start-Menu / dock launchers that may point at a deleted workspace.
    # Runtime launcher + studio.conf + icon are still written above.
    if [ "$_STUDIO_HOME_REDIRECT" = "env" ]; then
        substep "wrote launcher at $_css_launcher (persistent shortcuts skipped in env-override mode)"
        return 0
    fi

    _css_created=0

    if [ "$_css_os" = "linux" ]; then
        # ── Linux: .desktop file ──
        _css_app_dir="$HOME/.local/share/applications"
        mkdir -p "$_css_app_dir"

        _css_desktop="$_css_app_dir/unsloth-studio.desktop"
        # Escape backslashes and double-quotes for .desktop Exec= field
        _css_exec_escaped=$(printf '%s' "$_css_launcher" | sed 's/\\/\\\\/g; s/"/\\"/g')
        _css_icon_escaped=$(printf '%s' "$_css_icon_png" | sed 's/\\/\\\\/g; s/"/\\"/g')
        cat > "$_css_desktop" << DESKTOP_EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Unsloth Studio
Comment=Launch Unsloth Studio
Exec="$_css_exec_escaped"
Icon=$_css_icon_escaped
Terminal=true
StartupNotify=true
Categories=Development;Science;
DESKTOP_EOF
        chmod +x "$_css_desktop"

        # Copy to ~/Desktop if it exists
        if [ -d "$HOME/Desktop" ]; then
            cp "$_css_desktop" "$HOME/Desktop/unsloth-studio.desktop" 2>/dev/null || true
            chmod +x "$HOME/Desktop/unsloth-studio.desktop" 2>/dev/null || true
            # Mark as trusted so GNOME/Nautilus allows launching via double-click
            if command -v gio >/dev/null 2>&1; then
                gio set "$HOME/Desktop/unsloth-studio.desktop" metadata::trusted true 2>/dev/null || true
            fi
        fi

        # Best-effort update database
        update-desktop-database "$_css_app_dir" 2>/dev/null || true
        _css_created=1

    elif [ "$_css_os" = "macos" ]; then
        # ── macOS: .app bundle ──
        _css_app="$HOME/Applications/Unsloth Studio.app"
        _css_contents="$_css_app/Contents"
        _css_macos_dir="$_css_contents/MacOS"
        _css_res_dir="$_css_contents/Resources"
        # Recreate bundle if root or any subpath is a symlink (mkdir -p follows them).
        if [ -L "$_css_app" ] || [ -L "$_css_contents" ] \
            || [ -L "$_css_macos_dir" ] || [ -L "$_css_res_dir" ]; then
            rm -rf "$_css_app" 2>/dev/null || {
                echo "[ERROR] $_css_app contains a symlinked bundle path; remove manually and re-run install" >&2
                return 1
            }
        elif [ -e "$_css_app" ] && [ ! -d "$_css_app" ]; then
            echo "[ERROR] $_css_app exists but is not a directory; remove manually and re-run install" >&2
            return 1
        fi
        mkdir -p "$_css_macos_dir" "$_css_res_dir"

        # Info.plist
        cat > "$_css_contents/Info.plist" << 'PLIST_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>ai.unsloth.studio</string>
    <key>CFBundleName</key>
    <string>Unsloth Studio</string>
    <key>CFBundleDisplayName</key>
    <string>Unsloth Studio</string>
    <key>CFBundleExecutable</key>
    <string>launch-studio</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>10.15</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST_EOF

        # Executable stub: same single-quoted-heredoc + sed-substitute
        # pattern as launch-studio.sh so $-vars in $_css_data_dir don't
        # expand at .app launch time.
        _css_sq_dir=$(printf '%s' "$_css_data_dir" | sed "s/'/'\\\\''/g")
        _css_sed_dir=$(printf '%s' "$_css_sq_dir" | sed 's/[\\&|]/\\&/g')
        cat > "$_css_macos_dir/launch-studio" << 'STUB_EOF'
#!/bin/sh
exec '@@DATA_DIR@@/launch-studio.sh' "$@"
STUB_EOF
        sed "s|@@DATA_DIR@@|$_css_sed_dir|g" "$_css_macos_dir/launch-studio" \
            > "$_css_macos_dir/launch-studio.tmp" \
            && mv "$_css_macos_dir/launch-studio.tmp" "$_css_macos_dir/launch-studio"
        chmod +x "$_css_macos_dir/launch-studio"

        # Build AppIcon.icns from unsloth-gem.png (2240x2240)
        if [ -f "$_css_gem_png" ] && command -v sips >/dev/null 2>&1 && command -v iconutil >/dev/null 2>&1; then
            _css_tmpdir=$(mktemp -d 2>/dev/null)
            if [ -d "$_css_tmpdir" ]; then
                _css_iconset="$_css_tmpdir/AppIcon.iconset"
                mkdir -p "$_css_iconset"
                _css_icon_ok=true
                for _sz in 16 32 128 256 512; do
                    _sz2=$((_sz * 2))
                    sips -z "$_sz" "$_sz" "$_css_gem_png" --out "$_css_iconset/icon_${_sz}x${_sz}.png" >/dev/null 2>&1 || _css_icon_ok=false
                    sips -z "$_sz2" "$_sz2" "$_css_gem_png" --out "$_css_iconset/icon_${_sz}x${_sz}@2x.png" >/dev/null 2>&1 || _css_icon_ok=false
                done
                if [ "$_css_icon_ok" = "true" ]; then
                    iconutil -c icns "$_css_iconset" -o "$_css_res_dir/AppIcon.icns" 2>/dev/null || true
                fi
                rm -rf "$_css_tmpdir"
            fi
        fi
        # Fallback: copy PNG as icon
        if [ ! -f "$_css_res_dir/AppIcon.icns" ] && [ -f "$_css_icon_png" ]; then
            cp "$