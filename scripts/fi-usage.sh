#!/bin/bash
# fi-usage.sh — 从 mac 上一条命令查 Google Fi 当月数据用量
# 依赖: adb (brew install --cask android-platform-tools), Bliss VM 已登录 Google
set -uo pipefail

BLISS=${BLISS:-192.168.100.198:5555}
adb connect "$BLISS" >/dev/null 2>&1
adb -s "$BLISS" wait-for-device

# 唤醒 + 解锁（Bliss 一般不锁屏，无害）
adb -s "$BLISS" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true

# 打开 Fi 账户页
adb -s "$BLISS" shell am start \
  -a android.intent.action.VIEW \
  -d 'https://fi.google.com/account' \
  -p com.android.chrome >/dev/null

# 等页面渲染
sleep 6

# 抓 UI 树
adb -s "$BLISS" shell uiautomator dump /sdcard/fi-ui.xml >/dev/null
DUMP=$(adb -s "$BLISS" shell cat /sdcard/fi-ui.xml)

# 提取关键字段
USAGE=$(echo "$DUMP" | grep -oE 'Data usage is [0-9.]+ ?GB' | head -1 | sed 's/.*is //' || true)
ALERT=$(echo "$DUMP" | grep -oE 'Alert&#10;[0-9.]+[^"]*GB' | head -1 | sed 's/.*&#10;//' | sed 's/\xc2\xa0/ /g' || true)
BILL=$(echo "$DUMP" | grep -oE '\$[0-9]+\.[0-9]+' | head -1 || true)  # 账单必有小数,跳过 promo $60
CYCLE=$(echo "$DUMP" | grep -oE 'Cycle ends&#10;[0-9]+ days' | head -1 | sed 's/&#10;/ /' || true)

echo "Google Fi"
echo "  数据用量: ${USAGE:-未抓到}"
echo "  Alert 阈值: ${ALERT:-未抓到}"
echo "  ${CYCLE:-周期未抓到}"
echo "  当前账单: ${BILL:-未抓到}"

# 顺便 home 一下（关掉 Chrome 前台，避免一直停留）
adb -s "$BLISS" shell input keyevent KEYCODE_HOME >/dev/null 2>&1 || true
