#!/usr/bin/env bash
# =============================================================================
# Установка Claude Code (CLI от Anthropic)
# https://docs.anthropic.com/en/docs/claude-code/getting-started
# =============================================================================
set -euo pipefail

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
BOLD=$'\033[1m'
NC=$'\033[0m'

log_info()    { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_step()    { echo -e "\n${BOLD}${BLUE}==>${NC}${BOLD} $*${NC}"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }

install_claude_code() {
  log_step "Установка Claude Code CLI"

  export DEBIAN_FRONTEND=noninteractive

  # Устанавливаем curl если нет
  if ! command -v curl &>/dev/null; then
    log_info "Устанавливаем curl..."
    apt-get update -qq
    apt-get install -y curl
  fi

  log_info "Запускаем официальный установщик Claude Code..."
  # Официальный нативный установщик (рекомендован вместо npm)
  curl -fsSL https://claude.ai/install.sh | bash

  # Добавляем в PATH для текущей сессии если нужно
  CLAUDE_BIN_CANDIDATES=(
    "/root/.claude/bin"
    "${HOME}/.claude/bin"
    "/usr/local/bin"
  )
  for candidate in "${CLAUDE_BIN_CANDIDATES[@]}"; do
    if [ -f "${candidate}/claude" ]; then
      log_success "Claude Code установлен: ${candidate}/claude"
      break
    fi
  done

  # Проверяем установку
  if command -v claude &>/dev/null; then
    CLAUDE_VERSION=$(claude --version 2>/dev/null || echo "неизвестно")
    log_success "Claude Code готов к использованию! Версия: ${CLAUDE_VERSION}"
    log_info "Первый запуск: claude (потребуется аутентификация)"
  else
    log_warn "claude не найден в PATH. Возможно, нужно перезайти в терминал."
    log_info "Попробуйте: source ~/.bashrc && claude"
  fi
}

install_claude_code
