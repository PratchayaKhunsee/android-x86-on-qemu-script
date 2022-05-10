#!/bin/bash
SCRIPT_DIR=$(dirname "$(readlink -f "$BASH_SOURCE")")
DOWNLOAD_PATH=$SCRIPT_DIR"/download"
QEMU_PATH=$SCRIPT_DIR"/qemu"
QEMU_BIN_PATH=$QEMU_PATH"/build"
ANDROID_X86_ISO="android-x86.iso"
ANDROID_X86_DL="https://free.nchc.org.tw/osdn//android-x86/71931/android-x86_64-9.0-r2.iso"
QEMU_VERSION="7.0.0"
QEMU_DL="https://download.qemu.org/qemu-$QEMU_VERSION.tar.xz"
QEMU_TAR="qemu-$QEMU_VERSION.tar.xz"
ROOT_EXEC=$([ $UID -eq 0 ] || echo "exec sudo")

# Making '/dev/kvm' being available for any user in 'kvm' user group
function fix-kvm(){
    USER=$(whoami)

    ARGS=$(getopt -o "h" -l "help" -- $@)
    eval set -- "$ARGS"
    while [ : ]; do
    case $1 in
        "-h"|"--help")
            help fix-kvm
            exit
            ;;
        "--")
            shift
            break 
            ;;
    esac
    done

    ($ROOT_EXEC addgroup kvm)
    ($ROOT_EXEC adduser $USER kvm)
    ($ROOT_EXEC chmod 660 /dev/kvm & echo "\"/dev/kvm\" permission modified.")
}

# Managing the required repositories for building QEMU binaries
function repo(){
    ARGS=$(getopt -o "h" -l "help" -- $@)
    eval set -- "$ARGS"
    while [ : ]; do
    case $1 in
        "-h"|"--help")
            help repo
            exit
            ;;
        "--")
            shift
            break 
            ;;
    esac
    done

    case $1 in
        add)
            CMD=install
        ;;
        remove)
            CMD=remove
        ;;
        *)
            help repo
            exit
        ;;
    esac
    $ROOT_EXEC apt-get $CMD libglib2.0-dev libfdt-dev libpixman-1-dev zlib1g-dev \
    libaio-dev libbluetooth-dev libbrlapi-dev libbz2-dev \
    libcap-ng-dev libcurl4-gnutls-dev libgtk-3-dev \
    libibverbs-dev libjpeg8-dev libncurses5-dev libnuma-dev \
    libsasl2-dev libsdl2-dev libseccomp-dev libsnappy-dev libssh-dev \
    libvde-dev libvdeplug-dev libvte-2.91-dev libxen-dev liblzo2-dev \
    valgrind xfslibs-dev
}

# Downloading the QEMU source code and Android x86 ISO image, then compiling the QEMU binaries
function prepare(){

    ARGS=$(getopt -o "h" -l "help" -- $@)
    eval set -- "$ARGS"
    while [ : ]; do
    case $1 in
        "-h"|"--help")
            help prepare
            exit 0
            ;;
        "--")
            shift
            break 
            ;;
    esac
    done
    
    # Creating ./download directory.
    if [ ! -e $DOWNLOAD_PATH ]
    then
        mkdir $DOWNLOAD_PATH
    fi
    
    echo "Downloading QEMU tarball package."
    wget -c -O "$DOWNLOAD_PATH/$QEMU_TAR" $QEMU_DL
    echo "Downloading Android x86 ISO."
    wget -c -O "$DOWNLOAD_PATH/$ANDROID_X86_ISO" $ANDROID_X86_DL
    
    # Checking QEMU binary path
    if [ ! -e "$QEMU_PATH" ]
    then
        mkdir "$QEMU_PATH"
    fi
    
    echo "Extracting QEMU build binaries."
    tar -xJf "$DOWNLOAD_PATH/$QEMU_TAR" -C "$QEMU_PATH"
    
    # Building QEMU executable
    if [ -e "$QEMU_PATH/qemu-$QEMU_VERSION" ]
    then
        echo "Building QEMU executable file."
        if [ ! -e $QEMU_BIN_PATH ] ; then mkdir $QEMU_BIN_PATH; fi
        (
            cd $QEMU_BIN_PATH
            echo $QEMU_BIN_PATH
            ../qemu-$QEMU_VERSION/configure --target-list=x86_64-softmmu \
            --enable-kvm --enable-opengl --enable-pa --enable-alsa \
            --enable-gtk --enable-sdl --enable-spice \
            --enable-virglrenderer
            make
        )
    else
        exit 1
    fi
}

# Creating the emlator's disk image
function create(){
    IMG_SIZE=32G
    DISKIMG_PATH="./android.img"

    ARGS=$(getopt -o "hs:" -l "help,size:" -- $@)
    eval set -- "$ARGS"
    while [ : ]; do
    case $1 in
        "-h"|"--help")
            help create
            exit 0
            ;;
        "-s"|"--size")
            IMG_SIZE=$2
            shift 2
            ;;
        "--")
            shift
            break 
            ;;
    esac
    done

    if [ ! -e $DISKIMG_PATH ]
    then
        $QEMU_BIN_PATH/qemu-img create -f qcow2 $DISKIMG_PATH $IMG_SIZE
    else
        echo "\"$DISKIMG_PATH\" is already existed."
    fi
}

# Running the emulator
function run(){
    # Variables
    CORES=$(nproc)
    MEM=4096
    SMB_DIR=""
    SMB=""
    NETDEV_ID="netdev_"$(openssl rand -hex 6)
    AUDIODEV_ID="sound_"=$(openssl rand -hex 6)
    AUDIODEV=pa
    CDROM_BOOT=""
    BOOT_OPTIONS="menu=on"
    DISKIMG_PATH="./android.img"

    ARGS=$(getopt -o "hm:c" -l "help,with-installer,shared-dir:,memory:,cores:" -- $@)
    eval set -- "$ARGS"
    while [ : ]; do
    case $1 in
        "-h"|"--help")
            help run
            exit 0
            ;;
        "-m"|"--memory")
            MEM=$2
            shift 2
            ;;
        "-c"|"--cores")
            CORES=$2
            shift 2
            ;;
        "--with-installer")
            CDROM_BOOT="-cdrom $DOWNLOAD_PATH/$ANDROID_X86_ISO"
            BOOT_OPTIONS="c,$BOOT_OPTIONS"
            shift
            ;;
        "--shared-dir")
            SMB_DIR=$2
            SMB=",smb=$SMB_DIR"
            shift 2
            ;;
        "--")
            shift
            break 
            ;;
    esac
    done

    if [[ $1 != "" ]] ; then DISKIMG_PATH=$1; fi
    if [ ! -e  $SMB_DIR ] ; then mkdir $SMB_DIR; fi
    
    $QEMU_BIN_PATH/qemu-system-x86_64 \
    -enable-kvm \
    -m $MEM \
    -smp $CORES \
    -cpu host \
    -display gtk,gl=on \
    -device AC97,audiodev=$AUDIODEV_ID \
    -device virtio-vga-gl \
    -device virtio-mouse-pci \
    -device virtio-keyboard-pci \
    -device virtio-net,netdev=$NETDEV_ID \
    -netdev user,id=$NETDEV_ID$SMB \
    -audiodev $AUDIODEV,id=$AUDIODEV_ID \
    -boot $BOOT_OPTIONS \
    $CDROM_BOOT \
    -hda $DISKIMG_PATH \
   
}

# Printing the command's information
function help(){
    # Fallback message
    fbMsg="Command:\n"
    fbMsg="${fbMsg}  help - print the command's information\n"
    fbMsg="${fbMsg}Usage:\n"
    fbMsg="${fbMsg}  $0 help <command>\n"
    fbMsg="${fbMsg}\n"
    fbMsg="${fbMsg}  <command> - a command from this script (run, create, prepare, ...)"
    # Main Message (Default is fallback message)
    msg=$fbMsg

    if [[ $1 != "" && $1 != "help" && $1 != "__MAN__"  && $(type -t $1) == "function" ]]
    then
        case $1 in
            "run")
            msg="Command:\n"
            msg="${msg}  run - run an emulator\n"
            msg="${msg}Usage:\n"
            msg="${msg}  $0 run [options] <image>\n"
            msg="${msg}\n"
            msg="${msg}  <image> - a disk image file (default: \"./android.img\")\n"
            msg="${msg}Options:\n"
            msg="${msg}  -m|--memory <ramsize>\t\tset the emulator's RAM size (default: 4096)\n"
            msg="${msg}  -c|--core <number>\t\tset the emulator's number of CPU cores (default: <the host cpu's core>)\n"
            msg="${msg}  --with-installer\t\tstart the emulator while mounting the Android x86 installer ISO as CDROM\n"
            msg="${msg}  --cdrom <disk-image>\t\tstart the emulator while mounting the specific disk image as CDROM\n"
            msg="${msg}  --shared-dir <directory>\tlocate the directory for file sharing across the emulator's network\n"
            msg="${msg}  -h|--help\t\t\tprint this command's information\n"
            ;;
            "create")
            msg="Command:\n"
            msg="${msg}  create - create a disk image for emulator\n"
            msg="${msg}Usage:\n"
            msg="${msg}  $0 create [options] <image>\n"
            msg="${msg}\n"
            msg="${msg}  <image> - a disk image file (default: \"./android.img\")\n"
            msg="${msg}Options:\n"
            msg="${msg}  -s|--size <disk-size>\tset the emulator's disk image size (default: 32G)\n"
            msg="${msg}  -h|--help\t\tprint this command's information\n"
            ;;
            "prepare")
            msg="Command:\n"
            msg="${msg}  prepare - download the QEMU source code and Android x86 ISO image, then compile the QEMU binaries\n"
            msg="${msg}Usage:\n"
            msg="${msg}  $0 prepare [options]\n"
            msg="${msg}Options:\n"
            msg="${msg}  -h|--help\t\tprint this command's information\n"
            ;;
            "fix-kvm")
            msg="Command:\n"
            msg="${msg}  fix-kvm\tmake KVM being usable for the current user (root permission required)\n"
            msg="${msg}Usage:\n"
            msg="${msg}  $0 fix-kvm [options]\n"
            msg="${msg}Options:\n"
            msg="${msg}  -h|--help\t\tprint this command's information\n"
            ;;
            "repo")
            msg="Command:\n"
            msg="${msg}  repo - manage the required repositories for building QEMU binaries (root permission required)\n"
            msg="${msg}Usage:\n"
            msg="${msg}  $0 repo [options] <command>\n"
            msg="${msg}\n"
            msg="${msg}  <command> - the command of managing the required repositories (add, remove)\n"
            msg="${msg}\n"
            msg="${msg}  repo add - install the required repository\n"
            msg="${msg}  repo remove - uninstall the required repository\n"
            msg="${msg}Options:\n"
            msg="${msg}  -h|--help\t\tprint this command's information\n"
            ;;
        esac
    fi

    echo -e $msg
}

function __FALLBACK__(){
    msg="===================================================================================\n"
    msg="${msg}\"Android x86 on QEMU\" bash script (Debian/Ubuntu).\n"
    msg="${msg}===================================================================================\n"
    msg="${msg}Usage:\n"
    msg="${msg}  $0 <command> [options]\n"
    msg="${msg}Commands:\n"
    msg="${msg}  - prepare\tdownload the QEMU source code and Android x86 ISO image, then compile the QEMU binaries\n"
    msg="${msg}  - create\tcreate a disk image for emulator\n"
    msg="${msg}  - run\t\trun an emulator\n"
    msg="${msg}  - help\t\tprint the command's information\n"
    msg="${msg}  - fix-kvm\tmake KVM being usable for the current user (root permission required)\n"
    msg="${msg}  - repo\t\tmanage the required repositories for building QEMU binaries (root permission required)\n"
    msg="${msg}\n"
    msg="${msg}You can also print the command's information by putting \"-h\" or \"--help\" option in the command's options section\n"
    echo -e $msg
}

if [ $(egrep -c '(vmx|svm)' /proc/cpuinfo) == "0" ]
then
    echo "No KVM supported. Exited."
    exit 1
fi

if [[ $1 == "--first-time" ]]
then
    (repo add)
    (prepare)
    (fix-kvm)
    exit
fi

if [[ $1 != "" && $1 != "__FALLBACK__" && $(type -t $1) == "function" ]]
then
    $@
    exit
fi

__FALLBACK__ $@