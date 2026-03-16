# RK3308BS UNIHIKER M10 Linux SDK

[English](README.md)

基于 Rockchip Linux SDK 定制裁剪的 **RK3308BS + Debian 12 (bookworm)** SDK，目标硬件为 DFRobot UNIHIKER M10 开发板：

- 启动链路：`MiniLoaderAll.bin` → U-Boot → Linux 6.1 → Debian rootfs
- 分区方案：**仅 GPT**（boot + rootfs），无 oem/userdata 分区
- 根文件系统：Debian bookworm 最小化（纯控制台，无 GUI）

---
## 安装

**推荐方式（一步克隆含所有子模块）：**

```bash
git clone --recursive https://github.com/fary99/unihikerM10-bsp.git
cd unihikerM10-bsp
```

**如果克隆时未使用 `--recursive`，手动初始化子模块：**

```bash
git clone https://github.com/fary99/unihikerM10-bsp.git
cd unihikerM10-bsp
git submodule update --init --recursive
```


## 目录结构

- `kernel/` — Linux 6.1 内核源码（`unihikerM10_linux_defconfig`、`rk3308bs-unihikerM10.dts`）
- `u-boot/` — U-Boot 及 loader 输出（`MiniLoaderAll.bin`、`uboot.img`、`trust.img`）
- `debian/` — Debian 根文件系统构建脚本和 overlay
- `device/rockchip/.chips/rk3308/` — 板级配置
  - `dfrobot_unihikerM10_defconfig` — SDK defconfig
  - `parameter-64bit-debian.txt` — **GPT 分区表**（uboot/trust/misc/boot/rootfs）
- `device/rockchip/common/` — 公共构建脚本和钩子
  - `build-hooks/` — 顶层构建入口（`99-all.sh` 按顺序执行 loader → kernel → rootfs → firmware）
  - `post-hooks/` — rootfs 后处理步骤
  - `scripts/` — `mk-kernel.sh`、`mk-rootfs.sh`、`mk-firmware.sh` 等

---

## 编译环境和依赖

推荐系统：Ubuntu 20.04/22.04 x86_64。

### 必要软件包

```bash
sudo apt-get update
sudo apt-get install git ssh make gcc libssl-dev \
     liblz4-tool expect expect-dev g++ patchelf chrpath gawk texinfo chrpath \
     diffstat binfmt-support qemu-user-static live-build bison flex fakeroot \
     cmake gcc-multilib g++-multilib unzip device-tree-compiler ncurses-dev \
     libgucharmap-2-90-dev bzip2 expat gpgv2 cpp-aarch64-linux-gnu libgmp-dev \
     libmpc-dev bc python-is-python3 python2
```

> Debian rootfs 内的软件包由 `mk-rootfs-bookworm.sh` 在 chroot 内通过 `apt-get` 安装。

### 交叉编译工具链（需单独下载）

本仓库**不包含**预编译的交叉工具链，需从 Arm 官方下载：

- **Arm GNU Toolchain 10.3-2021.07**（AArch64 bare-metal）
- 下载页面（请检查最新链接）：`https://developer.arm.com/downloads/-/arm-gnu-toolchain-downloads`

解压到以下目录：

- `prebuilts/gcc/linux-x86/aarch64/gcc-arm-10.3-2021.07-x86_64-aarch64-none-linux-gnu/`

该目录下须包含 `bin/aarch64-none-linux-gnu-gcc` 等编译器文件，`build.sh` 会自动从此路径查找工具链。目录结构示例：

```
prebuilts/
└── gcc
    └── linux-x86
        ├── aarch64
        │   └── gcc-arm-10.3-2021.07-x86_64-aarch64-none-linux-gnu
        │       ├── bin
        │       │   ├── aarch64-none-linux-gnu-gcc
        │       │   └── ...
        │       ├── aarch64-none-linux-gnu/
        │       ├── readme.txt
        │       └── ...
        └── arm
            └── gcc-arm-10.3-2021.07-x86_64-arm-none-linux-gnueabihf
                └── ...
```

---

## 编译

### 1. 完整编译（推荐）

```bash
./build.sh           # 等同于 ./build.sh all
```

### 2. 单独编译各组件

- **仅编译 U-Boot + Loader：**

```bash
./build.sh uboot
```

- **仅编译内核：**

```bash
./build.sh kernel
```

- **仅编译 Debian rootfs (bookworm)：**

```bash
./build.sh debian
```

完整编译或部分编译后的产物：

- 内核：`kernel/boot.img`、`kernel/arch/arm64/boot/dts/rockchip/rk3308bs-unihikerM10.dtb`
- 根文件系统：`debian/unihiker-rootfs.img`

完整编译按以下顺序执行：

1. Loader / U-Boot（`mk-loader.sh`）
2. 内核（`mk-kernel.sh` → `boot.img`）
3. Debian rootfs（`mk-rootfs.sh` → `mk-rootfs-bookworm.sh`）
4. 固件打包（`mk-firmware.sh`）
5. 整包镜像打包（`mk-updateimg.sh` → `update.img`）

输出镜像目录：

```
output/firmware/   （同时链接为 rockdev/）
```

典型内容：

- `MiniLoaderAll.bin` — Loader
- `uboot.img` — U-Boot
- `trust.img` — Trust 固件
- `boot.img` — 内核（+ initramfs，如有）
- `rootfs.img` — Debian 根文件系统
- `misc.img` — misc 分区
- `parameter.txt` — 分区表（GPT，来自 `parameter-64bit-debian.txt`）
- `update.img` — Rockchip 整包烧录镜像（包含上述所有分区）

---

## Debian rootfs 默认配置

`debian/mk-rootfs-bookworm.sh` 在 chroot 中进行以下定制：

- **默认用户**
  - 用户名：`unihiker`
  - 密码：`dfrobot`
  - 所属组：`root`、`sudo`、`audio`、`video`、`plugdev`、`netdev`、`dialout`、`tty`、`gpio`
- **主机名 / 网络**
  - 主机名：`unihiker`
  - `/etc/hosts`：`127.0.1.1    unihiker`
  - APT 源：Debian 官方（`deb.debian.org`）
  - DNS：`8.8.8.8`
- **预装软件**
  - SSH：`openssh-server`、`openssh-client`
  - WiFi/蓝牙：`wpasupplicant`、`iw`、`network-manager`、`bluez`
  - 网络工具：`net-tools`（如 ifconfig）
  - 触屏调试：`evtest`
- **其他**
  - 用户 PATH 包含 `/sbin`、`/usr/sbin`
  - USB RNDIS/ECM 虚拟网卡（`usb-rndis-ether.service`）
  - 系统休眠已禁用（`/etc/systemd/logind.conf.d/disable-sleep.conf`）

---

## 分区与烧录（GPT）

分区定义文件：`device/rockchip/.chips/rk3308/parameter-64bit-debian.txt`

- 分区：`uboot`、`trust`、`misc`、`boot`、`rootfs (grow)`
- 仅使用 GPT，无 oem/userdata
- rootfs 可自动扩展填满剩余空间

烧录工具使用 SDK 自带的 **upgrade_tool**（Rockchip 命令行开发工具）：

```
tools/linux/Linux_Upgrade_Tool/Linux_Upgrade_Tool/upgrade_tool
```

> 详细用法参见同目录下的《命令行开发工具使用文档.pdf》。

**首次使用前，建议将 upgrade_tool 安装到系统路径（一次性操作）：**

```bash
sudo cp tools/linux/Linux_Upgrade_Tool/Linux_Upgrade_Tool/upgrade_tool /usr/local/bin/
sudo chmod +x /usr/local/bin/upgrade_tool
```

安装后即可在任意目录直接使用 `sudo upgrade_tool` 命令，无需每次输入完整路径。

### 方式一：整包烧录（update.img，推荐）

`update.img` 包含 loader、parameter、所有分区镜像，一次烧录即可完成整个系统写入。

**单独构建 update.img：**

```bash
./build.sh updateimg
```

> `./build.sh all` 会在最后自动生成 `update.img`，无需单独执行。

**烧录步骤：**

```bash
# 1. 板子进入 Maskrom 模式（按住 Maskrom 键上电）
# 2. 查看设备是否识别
sudo upgrade_tool ld

# 3. 整包烧录（自动下载 Boot + 写入所有分区）
sudo upgrade_tool uf output/firmware/update.img
```

### 方式二：分区单独烧录

适合开发调试时只更新某个分区，无需重新烧录整个系统。

```bash
# 板子进入 Maskrom 模式，下载 Boot
sudo upgrade_tool db output/firmware/MiniLoaderAll.bin

# 烧录 Loader（写入 IDBlock）
sudo upgrade_tool ul output/firmware/MiniLoaderAll.bin

# 烧录分区表
sudo upgrade_tool di -p output/firmware/parameter.txt

# 烧录各分区镜像（-u/-t/-m/-b 为内置缩写，rootfs 用分区名指定）
sudo upgrade_tool di -u output/firmware/uboot.img
sudo upgrade_tool di -t output/firmware/trust.img
sudo upgrade_tool di -m output/firmware/misc.img
sudo upgrade_tool di -b output/firmware/boot.img
sudo upgrade_tool di -rootfs output/firmware/rootfs.img
```

**常用分区缩写：**

| 缩写 | 分区名 |
|------|--------|
| `-u` | uboot |
| `-t` | trust |
| `-m` | misc |
| `-b` | boot |
| `-k` | kernel |
| `-r` | recovery |

> 没有内置缩写的分区（如 rootfs），使用 `-分区名` 格式：`-rootfs rootfs.img`。

---

## 常见问题

- **Q：`update.img` 和分区单独烧录有什么区别？**
  A：`update.img` 是 Rockchip 标准打包格式，包含所有分区，一条命令即可完成整个系统烧录，适合量产和首次刷机。分区单独烧录适合开发调试时只更新某个分区（如只刷 `boot.img` 或 `rootfs.img`）。

- **Q：如何只重新生成 update.img 而不重新编译？**
  A：确保 `output/firmware/` 下已有各分区镜像，然后运行 `./build.sh updateimg`。

---

## 反馈与贡献

本 SDK 是针对 UNIHIKER M10 定制裁剪的 Rockchip Linux SDK 子集。如有问题或改进建议：

- 在项目仓库提交 Issue 或 Pull Request，或
- 联系硬件厂商（DFRobot）获取支持。

---

## 许可证

本 SDK 包含多个不同许可证的组件：

- **Linux 内核**（`kernel/`）— [GPL-2.0-only](https://www.gnu.org/licenses/old-licenses/gpl-2.0.html)，附 Linux-syscall-note 例外
- **U-Boot**（`u-boot/`）— [GPL-2.0+](https://www.gnu.org/licenses/old-licenses/gpl-2.0.html)
- **构建脚本及板级配置**（`device/`、`debian/` 等）— [GPL-2.0](https://www.gnu.org/licenses/old-licenses/gpl-2.0.html)

本项目整体基于 **GNU 通用公共许可证第 2 版（GPL v2.0）** 发布。完整许可证文本见 [LICENSE](LICENSE)。

```
SPDX-License-Identifier: GPL-2.0
```
