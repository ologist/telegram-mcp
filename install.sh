#!/usr/bin/env bash
# telegram-mcp — Claude Desktop 플러그인 설치 스크립트 (Docker)
# 사용법: ./install.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_CONFIG="$HOME/Library/Application Support/Claude/claude_desktop_config.json"
PLIST_ID="com.telegram-mcp"
PLIST_PATH="$HOME/Library/LaunchAgents/${PLIST_ID}.plist"
MCP_URL="http://localhost:8001/mcp"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " telegram-mcp Installer (Docker)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── 0. 필수 확인 ────────────────────────────────────────────
echo ""
echo "🔍 필수 환경 확인 중..."

if ! command -v docker &>/dev/null; then
  echo "❌ Docker가 설치되어 있지 않습니다."
  exit 1
fi
echo "   ✓ Docker"

if [ ! -f "$SCRIPT_DIR/.env" ]; then
  echo ""
  echo "⚠️  .env 파일이 없습니다."
  echo "   cp $SCRIPT_DIR/.env.example $SCRIPT_DIR/.env"
  echo "   # TELEGRAM_API_ID, TELEGRAM_API_HASH, TELEGRAM_SESSION_STRING 설정 후 재실행"
  echo ""
  echo "   세션 문자열 생성이 필요하면:"
  echo "   cd $SCRIPT_DIR && uv run session_string_generator.py"
  exit 1
fi
echo "   ✓ .env"

# ── 1. Docker 이미지 빌드 ────────────────────────────────────
echo ""
echo "🐳 Docker 이미지 빌드 중..."
cd "$SCRIPT_DIR"
docker compose build --no-cache -q
echo "   → 빌드 완료"

# ── 2. LaunchAgent 등록 (로그인 시 자동 시작) ────────────────
echo ""
echo "⚙️  LaunchAgent 등록 중..."

DOCKER_PATH="$(command -v docker)"

if launchctl list "$PLIST_ID" &>/dev/null 2>&1; then
  launchctl unload "$PLIST_PATH" 2>/dev/null || true
fi

cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${PLIST_ID}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${DOCKER_PATH}</string>
    <string>compose</string>
    <string>-f</string>
    <string>${SCRIPT_DIR}/docker-compose.yml</string>
    <string>up</string>
    <string>--remove-orphans</string>
  </array>
  <key>WorkingDirectory</key>
  <string>${SCRIPT_DIR}</string>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <false/>
  <key>StandardOutPath</key>
  <string>/tmp/telegram-mcp.log</string>
  <key>StandardErrorPath</key>
  <string>/tmp/telegram-mcp.err</string>
</dict>
</plist>
EOF

launchctl load "$PLIST_PATH"
echo "   → $PLIST_PATH (로그인 시 자동 시작 등록)"

# ── 3. 컨테이너 즉시 시작 ────────────────────────────────────
echo ""
echo "🚀 컨테이너 시작 중..."
cd "$SCRIPT_DIR"
docker compose up -d
echo "   → 실행 중 (http://localhost:8001/mcp)"

# 헬스체크 (최대 20초 대기 — Telegram 연결 시간 고려)
echo "   헬스체크 중 (최대 20초)..."
for i in $(seq 1 20); do
  if curl -s -o /dev/null -X POST "$MCP_URL" \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"healthcheck","version":"1.0"}}}' 2>/dev/null; then
    echo "   ✓ 서버 응답 확인 (${i}초)"
    break
  fi
  if [ "$i" -eq 20 ]; then
    echo "   ⚠️  응답 없음 — 컨테이너 로그를 확인하세요:"
    echo "      docker compose -f $SCRIPT_DIR/docker-compose.yml logs"
  fi
  sleep 1
done

# ── 4. Claude Desktop MCP 등록 ──────────────────────────────
echo ""
echo "🖥️  Claude Desktop MCP 등록 중..."

python3 - <<PYEOF
import json

path = "$CLAUDE_CONFIG"
try:
    with open(path) as f:
        data = json.load(f)
except FileNotFoundError:
    data = {}

servers = data.setdefault("mcpServers", {})
servers["telegram-mcp"] = {
    "command": "npx",
    "args": ["-y", "mcp-remote", "$MCP_URL"]
}

with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")

print(f"   → {path}")
print(f"   → mcpServers.telegram-mcp 등록 완료")
PYEOF

# ── 완료 ────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ 설치 완료!"
echo ""
echo "   MCP 서버: $MCP_URL"
echo "   로그:     /tmp/telegram-mcp.log"
echo "            docker compose -f $SCRIPT_DIR/docker-compose.yml logs -f"
echo ""
echo "   Claude Desktop을 재시작하면 telegram-mcp가 활성화됩니다."
echo ""
echo "   ── 관리 명령어 ─────────────────────────"
echo "   시작:  docker compose -f $SCRIPT_DIR/docker-compose.yml up -d"
echo "   중지:  docker compose -f $SCRIPT_DIR/docker-compose.yml down"
echo "   로그:  docker compose -f $SCRIPT_DIR/docker-compose.yml logs -f"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
