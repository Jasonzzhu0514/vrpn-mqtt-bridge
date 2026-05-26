# VRPN MQTT Bridge

把 VRPN tracker 位姿转换成 MQTT JSON 消息。

```text
VRPN server -> vrpn-mqtt-bridge -> MQTT broker
```

`vrpn-mqtt-bridge` 是 C++ 可执行文件，直接使用 VRPN C++ API 读取 tracker pose，计算 yaw，并发布位置、yaw、状态和频率 topic。

## 参考

VRPN 读取方式参考了 [`GrooveWJH/vrpn-sim-mavlink`](https://github.com/GrooveWJH/vrpn-sim-mavlink) 中 Receiver 的 C++ 客户端实现思路：创建 `vrpn_Tracker_Remote`，注册 tracker 回调，并在主循环中调用 `mainloop()`。

本仓库只实现 VRPN 到 MQTT 的桥接，不引入其它转发链路。

## 依赖

编译前需要本机已有：

```text
cmake
C++17 compiler
vrpn_Tracker.h
vrpn_Connection.h
libvrpn
libquat
```

Ubuntu/Debian 可以直接安装构建依赖：

```bash
./scripts/install-deps.sh
```

`native/cmake/FindVRPN.cmake` 只查找本机已有 VRPN headers/libs，不下载、不编译 VRPN。VRPN 安装在非标准路径时，可以手动指定：

```bash
cmake -S native/vrpn_mqtt_bridge -B native/vrpn_mqtt_bridge/build \
  -DVRPN_INCLUDE_DIR=/path/to/include \
  -DVRPN_LIBRARY=/path/to/libvrpn.so \
  -DQUAT_LIBRARY=/path/to/libquat.so
```

## 默认值

| 配置 | 默认值 |
| --- | --- |
| VRPN tracker | `tracker0` |
| VRPN server | `127.0.0.1:3883` |
| MQTT broker | `localhost:1883` |
| MQTT 发布频率 | `10 Hz` |
| pose topic | `slam/position` |
| yaw topic | `slam/yaw` |
| status topic | `slam/status` |
| frequency topic | `slam/frequency` |

## 一键部署

```bash
./scripts/deploy-vrpn-mqtt.sh
```

如果希望部署前自动安装构建依赖：

```bash
./scripts/deploy-vrpn-mqtt.sh --install-deps
```

脚本会构建程序、安装到 `~/.local/opt/vrpn-mqtt-bridge/bin/vrpn-mqtt-bridge`，并在配置不存在时生成：

```text
~/.config/vrpn-mqtt-bridge/vrpn-mqtt-bridge.env
```

脚本结束会打印实际启动命令：

```text
Installed VRPN MQTT Bridge
  command: ...
  config: ...
  run: ...
```

## 手动构建

```bash
./scripts/build.sh
```

`scripts/build.sh` 会自动重建带有旧绝对路径的 CMake cache。需要强制清理时：

```bash
./scripts/build.sh --clean
```

构建产物：

```text
native/vrpn_mqtt_bridge/build/vrpn-mqtt-bridge
```

## 启动

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
native/vrpn_mqtt_bridge/build/vrpn-mqtt-bridge --env-file examples/default.env
```

只读取 VRPN，不连接 MQTT：

```bash
native/vrpn_mqtt_bridge/build/vrpn-mqtt-bridge \
  --env-file examples/default.env \
  --vrpn-only
```

关闭终端状态表：

```bash
native/vrpn_mqtt_bridge/build/vrpn-mqtt-bridge \
  --env-file examples/default.env \
  --quiet
```

## 配置

推荐从 `examples/default.env` 复制修改：

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
VRPN_ONLY=false
VRPN_QUIET=false
```

也可以使用完整 VRPN 地址：

```env
VRPN_ENDPOINT=tracker0@127.0.0.1:3883
```

## 状态表

交互式终端会显示一张实时刷新的状态表，表格会按终端宽度自适应。下方 `message:` 行显示断线、重连、MQTT 错误等诊断信息。

```text
x====================================================================x
|                            VRPN MQTT Bridge                        |
|--------------------------------------------------------------------|
|    GROUP     |       ITEM       |              VALUE               |
|--------------------------------------------------------------------|
|   OVERVIEW   |       time       |       YYYY-MM-DD HH:MM:SS        |
|   OVERVIEW   |     duration     |              HH:MM:SS            |
|   OVERVIEW   |       mode       |              normal              |
|   OVERVIEW   |     tracker      |             tracker0             |
|--------------------------------------------------------------------|
|     VRPN     |      status      |             running              |
|     VRPN     |       lag        |               0.0                |
|     VRPN     |      rec_hz      |               60.0               |
|--------------------------------------------------------------------|
|     MQTT     |      status      |                ok                |
|     MQTT     |      pub_hz      |               10.0               |
|--------------------------------------------------------------------|
|     DATA     |        x         |              1.23456             |
|     DATA     |        y         |              4.56789             |
|     DATA     |        z         |              7.89012             |
|     DATA     |       yaw        |              45.12345            |
x====================================================================x
message: VRPN connected to tracker0@127.0.0.1:3883
```

| 项 | 含义 |
| --- | --- |
| `mode` | `normal` 表示读取 VRPN 并发布 MQTT；`vrpn-only` 表示只读取 VRPN。 |
| `VRPN/status` | `waiting`、`running`、`stalled`、`no-response` 或 `reconnecting`。 |
| `VRPN/lag` | 距离最后一帧 VRPN pose 的时间，单位秒。 |
| `VRPN/rec_hz` | VRPN pose 接收频率。 |
| `MQTT/status` | `init`、`ok`、`error` 或 `disabled`。 |
| `MQTT/pub_hz` | 成功发布 pose 的频率。 |
| `DATA/x/y/z/yaw` | 最新位姿数据，保留 5 位小数。 |
| `message` | 固定在表格下方的一行诊断信息。默认抑制 VRPN 底层重复错误；需要原始 stderr 时使用 `--show-vrpn-errors` 或 `VRPN_SHOW_ERRORS=true`。 |

## MQTT Payload

默认 `slam/position`：

```json
{"timestamp":1710000000000,"source":"vrpn","tracker":"tracker0","x":1.23456,"y":4.56789,"z":7.89012}
```

默认 `slam/yaw`：

```json
{"timestamp":1710000000000,"source":"vrpn","tracker":"tracker0","yaw":45.12345}
```

默认 `slam/status`：

```json
{"timestamp":1710000000000,"source":"vrpn","tracker":"tracker0","status":"running","last_pose_age_sec":0.010}
```

默认 `slam/frequency`：

```json
{"timestamp":1710000000000,"source":"vrpn","tracker":"tracker0","vrpn":60.000,"mqtt":10.000}
```

## MQTT 支持范围

支持：TCP、CONNECT、用户名/密码、QoS 0 PUBLISH、retain、DISCONNECT。

不支持：TLS、QoS 1/2、订阅、自动重连队列、will message。

## 排查

| 现象 | 检查 |
| --- | --- |
| `VRPN/status=waiting` | tracker 名称、VRPN host/port、VRPN server 是否运行。 |
| `VRPN/status=no-response` | 已超过等待阈值仍未收到首帧数据，检查 tracker 名称和 VRPN server。 |
| `VRPN/status=stalled` | VRPN server 是否仍在发布数据。 |
| `VRPN/status=reconnecting` | 网络断开或连接异常，程序正在按间隔重建 VRPN 连接。 |
| `MQTT/status=error` | MQTT host/port、用户名、密码、broker 是否可连接。 |
| 只想验证 VRPN | 使用 `--vrpn-only`。 |
