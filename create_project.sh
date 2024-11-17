#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Variables
PROJECT_DIR="project"

# Remove existing project directory if it exists
if [ -d "$PROJECT_DIR" ]; then
    echo "Removing existing project directory..."
    rm -rf "$PROJECT_DIR"
fi

# Create the project directory
echo "Creating project directory..."
mkdir -p "$PROJECT_DIR"

# Navigate to the project directory
cd "$PROJECT_DIR"

# Create and populate each file
echo "Creating and populating files..."

# config.h
cat << 'EOF' > config.h
// config.h

#ifndef CONFIG_H
#define CONFIG_H

constexpr int NUM_DRIVES = 16;

#endif // CONFIG_H
EOF

# CMakeLists.txt
cat << 'EOF' > CMakeLists.txt
# CMakeLists.txt

cmake_minimum_required(VERSION 3.10)
project(MultiDriveStorageSystem)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_FLAGS "-Wall -pthread")

find_package(PkgConfig REQUIRED)
pkg_check_modules(FUSE3 REQUIRED fuse3)

include_directories(\${FUSE3_INCLUDE_DIRS})

add_executable(myfs main.cpp myfs.cpp murmurhash3.cpp ssd_model.cpp)
target_link_libraries(myfs \${FUSE3_LIBRARIES})
EOF

# main.cpp
cat << 'EOF' > main.cpp
// main.cpp

#include "myfs.h"
#include "ssd_model.h"
#include "disk_queue.h"
#include "logger.h"
#include "config.h" // Include config.h

#include <vector>
#include <thread>
#include <memory>

std::vector<std::unique_ptr<SSDModel>> ssds;
std::vector<DiskQueue<Operation>> disk_queues(NUM_DRIVES);
std::vector<std::thread> disk_threads;

// Function prototypes
void disk_worker(int drive_number);
void start_disk_workers();
void stop_disk_workers();

int main(int argc, char *argv[]) {
    // Initialize SSD models and start disk worker threads
    start_disk_workers();

    // Start FUSE filesystem
    int fuse_stat = myfs_start(argc, argv);

    // Stop disk worker threads
    stop_disk_workers();

    return fuse_stat;
}

void start_disk_workers() {
    for (int i = 0; i < NUM_DRIVES; ++i) {
        ssds.emplace_back(std::make_unique<SSDModel>(i));
        disk_threads.emplace_back(disk_worker, i);
    }
}

void stop_disk_workers() {
    // Implement a way to stop disk workers gracefully if needed
    for (auto &thread : disk_threads) {
        thread.detach(); // Or join if you have a termination mechanism
    }
}
EOF

# myfs.h
cat << 'EOF' > myfs.h
// myfs.h

#ifndef MYFS_H
#define MYFS_H

int myfs_start(int argc, char *argv[]);

#endif // MYFS_H
EOF

# myfs.cpp
cat << 'EOF' > myfs.cpp
// myfs.cpp

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
        return -ENOENT;
    }
    return 0;
}

static int myfs_readdir(const char *path, void *buf, fuse_fill_dir_t filler,
                        off_t offset, struct fuse_file_info *fi,
                        enum fuse_readdir_flags flags) {
    (void) offset;
    (void) fi;
    (void) flags;

    if (strcmp(path, "/") != 0)
        return -ENOENT;

    filler(buf, ".", NULL, 0, static_cast<fuse_fill_dir_flags>(0));
    filler(buf, "..", NULL, 0, static_cast<fuse_fill_dir_flags>(0));

    std::lock_guard<std::mutex> lock(file_mutex);
    for (const auto &entry : file_contents) {
        std::string filename = entry.first.substr(1); // Remove leading '/'
        filler(buf, filename.c_str(), NULL, 0, static_cast<fuse_fill_dir_flags>(0));
    }

    return 0;
}

static int myfs_open(const char *path, struct fuse_file_info *fi) {
    (void) fi;
    std::lock_guard<std::mutex> lock(file_mutex);

    if (file_contents.find(path) == file_contents.end())
        return -ENOENT;

    return 0;
}

static int myfs_read(const char *path, char *buf, size_t size, off_t offset,
                     struct fuse_file_info *fi) {
    (void) fi;
    std::lock_guard<std::mutex> lock(file_mutex);

    if (file_contents.find(path) == file_contents.end())
        return -ENOENT;

    std::string &content = file_contents[path];
    size_t len = content.size();

    if (offset >= (off_t)len)
        return 0;

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

        std::string page_data;
        ssds[drive_number]->read(page_id, page_data);

        size_t copy_size = std::min(current_size, page_data.size() - (offset % page_size));
        memcpy(buf + bytes_read, page_data.data() + (offset % page_size), copy_size);

        bytes_read += copy_size;
        size -= copy_size;
        offset += copy_size;
    }

    return bytes_read;
}

static int myfs_write(const char *path, const char *buf, size_t size, off_t offset,
                      struct fuse_file_info *fi) {
    (void) fi;
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

    return bytes_written;
}

static int myfs_create(const char *path, mode_t mode, struct fuse_file_info *fi) {
    (void) fi;
    (void) mode;
    std::lock_guard<std::mutex> lock(file_mutex);

    if (file_contents.find(path) != file_contents.end())
        return -EEXIST;

    file_contents[path] = "";

    return 0;
}

static int myfs_unlink(const char *path) {
    std::lock_guard<std::mutex> lock(file_mutex);

    if (file_contents.erase(path) == 0)
        return -ENOENT;

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
EOF

# murmurhash3.h
cat << 'EOF' > murmurhash3.h
// murmurhash3.h

#ifndef MURMURHASH3_H
#define MURMURHASH3_H

#include <cstdint>

void MurmurHash3_x86_32(const void *key, int len, uint32_t seed, void *out);

#endif // MURMURHASH3_H
EOF

# murmurhash3.cpp
cat << 'EOF' > murmurhash3.cpp
// murmurhash3.cpp

#include "murmurhash3.h"

void MurmurHash3_x86_32(const void *key, int len, uint32_t seed, void *out) {
    const uint8_t *data = (const uint8_t*)key;
    const int nblocks = len / 4;

    uint32_t h1 = seed;

    const uint32_t c1 = 0xcc9e2d51;
    const uint32_t c2 = 0x1b873593;

    // Body
    const uint32_t *blocks = (const uint32_t *)(data + nblocks * 4);
    for (int i = -nblocks; i; i++) {
        uint32_t k1 = blocks[i];

        k1 *= c1;
        k1 = (k1 << 15) | (k1 >> (32 - 15));
        k1 *= c2;

        h1 ^= k1;
        h1 = (h1 << 13) | (h1 >> (32 - 13));
        h1 = h1 * 5 + 0xe6546b64;
    }

    // Tail
    const uint8_t *tail = (const uint8_t*)(data + nblocks * 4);
    uint32_t k1 = 0;

    switch (len & 3) {
        case 3:
            k1 ^= tail[2] << 16;
            [[fallthrough]];
        case 2:
            k1 ^= tail[1] << 8;
            [[fallthrough]];
        case 1:
            k1 ^= tail[0];
            k1 *= c1;
            k1 = (k1 << 15) | (k1 >> (32 - 15));
            k1 *= c2;
            h1 ^= k1;
    }

    // Finalization
    h1 ^= len;

    // FMix (Final mix)
    h1 ^= h1 >> 16;
    h1 *= 0x85ebca6b;
    h1 ^= h1 >> 13;
    h1 *= 0xc2b2ae35;
    h1 ^= h1 >> 16;

    *(uint32_t*)out = h1;
}
EOF

# ssd_model.h
cat << 'EOF' > ssd_model.h
// ssd_model.h

#ifndef SSD_MODEL_H
#define SSD_MODEL_H

#include <string>
#include <unordered_map>
#include <mutex>
#include <random>

class SSDModel {
public:
    SSDModel(int id);
    void read(const std::string &page_id, std::string &data);
    void write(const std::string &page_id, const std::string &data);

private:
    int drive_id;
    int read_latency_us;
    int write_latency_us;
    std::unordered_map<std::string, std::string> storage_;
    std::mutex storage_mutex;

    void simulate_latency(int avg_latency_us);
};

struct Operation {
    enum Type { READ, WRITE } type;
    std::string page_id;
    std::string data; // For write operations
};

void disk_worker(int drive_number);

#endif // SSD_MODEL_H
EOF

# ssd_model.cpp
cat << 'EOF' > ssd_model.cpp
// ssd_model.cpp

#include "ssd_model.h"
#include "disk_queue.h"
#include "logger.h"

#include <chrono>
#include <thread>
#include <algorithm>
#include <memory>

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
    std::this_thread::sleep_for(std::chrono::microseconds(latency));
}

void SSDModel::read(const std::string &page_id, std::string &data) {
    simulate_latency(read_latency_us);
    std::lock_guard<std::mutex> lock(storage_mutex);
    data = storage_[page_id];
}

void SSDModel::write(const std::string &page_id, const std::string &data) {
    simulate_latency(write_latency_us);
    std::lock_guard<std::mutex> lock(storage_mutex);
    storage_[page_id] = data;
}

void disk_worker(int drive_number) {
    SSDModel &ssd = *ssds[drive_number];
    DiskQueue<Operation> &queue = disk_queues[drive_number];

    while (true) {
        Operation op = queue.dequeue();

        if (op.type == Operation::READ) {
            std::string data;
            ssd.read(op.page_id, data);
            // Handle data if necessary
        } else if (op.type == Operation::WRITE) {
            ssd.write(op.page_id, op.data);
        }

        // Log operation
        Logger::instance().log("Drive " + std::to_string(drive_number) +
                               " completed " + (op.type == Operation::READ ? "read" : "write") +
                               " operation on page " + op.page_id);
    }
}
EOF

# disk_queue.h
cat << 'EOF' > disk_queue.h
// disk_queue.h

#ifndef DISK_QUEUE_H
#define DISK_QUEUE_H

#include <queue>
#include <mutex>
#include <condition_variable>
#include <cstddef>

template<typename T>
class DiskQueue {
public:
    void enqueue(const T &item) {
        std::unique_lock<std::mutex> lock(mutex_);
        if (queue_.size() >= MAX_QUEUE_SIZE) {
            // Apply backpressure: wait until there's space
            condition_full_.wait(lock, [this]() { return queue_.size() < MAX_QUEUE_SIZE; });
        }
        queue_.push(item);
        condition_.notify_one();
    }

    T dequeue() {
        std::unique_lock<std::mutex> lock(mutex_);
        while (queue_.empty()) {
            condition_.wait(lock);
        }
        T item = queue_.front();
        queue_.pop();
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
EOF

# logger.h
cat << 'EOF' > logger.h
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
EOF

# test_program.cpp
cat << 'EOF' > test_program.cpp
// test_program.cpp

#include <fstream>
#include <iostream>
#include <thread>

void write_test(const std::string &filename) {
    std::ofstream ofs(filename);
    if (!ofs) {
        std::cerr << "Error opening file for writing.\n";
        return;
    }
    for (int i = 0; i < 1000; ++i) {
        ofs << "This is line " << i << "\n";
    }
    ofs.close();
}

void read_test(const std::string &filename) {
    std::ifstream ifs(filename);
    if (!ifs) {
        std::cerr << "Error opening file for reading.\n";
        return;
    }
    std::string line;
    while (std::getline(ifs, line)) {
        // Process line if needed
    }
    ifs.close();
}

int main() {
    std::string filename = "/tmp/myfs_mount/testfile.txt";

    // Start write test in a separate thread
    std::thread writer(write_test, filename);

    // Start read test
    read_test(filename);

    writer.join();

    return 0;
}
EOF

# Return to the original directory
cd ..

echo "Project files have been created and populated successfully."