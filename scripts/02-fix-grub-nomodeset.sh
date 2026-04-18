#!/bin/bash
# 持久化 nomodeset 到 Bliss VM 的 GRUB 配置（解决"卡在欢迎画面"的根本问题）
# 在 PVE 主机上跑。会先关 VM，做 ZFS 快照，挂 ZVOL 修改 grub，再开 VM。
set -euo pipefail

VMID=${VMID:-300}
STORAGE=${STORAGE:-nvme-pool}
DISK="${STORAGE}/vm-${VMID}-disk-0"

# 关 VM
echo "Stopping VM ${VMID}..."
qm stop "${VMID}" --skiplock 1 2>/dev/null || true
sleep 3
pkill -9 -f "kvm.*-id ${VMID}" 2>/dev/null || true
sleep 1
rm -f "/var/run/qemu-server/${VMID}."* "/var/lock/qemu-server/lock-${VMID}.conf"

# ZFS 快照
SNAP="${DISK}@before-grub-edit-$(date +%Y%m%d-%H%M)"
echo "Creating snapshot ${SNAP}..."
zfs snapshot "${SNAP}"

# 挂载 sda1
MNT=/mnt/bliss-edit
mkdir -p "${MNT}"
mount "/dev/zvol/${DISK}-part1" "${MNT}"

CFG="${MNT}/boot/grub/android.cfg"
if [ ! -f "${CFG}" ]; then
  echo "ERROR: ${CFG} not found. Bliss 安装可能没装 GRUB2。" >&2
  umount "${MNT}"
  exit 1
fi

# 备份 + 注入
cp -n "${CFG}" "${CFG}.orig" 2>/dev/null || true
if grep -q 'nomodeset xforcevesa' "${CFG}"; then
  echo "nomodeset xforcevesa 已经在 grub 里，跳过修改"
else
  sed -i 's|noexec=off \$src \$@|noexec=off nomodeset xforcevesa \$src \$@|' "${CFG}"
  echo "已注入 nomodeset xforcevesa:"
  grep 'noexec=off' "${CFG}"
fi

umount "${MNT}"

# 启动
qm start "${VMID}"
echo "VM ${VMID} 已启动。等 25-60 秒应该能 ssh 进去（如果 Termux:Boot 配好了）。"
echo "回滚命令: zfs rollback ${SNAP}"
