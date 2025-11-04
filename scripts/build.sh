#!/bin/bash

# Solana Perpetuals Program Build Script with auto-installation
# This script builds the program for deployment and installs dependencies

set -e

echo "🏗️  Building Solana Perpetuals Program with Dependencies..."

# Check if Rust is installed
if ! command -v rustc &> /dev/null; then
    echo "📦 Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source ~/.cargo/env
    echo "✅ Rust installed successfully"
else
    echo "✅ Rust already installed"
fi

# Check if Solana CLI is installed
if ! command -v solana &> /dev/null; then
    echo "📦 Installing Solana CLI..."
    curl -sSfL https://release.solana.com/v1.18.0/install | sh
    export PATH="~/.local/share/solana/install/active_release/bin:$PATH"
    echo "✅ Solana CLI installed successfully"
else
    echo "✅ Solana CLI already installed"
fi

# Install required Rust components
echo "📦 Installing Rust components..."
rustup component add rust-src
rustup target add bpf-unknown-unknown || echo "⚠️  BPF target installation may have failed, continuing..."

# Initialize Solana toolchain
echo "📦 Initializing Solana toolchain..."
solana install init || echo "⚠️  Solana init may have failed, continuing..."

# Update Rust toolchain
echo "🔄 Updating Rust toolchain..."
rustup update stable

# Check if cargo-build-bpf is available
if ! command -v cargo-build-bpf &> /dev/null; then
    echo "📦 Installing Solana BPF toolchain..."
    cargo install --git https://github.com/solana-labs/solana solana-install-init --tag v1.18.0 || echo "⚠️  cargo-build-bpf installation may have failed, continuing..."
else
    echo "✅ cargo-build-bpf already available"
fi

# Create target directory if it doesn't exist
mkdir -p target/deploy

# Build the program
echo "🔨 Compiling program..."
echo "Attempting build with cargo-build-bpf..."
cargo build-bpf --manifest-path Cargo.toml --bpf-out-dir target/deploy

if [ $? -ne 0 ]; then
    echo "⚠️  cargo-build-bpf failed, trying alternative build method..."
    echo "🔨 Attempting build with cargo build-sbf..."
    cargo build-sbf --manifest-path Cargo.toml --sbf-out-dir target/deploy
    
    if [ $? -ne 0 ]; then
        echo "⚠️  cargo build-sbf failed, trying standard Solana build..."
        echo "🔨 Attempting standard cargo build..."
        cargo build --release --target bpf-unknown-unknown
        
        if [ $? -ne 0 ]; then
            echo "❌ All build methods failed!"
            echo "💡 Try running these commands manually:"
            echo "   1. rustup update stable"
            echo "   2. rustup component add rust-src"
            echo "   3. rustup target add bpf-unknown-unknown"
            echo "   4. solana install init"
            echo "   5. cargo build-bpf"
            exit 1
        fi
    fi
fi

# Check for successful build output
if [ -f "target/deploy/simple_perps.so" ]; then
    echo "✅ Build successful!"
    echo "📄 Program binary: target/deploy/simple_perps.so"
    SIZE=$(stat -f%z target/deploy/simple_perps.so 2>/dev/null || stat -c%s target/deploy/simple_perps.so 2>/dev/null || echo "unknown")
    echo "📊 Binary size: ${SIZE} bytes"
elif [ -f "target/bpf-unknown-unknown/release/simple_perps.so" ]; then
    echo "✅ Build successful!"
    echo "📄 Program binary: target/bpf-unknown-unknown/release/simple_perps.so"
    mkdir -p target/deploy
    cp target/bpf-unknown-unknown/release/simple_perps.so target/deploy/simple_perps.so
    SIZE=$(stat -f%z target/deploy/simple_perps.so 2>/dev/null || stat -c%s target/deploy/simple_perps.so 2>/dev/null || echo "unknown")
    echo "📊 Binary size: ${SIZE} bytes"
else
    echo "❌ Build completed but binary not found!"
    echo "🔍 Searching for compiled binaries..."
    find . -name "*.so" -type f
    exit 1
fi

echo ""
echo "🚀 Ready to deploy! Run ./scripts/deploy.sh to deploy to Solana."