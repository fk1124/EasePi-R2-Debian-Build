# Linux 7.0 Build Profile

`linux7` is a public EasePi-R2 build profile for the stable upstream Linux 7.0 kernel.

Internally it maps to Armbian's `edge` branch, but pins:

```text
KERNEL_MAJOR_MINOR=7.0
KERNELBRANCH=branch:linux-7.0.y
KERNELPATCHDIR=archive/rockchip64-7.0
```

This keeps the Linux 7.0 workflow separate from the normal `edge` workflow if Armbian later moves `edge` to a newer kernel.

Debian BSP image:

```bash
bash build-bsp-image.sh debian trixie linux7 minimal
bash build-bsp-image.sh debian trixie linux7 server
```

Native Armbian image:

```bash
bash build.sh linux7 trixie minimal
bash build.sh linux7 trixie server
```

GPU userspace follows the mainline path: `panthor` plus Mesa packages. The Rockchip vendor `libmali` package is only used by the `vendor` kernel profile.
