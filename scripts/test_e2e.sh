#!/usr/bin/env bash
set -euo pipefail

# End-to-end tests for MLX Launcher interposer + backend
# Tests direct WebServer and interposer paths

BACKEND_PORT="${BACKEND_PORT:-8421}"
INTERPOSER_PORT="${INTERPOSER_PORT:-8900}"
PASS=0
FAIL=0

red()   { printf '\033[1;31m%s\033[0m\n' "$*"; }
green() { printf '\033[1;32m%s\033[0m\n' "$*"; }
bold()  { printf '\033[1m%s\033[0m\n' "$*"; }

assert_ok() {
  local name="$1" status="$2" body="$3"
  if [ "$status" -ge 200 ] && [ "$status" -lt 300 ]; then
    green "  PASS: $name (HTTP $status)"
    PASS=$((PASS + 1))
  else
    red "  FAIL: $name (HTTP $status)"
    echo "    Body: ${body:0:300}"
    FAIL=$((FAIL + 1))
  fi
}

assert_fail() {
  local name="$1" status="$2" body="$3" expected_status="${4:-400}"
  if [ "$status" -eq "$expected_status" ]; then
    green "  PASS: $name (expected HTTP $status)"
    PASS=$((PASS + 1))
  else
    red "  FAIL: $name (expected HTTP $expected_status, got $status)"
    echo "    Body: ${body:0:300}"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local name="$1" body="$2" needle="$3"
  if echo "$body" | grep -q "$needle"; then
    green "  PASS: $name (contains '$needle')"
    PASS=$((PASS + 1))
  else
    red "  FAIL: $name (missing '$needle')"
    echo "    Body: ${body:0:300}"
    FAIL=$((FAIL + 1))
  fi
}

do_request() {
  local port="$1" path="$2" data="$3"
  local tmpfile=$(mktemp)
  local status
  status=$(curl -s -o "$tmpfile" -w '%{http_code}' \
    -X POST "http://127.0.0.1:${port}${path}" \
    -H "Content-Type: application/json" \
    -d "$data" 2>/dev/null) || status=000
  local body
  body=$(cat "$tmpfile" 2>/dev/null || echo "")
  rm -f "$tmpfile"
  echo "$status"
  echo "$body"
}

# ===== Check services are running =====
bold "=== Checking services ==="

HEALTH_STATUS=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${BACKEND_PORT}/health" 2>/dev/null || echo "000")
if [ "$HEALTH_STATUS" = "200" ]; then
  green "  Backend (port $BACKEND_PORT): UP"
else
  red "  Backend (port $BACKEND_PORT): DOWN (HTTP $HEALTH_STATUS)"
  echo "  Start MLXLauncher and load a model first."
  exit 1
fi

INTERPOSER_STATUS=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${INTERPOSER_PORT}/health" 2>/dev/null || echo "000")
if [ "$INTERPOSER_STATUS" = "200" ]; then
  green "  Interposer (port $INTERPOSER_PORT): UP"
else
  red "  Interposer (port $INTERPOSER_PORT): DOWN (HTTP $INTERPOSER_STATUS)"
  echo "  Warning: Interposer tests will be skipped."
fi

# ===== Direct Backend Tests =====
bold ""
bold "=== Direct Backend Tests (port $BACKEND_PORT) ==="

# Test 1: GET /v1/models
bold "  Test: GET /v1/models"
RESULT=$(curl -s -w '\n%{http_code}' "http://127.0.0.1:${BACKEND_PORT}/v1/models" 2>/dev/null)
STATUS=$(echo "$RESULT" | tail -1)
BODY=$(echo "$RESULT" | sed '$d')
assert_ok "GET /v1/models" "$STATUS" "$BODY"
assert_contains "models list has data" "$BODY" '"data"'

# Test 2: Simple chat completion (non-streaming) - string content
bold "  Test: Simple chat completion (string content)"
read -r STATUS BODY <<< $(do_request "$BACKEND_PORT" "/v1/chat/completions" '{
  "model": "test",
  "stream": false,
  "max_tokens": 32,
  "messages": [
    {"role": "system", "content": "You are helpful."},
    {"role": "user", "content": "Say hello in one word."}
  ]
}' | { read s; read b; echo "$s $b"; })
assert_ok "chat completion string content" "$STATUS" "$BODY"

# Test 3: Chat completion with content array format
bold "  Test: Chat completion (array content)"
read -r STATUS BODY <<< $(do_request "$BACKEND_PORT" "/v1/chat/completions" '{
  "model": "test",
  "stream": false,
  "max_tokens": 32,
  "messages": [
    {"role": "system", "content": "You are helpful."},
    {"role": "user", "content": [{"type": "text", "text": "Say hello in one word."}]}
  ]
}' | { read s; read b; echo "$s $b"; })
assert_ok "chat completion array content" "$STATUS" "$BODY"

# Test 4: Chat completion with null content (edge case)
bold "  Test: Chat completion (null content in user msg)"
read -r STATUS BODY <<< $(do_request "$BACKEND_PORT" "/v1/chat/completions" '{
  "model": "test",
  "stream": false,
  "max_tokens": 32,
  "messages": [
    {"role": "user", "content": null},
    {"role": "user", "content": "Say hello."}
  ]
}' | { read s; read b; echo "$s $b"; })
assert_ok "chat completion null content" "$STATUS" "$BODY"

# Test 5: Streaming chat completion
bold "  Test: Streaming chat completion"
STREAM_RESULT=$(curl -s -w '\n%{http_code}' \
  -X POST "http://127.0.0.1:${BACKEND_PORT}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
  "model": "test",
  "stream": true,
  "max_tokens": 32,
  "messages": [
    {"role": "user", "content": "Say hi."}
  ]
}' 2>/dev/null)
STREAM_STATUS=$(echo "$STREAM_RESULT" | tail -1)
STREAM_BODY=$(echo "$STREAM_RESULT" | sed '$d')
assert_ok "streaming chat completion" "$STREAM_STATUS" "$STREAM_BODY"
assert_contains "streaming has data: prefix" "$STREAM_BODY" 'data:'

# ===== Interposer Tests =====
if [ "$INTERPOSER_STATUS" = "200" ]; then
  bold ""
  bold "=== Interposer Tests (port $INTERPOSER_PORT) ==="

  # Test 6: OpenAI Chat Completions through interposer
  bold "  Test: OpenAI chat/completions through interposer"
  read -r STATUS BODY <<< $(do_request "$INTERPOSER_PORT" "/v1/chat/completions" '{
    "model": "test",
    "stream": false,
    "max_tokens": 32,
    "messages": [
      {"role": "system", "content": "You are helpful."},
      {"role": "user", "content": "Say hello in one word."}
    ]
  }' | { read s; read b; echo "$s $b"; })
  assert_ok "interposer chat/completions" "$STATUS" "$BODY"

  # Test 7: Anthropic Messages API through interposer
  bold "  Test: Anthropic /v1/messages through interposer"
  RESULT=$(curl -s -w '\n%{http_code}' \
    -X POST "http://127.0.0.1:${INTERPOSER_PORT}/v1/messages" \
    -H "Content-Type: application/json" \
    -H "x-api-key: test-key" \
    -H "anthropic-version: 2023-06-01" \
    -d '{
    "model": "test",
    "max_tokens": 32,
    "stream": false,
    "messages": [
      {"role": "user", "content": "Say hello in one word."}
    ]
  }' 2>/dev/null)
  STATUS=$(echo "$RESULT" | tail -1)
  BODY=$(echo "$RESULT" | sed '$d')
  assert_ok "interposer Anthropic messages" "$STATUS" "$BODY"

  # Test 8: Anthropic Messages with system prompt
  bold "  Test: Anthropic /v1/messages with system prompt"
  RESULT=$(curl -s -w '\n%{http_code}' \
    -X POST "http://127.0.0.1:${INTERPOSER_PORT}/v1/messages" \
    -H "Content-Type: application/json" \
    -H "x-api-key: test-key" \
    -H "anthropic-version: 2023-06-01" \
    -d '{
    "model": "test",
    "max_tokens": 32,
    "stream": false,
    "system": "You are helpful.",
    "messages": [
      {"role": "user", "content": "Say hello in one word."}
    ]
  }' 2>/dev/null)
  STATUS=$(echo "$RESULT" | tail -1)
  BODY=$(echo "$RESULT" | sed '$d')
  assert_ok "interposer Anthropic with system" "$STATUS" "$BODY"

  # Test 9: Anthropic Messages with content blocks array
  bold "  Test: Anthropic /v1/messages with content blocks"
  RESULT=$(curl -s -w '\n%{http_code}' \
    -X POST "http://127.0.0.1:${INTERPOSER_PORT}/v1/messages" \
    -H "Content-Type: application/json" \
    -H "x-api-key: test-key" \
    -H "anthropic-version: 2023-06-01" \
    -d '{
    "model": "test",
    "max_tokens": 32,
    "stream": false,
    "messages": [
      {"role": "user", "content": [{"type": "text", "text": "Say hello in one word."}]}
    ]
  }' 2>/dev/null)
  STATUS=$(echo "$RESULT" | tail -1)
  BODY=$(echo "$RESULT" | sed '$d')
  assert_ok "interposer Anthropic content blocks" "$STATUS" "$BODY"

  # Test 10: Streaming through interposer (Anthropic format)
  bold "  Test: Streaming Anthropic through interposer"
  STREAM_RESULT=$(curl -s -w '\n%{http_code}' \
    -X POST "http://127.0.0.1:${INTERPOSER_PORT}/v1/messages" \
    -H "Content-Type: application/json" \
    -H "x-api-key: test-key" \
    -H "anthropic-version: 2023-06-01" \
    -d '{
    "model": "test",
    "max_tokens": 32,
    "stream": true,
    "messages": [
      {"role": "user", "content": "Say hi."}
    ]
  }' 2>/dev/null)
  STREAM_STATUS=$(echo "$STREAM_RESULT" | tail -1)
  STREAM_BODY=$(echo "$STREAM_RESULT" | sed '$d')
  assert_ok "interposer Anthropic streaming" "$STREAM_STATUS" "$STREAM_BODY"

  # Test 11: Streaming through interposer (OpenAI chat completions)
  bold "  Test: Streaming OpenAI chat/completions through interposer"
  STREAM_RESULT=$(curl -s -w '\n%{http_code}' \
    -X POST "http://127.0.0.1:${INTERPOSER_PORT}/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d '{
    "model": "test",
    "stream": true,
    "max_tokens": 32,
    "messages": [
      {"role": "user", "content": "Say hi."}
    ]
  }' 2>/dev/null)
  STREAM_STATUS=$(echo "$STREAM_RESULT" | tail -1)
  STREAM_BODY=$(echo "$STREAM_RESULT" | sed '$d')
  assert_ok "interposer OpenAI streaming" "$STREAM_STATUS" "$STREAM_BODY"

  # Test 12: Gemini format through interposer
  bold "  Test: Gemini generateContent through interposer"
  RESULT=$(curl -s -w '\n%{http_code}' \
    -X POST "http://127.0.0.1:${INTERPOSER_PORT}/v1/models/test:generateContent" \
    -H "Content-Type: application/json" \
    -d '{
    "contents": [
      {"role": "user", "parts": [{"text": "Say hello in one word."}]}
    ],
    "generationConfig": {"maxOutputTokens": 32}
  }' 2>/dev/null)
  STATUS=$(echo "$RESULT" | tail -1)
  BODY=$(echo "$RESULT" | sed '$d')
  assert_ok "interposer Gemini generateContent" "$STATUS" "$BODY"

fi

# ===== Summary =====
bold ""
bold "=== Results ==="
green "Passed: $PASS"
if [ "$FAIL" -gt 0 ]; then
  red "Failed: $FAIL"
  exit 1
else
  green "All tests passed!"
fi
