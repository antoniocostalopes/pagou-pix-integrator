#!/usr/bin/env bash
# install.sh — instalador da Skill Pagou PIX Integrator para macOS / Linux / WSL
#
# Uso:
#   ./install.sh                 # copia para ~/.claude/skills/
#   ./install.sh --link          # cria symlink
#   ./install.sh --force         # sobrescreve instalação existente
#   ./install.sh --path /custom  # destino customizado

set -euo pipefail

SKILL_NAME="pagou-pix-integrator"
SOURCE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
DEST_BASE="${HOME}/.claude/skills"
USE_LINK=0
FORCE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --link)  USE_LINK=1; shift ;;
    --force) FORCE=1; shift ;;
    --path)  DEST_BASE="$2"; shift 2 ;;
    -h|--help)
      grep -E '^#' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "Opção desconhecida: $1" >&2
      exit 1
      ;;
  esac
done

DEST="${DEST_BASE}/${SKILL_NAME}"

echo "Pagou PIX Integrator — instalador"
echo "  Origem:  ${SOURCE_DIR}"
echo "  Destino: ${DEST}"
echo

# Verificar source
if [[ ! -f "${SOURCE_DIR}/SKILL.md" ]]; then
  echo "ERRO: SKILL.md não encontrado em ${SOURCE_DIR}" >&2
  echo "Rode este script de dentro da pasta da skill." >&2
  exit 1
fi

# Criar pasta pai
mkdir -p "${DEST_BASE}"

# Tratar instalação existente
if [[ -e "${DEST}" || -L "${DEST}" ]]; then
  if [[ "${FORCE}" -eq 1 ]]; then
    echo "Removendo instalação existente..."
    rm -rf -- "${DEST}"
  else
    echo "ERRO: já existe uma instalação em ${DEST}" >&2
    echo "Use --force para sobrescrever." >&2
    exit 1
  fi
fi

# Instalar
if [[ "${USE_LINK}" -eq 1 ]]; then
  echo "Criando symbolic link..."
  ln -s "${SOURCE_DIR}" "${DEST}"
else
  echo "Copiando arquivos..."
  mkdir -p "${DEST}"
  # rsync se disponível (preserva timestamps); senão cp
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --exclude install.ps1 --exclude install.sh --exclude .git "${SOURCE_DIR}/" "${DEST}/"
  else
    cp -R "${SOURCE_DIR}/." "${DEST}/"
    rm -f "${DEST}/install.ps1" "${DEST}/install.sh"
    rm -rf "${DEST}/.git"
  fi
fi

# Verificar
if [[ ! -f "${DEST}/SKILL.md" ]]; then
  echo "ERRO: instalação falhou — SKILL.md não chegou ao destino." >&2
  exit 1
fi

echo
echo "Instalado com sucesso."
echo
echo "Próximos passos:"
echo "  1. Reinicie o Claude Code"
echo "  2. Em qualquer projeto, invoque: /pagou-pix-integrator"
echo
echo "Para verificar: ls ${DEST}"
