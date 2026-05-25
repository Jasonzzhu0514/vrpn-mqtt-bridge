# VRPN MQTT Bridge

这个仓库只做一件事：

```text
读取 VRPN tracker pose -> 发布 MQTT payload
```

它不产生 VRPN 数据，不实现 MQTT broker，也不包含第三方 VRPN 库源码或二进制库。

## 仓库里有什么

| 内容 | 路径 | 作用 |
| --- | --- | --- |
| Python 主程序 | `src/vrpn_mqtt_bridge/` | 读取配置、启动 VRPN reader、转换 pose、发布 MQTT。 |
| C++ VRPN reader 源码 | `native/vrpn_pose_reader/` | 编译出 `vrpn_pose_reader`，只负责读取 VRPN pose。 |
| CMake 查找脚本 | `native/cmake/FindVRPN.cmake` | 在本机查找已经安装好的 VRPN headers/libs。 |
| 部署脚本 | `scripts/deploy-vrpn-mqtt.sh` | 构建、安装、生成 env、执行安装检查。 |
| 配置模板 | `examples/native-vrpn.env` | 推荐的 native reader 配置模板。 |

## 仓库里没有什么

| 不包含 | 你需要提供什么 |
| --- | --- |
| VRPN server | 目标机器或网络中已经有 VRPN server 输出 tracker pose。 |
| VRPN 第三方库本体 | 目标机器上已经安装 `vrpn_Tracker.h`、`vrpn_Connection.h`、`libvrpn`、`libquat`。 |
| MQTT broker | 目标机器或网络中已经有 MQTT broker，例如监听 `localhost:1883`。 |
| Python VRPN bindings | 推荐路径不需要它；只有 `VRPN_SOURCE=python` 时才需要。 |

## Python 和 C++ 怎么分工

生产推荐路径：

```text
VRPN server
  -> C++ vrpn_pose_reader
  -> Python vrpn-mqtt-bridge
  -> MQTT broker
```

| 程序 | 谁启动 | 做什么 | 你平时是否手动运行 |
| --- | --- | --- | --- |
| `vrpn-mqtt-bridge` | 用户或 systemd | 主程序。读 env、启动 reader、转 MQTT、发布状态和频率。 | 是。 |
| `vrpn_pose_reader` | `vrpn-mqtt-bridge` 自动启动 | 调用 VRPN C++ API 读取 tracker pose，输出 JSON Lines。 | 否，除非排查 VRPN 读取。 |

一句话：**你运行 Python 主程序；C++ helper 由 Python 主程序自动调用。**

## 推荐部署

在仓库根目录执行：

```bash
./scripts/deploy-vrpn-mqtt.sh
```

这个脚本会执行固定流程：

1. 读取 `examples/native-vrpn.env`
2. 运行 Python 单元测试
3. 用 CMake 构建 `native/vrpn_pose_reader/build/vrpn_pose_reader`
4. 构建 Python wheel 和 source distribution
5. 安装 Python 包
6. 把 `vrpn_pose_reader` 复制到安装目录的 `bin/`
7. 写入 `~/.config/vrpn-mqtt-bridge/vrpn-mqtt-bridge.env`
8. 检查安装后的 `vrpn-mqtt-bridge --help` 能执行

脚本结束时会打印实际运行命令，格式如下：

```text
Installed VRPN MQTT Bridge
  prefix: ...
  command: ...
  config: ...
```

后续手动运行时，使用脚本打印的 `command` 和 `config`：

```bash
<command> --env-file <config>
```

不要自己猜命令路径。不同系统上，部署脚本会选择 venv 安装或 `pip --target`
安装，最终命令路径以脚本输出为准。

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

## 默认输入输出

默认 VRPN endpoint：

```text
tracker0@127.0.0.1:3883
```

默认 MQTT broker：

```text
localhost:1883
```

默认 MQTT topic：

```text
vrpn/pose
vrpn/yaw
vrpn/status
vrpn/frequency
```

这些值都在 env 文件里改。

## 推荐配置文件

模板文件：

```text
examples/native-vrpn.env
```

核心配置：

```env
VRPN_SOURCE=native
VRPN_NATIVE_READER_BIN=vrpn_pose_reader

VRPN_TRACKER=tracker0
VRPN_HOST=127.0.0.1
VRPN_PORT=3883

VRPN_MQTT_HOST=localhost
VRPN_MQTT_PORT=1883
VRPN_MQTT_POSE_TOPIC=vrpn/pose
VRPN_MQTT_YAW_TOPIC=vrpn/yaw
VRPN_MQTT_STATUS_TOPIC=vrpn/status
VRPN_MQTT_FREQUENCY_TOPIC=vrpn/frequency
```

部署脚本安装后会把 `VRPN_NATIVE_READER_BIN=vrpn_pose_reader` 改成安装目录里的
绝对路径，例如：

```env
VRPN_NATIVE_READER_BIN=/home/<user>/.local/opt/vrpn-mqtt-bridge/bin/vrpn_pose_reader
```

也可以直接指定完整 VRPN endpoint：

```env
VRPN_ENDPOINT=tracker0@127.0.0.1:3883
```

如果设置了 `VRPN_ENDPOINT`，程序使用它作为最终 VRPN 地址；此时
`VRPN_TRACKER`、`VRPN_HOST`、`VRPN_PORT` 不再参与 endpoint 拼接。

## VRPN_SOURCE 怎么选

| 值 | 行为 | 使用场景 |
| --- | --- | --- |
| `native` | Python 启动 `vrpn_pose_reader`，由 C++ helper 读 VRPN。 | 生产推荐。 |
| `auto` | 按顺序尝试 `native`、`python`、`cli`。 | 本地调试。生产建议写死 `native`。 |
| `python` | 直接使用 Python VRPN bindings。 | 只有你明确安装并验证过 Python VRPN bindings 时使用。 |
| `cli` | 调用 `vrpn_print_devices`，解析它的文本输出。 | `native` 暂时不可用时的临时 fallback。 |

## 手动构建和运行

一键部署之外，也可以手动执行每一步。

先构建 C++ reader：

```bash
cmake -S native/vrpn_pose_reader -B native/vrpn_pose_reader/build -DCMAKE_BUILD_TYPE=Release
cmake --build native/vrpn_pose_reader/build --parallel 2
```

再安装 Python 包：

```bash
python3 -m venv .venv
. .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install .
```

运行 Python 主程序：

```bash
vrpn-mqtt-bridge \
  --vrpn-source native \
  --vrpn-native-reader-bin native/vrpn_pose_reader/build/vrpn_pose_reader \
  --tracker tracker0 \
  --vrpn-host 127.0.0.1 \
  --vrpn-port 3883 \
  --mqtt-host localhost
```

只验证 VRPN 读取，不连接 MQTT：

```bash
vrpn-mqtt-bridge \
  --env-file examples/native-vrpn.env \
  --dry-run \
  --log-format table
```

直接排查 C++ reader：

```bash
native/vrpn_pose_reader/build/vrpn_pose_reader --endpoint tracker0@127.0.0.1:3883
```

如果这条命令持续输出 JSON Lines，说明 VRPN 读取层已经通了。

## C++ reader 依赖说明

`native/vrpn_pose_reader/` 不是第三方 VRPN 库。它只是本项目写的 reader 源码。

编译它之前，本机必须已经安装 VRPN C/C++ 开发文件：

```text
vrpn_Tracker.h
vrpn_Connection.h
libvrpn
libquat
```

`FindVRPN.cmake` 的职责只是查找这些文件；它不会下载、安装或编译第三方 VRPN。

如果 VRPN 安装在非标准路径，手动传入路径：

```bash
cmake -S native/vrpn_pose_reader -B native/vrpn_pose_reader/build \
  -DVRPN_INCLUDE_DIR=/path/to/include \
  -DVRPN_LIBRARY=/path/to/libvrpn.so \
  -DQUAT_LIBRARY=/path/to/libquat.so
```

如果 CMake 输出 `Found VRPN: /opt/ros/...`，含义只是：

```text
CMake 在 /opt/ros/... 找到了已经安装好的 VRPN headers/libs。
```

这不表示本项目依赖 ROS，也不表示本仓库自带 VRPN 库。

## MQTT Payload

位置 topic：

```json
{"timestamp":1710000000000,"source":"vrpn","tracker":"tracker0","x":1.23,"y":4.56,"z":7.89}
```

偏航角 topic：

```json
{"timestamp":1710000000000,"source":"vrpn","tracker":"tracker0","yaw":45.0}
```

状态 topic：

```json
{"timestamp":1710000000000,"source":"vrpn","tracker":"tracker0","status":"running","last_pose_age_sec":0.01}
```

频率 topic：

```json
{"timestamp":1710000000000,"source":"vrpn","tracker":"tracker0","vrpn":60.0,"mqtt":30.0}
```

## C++ reader 输出格式

`vrpn_pose_reader` 输出 JSON Lines，每行一条 pose：

```json
{"time":1710000000.0,"endpoint":"tracker0@127.0.0.1:3883","position":[1.0,2.0,3.0],"quaternion":[0.0,0.0,0.0,1.0]}
```

Python 主程序读取这个输出，并转换成 MQTT payload。正常部署时不需要其他程序直接消费它。

## 构建发布包

运行测试、构建 C++ reader，并生成 Python 包：

```bash
./scripts/build.sh
```

要求 C++ reader 必须构建成功：

```bash
./scripts/build.sh --require-native
```

构建产物：

```text
dist/vrpn_mqtt_bridge-0.1.0-py3-none-any.whl
dist/vrpn_mqtt_bridge-0.1.0.tar.gz
native/vrpn_pose_reader/build/vrpn_pose_reader
```

检查发布包里是否残留不应出现的现场相关字符串：

```bash
python3 scripts/check-dist.py dist/*.tar.gz dist/*.whl
```

## Python 依赖

Python 包会安装：

```text
paho-mqtt
```

推荐生产路径不需要 Python VRPN bindings。

## 目录结构

```text
src/vrpn_mqtt_bridge/        Python 主程序和 MQTT 桥接逻辑
native/vrpn_pose_reader/     C++ VRPN 读取 helper 源码
native/cmake/FindVRPN.cmake  查找本机 VRPN headers/libs
examples/                    env 示例和 systemd 示例
scripts/build.sh             测试、构建 C++ reader、构建 Python 包
scripts/deploy.sh            通用安装脚本
scripts/deploy-vrpn-mqtt.sh  推荐的一键部署脚本
tests/                       单元测试
```

## 常见问题

### 我应该运行 Python 还是 C++？

运行 Python：`vrpn-mqtt-bridge`。

C++ reader 由 Python 自动启动。你只需要保证 `VRPN_NATIVE_READER_BIN` 指向可执行的
`vrpn_pose_reader`。

### 这个仓库里是不是已经带了 VRPN 库？

不是。仓库里只有读取 VRPN 的 C++ 源码，没有第三方 VRPN headers/libs。

### 为什么 CMake 会找到 `/opt/ros/...`？

因为你的机器上有一份 VRPN 安装在这个路径。CMake 只是复用那份已安装的 VRPN。
项目本身不要求 ROS。

### 没有 Python VRPN bindings 可以吗？

可以。`VRPN_SOURCE=native` 不需要 Python VRPN bindings。

### native reader 不可用怎么办？

临时使用 `vrpn_print_devices`：

```bash
vrpn-mqtt-bridge \
  --vrpn-source cli \
  --vrpn-print-devices-bin /path/to/vrpn_print_devices
```

这是临时 fallback，不是推荐生产路径。
