#!/bin/bash

# ==============================================================================
# AUTOMATED ROM PORTING SCRIPT (Beryllium -> Crosshatch)
# For GitHub Codespaces (Ubuntu)
# ==============================================================================

# --- VARIABLES (YOU MUST REPLACE THESE LINKS) ---
# Link to a WORKING Pixel 3 XL ROM (Base) - preferably LineageOS or Stock
BASE_ROM_URL="https://mirrorbits.lineageos.org/full/crosshatch/20240101/lineage-21.0-20240101-nightly-crosshatch-signed.zip" 
# Link to the PixelOS POCO F1 ROM (Port) you want
PORT_ROM_URL="https://pixelos.net/download/beryllium/download_link_here.zip"

# --- SETUP ENVIRONMENT ---
echo "[*] Installing dependencies..."
sudo apt-get update -y
sudo apt-get install -y git python3 python3-pip android-sdk-lib-sparse-utils wget unzip zip tar sudo brotli p7zip-full

# Tools for unpacking
mkdir -p tools
cd tools
wget https://github.com/ssut/payload-dumper-go/releases/download/1.2.2/payload-dumper-go_1.2.2_linux_amd64.tar.gz
tar -xvf payload-dumper-go_1.2.2_linux_amd64.tar.gz
chmod +x payload-dumper-go
cd ..

# Create Workspaces
mkdir -p build/base
mkdir -p build/port
mkdir -p build/output

# --- DOWNLOAD ROMS ---
echo "[*] Downloading ROMs..."
wget -O base_rom.zip "$BASE_ROM_URL"
wget -O port_rom.zip "$PORT_ROM_URL"

# --- UNPACK BASE ROM (Crosshatch) ---
echo "[*] Extracting Base ROM (Pixel 3 XL)..."
unzip base_rom.zip -d build/base_extracted
# Check for payload.bin (Standard for Pixel/Lineage)
if [ -f "build/base_extracted/payload.bin" ]; then
    ./tools/payload-dumper-go -o build/base_images build/base_extracted/payload.bin
    mv build/base_images/system.img build/base_system.img
else
    echo "[!] Error: Base ROM must have payload.bin for this script."
    exit 1
fi

# --- UNPACK PORT ROM (Beryllium) ---
echo "[*] Extracting Port ROM (POCO F1)..."
unzip port_rom.zip -d build/port_extracted
# Check for Brotli/Dat format (Standard for POCO F1)
if [ -f "build/port_extracted/system.new.dat.br" ]; then
    echo "[*] Decompressing Brotli..."
    brotli -d build/port_extracted/system.new.dat.br -o build/port_extracted/system.new.dat
    echo "[*] Converting DAT to IMG..."
    # python sdat2img logic usually needed here, assuming sdat2img is available or using simple conversion
    # For this script, we'll download a helper
    wget https://raw.githubusercontent.com/xpirt/sdat2img/master/sdat2img.py -O tools/sdat2img.py
    python3 tools/sdat2img.py build/port_extracted/system.transfer.list build/port_extracted/system.new.dat build/port_system.img
elif [ -f "build/port_extracted/payload.bin" ]; then
     ./tools/payload-dumper-go -o build/port_images build/port_extracted/payload.bin
     mv build/port_images/system.img build/port_system.img
else
    echo "[!] Unknown Port ROM format. Ensure it has system.new.dat.br or payload.bin"
    exit 1
fi

# --- MOUNT AND SWAP ---
echo "[*] Mounting Images..."
mkdir -p mnt/base
mkdir -p mnt/port

# Mount Base (Read/Write to modify)
# Resize base to fit port files if necessary (add 500MB buffer)
e2fsck -f build/base_system.img
resize2fs build/base_system.img 3G 
sudo mount -o loop,rw build/base_system.img mnt/base

# Mount Port (Read Only)
sudo mount -o loop,ro build/port_system.img mnt/port

echo "[*] Performing THE SWAP..."
# 1. Clean Base System (Keep critical folders)
# We keep /system/vendor if it exists (for treble), but usually vendor is separate.
# In System-as-Root, we clean mostly everything except standard mounts.
sudo rm -rf mnt/base/system/app
sudo rm -rf mnt/base/system/priv-app
sudo rm -rf mnt/base/system/framework
sudo rm -rf mnt/base/system/media
sudo rm -rf mnt/base/system/etc/permissions
sudo rm -rf mnt/base/system/lib
sudo rm -rf mnt/base/system/lib64
sudo rm -rf mnt/base/system/usr
sudo rm -rf mnt/base/system/product
sudo rm -rf mnt/base/system/system_ext

# 2. Copy Port System
echo "[*] Copying POCO F1 system files to Pixel 3 XL Base..."
sudo cp -r mnt/port/system/* mnt/base/system/

# --- FIXES (The "Magic" Part) ---
echo "[*] Applying Crosshatch Fixes..."

# Fix 1: Build.prop identity
sudo sed -i 's/ro.product.device=beryllium/ro.product.device=crosshatch/g' mnt/base/system/build.prop
sudo sed -i 's/ro.product.name=beryllium/ro.product.name=crosshatch/g' mnt/base/system/build.prop

# Fix 2: Overlays (Try to preserve Base Overlays if backed up - simplified here)
# You would ideally copy back "framework-res__auto_generated_rro_product.apk" from a backup of base.

# --- UNMOUNT AND REPACK ---
echo "[*] Unmounting..."
sudo umount mnt/base
sudo umount mnt/port

echo "[*] Optimization..."
e2fsck -f build/base_system.img
resize2fs -M build/base_system.img # Shrink to min size

echo "[*] Done! File is ready."
echo "Your ported image is at: build/base_system.img"
echo "Download it and flash using: fastboot flash system build/base_system.img"
