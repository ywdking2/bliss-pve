#!/bin/bash
# 救火脚本：当 PVE 锁住 VM 300（Android 不响应 ACPI shutdown 导致的常见死锁）
# 在 PVE 主机上跑。等同于"硬重启 + 清所有残留状态"。
set -uo pipefail

VMID=${VMID:-300}

qm unlock "${VMID}" 2>/dev/null || true
rm -f "/var/lock/qemu-server/lock-${VMID}.conf"

# 杀残留 KVM 进程
pkill -9 -f "kvm.*-id ${VMID}" 2>/dev/null || true
sleep 2

# 清 PID/socket/scope
rm -f "/var/run/qemu-server/${VMID}."*
systemctl reset-failed "${VMID}.scope" 2>/dev/null || true

echo "已清理 VMID=${VMID} 的所有残留状态。"
qm status "${VMID}"
echo ""
echo "现在可以 'qm start ${VMID}' 重新启动。"
