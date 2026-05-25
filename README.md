# VRPN MQTT Bridge

## 项目目的

本项目只做一件事：

```text
读取 VRPN tracker pose -> 发布 MQTT JSON payload
```

运行时是一个纯 C++ 可执行文件：

```text
vrpn-mqtt-bridge
```

程序直接使用 VRPN C++ API 读取 tracker 位姿，计算 yaw，然后把位置、yaw、状态和频率发布到 MQTT topic。运行链路里不需要 Python。

## 参考说明

VRPN 读取部分参考了 GitHub 项目
[`GrooveWJH/vrpn-sim-mavlink`](https://github.com/GrooveWJH/vrpn-sim-mavlink) 中 Receiver 的 C++ 客户端思路：创建 `vrpn_Tracker_Remote`、注册 tracker 回调、在主循环里持续调用 `mainloop()` 读取 pose。

本项目只保留这个 VRPN tracker 读取方式，输出目标改为 MQTT。参考项目中的其它转发链路不属于本仓库目标，也没有被引入。

## 当前边界

包含：

| 模块 | 说明 |
| --- | --- |
| VRPN client | 使用 `vrpn_Tracker_Remote` 连接 `tracker@host:port`。 |
| MQTT publisher | 内置最小 MQTT 3.1.1 TCP client，发布 QoS 0 payload。 |
| 构建脚本 | 用 CMake 构建 C++ 程序。 |
| 部署脚本 | 安装二进制、生成 env、可选安装 user-level systemd 服务。 |
| 中文文档 | 说明构建、启动、配置和输出格式。 |

不包含：

| 不包含 | 说明 |
| --- | --- |
| VRPN server | 需要外部 VRPN server 已经在网络中输出 tracker pose。 |
| VRPN 第三方库源码 | 需要本机已经安装 VRPN headers/libs。 |
| MQTT broker | 需要外部 MQTT broker，例如 `localhost:1883`。 |
| Python 桥接逻辑 | 已移除。运行时不依赖 Python 包。 |
| 完整 MQTT SDK | 当前只实现本项目需要的 MQTT 3.1.1 QoS 0 发布能力。 |

## 数据流

```text
VRPN server -> vrpn-mqtt-bridge -> MQTT broker
```

程序启动后会：

1. 解析命令行参数或 env 配置。
2. 连接 VRPN server。
3. 订阅指定 tracker 的 pose。
4. 从 quaternion 计算 yaw。
5. 按 `VRPN_MAX_MQTT_RATE` 限频发布 MQTT。
6. 定期发布状态和频率。
7. 在交互式终端显示两行实时状态表。

## 依赖

编译前需要本机已经安装：

```text
cmake
C++17 compiler
vrpn_Tracker.h
vrpn_Connection.h
libvrpn
libquat
```

`native/vrpn_mqtt_bridge/` 是本项目的桥接程序源码，不是第三方 VRPN 库。

`native/cmake/FindVRPN.cmake` 只负责在本机查找已安装的 VRPN headers/libs，不下载、不安装、不编译 VRPN。

如果 VRPN 安装在非标准路径，可以手动指定：

```bash
cmake -S native/vrpn_mqtt_bridge -B native/vrpn_mqtt_bridge/build \
  -DVRPN_INCLUDE_DIR=/path/to/include \
  -DVRPN_LIBRARY=/path/to/libvrpn.so \
  -DQUAT_LIBRARY=/path/to/libquat.so
```

如果 CMake 输出类似 `Found VRPN: /opt/ros/...`，只表示 CMake 在这个路径找到了本机已安装的 VRPN 文件；不表示本项目依赖 ROS。

## 默认值

| 配置项 | 默认值 |
| --- | --- |
| VRPN tracker | `tracker0` |
| VRPN host | `127.0.0.1` |
| VRPN port | `3883` |
| MQTT host | `localhost` |
| MQTT port | `1883` |
| MQTT 发布频率 | `10 Hz` |
| pose topic | `slam/position` |
| yaw topic | `slam/yaw` |
| status topic | `slam/status` |
| frequency topic | `slam/frequency` |

## 一键部署

在仓库根目录执行：

```bash
./scripts/deploy-vrpn-mqtt.sh
```

脚本会执行：

1. 构建 `native/vrpn_mqtt_bridge/build/vrpn-mqtt-bridge`
2. 安装到 `~/.local/opt/vrpn-mqtt-bridge/bin/vrpn-mqtt-bridge`
3. 如果配置文件不存在，写入 `~/.config/vrpn-mqtt-bridge/vrpn-mqtt-bridge.env`
4. 执行安装检查

脚本结束会打印实际命令和配置路径：

```text
Installed VRPN MQTT Bridge
  prefix: ...
  command: ...
  config: ...
```

使用脚本打印的命令启动：

```bash
<command> --env-file <config>
```

## 手动构建

```bash
./scripts/build.sh
```

等价 CMake 命令：

```bash
cmake -S native/vrpn_mqtt_bridge -B native/vrpn_mqtt_bridge/build -DCMAKE_BUILD_TYPE=Release
cmake --build native/vrpn_mqtt_bridge/build --parallel 2
```

构建产物：

```text
native/vrpn_mqtt_bridge/build/vrpn-mqtt-bridge
```

## 手动启动

直接传参数：

```bash
native/vrpn_mqtt_bridge/build/vrpn-mqtt-bridge \
  --tracker tracker0 \
  --vrpn-host 127.0.0.1 \
  --vrpn-port 3883 \
  --mqtt-host localhost \
  --mqtt-port 1883
```

使用 env 文件：

```bash
native/vrpn_mqtt_bridge/build/vrpn-mqtt-bridge --env-file examples/native-vrpn.env
```

只验证 VRPN 读取，不连接 MQTT：

```bash
native/vrpn_mqtt_bridge/build/vrpn-mqtt-bridge \
  --env-file examples/native-vrpn.env \
  --dry-run
```

完全关闭终端显示：

```bash
native/vrpn_mqtt_bridge/build/vrpn-mqtt-bridge \
  --env-file examples/native-vrpn.env \
  --quiet
```

## 配置文件

推荐模板：

```text
examples/native-vrpn.env
```

核心配置：

```env
VRPN_TRACKER=tracker0
VRPN_HOST=127.0.0.1
VRPN_PORT=3883

VRPN_MQTT_HOST=localhost
VRPN_MQTT_PORT=1883
VRPN_MQTT_USERNAME=
VRPN_MQTT_PASSWORD=

VRPN_MQTT_POSE_TOPIC=slam/position
VRPN_MQTT_YAW_TOPIC=slam/yaw
VRPN_MQTT_STATUS_TOPIC=slam/status
VRPN_MQTT_FREQUENCY_TOPIC=slam/frequency

VRPN_MAX_MQTT_RATE=10
VRPN_STATUS_INTERVAL_SEC=1
VRPN_TIMEOUT_SEC=5
VRPN_Z_OFFSET=0
VRPN_INVERT_YAW=false
VRPN_QUIET=false
```

也可以直接指定完整 VRPN 地址：

```env
VRPN_ENDPOINT=tracker0@127.0.0.1:3883
```

如果设置了 `VRPN_ENDPOINT`，程序会从中解析 tracker、host 和 port。

## 启动输出

程序启动时先输出一次配置摘要：

```text
VRPN MQTT Bridge
  time: 2026-05-25 14:30:00
  mode: run
  route: VRPN tracker0@127.0.0.1:3883 -> MQTT localhost:1883
  vrpn_tracker: tracker0
  vrpn_server: 127.0.0.1:3883
  mqtt_broker: localhost:1883
  mqtt_topics: slam/position, slam/yaw, slam/status, slam/frequency
  max_mqtt_rate_hz: 10.0
  status_interval_sec: 1.0
  timeout_sec: 5.0
```

交互式终端里，启动摘要之后只保留两行实时状态表：

```text
TIME                MOD TRACKER          STATUS   AGE  VRPN  MQTT         X         Y         Z        YAW
2026-05-25 14:30:01 run tracker0         running  0.0  60.0  10.0   1.23456   4.56789   7.89012   45.12345
```

第二行原地刷新，不会持续刷屏。stdout 不是交互式终端时，例如 systemd、管道或重定向到文件，程序不会输出实时状态表。

列含义：

| 列 | 含义 |
| --- | --- |
| `TIME` | 本地标准时间，格式为 `YYYY-MM-DD HH:MM:SS`。 |
| `MOD` | `run` 表示连接 MQTT，`dry` 表示 `--dry-run`。 |
| `TRACKER` | VRPN tracker 名称。IP 和端口只在启动摘要里显示。 |
| `STATUS` | `waiting`、`running` 或 `stalled`。 |
| `AGE` | 当前时间距离最后一帧 VRPN pose 的时间，单位秒；值越大表示越久没有收到新数据。 |
| `VRPN` | 最近一个统计周期收到的 VRPN pose 频率。 |
| `MQTT` | 最近一个统计周期发布的 pose 频率。 |
| `X/Y/Z` | 最新位置，`Z` 已包含 `VRPN_Z_OFFSET`，保留小数点后 5 位。 |
| `YAW` | 由 quaternion 计算得到的 yaw，单位是度，保留小数点后 5 位。 |

## MQTT Payload

位置 topic，默认 `slam/position`：

```json
{"timestamp":1710000000000,"source":"vrpn","tracker":"tracker0","x":1.23456,"y":4.56789,"z":7.89012}
```

yaw topic，默认 `slam/yaw`：

```json
{"timestamp":1710000000000,"source":"vrpn","tracker":"tracker0","yaw":45.12345}
```

状态 topic，默认 `slam/status`：

```json
{"timestamp":1710000000000,"source":"vrpn","tracker":"tracker0","status":"running","last_pose_age_sec":0.010}
```

频率 topic，默认 `slam/frequency`：

```json
{"timestamp":1710000000000,"source":"vrpn","tracker":"tracker0","vrpn":60.000,"mqtt":10.000}
```

`x/y/z/yaw` 保留小数点后 5 位。状态 age 和频率保留小数点后 3 位。

## systemd 部署

安装并启动 user-level systemd 服务：

```bash
./scripts/deploy-vrpn-mqtt.sh --install-systemd --start
```

服务文件：

```text
~/.config/systemd/user/vrpn-mqtt-bridge.service
```

查看状态：

```bash
systemctl --user status vrpn-mqtt-bridge.service
```

查看日志：

```bash
journalctl --user -u vrpn-mqtt-bridge.service -f
```

这个部署方式不需要 sudo。

## MQTT 实现边界

支持：

```text
TCP
CONNECT
用户名/密码
QoS 0 PUBLISH
retain flag
DISCONNECT
```

不支持：

```text
TLS
QoS 1/2
订阅
自动重连队列
will message
```

## 常见问题

### CMake 找到的 VRPN 在 `/opt/ros/...`，是否表示依赖 ROS？

不是。这里只表示 CMake 在这个路径找到了本机已有的 `vrpn_Tracker.h`、`vrpn_Connection.h`、`libvrpn` 和 `libquat`。

### 启动后 `STATUS` 一直是 `waiting`

程序还没有收到 tracker pose。检查 tracker 名称、VRPN host、VRPN port，以及 VRPN server 是否已经运行。

### `STATUS` 变成 `stalled`

程序曾经收到过 pose，但超过 `VRPN_TIMEOUT_SEC` 没有收到新 pose。检查 VRPN server 是否还在发布数据。

### MQTT 没有收到消息

先用 `--dry-run` 验证 VRPN 是否可读。VRPN 正常后，再检查 `VRPN_MQTT_HOST`、`VRPN_MQTT_PORT`、用户名、密码和 topic。

## 目录结构

```text
native/vrpn_mqtt_bridge/     C++ VRPN-to-MQTT 主程序源码
native/cmake/FindVRPN.cmake  查找本机 VRPN headers/libs
examples/                    env 示例和 systemd 示例
scripts/build.sh             构建 C++ 程序
scripts/deploy.sh            通用安装脚本
scripts/deploy-vrpn-mqtt.sh  推荐的一键部署脚本
scripts/preflight.sh         配置和命令检查
```
