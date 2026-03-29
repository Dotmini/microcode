fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Compile the Objective-C++ bridge for Micro-VM
    if std::path::Path::new("src/vm/bridge.mm").exists() {
        cc::Build::new()
            .file("src/vm/bridge.mm")
            .flag("-fobjc-arc") // Enable ARC
            .flag("-std=c++17")
            .compile("vm_bridge");

        // Link Virtualization framework
        println!("cargo:rustc-link-lib=framework=Virtualization");
        println!("cargo:rustc-link-lib=framework=Foundation");

        // Rerun if bridge changes
        println!("cargo:rerun-if-changed=src/vm/bridge.mm");
        println!("cargo:rerun-if-changed=src/vm/bridge.h");
    }

    // Only compile protos if the file exists (avoid breaking build if missing)
    if std::path::Path::new("proto/preview_protocol.proto").exists() {
        // Note: tonic_build requires 'protoc' to be installed.
        // If it's missing, this might fail at build time.
        // We wrap it to allow other parts of the backend to build even if gRPC gen fails.
        // real implementation would handle this more gracefully or assume env is correct.
        let _ = tonic_build::compile_protos("proto/preview_protocol.proto");
    }
    Ok(())
}
