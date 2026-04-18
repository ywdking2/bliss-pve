#!/bin/bash
# cmhk-usage.sh — 从 mac 上一条命令查 CMHK (中国移动香港) 流量
set -uo pipefail

BLISS=${BLISS:-192.168.100.198:5555}
adb connect "$BLISS" >/dev/null 2>&1
adb -s "$BLISS" wait-for-device
adb -s "$BLISS" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true

adb -s "$BLISS" shell am start \
  -a android.intent.action.VIEW \
  -d 'https://www.hk.chinamobile.com/tc/home/my-zone/menu/usage-query' \
  -p com.android.chrome >/dev/null

# 轮询最多 30 秒，等 AJAX 加载出 "餘量" 字段
DUMP=""
for i in 1 2 3 4 5 6; do
  sleep 5
  adb -s "$BLISS" shell uiautomator dump /sdcard/cmhk-ui.xml >/dev/null 2>&1
  DUMP=$(adb -s "$BLISS" shell cat /sdcard/cmhk-ui.xml)
  if echo "$DUMP" | grep -q 'GB 餘量'; then break; fi
done

PLAN=$(echo "$DUMP" | grep -oE 'text="[^"]*服務計劃 ?[^"]*"' | head -1 | sed 's/text="//; s/"$//' || true)
REMAIN=$(echo "$DUMP" | grep -oE '[0-9]+\.[0-9]+GB 餘量' | head -1 || true)
USED_TOTAL=$(echo "$DUMP" | grep -oE '已用：[0-9.]+/[0-9.]+GB' | head -1 | sed 's/已用：//' || true)
USED_LINE=$(echo "$DUMP" | grep -oE '本號已用: ?[0-9.]+ ?[GM]B' | head -1 | sed 's/本號已用: *//' || true)
EXTRA=$(echo "$DUMP" | grep -oE 'MACAUONLY Data Package' | head -1 || true)

echo "CMHK (中國移動香港)"
echo "  計劃: ${PLAN:-未抓到}"
echo "  總用量: ${USED_TOTAL:-未抓到}  (餘: ${REMAIN:-未抓到})"
echo "  本號已用: ${USED_LINE:-未抓到}"

# Chrome 留在前台方便复查；不按 HOME

