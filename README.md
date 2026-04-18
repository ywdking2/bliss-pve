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

| 配置 | 症状 |
|---|---|
| UEFI/OVMF | `BdsDxe: Failed to load BootO003 / Not Found` |
| Q35 + virtio-scsi | init 早期卡 |
| virtio-vga | "Detecting Android-x86" 后黑屏 |
| 不加 cpu hidden=1 | 卡在 "Have A Truly Blissful Experience" |
| 4+ vCPU | 偶发 SMP 启动卡 |
| 只加 nomodeset 不加 xforcevesa | 部分情况仍卡 |

## 用途规划

| App | 装机源 | 网络要求 |
|---|---|---|
| Google Fi | Play Store | **必须美国 IP**（Tailscale exit node → dmit-lax） |
| CMHK 中国移动香港 | Play Store HK / APKMirror | 任意 |
| 中国移动 (10086) | https://www.10086.cn 官网 | 大陆 IP 更顺 |
| 中国电信 (10000) | https://189.cn 官网 | 大陆 IP 更顺 |
| 微信（备用号） | https://weixin.qq.com APK | 任意 |

四个运营商 App 都需要 SMS 验证码（手机号注册），需要把"接收码的真机"放手边手动转码。

## 用量查询脚本（已实施）

四家运营商通过 ADB + uiautomator dump 一条命令查：

```bash
./scripts/bliss-usage.sh         # 汇总 4 家
./scripts/fi-usage.sh            # Google Fi (web)
./scripts/cmhk-usage.sh          # CMHK 中國移動香港 (web)
./scripts/cmcc-usage.sh          # 中国移动 shop.10086.cn (web)
./scripts/ct-usage.sh            # 中国电信 App com.ct.client
```

**先决条件**：Bliss VM 内 Chrome 已登录各家网页（CMHK/CMCC/Fi）、中国电信 App 已登录。登录 session 存 Chrome cookie 里，不会过期（除非运营商主动踢 session）。

输出示例：

```
Google Fi
  数据用量: 0 GB
  Alert 阈值: 3 GB
  Cycle ends 27 days
  当前账单: $88.77

CMHK (中國移動香港)
  總用量: 15.15/100.00GB  (餘: 84.85GB)
  本號已用: 6.89 GB

中国移动
  套餐: 全家享套餐（全国版）199档
  流量: 已用 44.11 GB / 155.40 GB  (剩 111.29 GB, 72%)
  通话: 剩 382 / 600 分钟 (64%)

中国电信
  剩余流量: 178.89GB
  剩余语音: 2097分钟
  宽带速率: 2000Mbps
```

### 为什么不走 App 伪装 emulator detection

尝试过改 build.prop + PVE SMBIOS 伪装成 Samsung 设备。结论：

- **能改的**：DMI (sys_vendor/product_name 通过 PVE `--smbios1 manufacturer=... base64=1`)、build.prop 部分字段
- **改坏了**：直接 append `ro.hardware` 等 override 到 `/system/build.prop` 会让 Android init 挂在启动早期
- **需要 Magisk + PIF 才彻底**：但 Bliss 16 没有 Android boot.img，ramdisk 是 Linux initramfs，没法直接用 magiskboot patch
- **web 版完全绕过检测**：Chrome 没 emulator check，uiautomator 抓 DOM 节点一样有效

所以结论：**除非 App 独有功能（如充值），否则全部走网页 + ADB uiautomator dump**。中国电信是例外（Android 13 + user build 它不检测就让登）。

## ZFS 快照保护

```bash
zfs snapshot nvme-pool/vm-300-disk-0@bliss-fully-working   # 已有
zfs rollback nvme-pool/vm-300-disk-0@bliss-fully-working   # 一键回滚
```
