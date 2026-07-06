# EC25 Manager for macOS (a vibe coding project)

**本项目仅为个人实验用途，严禁用于各类违法用途。使用工具请后果自负。程序完全使用开放的接口实现，没有进行任何逆向研究。**

一个面向移远 Quectel EC25 / Baiwang USB Modem 的 **macOS 菜单栏（menu bar）管理工具**，使用 Electron 构建 GUI，底层通过原生
`libusb` 直接访问 AT bulk 接口。

## 架构

```
┌──────────────────────────┐   JSON over stdio   ┌────────────────────────┐   libusb   ┌──────────┐
│  Electron (菜单栏 + 弹窗)  │ ──────────────────► │  EC25Helper (Swift CLI) │ ─────────► │  EC25 /  │
│  main.js / renderer / IPC │ ◄────────────────── │  CEC25USB (C shim)      │ ◄───────── │  Baiwang │
└──────────────────────────┘                     └────────────────────────┘            └──────────┘
```

- **Electron 前端**（`app/`）：菜单栏托盘图标 + 弹出式窗口，所有 AT 编排与解析在主进程 `src/modem.js` 中完成。
- **Swift 助手**（`Sources/EC25Helper`）：一个精简的 USB/AT 传输进程，复用经过验证的 `CEC25USB` C 层，
  以「一行一个 JSON」的协议在 stdin/stdout 上通信。USB 阻塞 I/O 全部发生在这个独立进程，界面永不卡顿。

## 功能

- 启动后自动通过原生 `libusb` 连接 `2c7c:0125`，自动扫描可响应 `AT` 的 bulk IN/OUT 接口（不依赖物理 USB 口或扩展坞位置）
- **概览**：美观的信号强度（信号格 + dBm）、运营商、网络制式（2G/3G/4G）、注册状态、数据网络类型、
  IMEI、IMSI、ICCID、本机号码、SIM 状态等许多信息
- **短信中心**：读取短信列表、UCS2 中文短信收发、删除短信、轮询
- **AT 终端**：内置终端 + 常用命令快捷标签
- **系统设置**：USB 网络模式切换（ECM / QMI / MBIM / RNDIS）、APN 配置、重新搜索网络、重启模块、重连设备
- 顶部实时连接状态，可选的状态轮询周期 / 注册信息

## 运行（开发）

```bash
# 1. 依赖：Homebrew libusb + Node.js
brew install libusb

# 2. 构建 Swift 助手
swift build -c release

# 3. 安装 Electron 并启动
cd app && npm install && npm start
```

> 若 `npm install` 因沙箱拦截安装脚本而没有下载 Electron 运行时，执行
> `node node_modules/electron/install.js`（或用 `ditto -x -k <缓存zip> node_modules/electron/dist` 手动解压）。

## 打包为 .app

```bash
Tools/package_electron.sh
```

产物位于：

```text
dist/EC25 Manager.app
```

脚本会：release 构建 Swift 助手 → 生成图标 → 以 Electron 运行时为模板组装 bundle →
把 `EC25Helper` 与 `libusb-1.0.0.dylib` 内嵌到 `Contents/Resources/bin/` 并改写 `@rpath` →
写入菜单栏应用（`LSUIElement`）的 `Info.plist` → 本地 ad-hoc 签名。

## 初始化序列

连接后助手会依次执行：

```text
AT
ATE0
AT+CMEE=2
AT+CMGF=1
AT+CSCS="UCS2"
AT+CNMI=2,1,0,0,0
```

不同固件或运营商 SIM 的短信存储、字符集、收件号码格式可能略有差异

## macOS 网络模式

如果模块已切到 macOS 可识别的 ECM 模式，`AT+QCFG="usbnet"` 通常显示 `1`；在「设置」页可切换该值，
切换后一般需要 `AT+CFUN=1,1` 或断电重插让 USB 重新枚举。菜单栏应用会自动探测 `192.168.225.x` 的 ECM 网卡并在设置页提示。
