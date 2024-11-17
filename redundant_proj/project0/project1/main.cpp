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
