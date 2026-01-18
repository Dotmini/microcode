#pragma once

#include <string>

namespace Authentic {

// Abstract Interface for Document Lifecycle
class AuthenticDocument {
public:
    virtual ~AuthenticDocument() = default;

    // Open a document from path
    virtual bool open(const std::string& path) = 0;

    // Save current content to disk
    virtual bool save() = 0;

    // Close and release resources
    virtual void close() = 0;

    // Get current text content
    virtual std::string getContent() const = 0;

    // Check if document has unsaved changes
    virtual bool isDirty() const = 0;
};

} // namespace Authentic
