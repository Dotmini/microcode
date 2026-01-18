#include "../../Common/AuthenticFiler.h"
#include <iostream>

namespace Authentic {

class LinuxFiler : public AuthenticFiler {
public:
    std::vector<FileNode> listDirectory(const std::string& path) override {
        // STUB: Real implementation would use <dirent.h> or std::filesystem
        std::cout << "[Linux] Listing directory: " << path << std::endl;
        return {}; 
    }

    bool exists(const std::string& path) override {
        // STUB: Real implementation would use stat()
        return false;
    }

    bool createDirectory(const std::string& path) override {
        // STUB: Real implementation would use mkdir()
        std::cout << "[Linux] Creating directory: " << path << std::endl;
        return true;
    }
};

} // namespace Authentic
