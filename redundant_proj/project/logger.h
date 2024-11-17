#ifndef LOGGER_H
#define LOGGER_H

#include <iostream>
#include <fstream>
#include <mutex>
#include <string>
#include <chrono>
#include <iomanip>     // For std::put_time, std::setfill, std::setw
#include <thread>      // For std::this_thread

class Logger {
public:
    static Logger& instance() {
        static Logger logger_instance;
        return logger_instance;
    }

    void log(const std::string &message) {
        std::lock_guard<std::mutex> lock(mutex_);
        auto now = std::chrono::system_clock::now();
        auto in_time_t = std::chrono::system_clock::to_time_t(now);
        auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                      now.time_since_epoch()) % 1000;

        logfile_ << std::put_time(std::localtime(&in_time_t), "%Y-%m-%d %X")
                 << "." << std::setfill('0') << std::setw(3) << ms.count()
                 << " [Thread " << std::this_thread::get_id() << "] " << message << std::endl;
    }

private:
    Logger() : logfile_("log.txt") {}
    ~Logger() {
        logfile_.close();
    }

    std::ofstream logfile_;
    std::mutex mutex_;
};

#endif // LOGGER_H