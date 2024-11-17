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
