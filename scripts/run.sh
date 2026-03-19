#!/data/data/com.termux/files/usr/bin/bash
# CapStash Miner - Run Script
# Starts daemon (if not running), waits for sync, starts mining
set -e

INSTALL_DIR="$HOME/capstash"
DATA_DIR="$INSTALL_DIR/data"
BIN_DIR="$INSTALL_DIR/bin"
CLI="$BIN_DIR/CapStash-cli -datadir=$DATA_DIR"
DAEMON="$BIN_DIR/CapStashd -datadir=$DATA_DIR"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Load config
if [ ! -f "$INSTALL_DIR/miner.conf" ]; then
    echo "Error: Not installed. Run install.sh first."
    exit 1
fi
source "$INSTALL_DIR/miner.conf"

echo -e "${CYAN}CapStash Miner${NC}"
echo "  Address: $MINING_ADDR"
echo "  Target:  $TARGET"
echo ""

# Start daemon if not running
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
        echo "Error: Daemon failed to start. Check logs in $DATA_DIR/debug.log"
        exit 1
    fi
else
    echo -e "${GREEN}Daemon already running.${NC}"
fi

# Wait for sync
while true; do
    INFO=$($CLI getblockchaininfo 2>/dev/null)
    IBD=$(echo "$INFO" | grep initialblockdownload | grep -c true)
    if [ "$IBD" = "0" ]; then
        echo -e "${GREEN}Chain synced!${NC}"
        break
    fi
    BLOCKS=$(echo "$INFO" | grep '"blocks"' | tr -dc '0-9')
    HEADERS=$(echo "$INFO" | grep '"headers"' | tr -dc '0-9')
    if [ -n "$HEADERS" ] && [ "$HEADERS" -gt 0 ] 2>/dev/null; then
        PCT=$((BLOCKS * 100 / HEADERS))
        echo -ne "\rSyncing: $BLOCKS / $HEADERS blocks ($PCT%)   "
    fi
    sleep 10
done

# Start mining
echo ""
echo -e "${CYAN}Starting miner...${NC}"
RESULT=$($CLI setgenerate true $THREADS "$MINING_ADDR" "$COINBASE_TAG" 2>&1)
echo "$RESULT"

# Show status
echo ""
bash "$INSTALL_DIR/status.sh" 2>/dev/null || true
echo ""
echo -e "${GREEN}Miner is running in the background.${NC}"
echo "  Check status: bash ~/capstash/status.sh"
echo "  Stop:         bash ~/capstash/stop.sh"
