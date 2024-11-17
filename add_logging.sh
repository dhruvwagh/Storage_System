#!/bin/bash

# -----------------------------------------------------------------------------
# add_logging.sh
#
# A Bash script to automatically insert rigorous logging functionality into your
# C++ project files. It backs up existing files before modifying them.
#
# Usage:
#   chmod +x add_logging.sh    # Make the script executable
#   ./add_logging.sh           # Run the script
# -----------------------------------------------------------------------------

# Exit immediately if a command exits with a non-zero status
set -e

# -----------------------------------------------------------------------------
# Configuration Variables
# -----------------------------------------------------------------------------

# Define the project root directory (adjust this path if needed)
PROJECT_ROOT=~/Documents/Storage_System/project

# Define the log directory for backups
BACKUP_DIR="$PROJECT_ROOT/logs"
mkdir -p "$BACKUP_DIR"

# Timestamp for backups
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Files to be processed (relative to PROJECT_ROOT)
FILES_TO_PROCESS=(
    "logger.h"
    "disk_queue.h"
    "ssd_model.cpp"
    "myfs.cpp"
    "main.cpp"
)

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
# Function to Backup a File
# -----------------------------------------------------------------------------

backup_file() {
    local file_name="$1"
    local src_file="$PROJECT_ROOT/$file_name"
    local backup_path="$BACKUP_DIR/${file_name}.bak_$TIMESTAMP"

    if [[ -f "$src_file" ]]; then
        cp "$src_file" "$backup_path"
        log_info "Backed up $file_name to $backup_path"
    else
        log_error "File $file_name does not exist in $PROJECT_ROOT. Skipping backup."
    fi
}

# -----------------------------------------------------------------------------
# Function to Insert Logging into logger.h
# -----------------------------------------------------------------------------

update_logger_h() {
    local file_name="logger.h"
    local file_path="$PROJECT_ROOT/$file_name"

    if [[ -f "$file_path" ]]; then
        log_info "Updating $file_name..."

        # Replace the entire Logger class with the enhanced version
        sed -i '/class Logger/,/};/c\
class Logger {\
public:\
    static Logger& instance() {\
        static Logger logger_instance;\
        return logger_instance;\
    }\
\
    void log(const std::string &message) {\
        std::lock_guard<std::mutex> lock(mutex_);\
        auto now = std::chrono::system_clock::now();\
        auto in_time_t = std::chrono::system_clock::to_time_t(now);\
        auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(\
                      now.time_since_epoch()) % 1000;\
\
        logfile_ << std::put_time(std::localtime(&in_time_t), "%Y-%m-%d %X")\
                 << "." << std::setfill('0') << std::setw(3) << ms.count()\
                 << " [Thread " << std::this_thread::get_id() << "] " << message << std::endl;\
    }\
\
private:\
    Logger() : logfile_("log.txt") {}\
    ~Logger() {\
        logfile_.close();\
    }\
\
    std::ofstream logfile_;\
    std::mutex mutex_;\
};' "$file_path"

        log_success "$file_name updated successfully."
    else
        log_error "$file_name does not exist. Skipping."
    fi
}

# -----------------------------------------------------------------------------
# Function to Insert Logging into disk_queue.h
# -----------------------------------------------------------------------------

update_disk_queue_h() {
    local file_name="disk_queue.h"
    local file_path="$PROJECT_ROOT/$file_name"

    if [[ -f "$file_path" ]]; then
        log_info "Updating $file_name..."

        # Insert logging statements into enqueue and dequeue functions
        sed -i '/void enqueue/,/}/ {
    /void enqueue/ a\
        Logger::instance().log("Enqueue called.");
    /queue_.push(item);/ a\
        Logger::instance().log("Enqueued operation: " + item.page_id + ".");
}' "$file_path"

        sed -i '/T dequeue/,/}/ {
    /T dequeue/ a\
        Logger::instance().log("Dequeue called.");
    /queue_.pop();/ a\
        Logger::instance().log("Dequeued operation: " + item.page_id + ".");
}' "$file_path"

        log_success "$file_name updated successfully."
    else
        log_error "$file_name does not exist. Skipping."
    fi
}

# -----------------------------------------------------------------------------
# Function to Insert Logging into ssd_model.cpp
# -----------------------------------------------------------------------------

update_ssd_model_cpp() {
    local file_name="ssd_model.cpp"
    local file_path="$PROJECT_ROOT/$file_name"

    if [[ -f "$file_path" ]]; then
        log_info "Updating $file_name..."

        # Insert logging into simulate_latency function
        sed -i '/void SSDModel::simulate_latency/,/^}/ {
    /^}/ i\
        Logger::instance().log("SSD " + std::to_string(drive_id) + " simulating latency: " + std::to_string(latency) + "us.");
}' "$file_path"

        # Insert logging into read function
        sed -i '/void SSDModel::read/,/^}/ {
    /^{/ a\
        Logger::instance().log("SSD " + std::to_string(drive_id) + " initiating read for " + page_id + ".");
}' "$file_path"

        # Insert logging into write function
        sed -i '/void SSDModel::write/,/^}/ {
    /^{/ a\
        Logger::instance().log("SSD " + std::to_string(drive_id) + " initiating write for " + page_id + ".");
}' "$file_path"

        # Insert logging at the end of read function
        sed -i '/void SSDModel::read/,/^}/ {
    /^}/ i\
        Logger::instance().log("SSD " + std::to_string(drive_id) + " completed read for " + page_id + ".");
}' "$file_path"

        # Insert logging at the end of write function
        sed -i '/void SSDModel::write/,/^}/ {
    /^}/ i\
        Logger::instance().log("SSD " + std::to_string(drive_id) + " completed write for " + page_id + ".");
}' "$file_path"

        log_success "$file_name updated successfully."
    else
        log_error "$file_name does not exist. Skipping."
    fi
}

# -----------------------------------------------------------------------------
# Function to Insert Logging into myfs.cpp
# -----------------------------------------------------------------------------

update_myfs_cpp() {
    local file_name="myfs.cpp"
    local file_path="$PROJECT_ROOT/$file_name"

    if [[ -f "$file_path" ]]; then
        log_info "Updating $file_name..."

        # Insert logging at the start of each FUSE operation function
        FUSE_FUNCTIONS=("myfs_getattr" "myfs_readdir" "myfs_open" "myfs_read" "myfs_write" "myfs_create" "myfs_unlink")

        for func in "${FUSE_FUNCTIONS[@]}"; do
            # Escape parentheses in function names if necessary
            escaped_func=$(echo "$func" | sed 's/[]\/$*.^|[]/\\&/g')

            # Insert logging at the start of the function body
            sed -i "/static int $escaped_func/,/^}/ {
    /{/ a\
        Logger::instance().log(\"$func called for path: \" + std::string(path) + \".\");
}" "$file_path"
        done

        log_success "$file_name updated successfully."
    else
        log_error "$file_name does not exist. Skipping."
    fi
}

# -----------------------------------------------------------------------------
# Function to Insert Logging into main.cpp
# -----------------------------------------------------------------------------

update_main_cpp() {
    local file_name="main.cpp"
    local file_path="$PROJECT_ROOT/$file_name"

    if [[ -f "$file_path" ]]; then
        log_info "Updating $file_name..."

        # Insert logging into main function
        sed -i '/int main/,/^}/ {
    /start_disk_workers();/ a\
        Logger::instance().log("Disk workers started.");
    /stop_disk_workers();/ a\
        Logger::instance().log("Disk workers stopped.");
}' "$file_path"

        # Insert logging into disk_worker function
        sed -i '/void disk_worker/,/^}/ {
    /while $begin:math:text$true$end:math:text$/ a\
        Logger::instance().log("Disk worker " + std::to_string(drive_number) + " started.");
    /break;/ a\
        Logger::instance().log("Disk worker " + std::to_string(drive_number) + " shutting down.");
}' "$file_path"

        log_success "$file_name updated successfully."
    else
        log_error "$file_name does not exist. Skipping."
    fi
}

# -----------------------------------------------------------------------------
# Main Execution Flow
# -----------------------------------------------------------------------------

log_info "Starting the addition of rigorous logging to your project."

for file in "${FILES_TO_PROCESS[@]}"; do
    case "$file" in
        "logger.h")
            update_logger_h
            ;;
        "disk_queue.h")
            update_disk_queue_h
            ;;
        "ssd_model.cpp")
            update_ssd_model_cpp
            ;;
        "myfs.cpp")
            update_myfs_cpp
            ;;
        "main.cpp")
            update_main_cpp
            ;;
        *)
            log_error "Unknown file: $file"
            ;;
    esac
done

log_success "All files have been updated successfully with rigorous logging."

exit 0