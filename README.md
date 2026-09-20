# CPULowPower（RootHide 实验版）

从 CPUthermal 1.6.2-129 的分析结果提取 CPU 低功耗相关功能，**不是原 DEB 的逐字源码，也未经过真机频率验证**。0.5.3 在用户 iPhone 13 Pro Max 上已证实注入、读取配置并下发 CPU 预算，但三个档位实测都为约 600 MHz。0.6.0 因此移除了所有档位共用的 CPU 等级 2 限制，改用 CPU 预算百分比区分；实际频率仍待设备逐档校准。

## 功能边界

- 启用插件后，白名单模式关闭时解锁状态下全局低功耗；打开时解锁状态下只对 `lowPowerApps` 中的前台应用施加限制。熄屏后不论白名单状态，自动切换到独立的锁屏档位；亮屏后恢复原规则。
- 从旧版升级时，如未设置新的白名单开关，旧 `powerMode=fullPower` 自动视为白名单开启，旧 `powerMode=lowPower` 视为白名单关闭。旧 `fullPowerApps` 不再使用。
- 解锁和锁屏分别可选省电、标准、性能三个档位，当前对应 `MitigationController` 的 CPU 预算上限 35%、55%、75%。与系统较严格的原生预算取更低值；不修改 GPU、屏幕或电池状态。百分比**不是 MHz**，不保证精确频率。
- 收到熄屏/亮屏通知时立即切换档位；启用期间每 2 秒重新下发一次限制，避免系统在锁屏或开关切换后覆盖。该定时唤醒本身有少量功耗，真机测试后可调整。
- 未包含控制中心、充电、挂载、电池伪装、屏幕亮度、刷新率或高温告警拦截。

## 配置

安装后在 iOS「设置」→「CPULowPower」里操作总开关、白名单模式、解锁档位、锁屏档位与白名单应用。首次安装总开关默认关闭；从旧包迁移时会读取旧配置。设置页写入 RootHide 隐根内的新偏好文件，并通知 `thermalmonitord` 重载；安装/升级包时会重启 `thermalmonitord` 使新注入代码加载。新包标识符是 `com.mox1121.cpulowpower`，与旧独立包冲突，不能同时安装。

也可手动把 `preferences.example.plist` 复制到设备隐根内 `jbroot /var/mobile/Library/Preferences/com.mox1121.cpulowpower.plist` 所指向的实际路径；不要放在真实 rootfs 的同名路径。修改后发送 Darwin 通知 `com.mox1121.cpulowpower/settingsChanged`，或重启 `thermalmonitord`。

设置图标提供带透明圆角的 `icon.png` (29×29)、`icon@2x.png` (58×58)、`icon@3x.png` (87×87)；底稿独立保存，不会打进 DEB。设置界面和应用选择页已通过构建与静态检查，**尚无真机打开页面的验证**。

## 构建与限制

公开 GitHub 仓库的 Actions 页面提供 `Package RootHide DEB` 工作流：推送到 `main` 或点击 **Run workflow** 后，在 macOS 上用 RootHide 的 Theos 分支构建。构建通过后，在该次运行的 **Artifacts** 下载 `cputhermal-lowpower-roothide`，其中包含 DEB；不会自动发布 Release，也不再构建普通 rootless 包。此包原生按 RootHide 方案构建，不依赖 `rootless-compat`。

本地构建需要 Xcode、[roothide/theos](https://github.com/roothide/theos)、iPhoneOS16.5 SDK，以及 `ldid`、`dpkg`、`xz`：`make clean package THEOS_PACKAGE_SCHEME=roothide FINALPACKAGE=1`。RootHide 的路径、签名和注入兼容性仍须在设备上验证。**当前 Windows 环境未安装 Theos，也未真机验证。**

0.6.1 只控制 CPU 预算，不再写固定 CPU 等级 2 或固定 mW 目标，并补齐设置页顶层标题。`thermalmonitord` 会在隐根 `/var/mobile/Library/Preferences/com.mox1121.cpulowpower.status.txt` 写状态；在设备终端运行 `cat /var/mobile/Library/Preferences/com.mox1121.cpulowpower.status.txt` 可查看屏幕状态、档位、上限、实际送入预算 setter 的值，以及新/旧配置来源。`active=0` 表示总开关或白名单条件未启用；`budgetRequested=1` 只表示方法曾被调用，**不等于已证实物理频率变化**。请在同一负载下逐档实测锁屏、解锁与开关切换，并留意设备温度。私有通知和 CPU 控制接口可能随 iOS 版本变化。
