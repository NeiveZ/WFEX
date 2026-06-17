#!/usr/bin/env bash
# WFEX - Web Fuzzer & Enumerator eXtended
# Author: NeiveZ | github.com/NeiveZ/WFEX

set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────
R="\e[0m"; BOLD="\e[1m"
RD="\e[91m"; GR="\e[92m"; YL="\e[93m"; BL="\e[94m"; DG="\e[90m"

# ── Wordlist directory ────────────────────────────────────────────
# Looks in: ~/.config/webrecon/wordlists/
# Can be overridden with WEBRECON_WORDLIST_DIR env var
WL_DIR="${WEBRECON_WORDLIST_DIR:-${HOME}/.config/webrecon/wordlists}"

# ── Defaults ──────────────────────────────────────────────────────
URL=""
WORDLIST=""
OUTPUT=""
THREADS=20
TIMEOUT=8
DELAY=0
SILENT=false
ONLY_DIRS=false
ONLY_FILES=false
FOLLOW_REDIRECT=false
EXTENSIONS="php,html,js,txt,bak,old,zip,json,xml,sql,env"
INTERESTING="bak,old,zip,env,sql,log,conf,key,pem"
UA_FILE=""
CODES="200,204,301,302,403,500"
COUNTER_FILE=""

# ── Built-in User-Agents ──────────────────────────────────────────
BUILTIN_UAS=(
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0.0.0 Safari/537.36"
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/119.0.0.0 Safari/537.36"
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:121.0) Gecko/20100101 Firefox/121.0"
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 13_5) AppleWebKit/605.1.15 Version/17.0 Safari/605.1.15"
    "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:120.0) Gecko/20100101 Firefox/120.0"
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Edg/120.0.2210.61 Safari/537.36"
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148 Safari/604.1"
    "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 Chrome/120.0.0.0 Mobile Safari/537.36"
    "Googlebot/2.1 (+http://www.google.com/bot.html)"
    "curl/7.88.1"
)

# ── Built-in fallback wordlist (used when no -w is passed) ───────
BUILTIN_WORDLIST=(
    admin login panel dashboard upload uploads files backup backups tmp temp
    old test dev staging api assets static public private secure auth user
    users account config data logs .git .env wp-admin wp-login.php phpinfo.php
    robots.txt sitemap.xml .htaccess web.config index install setup update
    reset register logout profile settings core system lib vendor src app
    docs support marketing reports monitor status
)

# ================================================================
#  WORDLIST RESOLUTION
# ================================================================

# Resolves -w value in this priority order:
#   1. Exact file path (absolute or relative)  → use directly
#   2. Short name (e.g. "common")              → look in WL_DIR/common.txt
#   3. Empty                                   → use built-in fallback
resolve_wordlist() {
    local input="$1"

    # Exact path
    if [[ -f "$input" ]]; then
        echo "$input"
        return
    fi

    # Short name → search in WL_DIR
    # Tries exact match first, then appends .txt
    if [[ -d "$WL_DIR" ]]; then
        if [[ -f "${WL_DIR}/${input}" ]]; then
            echo "${WL_DIR}/${input}"
            return
        fi
        if [[ -f "${WL_DIR}/${input}.txt" ]]; then
            echo "${WL_DIR}/${input}.txt"
            return
        fi
    fi

    echo ""  # not found
}

list_wordlists() {
    echo -e "${BOLD}Wordlist directory:${R} ${WL_DIR}"
    echo

    if [[ ! -d "$WL_DIR" ]]; then
        echo -e "${DG}  No wordlists installed. Run:${R}"
        echo -e "  mkdir -p \"${WL_DIR}\""
        echo -e "  cp your_wordlist.txt \"${WL_DIR}/\""
        echo
        echo -e "${DG}  Common sources:${R}"
        echo -e "  /usr/share/wordlists/dirb/common.txt"
        echo -e "  /usr/share/seclists/Discovery/Web-Content/common.txt"
        echo -e "  https://github.com/danielmiessler/SecLists"
        exit 0
    fi

    local count=0
    while IFS= read -r -d '' f; do
        local name lines
        name=$(basename "$f")
        lines=$(wc -l < "$f" 2>/dev/null || echo "?")
        printf "  %-30s %s lines\n" "$name" "$lines"
        count=$((count + 1))
    done < <(find "$WL_DIR" -maxdepth 2 -type f \( -name "*.txt" -o -name "*.lst" \) -print0 | sort -z)

    [[ $count -eq 0 ]] && echo -e "  ${DG}(no .txt or .lst files found)${R}"
    echo
    echo -e "${DG}Usage:  -w common   or   -w /full/path/to/file.txt${R}"
    exit 0
}

install_wordlist() {
    local src="$1"
    local dst_name="${2:-$(basename "$src")}"

    [[ ! -f "$src" ]] && { echo -e "${RD}[!]${R} File not found: $src"; exit 1; }

    mkdir -p "$WL_DIR"
    cp "$src" "${WL_DIR}/${dst_name}"
    local lines; lines=$(wc -l < "${WL_DIR}/${dst_name}")
    echo -e "${GR}[+]${R} Installed: ${WL_DIR}/${dst_name}  (${lines} lines)"
    exit 0
}

# ================================================================
#  HELP
# ================================================================

usage() {
cat << HELP
${BOLD}Usage:${R}
  $0 -u <URL> [options]

${BOLD}WFEX - Web Fuzzer & Enumerator eXtended${R}

${BOLD}Options:${R}
  -u, --url             Target URL (required)
  -w, --wordlist        Wordlist: name, path, or use --list-wordlists
  -o, --output          Save results to file
  -t, --threads         Parallel requests (default: 20)
  -T, --timeout         Request timeout in seconds (default: 8)
  -d, --delay           Delay between requests in ms (default: 0)
  -e, --extensions      Extensions, comma-separated (default: php,html,...)
  -c, --codes           HTTP codes of interest (default: 200,204,301,302,403,500)
  -a, --agents          Custom User-Agent file (default: built-in)
  --dirs-only           Test directories only
  --files-only          Test files only
  --follow              Follow redirects (301/302)
  --silent              Silent mode (results only)
  --list-wordlists      Show available wordlists
  --install-wordlist    Install a wordlist: --install-wordlist /path/file.txt [name]
  -h, --help            Show this help

${BOLD}Wordlist examples:${R}
  $0 -u https://target.com                        # built-in fallback
  $0 -u https://target.com -w common             # ~/.config/webrecon/wordlists/common.txt
  $0 -u https://target.com -w recon              # ~/.config/webrecon/wordlists/recon.txt
  $0 -u https://target.com -w /path/to/list.txt  # full path
  $0 --list-wordlists                             # show all available
  $0 --install-wordlist /usr/share/wordlists/dirb/common.txt

${BOLD}More examples:${R}
  $0 -u https://target.com -t 50 -e php,asp,aspx --silent
  $0 -u https://target.com --dirs-only -c 200,301,403 -o results.txt
HELP
exit 0
}

# ================================================================
#  CORE FUNCTIONS
# ================================================================

get_ua() {
    if [[ -n "$UA_FILE" && -f "$UA_FILE" ]]; then
        mapfile -t ua_array < "$UA_FILE"
    else
        ua_array=("${BUILTIN_UAS[@]}")
    fi
    echo "${ua_array[RANDOM % ${#ua_array[@]}]}"
}

get_wordlist() {
    if [[ -n "$WORDLIST" && -f "$WORDLIST" ]]; then
        cat "$WORDLIST"
    else
        printf '%s\n' "${BUILTIN_WORDLIST[@]}"
    fi
}

codes_to_regex() {
    echo "$1" | tr ',' '|' | sed 's/^/^(/;s/$/)$/'
}

detect_cloud() {
    local h="$1"
    local cloud="none" waf=""
    echo "$h" | grep -qiE "x-amz|cloudfront|awselb"    && cloud="AWS"
    echo "$h" | grep -qiE "x-azure-ref|windows-azure"   && cloud="Azure"
    echo "$h" | grep -qiE "x-cloud-trace|gws"           && cloud="GCP"
    echo "$h" | grep -qiE "^cf-ray:|cloudflare"         && waf="Cloudflare"
    echo "$h" | grep -qiE "akamai|x-akamai"             && waf="Akamai"
    echo "$h" | grep -qiE "x-sucuri|sucuri"             && waf="Sucuri"
    echo "$h" | grep -qiE "x-fastly|fastly"             && waf="Fastly"
    [[ -n "$waf" ]] && echo "${cloud}+WAF:${waf}" || echo "$cloud"
}

detect_server() {
    echo "$1" | grep -i "^server:" | cut -d: -f2- | tr -d '\r' | xargs
}

inc_counter() {
    local key="$1"
    flock -x 8
    local val
    val=$(grep "^${key}=" "$COUNTER_FILE" 2>/dev/null | cut -d= -f2 || echo 0)
    val=$((val + 1))
    grep -v "^${key}=" "$COUNTER_FILE" > "${COUNTER_FILE}.tmp" 2>/dev/null || true
    echo "${key}=${val}" >> "${COUNTER_FILE}.tmp"
    mv "${COUNTER_FILE}.tmp" "$COUNTER_FILE"
    flock -u 8
}

do_request() {
    local url="$1"
    local ua; ua=$(get_ua)
    local flags=(-s -o /dev/null -w "%{http_code}" --max-time "$TIMEOUT")
    $FOLLOW_REDIRECT && flags+=(-L)
    [[ $DELAY -gt 0 ]] && sleep "$(echo "scale=3; $DELAY/1000" | bc)"
    curl "${flags[@]}" -H "User-Agent: $ua" "$url" 2>/dev/null || echo "000"
}

test_dir() {
    local word="$1"
    local target="${URL}/${word}/"
    local code; code=$(do_request "$target")

    echo "$code" | grep -qE "$CODES_REGEX" || return

    local color="$GR"
    [[ "$code" == "403" ]] && color="$YL"
    [[ "$code" == "500" ]] && color="$RD"
    [[ "$code" == 3*   ]] && color="$BL"

    if $SILENT; then
        echo "$target [$code]"
    else
        printf "${BOLD}${color}[DIR]${R} %s ${DG}[%s]${R}\n" "$target" "$code"
    fi

    [[ -n "$OUTPUT" ]] && echo "[DIR] $target [$code]" >> "$OUTPUT"
    inc_counter "dirs"
}

test_file() {
    local word="$1" ext="$2"
    local target="${URL}/${word}.${ext}"
    local code; code=$(do_request "$target")

    echo "$code" | grep -qE "$CODES_REGEX" || return

    local sensitive=false
    IFS=',' read -ra ilist <<< "$INTERESTING"
    for i in "${ilist[@]}"; do [[ "$ext" == "$i" ]] && sensitive=true && break; done

    local color="$GR"; $sensitive && color="$RD"
    [[ "$code" == "403" ]] && color="$YL"
    [[ "$code" == 3*   ]] && color="$BL"

    local label="FILE"; $sensitive && label="SENSITIVE"

    if $SILENT; then
        echo "$target [$code]"
    else
        printf "${BOLD}${color}[%s]${R} %s ${DG}[%s]${R}\n" "$label" "$target" "$code"
    fi

    [[ -n "$OUTPUT" ]] && echo "[$label] $target [$code]" >> "$OUTPUT"
    $sensitive && inc_counter "interesting" || inc_counter "files"
}

run_parallel() {
    local -a jobs=()

    while IFS= read -r word; do
        [[ -z "$word" || "$word" == \#* ]] && continue

        if ! $ONLY_FILES; then
            test_dir "$word" &
            jobs+=($!)
        fi

        if ! $ONLY_DIRS; then
            IFS=',' read -ra exts <<< "$EXTENSIONS"
            for ext in "${exts[@]}"; do
                test_file "$word" "$ext" &
                jobs+=($!)

                while [[ ${#jobs[@]} -ge $THREADS ]]; do
                    local alive=()
                    for pid in "${jobs[@]}"; do
                        kill -0 "$pid" 2>/dev/null && alive+=("$pid")
                    done
                    jobs=("${alive[@]}")
                    [[ ${#jobs[@]} -ge $THREADS ]] && sleep 0.05
                done
            done
        fi

    done < <(get_wordlist)

    for pid in "${jobs[@]}"; do wait "$pid" 2>/dev/null || true; done
}

# ================================================================
#  ARGUMENT PARSING
# ================================================================

[[ $# -eq 0 ]] && usage

while [[ $# -gt 0 ]]; do
    case "$1" in
        -u|--url)             URL="$2";                     shift 2 ;;
        -w|--wordlist)        WORDLIST="$2";                shift 2 ;;
        -o|--output)          OUTPUT="$2";                  shift 2 ;;
        -t|--threads)         THREADS="$2";                 shift 2 ;;
        -T|--timeout)         TIMEOUT="$2";                 shift 2 ;;
        -d|--delay)           DELAY="$2";                   shift 2 ;;
        -e|--extensions)      EXTENSIONS="$2";              shift 2 ;;
        -c|--codes)           CODES="$2";                   shift 2 ;;
        -a|--agents)          UA_FILE="$2";                 shift 2 ;;
        --dirs-only)          ONLY_DIRS=true;               shift ;;
        --files-only)         ONLY_FILES=true;              shift ;;
        --follow)             FOLLOW_REDIRECT=true;         shift ;;
        --silent)             SILENT=true;                  shift ;;
        --list-wordlists)     list_wordlists ;;
        --install-wordlist)   install_wordlist "$2" "${3:-}"; shift 2 ;;
        -h|--help)            usage ;;
        *) echo -e "${RD}[!]${R} Unknown option: $1"; usage ;;
    esac
done

# ── Validations ───────────────────────────────────────────────────

[[ -z "$URL" ]] && { echo -e "${RD}[!]${R} -u is required"; exit 1; }
[[ "$URL" != http://* && "$URL" != https://* ]] && URL="https://${URL}"
URL="${URL%/}"

for dep in curl flock bc; do
    command -v "$dep" &>/dev/null || { echo -e "${RD}[!]${R} missing dependency: $dep"; exit 1; }
done

# ── Resolve wordlist ──────────────────────────────────────────────

if [[ -n "$WORDLIST" ]]; then
    resolved=$(resolve_wordlist "$WORDLIST")
    if [[ -z "$resolved" ]]; then
        echo -e "${RD}[!]${R} Wordlist not found: \"${WORDLIST}\""
        echo -e "${DG}    Run --list-wordlists to see available options${R}"
        exit 1
    fi
    WORDLIST="$resolved"
fi

CODES_REGEX=$(codes_to_regex "$CODES")

# ── Prepare output file ───────────────────────────────────────────

if [[ -n "$OUTPUT" ]]; then
    printf "# WFEX | %s | %s\n\n" "$URL" "$(date '+%Y-%m-%d %H:%M:%S')" > "$OUTPUT"
fi

# ── Thread-safe counters ──────────────────────────────────────────

COUNTER_FILE=$(mktemp)
printf "dirs=0\nfiles=0\ninteresting=0\n" > "$COUNTER_FILE"
exec 8>"${COUNTER_FILE}.lock"

# ── Initial request (headers reused for cloud/server detection) ───

START_TIME=$(date +%s)
INIT_HEADERS=$(curl -sI --max-time "$TIMEOUT" "$URL" 2>/dev/null || true)
CLOUD=$(detect_cloud "$INIT_HEADERS")
SERVER=$(detect_server "$INIT_HEADERS")
INIT_CODE=$(echo "$INIT_HEADERS" | head -1 | awk '{print $2}')
WL_SOURCE="${WORDLIST:-built-in}"
WL_COUNT=$(get_wordlist | grep -c '[^[:space:]]' 2>/dev/null || echo "${#BUILTIN_WORDLIST[@]}")

# ── Run header ────────────────────────────────────────────────────

if ! $SILENT; then
    echo -e "${BOLD}${URL}${R}  ${DG}[${INIT_CODE:-?}]${R}  server:${SERVER:-?}  cloud:${CLOUD}"
    echo -e "${DG}wfex${R} | wordlist:$(basename "$WL_SOURCE")  words:${WL_COUNT}  threads:${THREADS}"
    echo
fi

# ================================================================
#  RUN
# ================================================================

run_parallel
wait

FOUND_DIRS=$(grep        "^dirs="        "$COUNTER_FILE" | cut -d= -f2)
FOUND_FILES=$(grep       "^files="       "$COUNTER_FILE" | cut -d= -f2)
FOUND_INTERESTING=$(grep "^interesting=" "$COUNTER_FILE" | cut -d= -f2)
rm -f "$COUNTER_FILE" "${COUNTER_FILE}.lock" "${COUNTER_FILE}.tmp" 2>/dev/null || true

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

# ── Summary ───────────────────────────────────────────────────────

if ! $SILENT; then
    echo
    echo -e "${DG}dirs:${R} ${FOUND_DIRS}  ${DG}files:${R} ${FOUND_FILES}  ${DG}sensitive:${R} ${FOUND_INTERESTING}  ${DG}time:${R} ${ELAPSED}s"
    [[ -n "$OUTPUT" ]] && echo -e "${DG}saved:${R} ${OUTPUT}"
fi

if [[ -n "$OUTPUT" ]]; then
    printf "\n# dirs: %s  files: %s  sensitive: %s  time: %ss\n" \
        "$FOUND_DIRS" "$FOUND_FILES" "$FOUND_INTERESTING" "$ELAPSED" >> "$OUTPUT"
fi
