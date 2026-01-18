#pragma once

#include <string>
#include <vector>

namespace Authentic {

// Generic File Node structure
struct FileNode {
    std::string name;
    std::string path;
    bool isDirectory;
    long long size;
};

// Abstract Interface for File System Operations
class AuthenticFiler {
public:
    virtual ~AuthenticFiler() = default;

    // List contents of a directory
    virtual std::vector<FileNode> listDirectory(const std::string& path) = 0;

    // Check if path exists
    virtual bool exists(const std::string& path) = 0;

    // Create a new directory
    virtual bool createDirectory(const std::string& path) = 0;
};

} // namespace Authentic
