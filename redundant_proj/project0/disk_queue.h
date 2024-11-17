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
