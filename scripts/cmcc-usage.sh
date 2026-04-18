#!/bin/bash
# cmcc-usage.sh — 从 mac 上一条命令查 中国移动 个人中心 (shop.10086.cn) 套餐用量
set -uo pipefail

BLISS=${BLISS:-192.168.100.198:5555}
adb connect "$BLISS" >/dev/null 2>&1
adb -s "$BLISS" wait-for-device
adb -s "$BLISS" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true

adb -s "$BLISS" shell am start \
  -a android.intent.action.VIEW \
  -d 'https://shop.10086.cn/i/' \
  -p com.android.chrome >/dev/null

# 轮询最多 35 秒等"共 XX.XX GB"字样出现
for i in 1 2 3 4 5 6 7; do
  sleep 5
  adb -s "$BLISS" shell uiautomator dump /sdcard/cmcc-ui.xml >/dev/null 2>&1
  DUMP=$(adb -s "$BLISS" shell cat /sdcard/cmcc-ui.xml)
  if echo "$DUMP" | grep -q '流量'; then break; fi
done

python3 - "$DUMP" <<'PY'
import sys, re
data = sys.argv[1]
texts = re.findall(r'text="([^"]*)"', data)

def find_block(texts, anchor_prev, unit):
    for i, t in enumerate(texts):
        if re.fullmatch(r'[0-9]+(?:\.[0-9]+)?', t) and i >= 2 \
           and texts[i-1] == '剩余' and texts[i-2] == anchor_prev \
           and i+4 < len(texts) and texts[i+1] == unit:
            # texts[i]=剩余量, texts[i+1]=unit, texts[i+2]=百分比, texts[i+3]=共, texts[i+4]=总量
            return t, texts[i+4], texts[i+2]  # rem, total, pct
    return None

plan = next((t for t in texts if '档' in t and '套餐' in t), None) \
    or next((t for t in texts if '套餐' in t and '查询' not in t), '未知')
voice = find_block(texts, '通话', '分钟') or find_block(texts, '语音', '分钟')
data_blk = find_block(texts, '流量', 'GB') or find_block(texts, '流量', 'MB')
balance = next((texts[i+2] for i,t in enumerate(texts) if '账户总余额' in t and i+2 < len(texts)), None)
last_bill = next((re.search(r'上月消费：?([0-9.]+)', t).group(1) for t in texts if '上月消费' in t and re.search(r'上月消费：?([0-9.]+)', t)), None)

print('中国移动')
print(f'  套餐: {plan}')
if data_blk:
    rem, total, pct = data_blk
    used = float(total) - float(rem)
    print(f'  流量: 已用 {used:.2f} GB / {total} GB  (剩 {rem} GB, {pct})')
if voice:
    rem, total, pct = voice
    print(f'  通话: 剩 {rem} / {total} 分钟 ({pct})')
if balance:
    print(f'  账户余额: ¥{balance}')
if last_bill:
    print(f'  上月消费: ¥{last_bill}')
PY
