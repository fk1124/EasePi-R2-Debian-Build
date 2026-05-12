# EasePi-R2 GPU / Panthor 安全调试版

本版目标不是强行“GPU 开箱自动加载”，而是先保证系统能正常启动，再手动验证 panthor。

已保留的修复：

1. GPU compatible 改为主线 panthor 可匹配的写法：

```dts
compatible = "rockchip,rk3588-mali", "arm,mali-valhall-csf";
```

2. GPU OPP 表改为单供电三元组写法，避免：

```text
Invalid number of elements in microvolt property (6) with supplies (1)
_of_add_opp_table_v2: Failed to add OPP, -22
```

3. 保留 Mesa / Vulkan 基础用户态和 `easepi-r2-gpu-check` 检测工具。

安全处理：

- 删除 `/etc/modules-load.d/easepi-r2-gpu.conf`，不再开机强制加载 panthor。
- 新增 `/etc/modprobe.d/99-easepi-r2-panthor-manual-only.conf`，阻止 udev/modalias 在开机时自动加载 panthor。
- 保留 `blacklist panfrost`，避免旧 Mali 驱动方向干扰。

## 启动后操作

先看状态：

```bash
easepi-r2-gpu-check
```

确认系统稳定后，手动加载 panthor：

```bash
easepi-r2-gpu-check load
```

如果出现 `/dev/dri/renderD128`，说明 Mali-G610 3D 入口起来了。

如果手动加载后卡死，断电重启即可；本版默认不会自动加载 panthor，下一次启动应能恢复。

如果手动加载稳定成功，再启用开机自动加载：

```bash
easepi-r2-gpu-check enable-auto
reboot
```

如果启用自动加载后再次卡住，挂载 rootfs 删除：

```bash
rm -f /etc/modules-load.d/easepi-r2-gpu.conf
cat >/etc/modprobe.d/99-easepi-r2-panthor-manual-only.conf <<'EOC'
blacklist panthor
EOC
```
