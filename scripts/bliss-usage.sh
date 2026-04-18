#!/bin/bash
# bliss-usage.sh — 一条命令跑四家运营商的用量查询
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================"
echo "  全部 SIM 用量汇总"
echo "========================"

bash "$DIR/fi-usage.sh"
echo
bash "$DIR/cmhk-usage.sh"
echo
bash "$DIR/cmcc-usage.sh"
echo
bash "$DIR/ct-usage.sh"
