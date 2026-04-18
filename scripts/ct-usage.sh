#!/bin/bash
# ct-usage.sh — 中国电信 App (com.ct.client) 首页用量
set -uo pipefail

BLISS=${BLISS:-192.168.100.198:5555}
adb connect "$BLISS" >/dev/null 2>&1
adb -s "$BLISS" wait-for-device
adb -s "$BLISS" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true

# 强制前台启动 App 主页
adb -s "$BLISS" shell am force-stop com.ct.client >/dev/null 2>&1 || true
adb -s "$BLISS" shell monkey -p com.ct.client -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1

for i in 1 2 3 4 5 6; do
  sleep 5
  adb -s "$BLISS" shell uiautomator dump /sdcard/ct-ui.xml >/dev/null 2>&1
  DUMP=$(adb -s "$BLISS" shell cat /sdcard/ct-ui.xml)
  if echo "$DUMP" | grep -q '剩余通用流量'; then break; fi
done

python3 - "$DUMP" <<'PY'
import sys, re
data = sys.argv[1]
texts = re.findall(r'text="([^"]*)"', data)

def val_before_label(label):
    for i, t in enumerate(texts):
        if t == label and i > 0:
            return texts[i-1]
    return None

print('中国电信')
print(f"  账户余额: {val_before_label('账户余额') or '未抓到'}")
print(f"  剩余流量: {val_before_label('剩余通用流量') or '未抓到'}")
print(f"  剩余语音: {val_before_label('剩余语音') or '未抓到'}")
print(f"  剩余积分: {val_before_label('剩余积分') or '未抓到'}")
cloud = val_before_label('剩余云盘空间')
if cloud: print(f"  剩余云盘: {cloud}")
bb = val_before_label('深圳市龙岗区********信义嘉御豪园*栋A座**层****房') or \
     next((texts[i-1] for i,t in enumerate(texts) if '融合宽带' in (texts[i-1] if i>0 else '')), None)
# 宽带速率
speed = next((t for t in texts if re.fullmatch(r'[0-9]+Mbps', t)), None)
if speed: print(f"  宽带速率: {speed}")
PY
