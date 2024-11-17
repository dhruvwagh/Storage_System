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
Logger::instance().log("myfs_unlink called for path: " + std::string(path) + ".");
Logger::instance().log("myfs_create called for path: " + std::string(path) + ".");
Logger::instance().log("myfs_write called for path: " + std::string(path) + ".");
Logger::instance().log("myfs_read called for path: " + std::string(path) + ".");
Logger::instance().log("myfs_open called for path: " + std::string(path) + ".");
Logger::instance().log("myfs_readdir called for path: " + std::string(path) + ".");
Logger::instance().log("myfs_getattr called for path: " + std::string(path) + ".");
    (void) fi;
    memset(stbuf, 0, sizeof(struct stat));

    std::lock_guard<std::mutex> lock(file_mutex);

    if (strcmp(path, "/") == 0) {
Logger::instance().log("myfs_unlink called for path: " + std::string(path) + ".");
Logger::instance().log("myfs_create called for path: " + std::string(path) + ".");
Logger::instance().log("myfs_write called for path: " + std::string(path) + ".");
Logger::instance().log("myfs_read called for path: " + std::string(path) + ".");
Logger::instance().log("myfs_open called for path: " + std::string(path) + ".");
Logger::instance().log("myfs_readdir called for path: " + std::string(path) + ".");
Logger::instance().log("myfs_getattr called for path: " + std::string(path) + ".");
        // Root directory
        stbuf->st_mode = S_IFDIR | 0755;
        stbuf->st_nlink = 2;
    } else if (file_contents.find(path) != file_contents.end()) {
Logger::instance().log("myfs_unlink called for path: " + std::string(path) + ".");
Logger::instance().log("myfs_create called for path: " + std::string(path) + ".");
Logger::instance().log("myfs_write called for path: " + std::string(path) + ".");
Logger::instance().log("myfs_read called for path: " + std::string(path) + ".");
Logger::instance().log("myfs_open called for path: " + std::string(path) + ".");
Logger::instance().log("myfs_readdir called for path: " + std::string(path) + ".");
Logger::instance().log("myfs_getattr called for path: " + std::string(path) + ".");
        // Regular file
        stbuf->st_mode = S_IFREG | 0644;
        stbuf->st_nlink = 1;
        stbuf->st_size = file_contents[path].size();
    } else {
Logger::instance().log("myfs_unlink called for path: " + std::string(path) + ".");
Logger::instance().log("myfs_create called for path: " + std::string(path) + ".");
Logger::instance().log("myfs_write called for path: " + std::string(path) + ".");
Logger::instance().log("myfs_read called for path: " + std::string(path) + ".");
Logger::instance().log("myfs_open called for path: " + std::string(path) + ".");
Logger::instance().log("myfs_readdir called for path: " + std::string(path) + ".");
Logger::instance().log("myfs_getattr called for path: " + std::string(path) + ".");
        return -ENOENT;
    }
    return 0;
}

static int myfs_readdir(const char *path, void *buf, fuse_fill_dir_t filler,
                        off_t offset, struct fuse_file_info *fi,
                        enum fuse_readdir_flags flags) {
Logger::instance().log("myfs_read called for path: " + std::string(path) + ".");
Logger::instance().log("myfs_readdir called for path: " + std::string(path) + ".");
    (void) offset;
    (void) fi;
    (void) flags;

    if (strcmp(path, "/") != 0)
        return -ENOENT;

    filler(buf, ".", NULL, 0, static_cast<fuse_fill_dir_flags>(0));
    filler(buf, "..", NULL, 0, static_cast<fuse_fill_dir_flags>(0));

    std::lock_guard<std::mutex> lock(file_mutex);
    for (const auto &entry : file_contents) {
Logger::instance().log("myfs_read called for path: " + std::string(path) + ".");
Logger::instance().log("myfs_readdir called for path: " + std::string(path) + ".");
        std::string filename = entry.first.substr(1); // Remove leading '/'
        filler(buf, filename.c_str(), NULL, 0, static_cast<fuse_fill_dir_flags>(0));
    }

    return 0;
}

static int myfs_open(const char *path, struct fuse_file_info *fi) {
Logger::instance().log("myfs_open called for path: " + std::string(path) + ".");
    (void) fi;
    std::lock_guard<std::mutex> lock(file_mutex);

    if (file_contents.find(path) == file_contents.end())
        return -ENOENT;

    return 0;
}

static int myfs_read(const char *path, char *buf, size_t size, off_t offset,
                     struct fuse_file_info *fi) {
Logger::instance().log("myfs_read called for path: " + std::string(path) + ".");
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
Logger::instance().log("myfs_read called for path: " + std::string(path) + ".");
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
Logger::instance().log("myfs_write called for path: " + std::string(path) + ".");
    (void) fi;
    std::lock_guard<std::mutex> lock(file_mutex);

    std::string &content = file_contents[path];
    if (offset + size > content.size())
        content.resize(offset + size);

    // Write data to SSDs
    size_t page_size = 4096; // 4KB pages
    size_t bytes_written = 0;
    while (size > 0) {
Logger::instance().log("myfs_write called for path: " + std::string(path) + ".");
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
Logger::instance().log("myfs_create called for path: " + std::string(path) + ".");
    (void) fi;
    (void) mode;
    std::lock_guard<std::mutex> lock(file_mutex);

    if (file_contents.find(path) != file_contents.end())
        return -EEXIST;

    file_contents[path] = "";

    return 0;
}

static int myfs_unlink(const char *path) {
Logger::instance().log("myfs_unlink called for path: " + std::string(path) + ".");
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
