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
