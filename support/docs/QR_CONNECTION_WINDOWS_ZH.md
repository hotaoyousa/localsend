# 新版扫码连接：Windows 本地编译

新版源码在 `feat/qr-device-discovery` 分支。包含独立「扫码连接」导航、手机扫码发送/接收，以及 A 发送、B 接收的双电脑连接流程。当前版本还包含扫码收件接受/拒绝、独立的扫码连接自动保存开关、实际保存路径显示，以及固定2×2排列和平滑扫码发送过渡。

预编译安装包：[扫码收件确认测试版](https://github.com/hotaoyousa/localsend/releases/tag/qr-receive-20261020)，包含本次 Windows x64 EXE。

## 准备环境

在 Windows x64 电脑上准备：

- Git。
- Flutter **3.41.9**（使用 FVM 时先执行 `fvm install`；也可直接将此版本的 Flutter 加入 PATH）。
- Rust/rustup，项目的 `rust-toolchain.toml` 固定使用 **1.97.1**。
- Visual Studio 的 **Desktop development with C++ / 使用 C++ 的桌面开发**工作负载。
- Windows SDK，包含 `makepri.exe` 和 `makeappx.exe`。

首次构建需要联网下载项目依赖。建议把源码放在较短的路径，例如 `C:\src\localsend`。

## 获取本次源码

第一次克隆：

```powershell
git -c core.longpaths=true clone --branch feat/qr-device-discovery --single-branch https://github.com/hotaoyousa/localsend.git
cd localsend
```

已克隆的仓库：

```powershell
git fetch origin
git switch feat/qr-device-discovery
git pull --ff-only
```

## 编译并打包

从仓库根目录执行：

```powershell
powershell -ExecutionPolicy Bypass -File support\scripts\build_qr_connection_windows.ps1
```

脚本会构建 Windows MSIX 辅助资源、同步 Flutter 依赖、编译 Release，并打包便携 ZIP。它使用可用的 FVM，或 PATH 中的 Flutter；不会上传源码或产物。

输出文件：

```text
dist\qr-connection-20261020\LocalSend-1.18.2-qr-connection-windows-x64.zip
```

解压整个 ZIP 后运行 `localsend_app.exe`，请保留同目录下的 DLL 和 `data` 目录。

如果 Flutter 报环境缺失，先运行 `flutter doctor -v`；使用 FVM 时运行 `fvm flutter doctor -v`。

## 验证新功能

1. Windows 与另一台电脑都进入「扫码连接」，选择手机所在局域网对应的二维码。
2. 手机选择「连接电脑」，先扫描 A（发送端），再扫描 B（接收端）。
3. 建立连接后，B 等待接收，A 自动进入添加文件界面，无需再次选择角色。
4. 在 A 选择文件并发送，在 B 点击接受后确认文件实际收到；也可先在 B 的设置 → 接收开启「扫码连接自动保存」跳过确认。
5. 设置中的保存目录应显示完整实际路径，核对收件位置。

本次源码已通过 176 项 Flutter 测试与静态分析；Android/macOS 已构建，Windows x64 无签名安装程序已在 [GitHub Windows 工作流](https://github.com/hotaoyousa/localsend/actions/runs/39394781583) 编译成功。真实三设备文件收件仍需实机验收。
