# bliss-pve

Bliss OS 16.x (Android 13 x86_64) 部署到 Proxmox VE 9，提供 SSH 远程访问，用于查询多张 SIM 卡（CMHK / Google Fi / 中国移动 / 中国电信）的流量余额，以及作为微信备用机。

## 物理拓扑

```
Mac → Tailscale → istoreos (192.168.100.1) → 4u-pve (192.168.100.188)
                                                    │
                                                    └─ VM 300 bliss-android (192.168.100.198)
                                                       └─ Termux sshd :8022
```

`ssh bliss-pve` 一条命令直连。SSH config 模板见 [`ssh-config.example`](ssh-config.example)。

## 经过验证最稳的 VM 配置

| 项 | 值 | 为什么 |
|---|---|---|
| BIOS | seabios | UEFI/OVMF 装完报 BdsDxe BootO003 not found |
| Machine | pc (i440fx) | Q35 init 阶段总线探测兼容差 |
| 磁盘 | SATA (AHCI) | virtio-scsi 启动慢；SATA 是 Android 内置最稳的驱动 |
| 网卡 | e1000 | virtio-net 偶发；Android 自带 e1000 |
| 显卡 | vmware (SVGA II) | virtio-vga / virtio 在 init 阶段黑屏 |
| CPU | host,hidden=1 | **核心**，不隐藏 hypervisor flag 会卡 init |
| Cores | 2 | 4 核以上偶发 SMP 启动卡 |
| RAM | 16 GB | balloon=0 独占 |
| 内核参数 | `nomodeset xforcevesa` | 不加会卡在"Have A Truly Blissful Experience"那行 |

完整 `qm create` 命令在 [`scripts/01-create-vm.sh`](scripts/01-create-vm.sh)。

## 部署流程

1. **下 ISO**：SourceForge BlissOS16/Gapps/Generic（Generic 比 Go 完整）
2. **建 VM**：`bash scripts/01-create-vm.sh`
3. **noVNC 装系统**：分区表选 `dos` (MBR)，OTA Virtual A/B 选 No，GRUB 选 Yes，R/W system 选 Yes
4. **首次启动**：在 GRUB editor (按 `e`) 给 linux 行末追加 `nomodeset xforcevesa DEBUG=2`，进 init shell 后 `exit` 继续
5. **持久化 nomodeset**：`bash scripts/02-fix-grub-nomodeset.sh`（在 PVE 端跑，挂 ZVOL 改 `/boot/grub/android.cfg`）
6. **桌面装 Termux + Termux:Boot**（详细见下）
7. **配 SSH 自启**：`scp termux/start-sshd bliss-pve:.termux/boot/`

## Termux 装机

```bash
# 1. 装 Termux APK（不用 Play Store）
#    https://github.com/termux/termux-app/releases
# 2. 装 Termux:Boot APK，装完打开一次激活 BOOT_COMPLETED
#    https://github.com/termux/termux-boot/releases

# 3. Termux 里：
pkg update -y && pkg install -y openssh termux-services termux-api
passwd                # 设密码
sshd                  # 第一次手动启
mkdir -p ~/.termux/boot
# 上传 termux/start-sshd 到 ~/.termux/boot/，chmod +x

# 4. 推公钥（从 mac 本地）
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_bliss -N ''
# 用 PVE 起临时 HTTP 中转公钥（noVNC 没法粘贴长字符串）
# 或者直接 cat 公钥手输到 ~/.ssh/authorized_keys
```

## 关 VM 的正确姿势

**Android 不响应 ACPI shutdown**，PVE 的 Shutdown 按钮会等超时 → 锁死。

| 操作 | 怎么做 |
|---|---|
| 正常关机 | PVE Web UI 用 **Stop**（不是 Shutdown），或在 Bliss 桌面 Power → Power off |
| 命令行关 | `qm stop 300 --skiplock 1` |
| 锁住了救火 | `bash scripts/03-bliss-rescue.sh` |

## 失败配方汇总

| 配置/行为 | 症状 | 解决 |
|---|---|---|
| UEFI/OVMF | `BdsDxe: Failed to load BootO003 / Not Found` | 改 SeaBIOS |
| Q35 + virtio-scsi | init 早期卡 | 改 i440fx + SATA |
| virtio-vga | "Detecting Android-x86" 后黑屏 | 改 vmware SVGA |
| 不加 `cpu host,hidden=1` | 卡在 "Have A Truly Blissful Experience" | 隐藏 hypervisor flag |
| 4+ vCPU | 偶发 SMP 启动卡 | 降到 2 |
| 只加 `nomodeset` 不加 `xforcevesa` | 部分情况仍卡 | 两个一起 |
| 手动改 `/system/build.prop` 加 override | init 起不来 | 只用 PVE SMBIOS + user build 层面改，ro.* override 无效且有副作用 |
| uiautomator dump 切屏扰 VNC | force-stop + am start + dump 反复把 App 切到前台 | 改走 Chrome CDP + Runtime.evaluate 读 DOM |
| CDP Page.reload 后立即 evaluate 拿空 DOM | CMHK SPA 加载 AJAX 用量数据需 30-40s | marker_js 轮询，每 3s 试一次最多 90s |
| CT App 升级后首页无流量字段 | App 13.2 首页改成广告聚合 | 暂禁用 CT，待走 e.189.cn 网页路线 |
| CMCC cookie session 30 分钟就被踢 | shop.10086.cn 风控严格 | 接入 dmit-lax SMS bot 每日 19:00 CST 流量查询作备用源 |
| Android 不响应 ACPI shutdown → PVE 锁死 | PVE 点 Shutdown 等超时 3 分钟 → 下次操作全部卡 lock | 用 **Stop** 不用 Shutdown；或 `scripts/03-bliss-rescue.sh` 救火 |

## 用途规划

| App | 装机源 | 网络要求 |
|---|---|---|
| Google Fi | Play Store | **必须美国 IP**（Tailscale exit node → dmit-lax） |
| CMHK 中国移动香港 | Play Store HK / APKMirror | 任意 |
| 中国移动 (10086) | https://www.10086.cn 官网 | 大陆 IP 更顺 |
| 中国电信 (10000) | https://189.cn 官网 | 大陆 IP 更顺 |
| 微信（备用号） | https://weixin.qq.com APK | 任意 |

四个运营商 App 都需要 SMS 验证码（手机号注册），需要把"接收码的真机"放手边手动转码。

## Chrome Remote Debugging (CDP) — 推荐数据采集方案

Bliss Chrome 默认开启了 Chrome DevTools Protocol（通过 Android abstract socket）。
从任意宿主（4090 / mac）通过 ADB forward 即可接入：

```bash
adb -s 192.168.100.198:5555 forward tcp:9222 localabstract:chrome_devtools_remote

# 现在 localhost:9222 就是完整 CDP endpoint
curl http://localhost:9222/json         # 列出所有 tab（每个 am start 都会新建）
curl http://localhost:9222/json/version # Chrome 版本信息
```

用 Python websockets 连 tab 的 `webSocketDebuggerUrl`，直接：
- `Runtime.evaluate` — 读 `document.body.innerText`，绕过所有 uiautomator 切屏
- `Page.reload` — 刷新页面触发新 AJAX
- `Network.getAllCookies` — 导出登录态 cookie（包括 httpOnly，可迁移到 Python requests）
- `Target.createTarget` — 创建新 tab 打开任意 URL

**对比 uiautomator dump**：

| 维度 | uiautomator dump | CDP + DOM |
|---|---|---|
| 干扰 VNC | ❌ 每次 am start 切屏 | ✅ 纯后台读 DOM |
| Android emulator detection | ❌ App 拒运行 | ✅ 网页无检测 |
| Session 过期检测 | ⚠️ 需额外 grep | ✅ DOM 变登录页自动识别 |
| 速度 | 慢（am start + render 切回） | 快 5 倍 |

生产部署参见 [ywdking2/invest-review](https://github.com/ywdking2/invest-review) 的 `backend/api/sim_monitor.py`。

### Chrome tab 维护

需要保持 3 个 tab 登录态：
- `https://fi.google.com/account`
- `https://www.hk.chinamobile.com/tc/home/my-zone/menu/usage-query`
- `https://shop.10086.cn/i/`

Bliss Chrome profile 持久化 cookie，VM 重启后自动保留。Session 过期时：
- **CMHK** 已实现 CDP 自动重登（账号 + 密码 + ddddocr 识别 4 位数字 captcha），见 invest-review `backend/api/sim_monitor.py::_ensure_cmhk_login`
- **CMCC** 没自动登录（shop.10086.cn 登录走 SMS），但有 dmit-lax SMS 每日备用源覆盖
- **Fi** 寿命 30 天+，过期就在 noVNC 里登一次

### CMHK 登录页 DOM selectors（自动化用得到）

| 元素 | Selector | 备注 |
|---|---|---|
| 账号输入框 | `#img_home_001` | placeholder "手機號碼或客戶號碼" |
| 密码输入框 | `#input_login_001` | placeholder "請輸入登錄密碼" |
| 登入按钮 | `#img_home_003` | y 位置在 captcha 弹出前 418、弹出后 532 |
| 验证码图 | `#img_home_002` | class `verification-code_image`，160x48，src 是 blob URL（必须 canvas drawImage 取字节） |
| 验证码输入框 | `#input_login_002` | placeholder "驗證碼"，弹出后才存在 |
| 換一張按钮 | `.vali-code_change_text` | 识别错时点这个刷新 |

### Bliss Chrome 自动化登录的关键 trick（CMHK 案例总结）

**踩过的坑（按发现顺序）**：

1. **后台 tab Vue 完全 hydrate 不了**：Android Chrome 严重节流 background tab 的 setTimeout/MicroTask，Vue/Nuxt 的 onMounted/created lifecycle hook 不跑 → input DOM 来自 SSR HTML 但 event listener 没绑 → 看起来 input 存在但点击无反应。`bodyLen` 长期停在 21（页脚）字节是诊断特征。**解法**：
   - 关掉**冗余 tab**（同 origin 多个 tab 互相挤背景）：CDP `/json/close/{id}`
   - **`Target.activateTarget`**：CDP `/json/activate/{id}`，把 tab 切到 active
   - **ADB `input keyevent KEYCODE_WAKEUP`**：让屏幕亮+让 Chrome 知道 user interaction
   - 等 8-15s `bodyLen > 100` + 关键文字出现才能确认 hydrate
2. **Vue v-model 不响应 JS 改 input.value**：用 `Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set.call(el, v)` + dispatch input/change，**对原生 input 有效**，但部分组件库（比如 Element Plus 的 `<el-input>`）反应式系统不感知。**解法**：用 CDP `Input.insertText`（trusted keyboard event），强制触发 v-model 同步。
3. **`Input.dispatchMouseEvent` 在 SPA 里不触发 `@click`**：Vue 监听的是合成 click，但有些组件等的是 `pointerdown` 或 `vue-on-click` 装饰器。**解法**：JS 层 `el.dispatchEvent(new MouseEvent('mousedown/mouseup/click', {bubbles:true,view:window}))` + `el.click()` 双保险更稳（前提是 hydrate 已完成）。
4. **多 worker（uvicorn `--workers 4`）并发同时操作同一 tab**：4 个 worker 收到 trigger 都跑自动登录，type_into 把账号填成 `8494698984946989`（叠加）。**解法**：fcntl 文件锁让只一个 worker 真跑，其他直接 return False。
5. **reload 后立即 evaluate 拿空 DOM**：reload 触发 navigation 但 background tab 异步 render 慢。轮询每 3s 检查 marker，最多 60-90s。
6. **图形 captcha**：CMHK 4 位带噪点数字。`canvas.drawImage(img); canvas.toDataURL('image/png')` 把 blob URL 转 base64（`<img src="blob:...">` 不能直接 wget）。**ddddocr** 本地 ONNX 模型，CPU 20ms，准确率 ~70-85%（噪点重）。

### CMHK 自动登录现状（2026-04-19）

**90% 通路打通**，最后 form submit + redirect 这一步 captcha 解出后 never redirect。怀疑 OCR 准确率 + JS click 在 final submit 没触发 form handler。代码在 `invest-review/backend/api/sim_monitor.py::_ensure_cmhk_login_locked`，rate limit 12h 1 次防 lockout。失败的 captcha PNG dump 到 `/tmp/cmhk-captcha-*.png` 事后分析。

**当前推荐**：手动在 Bliss noVNC 里登一次（cookie 寿命几天到几周），自动登录算碰运气保险。

### 锁横屏（防 App 强制 portrait 撑出竖屏）

```bash
adb shell cmd window set-ignore-orientation-request true
adb shell cmd window user-rotation lock 0
```

（重启后失效，sim_monitor poller 启动时自动重做）

## 用量查询 bash 脚本（早期手动方案）

四家运营商通过 ADB + uiautomator dump 一条命令查（⚠️ 已被 invest-review CDP 路线取代，保留作为本地测试备份）：

```bash
./scripts/bliss-usage.sh         # 汇总 4 家
./scripts/fi-usage.sh            # Google Fi (web)
./scripts/cmhk-usage.sh          # CMHK 中國移動香港 (web)
./scripts/cmcc-usage.sh          # 中国移动 shop.10086.cn (web)
./scripts/ct-usage.sh            # 中国电信 App com.ct.client
```

### 为什么不走 App 伪装 emulator detection

尝试过改 build.prop + PVE SMBIOS 伪装成 Samsung 设备。结论：

- **能改的**：DMI (sys_vendor/product_name 通过 PVE `--smbios1 manufacturer=... base64=1`)、build.prop 部分字段
- **改坏了**：直接 append `ro.hardware` 等 override 到 `/system/build.prop` 会让 Android init 挂在启动早期
- **需要 Magisk + PIF 才彻底**：但 Bliss 16 没有 Android boot.img，ramdisk 是 Linux initramfs，没法直接用 magiskboot patch
- **CDP + DOM 完全绕过**：Chrome 作为 headless renderer 直接读渲染后的文字，app-level emulator detection 无关

所以结论：**全部走网页 + CDP Runtime.evaluate**。App 路线仅在某些功能（充值、客服）时偶尔需要 uiautomator dump 兜底。

## ZFS 快照保护

```bash
zfs snapshot nvme-pool/vm-300-disk-0@bliss-fully-working   # 已有
zfs rollback nvme-pool/vm-300-disk-0@bliss-fully-working   # 一键回滚
```
