#include <vrpn_Connection.h>
#include <vrpn_Tracker.h>

#include <atomic>
#include <chrono>
#include <csignal>
#include <cstdlib>
#include <cstring>
#include <iomanip>
#include <iostream>
#include <memory>
#include <sstream>
#include <stdexcept>
#include <string>
#include <thread>

namespace {

std::atomic<bool> g_should_exit{false};

struct Options {
    std::string endpoint;
    std::string tracker = "tracker";
    std::string host = "127.0.0.1";
    int port = 3883;
    int sample_ms = 2;
};

void handle_signal(int) {
    g_should_exit.store(true);
}

void print_usage(const char* exe) {
    std::cout
        << "Usage: " << exe << " [options]\n"
        << "\n"
        << "Read a VRPN tracker and print pose messages as JSON Lines.\n"
        << "\n"
        << "Options:\n"
        << "  --endpoint NAME@HOST:PORT  Full VRPN endpoint\n"
        << "  --tracker NAME             Tracker name (default tracker)\n"
        << "  --host HOST                VRPN host (default 127.0.0.1)\n"
        << "  --port PORT                VRPN port (default 3883)\n"
        << "  --sample-ms MS             Poll sleep in milliseconds (default 2)\n"
        << "  -h, --help                 Show this help\n";
}

bool needs_value(int index, int argc, const char* name) {
    if (index + 1 < argc) {
        return true;
    }
    std::cerr << name << " requires a value\n";
    return false;
}

Options parse_args(int argc, char** argv) {
    Options opts;
    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        if (arg == "--endpoint") {
            if (!needs_value(i, argc, "--endpoint")) {
                std::exit(2);
            }
            opts.endpoint = argv[++i];
        } else if (arg == "--tracker") {
            if (!needs_value(i, argc, "--tracker")) {
                std::exit(2);
            }
            opts.tracker = argv[++i];
        } else if (arg == "--host") {
            if (!needs_value(i, argc, "--host")) {
                std::exit(2);
            }
            opts.host = argv[++i];
        } else if (arg == "--port") {
            if (!needs_value(i, argc, "--port")) {
                std::exit(2);
            }
            opts.port = std::atoi(argv[++i]);
        } else if (arg == "--sample-ms") {
            if (!needs_value(i, argc, "--sample-ms")) {
                std::exit(2);
            }
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
        opts.endpoint = opts.tracker + "@" + opts.host + ":" + std::to_string(opts.port);
    }
    if (opts.sample_ms < 1) {
        opts.sample_ms = 1;
    }
    return opts;
}

std::string json_escape(const std::string& value) {
    std::ostringstream out;
    for (char ch : value) {
        switch (ch) {
            case '"':
                out << "\\\"";
                break;
            case '\\':
                out << "\\\\";
                break;
            case '\n':
                out << "\\n";
                break;
            case '\r':
                out << "\\r";
                break;
            case '\t':
                out << "\\t";
                break;
            default:
                out << ch;
                break;
        }
    }
    return out.str();
}

void VRPN_CALLBACK handle_tracker(void* userdata, const vrpn_TRACKERCB info) {
    auto* endpoint = static_cast<std::string*>(userdata);
    const double timestamp = static_cast<double>(info.msg_time.tv_sec) +
                             static_cast<double>(info.msg_time.tv_usec) / 1000000.0;
    std::cout << std::setprecision(17)
              << "{\"time\":" << timestamp
              << ",\"endpoint\":\"" << json_escape(*endpoint) << "\""
              << ",\"position\":[" << info.pos[0] << "," << info.pos[1] << "," << info.pos[2] << "]"
              << ",\"quaternion\":[" << info.quat[0] << "," << info.quat[1] << ","
              << info.quat[2] << "," << info.quat[3] << "]}"
              << std::endl;
}

}  // namespace

int main(int argc, char** argv) {
    std::signal(SIGINT, handle_signal);
    std::signal(SIGTERM, handle_signal);

    const Options opts = parse_args(argc, argv);

    try {
        std::unique_ptr<vrpn_Tracker_Remote> tracker(new vrpn_Tracker_Remote(opts.endpoint.c_str()));
        tracker->register_change_handler(const_cast<std::string*>(&opts.endpoint), &handle_tracker);

        while (!g_should_exit.load()) {
            tracker->mainloop();
            if (auto* connection = tracker->connectionPtr()) {
                connection->mainloop();
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(opts.sample_ms));
        }
        tracker->unregister_change_handler(const_cast<std::string*>(&opts.endpoint), &handle_tracker);
    } catch (const std::exception& exc) {
        std::cerr << "error: " << exc.what() << "\n";
        return 1;
    }

    return 0;
}
