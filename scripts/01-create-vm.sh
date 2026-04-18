#!/bin/bash
# 在 PVE 主机上创建 Bliss OS VM（VMID 300）
# 跑法：scp 到 4u-pve 后 bash 执行，或：ssh 4u-pve "bash -s" < 01-create-vm.sh
set -euo pipefail

VMID=${VMID:-300}
ISO=${ISO:-Bliss-v16.9.7-gapps.iso}
STORAGE=${STORAGE:-nvme-pool}

# 下载 ISO（如不存在）
ISO_PATH="/var/lib/vz/template/iso/${ISO}"
if [ ! -f "${ISO_PATH}" ]; then
  echo "Downloading ${ISO}..."
  wget -c --content-disposition -L \
    "https://sourceforge.net/projects/blissos-x86/files/Official/BlissOS16/Gapps/Generic/${ISO}/download" \
    -O "${ISO_PATH}"
fi

# 创建 VM
qm create "${VMID}" \
  --name bliss-android \
  --memory 16384 --balloon 0 \
  --cores 2 --cpu 'host,hidden=1' \
  --machine pc --bios seabios \
  --sata0 "${STORAGE}:64,ssd=1,discard=on" \
  --net0 e1000,bridge=vmbr0 \
  --vga vmware --serial0 socket \
  --ide2 "local:iso/${ISO},media=cdrom" \
  --boot order='ide2;sata0' \
  --ostype l26 --tablet 1 \
  --tags android,bliss

qm start "${VMID}"
echo "VM ${VMID} 已启动。打开 PVE noVNC 完成图形化安装。"
echo "安装时关键选择："
echo "  - 分区表 label type 选 'dos' (MBR)"
echo "  - OTA Virtual A/B 选 No"
echo "  - Install GRUB2 选 Yes"
echo "  - Install /system R/W 选 Yes"
echo ""
echo "首次启动会卡死，必须在 GRUB 按 e 给 linux 行加: nomodeset xforcevesa DEBUG=2"
echo "进入 init shell 后输入 exit 继续启动。"
echo "进桌面后跑 02-fix-grub-nomodeset.sh 持久化。"
