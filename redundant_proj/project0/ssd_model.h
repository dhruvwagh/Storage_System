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
