# Still Link

原生 Android 手表伴侣，面向 OPPO Watch X 做真机验证。Java + Android SDK，无第三方运行时依赖；不使用官方健康账号、不读取历史健康记录、不生成模拟心率。

功能：真实 `TYPE_HEART_RATE` → 加密 BLE 通知；接收 Mac 课程名、播放/暂停状态、剩余时间；发送绑定当前会话的暂停/继续/结束命令。前台服务显示停止入口，搜索 2 分钟无人连接自动停止，断开后停止传感器。

## 构建

要求 JDK 17–24、Gradle 8.13+ / 8.x、Android SDK 35（已用 JDK21 / Gradle8.14.3 / SDK35 验证）。

```sh
JAVA_HOME=/path/to/jdk ANDROID_HOME=/path/to/sdk GRADLE_BIN=/path/to/gradle bash scripts/build-watch.sh
```

在仓库根执行，产物 `dist/Still-Link-debug.apk`。目前为调试签名，本地密钥不提交；换机器可能需要保留自己的签名密钥才能覆盖安装。

## Watch X 真机接入

1. 在手表启用开发者选项与无线调试，手表和 Mac 在同一局域网。
2. 使用手表实际显示的地址/端口；若要求无线配对，先执行 `adb pair <配对地址:端口>` 并由用户输入当次配对码，再 `adb connect <连接地址:端口>`。不要假设所有固件都是 5555。
3. `adb -s <已核实的手表序列> install -r dist/Still-Link-debug.apk`。不要安装到采集课程的手机作为手表实测替代。
4. 手表打开 Still Link，允许身体传感器、蓝牙权限，点击开始连接。Mac 息间 → 我的手表 → 搜索手表 → Still Link；如系统提示蓝牙配对，在两端确认。
5. 检查至少 60 秒真实心率传输、暂停/继续/结束、断线 10 秒读数清空、退出服务后传感器停止。

不会解绑 OPPO 健康，不向官方运动记录写入数据。光学传感器、后台采样、加密订阅、圆屏适配与功耗仍需 Watch X 真机验收。

## BLE contract v1

- Heart Rate Service `180D` / Measurement `2A37` / CCCD `2902`。
- Still 服务 `782B1000-6F52-4C85-A701-596BE18A7810`。
- 状态 `…1001…`：加密 write-with-response，UTF-8 `session8|R/P/E|remainingSeconds|title`，上限180字节。session8 为 UUID 前8位，无会话为 `-`。支持 ATT prepared writes。
- 控制 `…1002…`：加密订阅，UTF-8 `session8|pause/resume/end`，20字节以内。
- 同一时间只接受一个已绑定中心设备；蓝牙配对是身份边界，会话 ID 仅用于拒绝旧指令。状态每1–2秒刷新，10秒过期后停用手表课程控制。
- 只持有当前心率在内存中，不持久保存、不联网。无传感器/无权限时明确失败。

研究线索：[HeartRateBroadcaster](https://github.com/QingyueBeaker/HeartRateBroadcaster) 的 README 描述 Watch X 采用标准 Android 传感器/BLE 的方案；其自动模拟数据行为不被本项目采用。未复制其代码，也未将该 README 视为本项目兼容性验收。
