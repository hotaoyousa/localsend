## 当前已验证状态

- 仓库根目录：`/Users/hutao/Desktop/localsend/localsend`
- 标准启动路径：`cd app && fvm flutter run`
- 标准验证路径：
  - `cd app && fvm flutter analyze`
  - `cd app && fvm flutter test`
  - `cd packages/core && cargo check --features full`
- 当前功能：`phone_receive-001` 代码与自动化验证已完成，等待 Android 真机端到端验收；`phone_receive-002` 的二维码端实现及自动化已完成，真实反向发送验收依赖前者。
- 当前 blocker：ADB 当前没有连接设备，无法执行“手机扫码并接收 → 二维码端收到 IP → 选择文件发回 → 手机实际收件”的真机闭环。

## 会话记录

### Session 001

- 日期：
- 本轮目标：
- 已完成：
- 运行过的验证：
- 已记录证据：
- 提交记录：
- 更新过的文件或工件：
- 已知风险或未解决问题：
- 下一步最佳动作：

### Session 002

- 日期：
- 本轮目标：
- 已完成：
- 运行过的验证：
- 已记录证据：
- 提交记录：
- 更新过的文件或工件：
- 已知风险或未解决问题：
- 下一步最佳动作：
### 2026-09-30 — 基线与 scan-001

- 当前功能：scan-001 已通过自动化入口验收，开始 scan-002。
- 已完成：恢复 FVM/Flutter 3.41.9、Rust 1.97.1；修复 init.sh 执行权限；扫码入口移至手动 IP 按钮旁。
- 修改：init.sh（执行位）、send_tab.dart、qr_scan_page_test.dart、feature_list.json。保留用户 AGENTS.md 原文。
- 验证：./init.sh 成功；flutter analyze 无问题；原有80项 Flutter 测试通过；cargo check --features full 通过；新增入口验证后扫码页面7项测试通过。
- 发现：现有扫码结果只保留 IP，发送必须保留二维码端口及协议，并复用手动 IP 注册与 sendProvider。
- 环境：本地缓存位于仓库外的 ../.tooling；执行命令前可 source ../.tooling/env.sh。
- 待验证：Android/iOS 真机相机；目前 adb 未检测到 USB 手机。
- 下一步：scan-002 解析并返回完整连接信息。

### 2026-09-30 — scan-002 自动化验证

- 已完成：QrConnectionInfo 保留 IP/端口/协议；扫码结果确认后返回连接信息，停止相机并阻止重复结果。
- 修改：qr_connection_info.dart（替代仅解析 IP 的 helper）、qr_scan_page.dart、对应解析及页面测试。
- 验证：解析与页面测试13项通过。原生相机识码尚未验证，因此 scan-002 暂记 blocked，不记 passing。
- 阻塞：adb 尚未检测到手机，用户已表示有 Android 和接收设备；Android SDK 已准备。
- 当前唯一开发功能：scan-003，连接现有手动 IP 注册、文件选择及发送链路；完成后集中进行真机端到端验收。

### 2026-09-30 — scan-003 实现与原生验收准备

- 已实现：扫码确认返回完整地址，复用 AddressInputDialog 注册目标；无已选文件时打开原有选择器，再调用 sendProvider.startSession；保留手动 IP 行为和原有传输协议。
- 修改：send_tab_vm.dart、address_input_dialog.dart、扫码页与解析 helper、英文及简繁中文文案和生成文件、iOS 相机权限说明、对应测试。
- 验证：完整 Flutter 测试95项通过；本轮 ./init.sh 成功、扫码相关冒烟23项通过、flutter analyze 无问题、git diff --check 通过。自动化覆盖 Android/iOS 选择文件、已有文件、取消、目标不可达；网络和相机使用替身，不能证明真机收件。
- 真机：ADB 已连接 Android 23049RAD8C；接收端为此 Mac，二维码为 http://10.29.252.119:53317；手机到 Mac ping 成功，Mac /api/localsend/v2/info 返回协议2.2。
- 测试文件：../.tooling/verification/localsend-qr-test.txt 已推送手机 Download，92字节，不含用户数据。
- 原生构建：Android debug（独立 .debug 包名）进行中。iOS 已补齐 CocoaPods；常规构建被 Xcode27 对旧部署目标的限制阻塞，正通过 xcodebuild 命令参数 IPHONEOS_DEPLOYMENT_TARGET=15.0 验证，未修改项目支持版本。
- 下一步：完成 Android 构建、安装、摄像头扫 Mac 二维码并发送测试文件；核对 Mac 实际接收内容后才能标记验收通过。代码未提交或推送。

- iOS 后续结果：xcodebuild 无签名构建成功（BUILD SUCCEEDED）。仅命令覆盖 IPHONEOS_DEPLOYMENT_TARGET=15.0，并通过 ../.tooling/xcode-bin/xcrun 为 Dart native hook 指定 SDK；未修改全局 xcode-select 或项目最低版本。相机插件原生代码编译通过，不代表 iPhone 真机相机验收。pod install 同步了 Podfile.lock，新增 mobile_scanner，并将原先滞后的 open_filex 项同步为 pubspec 已有的 open_file_ios。

- Android 后续结果：fvm flutter build apk --debug --target-platform android-arm64 --no-pub 成功（631.5秒）；ADB install 返回 Success。安装包 app/build/app/outputs/flutter-apk/app-debug.apk；手机应用名 LocalSend Debug，包名 org.localsend.localsend_app.debug，未覆盖正式版。接收 Mac 正式版为1.18.2。已请用户实际扫描并选择测试文件发送，尚未收到验收结果。构建及测试日志已保存 ../.tooling/verification。

- 真机当前证据：11:31:47 相机关闭后，Android 日志显示连接二维码地址 10.29.252.119:53317；11:31:58 目标为 Mac 的3字节文本会话进入 SessionStatus.finished，无错误。尚未验证准备的92字节测试文件落盘，不能标记 scan-003 passing。已提示用户选择「文件」发送 Download/localsend-qr-test.txt；后续检查 Mac 接收文件并与 ../.tooling/verification/localsend-qr-test.txt 比较内容。扫码相机行为及最终收件仍等待用户反馈。

- 人工补充：扫码发送功能在安卓手机上基本实现。但是传输速度太慢了，需要测试走的什么传输链路，有没有保留原有传输。

### 2026-09-30 — 扫码连接错误与性能诊断续作

- 范围：只处理扫码发送连接错误与速度；按用户要求不实现 phone_receive，不修改其功能清单。
- 基线：重新读取 AGENTS.md、进度、功能列表及 Git 状态；./init.sh 成功。发现上次审批额度中断导致翻译字段缺失、页面无法编译，已补齐恢复。
- 修复：新增 qrDiscoveryClientProvider，在 Rust HTTP 客户端设置扫码注册请求5秒总超时；上传仍使用原有 pinned client，不受该超时影响。补齐英/简繁中文网络排查提示、重试按钮，重试清除旧错误。
- 修改：http_provider.dart、address_input_dialog.dart、四个 i18n 源文件及生成文件、qr_scan_page_test.dart。未更改传输协议、校验和或缓冲区。
- 验证：完整95项 Flutter 测试通过，flutter analyze --no-pub 无问题；Android debug APK 构建成功（29.8秒），adb install -r Success。补充失败后重试恢复到选文件的测试。app/packages diff whitespace 检查通过；AGENTS.md 用户原有行28尾空白未改。
- 真机网络：Android 10.29.14.253 经 wlan0 直达 Mac 10.29.252.119，同为10.29/16；3次 ping 成功，平均22.48ms。当前没有复现 os error113，因此不能断言该错误的具体路由原因已修复。
- 链路确认：扫码 -> AddressInputDialog 注册 -> 原有 SendNotifier.startSession -> HttpUploadFilesTask -> Rust /api/localsend/v2/upload；不经过网页中转，HTTP client 已有 no_proxy。
- 性能证据：真机历史207426字节图片上传阶段约2.66秒，文件读取22ms；独立测试绕过 LocalSend，用 Android toybox nc 将16 MiB零数据直接发送至 Mac 临时 TCP 接收端，耗时161.803秒，0.099 MiB/s。测试结束端口已关闭。证明当前链路在应用之外也慢，尚不能区分校园网限速、丢包或接入点原因。
- 下一步/阻塞：已请用户将两端切到同一私人 Wi-Fi 或热点并刷新二维码，再复测 TCP 与扫码发送；尚未确认速度恢复，不标记 scan-003 passing。代码留在 feat/qr-device-discovery，未提交推送。

- 用户表示已切换网络并打开二维码后的复测：ADB 设备列表为空，Mac en0 仍为10.29.252.119；LocalSend UI 读取被系统锁屏阻止。已请用户解锁、重新连接 USB 并确认 Mac 也在新热点，尚未进行第二组吞吐测试。

### 2026-09-30 — 换网复测准备

- 已按最新 AGENTS.md 重新读取进度、功能列表与 Git 状态，分支仍为 feat/qr-device-discovery。
- ./init.sh 成功；扫码解析与页面冒烟23项通过；app/packages diff 检查通过。未新增代码或涉及 phone_receive。
- Android USB 已恢复，当前热点地址192.168.146.6/24（wlan2）；Mac 全接口检查仅有校园网IPv4地址10.29.252.119/16（en0）。两端尚未同时切换到同一热点，不能开展有效的换网对照。
- 已请用户将 Mac 也加入同一热点，并刷新 LocalSend 二维码。下一步读取新地址、复测16 MiB TCP上传，再核对真实扫码文件收件与耗时。暂未标记验收完成。

### 2026-09-30 — 热点对照测速

- 两端已切到同一热点：Android 192.168.146.6，Mac 192.168.146.87；Mac LocalSend 当前二维码 http://192.168.146.87:53317 已目视确认。
- 同样16 MiB纯 TCP上传，热点耗时0.247秒（64.862 MiB/s），校园网161.803秒（0.099 MiB/s）；证据 ../.tooling/verification/tcp-hotspot-20260930.json。表明先前主要吞吐瓶颈来自网络路径，并非扫码新增传输协议。
- 已准备32 MiB确定性无敏感测试文件 localsend-qr-speed-32MiB.bin，推送 Android Download；已请用户通过 LocalSend Debug 真摄像头扫码并发送，待核对Mac收件内容及应用内耗时。

### 2026-09-30 — 热点真实扫码文件验收完成

- 用户确认通过扫码发送32 MiB测试文件；Mac Downloads/localsend-qr-speed-32MiB.bin 已收到，33554432字节，与测试源文件逐字节一致。
- Android会话日志：startTime 1790755610621，endTime 1790755611153，上传阶段0.532秒，约60.15 MiB/s，Transfer finished successfully。此时间不含扫码、选文件、校验和准备及接收确认。
- Android扫码发送验收通过；iOS仍仅完成此前无签名构建，没有iPhone真机验收。当前网络对照证据支持校园网路径瓶颈，具体QoS/丢包/隔离策略尚未由网管日志或抓包确认。

### 2026-09-30 — phone_receive 交接与实现续作

- 当前功能：`phone_receive-001`；`phone_receive-002` 的代码与自动化已实现，真机验收依赖 001。
- 先前记录：发现并解析了 dsh 会话 `~/.dsh/sessions/--Users-hutao-Desktop-localsend-localsend--/session-260f2d9d-1242-4073-bf70-49f179d737b9/session.v4.jsonl.zstd`。用户当时选择了“复用现有 register 宣告”和“弹窗确认后选文件发送”。指定的 `phone_receive.md` 在本机未找到，本次以 `feature_list.json` 中的两条 `phone_receive` 验收项和该会话为准。
- 已完成：手机扫码页新增“接收文件”；点击后按需启动本地服务器，并通过现有 v2 `register` 宣告本机 alias、端口、协议和指纹；展示请求中、等待、失败及重试状态。二维码端监听 `Register`，仅在二维码弹窗可见时把扫描设备交给 `qrShareProvider`；弹窗提示用户选择文件并复用原发送链路，未选文件时打开原有文件选择器。
- 修改：`app/lib/pages/qr_scan_page.dart`、`app/lib/provider/qr_share_provider.dart`、`app/lib/widget/dialogs/qr_send_request_prompt.dart`、`qr_dialog.dart`、`zoom_dialog.dart`、`app/lib/pages/web_share_page.dart`、`app/lib/provider/network/server/controller/receive_controller.dart`、相关 i18n/生成文件和测试。
- 验证：`./init.sh` 成功；`fvm flutter analyze --no-pub` 无问题；二维码相关 28 项测试通过；完整 Flutter 测试 104 项通过；`fvm dart format --output=none --set-exit-if-changed lib test` 通过（0 个文件变化）；`cargo check --features full` 通过；Android arm64 debug APK 构建成功。`git diff --check` 唯一失败仍为既有用户文件 `AGENTS.md` 第 28 行尾随空格。
- 补充覆盖：修正测试中的未使用 import、未等待 `showDialog`，并新增二维码端“没有预选文件时打开选择器，选择后再调用原发送链路”的验证。
- 阻塞：`adb devices -l` 无设备；macOS 桌面调试构建受本机 Xcode/Swift Package 缓存与权限环境限制，未完成。当前不能证明真机反向收件及 iOS 验收。
- 下一步：连接 Android 真机，安装 `app/build/app/outputs/flutter-apk/app-debug.apk`；在二维码端运行包含本改动的应用，打开接收页的链接二维码，手机扫码后点“接收文件”，二维码端选择确定性测试文件发回，核对手机实际落盘内容与哈希。

### 2026-10-01 — Windows 对齐与 macOS 本地测试包

- 当前功能：`phone_receive-001` 与 `phone_receive-002` 继续等待真机闭环；本轮完成 Windows 平台对齐验证和 macOS 本地安装包。
- Windows：项目没有独立的 Windows UI 实现；发送页、WebSharePage、QrDialog、QrSendRequestPrompt 和 ReceiveController 都是共享 Flutter/Dart 代码。Windows 会与 macOS 使用同一套二维码提示、桌面文件和发送流程，不需要新增原生页面。
- 平台覆盖：将二维码端“收到 register → 提示选择文件 → 打开桌面文件选择器 → 调用原发送流程”测试扩为 Android 与 Windows 两个 TargetPlatform 变体；Windows 变体通过。完整 Flutter 测试 105 项通过，`flutter analyze --no-pub` 无问题。
- macOS 本地包：在独立构建副本中使用官方 DockProgress/LaunchAtLogin 本地 Swift Package 源码，构建 arm64 Release 应用（macOS 12+，ad-hoc 本地签名）。未做 Developer ID 签名和 notarization。
- 工件：`dist/macos-arm64/LocalSend.app`、`dist/LocalSend-1.18.2-macos-arm64-local.dmg`、`dist/LocalSend-1.18.2-macos-arm64-local.zip`。
- 验证：应用隐藏启动成功，HttpServerIsolate 启动并通过 53317 监听；`codesign --verify --deep --strict` 通过；主可执行文件为 arm64；DMG checksum 与 ZIP 完整性验证通过。
- 校验和：DMG `5ce34d2283648d3dec98b9161f6b2da59292710ae3e554f1714225f52f11e94c`；ZIP `ffea3dfb98719a6cbac71566f65bc3e002250dae301de504cc99b5d1416059ca`。
- Windows 阻塞：当前主机是 macOS，Flutter 不支持从 macOS 交叉构建 Windows 桌面包，因此本轮只能完成共享源码与 Windows 平台变体验证，不能在此机生成 Windows EXE/MSIX/ZIP。
- Windows 下一步：在 Windows 开发机运行 `cd app && fvm flutter pub get && fvm flutter build windows`，产物位于 `app/build/windows/x64/runner/Release`；再执行二维码端反向发送真机/局域网验收。

### 2026-10-15 — 最新构建保留与空间清理

- 已保留并通过压缩包完整性检查：`dist/LocalSend-1.18.2-macos-arm64-local.dmg`、`dist/LocalSend-1.18.2-macos-arm64-local.zip`、`dist/android-arm64/LocalSend-1.18.2-android-arm64-debug.apk`。macOS 为10月1日本地 Release，Android 为9月30日最新 arm64 debug。
- 清理了 app/build、独立 macOS 副本中的 app/build 与 Dart 缓存、根 target；保留工作源码、独立副本源码和最新安装包。实际可用空间增加约 14.21 GiB。
- GitHub fork：hotaoyousa/localsend。远程读取成功，但 Release API 使用本机 Git 凭据返回 HTTP 401；安装包尚未上传，未创建 Release。
- 下一步：恢复有效的 GitHub 登录，然后上传上述三个安装包；本轮未修改或提交现有功能源码。

### 2026-10-20 — GitHub 登录恢复与构建上传完成

- GitHub CLI 浏览器授权成功，账号 hotaoyousa；fork 写入权限已验证，Git 已配置为使用 CLI 认证。CLI 路径：`../.tooling/github-cli/gh_2.102.0_macOS_arm64/bin/gh`。
- 三个保留安装包已上传并发布为预发布版本：https://github.com/hotaoyousa/localsend/releases/tag/local-build-1.18.2-20261001 。
- 服务端三个文件状态均为 uploaded，大小与本地完全一致：DMG 30502639、ZIP 26637741、APK 234582768 字节。
- 本地路径继续保留：`dist/LocalSend-1.18.2-macos-arm64-local.dmg`、`dist/LocalSend-1.18.2-macos-arm64-local.zip`、`dist/android-arm64/LocalSend-1.18.2-android-arm64-debug.apk`。
- Release 说明明确：标签基于 6f6cd3ee，不包含尚未提交的本地功能源码；现有源码改动未提交。此前清理释放约14.21 GiB，本轮未重新构建。

### 2026-10-20 — 手机协助双电脑连接

- 当前功能 desktop_pairing-001。Android 扫码页新增「连接两台电脑」入口，保留 A/B 地址、端口、协议、身份；拒绝重复电脑，分别展示结果，只重试未完成端。退出页面取消等待中的邀请。
- 通过现有 prepare-upload 元数据发送专用连接邀请；macOS/Windows 共用接收逻辑，仅二维码展示期间询问用户，确认后使用绑定对方证书的 HTTP 客户端直接 register；返回204表示直连成功，无文件字节经手机中转。未识别邀请的旧客户端不会被视为成功。
- 处理拒绝、超时、对端不可达和请求中止，保持原传输路径。邀请不转发二维码 PIN；手机仅将各自 PIN 用于邀请收件端。
- 修改：双电脑页面、配对 service/邀请数据模型、扫码页入口、ReceiveController、HTTP 客户端超时参数、二维码 PIN 解析、英/简繁中文文案和测试。
- 验证：./init.sh 与原扫码22项基线通过；完整 Flutter 测试123项通过。Android USB 无设备，真实三设备传输尚未验收。Android/macOS 构建正在进行；Windows 将运行 fork 的无签名构建工作流。
- 此提交也包含此前未提交的扫码/反向接收实现及对应测试，作为新功能依赖；保留用户 AGENTS.md 修改未提交。

### 2026-10-20 — 双电脑连接三平台构建与发布完成

- 实现已提交并推送到 `feat/qr-device-discovery`，代码提交 `965995a9`（主实现 `31e3129c`）；专用 Windows 无签名工作流 `build_desktop_pairing_windows.yml` 已接入分支推送。用户原有 AGENTS.md 修改未提交。
- 自动化：完整123项测试通过，静态分析无问题；最终文案修正后桌面对话框6项回归通过。macOS 独立便携配置与55319测试端口启动成功，/info返回2.2；正常及畸形邀请在未打开二维码时均403，随后服务仍可用。测试实例均已关闭。
- 构建完成：Android arm64 Debug APK；macOS arm64 Release，应用已重新进行 ad-hoc 深度签名并通过严格验证，DMG/ZIP完整性通过；Windows x64无签名安装程序，GitHub工作流 https://github.com/hotaoyousa/localsend/actions/runs/39361099755 成功（10分44秒）。macOS构建使用独立副本和 DEVELOPER_DIR 命令级覆盖；未改变系统 Xcode 选择。
- 本地工件：
  - `dist/desktop-pairing-20261020/LocalSend-1.18.2-phone-pairing-android-arm64-debug.apk`
  - `dist/desktop-pairing-20261020/LocalSend.app`
  - `dist/desktop-pairing-20261020/LocalSend-1.18.2-phone-pairing-macos-arm64.dmg`
  - `dist/desktop-pairing-20261020/LocalSend-1.18.2-phone-pairing-macos-arm64.zip`
  - `dist/desktop-pairing-20261020/LocalSend-1.18.2-phone-pairing-windows-x64.exe`
- 已发布测试版：https://github.com/hotaoyousa/localsend/releases/tag/phone-pairing-20261020 。4个安装工件上传状态均为uploaded，大小与本地一致；Release标签包含实际功能源码。Android为.debug独立包名；macOS未做Apple公证，Windows未签名。
- 用法：两台电脑展示接收链接二维码并保持窗口打开 → 手机发送页扫码界面右上角「连接两台电脑」 → 分别扫描A/B → 建立连接并在两台电脑确认 → 电脑发送页选择对方传文件。手机只交换连接信息。
- 剩余验收：ADB无设备，尚未真实完成 Android+macOS+Windows 三设备互连及双向文件落盘核对。功能清单按原证据规则记blocked，不能宣称已完成真机验收；下一步安装上述版本在同一可直连网络测试。

### 2026-10-20 — 扫码连接导航与角色逻辑改进（仅本地）

- 本轮按用户要求不上传GitHub，先保留旧产物，待新版验证后再清理。
- 新增与接收/发送/设置同级的「扫码连接」；桌面/手机均直接展示本机局域网地址、复制、二维码和放大地址。手机另有突出显示的扫码发送、扫码接收、连接电脑三个入口。原发送页扫码快捷入口同样改为直接发送模式。
- 新扫码发送直接识别目标并选文件；接收直接请求对方发送并等待。双电脑固定A发送/B接收，先准备B，再让A选文件，电脑无需再确认角色；仅从本轮选定发送者自动接收，离开或取消清除等待。发送端始终先选文件，取消不会发送旧选择。
- 处理多网卡：手机介绍自己时使用服务器观察到的来源IP，保留端口/协议/指纹。回归覆盖请求中止、不在线、重复设备和失败重试。
- 验证：./init.sh及基线通过，flutter analyze无问题，完整Flutter测试143项通过，三平台页面预览通过（320px手机宽度）；ADB无连接设备。Android APK已构建成功，macOS Release正在构建。
- Windows：本机为macOS且本轮不上传源码；新增 `support/scripts/build_qr_connection_windows.ps1` 供Windows主机本地生成新版便携ZIP。尚未运行Windows编译，不将旧EXE标为新版。

### 2026-10-20 — 扫码连接新版构建、实际流程验证与清理完成

- 新版工件均位于 `dist/qr-connection-20261020/`：`LocalSend-1.18.2-qr-connection-android-arm64-debug.apk`、`LocalSend.app`、`LocalSend-1.18.2-qr-connection-macos-arm64.dmg`、`LocalSend-1.18.2-qr-connection-macos-arm64.zip`。APK/ZIP和DMG校验通过，macOS ad-hoc深度签名后严格验证通过。
- 实际macOS应用采用独立便携设置和55329端口启动成功，验证「接收、发送、扫码连接、设置」四个入口；进入扫码连接立即显示本机地址、复制、二维码/放大按钮。临时本地HTTP对端验证receive/send角色均返回204，发生两次直接register；实际发送端自动显示添加文件，无角色确认，无用户文件传输。临时实例已关闭。
- 原生测试中旧网络接口192.168.1.100已断开，初次注册超时；改用当前en0地址后两角色均成功。
- 用户明确选择先完成Android/macOS，保留旧Windows包。旧Windows EXE已移至 `dist/windows-last-available-20261020/LocalSend-1.18.2-phone-pairing-windows-x64.exe`，附有旧版说明；本轮没有新版Windows二进制。
- Windows新版源码归档：`dist/qr-connection-20261020/LocalSend-qr-connection-source.zip`；构建脚本 `support/scripts/build_qr_connection_windows.ps1`（尚未在Windows执行）。同目录README有用法，preview有三平台界面渲染。
- 新版验证完成后，删除旧Android/macOS产物、app/build和macOS独立副本中的重复构建/派生缓存及本轮临时测试副本，实际增加可用空间约 14.57 GiB；保留源码、工具链和用户AGENTS.md修改。
- 本轮没有git push、Release上传或远程Windows构建。实现留在工作区；完整143项Flutter测试通过，静态分析无问题。Android无USB设备，真实三设备收件验收仍待进行，功能清单未标passing。

### 2026-10-20 — 新版源码同步到 fork，供 Windows 自行构建

- 用户新授权：将本次扫码连接构建对应源码上传 GitHub，方便后续在其他 Windows 电脑自行编译；此前仅本地交付的约束已被此次源码上传请求更新。
- 同步范围：新版扫码连接页面、自动 A/B 角色分派、文案/生成文件、对应测试、功能清单、进度记录，以及 `support/scripts/build_qr_connection_windows.ps1`。新增中文说明 `support/docs/QR_CONNECTION_WINDOWS_ZH.md`，含目标分支、依赖版本、克隆/更新命令、脚本入口和 ZIP 输出路径。
- 目标：fork `hotaoyousa/localsend` 的 `feat/qr-device-discovery`。提交使用 skip ci，避免仅同步源码时触发已有远程 Windows 构建。安装包、缓存、独立构建副本及用户原有 AGENTS.md 修改未纳入本次提交。
- 验证依据：本次功能构建时的完整143项 Flutter 测试、静态检查与 macOS 实际角色流程验证均已通过；此次仅补编译说明及同步源码，未重新构建安装包。Windows 脚本尚未在 Windows 主机执行。下一步在 Windows 拉取该分支，按中文说明编译并验收实际文件收件。


### 2026-10-20 — 桌面选择排列与扫码发送过渡优化

- 当前功能 qr_polish-003。桌面添加文件固定两列：文件/文件夹、文本/剪贴板，窄窗口滚动避免溢出；手机原有文件选择保持。
- 扫码发送改为扫码页内部直接register，成功返回Device后进入原文件选择；不再弹自动IP连接框。超过250ms才显示内嵌进度，没有人为最短等待；扫码页零时长退出避免与文件选择进入动画叠加，错误留页重试/重扫，退出忽略迟到结果。
- 修改：add_file_dialog、qr_scan_page、qr_connection_tab、send_tab_vm与对应测试。./init.sh及旧扫码基线通过；完整151项Flutter测试通过，flutter analyze无问题。布局覆盖macOS/Windows的640/1200/400宽度，连接覆盖快/慢/失败重试/连接中退出。ADB无设备，未做本轮手机真机动画验收。
- 用户授权上传新版Windows构建。本轮提交将触发fork的Windows工作流；Android/macOS本地构建同步进行。新产物验证完成前保留旧包；用户AGENTS.md修改不纳入提交。


### 2026-10-20 — 扫码过渡与2×2桌面布局：三平台发布及旧包清理完成

- 功能 qr_polish-003 按本轮自动化/构建交付规则通过；源码提交 `25b25b618b9216b856a6ca9462fa89b9e0a687ed` 已上传 fork 分支 `feat/qr-device-discovery`。完整151项Flutter测试通过，静态分析无问题；用户AGENTS.md修改未提交。
- Windows工作流 https://github.com/hotaoyousa/localsend/actions/runs/39387964307 成功，Windows任务13分52秒；EXE从该次工作流下载，ZIP完整性验证通过。更新中文Windows自行编译说明及新版下载入口。
- macOS arm64 Release重新ad-hoc深度签名，严格校验通过；DMG/ZIP完整性通过。临时便携设置与55339端口实际启动，info返回别名及协议2.2；测试进程和临时设置已移除。Android arm64 Debug APK包名.debug、压缩完整性通过。
- 已发布 https://github.com/hotaoyousa/localsend/releases/tag/qr-polish-20261020 ，标签绑定功能提交25b25b61。4个工件状态uploaded，服务端大小逐一与本地一致：APK198539247、DMG30542030、ZIP26675038、EXE18926791字节。
- 本地可测试产物：
  - `dist/qr-polish-20261020/LocalSend-1.18.2-qr-polish-android-arm64-debug.apk`
  - `dist/qr-polish-20261020/LocalSend.app`
  - `dist/qr-polish-20261020/LocalSend-1.18.2-qr-polish-macos-arm64.dmg`
  - `dist/qr-polish-20261020/LocalSend-1.18.2-qr-polish-macos-arm64.zip`
  - `dist/qr-polish-20261020/LocalSend-1.18.2-qr-polish-windows-x64.exe`
- 新版校验后删除 `dist/qr-connection-20261020`、`dist/windows-last-available-20261020`，以及 app/build、独立macOS副本app/build和本轮Kotlin缓存；清理期间实测可用空间增加约15.62GiB。保留新包、源码、工具链与macOS本地Swift包配置；本次未删除GitHub历史Release。
- 剩余验收：ADB无设备，手机实际动画观感和Android/macOS/Windows真实三设备文件落盘仍需安装新版实测；Windows未经本地实机启动验收，Mac未Apple公证、Windows未签名。未将既有真实三设备验收项标记passing。


### 2026-10-20 — 扫码收件确认与真实保存目录

- 当前功能 qr_receive-004，按用户要求新增三端扫码收件确认及独立扫码连接自动保存开关（默认关闭）；该开关对本次明确连接的发送者生效，并覆盖普通/收藏自动保存，不影响普通传输规则。
- 复用现有ReceivePage的接受/拒绝按钮；扫码发送通过既有元数据邀请明确接收角色，手机扫码接收及双电脑B同样应用新策略。收件会话记录扫码来源，结束处理保持同一规则。等待页同步展示是否需要确认。
- 保存目录读取与收件端相同的系统API，完整路径单独占行；Windows显示原生反斜杠，兼容已移动的Downloads。自定义目录及恢复默认操作保持。
- 修改设置存储/状态及生成映射、收件控制器、扫码页/连接页/设置页、目录provider/widget、英/简繁中文及对应测试。
- 验证：./init.sh与33项扫码基线通过；完整176项Flutter测试通过，静态分析无问题。覆盖Android/macOS/Windows接受/拒绝、自动保存、全局开关不绕过扫码确认、不同发送者、普通传输、默认/自定义路径、设置持久化；ADB无设备。
- 已授权生成并上传三平台新版，验证新包后删除旧本地产物。Windows使用fork既有工作流，Android/macOS本机构建；用户AGENTS.md修改不提交。


### 2026-10-20 — 扫码收件确认与实际目录：三平台发布完成

- 功能 qr_receive-004 本轮自动化/构建交付通过；源码提交 `b552ddeace482edd64e7f414bcb15c5520f48083` 已上传 fork 的 `feat/qr-device-discovery`。完整176项Flutter测试与静态分析通过；保留用户AGENTS.md修改未提交。
- Windows工作流 https://github.com/hotaoyousa/localsend/actions/runs/39394781583 成功，Windows任务13分56秒；安装程序下载ZIP完整性通过。
- Android arm64 Debug APK完整性通过。macOS原生资源缓存曾引用上次清理已删除的objective_c输出；重置独立副本的 app/.dart_tool/flutter_build 和根 .dart_tool/hooks_runner 后构建成功，未修改功能代码。应用ad-hoc深度签名及严格验证通过，DMG/ZIP完整性通过；临时独立配置55349端口实际启动返回协议2.2，测试实例与临时设置已移除。
- 已发布 https://github.com/hotaoyousa/localsend/releases/tag/qr-receive-20261020 ，标签绑定功能提交b552ddea。四个工件状态uploaded、服务端大小与本地一致：APK198544739、DMG30541093、ZIP26672435、EXE18937977字节。
- 本地可测试产物：
  - `dist/qr-receive-20261020/LocalSend-1.18.2-qr-receive-android-arm64-debug.apk`
  - `dist/qr-receive-20261020/LocalSend.app`
  - `dist/qr-receive-20261020/LocalSend-1.18.2-qr-receive-macos-arm64.dmg`
  - `dist/qr-receive-20261020/LocalSend-1.18.2-qr-receive-macos-arm64.zip`
  - `dist/qr-receive-20261020/LocalSend-1.18.2-qr-receive-windows-x64.exe`
- 验证新版后删除旧 `dist/qr-polish-20261020`、主工程/独立macOS副本的 app/build、本轮Kotlin缓存及成对的Flutter/native-assets派生缓存；可用空间实测增加约13.83GiB。保留新包、源码、工具链及macOS本地Swift包配置；GitHub历史Release未删除。
- 用法：在收件端设置 → 接收打开或关闭「扫码连接自动保存」（首次默认关闭）；关闭时扫码连接的实际文件请求显示接受/拒绝，开启时自动接收明确连接的发送方。保存目录现在显示系统完整实际路径，可继续选择自定义目录或恢复默认。
- 剩余验收：无Android USB设备，手机/Windows实机运行及真实三设备文件落盘仍需用户安装新版验证；Android为.debug包，macOS未Apple公证，Windows未签名。既有真实三设备验收项保持blocked。
