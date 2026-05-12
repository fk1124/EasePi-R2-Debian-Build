# EasePi-R2 Armbian / Debian Build

给 **EasePi-R2 / RK3588** 构建 Armbian 原生镜像和 Debian BSP 打包镜像。

本项目主要保留两条路线：

```text
路线一：Armbian 原生镜像
Armbian build 直接负责 U-Boot / Kernel / DTB / rootfs / 分区镜像

路线二：Debian BSP 打包镜像
Armbian build 负责 U-Boot / Kernel / DTB / kernel modules
本项目负责 Debian rootfs 生成、BSP 安装、分区打包、U-Boot 写入
```

最终可以生成可写入 TF 卡、USB 存储或 eMMC 的 `.img.xz` 镜像。

---

## 基础环境要求

推荐使用 **原生 Linux 主机** 或 **Linux 虚拟机** 进行编译。

推荐系统：

```text
Debian 13
Debian 12
```

推荐配置：

```text
CPU：4 核以上，推荐 8 核以上
内存：8GB 起步，推荐 16GB 以上
磁盘：100GB 起步，推荐 150GB 以上
网络：能正常访问 GitHub、Debian 软件源
```

不推荐使用 WSL，编译内核、挂载镜像、loop 设备、chroot、binfmt、权限处理等环节容易出现问题。

---

推荐结构：

```text
~/rk3588_build/
├── build/                                  # Armbian 官方 build 源码
└── EasePi-R2-Debian-Build/          # 本仓库
    ├── build-bsp-image.sh                  # Debian BSP 打包镜像入口
    ├── build.sh                            # Armbian 原生镜像入口
    ├── README.md
    ├── rootfs/
    ├── scripts/
    └── userpatches/
```

---

## 一、安装依赖

```bash
sudo apt update
sudo apt install -y git curl wget rsync unzip xz-utils ca-certificates
sudo apt install -y build-essential gcc g++ make bc bison flex
sudo apt install -y libssl-dev libncurses-dev python3 python3-pip python3-setuptools
sudo apt install -y file cpio qemu-user-static binfmt-support debootstrap
sudo apt install -y parted dosfstools e2fsprogs util-linux u-boot-tools
```

---

## 二、基础准备

```bash
mkdir -p ~/rk3588_build
cd ~/rk3588_build

git clone --depth=1 https://github.com/armbian/build.git build
git clone https://github.com/fk1124/EasePi-R2-Debian-Build.git

cd EasePi-R2-Debian-Build
chmod +x build-bsp-image.sh build.sh scripts/*.sh
```


---

## 三、开始编译

进入项目目录：

```bash
cd ~/rk3588_build/EasePi-R2-Debian-Build
```

---

### 3.1 编译 Debian BSP 打包镜像

| 镜像类型                                  | 编译命令                                                  |
| ----------------------------------------- | --------------------------------------------------------- |
| Debian 13 + 主线内核 + 最小化镜像（推荐） | `bash build-bsp-image.sh debian trixie current minimal`   |
| Debian 13 + 主线内核 + 服务器镜像         | `bash build-bsp-image.sh debian trixie current server`    |
| Debian 13 + 新主线内核 + 最小化镜像       | `bash build-bsp-image.sh debian trixie edge minimal`      |
| Debian 13 + 新主线内核 + 服务器镜像       | `bash build-bsp-image.sh debian trixie edge server`       |
| Debian 12 + 主线内核 + 最小化镜像         | `bash build-bsp-image.sh debian bookworm current minimal` |
| Debian 12 + 主线内核 + 服务器镜像         | `bash build-bsp-image.sh debian bookworm current server`  |
| Debian 12 + 厂商内核 + 最小化镜像         | `bash build-bsp-image.sh debian bookworm vendor minimal`  |
| Debian 12 + 厂商内核 + 服务器镜像         | `bash build-bsp-image.sh debian bookworm vendor server`   |

格式解释：

```bash
bash build-bsp-image.sh debian [系统版本] [内核分支] [镜像类型]
```

参数解释：

```text
debian
trixie / bookworm
current / edge / vendor
minimal / server
```

建议优先测试：

```bash
bash build-bsp-image.sh debian trixie current minimal
```

---

### 3.2 编译 Armbian 原生镜像

| 镜像类型                                          | 编译命令                                |
| ------------------------------------------------- | --------------------------------------- |
| Armbian Debian 13 + 主线内核 + 最小化镜像（推荐） | `bash build.sh current trixie minimal`  |
| Armbian Debian 13 + 主线内核 + 服务器镜像         | `bash build.sh current trixie server`   |
| Armbian Debian 13 + 主线内核 + XFCE 桌面镜像      | `bash build.sh current trixie desktop`  |
| Armbian Debian 13 + 新主线内核 + 最小化镜像       | `bash build.sh edge trixie minimal`     |
| Armbian Debian 13 + 新主线内核 + 服务器镜像       | `bash build.sh edge trixie server`      |
| Armbian Debian 12 + 厂商内核 + 最小化镜像         | `bash build.sh vendor bookworm minimal` |
| Armbian Debian 12 + 厂商内核 + 服务器镜像         | `bash build.sh vendor bookworm server`  |

格式解释：

```bash
bash build.sh [current|edge|vendor] [trixie|bookworm] [minimal|server|desktop]
```

建议优先测试：

```bash
bash build.sh current trixie minimal
```

---

## 四、编译产物位置

Debian BSP 打包镜像产物：

```bash
~/rk3588_build/EasePi-R2-Debian-Build/output/images/
```

Armbian 原生镜像产物：

```bash
~/rk3588_build/build/output/images/
```

常见产物：

```text
EasePi-R2-debian-trixie-current-minimal.img
EasePi-R2-debian-trixie-current-minimal.img.xz
EasePi-R2-debian-trixie-current-minimal.img.xz.sha256
```

---

## 五、登录账户说明

编译 Debian BSP 打包镜像时，脚本会要求你在构建时设置 root 密码，并提示输入两次。

也可以通过环境变量提前传入 root 密码：

```bash
ROOT_PASSWORD='你的root密码' bash build-bsp-image.sh debian trixie current minimal
```

如果要创建普通 sudo 用户：

```bash
CREATE_USER=yes IMAGE_USER=fk IMAGE_PASSWORD='你的用户密码' ROOT_PASSWORD='你的root密码' \
  bash build-bsp-image.sh debian trixie current minimal
```

Armbian 原生镜像构建按 Armbian 自身流程处理首次登录账户。

---

## 六、脚本工作流程

`build-bsp-image.sh` 会依次调用：

```text
scripts/00-env.sh           检查依赖和目录
scripts/10-build-bsp.sh     使用 Armbian build 编译 U-Boot / Kernel / DTB
scripts/20-make-rootfs.sh   使用 debootstrap 生成 Debian arm64 rootfs
scripts/30-install-bsp.sh   安装 Kernel / DTB / modules，写入账号、网络、启动配置
scripts/40-pack-image.sh    创建 GPT 分区镜像，写入 U-Boot，压缩 img
```

分区结构：

```text
GPT
├── p1  FAT32  256MB  /boot
└── p2  ext4   剩余   /
```

启动文件：

```text
/boot/armbianEnv.txt
/boot/boot.scr
/boot/boot.cmd
/boot/extlinux/extlinux.conf     # 找不到 Armbian boot-rk35xx.cmd 时作为备用
/boot/vmlinuz
/boot/initrd.img
/boot/uInitrd                    # 由 initrd.img 生成，兼容部分 U-Boot 启动流程
/boot/dtb/rockchip/rk3588-easepi-r2.dtb
```

---

## 七、BSP 缓存和重新编译

BSP deb 包会缓存到：

```text
output/bsp/current/
output/bsp/edge/
output/bsp/vendor/
```

如果已经有对应 BSP，脚本会优先复用，避免每次都重新编译内核。

强制重新编译 BSP：

```bash
FORCE_BSP_REBUILD=yes bash build-bsp-image.sh debian trixie current minimal
```

清理输出：

```bash
sudo rm -rf output/rootfs output/images
```

清理全部缓存：

```bash
sudo rm -rf output work
```

---

## 八、常用环境变量

| 变量                | 说明                      | 示例                       |
| ------------------- | ------------------------- | -------------------------- |
| `ARMBIAN_BUILD_DIR` | 指定 Armbian Build 目录   | `/root/rk3588_build/build` |
| `CPUTHREADS`        | 指定编译线程数            | `8`                        |
| `REGIONAL_MIRROR`   | 指定区域镜像策略          | `china`                    |
| `MAINLINE_MIRROR`   | 指定主线内核镜像          | `google` / `tuna` / `bfsu` |
| `UBOOT_MIRROR`      | 指定 U-Boot 源            | `github` / `gitee`         |
| `IMAGE_SIZE_MB`     | 指定最终镜像大小          | `8192`                     |
| `BOOT_SIZE_MB`      | 指定 boot 分区大小        | `512`                      |
| `ROOT_PASSWORD`     | Debian BSP 镜像 root 密码 | 自定义                     |
| `CREATE_USER`       | 是否创建普通用户          | `yes` / `no`               |
| `IMAGE_USER`        | 普通用户名                | `fk`                       |
| `IMAGE_PASSWORD`    | 普通用户密码              | 自定义                     |

示例：

```bash
CPUTHREADS=8 bash build.sh current trixie minimal
```

```bash
ROOT_PASSWORD='123456' IMAGE_SIZE_MB=8192 \
  bash build-bsp-image.sh debian trixie current minimal
```

---

## 九、注意事项

1. `current` 和 `edge` 默认使用项目里的主线 U-Boot 适配。
2. `vendor` 使用 Armbian rk35xx family 的厂商 U-Boot / 内核路线。
3. `minimal` 是最小化镜像，`server` 会额外安装网络、容器、路由相关常用组件。
4. `desktop` 主要用于 Armbian 原生镜像，Debian BSP 打包镜像默认只保留 `minimal / server`。
5. 首次编译耗时较长，后续会优先复用 BSP 缓存。
6. 不建议在 WSL 下编译，推荐使用原生 Linux 或 Linux 虚拟机。

---

## 十、硬件检测脚本

镜像启动后，可以运行硬件检测脚本：

```bash
sudo bash easepi-r2-hardware-test.sh
```

也可以在线执行：

```bash
bash -c "$(curl -fsSL 'https://raw.githubusercontent.com/fk1124/EasePi-R2-Debian-Build/refs/heads/main/easepi-r2-hardware-test.sh')"
```

重点看：

```text
有线网卡 / Wi-Fi / 蓝牙
默认路由 / 网络管理器
HDMI / 音频 / 红外
/dev/dri / GPU 内核模块 / Mesa / Vulkan
VPU / NPU 节点
eMMC / TF / USB / PCIe
```

---

## 十一、刷写镜像

以 `.img.xz` 为例：

```bash
xz -dk output/images/EasePi-R2-debian-trixie-current-minimal.img.xz
sudo dd if=output/images/EasePi-R2-debian-trixie-current-minimal.img of=/dev/sdX bs=4M status=progress conv=fsync
```

其中 `/dev/sdX` 要替换成你的 TF 卡、U 盘或 eMMC 对应设备。

写入前务必确认设备名，避免误写系统盘。

---

## 十二、建议当前验证顺序

建议先不要同时扩展太多场景，按下面顺序验证：

```text
1. Armbian Debian 13 current minimal 是否能稳定编译、启动
2. Debian 13 current minimal BSP 打包镜像是否能稳定编译、启动
3. 有线网卡、Wi-Fi、GPU、HDMI 是否正常
4. 再测试 edge / vendor 分支
5. 最后再扩展 server / desktop 场景
```
