from vrpn_mqtt_bridge.bridge import VrpnMqttBridge
from vrpn_mqtt_bridge.config import config_from_env


class FakeTracker:
    def __init__(self):
        self.callback = None
        self.userdata = None

    def register_change_handler(self, userdata, callback, change_type):
        assert change_type == "position"
        self.userdata = userdata
        self.callback = callback

    def mainloop(self):
        return None

    def emit(self, message):
        self.callback(self.userdata, message)


class FakePublisher:
    def __init__(self):
        self.connected = True
        self.published = []
        self.last_error = ""

    def start(self):
        return None

    def stop(self):
        self.connected = False

    def connect(self):
        self.connected = True

    def disconnect_after_error(self, exc):
        self.connected = False
        self.last_error = str(exc)

    def publish_json(self, topic, payload, retain=False):
        self.published.append((topic, payload, retain))


def test_bridge_publishes_pose_and_yaw():
    config = config_from_env({"VRPN_MQTT_POSE_TOPIC": "pose", "VRPN_MQTT_YAW_TOPIC": "yaw", "VRPN_QUIET": "true"})
    tracker = FakeTracker()
    publisher = FakePublisher()
    bridge = VrpnMqttBridge(config, tracker=tracker, publisher=publisher)
    tracker.emit({"time": 1.0, "position": (1, 2, 3), "quaternion": (0, 0, 0, 1)})
    bridge._publish_latest_if_due(10.0)

    assert publisher.published[0][0] == "pose"
    assert publisher.published[0][1]["x"] == 1.0
    assert publisher.published[1][0] == "yaw"
    assert publisher.published[1][1]["yaw"] == 0.0
