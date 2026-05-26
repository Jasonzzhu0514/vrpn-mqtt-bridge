#include <netdb.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>
#include <vrpn_Connection.h>
#include <vrpn_Tracker.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <csignal>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cctype>
#include <ctime>
#include <iomanip>
#include <iostream>
#include <memory>
#include <sstream>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

namespace {

std::atomic<bool> g_should_exit{false};

constexpr double kDefaultMaxMqttRateHz = 10.0;
constexpr int kPosePrecision = 5;
constexpr int kMetricPrecision = 3;
constexpr std::size_t kMinPanelWidth = 70;
constexpr std::size_t kGroupColumnWidth = 12;
constexpr std::size_t kItemColumnWidth = 16;

struct Options {
    std::string env_file;
    std::string endpoint;
    std::string tracker = "tracker0";
    std::string vrpn_host = "127.0.0.1";
    int vrpn_port = 3883;
    int sample_ms = 2;

    std::string mqtt_host = "localhost";
    int mqtt_port = 1883;
    std::string mqtt_username;
    std::string mqtt_password;
    std::string mqtt_client_id = "vrpn-mqtt-bridge";
    std::string pose_topic = "slam/position";
    std::string yaw_topic = "slam/yaw";
    std::string status_topic = "slam/status";
    std::string frequency_topic = "slam/frequency";
    double max_mqtt_rate_hz = kDefaultMaxMqttRateHz;
    double status_interval_sec = 1.0;
    double timeout_sec = 5.0;
    double z_offset = 0.0;
    bool invert_yaw = false;
    bool vrpn_only = false;
    bool quiet = false;
};

struct Pose {
    double timestamp_sec = 0.0;
    double x = 0.0;
    double y = 0.0;
    double z = 0.0;
    double qx = 0.0;
    double qy = 0.0;
    double qz = 0.0;
    double qw = 1.0;
};

struct RuntimeState {
    Pose latest_pose;
    bool has_pose = false;
    double last_vrpn_wall_sec = 0.0;
    std::uint64_t vrpn_count = 0;
};

void handle_signal(int) {
    g_should_exit.store(true);
}

double now_sec() {
    using clock = std::chrono::steady_clock;
    static const auto start_steady = clock::now();
    static const auto start_system = std::chrono::system_clock::now();
    const auto elapsed = clock::now() - start_steady;
    const auto current = start_system + std::chrono::duration_cast<std::chrono::system_clock::duration>(elapsed);
    return std::chrono::duration<double>(current.time_since_epoch()).count();
}

std::int64_t now_ms() {
    return static_cast<std::int64_t>(now_sec() * 1000.0);
}

std::string local_time_text() {
    const std::time_t raw = std::time(nullptr);
    struct tm local {};
    localtime_r(&raw, &local);
    char buffer[20] = {0};
    std::strftime(buffer, sizeof(buffer), "%Y-%m-%d %H:%M:%S", &local);
    return buffer;
}

std::string duration_text(double seconds) {
    if (seconds < 0) {
        seconds = 0;
    }
    const auto total = static_cast<std::int64_t>(seconds);
    const auto days = total / 86400;
    const auto hours = (total % 86400) / 3600;
    const auto minutes = (total % 3600) / 60;
    const auto secs = total % 60;
    std::ostringstream out;
    if (days > 0) {
        out << days << "d ";
    }
    out << std::setfill('0') << std::setw(2) << hours << ":"
        << std::setw(2) << minutes << ":"
        << std::setw(2) << secs;
    return out.str();
}

void print_usage(const char* exe) {
    std::cout
        << "Usage: " << exe << " [options]\n"
        << "\n"
        << "Read a VRPN tracker pose and publish MQTT JSON payloads.\n"
        << "\n"
        << "Options:\n"
        << "  --env-file FILE           Load KEY=VALUE config file\n"
        << "  --endpoint NAME@HOST:PORT Full VRPN endpoint\n"
        << "  --tracker NAME            VRPN tracker name (default tracker0)\n"
        << "  --vrpn-host HOST          VRPN host (default 127.0.0.1)\n"
        << "  --vrpn-port PORT          VRPN port (default 3883)\n"
        << "  --mqtt-host HOST          MQTT host (default localhost)\n"
        << "  --mqtt-port PORT          MQTT port (default 1883)\n"
        << "  --mqtt-username USER      MQTT username\n"
        << "  --mqtt-password PASSWORD  MQTT password\n"
        << "  --pose-topic TOPIC        MQTT pose topic (default slam/position)\n"
        << "  --yaw-topic TOPIC         MQTT yaw topic (default slam/yaw)\n"
        << "  --status-topic TOPIC      MQTT status topic (default slam/status)\n"
        << "  --frequency-topic TOPIC   MQTT frequency topic (default slam/frequency)\n"
        << "  --max-mqtt-rate HZ        Pose publish limit (default " << kDefaultMaxMqttRateHz << ")\n"
        << "  --status-interval-sec SEC Status/frequency interval (default 1)\n"
        << "  --timeout-sec SEC         Stalled threshold (default 5)\n"
        << "  --z-offset METERS         Add offset to z\n"
        << "  --invert-yaw              Invert yaw sign\n"
        << "  --vrpn-only               Read VRPN without connecting to MQTT\n"
        << "  --quiet                   Suppress terminal status display\n"
        << "  --sample-ms MS            VRPN poll sleep in milliseconds (default 2)\n"
        << "  -h, --help                Show this help\n";
}

bool needs_value(int index, int argc, const char* name) {
    if (index + 1 < argc) {
        return true;
    }
    std::cerr << name << " requires a value\n";
    return false;
}

std::string trim(const std::string& value) {
    const auto first = value.find_first_not_of(" \t\r\n");
    if (first == std::string::npos) {
        return "";
    }
    const auto last = value.find_last_not_of(" \t\r\n");
    return value.substr(first, last - first + 1);
}

std::string strip_quotes(const std::string& value) {
    if (value.size() >= 2 && value.front() == value.back() && (value.front() == '"' || value.front() == '\'')) {
        return value.substr(1, value.size() - 2);
    }
    return value;
}

bool env_bool(const std::string& value, bool default_value) {
    std::string normalized = trim(value);
    std::transform(normalized.begin(), normalized.end(), normalized.begin(), [](unsigned char ch) {
        return static_cast<char>(std::tolower(ch));
    });
    if (normalized == "1" || normalized == "true" || normalized == "yes" || normalized == "on") {
        return true;
    }
    if (normalized == "0" || normalized == "false" || normalized == "no" || normalized == "off") {
        return false;
    }
    return default_value;
}

void apply_endpoint_parts(Options& opts) {
    const auto at = opts.endpoint.find('@');
    if (at == std::string::npos) {
        return;
    }
    const std::string endpoint_tracker = trim(opts.endpoint.substr(0, at));
    if (!endpoint_tracker.empty()) {
        opts.tracker = endpoint_tracker;
    }

    const std::string server = trim(opts.endpoint.substr(at + 1));
    if (server.empty()) {
        return;
    }
    const auto colon = server.rfind(':');
    if (colon == std::string::npos) {
        opts.vrpn_host = server;
        return;
    }
    const std::string host = trim(server.substr(0, colon));
    const std::string port = trim(server.substr(colon + 1));
    if (!host.empty()) {
        opts.vrpn_host = host;
    }
    if (!port.empty()) {
        opts.vrpn_port = std::atoi(port.c_str());
    }
}

void apply_config(Options& opts, const std::string& key, const std::string& value) {
    if (key == "VRPN_ENDPOINT") opts.endpoint = value;
    else if (key == "VRPN_TRACKER") opts.tracker = value;
    else if (key == "VRPN_HOST" || key == "VRPN_IP") opts.vrpn_host = value;
    else if (key == "VRPN_PORT") opts.vrpn_port = std::atoi(value.c_str());
    else if (key == "VRPN_MQTT_HOST" || key == "SLAM_MQTT_HOST") opts.mqtt_host = value;
    else if (key == "VRPN_MQTT_PORT" || key == "SLAM_MQTT_PORT") opts.mqtt_port = std::atoi(value.c_str());
    else if (key == "VRPN_MQTT_USERNAME" || key == "SLAM_MQTT_USERNAME") opts.mqtt_username = value;
    else if (key == "VRPN_MQTT_PASSWORD" || key == "SLAM_MQTT_PASSWORD") opts.mqtt_password = value;
    else if (key == "VRPN_MQTT_CLIENT_ID") opts.mqtt_client_id = value;
    else if (key == "VRPN_MQTT_POSE_TOPIC" || key == "SLAM_POSE_TOPIC") opts.pose_topic = value;
    else if (key == "VRPN_MQTT_YAW_TOPIC" || key == "SLAM_YAW_TOPIC") opts.yaw_topic = value;
    else if (key == "VRPN_MQTT_STATUS_TOPIC" || key == "SLAM_STATUS_TOPIC") opts.status_topic = value;
    else if (key == "VRPN_MQTT_FREQUENCY_TOPIC" || key == "SLAM_FREQUENCY_TOPIC") opts.frequency_topic = value;
    else if (key == "VRPN_MAX_MQTT_RATE" || key == "SLAM_MAX_MQTT_RATE") opts.max_mqtt_rate_hz = std::atof(value.c_str());
    else if (key == "VRPN_STATUS_INTERVAL_SEC") opts.status_interval_sec = std::atof(value.c_str());
    else if (key == "VRPN_TIMEOUT_SEC" || key == "SLAM_TIMEOUT_SEC") opts.timeout_sec = std::atof(value.c_str());
    else if (key == "VRPN_Z_OFFSET") opts.z_offset = std::atof(value.c_str());
    else if (key == "VRPN_INVERT_YAW") opts.invert_yaw = env_bool(value, opts.invert_yaw);
    else if (key == "VRPN_ONLY") opts.vrpn_only = env_bool(value, opts.vrpn_only);
    else if (key == "VRPN_QUIET") opts.quiet = env_bool(value, opts.quiet);
    else if (key == "VRPN_SAMPLE_MS") opts.sample_ms = std::atoi(value.c_str());
}

void load_env_file(Options& opts, const std::string& path) {
    FILE* file = std::fopen(path.c_str(), "r");
    if (!file) {
        throw std::runtime_error("env file not found: " + path);
    }
    char* line = nullptr;
    std::size_t size = 0;
    while (getline(&line, &size, file) != -1) {
        std::string raw = trim(line);
        if (raw.empty() || raw[0] == '#') {
            continue;
        }
        if (raw.rfind("export ", 0) == 0) {
            raw = trim(raw.substr(7));
        }
        const auto eq = raw.find('=');
        if (eq == std::string::npos) {
            continue;
        }
        const std::string key = trim(raw.substr(0, eq));
        const std::string value = strip_quotes(trim(raw.substr(eq + 1)));
        apply_config(opts, key, value);
    }
    std::free(line);
    std::fclose(file);
}

Options parse_args(int argc, char** argv) {
    Options opts;
    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        if (arg == "--env-file") {
            if (!needs_value(i, argc, "--env-file")) std::exit(2);
            opts.env_file = argv[++i];
            load_env_file(opts, opts.env_file);
            break;
        }
    }
    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        if (arg == "--env-file") {
            if (!needs_value(i, argc, "--env-file")) std::exit(2);
            opts.env_file = argv[++i];
        } else if (arg == "--endpoint" || arg == "--vrpn-endpoint") {
            if (!needs_value(i, argc, arg.c_str())) std::exit(2);
            opts.endpoint = argv[++i];
        } else if (arg == "--tracker") {
            if (!needs_value(i, argc, "--tracker")) std::exit(2);
            opts.tracker = argv[++i];
        } else if (arg == "--vrpn-host" || arg == "--ip") {
            if (!needs_value(i, argc, arg.c_str())) std::exit(2);
            opts.vrpn_host = argv[++i];
        } else if (arg == "--vrpn-port") {
            if (!needs_value(i, argc, "--vrpn-port")) std::exit(2);
            opts.vrpn_port = std::atoi(argv[++i]);
        } else if (arg == "--mqtt-host") {
            if (!needs_value(i, argc, "--mqtt-host")) std::exit(2);
            opts.mqtt_host = argv[++i];
        } else if (arg == "--mqtt-port") {
            if (!needs_value(i, argc, "--mqtt-port")) std::exit(2);
            opts.mqtt_port = std::atoi(argv[++i]);
        } else if (arg == "--mqtt-username") {
            if (!needs_value(i, argc, "--mqtt-username")) std::exit(2);
            opts.mqtt_username = argv[++i];
        } else if (arg == "--mqtt-password") {
            if (!needs_value(i, argc, "--mqtt-password")) std::exit(2);
            opts.mqtt_password = argv[++i];
        } else if (arg == "--pose-topic") {
            if (!needs_value(i, argc, "--pose-topic")) std::exit(2);
            opts.pose_topic = argv[++i];
        } else if (arg == "--yaw-topic") {
            if (!needs_value(i, argc, "--yaw-topic")) std::exit(2);
            opts.yaw_topic = argv[++i];
        } else if (arg == "--status-topic") {
            if (!needs_value(i, argc, "--status-topic")) std::exit(2);
            opts.status_topic = argv[++i];
        } else if (arg == "--frequency-topic") {
            if (!needs_value(i, argc, "--frequency-topic")) std::exit(2);
            opts.frequency_topic = argv[++i];
        } else if (arg == "--max-mqtt-rate") {
            if (!needs_value(i, argc, "--max-mqtt-rate")) std::exit(2);
            opts.max_mqtt_rate_hz = std::atof(argv[++i]);
        } else if (arg == "--status-interval-sec") {
            if (!needs_value(i, argc, "--status-interval-sec")) std::exit(2);
            opts.status_interval_sec = std::atof(argv[++i]);
        } else if (arg == "--timeout-sec") {
            if (!needs_value(i, argc, "--timeout-sec")) std::exit(2);
            opts.timeout_sec = std::atof(argv[++i]);
        } else if (arg == "--z-offset") {
            if (!needs_value(i, argc, "--z-offset")) std::exit(2);
            opts.z_offset = std::atof(argv[++i]);
        } else if (arg == "--invert-yaw") {
            opts.invert_yaw = true;
        } else if (arg == "--vrpn-only") {
            opts.vrpn_only = true;
        } else if (arg == "--quiet") {
            opts.quiet = true;
        } else if (arg == "--sample-ms") {
            if (!needs_value(i, argc, "--sample-ms")) std::exit(2);
            opts.sample_ms = std::atoi(argv[++i]);
        } else if (arg == "-h" || arg == "--help") {
            print_usage(argv[0]);
            std::exit(0);
        } else {
            std::cerr << "unknown argument: " << arg << "\n";
            print_usage(argv[0]);
            std::exit(2);
        }
    }
    if (opts.endpoint.empty()) {
        opts.endpoint = opts.tracker + "@" + opts.vrpn_host + ":" + std::to_string(opts.vrpn_port);
    } else {
        apply_endpoint_parts(opts);
    }
    if (opts.sample_ms < 1) opts.sample_ms = 1;
    if (opts.max_mqtt_rate_hz <= 0) opts.max_mqtt_rate_hz = kDefaultMaxMqttRateHz;
    if (opts.status_interval_sec <= 0) opts.status_interval_sec = 1.0;
    if (opts.timeout_sec <= 0) opts.timeout_sec = 5.0;
    return opts;
}

std::vector<std::uint8_t> encode_string(const std::string& value) {
    if (value.size() > 65535) {
        throw std::runtime_error("MQTT string is too long");
    }
    std::vector<std::uint8_t> out;
    out.push_back(static_cast<std::uint8_t>((value.size() >> 8) & 0xff));
    out.push_back(static_cast<std::uint8_t>(value.size() & 0xff));
    out.insert(out.end(), value.begin(), value.end());
    return out;
}

void append_string(std::vector<std::uint8_t>& target, const std::string& value) {
    const auto encoded = encode_string(value);
    target.insert(target.end(), encoded.begin(), encoded.end());
}

std::vector<std::uint8_t> encode_remaining_length(std::size_t length) {
    std::vector<std::uint8_t> out;
    do {
        std::uint8_t byte = static_cast<std::uint8_t>(length % 128);
        length /= 128;
        if (length > 0) byte |= 0x80;
        out.push_back(byte);
    } while (length > 0);
    return out;
}

void send_all(int fd, const std::vector<std::uint8_t>& data) {
    std::size_t sent = 0;
    while (sent < data.size()) {
        const ssize_t rc = ::send(fd, data.data() + sent, data.size() - sent, MSG_NOSIGNAL);
        if (rc <= 0) {
            throw std::runtime_error("socket send failed");
        }
        sent += static_cast<std::size_t>(rc);
    }
}

class MqttClient {
   public:
    explicit MqttClient(const Options& options) : opts_(options) {}

    ~MqttClient() {
        close();
    }

    void connect() {
        close();
        struct addrinfo hints {};
        hints.ai_family = AF_UNSPEC;
        hints.ai_socktype = SOCK_STREAM;
        struct addrinfo* result = nullptr;
        const std::string port = std::to_string(opts_.mqtt_port);
        const int gai = getaddrinfo(opts_.mqtt_host.c_str(), port.c_str(), &hints, &result);
        if (gai != 0) {
            throw std::runtime_error(std::string("MQTT DNS lookup failed: ") + gai_strerror(gai));
        }
        for (auto* rp = result; rp != nullptr; rp = rp->ai_next) {
            fd_ = socket(rp->ai_family, rp->ai_socktype, rp->ai_protocol);
            if (fd_ < 0) continue;
            struct timeval timeout {};
            timeout.tv_sec = 5;
            setsockopt(fd_, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
            setsockopt(fd_, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
            if (::connect(fd_, rp->ai_addr, rp->ai_addrlen) == 0) break;
            ::close(fd_);
            fd_ = -1;
        }
        freeaddrinfo(result);
        if (fd_ < 0) {
            throw std::runtime_error("MQTT TCP connect failed");
        }
        send_connect_packet();
        read_connack();
        connected_ = true;
    }

    bool connected() const {
        return connected_;
    }

    void close() {
        if (fd_ >= 0) {
            const std::vector<std::uint8_t> disconnect = {0xe0, 0x00};
            (void)::send(fd_, disconnect.data(), disconnect.size(), MSG_NOSIGNAL);
            ::close(fd_);
        }
        fd_ = -1;
        connected_ = false;
    }

    void publish(const std::string& topic, const std::string& payload, bool retain = false) {
        if (!connected_) {
            connect();
        }
        std::vector<std::uint8_t> variable;
        append_string(variable, topic);
        variable.insert(variable.end(), payload.begin(), payload.end());

        std::vector<std::uint8_t> packet;
        packet.push_back(static_cast<std::uint8_t>(0x30 | (retain ? 0x01 : 0x00)));
        const auto remaining = encode_remaining_length(variable.size());
        packet.insert(packet.end(), remaining.begin(), remaining.end());
        packet.insert(packet.end(), variable.begin(), variable.end());
        send_all(fd_, packet);
    }

   private:
    void send_connect_packet() {
        if (!opts_.mqtt_password.empty() && opts_.mqtt_username.empty()) {
            throw std::runtime_error("MQTT password requires MQTT username");
        }
        std::vector<std::uint8_t> payload;
        append_string(payload, opts_.mqtt_client_id);
        if (!opts_.mqtt_username.empty()) append_string(payload, opts_.mqtt_username);
        if (!opts_.mqtt_password.empty()) append_string(payload, opts_.mqtt_password);

        std::vector<std::uint8_t> variable;
        append_string(variable, "MQTT");
        variable.push_back(4);
        std::uint8_t flags = 0x02;
        if (!opts_.mqtt_username.empty()) flags |= 0x80;
        if (!opts_.mqtt_password.empty()) flags |= 0x40;
        variable.push_back(flags);
        variable.push_back(0);
        variable.push_back(30);
        variable.insert(variable.end(), payload.begin(), payload.end());

        std::vector<std::uint8_t> packet;
        packet.push_back(0x10);
        const auto remaining = encode_remaining_length(variable.size());
        packet.insert(packet.end(), remaining.begin(), remaining.end());
        packet.insert(packet.end(), variable.begin(), variable.end());
        send_all(fd_, packet);
    }

    void read_connack() {
        std::uint8_t response[4] = {0, 0, 0, 0};
        const ssize_t rc = recv(fd_, response, sizeof(response), MSG_WAITALL);
        if (rc != 4 || response[0] != 0x20 || response[1] != 0x02 || response[3] != 0x00) {
            throw std::runtime_error("MQTT CONNACK rejected");
        }
    }

    const Options& opts_;
    int fd_ = -1;
    bool connected_ = false;
};

std::string json_escape(const std::string& value) {
    std::ostringstream out;
    for (char ch : value) {
        switch (ch) {
            case '"': out << "\\\""; break;
            case '\\': out << "\\\\"; break;
            case '\n': out << "\\n"; break;
            case '\r': out << "\\r"; break;
            case '\t': out << "\\t"; break;
            default: out << ch; break;
        }
    }
    return out.str();
}

double yaw_from_quaternion(const Pose& pose) {
    const double siny_cosp = 2.0 * (pose.qw * pose.qz + pose.qx * pose.qy);
    const double cosy_cosp = 1.0 - 2.0 * (pose.qy * pose.qy + pose.qz * pose.qz);
    return std::atan2(siny_cosp, cosy_cosp) * 180.0 / M_PI;
}

double normalize_yaw(double yaw) {
    double normalized = std::fmod(yaw + 180.0, 360.0);
    if (normalized < 0) normalized += 360.0;
    normalized -= 180.0;
    return normalized == -180.0 ? 180.0 : normalized;
}

std::string format_decimal(double value, int precision) {
    std::ostringstream out;
    out << std::fixed << std::setprecision(precision) << value;
    return out.str();
}

std::string pose_payload(const Options& opts, const Pose& pose) {
    std::ostringstream out;
    out << "{\"timestamp\":" << static_cast<std::int64_t>(pose.timestamp_sec * 1000.0)
        << ",\"source\":\"vrpn\""
        << ",\"tracker\":\"" << json_escape(opts.tracker) << "\""
        << ",\"x\":" << format_decimal(pose.x, kPosePrecision)
        << ",\"y\":" << format_decimal(pose.y, kPosePrecision)
        << ",\"z\":" << format_decimal(pose.z + opts.z_offset, kPosePrecision)
        << "}";
    return out.str();
}

std::string yaw_payload(const Options& opts, const Pose& pose) {
    double yaw = yaw_from_quaternion(pose);
    if (opts.invert_yaw) yaw = -yaw;
    std::ostringstream out;
    out << "{\"timestamp\":" << static_cast<std::int64_t>(pose.timestamp_sec * 1000.0)
        << ",\"source\":\"vrpn\""
        << ",\"tracker\":\"" << json_escape(opts.tracker) << "\""
        << ",\"yaw\":" << format_decimal(normalize_yaw(yaw), kPosePrecision)
        << "}";
    return out.str();
}

std::string status_payload(const Options& opts, const std::string& status, double age_sec) {
    std::ostringstream out;
    out << "{\"timestamp\":" << now_ms()
        << ",\"source\":\"vrpn\""
        << ",\"tracker\":\"" << json_escape(opts.tracker) << "\""
        << ",\"status\":\"" << status << "\""
        << ",\"last_pose_age_sec\":";
    if (age_sec < 0) {
        out << "null";
    } else {
        out << format_decimal(age_sec, kMetricPrecision);
    }
    out << "}";
    return out.str();
}

std::string frequency_payload(const Options& opts, double vrpn_hz, double mqtt_hz) {
    std::ostringstream out;
    out << "{\"timestamp\":" << now_ms()
        << ",\"source\":\"vrpn\""
        << ",\"tracker\":\"" << json_escape(opts.tracker) << "\""
        << ",\"vrpn\":" << format_decimal(vrpn_hz, kMetricPrecision)
        << ",\"mqtt\":" << format_decimal(mqtt_hz, kMetricPrecision)
        << "}";
    return out.str();
}

bool publish_or_skip(MqttClient& mqtt,
                     const Options& opts,
                     const std::string& topic,
                     const std::string& payload,
                     std::string& mqtt_status,
                     bool retain = false) {
    if (opts.vrpn_only) {
        mqtt_status = "disabled";
        return false;
    }
    try {
        mqtt.publish(topic, payload, retain);
        mqtt_status = "ok";
        return true;
    } catch (const std::exception&) {
        mqtt.close();
        mqtt_status = "error";
        return false;
    }
}

std::string center_cell(const std::string& value, std::size_t width) {
    if (width == 0) {
        return "";
    }
    if (value.size() > width) {
        if (width == 1) {
            return "~";
        }
        return value.substr(0, width - 1) + "~";
    }
    const std::size_t total_padding = width - value.size();
    const std::size_t left_padding = total_padding / 2;
    const std::size_t right_padding = total_padding - left_padding;
    return std::string(left_padding, ' ') + value + std::string(right_padding, ' ');
}

std::size_t terminal_columns() {
    struct winsize size {};
    if (ioctl(STDOUT_FILENO, TIOCGWINSZ, &size) == 0 && size.ws_col > 20) {
        return static_cast<std::size_t>(size.ws_col);
    }
    return 80;
}

std::string trim_to_terminal(std::string line) {
    const std::size_t columns = terminal_columns();
    if (columns <= 1) {
        return "";
    }
    const std::size_t max_width = columns - 1;
    if (line.size() > max_width) {
        line.resize(max_width);
    }
    return line;
}

std::size_t panel_width() {
    const std::size_t columns = terminal_columns();
    if (columns <= kMinPanelWidth + 1) {
        return kMinPanelWidth;
    }
    return columns - 1;
}

std::size_t value_column_width(std::size_t width) {
    const std::size_t fixed_width = kGroupColumnWidth + kItemColumnWidth + 10;
    if (width <= fixed_width) {
        return 32;
    }
    return width - fixed_width;
}

std::string panel_border(std::size_t width) {
    return "x" + std::string(width - 2, '=') + "x";
}

std::string panel_title(const std::string& value, std::size_t width) {
    return "| " + center_cell(value, width - 4) + " |";
}

std::string panel_rule(std::size_t width) {
    return "|" + std::string(width - 2, '-') + "|";
}

std::string panel_table_row(const std::string& group,
                            const std::string& item,
                            const std::string& value,
                            std::size_t width) {
    return "| " + center_cell(group, kGroupColumnWidth) +
           " | " + center_cell(item, kItemColumnWidth) +
           " | " + center_cell(value, value_column_width(width)) + " |";
}

std::vector<std::string> live_pose_values(const Options& opts, const RuntimeState& state) {
    std::string x = "-";
    std::string y = "-";
    std::string z = "-";
    std::string yaw = "-";
    if (state.has_pose) {
        double current_yaw = yaw_from_quaternion(state.latest_pose);
        if (opts.invert_yaw) current_yaw = -current_yaw;
        x = format_decimal(state.latest_pose.x, kPosePrecision);
        y = format_decimal(state.latest_pose.y, kPosePrecision);
        z = format_decimal(state.latest_pose.z + opts.z_offset, kPosePrecision);
        yaw = format_decimal(normalize_yaw(current_yaw), kPosePrecision);
    }

    return {x, y, z, yaw};
}

std::string mode_text(const Options& opts) {
    return opts.vrpn_only ? "vrpn-only" : "normal";
}

std::vector<std::string> live_status_table(const Options& opts,
                                           const RuntimeState& state,
                                           const std::string& vrpn_status,
                                           const std::string& mqtt_status,
                                           double duration_sec,
                                           double age_sec,
                                           double vrpn_hz,
                                           double mqtt_hz) {
    const std::vector<std::string> pose = live_pose_values(opts, state);
    const std::size_t width = panel_width();
    return {panel_border(width),
            panel_title("VRPN MQTT Bridge", width),
            panel_rule(width),
            panel_table_row("GROUP", "ITEM", "VALUE", width),
            panel_rule(width),
            panel_table_row("OVERVIEW", "time", local_time_text(), width),
            panel_table_row("OVERVIEW", "duration", duration_text(duration_sec), width),
            panel_table_row("OVERVIEW", "mode", mode_text(opts), width),
            panel_table_row("OVERVIEW", "tracker", opts.tracker, width),
            panel_rule(width),
            panel_table_row("VRPN", "status", vrpn_status, width),
            panel_table_row("VRPN", "lag", age_sec < 0 ? "-" : format_decimal(age_sec, 1), width),
            panel_table_row("VRPN", "rec_hz", format_decimal(vrpn_hz, 1), width),
            panel_rule(width),
            panel_table_row("MQTT", "status", mqtt_status, width),
            panel_table_row("MQTT", "pub_hz", format_decimal(mqtt_hz, 1), width),
            panel_rule(width),
            panel_table_row("DATA", "x", pose[0], width),
            panel_table_row("DATA", "y", pose[1], width),
            panel_table_row("DATA", "z", pose[2], width),
            panel_table_row("DATA", "yaw", pose[3], width),
            panel_border(width)};
}

class LiveStatus {
   public:
    explicit LiveStatus(const Options& opts) : enabled_(!opts.quiet && isatty(STDOUT_FILENO)) {}

    ~LiveStatus() {
        finish();
    }

    void render(const Options& opts,
                const RuntimeState& state,
                const std::string& vrpn_status,
                const std::string& mqtt_status,
                double duration_sec,
                double age_sec,
                double vrpn_hz,
                double mqtt_hz) {
        if (!enabled_) {
            return;
        }
        const auto lines = live_status_table(opts, state, vrpn_status, mqtt_status, duration_sec, age_sec, vrpn_hz, mqtt_hz);
        if (printed_ && line_count_ > 0) {
            std::cout << "\033[" << line_count_ << "A";
        } else {
            printed_ = true;
        }
        line_count_ = lines.size();
        for (std::size_t i = 0; i < lines.size(); ++i) {
            std::cout << "\r\033[2K" << trim_to_terminal(lines[i]);
            if (i + 1 < lines.size()) {
                std::cout << "\n";
            }
        }
        std::cout << "\n" << std::flush;
    }

    void finish() {
        if (enabled_ && printed_) {
            std::cout << "\n";
            printed_ = false;
        }
    }

   private:
    bool enabled_ = false;
    bool printed_ = false;
    std::size_t line_count_ = 0;
};

void print_startup_config(const Options& opts) {
    if (opts.quiet) {
        return;
    }
    std::cout << "VRPN MQTT Bridge\n"
              << "  time: " << local_time_text() << "\n"
              << "  mode: " << mode_text(opts) << "\n"
              << "  route: VRPN " << opts.tracker << "@"
              << opts.vrpn_host << ":" << opts.vrpn_port
              << " -> MQTT " << opts.mqtt_host << ":" << opts.mqtt_port << "\n"
              << "  vrpn_tracker: " << opts.tracker << "\n"
              << "  vrpn_server: " << opts.vrpn_host << ":" << opts.vrpn_port << "\n"
              << "  mqtt_broker: " << opts.mqtt_host << ":" << opts.mqtt_port << "\n"
              << "  mqtt_topics: " << opts.pose_topic << ", "
              << opts.yaw_topic << ", "
              << opts.status_topic << ", "
              << opts.frequency_topic << "\n"
              << "  max_mqtt_rate_hz: " << format_decimal(opts.max_mqtt_rate_hz, 1) << "\n"
              << "  status_interval_sec: " << format_decimal(opts.status_interval_sec, 1) << "\n"
              << "  timeout_sec: " << format_decimal(opts.timeout_sec, 1) << "\n";
    if (opts.invert_yaw) {
        std::cout << "  invert_yaw: true\n";
    }
    if (opts.z_offset != 0.0) {
        std::cout << "  z_offset: " << format_decimal(opts.z_offset, kMetricPrecision) << "\n";
    }
    std::cout << "\n" << std::flush;
}

void VRPN_CALLBACK handle_tracker(void* userdata, const vrpn_TRACKERCB info) {
    auto* state = static_cast<RuntimeState*>(userdata);
    state->latest_pose.timestamp_sec = static_cast<double>(info.msg_time.tv_sec) +
                                       static_cast<double>(info.msg_time.tv_usec) / 1000000.0;
    state->latest_pose.x = info.pos[0];
    state->latest_pose.y = info.pos[1];
    state->latest_pose.z = info.pos[2];
    state->latest_pose.qx = info.quat[0];
    state->latest_pose.qy = info.quat[1];
    state->latest_pose.qz = info.quat[2];
    state->latest_pose.qw = info.quat[3];
    state->has_pose = true;
    state->last_vrpn_wall_sec = now_sec();
    state->vrpn_count += 1;
}

}  // namespace

int main(int argc, char** argv) {
    std::signal(SIGINT, handle_signal);
    std::signal(SIGTERM, handle_signal);

    try {
        Options opts = parse_args(argc, argv);
        RuntimeState state;

        print_startup_config(opts);

        const double started_at = now_sec();
        MqttClient mqtt(opts);
        std::string mqtt_status = opts.vrpn_only ? "disabled" : "init";

        LiveStatus live_status(opts);
        live_status.render(opts, state, "waiting", mqtt_status, 0.0, -1.0, 0.0, 0.0);

        std::unique_ptr<vrpn_Tracker_Remote> tracker(new vrpn_Tracker_Remote(opts.endpoint.c_str()));
        tracker->register_change_handler(&state, &handle_tracker);

        double last_publish = 0.0;
        double last_status = 0.0;
        double last_render = 0.0;
        double stat_at = now_sec();
        double latest_vrpn_hz = 0.0;
        double latest_mqtt_hz = 0.0;
        std::string latest_vrpn_status = "waiting";
        std::uint64_t vrpn_count_at_stat = 0;
        std::uint64_t mqtt_count_at_stat = 0;
        std::uint64_t mqtt_count = 0;

        while (!g_should_exit.load()) {
            tracker->mainloop();
            if (auto* connection = tracker->connectionPtr()) {
                connection->mainloop();
            }

            const double now = now_sec();
            if (state.has_pose && now - last_publish >= 1.0 / opts.max_mqtt_rate_hz) {
                const bool pose_ok = publish_or_skip(mqtt, opts, opts.pose_topic, pose_payload(opts, state.latest_pose), mqtt_status);
                const bool yaw_ok = publish_or_skip(mqtt, opts, opts.yaw_topic, yaw_payload(opts, state.latest_pose), mqtt_status);
                if (pose_ok && yaw_ok) {
                    mqtt_count += 1;
                }
                last_publish = now;
            }

            if (now - last_status >= opts.status_interval_sec) {
                const double age = state.has_pose ? now - state.last_vrpn_wall_sec : -1.0;
                latest_vrpn_status = "waiting";
                if (state.has_pose && age <= opts.timeout_sec) latest_vrpn_status = "running";
                if (state.has_pose && age > opts.timeout_sec) latest_vrpn_status = "stalled";
                publish_or_skip(mqtt, opts, opts.status_topic, status_payload(opts, latest_vrpn_status, age), mqtt_status, true);

                const double dt = now - stat_at;
                if (dt > 0) {
                    latest_vrpn_hz = static_cast<double>(state.vrpn_count - vrpn_count_at_stat) / dt;
                    latest_mqtt_hz = static_cast<double>(mqtt_count - mqtt_count_at_stat) / dt;
                    publish_or_skip(mqtt, opts, opts.frequency_topic, frequency_payload(opts, latest_vrpn_hz, latest_mqtt_hz), mqtt_status);
                    vrpn_count_at_stat = state.vrpn_count;
                    mqtt_count_at_stat = mqtt_count;
                    stat_at = now;
                }
                last_status = now;
            }

            if (now - last_render >= 0.1) {
                const double age = state.has_pose ? now - state.last_vrpn_wall_sec : -1.0;
                live_status.render(opts, state, latest_vrpn_status, mqtt_status, now - started_at, age, latest_vrpn_hz, latest_mqtt_hz);
                last_render = now;
            }

            std::this_thread::sleep_for(std::chrono::milliseconds(opts.sample_ms));
        }

        tracker->unregister_change_handler(&state, &handle_tracker);
        publish_or_skip(mqtt, opts, opts.status_topic, status_payload(opts, "idle", -1.0), mqtt_status, true);
    } catch (const std::exception& exc) {
        std::cerr << "error: " << exc.what() << "\n";
        return 1;
    }

    return 0;
}
