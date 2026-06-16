# WFEX

> Web Fuzzer & Enumerator eXtended — directory and file fuzzer for pentest and bug bounty, written in Bash.

![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat-square&logo=gnu-bash&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-Linux%20%7C%20Kali-557C94?style=flat-square&logo=kalilinux&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-blue?style=flat-square)
![Status](https://img.shields.io/badge/Status-Active-brightgreen?style=flat-square)

---

## Overview

WFEX performs **directory and file enumeration** against a target URL, combining parallel HTTP requests, automatic cloud/WAF detection, built-in User-Agent rotation, and a managed wordlist system — all in a single portable Bash script with no external dependencies beyond `curl`.

Designed for authorized penetration tests and bug bounty recon workflows.

---

## Features

- **Parallel requests** — configurable thread pool (default: 20), significantly faster than sequential scanning
- **Cloud & WAF detection** — identifies AWS, Azure, GCP, Cloudflare, Akamai, Sucuri, Fastly from response headers with no extra request
- **User-Agent rotation** — randomizes UA per request from a built-in pool or a custom file
- **Managed wordlist system** — install, name, and select wordlists from `~/.config/wfex/wordlists/` by short name
- **Sensitive file flagging** — highlights `.bak`, `.env`, `.sql`, `.key` and similar extensions separately
- **HTTP code filtering** — configurable list of response codes to report
- **Output to file** — saves results with timestamped header and final summary
- **Silent mode** — outputs found URLs only, suitable for piping into other tools
- **Zero external dependencies** — only requires `curl`, `flock`, and `bc`

---

## Requirements

| Dependency | Purpose | Install |
|---|---|---|
| `bash 4.0+` | Script runtime | Pre-installed on Linux |
| `curl` | HTTP requests | `apt install curl` |
| `flock` | Thread-safe counters | `apt install util-linux` |
| `bc` | Delay calculation | `apt install bc` |

```bash
sudo apt install curl util-linux bc
```

---

## Installation

### 1. Clone the repository

```bash
git clone https://github.com/NeiveZ/WFEX.git
cd WFEX
```

### 2. Make the script executable

```bash
chmod +x wfex.sh
```

### 3. (Optional) Install globally

```bash
sudo cp wfex.sh /usr/local/bin/wfex
```

### 4. (Optional) Install a wordlist

WFEX includes a built-in fallback wordlist. For broader coverage:

```bash
# From the repo's own wordlist
./wfex.sh --install-wordlist wordlist_recon.txt recon

# From Kali built-in
./wfex.sh --install-wordlist /usr/share/wordlists/dirb/common.txt common

# From SecLists
./wfex.sh --install-wordlist /usr/share/seclists/Discovery/Web-Content/common.txt common
```

---

## Wordlist Management

Wordlists are stored in `~/.config/wfex/wordlists/` and referenced by short name — no need to type full paths every run.

### List installed wordlists

```bash
./wfex.sh --list-wordlists
```

```
Wordlist directory: /home/user/.config/wfex/wordlists

  common.txt     4614 lines
  recon.txt       320 lines
  big.txt       20469 lines

Usage:  -w common   or   -w /full/path/to/file.txt
```

### Install a wordlist

```bash
./wfex.sh --install-wordlist /usr/share/wordlists/dirb/common.txt common
./wfex.sh --install-wordlist ~/my-wordlist.txt custom
```

### Use by short name

```bash
./wfex.sh -u https://target.com -w common
./wfex.sh -u https://target.com -w recon
```

### Use by full path

```bash
./wfex.sh -u https://target.com -w /usr/share/wordlists/dirb/big.txt
```

### Override the wordlist directory

```bash
export WFEX_WORDLIST_DIR=/opt/shared-wordlists
./wfex.sh --list-wordlists
```

**Recommended sources:**
- [SecLists](https://github.com/danielmiessler/SecLists) — `Discovery/Web-Content/`
- Kali built-in: `/usr/share/wordlists/dirb/`
- `wordlist_recon.txt` — included in this repository

---

## Usage

```
./wfex.sh -u <URL> [options]

Options:
  -u, --url             Target URL (required)
  -w, --wordlist        Wordlist name or full path (default: built-in)
  -o, --output          Save results to file
  -t, --threads         Parallel requests (default: 20)
  -T, --timeout         Request timeout in seconds (default: 8)
  -d, --delay           Delay between requests in ms (default: 0)
  -e, --extensions      Extensions, comma-separated (default: php,html,js,txt,bak,old,zip,json,xml,sql,env)
  -c, --codes           HTTP codes to report (default: 200,204,301,302,403,500)
  -a, --agents          Custom User-Agent file
  --dirs-only           Directories only
  --files-only          Files only
  --follow              Follow redirects (301/302)
  --silent              Found URLs only — no header or summary
  --list-wordlists      Show available wordlists
  --install-wordlist    Install a wordlist file
  -h, --help            Show this help
```

---

## Examples

**Quickstart:**
```bash
./wfex.sh -u https://target.com
```

**Named wordlist, save results:**
```bash
./wfex.sh -u https://target.com -w common -o results.txt
```

**High-speed scan (50 threads):**
```bash
./wfex.sh -u https://target.com -w common -t 50
```

**Directories only, filter by status code:**
```bash
./wfex.sh -u https://target.com --dirs-only -c 200,301,403
```

**ASP.NET target with custom extensions:**
```bash
./wfex.sh -u https://target.com -e asp,aspx,config,bak -w common
```

**Silent mode — pipe into other tools:**
```bash
./wfex.sh -u https://target.com --silent | tee findings.txt
./wfex.sh -u https://target.com --silent | grep SENSITIVE
```

**Low-noise scan with delay:**
```bash
./wfex.sh -u https://target.com -d 300 -t 5
```

**Follow redirects, files only:**
```bash
./wfex.sh -u https://target.com --files-only --follow -w recon
```

---

## Output

```
https://target.com  [200]  server:nginx  cloud:Cloudflare+WAF
wfex | wordlist:common  words:4614  threads:20

[DIR]       https://target.com/admin/ [301]
[DIR]       https://target.com/uploads/ [200]
[SENSITIVE] https://target.com/.env [200]
[SENSITIVE] https://target.com/backup.sql [200]
[FILE]      https://target.com/index.php [200]

dirs: 2  files: 1  sensitive: 2  time: 34s
```

| Label | Description |
|---|---|
| `[DIR]` | Directory found |
| `[FILE]` | File found (standard extension) |
| `[SENSITIVE]` | File with sensitive extension (`.bak`, `.env`, `.sql`, `.key`, `.pem`, etc.) |

| Color | Condition |
|---|---|
| Green | 200, 204 |
| Blue | 3xx redirect |
| Yellow | 403 Forbidden |
| Red | 500 or sensitive file |

---

## Repository Structure

```
WFEX/
├── wfex.sh              # Main script
├── wordlist_recon.txt   # Bundled recon wordlist
└── user_agents.txt      # Optional User-Agent list (use with -a)
```

---

## Legal

For use only on systems you own or have explicit written authorization to test.
Unauthorized use against third-party systems is illegal.
