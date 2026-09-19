# CPUthermal 独立低功耗插件（实验源码）

从 CPUthermal 1.6.2-129 的分析结果提取低功耗相关功能，**不是原 DEB 的逐字源码，也未经过真机验证**。本工程有独立包名、配置域和通知名；与原 CPUthermal 包冲突，不要同时注入 `thermalmonitord`。

## 功能边界

- 常驻低功耗或常驻系统原生温控两种模式。`fullPowerApps` 是低功耗模式的例外应用；`lowPowerApps` 是原生模式下进入低功耗的应用。这里的 “fullPower” 只表示不施加本插件的限制，**不会解除系统温控**。
- 熄屏优先进入低功耗；亮屏恢复常驻模式和前台应用例外。
- 三档上限沿用逆向分析值：`saver` 2000mW/35%，`standard` 2500mW/45%，`performance` 3000mW/55%。与系统原生预算取更严格者，不覆盖更严格的原生热限制。
- 未包含控制中心、充电、挂载、电池伪装、屏幕亮度、刷新率或高温告警拦截。

## 配置

安装后在 iOS「设置」→「CPU 低功耗」里操作总开关、常驻模式、三档强度与两种应用名单。首次安装默认关闭，须主动开启。设置页写入 RootHide 隐根内的偏好文件，并通知 `thermalmonitord` 重载。

仍可手动把 `preferences.example.plist` 复制到设备隐根内 `jbroot /var/mobile/Library/Preferences/com.huayuarc.cputhermal.lowpower.plist` 所指向的实际路径；不要放在真实 rootfs 的同名路径。修改后发送 Darwin 通知 `com.huayuarc.cputhermal.lowpower/settingsChanged`，或重启 `thermalmonitord`。

设置图标提供 `icon.png` (29×29)、`icon@2x.png` (58×58)、`icon@3x.png` (87×87)；底稿独立保存，不会打进 DEB。设置界面和应用选择页已通过构建与静态检查，**尚无真机打开页面的验证**。

## 构建与限制

公开 GitHub 仓库的 Actions 页面提供 `Package RootHide DEB` 工作流：推送到 `main` 或点击 **Run workflow** 后，在 macOS 上用 RootHide 的 Theos 分支构建。构建通过后，在该次运行的 **Artifacts** 下载 `cputhermal-lowpower-roothide`，其中包含 DEB；不会自动发布 Release，也不再构建普通 rootless 包。

本地构建需要 Xcode、[roothide/theos](https://github.com/roothide/theos)、iPhoneOS16.5 SDK，以及 `ldid`、`dpkg`、`xz`：`make clean package THEOS_PACKAGE_SCHEME=roothide FINALPACKAGE=1`。RootHide 的路径、签名和注入兼容性仍须在设备上验证。**当前 Windows 环境未安装 Theos，也未真机验证。**

此最小版本只拦截已观察到的 `MitigationController` CPU 预算 setter 并在模式切换时请求重新计算。不同机型/iOS 版本可能不调用这些 selector；模式切换后的预算恢复也必须通过设备日志与实测确认。测试前不要用于依赖稳定散热或性能的设备。若要达到原包的全覆盖路径，需要进一步针对目标设备确认私有 API 和恢复流程。
