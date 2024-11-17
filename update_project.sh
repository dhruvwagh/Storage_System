#!/bin/bash

# -----------------------------------------------------------------------------
# update_project.sh
#
# A Bash script to update project files with enhanced logging and fixed SSD
# initialization. It backs up existing files before replacing them with the
# updated content.
#
# Usage:
#   chmod +x update_project.sh    # Make the script executable
#   ./update_project.sh           # Run the script
# -----------------------------------------------------------------------------

# Exit immediately if a command exits with a non-zero status
set -e

# -----------------------------------------------------------------------------
# Configuration Variables
# -----------------------------------------------------------------------------

# Define the project root directory (adjust this path as needed)
PROJECT_ROOT=~/Documents/Storage_System/project

# Define the source directory where your .cpp and .h files are located
SRC_DIR="$PROJECT_ROOT/src"

# Define the log directory (ensure it exists)
LOG_DIR="$PROJECT_ROOT/logs"
mkdir -p "$LOG_DIR"

# Timestamp for backups
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# -----------------------------------------------------------------------------
# Logging Functions for the Script
# -----------------------------------------------------------------------------

# Function to log informational messages
log_info() {
    echo -e "\e[34m[INFO]\e[0m $1"
}

# Function to log error messages
log_error() {
    echo -e "\e[31m[ERROR]\e[0m $1" >&2
}

# Function to log success messages
log_success() {
    echo -e "\e[32m[SUCCESS]\e[0m $1"
}

# -----------------------------------------------------------------------------
# Function to Backup Existing Files
# -----------------------------------------------------------------------------

backup_file() {
    local file_path="$1"
    local backup_path="$LOG_DIR/$(basename "$file_path").bak_$TIMESTAMP"

    if [[ -f "$file_path" ]]; then
        cp "$file_path" "$backup_path"
        log_info "Backed up $(basename "$file_path") to $backup_path"
    else
        log_info "File $(basename "$file_path") does not exist. Skipping backup."
    fi
}

# -----------------------------------------------------------------------------
# Function to Replace Files with Updated Content Using Heredoc
# -----------------------------------------------------------------------------

replace_file() {
    local file_path="$1"
    local file_name=$(basename "$file_path")
    local content="$2"

    log_info "Updating $file_name..."

    # Use heredoc to write multi-line content
    cat << 'EOF' > "$file_path"
$content
EOF

    log_success "Updated $file_name successfully."
}

# -----------------------------------------------------------------------------
# Function to Update logger.h
# -----------------------------------------------------------------------------

update_logger_h() {
    local file_path="$SRC_DIR/logger.h"

    backup_file "$file_path"

    local content='// logger.h

#ifndef LOGGER_H
#define LOGGER_H

#include <fstream>
#include <mutex>
#include <string>
#include <chrono>
#include <iomanip>
#include <thread>

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
'

    replace_file "$file_path" "$content"
}

# -----------------------------------------------------------------------------
# Function to Update disk_queue.h
# -----------------------------------------------------------------------------

update_disk_queue_h() {
    local file_path="$SRC_DIR/disk_queue.h"

    backup_file "$file_path"

    local content='// disk_queue.h

#ifndef DISK_QUEUE_H
#define DISK_QUEUE_H

#include <queue>
#include <mutex>
#include <condition_variable>
#include <cstddef>
#include "logger.h"

template<typename T>
class DiskQueue {
public:
    void enqueue(const T &item) {
        std::unique_lock<std::mutex> lock(mutex_);
        if (queue_.size() >= MAX_QUEUE_SIZE) {
            Logger::instance().log("DiskQueue full, waiting to enqueue.");
            // Apply backpressure: wait until there\'s space
            condition_full_.wait(lock, [this]() { return queue_.size() < MAX_QUEUE_SIZE; });
        }
        queue_.push(item);
        Logger::instance().log("Enqueued operation: " + item.page_id);
        condition_.notify_one();
    }

    T dequeue() {
        std::unique_lock<std::mutex> lock(mutex_);
        while (queue_.empty()) {
            Logger::instance().log("DiskQueue empty, waiting to dequeue.");
            condition_.wait(lock);
        }
        T item = queue_.front();
        queue_.pop();
        Logger::instance().log("Dequeued operation: " + item.page_id);
        condition_full_.notify_one();
        return item;
    }

    size_t size() const {
        std::lock_guard<std::mutex> lock(mutex_);
        return queue_.size();
    }

private:
    static const size_t MAX_QUEUE_SIZE = 1000; // Set an appropriate limit
    std::queue<T> queue_;
    mutable std::mutex mutex_;
    std::condition_variable condition_;
    std::condition_variable condition_full_;
};

#endif // DISK_QUEUE_H
'

    replace_file "$file_path" "$content"
}

# -----------------------------------------------------------------------------
# Function to Update ssd_model.cpp
# -----------------------------------------------------------------------------

update_ssd_model_cpp() {
    local file_path="$SRC_DIR/ssd_model.cpp"

    backup_file "$file_path"

    local content='// ssd_model.cpp

#include "ssd_model.h"
#include "disk_queue.h"
#include "logger.h"

#include <chrono>
#include <thread>
#include <algorithm>
#include <memory>
#include <random>

// External variables from main.cpp
extern std::vector<DiskQueue<Operation>> disk_queues;
extern std::vector<std::unique_ptr<SSDModel>> ssds;

SSDModel::SSDModel(int id)
    : drive_id(id),
      read_latency_us(100),     // Average read latency in microseconds
      write_latency_us(200) {}  // Average write latency in microseconds

void SSDModel::simulate_latency(int avg_latency_us) {
    static thread_local std::default_random_engine generator(std::random_device{}());
    std::normal_distribution<double> distribution(avg_latency_us, avg_latency_us * 0.1);
    int latency = std::max(1, static_cast<int>(distribution(generator)));
    Logger::instance().log("SSD " + std::to_string(drive_id) + " simulating latency: " + std::to_string(latency) + "us");
    std::this_thread::sleep_for(std::chrono::microseconds(latency));
}

void SSDModel::read(const std::string &page_id, std::string &data) {
    Logger::instance().log("SSD " + std::to_string(drive_id) + " initiating read for " + page_id);
    simulate_latency(read_latency_us);
    std::lock_guard<std::mutex> lock(storage_mutex);
    data = storage_[page_id];
    Logger::instance().log("SSD " + std::to_string(drive_id) + " completed read for " + page_id);
}

void SSDModel::write(const std::string &page_id, const std::string &data) {
    Logger::instance().log("SSD " + std::to_string(drive_id) + " initiating write for " + page_id);
    simulate_latency(write_latency_us);
    std::lock_guard<std::mutex> lock(storage_mutex);
    storage_[page_id] = data;
    Logger::instance().log("SSD " + std::to_string(drive_id) + " completed write for " + page_id);
}

void disk_worker(int drive_number) {
    SSDModel &ssd = *ssds[drive_number];
    DiskQueue<Operation> &queue = disk_queues[drive_number];

    Logger::instance().log("Disk worker " + std::to_string(drive_number) + " started.");

    while (true) {
        Operation op = queue.dequeue();

        Logger::instance().log("Disk worker " + std::to_string(drive_number) +
                               " processing " + (op.type == Operation::READ ? "read" : "write") +
                               " operation on page " + op.page_id);

        if (op.type == Operation::READ) {
            std::string data;
            ssd.read(op.page_id, data);
            // Handle data if necessary
        } else if (op.type == Operation::WRITE) {
            ssd.write(op.page_id, op.data);
        }

        // Log operation completion
        Logger::instance().log("Disk worker " + std::to_string(drive_number) +
                               " completed " + (op.type == Operation::READ ? "read" : "write") +
                               " operation on page " + op.page_id);
    }
}
'

    replace_file "$file_path" "$content"
}

# -----------------------------------------------------------------------------
# Function to Update myfs.cpp
# -----------------------------------------------------------------------------

update_myfs_cpp() {
    local file_path="$SRC_DIR/myfs.cpp"

    backup_file "$file_path"

    local content='// myfs.cpp

#define FUSE_USE_VERSION 31
#include <fuse3/fuse.h>
#include <cstring>
#include <cerrno>
#include <cstdio>
#include <string>
#include <unordered_map>
#include <mutex>
#include "config.h" // Include config.h

#include "murmurhash3.h"
#include "disk_queue.h"
#include "ssd_model.h"
#include "logger.h"

// External variables from main.cpp
extern std::vector<DiskQueue<Operation>> disk_queues;
extern std::vector<std::unique_ptr<SSDModel>> ssds;

// In-memory file system structure
std::unordered_map<std::string, std::string> file_contents;
std::mutex file_mutex;

// Function declarations for FUSE operations
static int myfs_getattr(const char *path, struct stat *stbuf, struct fuse_file_info *fi);
static int myfs_readdir(const char *path, void *buf, fuse_fill_dir_t filler,
                        off_t offset, struct fuse_file_info *fi,
                        enum fuse_readdir_flags flags);
static int myfs_open(const char *path, struct fuse_file_info *fi);
static int myfs_read(const char *path, char *buf, size_t size, off_t offset,
                     struct fuse_file_info *fi);
static int myfs_write(const char *path, const char *buf, size_t size, off_t offset,
                      struct fuse_file_info *fi);
static int myfs_create(const char *path, mode_t mode, struct fuse_file_info *fi);
static int myfs_unlink(const char *path);

// Implementations of FUSE operations

static int myfs_getattr(const char *path, struct stat *stbuf, struct fuse_file_info *fi) {
    (void) fi;
    memset(stbuf, 0, sizeof(struct stat));

    Logger::instance().log("getattr called for path: " + std::string(path));

    std::lock_guard<std::mutex> lock(file_mutex);

    if (strcmp(path, "/") == 0) {
        // Root directory
        stbuf->st_mode = S_IFDIR | 0755;
        stbuf->st_nlink = 2;
    } else if (file_contents.find(path) != file_contents.end()) {
        // Regular file
        stbuf->st_mode = S_IFREG | 0644;
        stbuf->st_nlink = 1;
        stbuf->st_size = file_contents[path].size();
    } else {
        Logger::instance().log("getattr: path not found: " + std::string(path));
        return -ENOENT;
    }
    Logger::instance().log("getattr: success for path: " + std::string(path));
    return 0;
}

static int myfs_readdir(const char *path, void *buf, fuse_fill_dir_t filler,
                        off_t offset, struct fuse_file_info *fi,
                        enum fuse_readdir_flags flags) {
    (void) offset;
    (void) fi;
    (void) flags;

    Logger::instance().log("readdir called for path: " + std::string(path));

    if (strcmp(path, "/") != 0) {
        Logger::instance().log("readdir: path not a directory: " + std::string(path));
        return -ENOENT;
    }

    filler(buf, ".", NULL, 0, static_cast<fuse_fill_dir_flags>(0));
    filler(buf, "..", NULL, 0, static_cast<fuse_fill_dir_flags>(0));

    std::lock_guard<std::mutex> lock(file_mutex);
    for (const auto &entry : file_contents) {
        std::string filename = entry.first.substr(1); // Remove leading '/'
        filler(buf, filename.c_str(), NULL, 0, static_cast<fuse_fill_dir_flags>(0));
    }

    Logger::instance().log("readdir: success for path: " + std::string(path));
    return 0;
}

static int myfs_open(const char *path, struct fuse_file_info *fi) {
    Logger::instance().log("open called for path: " + std::string(path));

    std::lock_guard<std::mutex> lock(file_mutex);

    if (file_contents.find(path) == file_contents.end()) {
        Logger::instance().log("open: path not found: " + std::string(path));
        return -ENOENT;
    }

    Logger::instance().log("open: success for path: " + std::string(path));
    return 0;
}

static int myfs_read(const char *path, char *buf, size_t size, off_t offset,
                     struct fuse_file_info *fi) {
    (void) fi;
    Logger::instance().log("read called for path: " + std::string(path) +
                           ", size: " + std::to_string(size) +
                           ", offset: " + std::to_string(offset));

    std::lock_guard<std::mutex> lock(file_mutex);

    if (file_contents.find(path) == file_contents.end()) {
        Logger::instance().log("read: path not found: " + std::string(path));
        return -ENOENT;
    }

    std::string &content = file_contents[path];
    size_t len = content.size();

    if (offset >= static_cast<off_t>(len)) {
        Logger::instance().log("read: offset beyond file size for path: " + std::string(path));
        return 0;
    }

    if (offset + size > len)
        size = len - offset;

    // Read data from SSDs
    size_t page_size = 4096; // 4KB pages
    size_t bytes_read = 0;
    while (size > 0) {
        size_t current_size = std::min(size, page_size - (offset % page_size));
        std::string page_id = std::string(path) + ":" + std::to_string(offset / page_size);

        uint32_t hash_value;
        MurmurHash3_x86_32(page_id.data(), page_id.size(), 0, &hash_value);
        int drive_number = hash_value % NUM_DRIVES;

        Logger::instance().log("read: accessing SSD " + std::to_string(drive_number) + " for page " + page_id);
        std::string page_data;
        ssds[drive_number]->read(page_id, page_data);

        size_t copy_size = std::min(current_size, page_data.size() - (offset % page_size));
        memcpy(buf + bytes_read, page_data.data() + (offset % page_size), copy_size);

        bytes_read += copy_size;
        size -= copy_size;
        offset += copy_size;
    }

    Logger::instance().log("read: completed " + std::to_string(bytes_read) + " bytes for path: " + std::string(path));
    return bytes_read;
}

static int myfs_write(const char *path, const char *buf, size_t size, off_t offset,
                      struct fuse_file_info *fi) {
    (void) fi;
    Logger::instance().log("write called for path: " + std::string(path) +
                           ", size: " + std::to_string(size) +
                           ", offset: " + std::to_string(offset));

    std::lock_guard<std::mutex> lock(file_mutex);

    std::string &content = file_contents[path];
    if (offset + size > content.size())
        content.resize(offset + size);

    // Write data to SSDs
    size_t page_size = 4096; // 4KB pages
    size_t bytes_written = 0;
    while (size > 0) {
        size_t current_size = std::min(size, page_size - (offset % page_size));
        std::string page_id = std::string(path) + ":" + std::to_string(offset / page_size);

        uint32_t hash_value;
        MurmurHash3_x86_32(page_id.data(), page_id.size(), 0, &hash_value);
        int drive_number = hash_value % NUM_DRIVES;

        Logger::instance().log("write: accessing SSD " + std::to_string(drive_number) + " for page " + page_id);
        // Prepare operation
        Operation op;
        op.type = Operation::WRITE;
        op.page_id = page_id;
        op.data.assign(buf + bytes_written, current_size);

        // Enqueue operation
        disk_queues[drive_number].enqueue(op);

        bytes_written += current_size;
        size -= current_size;
        offset += current_size;
    }

    Logger::instance().log("write: completed " + std::to_string(bytes_written) + " bytes for path: " + std::string(path));
    return bytes_written;
}

static int myfs_create(const char *path, mode_t mode, struct fuse_file_info *fi) {
    (void) fi;
    (void) mode;
    Logger::instance().log("create called for path: " + std::string(path));

    std::lock_guard<std::mutex> lock(file_mutex);

    if (file_contents.find(path) != file_contents.end()) {
        Logger::instance().log("create: path already exists: " + std::string(path));
        return -EEXIST;
    }

    file_contents[path] = "";

    Logger::instance().log("create: success for path: " + std::string(path));
    return 0;
}

static int myfs_unlink(const char *path) {
    Logger::instance().log("unlink called for path: " + std::string(path));

    std::lock_guard<std::mutex> lock(file_mutex);

    if (file_contents.erase(path) == 0) {
        Logger::instance().log("unlink: path not found: " + std::string(path));
        return -ENOENT;
    }

    Logger::instance().log("unlink: success for path: " + std::string(path));
    return 0;
}

// Initialize the fuse_operations struct
static struct fuse_operations myfs_oper = {};

int myfs_start(int argc, char *argv[]) {
    // Assign the struct fields individually
    memset(&myfs_oper, 0, sizeof(myfs_oper));
    myfs_oper.getattr = myfs_getattr;
    myfs_oper.readdir = myfs_readdir;
    myfs_oper.open    = myfs_open;
    myfs_oper.read    = myfs_read;
    myfs_oper.write   = myfs_write;
    myfs_oper.create  = myfs_create;
    myfs_oper.unlink  = myfs_unlink;
    // Add any additional operations as needed

    return fuse_main(argc, argv, &myfs_oper, NULL);
}
'

    replace_file "$file_path" "$content"
}

# -----------------------------------------------------------------------------
# Function to Update main.cpp
# -----------------------------------------------------------------------------

update_main_cpp() {
    local file_path="$SRC_DIR/main.cpp"

    backup_file "$file_path"

    local content='// main.cpp

#include "myfs.h"
#include "ssd_model.h"
#include "disk_queue.h"
#include "logger.h"
#include "config.h" // Include config.h

#include <vector>
#include <thread>
#include <memory>
#include <atomic>

// Global variables
std::vector<std::unique_ptr<SSDModel>> ssds;
std::vector<DiskQueue<Operation>> disk_queues(NUM_DRIVES);
std::vector<std::thread> disk_threads;

std::atomic<bool> shutdown_flag(false); // Global shutdown flag

// Function prototypes
void disk_worker(int drive_number);
void start_disk_workers();
void stop_disk_workers();

int main(int argc, char *argv[]) {
    // Initialize SSD models and start disk worker threads
    start_disk_workers();

    // Start FUSE filesystem
    int fuse_stat = myfs_start(argc, argv);

    // Signal shutdown to disk workers
    shutdown_flag.store(true);

    // Notify all DiskQueues to unblock any waiting threads
    for(auto &dq : disk_queues) {
        Operation op;
        op.type = Operation::WRITE; // Type doesn't matter
        op.page_id = "shutdown";
        op.data = "";
        dq.enqueue(op);
    }

    // Join disk worker threads
    stop_disk_workers();

    return fuse_stat;
}

void start_disk_workers() {
    for (int i = 0; i < NUM_DRIVES; ++i) {
        ssds.emplace_back(std::make_unique<SSDModel>(i));
        disk_threads.emplace_back(disk_worker, i);
        Logger::instance().log("Initialized SSD " + std::to_string(i));
    }
}

void stop_disk_workers() {
    for (auto &thread : disk_threads) {
        if (thread.joinable()) {
            thread.join();
            Logger::instance().log("Disk worker thread joined.");
        }
    }
}

void disk_worker(int drive_number) {
    SSDModel &ssd = *ssds[drive_number];
    DiskQueue<Operation> &queue = disk_queues[drive_number];

    Logger::instance().log("Disk worker " + std::to_string(drive_number) + " started.");

    while (true) {
        Operation op = queue.dequeue();

        if (shutdown_flag.load() && op.page_id == "shutdown") {
            Logger::instance().log("Disk worker " + std::to_string(drive_number) + " shutting down.");
            break;
        }

        Logger::instance().log("Disk worker " + std::to_string(drive_number) +
                               " processing " + (op.type == Operation::READ ? "read" : "write") +
                               " operation on page " + op.page_id);

        if (op.type == Operation::READ) {
            std::string data;
            ssd.read(op.page_id, data);
            // Handle data if necessary
        } else if (op.type == Operation::WRITE) {
            ssd.write(op.page_id, op.data);
        }

        // Log operation completion
        Logger::instance().log("Disk worker " + std::to_string(drive_number) +
                               " completed " + (op.type == Operation::READ ? "read" : "write") +
                               " operation on page " + op.page_id);
    }
}
'

    replace_file "$file_path" "$content"
}

# -----------------------------------------------------------------------------
# Function to Update config.h
# -----------------------------------------------------------------------------

update_config_h() {
    local file_path="$PROJECT_ROOT/config.h"

    backup_file "$file_path"

    local content='// config.h

#ifndef CONFIG_H
#define CONFIG_H

constexpr int NUM_DRIVES = 16; // Fixed number of SSDs

#endif // CONFIG_H
'

    replace_file "$file_path" "$content"
}

# -----------------------------------------------------------------------------
# Main Execution Flow
# -----------------------------------------------------------------------------

log_info "Starting project update script."

# Update logger.h
update_logger_h

# Update disk_queue.h
update_disk_queue_h

# Update ssd_model.cpp
update_ssd_model_cpp

# Update myfs.cpp
update_myfs_cpp

# Update main.cpp
update_main_cpp

# Update config.h
update_config_h

log_success "All files have been updated successfully."

exit 0