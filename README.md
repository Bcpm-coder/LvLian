# RhythmFit（律练）

一款面向 iPhone 与 Apple Watch 的本地训练 App，用节奏提示辅助盆底肌练习，并记录每日深蹲计划。

RhythmFit 是一个 **Vibe Coding** 实践项目：先用自然语言描述真实需求，再通过真机体验、问题反馈和自动化测试持续调整代码。它关注的不是一次性生成界面，而是让产品在反复使用中逐步贴近日常习惯。

> 用自然语言表达需求，用真实体验打磨产品。

## 功能

### 盆底肌训练

- 默认节奏：准备 5 秒，收缩 5 秒，放松 5 秒，10 次为一组。
- 每日目标可设为 1～8 组，支持分时完成。
- 提供感知、熟悉、控制、巩固四阶段通用示例课程。
- 倒计时、进度环、次数、暂停、继续和提前结束完整联动。
- iPhone 使用 Core Haptics 提示收缩与放松，可选择增强或轻提示。
- 进入后台、锁屏或发生系统中断时自动暂停；恢复后先从完整放松开始。

### 每日深蹲

- 每日目标 50 个，默认安排为 5 组 × 10 个。
- 准备 5 秒，下蹲与起身默认各 2 秒，组间休息 30 秒。
- 下蹲、起身与休息时间可在开始前调整。
- 每组结束后由用户确认实际完成次数；当天可以分多次完成。
- 提前结束时丢弃当前未确认组，保留此前已确认次数。
- 支持中文动作语音和独立的 iPhone 震动开关。

### Apple Watch

- 可脱离手机独立开始一组盆底肌训练或深蹲训练。
- 显示动作、剩余时间、组数、次数，以及深蹲训练的实时心率。
- 深蹲使用 HealthKit 记录功能性力量训练，并将心率回传至手机。
- 手表独立完成的记录通过 WatchConnectivity 延迟同步，使用 UUID 去重。
- 支持暂停、继续和提前结束；动作变化使用固定的系统触感组合。

watchOS 不开放触感振幅参数，实际强度由设备及“声音与触感”设置决定。无线通信可能存在延迟，手机与手表的提示不保证完全同时发生。

### 记录与提醒

- SwiftData 保存盆底肌和深蹲记录，无需账号或服务器。
- 今天页分别显示两项训练目标及完成进度。
- 月历区分两类达标记录，并统计训练天数、有效时长和深蹲总次数。
- 支持查看详情、删除单条记录和清空训练数据。
- 每日提醒默认关闭，预选 21:00；开启后使用系统本地通知。

## 课程示例

四阶段课程属于通用练习示例，不是个体化治疗处方。

| 阶段 | 每次收缩 | 每次放松 | 每节次数 |
|---|---:|---:|---:|
| 感知 | 3 秒 | 6 秒 | 8 次 |
| 熟悉 | 3 秒 | 6 秒 | 10 次 |
| 控制 | 4 秒 | 8 秒 | 10 次 |
| 巩固 | 5 秒 | 10 秒 | 10 次 |

每阶段完成 7 个不同日期的训练后，用户确认无不适且能充分放松，才会进入下一阶段。同日重复训练不会加快升级，深蹲记录也不影响盆底肌课程进度。

## 技术实现

- SwiftUI：iPhone 与 Apple Watch 界面
- SwiftData：本地训练记录
- Core Haptics / WatchKit：动作触感提示
- HealthKit：手表心率和功能性力量训练
- WatchConnectivity：手机与手表状态及记录同步
- UserNotifications：每日本地提醒
- TimelineView + 单调时钟：流畅倒计时，避免逐帧计数误差
- 串行存储队列：防止旧检查点覆盖终态记录

最低系统版本：

- iOS 17.0
- watchOS 10.0

当前工程版本：**1.10（11）**。

## 运行工程

### 环境

- macOS
- 完整版 Xcode 16 或更新版本
- 真机运行需要 Apple ID、开发者模式及有效签名
- Apple Watch 功能需要与 iPhone 配对的手表

### iPhone

1. 克隆仓库并打开 `LvLian.xcodeproj`。
2. 选择 `LvLian` Scheme。
3. 在 **Signing & Capabilities** 中选择自己的 Team。
4. 如果现有 Bundle Identifier 无法用于你的账号，请同时修改手机和手表标识，并保持手表的 Companion App 标识与手机一致。
5. 选择 iPhone 模拟器或已连接的真机，点击 Run。

震动、通知、HealthKit 和 Apple Watch 通信需要真机验证。免费 Personal Team 的开发描述文件通常只有 7 天有效期；到期后需要使用相同 Bundle Identifier 重新签名并覆盖安装，才能继续保留原应用数据。

### Apple Watch

1. 解锁 iPhone 和 Apple Watch，开启开发者模式，并保持蓝牙与 Wi-Fi 可用。
2. 在 Xcode 中选择 `LvLianWatch` Scheme 和真实手表设备。
3. 确认 HealthKit 权限说明及签名配置后运行。

也可以用仓库脚本构建 Release 版本并直接安装：

```sh
xcrun devicectl list devices
./Scripts/install-watch-release.sh <Watch-CoreDevice-ID>
```

脚本不会绕过 Apple 的签名和设备信任要求。连接失败时，请先确认手表已解锁、Mac 与手表处于可互访的普通 Wi-Fi，且 VPN 或网络隔离没有阻断本地设备通道。

## 测试

运行核心状态机测试：

```sh
./Scripts/test-core.sh
```

使用完整 Xcode / Swift 工具链运行 XCTest：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

运行 SwiftData 磁盘迁移与保存测试：

```sh
./Scripts/test-storage.sh
```

测试覆盖课程切换、暂停恢复、跨日统计、同日去重、七日升级、深蹲分组与确认、提前结束、异常退出、终态保护和旧数据库迁移。真机安装历史与人工验收边界见 [TESTING.md](TESTING.md)。

## 工程结构

```text
LvLian/
├── App/          # SwiftData 模型、应用入口和设置
├── Core/         # 训练状态机、课程和纯逻辑
├── Services/     # 会话、存储、提醒、语音、触感和手表通信
└── Views/        # SwiftUI 页面及倒计时组件

LvLianWatch/      # 独立 watchOS App、HealthKit 与手表端状态机
Tests/            # 核心逻辑和迁移测试
Scripts/          # 测试、工程生成、图标与手表安装脚本
```

`Core` 层不依赖页面和数据库，训练计数由状态机负责，动画只负责显示。应用以唯一记录 ID 防止重复保存，终态记录不会被较旧的训练检查点覆盖。

## 隐私

- 训练记录保存在本地，不使用账号、广告或分析 SDK。
- SwiftData 配置不启用 CloudKit 自动同步。
- 盆底肌训练不读取健康数据。
- 深蹲开始后，手表仅在用户授权的情况下读取心率并写入功能性力量训练。
- 系统备份是否包含应用数据取决于用户的设备备份设置。

## 健康提示

RhythmFit 是训练辅助工具，不提供诊断或治疗，也不承诺改善勃起硬度。训练时应自然呼吸、轻柔收缩并充分放松；如果出现疼痛或明显不适，应停止练习并咨询合格的医疗专业人员。

参考资料：

- [NIDDK：Kegel Exercises](https://www.niddk.nih.gov/health-information/urologic-diseases/kegel-exercises)
- [Apple：Scheduling a notification locally from your app](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app)
- [Apple：HealthKit](https://developer.apple.com/documentation/healthkit)
- [Apple：Watch Connectivity](https://developer.apple.com/documentation/watchconnectivity)
- [Apple：Core Haptics](https://developer.apple.com/documentation/corehaptics)
