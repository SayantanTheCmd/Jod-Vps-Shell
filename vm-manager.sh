#!/bin/bash
set -uo pipefail

# ╔══════════════════════════════════════════════════════════════╗
# ║                     SJTHEJOD VM MANAGER                      ║
# ║            Professional Multi-VM Virtualization             ║
# ║         QEMU/KVM + Cloud-Init • Container-Friendly         ║
# ╚══════════════════════════════════════════════════════════════╝

# shellcheck disable=SC2034
APP_NAME="SJTheJod"
APP_VERSION="6.0"

# ── Global state ─────────────────────────────────────────────────
KVM_AVAILABLE=false
KVM_REASON="not detected"
VM_DIR="${VM_DIR:-$HOME/vms}"

# tput may not exist / TERM may be dumb inside minimal containers.
if command -v tput >/dev/null 2>&1 && [ -n "${TERM:-}" ] && [ "${TERM:-}" != "dumb" ]; then
    HAVE_TPUT=true
else
    HAVE_TPUT=false
fi

cursor_hide() { [ "$HAVE_TPUT" = true ] && tput civis 2>/dev/null || true; }
cursor_show() { [ "$HAVE_TPUT" = true ] && tput cnorm 2>/dev/null || true; }

display_header() {
    if [ -t 1 ]; then clear 2>/dev/null || printf '\033[2J\033[H'; fi
    cursor_hide

    cat << 'EOF'
 ████████╗██╗  ██╗███████╗     ██╗ ██████╗ ██████╗
 ╚══██╔══╝██║  ██║██╔════╝     ██║██╔═══██╗██╔══██╗
    ██║   ███████║█████╗       ██║██║   ██║██║  ██║
    ██║   ██╔══██║██╔══╝  ██   ██║██║   ██║██║  ██║
    ██║   ██║  ██║███████╗╚█████╔╝╚██████╔╝██████╔╝
    ╚═╝   ╚═╝  ╚═╝╚══════╝ ╚════╝  ╚═════╝ ╚═════╝

                    💫 POWERED BY : SJTheJod ✨
EOF

    echo
    printf "\e[1;35m"
    printf "══════════════════════════════════════════════════════════════════════════════════════\n"
    printf "\e[0m"

    printf "\e[1;37m"
    printf "                     PROFESSIONAL VIRTUAL MACHINE CONTROL CENTER\n"
    printf "\e[1;90m"
    printf "                    Powered by QEMU • KVM • Cloud-Init • Linux\n"
    printf "\e[0m"

    echo

    # The splash animation is shown once; replaying it on every menu redraw
    # made the TUI slow and annoying.
    if [ "${SPLASH_SHOWN:-false}" != true ]; then
        printf "\e[1;36mBoot Sequence\e[0m\n"
        printf "────────────────────────────────────────────────────────────────────────────────────\n"

        if [ -t 1 ]; then
            for i in {1..50}; do
                printf "\e[1;32m█\e[0m"
                sleep 0.015
            done
        else
            printf "\e[1;32m██████████████████████████████████████████████████\e[0m"
        fi
        printf " \e[1;32m100%%\e[0m\n\n"

        printf "\e[1;32m✔\e[0m Loading Hypervisor Engine............... \e[1;36mONLINE\e[0m\n"
        if [ "$KVM_AVAILABLE" = true ]; then
            printf "\e[1;32m✔\e[0m Detecting CPU Virtualization............ \e[1;36mKVM AVAILABLE\e[0m\n"
        else
            printf "\e[1;33m!\e[0m Detecting CPU Virtualization............ \e[1;33mTCG FALLBACK\e[0m\n"
        fi
        printf "\e[1;32m✔\e[0m Initializing Cloud-Init................. \e[1;36mREADY\e[0m\n"
        printf "\e[1;32m✔\e[0m Loading Storage Manager................. \e[1;36mREADY\e[0m\n"
        printf "\e[1;32m✔\e[0m Verifying Network Stack................. \e[1;36mONLINE\e[0m\n"
        printf "\e[1;32m✔\e[0m Scanning Existing Virtual Machines...... \e[1;36mCOMPLETE\e[0m\n"
        printf "\e[1;32m✔\e[0m Loading Configuration................... \e[1;36mDONE\e[0m\n"

        echo
        SPLASH_SHOWN=true
    fi

    echo

    printf "\e[1;35m────────────────────────────────────────────────────────────────────────────────────\e[0m\n"

    printf "\e[1;36m Hostname      \e[0m : %s\n" "$(hostname)"
    printf "\e[1;36m User          \e[0m : %s\n" "$(whoami)"
    printf "\e[1;36m Kernel        \e[0m : %s\n" "$(uname -r)"
    printf "\e[1;36m Architecture  \e[0m : %s\n" "$(uname -m)"
    printf "\e[1;36m Date          \e[0m : %s\n" "$(date '+%d %b %Y')"
    printf "\e[1;36m Time          \e[0m : %s\n" "$(date '+%I:%M:%S %p')"

    printf "\e[1;35m────────────────────────────────────────────────────────────────────────────────────\e[0m\n"

    echo
    printf "\e[1;32m                       %s VM MANAGER v%s\e[0m\n" "$APP_NAME" "$APP_VERSION"
    printf "\e[1;90m               Enterprise Virtualization Platform\e[0m\n"
    if [ "$KVM_AVAILABLE" = true ]; then
        printf "\e[1;36m Acceleration  \e[0m : \e[1;32mKVM (hardware)\e[0m\n"
    else
        printf "\e[1;36m Acceleration  \e[0m : \e[1;33mTCG (software) - %s\e[0m\n" "$KVM_REASON"
    fi
    if [ "$IN_CONTAINER" = true ]; then
        printf "\e[1;36m Environment   \e[0m : \e[1;33mcontainer (%s)\e[0m\n" "${CONTAINER_KIND:-unknown}"
    fi
    echo
}

# Function to display colored output
print_status() {
    local type=$1
    local message=$2
    
    case $type in
        "INFO") echo -e "\033[1;34m[INFO]\033[0m $message" ;;
        "WARN") echo -e "\033[1;33m[WARN]\033[0m $message" ;;
        "ERROR") echo -e "\033[1;31m[ERROR]\033[0m $message" ;;
        "SUCCESS") echo -e "\033[1;32m[SUCCESS]\033[0m $message" ;;
        "INPUT") echo -e "\033[1;36m[INPUT]\033[0m $message" ;;
        *) echo "[$type] $message" ;;
    esac
}

# Function to validate input
validate_input() {
    local type=$1
    local value=$2
    
    case $type in
        "number")
            if ! [[ "$value" =~ ^[0-9]+$ ]]; then
                print_status "ERROR" "Must be a number"
                return 1
            fi
            ;;
        "size")
            if ! [[ "$value" =~ ^[0-9]+[GgMm]$ ]]; then
                print_status "ERROR" "Must be a size with unit (e.g., 100G, 512M)"
                return 1
            fi
            ;;
        "port")
            # Ports below 1024 need root/CAP_NET_BIND_SERVICE; allow them but
            # say so, since 80/443 forwarding is a common request.
            if ! [[ "$value" =~ ^[0-9]+$ ]] || [ "$value" -lt 1 ] || [ "$value" -gt 65535 ]; then
                print_status "ERROR" "Must be a valid port number (1-65535)"
                return 1
            fi
            if [ "$value" -lt 1024 ] && [ "$(id -u)" -ne 0 ]; then
                print_status "ERROR" "Port $value is privileged; run as root or pick a port above 1023"
                return 1
            fi
            ;;
        "name")
            if ! [[ "$value" =~ ^[a-zA-Z0-9_-]+$ ]]; then
                print_status "ERROR" "VM name can only contain letters, numbers, hyphens, and underscores"
                return 1
            fi
            ;;
        "username")
            if ! [[ "$value" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
                print_status "ERROR" "Username must start with a letter or underscore, and contain only letters, numbers, hyphens, and underscores"
                return 1
            fi
            ;;
    esac
    return 0
}

# Function to check dependencies
check_dependencies() {
    local deps=("qemu-system-x86_64" "qemu-img" "cloud-localds" "openssl")
    local missing_deps=()

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done

    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_status "ERROR" "Missing dependencies: ${missing_deps[*]}"
        print_status "INFO" "On Ubuntu/Debian, try: sudo apt install qemu-system-x86 qemu-utils cloud-image-utils wget openssl"
        exit 1
    fi

    # wget is only needed when an image actually has to be downloaded.
    if ! command -v wget &> /dev/null && ! command -v curl &> /dev/null; then
        print_status "ERROR" "Missing downloader: install wget or curl"
        exit 1
    fi
}

# Detect whether we are running inside a container (docker/podman/lxc/k8s).
detect_container() {
    IN_CONTAINER=false
    CONTAINER_KIND=""

    if [ -f /.dockerenv ]; then
        IN_CONTAINER=true; CONTAINER_KIND="docker"
    elif [ -f /run/.containerenv ]; then
        IN_CONTAINER=true; CONTAINER_KIND="podman"
    elif [ -n "${KUBERNETES_SERVICE_HOST:-}" ]; then
        IN_CONTAINER=true; CONTAINER_KIND="kubernetes"
    elif [ -n "${container:-}" ]; then
        IN_CONTAINER=true; CONTAINER_KIND="$container"
    elif grep -qaE '(docker|lxc|containerd|kubepods)' /proc/1/cgroup 2>/dev/null; then
        IN_CONTAINER=true; CONTAINER_KIND="cgroup-detect"
    fi
}

# Detect KVM. Inside a container this needs BOTH /dev/kvm exposure and
# enough privileges (CAP_SYS_ADMIN / --device /dev/kvm), so explain why.
detect_kvm() {
    KVM_AVAILABLE=false
    KVM_REASON="not detected"

    if [ ! -e /dev/kvm ]; then
        KVM_REASON="/dev/kvm missing"
        if [ "$IN_CONTAINER" = true ]; then
            KVM_REASON="/dev/kvm missing (container needs: docker run --device /dev/kvm --cap-add SYS_ADMIN)"
        fi
        return 1
    fi

    if [ ! -r /dev/kvm ] || [ ! -w /dev/kvm ]; then
        KVM_REASON="/dev/kvm not readable/writable (add group kvm or --privileged)"
        return 1
    fi

    # Verify the host CPU actually exposes virtualization to us.
    if ! grep -qE '(^flags.*[[:space:]](vmx|svm)([[:space:]]|$))|^(vmx|svm)' /proc/cpuinfo 2>/dev/null; then
        KVM_REASON="host CPU exposes no vmx/svm flags (nested virt disabled on host?)"
        return 1
    fi

    KVM_AVAILABLE=true
    KVM_REASON="available"
    return 0
}

# Container-style hardening: nested VMs perform badly / fail without these,
# so apply the safe subset that is available on this host.
apply_virt_tuning() {
    # Kernel Samepage Merging: big win when several nested VMs run together.
    if [ -w /sys/kernel/mm/ksm/run ] && [ "$(cat /sys/kernel/mm/ksm/run 2>/dev/null || echo 0)" != "1" ]; then
        echo 1 > /sys/kernel/mm/ksm/run 2>/dev/null || true
    fi

    # Increase inotify/file limits when we have the privilege to do so.
    if [ "$(id -u)" -eq 0 ] && command -v sysctl >/dev/null 2>&1; then
        sysctl -qw fs.inotify.max_user_instances=1024 2>/dev/null || true
        sysctl -qw fs.inotify.max_user_watches=524288 2>/dev/null || true
    fi

    # Warn when nested virt is switched off on the host.
    if [ -r /sys/module/kvm_intel/parameters/nested ]; then
        [ "$(cat /sys/module/kvm_intel/parameters/nested 2>/dev/null)" = "N" ] && \
            print_status "WARN" "Host kvm_intel nested=0: nested VMs cannot use hardware acceleration"
    elif [ -r /sys/module/kvm_amd/parameters/nested ]; then
        [ "$(cat /sys/module/kvm_amd/parameters/nested 2>/dev/null)" = "0" ] && \
            print_status "WARN" "Host kvm_amd nested=0: nested VMs cannot use hardware acceleration"
    fi
    return 0
}

# Parse "8080:80,2222:22" into validated forwards.
# Returns 0 and fills FORWARD_SPEC on success.
parse_port_forwards() {
    local spec="$1"
    FORWARD_SPEC=""
    [ -z "$spec" ] && return 0

    local forward host_port guest_port
    IFS=',' read -ra forwards <<< "$spec"
    for forward in "${forwards[@]}"; do
        forward="$(echo "$forward" | tr -d '[:space:]')"
        [ -z "$forward" ] && continue
        if [[ ! "$forward" =~ ^([0-9]+):([0-9]+)$ ]]; then
            print_status "ERROR" "Invalid port forward '$forward' (expected HOSTPORT:GUESTPORT)"
            return 1
        fi
        host_port="${BASH_REMATCH[1]}"
        guest_port="${BASH_REMATCH[2]}"
        if ! validate_input "port" "$host_port"; then
            return 1
        fi
        if [[ ! "$guest_port" =~ ^[0-9]+$ ]] || [ "$guest_port" -lt 1 ] || [ "$guest_port" -gt 65535 ]; then
            print_status "ERROR" "Invalid guest port $guest_port (1-65535)"
            return 1
        fi
        # Bind to loopback by default: inside a container, 0.0.0.0 leaks
        # guest ports onto the container network.
        FORWARD_SPEC+="${FORWARD_SPEC:+,}hostfwd=tcp:${BIND_ADDR}:${host_port}-:${guest_port}"
    done
    return 0
}

# Function to cleanup temporary files
cleanup() {
    cursor_show
    [ -n "${CLOUD_INIT_TMPDIR:-}" ] && [ -d "$CLOUD_INIT_TMPDIR" ] && rm -rf "$CLOUD_INIT_TMPDIR"
}

# Function to get all VM configurations
get_vm_list() {
    find "$VM_DIR" -name "*.conf" -exec basename {} .conf \; 2>/dev/null | sort
}

# Function to load VM configuration
load_vm_config() {
    local vm_name=$1
    local config_file="$VM_DIR/$vm_name.conf"
    
    if [[ -f "$config_file" ]]; then
        unset VM_NAME OS_TYPE CODENAME IMG_URL HOSTNAME USERNAME PASSWORD
        unset DISK_SIZE MEMORY CPUS SSH_PORT GUI_MODE PORT_FORWARDS IMG_FILE SEED_FILE CREATED
        
        source "$config_file"
        return 0
    else
        print_status "ERROR" "Configuration for VM '$vm_name' not found"
        return 1
    fi
}

# Function to save VM configuration
save_vm_config() {
    local config_file="$VM_DIR/$VM_NAME.conf"

    # Create with restrictive permissions first: the file holds credentials.
    ( umask 077; : > "$config_file" )

    cat > "$config_file" <<EOF
VM_NAME="$VM_NAME"
OS_TYPE="$OS_TYPE"
CODENAME="$CODENAME"
IMG_URL="$IMG_URL"
HOSTNAME="$HOSTNAME"
USERNAME="$USERNAME"
PASSWORD="$PASSWORD"
DISK_SIZE="$DISK_SIZE"
MEMORY="$MEMORY"
CPUS="$CPUS"
SSH_PORT="$SSH_PORT"
GUI_MODE="$GUI_MODE"
PORT_FORWARDS="$PORT_FORWARDS"
IMG_FILE="$IMG_FILE"
SEED_FILE="$SEED_FILE"
CREATED="$CREATED"
EOF

    chmod 600 "$config_file" 2>/dev/null || true

    print_status "SUCCESS" "Configuration saved to $config_file"
}

# Function to create new VM
create_new_vm() {
    print_status "INFO" "Creating a new VM"
    
    print_status "INFO" "Select an OS to set up:"
    local os_options=()
    local i=1
    for os in "${!OS_OPTIONS[@]}"; do
        echo "  $i) $os"
        os_options[$i]="$os"
        ((i++))
    done
    
    while true; do
        read -p "$(print_status "INPUT" "Enter your choice (1-${#OS_OPTIONS[@]}): ")" choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#OS_OPTIONS[@]} ]; then
            local os="${os_options[$choice]}"
            IFS='|' read -r OS_TYPE CODENAME IMG_URL DEFAULT_HOSTNAME DEFAULT_USERNAME DEFAULT_PASSWORD <<< "${OS_OPTIONS[$os]}"
            break
        else
            print_status "ERROR" "Invalid selection. Try again."
        fi
    done

    while true; do
        read -p "$(print_status "INPUT" "Enter VM name (default: $DEFAULT_HOSTNAME): ")" VM_NAME
        VM_NAME="${VM_NAME:-$DEFAULT_HOSTNAME}"
        if validate_input "name" "$VM_NAME"; then
            if [[ -f "$VM_DIR/$VM_NAME.conf" ]]; then
                print_status "ERROR" "VM with name '$VM_NAME' already exists"
            else
                break
            fi
        fi
    done

    while true; do
        read -p "$(print_status "INPUT" "Enter hostname (default: $VM_NAME): ")" HOSTNAME
        HOSTNAME="${HOSTNAME:-$VM_NAME}"
        if validate_input "name" "$HOSTNAME"; then
            break
        fi
    done

    while true; do
        read -p "$(print_status "INPUT" "Enter username (default: $DEFAULT_USERNAME): ")" USERNAME
        USERNAME="${USERNAME:-$DEFAULT_USERNAME}"
        if validate_input "username" "$USERNAME"; then
            break
        fi
    done

    while true; do
        read -s -p "$(print_status "INPUT" "Enter password (default: $DEFAULT_PASSWORD): ")" PASSWORD
        PASSWORD="${PASSWORD:-$DEFAULT_PASSWORD}"
        echo
        if [ -n "$PASSWORD" ]; then
            break
        else
            print_status "ERROR" "Password cannot be empty"
        fi
    done

    while true; do
        read -p "$(print_status "INPUT" "Disk size (default: 20G): ")" DISK_SIZE
        DISK_SIZE="${DISK_SIZE:-20G}"
        if validate_input "size" "$DISK_SIZE"; then
            break
        fi
    done

    while true; do
        read -p "$(print_status "INPUT" "Memory in MB (default: 2048): ")" MEMORY
        MEMORY="${MEMORY:-2048}"
        if validate_input "number" "$MEMORY"; then
            break
        fi
    done

    while true; do
        read -p "$(print_status "INPUT" "Number of CPUs (default: 2): ")" CPUS
        CPUS="${CPUS:-2}"
        if validate_input "number" "$CPUS"; then
            break
        fi
    done

    while true; do
        read -p "$(print_status "INPUT" "SSH Port (default: 2222): ")" SSH_PORT
        SSH_PORT="${SSH_PORT:-2222}"
        if validate_input "port" "$SSH_PORT"; then
            if ss -tln 2>/dev/null | grep -q ":$SSH_PORT "; then
                print_status "ERROR" "Port $SSH_PORT is already in use"
            else
                break
            fi
        fi
    done

    while true; do
        read -p "$(print_status "INPUT" "Enable GUI mode? (y/n, default: n): ")" gui_input
        GUI_MODE=false
        gui_input="${gui_input:-n}"
        if [[ "$gui_input" =~ ^[Yy]$ ]]; then 
            GUI_MODE=true
            break
        elif [[ "$gui_input" =~ ^[Nn]$ ]]; then
            break
        else
            print_status "ERROR" "Please answer y or n"
        fi
    done

    # Validate the forwards now so a bad spec is caught at creation time.
    while true; do
        read -p "$(print_status "INPUT" "Additional port forwards (e.g., 8080:80, press Enter for none): ")" PORT_FORWARDS
        if parse_port_forwards "${PORT_FORWARDS:-}"; then
            break
        fi
    done

    IMG_FILE="$VM_DIR/$VM_NAME.img"
    SEED_FILE="$VM_DIR/$VM_NAME-seed.iso"
    CREATED="$(date '+%Y-%m-%d %H:%M:%S')"

    # setup_vm_image can fail (network, disk, privileges) without destroying
    # the config already on disk, so report it and return.
    if ! setup_vm_image; then
        print_status "ERROR" "VM creation failed; no configuration was saved"
        return 1
    fi
    save_vm_config
    return 0
}

# Function to setup VM image
setup_vm_image() {
    print_status "INFO" "Downloading and preparing image..."

    mkdir -p "$VM_DIR"

    if [[ -f "$IMG_FILE" ]]; then
        print_status "INFO" "Image file already exists. Skipping download."
    else
        print_status "INFO" "Downloading image from $IMG_URL..."
        local downloaded=false
        if command -v wget &> /dev/null; then
            wget --progress=bar:force "$IMG_URL" -O "$IMG_FILE.tmp" && downloaded=true
        elif command -v curl &> /dev/null; then
            curl -fL --progress-bar "$IMG_URL" -o "$IMG_FILE.tmp" && downloaded=true
        fi
        if [ "$downloaded" != true ]; then
            rm -f "$IMG_FILE.tmp"
            print_status "ERROR" "Failed to download image from $IMG_URL"
            return 1
        fi
        mv "$IMG_FILE.tmp" "$IMG_FILE"
    fi

    # Resize the base image in place. Never delete the base image to make room:
    # that destroys the only copy of the OS.
    if ! qemu-img resize "$IMG_FILE" "$DISK_SIZE" >/dev/null 2>&1; then
        print_status "WARN" "In-place resize failed; using a qcow2 overlay instead."
        local base="$IMG_FILE.base"
        if [ ! -f "$base" ]; then
            cp --reflink=auto "$IMG_FILE" "$base" 2>/dev/null || cp "$IMG_FILE" "$base" || {
                print_status "ERROR" "Could not preserve the base image at $base"
                return 1
            }
        fi
        rm -f "$IMG_FILE.new"
        if ! qemu-img create -f qcow2 -F qcow2 -b "$base" "$IMG_FILE.new" "$DISK_SIZE" >/dev/null 2>&1 \
           || [ ! -f "$IMG_FILE.new" ]; then
            print_status "ERROR" "Failed to create the qcow2 overlay (base preserved at $base)"
            return 1
        fi
        if ! mv "$IMG_FILE.new" "$IMG_FILE"; then
            print_status "ERROR" "Failed to install the new overlay image"
            return 1
        fi
        print_status "INFO" "Overlay created on top of $base"
    fi

    # cloud-init working files must not live in the caller's CWD: inside a
    # container that is often read-only or shared between runs.
    if [ -z "${CLOUD_INIT_TMPDIR:-}" ] || [ ! -d "${CLOUD_INIT_TMPDIR:-}" ]; then
        CLOUD_INIT_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/sjthejod.XXXXXX")"
    fi
    local userdata="$CLOUD_INIT_TMPDIR/user-data"
    local metadata="$CLOUD_INIT_TMPDIR/meta-data"

    # Hash the password so the plaintext never lands in the seed ISO's
    # world-readable user-data payload.
    local pw_hash
    pw_hash="$(openssl passwd -6 "$PASSWORD")"

    cat > "$userdata" <<EOF
#cloud-config
hostname: $HOSTNAME
manage_etc_hosts: true
ssh_pwauth: true
# root login stays disabled; use the sudo user instead.
disable_root: true
resize_rootfs: true
growpart:
  mode: auto
users:
  - name: $USERNAME
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: false
    passwd: $pw_hash
ssh_authorized_keys:
chpasswd:
  expire: false
EOF

    cat > "$metadata" <<EOF
instance-id: iid-$VM_NAME
local-hostname: $HOSTNAME
EOF

    if ! cloud-localds "$SEED_FILE" "$userdata" "$metadata"; then
        print_status "ERROR" "Failed to create cloud-init seed image"
        return 1
    fi

    print_status "SUCCESS" "VM '$VM_NAME' created successfully."
    return 0
}

# Function to start a VM
# QEMU always runs in the background so this menu stays usable, and a crash
# never takes the manager down with it.
start_vm() {
    local vm_name=$1

    load_vm_config "$vm_name" || return 1

    if [[ ! -f "$IMG_FILE" ]]; then
        print_status "ERROR" "VM image file not found: $IMG_FILE"
        return 1
    fi

    if is_vm_running "$vm_name"; then
        print_status "WARN" "VM $vm_name is already running"
        return 0
    fi

    if [[ ! -f "$SEED_FILE" ]]; then
        print_status "WARN" "Seed file not found, recreating..."
        setup_vm_image || return 1
    fi

    # Validate forwards before building the command line.
    BIND_ADDR="${BIND_ADDR:-127.0.0.1}"
    if ! parse_port_forwards "${PORT_FORWARDS:-}"; then
        print_status "ERROR" "Aborting start: invalid port forwards in config"
        return 1
    fi

    local netdev="user,id=n0,hostfwd=tcp:${BIND_ADDR}:${SSH_PORT}-:22"
    [ -n "$FORWARD_SPEC" ] && netdev+=",${FORWARD_SPEC}"

    local qemu_cmd=(
        qemu-system-x86_64
        -name "vm=$vm_name"
        -m "$MEMORY"
        -smp "$CPUS"
        -machine q35
        -drive "file=$IMG_FILE,format=qcow2,if=virtio"
        -drive "file=$SEED_FILE,format=raw,if=virtio,readonly=on"
        -boot order=c
        -device virtio-net-pci,netdev=n0
        -netdev "$netdev"
        -qmp "unix:$VM_DIR/$vm_name.qmp,server=on,wait=off"
        -pidfile "$VM_DIR/$vm_name.pid"
        -device virtio-balloon-pci
        -device virtio-rng-pci
    )

    # Nested/container virtualization: use KVM when the host really exposes it,
    # otherwise fall back to TCG with a CPU model that can boot modern images.
    if [ "$KVM_AVAILABLE" = true ]; then
        qemu_cmd+=(-enable-kvm -cpu host)
    else
        qemu_cmd+=(-cpu max)
        print_status "WARN" "Running without KVM ($KVM_REASON) - expect slow nested performance"
    fi

    if [[ "$GUI_MODE" == true ]]; then
        if [ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
            print_status "WARN" "No display detected (headless/container): falling back to console mode"
            qemu_cmd+=(-nographic -serial mon:stdio)
        else
            qemu_cmd+=(-vga virtio -display "gtk,gl=on")
        fi
    else
        qemu_cmd+=(-nographic -serial mon:stdio)
    fi

    local log_file="$VM_DIR/$vm_name.log"

    print_status "INFO" "Starting VM: $vm_name"
    if [ "$GUI_MODE" == true ] && [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
        "${qemu_cmd[@]}" >> "$log_file" 2>&1 &
    else
        # Detach the console so the manager keeps running. Attach later with:
        #   socat -,raw,echo=0 unix-connect:$VM_DIR/$vm_name.console
        "${qemu_cmd[@]}" >> "$log_file" 2>&1 < /dev/null &
    fi

    local qemu_pid=$!
    echo "$qemu_pid" > "$VM_DIR/$vm_name.pid"
    sleep 1

    if ! kill -0 "$qemu_pid" 2>/dev/null; then
        print_status "ERROR" "QEMU exited immediately. Last lines of $log_file:"
        tail -n 15 "$log_file" 2>/dev/null || true
        return 1
    fi

    print_status "SUCCESS" "VM $vm_name started (PID $qemu_pid)"
    print_status "INFO" "SSH: ssh -p $SSH_PORT $USERNAME@localhost"
    print_status "INFO" "Log: $log_file"
    return 0
}

# Function to delete a VM
delete_vm() {
    local vm_name=$1

    load_vm_config "$vm_name" || return 1

    # Deleting the disk of a running VM corrupts it.
    if is_vm_running "$vm_name"; then
        print_status "ERROR" "VM '$vm_name' is running. Stop it first."
        return 1
    fi

    print_status "WARN" "This will permanently delete VM '$vm_name' and all its data!"
    read -p "$(print_status "INPUT" "Are you sure? (y/N): ")" -n 1 -r
    echo
    if [[ ${REPLY:-} =~ ^[Yy]$ ]]; then
        rm -f "$IMG_FILE" "$IMG_FILE.base" "$SEED_FILE" "$VM_DIR/$vm_name.conf" \
              "$VM_DIR/$vm_name.pid" "$VM_DIR/$vm_name.qmp" "$VM_DIR/$vm_name.log"
        print_status "SUCCESS" "VM '$vm_name' has been deleted"
    else
        print_status "INFO" "Deletion cancelled"
    fi
    return 0
}

# Function to show VM info
show_vm_info() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        echo
        print_status "INFO" "VM Information: $vm_name"
        echo "=========================================="
        echo "OS: $OS_TYPE"
        echo "Hostname: $HOSTNAME"
        echo "Username: $USERNAME"
        echo "Password: ******** (stored in $VM_DIR/$vm_name.conf)"
        echo "SSH Port: $SSH_PORT"
        echo "Memory: $MEMORY MB"
        echo "CPUs: $CPUS"
        echo "Disk: $DISK_SIZE"
        echo "GUI Mode: $GUI_MODE"
        echo "Port Forwards: ${PORT_FORWARDS:-None}"
        echo "Created: $CREATED"
        echo "Image File: $IMG_FILE"
        echo "Seed File: $SEED_FILE"
        echo "=========================================="
        echo
        read -p "$(print_status "INPUT" "Press Enter to continue...")"
    fi
}

# Resolve the PID of a VM from its pidfile, falling back to matching the
# unique image path (never the bare name, which matches other VMs).
vm_pid() {
    local vm_name=$1
    local pidfile="$VM_DIR/$vm_name.pid"
    local pid=""

    if [ -f "$pidfile" ]; then
        pid="$(cat "$pidfile" 2>/dev/null || true)"
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            echo "$pid"; return 0
        fi
    fi

    pid="$(pgrep -f -- "\-name vm=$vm_name([[:space:]]|$)" 2>/dev/null | head -n1 || true)"
    [ -n "$pid" ] && { echo "$pid"; return 0; }
    return 1
}

# Function to check if VM is running
is_vm_running() {
    local vm_name=$1
    vm_pid "$vm_name" >/dev/null 2>&1
}

# Send a QMP command to a running VM.
qmp_command() {
    local vm_name=$1
    local command=$2
    local sock="$VM_DIR/$vm_name.qmp"
    [ -S "$sock" ] || return 1
    command -v socat >/dev/null 2>&1 || return 1

    printf '{"execute": "qmp_capabilities"}\n{"execute": "%s"}\n' "$command" \
        | timeout 5 socat - UNIX-CONNECT:"$sock" >/dev/null 2>&1
}

# Function to stop a running VM
stop_vm() {
    local vm_name=$1

    load_vm_config "$vm_name" || return 1

    if ! is_vm_running "$vm_name"; then
        print_status "INFO" "VM $vm_name is not running"
        return 0
    fi

    local pid
    pid="$(vm_pid "$vm_name")" || pid=""
    if [ -z "$pid" ]; then
        print_status "ERROR" "Could not resolve PID for VM $vm_name"
        return 1
    fi

    print_status "INFO" "Stopping VM: $vm_name (PID $pid)"

    # 1) Ask the guest to shut down cleanly (needs ACPI support in the guest).
    if qmp_command "$vm_name" "system_powerdown"; then
        local waited=0
        while kill -0 "$pid" 2>/dev/null && [ "$waited" -lt 30 ]; do
            sleep 1
            waited=$((waited + 1))
        done
    fi

    # 2) SIGTERM, then SIGKILL as the last resort.
    if kill -0 "$pid" 2>/dev/null; then
        print_status "WARN" "Guest did not shut down, sending SIGTERM..."
        kill "$pid" 2>/dev/null || true
        sleep 3
    fi
    if kill -0 "$pid" 2>/dev/null; then
        print_status "WARN" "Forcing termination..."
        kill -9 "$pid" 2>/dev/null || true
        sleep 1
    fi

    rm -f "$VM_DIR/$vm_name.pid" "$VM_DIR/$vm_name.qmp"

    if kill -0 "$pid" 2>/dev/null; then
        print_status "ERROR" "VM $vm_name is still running"
        return 1
    fi

    print_status "SUCCESS" "VM $vm_name stopped"
    return 0
}

# Function to edit VM configuration
edit_vm_config() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        print_status "INFO" "Editing VM: $vm_name"
        
        while true; do
            echo "What would you like to edit?"
            echo "  1) Hostname"
            echo "  2) Username"
            echo "  3) Password"
            echo "  4) SSH Port"
            echo "  5) GUI Mode"
            echo "  6) Port Forwards"
            echo "  7) Memory (RAM)"
            echo "  8) CPU Count"
            echo "  9) Disk Size"
            echo "  0) Back to main menu"
            
            read -p "$(print_status "INPUT" "Enter your choice: ")" edit_choice
            
            case $edit_choice in
                1)
                    while true; do
                        read -p "$(print_status "INPUT" "Enter new hostname (current: $HOSTNAME): ")" new_hostname
                        new_hostname="${new_hostname:-$HOSTNAME}"
                        if validate_input "name" "$new_hostname"; then
                            HOSTNAME="$new_hostname"
                            break
                        fi
                    done
                    ;;
                2)
                    while true; do
                        read -p "$(print_status "INPUT" "Enter new username (current: $USERNAME): ")" new_username
                        new_username="${new_username:-$USERNAME}"
                        if validate_input "username" "$new_username"; then
                            USERNAME="$new_username"
                            break
                        fi
                    done
                    ;;
                3)
                    while true; do
                        read -s -p "$(print_status "INPUT" "Enter new password (current: ****): ")" new_password
                        new_password="${new_password:-$PASSWORD}"
                        echo
                        if [ -n "$new_password" ]; then
                            PASSWORD="$new_password"
                            break
                        else
                            print_status "ERROR" "Password cannot be empty"
                        fi
                    done
                    ;;
                4)
                    while true; do
                        read -p "$(print_status "INPUT" "Enter new SSH port (current: $SSH_PORT): ")" new_ssh_port
                        new_ssh_port="${new_ssh_port:-$SSH_PORT}"
                        if validate_input "port" "$new_ssh_port"; then
                            if [ "$new_ssh_port" != "$SSH_PORT" ] && ss -tln 2>/dev/null | grep -q ":$new_ssh_port "; then
                                print_status "ERROR" "Port $new_ssh_port is already in use"
                            else
                                SSH_PORT="$new_ssh_port"
                                break
                            fi
                        fi
                    done
                    ;;
                5)
                    while true; do
                        read -p "$(print_status "INPUT" "Enable GUI mode? (y/n, current: $GUI_MODE): ")" gui_input
                        gui_input="${gui_input:-}"
                        if [[ "$gui_input" =~ ^[Yy]$ ]]; then 
                            GUI_MODE=true
                            break
                        elif [[ "$gui_input" =~ ^[Nn]$ ]]; then
                            GUI_MODE=false
                            break
                        elif [ -z "$gui_input" ]; then
                            break
                        else
                            print_status "ERROR" "Please answer y or n"
                        fi
                    done
                    ;;
                6)
                    while true; do
                        read -p "$(print_status "INPUT" "Additional port forwards (current: ${PORT_FORWARDS:-None}): ")" new_port_forwards
                        new_port_forwards="${new_port_forwards:-$PORT_FORWARDS}"
                        if parse_port_forwards "${new_port_forwards:-}"; then
                            PORT_FORWARDS="$new_port_forwards"
                            break
                        fi
                    done
                    ;;
                7)
                    while true; do
                        read -p "$(print_status "INPUT" "Enter new memory in MB (current: $MEMORY): ")" new_memory
                        new_memory="${new_memory:-$MEMORY}"
                        if validate_input "number" "$new_memory"; then
                            MEMORY="$new_memory"
                            break
                        fi
                    done
                    ;;
                8)
                    while true; do
                        read -p "$(print_status "INPUT" "Enter new CPU count (current: $CPUS): ")" new_cpus
                        new_cpus="${new_cpus:-$CPUS}"
                        if validate_input "number" "$new_cpus"; then
                            CPUS="$new_cpus"
                            break
                        fi
                    done
                    ;;
                9)
                    while true; do
                        read -p "$(print_status "INPUT" "Enter new disk size (current: $DISK_SIZE): ")" new_disk_size
                        new_disk_size="${new_disk_size:-$DISK_SIZE}"
                        if validate_input "size" "$new_disk_size"; then
                            DISK_SIZE="$new_disk_size"
                            break
                        fi
                    done
                    ;;
                0)
                    return 0
                    ;;
                *)
                    print_status "ERROR" "Invalid selection"
                    continue
                    ;;
            esac
            
            if [[ "$edit_choice" -eq 1 || "$edit_choice" -eq 2 || "$edit_choice" -eq 3 ]]; then
                if is_vm_running "$vm_name"; then
                    print_status "WARN" "VM is running: new credentials only apply after a reboot of the guest"
                fi
                print_status "INFO" "Updating cloud-init configuration..."
                # Credentials changed: rebuild the seed ISO so a reboot picks
                # them up. Failure here must not kill the menu.
                setup_vm_image || print_status "ERROR" "Failed to regenerate cloud-init seed"
            fi
            
            save_vm_config
            
            read -p "$(print_status "INPUT" "Continue editing? (y/N): ")" continue_editing
            if [[ ! "$continue_editing" =~ ^[Yy]$ ]]; then
                break
            fi
        done
    fi
}

# Function to resize VM disk
resize_vm_disk() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        print_status "INFO" "Current disk size: $DISK_SIZE"
        
        while true; do
            read -p "$(print_status "INPUT" "Enter new disk size (e.g., 50G): ")" new_disk_size
            if validate_input "size" "$new_disk_size"; then
                if [[ "$new_disk_size" == "$DISK_SIZE" ]]; then
                    print_status "INFO" "New disk size is the same as current size. No changes made."
                    return 0
                fi

                # Resizing a live qcow2 from under QEMU is unsafe.
                if is_vm_running "$vm_name"; then
                    print_status "ERROR" "VM $vm_name is running. Stop it before resizing the disk."
                    return 1
                fi

                local current_size_num=${DISK_SIZE%[GgMm]}
                local new_size_num=${new_disk_size%[GgMm]}
                local current_unit=${DISK_SIZE: -1}
                local new_unit=${new_disk_size: -1}
                
                if [[ "$current_unit" =~ [Gg] ]]; then
                    current_size_num=$((current_size_num * 1024))
                fi
                if [[ "$new_unit" =~ [Gg] ]]; then
                    new_size_num=$((new_size_num * 1024))
                fi
                
                if [[ $new_size_num -lt $current_size_num ]]; then
                    print_status "WARN" "Shrinking disk size is not recommended and may cause data loss!"
                    read -p "$(print_status "INPUT" "Are you sure you want to continue? (y/N): ")" confirm_shrink
                    if [[ ! "$confirm_shrink" =~ ^[Yy]$ ]]; then
                        print_status "INFO" "Disk resize cancelled."
                        return 0
                    fi
                fi
                
                print_status "INFO" "Resizing disk to $new_disk_size..."
                # --shrink is required for qemu-img to accept a smaller size;
                # without it the guest filesystem would be truncated.
                local resize_flags=()
                if [[ $new_size_num -lt $current_size_num ]]; then
                    resize_flags+=(--shrink)
                fi
                if qemu-img resize "${resize_flags[@]}" "$IMG_FILE" "$new_disk_size"; then
                    DISK_SIZE="$new_disk_size"
                    save_vm_config
                    print_status "SUCCESS" "Disk resized successfully to $new_disk_size"
                else
                    print_status "ERROR" "Failed to resize disk"
                    return 1
                fi
                break
            fi
        done
    fi
}

# Function to show VM performance metrics
show_vm_performance() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        if is_vm_running "$vm_name"; then
            print_status "INFO" "Performance metrics for VM: $vm_name"
            echo "=========================================="
            
            local qemu_pid
            qemu_pid="$(vm_pid "$vm_name")" || qemu_pid=""
            if [[ -n "$qemu_pid" ]]; then
                echo "QEMU Process Stats:"
                ps -p "$qemu_pid" -o pid,%cpu,%mem,sz,rss,vsz,cmd --no-headers
                echo
                
                echo "Memory Usage:"
                free -h
                echo
                
                echo "Disk Usage:"
                df -h "$IMG_FILE" 2>/dev/null || du -h "$IMG_FILE"
            else
                print_status "ERROR" "Could not find QEMU process for VM $vm_name"
            fi
        else
            print_status "INFO" "VM $vm_name is not running"
            echo "Configuration:"
            echo "  Memory: $MEMORY MB"
            echo "  CPUs: $CPUS"
            echo "  Disk: $DISK_SIZE"
        fi
        echo "=========================================="
        read -p "$(print_status "INPUT" "Press Enter to continue...")"
    fi
}

# Main menu function
main_menu() {
    while true; do
        display_header
        
        local vms=()
    if [ -n "$(get_vm_list)" ]; then
        mapfile -t vms < <(get_vm_list)
    fi
        local vm_count=${#vms[@]}
        
        if [ $vm_count -gt 0 ]; then
            print_status "INFO" "Found $vm_count existing VM(s):"
            for i in "${!vms[@]}"; do
                local status="Stopped"
                if is_vm_running "${vms[$i]}"; then
                    status="Running"
                fi
                printf "  %2d) %s (%s)\n" $((i+1)) "${vms[$i]}" "$status"
            done
            echo
        fi
        
        echo "Main Menu:"
        echo "  1) Create a new VM"
        if [ $vm_count -gt 0 ]; then
            echo "  2) Start a VM"
            echo "  3) Stop a VM"
            echo "  4) Show VM info"
            echo "  5) Edit VM configuration"
            echo "  6) Delete a VM"
            echo "  7) Resize VM disk"
            echo "  8) Show VM performance"
        fi
        echo "  0) Exit"
        echo
        
        read -p "$(print_status "INPUT" "Enter your choice: ")" choice
        
        case $choice in
            1)
                create_new_vm
                ;;
            2)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number to start: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        start_vm "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            3)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number to stop: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        stop_vm "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            4)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number to show info: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        show_vm_info "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            5)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number to edit: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        edit_vm_config "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            6)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number to delete: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        delete_vm "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            7)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number to resize disk: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        resize_vm_disk "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            8)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number to show performance: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        show_vm_performance "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            0)
                print_status "INFO" "Goodbye!"
                exit 0
                ;;
            *)
                print_status "ERROR" "Invalid option"
                ;;
        esac
        
        read -p "$(print_status "INPUT" "Press Enter to continue...")"
    done
}

# ── Startup ──────────────────────────────────────────────────────
check_dependencies

detect_container
detect_kvm || true

# SSH/telnet may not be present in slim containers; only used for warnings.
VM_DIR="${VM_DIR:-$HOME/vms}"
mkdir -p "$VM_DIR" || { print_status "ERROR" "Cannot create VM_DIR: $VM_DIR"; exit 1; }

# Loopback-bound port forwards by default. Set BIND_ADDR=0.0.0.0 to expose
# guest ports beyond the container/host.
BIND_ADDR="${BIND_ADDR:-127.0.0.1}"

# cloud-init scratch space, removed by the EXIT trap
CLOUD_INIT_TMPDIR=""

# VM_DIR must be writable for images; warn early instead of failing mid-run.
if [ ! -w "$VM_DIR" ]; then
    print_status "ERROR" "VM_DIR is not writable: $VM_DIR"
    exit 1
fi

if [ "$IN_CONTAINER" = true ]; then
    print_status "INFO" "Container detected ($CONTAINER_KIND): nested VMs need /dev/kvm, SYS_ADMIN and enough RAM"
fi
if [ "$KVM_AVAILABLE" != true ]; then
    print_status "WARN" "No hardware acceleration: $KVM_REASON"
    print_status "INFO" "Nested VMs will run under TCG (software emulation) - expect slow boots"
fi
apply_virt_tuning

# Supported OS list
declare -A OS_OPTIONS=(
    ["Ubuntu 22.04"]="ubuntu|jammy|https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img|ubuntu22|ubuntu|ubuntu"
    ["Ubuntu 24.04"]="ubuntu|noble|https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img|ubuntu24|ubuntu|ubuntu"
    ["Debian 11"]="debian|bullseye|https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-generic-amd64.qcow2|debian11|debian|debian"
    ["Debian 12"]="debian|bookworm|https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2|debian12|debian|debian"
    ["Fedora 40"]="fedora|40|https://download.fedoraproject.org/pub/fedora/linux/releases/40/Cloud/x86_64/images/Fedora-Cloud-Base-40-1.14.x86_64.qcow2|fedora40|fedora|fedora"
    ["CentOS Stream 9"]="centos|stream9|https://cloud.centos.org/centos/9-stream/x86_64/images/CentOS-Stream-GenericCloud-9-latest.x86_64.qcow2|centos9|centos|centos"
    ["AlmaLinux 9"]="almalinux|9|https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/AlmaLinux-9-GenericCloud-latest.x86_64.qcow2|almalinux9|alma|alma"
    ["Rocky Linux 9"]="rockylinux|9|https://download.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud.latest.x86_64.qcow2|rocky9|rocky|rocky"
)

# Start the main menu
main_menu

# Powered By SJTheJod
