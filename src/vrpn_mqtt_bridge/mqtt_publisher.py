"""MQTT publishing wrapper."""

from __future__ import annotations

import json
from typing import Any

import paho.mqtt.client as mqtt

from vrpn_mqtt_bridge.config import BridgeConfig


class MqttPublisher:
    def __init__(self, config: BridgeConfig) -> None:
        self.config = config
        self.client = make_mqtt_client(config.client_id)
        if config.mqtt_username:
            self.client.username_pw_set(config.mqtt_username, config.mqtt_password)
        self.connected = False
        self.last_error = ""

    def start(self) -> None:
        if not self.config.dry_run:
            self.client.loop_start()

    def stop(self) -> None:
        if self.config.dry_run:
            return
        self.client.loop_stop()
        if self.connected:
            try:
                self.client.disconnect()
            except Exception:
                pass
        self.connected = False

    def connect(self) -> None:
        if self.config.dry_run:
            return
        self.client.connect(self.config.mqtt_host, self.config.mqtt_port, keepalive=30)
        self.connected = True
        self.last_error = ""

    def disconnect_after_error(self, exc: Exception) -> None:
        self.connected = False
        self.last_error = str(exc)
        try:
            self.client.disconnect()
        except Exception:
            pass

    def publish_json(self, topic: str, payload: dict[str, Any], *, retain: bool = False) -> None:
        if self.config.dry_run:
            return
        self.client.publish(topic, json.dumps(payload, separators=(",", ":")), qos=0, retain=retain)


def make_mqtt_client(client_id: str) -> mqtt.Client:
    callback_api_version = getattr(mqtt, "CallbackAPIVersion", None)
    if callback_api_version is not None:
        try:
            return mqtt.Client(callback_api_version.VERSION2, client_id=client_id)
        except (AttributeError, TypeError):
            pass
    return mqtt.Client(client_id=client_id)
