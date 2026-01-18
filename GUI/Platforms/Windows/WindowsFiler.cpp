#include "../../Common/AuthenticFiler.h"
#include <iostream>

namespace Authentic {

class WindowsFiler : public AuthenticFiler {
public:
    std::vector<FileNode> listDirectory(const std::string& path) override {
        // STUB: Real implementation would use FindFirstFile/FindNextFile
        std::cout << "[Windows] Listing directory: " << path << std::endl;
        return {}; 
    }

    bool exists(const std::string& path) override {
        // STUB: Real implementation would use GetFileAttributes
        return false;
    }

    bool createDirectory(const std::string& path) override {
        // STUB: Real implementation would use CreateDirectory
        std::cout << "[Windows] Creating directory: " << path << std::endl;
        return true;
    }
};

} // namespace Authentic
