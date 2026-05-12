# EasePi-R2 GPU / Panthor 安全调试版

本版默认不自动加载 panthor。RK3588 Mali-G610 的主线方向是 panthor，但如果 DTB 里的 GPU 时钟、IRQ、供电或 power-domain 描述不对，`modprobe panthor` 可能导致 SSH 和 HDMI 同时卡死。

## 本版修正

1. GPU compatible 使用当前主线 panthor 可匹配的写法：

```dts
compatible = "rockchip,rk3588-mali", "arm,mali-valhall-csf";
```

2. GPU 时钟名、IRQ 名改回 panthor 驱动实际读取的名字：

```dts
clock-names = "core", "coregroup", "stacks";
interrupt-names = "job", "mmu", "gpu";
```

3. GPU 供电使用 panthor 当前约定：

```dts
mali-supply = <&vdd_gpu_s0>;
sram-supply = <&vdd_gpu_mem_s0>;
```

4. 保留手动安全调试模式：

- `blacklist panthor`：避免 udev/modalias 在开机时自动加载。
- `blacklist panfrost`：避免旧 Mali 驱动方向干扰。
- `easepi-r2-gpu-check load` 现在必须显式设置确认环境变量才会执行 `modprobe panthor`。

## 构建提醒

如果改过 DTS/DTB，必须让 BSP 重新编译。脚本现在会记录 BSP 输入文件 hash，避免旧 `output/bsp/current` 被误复用。需要强制重编时仍可执行：

```bash
FORCE_BSP_REBUILD=yes bash build-bsp-image.sh debian trixie current minimal
```

刷机后先确认 DTB 已更新：

```bash
easepi-r2-gpu-check guard
easepi-r2-gpu-check
```

只有 `guard` 全部通过，才考虑手动加载 panthor。建议连接串口或保留可恢复入口后执行：

```bash
EASEPI_R2_GPU_DANGEROUS_LOAD=yes easepi-r2-gpu-check load
```

如果出现 `/dev/dri/renderD128` 且系统稳定，再启用开机自动加载：

```bash
easepi-r2-gpu-check enable-auto
reboot
```

如果加载后卡死，断电重启即可；默认黑名单仍会让下一次启动恢复到不加载 panthor 的状态。若你已经启用了自动加载，需要挂载 rootfs 后恢复：

```bash
rm -f /etc/modules-load.d/easepi-r2-gpu.conf
cat >/etc/modprobe.d/99-easepi-r2-panthor-manual-only.conf <<'EOC'
blacklist panthor
EOC
```
