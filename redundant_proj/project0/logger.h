// logger.h

#ifndef LOGGER_H
#define LOGGER_H

#include <fstream>
#include <mutex>
#include <string>

class Logger {
public:
    static Logger& instance() {
        static Logger logger_instance;
        return logger_instance;
    }

    void log(const std::string &message) {
        std::lock_guard<std::mutex> lock(mutex_);
        logfile_ << message << std::endl;
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
