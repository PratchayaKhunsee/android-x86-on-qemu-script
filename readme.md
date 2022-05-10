# "Android x86 on QEMU" bash script (Debian/Ubuntu)

The chance to test "Android-x86 on QEMU" is here. It is simple and yet reliable solution for android emulation. 

## Easy steps to use this script for first time.

1. download the script
2. make the script being executable
3. run ./script.bash --first-time
4. your android emulator is complete

## What this script can do?

It now has 6 functions. 

> prepare - download the QEMU source code and Android x86 ISO image, then compile the QEMU binaries

> create - create a disk image for emulator

> run - run an emulator

> help - print the command's information

> fix-kvm - make KVM being usable for the current user (root permission required)

> repo - manage the required repositories for building QEMU binaries (root permission required)