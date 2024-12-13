#!/bin/bash

VERSION="0.7.1"
AMD64_URL="https://github.com/madeofpendletonwool/PinePods/releases/download/${VERSION}/Pinepods_${VERSION}_amd64.deb"
ARM64_URL="https://github.com/madeofpendletonwool/PinePods/releases/download/${VERSION}/Pinepods_${VERSION}_arm64.deb"

echo "Downloading AMD64 deb..."
curl -LO "$AMD64_URL"
echo "Downloading ARM64 deb..."
curl -LO "$ARM64_URL"

echo -e "\nSHA256 sums:"
echo "AMD64: $(sha256sum Pinepods_${VERSION}_amd64.deb | cut -d' ' -f1)"
echo "ARM64: $(sha256sum Pinepods_${VERSION}_arm64.deb | cut -d' ' -f1)"

# Clean up
rm Pinepods_${VERSION}_*.deb
