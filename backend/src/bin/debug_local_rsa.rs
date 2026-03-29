use base64::{engine::general_purpose, Engine as _};
use russh_keys::*;
use std::fs;
use std::process::Command;

fn main() {
    // 1. Generate RSA Key
    let _ = fs::remove_file("test_rsa");
    let _ = fs::remove_file("test_rsa.pub");

    let status = Command::new("ssh-keygen")
        .args(&["-t", "rsa", "-b", "2048", "-f", "test_rsa", "-N", ""])
        .output()
        .expect("Failed to run ssh-keygen");

    if !status.status.success() {
        println!("ssh-keygen failed");
        return;
    }

    // 2. Read Public Key
    let pub_content = fs::read_to_string("test_rsa.pub").expect("Failed to read pub key");
    let parts: Vec<&str> = pub_content.split_whitespace().collect();
    let key_base64 = parts[1];

    // 3. Decode and Parse
    match general_purpose::STANDARD.decode(key_base64) {
        Ok(bytes) => {
            println!("Decoded {} bytes", bytes.len());
            if bytes.len() > 4 {
                let len = u32::from_be_bytes(bytes[0..4].try_into().unwrap()) as usize;
                if bytes.len() >= 4 + len {
                    let algo = &bytes[4..4 + len];
                    let rest = &bytes[4 + len..];
                    println!("Algo: {:?}", String::from_utf8_lossy(algo));

                    match russh_keys::key::PublicKey::parse(algo, &bytes) {
                        Ok(pk) => println!("✅ Local Key Parsed Successfully: {:?}", pk.name()),
                        Err(e) => println!("❌ Local Key Parse Failed: {:?}", e),
                    }
                }
            }
        }
        Err(e) => println!("Base64 fail: {}", e),
    }

    let _ = fs::remove_file("test_rsa");
    let _ = fs::remove_file("test_rsa.pub");
}
