# EC25 Manager for macOS (a vibe coding project)

**本项目仅为个人实验用途，严禁用于各类违法用途。使用工具请后果自负。程序完全使用开放的接口实现，没有进行任何逆向研究。**

一个面向移远 Quectel EC25 / Baiwang USB Modem 的 **原生 macOS 菜单栏应用**（Swift + AppKit），
通过 `libusb` 直接访问 AT 接口。相比早期的 Electron 版本，安装包从约 250 MB 降到 **~2.4 MB**，
内存/CPU 占用大幅降低，无浏览器、无 Node、无独立 helper 进程。

## 架构

```
┌─────────────────────────────────────────────┐   libusb   ┌──────────────┐
│  EC25 Manager.app  (Swift / AppKit 菜单栏)    │ ─────────► │  EC25 /      │
│  NSStatusItem + NSPopover                     │ ◄───────── │  Baiwang     │
│  Modem(@MainActor) ─ USBTransport ─ CEC25USB  │            │  2c7c:0125   │
└─────────────────────────────────────────────┘            └──────────────┘
```

- 纯原生：`NSStatusItem` + `NSPopover`，无 SwiftUI 依赖（命令行工具链下可直接构建）。
- USB 阻塞 I/O 跑在独立串行队列，界面永不卡顿；直接链接 `CEC25USB`（复用的 C/libusb 层），**无独立进程**。
- **IOKit 事件驱动的 USB 在位检测**（非轮询），插拔即时响应、空闲 CPU 近 0，实现无缝自动隐藏/显示菜单栏图标。
- 登录项走 `SMAppService`（仅打包后注册）。

## 功能

- 启动自动连接 `2c7c:0125`，自动扫描可响应 `AT` 的 bulk 接口
- **概览**：信号（RSRP/RSRQ/SINR/信号格）、运营商、2G/3G/4G/5G、注册状态、IMEI/IMSI/ICCID、
  频段/信道(EARFCN)/下行频率、调制、模组温度（全部传感器 + 平均）、载波聚合/服务小区，字段可自选
- **短信中心**：按发件人分组的会话 + 气泡对话，UCS2 中文收发（DCS=8）、删除、未读指示与一键已读；本机发出的短信本地留存
- **AT 终端**：输入 + 快捷命令
- **设置**：USB 网络模式、APN、重新搜索/重连/重启、开机自启、轮询间隔、休眠唤醒重启模块、仅在连接时显示图标

## 运行（开发）

```bash
brew install libusb
swift build -c release
.build/release/EC25Manager        # 菜单栏出现图标
```

## 打包为 .app

```bash
Tools/package_app.sh              # -> dist/EC25 Manager.app（~2.4MB，内嵌 libusb，ad-hoc 签名）
Tools/make_release.sh             # 额外产出 dmg / zip / SHA256SUMS.txt
```

打包脚本会：release 构建 → 生成 `EC25Manager.icns` → 组装 bundle、内嵌 `libusb-1.0.0.dylib` 并改写 `@rpath` →
写入菜单栏应用（`LSUIElement`）的 `Info.plist` → 本地 ad-hoc 签名。

## 初始化序列

连接后依次执行：`AT` · `ATE0` · `AT+CMEE=2` · `AT+CMGF=1` · `AT+CSCS="UCS2"` · `AT+CNMI=2,1,0,0,0`。
不同固件/运营商的短信存储、字符集、号码格式可能略有差异，可在「终端 / 实时状态」中微调。

## 说明

应用为本地 ad-hoc 签名、未做 Apple 公证；从 GitHub 下载后首次打开需右键→打开
（或 `xattr -dr com.apple.quarantine "/Applications/EC25 Manager.app"`）。仅 Apple Silicon。
