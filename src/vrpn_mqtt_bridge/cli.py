"""Command-line entry point."""

from __future__ import annotations

import argparse
import dataclasses
import signal
import sys
from typing import Sequence

from vrpn_mqtt_bridge.bridge import VrpnMqttBridge
from vrpn_mqtt_bridge.config import BridgeConfig, config_from_env, validate_config
from vrpn_mqtt_bridge.env import load_env_file


def build_parser(defaults: BridgeConfig) -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Read a VRPN tracker pose and publish MQTT pose topics."
    )
    parser.add_argument(
        "--env-file",
        help="Load KEY=VALUE settings from a dotenv-style file before parsing runtime options.",
    )
    parser.add_argument(
        "--ip",
        "--vrpn-host",
        dest="vrpn_host",
        default=defaults.vrpn_host,
        help=f"VRPN server IP/host. Default: {defaults.vrpn_host}",
    )
    parser.add_argument(
        "--vrpn-port",
        type=int,
        default=defaults.vrpn_port,
        help=f"VRPN TCP port. Default: {defaults.vrpn_port}",
    )
    parser.add_argument(
        "--vrpn-endpoint",
        default=defaults.vrpn_endpoint,
        help="Full VRPN endpoint such as tracker@127.0.0.1:3883. Overrides tracker/host/port.",
    )
    parser.add_argument(
        "--tracker",
        default=defaults.tracker_name,
        help=f"VRPN tracker name. Default: {defaults.tracker_name}",
    )
    parser.add_argument(
        "--compat",
        choices=["generic", "native-vrpn"],
        default="generic",
        help="Compatibility preset. native-vrpn keeps generic tracker naming, native source, and port 3883.",
    )
    parser.add_argument("--mqtt-host", default=defaults.mqtt_host)
    parser.add_argument("--mqtt-port", type=int, default=defaults.mqtt_port)
    parser.add_argument("--mqtt-username", default=defaults.mqtt_username)
    parser.add_argument("--mqtt-password", default=defaults.mqtt_password)
    parser.add_argument("--pose-topic", default=defaults.pose_topic)
    parser.add_argument("--yaw-topic", default=defaults.yaw_topic)
    parser.add_argument("--status-topic", default=defaults.status_topic)
    parser.add_argument("--frequency-topic", default=defaults.frequency_topic)
    parser.add_argument("--max-mqtt-rate", type=float, default=defaults.max_mqtt_rate_hz)
    parser.add_argument(
        "--display-rate",
        type=float,
        default=defaults.display_rate_hz,
        help="Terminal refresh rate in Hz. Does not affect MQTT publish rate.",
    )
    parser.add_argument("--status-interval-sec", type=float, default=defaults.status_interval_sec)
    parser.add_argument("--timeout-sec", type=float, default=defaults.timeout_sec)
    parser.add_argument("--client-id", default=defaults.client_id)
    parser.add_argument("--z-offset", type=float, default=defaults.z_offset)
    add_bool_option(parser, "invert-yaw", default=defaults.invert_yaw)
    parser.add_argument(
        "--vrpn-source",
        choices=["auto", "native", "python", "cli"],
        default=defaults.vrpn_source,
        help="auto uses the native VRPN reader when available, then Python bindings, then vrpn_print_devices.",
    )
    parser.add_argument(
        "--vrpn-native-reader-bin",
        default=defaults.vrpn_native_reader_bin,
        help="Path to vrpn_pose_reader used when --vrpn-source=native or auto.",
    )
    parser.add_argument(
        "--vrpn-print-devices-bin",
        default=defaults.vrpn_print_devices_bin,
        help="Path to vrpn_print_devices used when --vrpn-source=cli or Python bindings are missing.",
    )
    add_bool_option(
        parser,
        "dry-run",
        default=defaults.dry_run,
        help="Read VRPN and print parsed xyz/yaw without connecting to MQTT.",
    )
    add_bool_option(
        parser,
        "quiet",
        default=defaults.quiet,
        help="Do not print each published realtime pose.",
    )
    parser.add_argument(
        "--log-format",
        choices=["table", "json"],
        default=defaults.log_format,
        help="Realtime pose print format.",
    )
    parser.add_argument(
        "--reconnect-interval-sec",
        type=float,
        default=defaults.reconnect_interval_sec,
        help="Seconds between MQTT reconnect attempts when broker is unavailable.",
    )
    add_bool_option(
        parser,
        "fail-on-mqtt-error",
        default=defaults.fail_on_mqtt_error,
        help="Exit if MQTT connect/publish fails instead of continuing to show VRPN data.",
    )
    return parser


def add_bool_option(
    parser: argparse.ArgumentParser,
    name: str,
    *,
    default: bool,
    help: str | None = None,
) -> None:
    dest = name.replace("-", "_")
    parser.add_argument(f"--{name}", dest=dest, action="store_true", default=default, help=help)
    parser.add_argument(f"--no-{name}", dest=dest, action="store_false")


def parse_config(argv: Sequence[str] | None = None) -> BridgeConfig:
    argv = sys.argv[1:] if argv is None else list(argv)
    env_file = _extract_env_file(argv)
    if env_file is not None:
        load_env_file(env_file)

    defaults = config_from_env()
    parser = build_parser(defaults)
    args = parser.parse_args(argv)
    tracker_name = args.tracker
    vrpn_host = args.vrpn_host
    vrpn_port = args.vrpn_port
    if args.compat == "native-vrpn":
        if not _option_present(argv, "--tracker"):
            tracker_name = "tracker0"
        if not _option_present(argv, "--vrpn-source"):
            args.vrpn_source = "native"
        if not _option_present(argv, "--vrpn-port"):
            vrpn_port = 3883
    if args.vrpn_endpoint:
        from vrpn_mqtt_bridge.config import parse_vrpn_endpoint

        endpoint_parts = parse_vrpn_endpoint(args.vrpn_endpoint)
        if endpoint_parts.tracker:
            tracker_name = endpoint_parts.tracker
        if endpoint_parts.host:
            vrpn_host = endpoint_parts.host
        if endpoint_parts.port is not None:
            vrpn_port = endpoint_parts.port
    config = BridgeConfig(
        vrpn_endpoint=args.vrpn_endpoint,
        vrpn_host=vrpn_host,
        vrpn_port=vrpn_port,
        tracker_name=tracker_name,
        mqtt_host=args.mqtt_host,
        mqtt_port=args.mqtt_port,
        mqtt_username=args.mqtt_username,
        mqtt_password=args.mqtt_password,
        pose_topic=args.pose_topic,
        yaw_topic=args.yaw_topic,
        status_topic=args.status_topic,
        frequency_topic=args.frequency_topic,
        max_mqtt_rate_hz=args.max_mqtt_rate,
        display_rate_hz=args.display_rate,
        status_interval_sec=args.status_interval_sec,
        timeout_sec=args.timeout_sec,
        client_id=args.client_id,
        z_offset=args.z_offset,
        invert_yaw=args.invert_yaw,
        vrpn_source=args.vrpn_source,
        vrpn_native_reader_bin=args.vrpn_native_reader_bin,
        vrpn_print_devices_bin=args.vrpn_print_devices_bin,
        dry_run=args.dry_run,
        quiet=args.quiet,
        log_format=args.log_format,
        reconnect_interval_sec=args.reconnect_interval_sec,
        fail_on_mqtt_error=args.fail_on_mqtt_error,
    )
    validate_config(config)
    return config


def _option_present(argv: Sequence[str], option_name: str) -> bool:
    return any(arg == option_name or arg.startswith(option_name + "=") for arg in argv)


def _extract_env_file(argv: Sequence[str]) -> str | None:
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--env-file")
    namespace, _remaining = parser.parse_known_args(argv)
    return namespace.env_file


def main(argv: Sequence[str] | None = None) -> int:
    try:
        config = parse_config(argv)
    except (FileNotFoundError, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    bridge = VrpnMqttBridge(config)

    def _stop(_signum: int, _frame: object) -> None:
        bridge.stop()

    signal.signal(signal.SIGINT, _stop)
    signal.signal(signal.SIGTERM, _stop)
    bridge.run()
    return 0


def config_as_dict(config: BridgeConfig) -> dict[str, object]:
    return dataclasses.asdict(config)


if __name__ == "__main__":
    raise SystemExit(main())
