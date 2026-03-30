#!/bin/bash
# Generate Xcode project using swift package
cd "$(dirname "$0")"

# Create a proper Swift Package for macOS app
cat > Package.swift << 'EOF'
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LelokOS",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "LelokOS",
            path: "LelokOS/Shared"
        )
    ]
)
EOF

echo "Package.swift created. Building..."
swift build 2>&1
