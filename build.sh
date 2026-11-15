#!/usr/bin/env bash
# Gera index.html (página standalone) a partir de src/game.html
set -euo pipefail
cd "$(dirname "$0")"
{
  printf '<!doctype html>\n<html lang="pt-BR">\n<head>\n<meta charset="utf-8">\n<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">\n'
  sed -n '1,/^<\/style>/p' src/game.html
  printf '</head>\n<body>\n'
  sed -n '/^<\/style>/,$p' src/game.html | tail -n +2
  printf '</body>\n</html>\n'
} > index.html
