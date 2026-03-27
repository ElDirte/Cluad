#!/usr/bin/env bash
# cleanup-claude.sh
# Removes all traces of Claude Code from this system so a fresh install can proceed.
# Run this AFTER closing any active Claude Code session.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info()    { echo -e "${YELLOW}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[DONE]${NC} $*"; }
warn()    { echo -e "${RED}[WARN]${NC} $*"; }

echo "========================================"
echo "  Claude Code Cleanup Script"
echo "========================================"
echo ""

# ── 1. npm global package ──────────────────────────────────────────────────────
info "Removing npm global package @anthropic-ai/claude-code..."
if npm uninstall -g @anthropic-ai/claude-code 2>/dev/null; then
    success "npm package removed."
else
    warn "npm uninstall failed or package not found — attempting manual removal."
    rm -rf /opt/node22/lib/node_modules/@anthropic-ai/claude-code 2>/dev/null || true
    success "Manual removal of npm package directory done."
fi

# ── 2. Binary symlink ──────────────────────────────────────────────────────────
info "Removing claude binary symlink at /opt/node22/bin/claude..."
rm -f /opt/node22/bin/claude 2>/dev/null || true
success "Binary symlink removed."

# ── 3. Main installation directory ────────────────────────────────────────────
info "Removing main installation directory /opt/claude-code/..."
rm -rf /opt/claude-code 2>/dev/null || true
success "Installation directory removed."

# ── 4. User config directories ────────────────────────────────────────────────
info "Removing Claude config directories..."
rm -rf /root/.claude 2>/dev/null || true
rm -rf "$HOME/.claude" 2>/dev/null || true
success "Config directories removed."

# ── 5. Config JSON file and cache directory ───────────────────────────────────
info "Removing /root/.claude.json config file..."
rm -f /root/.claude.json 2>/dev/null || true
rm -f "$HOME/.claude.json" 2>/dev/null || true
success "Config JSON file removed."

info "Removing Claude cache directory..."
rm -rf /root/.cache/claude-cli-nodejs 2>/dev/null || true
rm -rf "$HOME/.cache/claude-cli-nodejs" 2>/dev/null || true
success "Cache directory removed."

# ── 6. Temp files ─────────────────────────────────────────────────────────────
info "Cleaning up temp files in /tmp/..."
rm -f /tmp/claude-code.log /tmp/claude-command 2>/dev/null || true
rm -f /tmp/claude-code-*.diag.log 2>/dev/null || true
rm -rf /tmp/claude-0 2>/dev/null || true
success "Temp files cleaned."

# ── 7. Verify ─────────────────────────────────────────────────────────────────
echo ""
echo "========================================"
echo "  Verification"
echo "========================================"

if command -v claude &>/dev/null; then
    warn "claude binary still found at: $(command -v claude)"
    warn "You may need to manually remove it or check your PATH."
else
    success "No 'claude' binary found in PATH. Clean!"
fi

if [ -d /opt/claude-code ]; then
    warn "/opt/claude-code still exists."
else
    success "/opt/claude-code is gone."
fi

if [ -d /root/.claude ] || [ -d "$HOME/.claude" ]; then
    warn ".claude config directory still exists."
else
    success ".claude config directory is gone."
fi

echo ""
echo "========================================"
echo "  All done! You can now do a fresh"
echo "  install of Claude Code."
echo "========================================"
