#!/data/data/com.termux/files/usr/bin/bash
# CapStash Miner - Run Script
# Reads config from ~/capstash/config.json, starts daemon, waits for sync, starts mining

set -e

INSTALL_DIR="$HOME/capstash"
DATA_DIR="$INSTALL_DIR/data"
BIN_DIR="$INSTALL_DIR/bin"
CONFIG_JSON="$INSTALL_DIR/config.json"

CLI="$BIN_DIR/CapStash-cli -datadir=$DATA_DIR"
DAEMON="$BIN_DIR/CapStashd -datadir=$DATA_DIR"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

trim() {
    local var="$1"
    var="${var#"${var%%[![:space:]]*}"}"
    var="${var%"${var##*[![:space:]]}"}"
    printf '%s' "$var"
}

json_get_string() {
    local key="$1"
    local file="$2"
    grep -o "\"$key\":[[:space:]]*\"[^\"]*\"" "$file" | head -n1 | sed "s/.*\"$key\":[[:space:]]*\"\([^\"]*\)\".*/\1/"
}

json_get_number() {
    local key="$1"
    local file="$2"
    grep -o "\"$key\":[[:space:]]*[-0-9][0-9]*" "$file" | head -n1 | sed "s/.*\"$key\":[[:space:]]*//"
}

echo -e "${CYAN}CapStash Miner${NC}"
echo "  Install dir: $INSTALL_DIR"
echo "  Config file: $CONFIG_JSON"
echo ""

# ---------- load config.json ----------

if [ ! -f "$CONFIG_JSON" ]; then
    echo -e "${RED}Error: config.json not found at $CONFIG_JSON${NC}"
    exit 1
fi

MINING_ADDR="$(json_get_string "wallet_address" "$CONFIG_JSON")"
THREADS="$(json_get_number "threads" "$CONFIG_JSON")"
COINBASE_TAG="$(json_get_string "coinbase_tag" "$CONFIG_JSON")"
TARGET="$(json_get_string "target" "$CONFIG_JSON")"

MINING_ADDR="$(trim "$MINING_ADDR")"
THREADS="$(trim "$THREADS")"
COINBASE_TAG="$(trim "$COINBASE_TAG")"
TARGET="$(trim "$TARGET")"

# defaults / validation
[ -z "$COINBASE_TAG" ] && COINBASE_TAG="CellSwarm"
[ -z "$TARGET" ] && TARGET="auto"
[ -z "$THREADS" ] && THREADS="-1"

echo -e "${CYAN}DEBUG: Raw config.json:${NC}"
cat "$CONFIG_JSON"
echo ""
echo -e "${CYAN}DEBUG: Parsed wallet_address:${NC} '$MINING_ADDR'"
echo -e "${CYAN}DEBUG: Parsed threads:${NC} '$THREADS'"
echo -e "${CYAN}DEBUG: Parsed coinbase_tag:${NC} '$COINBASE_TAG'"
echo -e "${CYAN}DEBUG: Parsed target:${NC} '$TARGET'"
echo ""

if [ -z "$MINING_ADDR" ]; then
    echo -e "${RED}wallet_address is empty in config.json${NC}"
    exit 1
fi

case "$THREADS" in
    ''|*[!0-9-]*)
        echo -e "${RED}Invalid threads value in config.json: '$THREADS'${NC}"
        exit 1
        ;;
esac

echo "  Address: $MINING_ADDR"
echo "  Target:  $TARGET"
echo "  Threads: $THREADS"
echo ""

# ---------- start daemon if not running ----------

if ! $CLI getblockchaininfo >/dev/null 2>&1; then
    echo -e "${YELLOW}Starting daemon...${NC}"
    $DAEMON -daemon

    echo "Waiting for RPC..."
    for i in $(seq 1 60); do
        if $CLI getblockchaininfo >/dev/null 2>&1; then
            echo -e "${GREEN}Daemon started.${NC}"
            break
        fi
        sleep 2
    done

    if ! $CLI getblockchaininfo >/dev/null 2>&1; then
        echo -e "${RED}Error: Daemon failed to start. Check logs in $DATA_DIR/debug.log${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}Daemon already running.${NC}"
fi

# ---------- wait for sync ----------

while true; do
    INFO="$($CLI getblockchaininfo 2>/dev/null || true)"

    if [ -z "$INFO" ]; then
        echo -ne "\rWaiting for blockchain info...   "
        sleep 5
        continue
    fi

    IBD="$(echo "$INFO" | grep initialblockdownload | grep -c true || true)"
    if [ "$IBD" = "0" ]; then
        echo ""
        echo -e "${GREEN}Chain synced!${NC}"
        break
    fi

    BLOCKS="$(echo "$INFO" | grep '"blocks"' | tr -dc '0-9')"
    HEADERS="$(echo "$INFO" | grep '"headers"' | tr -dc '0-9')"

    if [ -n "$HEADERS" ] && [ "$HEADERS" -gt 0 ] 2>/dev/null; then
        PCT=$((BLOCKS * 100 / HEADERS))
        echo -ne "\rSyncing: $BLOCKS / $HEADERS blocks ($PCT%)   "
    else
        echo -ne "\rSyncing blockchain...   "
    fi

    sleep 10
done

# ---------- start mining ----------

echo ""
echo -e "${CYAN}Starting miner...${NC}"
RESULT="$($CLI setgenerate true "$THREADS" "$MINING_ADDR" "$COINBASE_TAG" 2>&1 || true)"
echo "$RESULT"

# ---------- show status ----------

echo ""
bash "$INSTALL_DIR/status.sh" 2>/dev/null || true
echo ""
echo -e "${GREEN}Miner is running in the background.${NC}"
echo "  Check status: bash ~/capstash/status.sh"
echo "  Stop:         bash ~/capstash/stop.sh"
