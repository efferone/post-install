#!/bin/bash

# log all the things!
log_dir="$HOME/logs"
mkdir -p "$log_dir"
log_file="$log_dir/post-install-$(date +%Y%m%d-%H%M%S).log"

# save the original file descriptors
exec 3>&1 4>&2

# redirect all script output to both the terminal and log file
exec 1> >(tee -a "$log_file")
exec 2> >(tee -a "$log_file" >&2)

echo 
echo 
echo "~~~########################################~~~"
echo "Post-install script started at $(date)"
echo "Logging to: $log_file"
echo "~~~########################################~~~"

# colours for more pretty
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[1;33m'
blue='\033[0;34m'
nc='\033[0m' # no colour

# creating a variable to track group changes
groups_modified=false

# function to display messages
print_message() {
    echo -e "${blue}[*]${nc} $1"
}

print_success() {
    echo -e "${green}[+]${nc} $1"
}

print_error() {
    echo -e "${red}[-]${nc} $1"
}

print_warning() {
    echo -e "${yellow}[!]${nc} $1"
}

# function to check if user has sudo privileges
check_sudo() {
    print_message "Checking sudo privileges"
    if sudo -v &>/dev/null; then
        print_success "You already have sudo privileges."
        return 0
    else
        print_message "You don't have sudo privileges. Enter your root pw"
        # need to use su to add the user to sudo group from inside the script.
        if [ "$pkg_manager" = "zypper" ]; then
            su -c "usermod -aG wheel $USER" root
        else
            su -c "usermod -aG sudo $USER" root
        fi
        
        if [ $? -eq 0 ]; then
            print_success "Added $USER to sudo group."
            groups_modified=true
            print_message "Applying group changes"
            if [ "$pkg_manager" = "zypper" ]; then
                print_message "Quit the script run 'newgrp wheel' then run the script again"
            else
                print_message "Quit the script run 'newgrp sudo' then run the script again"
            fi
            print_message "Press 'q' to quit."

            # Wait for user to press 'q'
            while true; do
                read -n 1 key
                if [[ $key = q ]]; then
                    echo ""
                    if [ "$pkg_manager" = "zypper" ]; then
                        echo "Exiting script. Please run 'newgrp wheel' and restart the script."
                    else
                        echo "Exiting script. Please run 'newgrp sudo' and restart the script."
                    fi
                    exit 0
                fi
            done
        else
            print_error "Failed to add user to sudo group. This script requires sudo privileges."
            return 1
        fi
    fi
}

# detect system info, de/wm etc
detect_system_info() {
    print_message "Detecting system info"

    # detect distro
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        distro="${NAME:-$ID}"
    elif [ -f /etc/lsb-release ]; then
        . /etc/lsb-release
        distro="${DISTRIB_DESCRIPTION:-$DISTRIB_ID}"
    elif [ -f /etc/debian_version ]; then
        distro="Debian $(cat /etc/debian_version)"
    else
        distro="$(uname -s) $(uname -r)"
    fi

    # detect package manager
    if command -v apt &>/dev/null; then
        pkg_manager="apt"
    elif command -v zypper &>/dev/null; then
        pkg_manager="zypper"
    elif command -v dnf &>/dev/null; then
        pkg_manager="dnf"
    elif command -v yum &>/dev/null; then
        pkg_manager="yum"
    elif command -v pacman &>/dev/null; then
        pkg_manager="pacman"
    else
        pkg_manager="Unknown"
    fi

    # detect init system
    if command -v systemctl &>/dev/null; then
        init_system="systemd"
    elif [ -f /sbin/init ] && file /sbin/init | grep -q upstart; then
        init_system="upstart"
    elif [ -f /sbin/init ] && file /sbin/init | grep -q sysvinit; then
        init_system="sysvinit"
    else
        init_system="$(ps -p 1 -o comm=)"
    fi

    # a few methods to detect DE because original function wasn't always working..
    if [ -n "$XDG_CURRENT_DESKTOP" ]; then
        de="$XDG_CURRENT_DESKTOP"
    elif [ -n "$DESKTOP_SESSION" ]; then
        de="$DESKTOP_SESSION"
    elif [ -n "$GNOME_DESKTOP_SESSION_ID" ]; then
        de="GNOME"
    elif [ -n "$KDE_FULL_SESSION" ]; then
        de="KDE"
    elif pgrep -x "gnome-session" >/dev/null; then
        de="GNOME"
    elif pgrep -x "ksmserver" >/dev/null; then
        de="KDE"
    elif pgrep -x "xfce4-session" >/dev/null; then
        de="XFCE"
    elif pgrep -x "mate-session" >/dev/null; then
        de="MATE"
    elif pgrep -x "lxsession" >/dev/null; then
        de="LXDE"
    elif pgrep -x "cinnamon-session" >/dev/null; then
        de="Cinnamon"
    else
        de="Unknown"
    fi

    # window manager detection
    if command -v wmctrl &>/dev/null; then
        wm=$(wmctrl -m 2>/dev/null | grep "Name:" | cut -d: -f2 | xargs)
    fi

    # and if wmctrl didn't work
    if [ -z "$wm" ] || [ "$wm" = "Unknown" ]; then
        # check $WINDOW_MANAGER
        if [ -n "$WINDOW_MANAGER" ]; then
            wm=$(basename "$WINDOW_MANAGER")
        # or check running processes
        elif pgrep -x "i3" >/dev/null; then
            wm="i3"
        elif pgrep -x "openbox" >/dev/null; then
            wm="Openbox"
        elif pgrep -x "xfwm4" >/dev/null; then
            wm="Xfwm4"
        elif pgrep -x "kwin" >/dev/null; then
            wm="KWin"
        elif pgrep -x "mutter" >/dev/null; then
            wm="Mutter"
        elif pgrep -x "compiz" >/dev/null; then
            wm="Compiz"
        elif pgrep -x "dwm" >/dev/null; then
            wm="dwm"
        elif pgrep -x "awesome" >/dev/null; then
            wm="Awesome"
        # or finally extract from GNOME or KDE
        elif [ "$de" = "GNOME" ]; then
            wm="Mutter"
        elif [ "$de" = "KDE" ]; then
            wm="KWin"
        else
            wm="Unknown"
        fi
    fi

    # install wmctrl if needed for future runs
    if [ "$wm" = "Unknown" ]; then
        case "$pkg_manager" in
            "apt")
                print_warning "Could not detect window manager. Installing wmctrl for better detection."
                sudo apt install -y wmctrl 2>/dev/null
                ;;
            "zypper")
                print_warning "Could not detect window manager. Installing wmctrl for better detection."
                sudo zypper --non-interactive install wmctrl 2>/dev/null
                ;;
        esac
    fi
}

# fancy banner, ASCII is never not cool
display_banner() {
    clear
    echo -e "${blue}"
    echo "  _____           _      _____           _        _ _ "
    echo " |  __ \         | |    |_   _|         | |      | | |"
    echo " | |__) |__  ___ | |_     | |  _ __  ___| |_ __ _| | |"
    echo " |  ___/ _ \/ __|| __|    | | | '_ \/ __| __/ _\` | | |"
    echo " | |  | (_) \__ \| |_    _| |_| | | \__ \ || (_| | | |"
    echo " |_|   \___/|___/ \__|  |_____|_| |_|___/\__\__,_|_|_|"
    echo -e "${nc}"
    echo -e "Distribution: ${green}$distro${nc}"
    echo -e "Package Manager: ${green}$pkg_manager${nc}"
    echo -e "Init System: ${green}$init_system${nc}"
    echo -e "Desktop Environment: ${green}$de${nc}"
    echo -e "Window Manager: ${green}$wm${nc}"
    echo ""
}

# Improved package installation function with better alternative handling
install_packages() {
    print_message "Package Installation"

    # define packages - ensure they're in numerical order
    declare -A packages
    packages[1]="terminator"
    packages[2]="vim"
    packages[3]="git"
    packages[4]="wget"
    packages[5]="curl"
    packages[6]="freerdp"
    packages[7]="vscodium"
    packages[8]="joplin"
    packages[9]="slack"
    packages[10]="docker"

    # display available packages
    echo -e "\nAvailable packages:"
    echo "0. All"

    # package list in correct order this time
    for i in $(seq 1 ${#packages[@]}); do
        echo "$i. ${packages[$i]}"
    done

    # get user input
    echo -e "\nEnter the numbers of packages you want to install (space-separated):"
    read -r selections

    # '10' was being interpreted as '1' and '0', so everything was getting installed if I chose 10 oops
    if [[ $selections == "0" ]]; then
        selections=$(seq 1 ${#packages[@]} | tr '\n' ' ')
    fi

    # keep a track of installation results
    declare -A install_results

    # process each selected package
    for selection in $selections; do
        if [[ $selection -ge 1 && $selection -le ${#packages[@]} ]]; then
            package=${packages[$selection]}
            print_message "Installing $package"

            # install packages not in the repo
            case "$package" in
            "joplin")
                install_joplin
                if [ $? -eq 0 ]; then
                    install_results[$package]="SUCCESS"
                else
                    install_results[$package]="FAILED"
                fi
                ;;

            "slack")
                install_slack
                if [ $? -eq 0 ]; then
                    install_results[$package]="SUCCESS"
                else
                    install_results[$package]="FAILED"
                fi
                ;;

            "vscodium")
                install_vscodium
                if [ $? -eq 0 ]; then
                    install_results[$package]="SUCCESS"
                else
                    install_results[$package]="FAILED"
                fi
                ;;

            "docker")
                # Try package manager specific docker installation
                case "$pkg_manager" in
                    "apt")
                        if sudo apt install -y docker docker-compose &>/dev/null; then
                            print_success "Docker and docker-compose installed successfully via apt."
                            # add my user to docker group
                            sudo usermod -aG docker $USER
                            groups_modified=true
                            install_results[$package]="SUCCESS"
                        else
                            print_warning "Couldn't install Docker via apt, falling back to Docker's repo"
                            install_docker
                            if [ $? -eq 0 ]; then
                                install_results[$package]="SUCCESS"
                            else
                                install_results[$package]="FAILED"
                            fi
                        fi
                        ;;
                    "zypper")
                        # In openSUSE, Docker is provided as docker and docker-compose
                        if sudo zypper --non-interactive install docker docker-compose; then
                            print_success "Docker and docker-compose installed successfully via zypper."
                            # Add user to docker group
                            sudo usermod -aG docker $USER
                            # Enable and start the Docker service
                            sudo systemctl enable docker
                            sudo systemctl start docker
                            groups_modified=true
                            install_results[$package]="SUCCESS"
                        else
                            # Check if packages are already installed
                            if sudo zypper info docker &>/dev/null && sudo zypper info docker-compose &>/dev/null; then
                                print_success "Docker and docker-compose are already installed."
                                # Ensure user is in docker group
                                sudo usermod -aG docker $USER
                                # Ensure Docker service is enabled and running
                                sudo systemctl enable docker
                                sudo systemctl start docker
                                groups_modified=true
                                install_results[$package]="SUCCESS"
                            else
                                print_error "Failed to install Docker via zypper."
                                install_results[$package]="FAILED"
                            fi
                        fi
                        ;;
                esac
                ;;

            *)
                # Install standard packages using the appropriate package manager
                case "$pkg_manager" in
                    "apt")
                        if sudo apt install -y "$package" &>/dev/null; then
                            print_success "$package installed successfully."
                            install_results[$package]="SUCCESS"
                        else
                            print_error "Failed to install $package. Looking for alternatives..."

                            # some packages go by a different name so..
                            results=$(apt-cache search "$package" | grep -i "$package" | head -n 5)

                            if [ -n "$results" ]; then
                                echo -e "Found possible alternatives:"
                                counter=1
                                alt_packages=()

                                # display and store package names
                                while IFS= read -r line; do
                                    pkg_name=$(echo "$line" | awk '{print $1}')
                                    pkg_desc=$(echo "$line" | cut -d ' ' -f 2-)
                                    echo -e "$counter. ${green}$pkg_name${nc} - $pkg_desc"
                                    alt_packages+=("$pkg_name")
                                    counter=$((counter + 1))
                                done <<<"$results"

                                echo "Enter the number to install (or 0 to skip):"
                                read -r alt_selection

                                if [[ "$alt_selection" =~ ^[0-9]+$ ]] && [ "$alt_selection" != "0" ] && [ "$alt_selection" -le "${#alt_packages[@]}" ]; then
                                    alt_package="${alt_packages[$((alt_selection - 1))]}"

                                    if sudo apt install -y "$alt_package" &>/dev/null; then
                                        print_success "$alt_package installed successfully."
                                        install_results[$package]="INSTALLED $alt_package INSTEAD"
                                    else
                                        print_error "Failed to install $alt_package."
                                        install_results[$package]="FAILED"
                                    fi
                                else
                                    install_results[$package]="SKIPPED"
                                fi
                            else
                                print_error "No alternatives found for $package."
                                install_results[$package]="FAILED"
                            fi
                        fi
                        ;;
                    "zypper")
                        # Map package names if necessary for openSUSE
                        case "$package" in
                            "terminator")
                                opensuse_pkg="terminator"
                                ;;
                            "freerdp")
                                opensuse_pkg="freerdp"
                                ;;
                            *)
                                opensuse_pkg="$package"
                                ;;
                        esac
                        
                        if sudo zypper --non-interactive install "$opensuse_pkg"; then
                            print_success "$package installed successfully."
                            install_results[$package]="SUCCESS"
                        else
                            print_error "Failed to install $package. Looking for alternatives..."

                            # Search for alternatives
                            results=$(zypper search "$package" | grep -i "$package" | head -n 5)

                            if [ -n "$results" ]; then
                                echo -e "Found possible alternatives:"
                                counter=1
                                alt_packages=()

                                # display and store package names
                                while IFS= read -r line; do
                                    # Extract package name from zypper search output
                                    pkg_name=$(echo "$line" | awk '{print $5}')
                                    pkg_desc=$(echo "$line" | awk '{$1=$2=$3=$4=$5=""; print $0}' | sed 's/^ *//')
                                    
                                    if [ -n "$pkg_name" ]; then
                                        echo -e "$counter. ${green}$pkg_name${nc} - $pkg_desc"
                                        alt_packages+=("$pkg_name")
                                        counter=$((counter + 1))
                                    fi
                                done <<<"$results"

                                echo "Enter the number to install (or 0 to skip):"
                                read -r alt_selection

                                if [[ "$alt_selection" =~ ^[0-9]+$ ]] && [ "$alt_selection" != "0" ] && [ "$alt_selection" -le "${#alt_packages[@]}" ]; then
                                    alt_package="${alt_packages[$((alt_selection - 1))]}"

                                    if sudo zypper --non-interactive install "$alt_package"; then
                                        print_success "$alt_package installed successfully."
                                        install_results[$package]="INSTALLED $alt_package INSTEAD"
                                    else
                                        print_error "Failed to install $alt_package."
                                        install_results[$package]="FAILED"
                                    fi
                                else
                                    install_results[$package]="SKIPPED"
                                fi
                            else
                                print_error "No alternatives found for $package."
                                install_results[$package]="FAILED"
                            fi
                        fi
                        ;;
                esac
                ;;
            esac
        fi
    done

    # display installation summary
    echo -e "\n~#~ Installation Summary ~#~"
    for package in "${!install_results[@]}"; do
        result=${install_results[$package]}
        if [ "$result" == "SUCCESS" ]; then
            echo -e "${green}[✓]${nc} $package: $result"
        elif [ "$result" == "SKIPPED" ]; then
            echo -e "${yellow}[!]${nc} $package: $result"
        else
            echo -e "${red}[✗]${nc} $package: $result"
        fi
    done

    # next change some configs
    configure_packages
}

## a fair few packages I need aren't in default repos so a few functions to handle that, this might not be the cleanest way but it works

# install Joplin
install_joplin() {
    print_message "Installing Joplin"

    # Install dependencies based on package manager
    case "$pkg_manager" in
        "apt")
            print_message "Installing Joplin dependencies"
            sudo apt install -y libfuse2

            if [ $? -ne 0 ]; then
                print_error "Failed to install Joplin dependencies (libfuse2)"
                return 1
            fi
            ;;
        "zypper")
            print_message "Installing Joplin dependencies"
            # Fix: Use the correct package name libfuse2 instead of fuse2
            sudo zypper --non-interactive install libfuse2

            if [ $? -ne 0 ]; then
                print_error "Failed to install Joplin dependencies (libfuse2)"
                return 1
            fi
            ;;
    esac

    # make sure wget is installed
    if ! command -v wget &>/dev/null; then
        case "$pkg_manager" in
            "apt")
                sudo apt install -y wget
                ;;
            "zypper")
                sudo zypper --non-interactive install wget
                ;;
        esac
    fi

    # download and run installer
    wget -O - https://raw.githubusercontent.com/laurent22/joplin/dev/Joplin_install_and_update.sh | bash

    if [ $? -eq 0 ]; then
        print_success "Joplin installed successfully."
        return 0
    else
        print_error "Failed to install Joplin."
        return 1
    fi
}

# install Slack
install_slack() {
    print_message "Installing Slack"

    case "$pkg_manager" in
        "apt")
            # download Slack .deb package
            wget -O /tmp/slack.deb "https://downloads.slack-edge.com/releases/linux/4.31.155/prod/x64/slack-desktop-4.31.155-amd64.deb"

            if [ $? -ne 0 ]; then
                print_error "Failed to download Slack package."
                return 1
            fi

            # install dependencies
            sudo apt install -y libappindicator1 libindicator7

            # install the .deb
            sudo dpkg -i /tmp/slack.deb

            if [ $? -ne 0 ]; then
                sudo apt install -f -y
                sudo dpkg -i /tmp/slack.deb
            fi

            # clean up after
            rm -f /tmp/slack.deb
            ;;
        "zypper")
            # For openSUSE, download the RPM package
            wget -O /tmp/slack.rpm "https://downloads.slack-edge.com/releases/linux/4.31.155/prod/x64/slack-4.31.155-0.1.el8.x86_64.rpm"

            if [ $? -ne 0 ]; then
                print_error "Failed to download Slack package."
                return 1
            fi

            # Install the RPM and choose 'i' for ignore when asked about unsigned package
            # Use expect-like approach to handle interactive prompts
            print_message "Installing Slack RPM without signature check using rpm directly"
            sudo rpm -ivh --nosignature /tmp/slack.rpm

            # Clean up
            rm -f /tmp/slack.rpm
            ;;
    esac

    if command -v slack &>/dev/null; then
        print_success "Slack installed successfully."
        return 0
    else
        print_warning "Slack command not found, but installation might have completed. Check your applications menu."
        # On some systems, the slack binary might not be in PATH
        # Check if the application directory exists
        if [ -d "/usr/lib/slack" ] || [ -d "/opt/slack" ]; then
            print_success "Slack appears to be installed in the system."
            return 0
        else
            print_error "Failed to install Slack."
            return 1
        fi
    fi
}

# install VSCodium
install_vscodium() {
    print_message "Installing VSCodium"

    case "$pkg_manager" in
        "apt")
            # import GPG key
            wget -qO - https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg | sudo apt-key add -

            # add repository
            echo 'deb https://paulcarroty.gitlab.io/vscodium-deb-rpm-repo/debs/ vscodium main' | sudo tee /etc/apt/sources.list.d/vscodium.list

            # update and install
            sudo apt update
            sudo apt install -y codium
            ;;
        "zypper")
            # Fix: Use the correct repository configuration for openSUSE
            # Import the GPG key
            sudo rpmkeys --import https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/-/raw/master/pub.gpg
            
            # Remove the old repository if it exists to avoid conflicts
            sudo zypper removerepo vscodium 2>/dev/null
            
            # Add the repository with correct URL
            sudo zypper addrepo -cfp 90 'https://paulcarroty.gitlab.io/vscodium-deb-rpm-repo/rpms/' vscodium
            
            # Refresh repos and install vscodium
            sudo zypper refresh
            sudo zypper --non-interactive install codium
            ;;
    esac

    if command -v codium &>/dev/null; then
        print_success "VSCodium installed successfully."
        return 0
    else
        print_error "Failed to install VSCodium."
        return 1
    fi
}

# install Docker (fallback method for Debian/Ubuntu)
install_docker() {
    print_message "Installing Docker from Docker's repository"

    # Debian/Ubuntu specific installation
    if [ "$pkg_manager" = "apt" ]; then
        # install dependencies
        sudo apt update
        sudo apt install -y apt-transport-https ca-certificates curl gnupg lsb-release

        # add Docker's GPG key
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

        # set up the repo - more robust to handle different distributions
        if [ -f /etc/debian_version ]; then
            # For Debian-based systems
            if [ -f /etc/os-release ]; then
                . /etc/os-release
                if [ "$ID" = "debian" ]; then
                    dist_name="debian"
                else
                    dist_name="ubuntu"
                fi
            else
                dist_name="debian"
            fi
        else
            dist_name="ubuntu" # Default fallback
        fi

        echo \
            "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/$dist_name \
          $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

        # install docker
        sudo apt update
        sudo apt install -y docker-ce docker-ce-cli containerd.io

        # install docker-compose
        sudo apt install -y docker-compose
    fi

    # add current user to docker group
    sudo usermod -aG docker $USER
    groups_modified=true

    if command -v docker &>/dev/null; then
        print_success "Docker installed successfully."
        
        # For docker-compose, check both docker-compose and docker compose (v2)
        if command -v docker-compose &>/dev/null || docker compose version &>/dev/null 2>&1; then
            print_success "docker-compose also installed successfully."
            return 0
        else
            print_error "Failed to install docker-compose."
            return 1
        fi
    else
        print_error "Failed to install Docker."
        return 1
    fi
}

# function to configure packages
configure_packages() {
    print_message "\nDo you want to configure any of the installed packages? (y/n)"
    read -r configure

    if [ "$configure" != "y" ]; then
        return
    fi

    # define configurable packages, will add more
    declare -A configurable
    configurable[1]="terminator"
    configurable[2]="vim"
    configurable[3]="git"

    # display available packages for configuration
    echo -e "\nAvailable packages to configure:"
    # again, make sure they are displayed in the right order
    for i in $(seq 1 ${#configurable[@]}); do
        echo "$i. ${configurable[$i]}"
    done

    # get user input
    echo -e "\nEnter the number of the package you want to configure:"
    read -r selection

    if [[ $selection -ge 1 && $selection -le ${#configurable[@]} ]]; then
        package=${configurable[$selection]}

        # choose editor, hint - vim!!
        editor="vim"
        if ! command -v vim &>/dev/null; then
            editor="nano"
        fi

        case "$package" in
        "terminator")
            # make sure config directory exists, sometimes it doesn't until you first run terminator
            mkdir -p ~/.config/terminator
            touch ~/.config/terminator/config
            $editor ~/.config/terminator/config
            ;;

        "vim")
            touch ~/.vimrc
            $editor ~/.vimrc
            ;;

        "git")
            print_message "Configuring git user information"
            echo "Enter your git username:"
            read -r git_user
            echo "Enter your git email:"
            read -r git_email

            git config --global user.name "$git_user"
            git config --global user.email "$git_email"

            print_message "Configure additional git settings via the config? (y/n)"
            read -r git_more

            if [ "$git_more" == "y" ]; then
                $editor ~/.gitconfig
            fi
            ;;
        esac
    fi
}

# install KVM
install_kvm() {
    print_message "Starting KVM Installation"

    # CPU check
    if grep -E --color=auto 'vmx|svm' /proc/cpuinfo &>/dev/null; then
        print_success "CPU supports hardware virtualization."
    else
        print_error "CPU does not support hardware virtualization."
        print_error "KVM requires hardware virtualization support. Installation aborted."
        return 1
    fi

    # kvm
    case "$pkg_manager" in
        "apt")
            print_message "Installing KVM and related packages"
            sudo apt update
            sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils virt-manager
            
            if [ $? -ne 0 ]; then
                print_error "Failed to install KVM packages."
                return 1
            else
                print_success "KVM packages installed successfully."
            fi
            ;;
        "zypper")
            print_message "Installing KVM and related packages"
            sudo zypper --non-interactive install patterns-openSUSE-kvm_server patterns-server-kvm_tools virt-manager libvirt-daemon qemu-kvm
            
            if [ $? -ne 0 ]; then
                print_error "Failed to install KVM packages."
                return 1
            else
                print_success "KVM packages installed successfully."
            fi
            ;;
    esac

    # Add user to libvirt group
    print_message "Adding user to libvirt group"
    sudo usermod -aG libvirt $USER
    sudo usermod -aG kvm $USER
    groups_modified=true
    
    print_success "Added $USER to libvirt and kvm groups."

    # Start and enable libvirtd
    print_message "Starting libvirt service"
    sudo systemctl enable libvirtd
    sudo systemctl start libvirtd
    
    if systemctl is-active --quiet libvirtd; then
        print_success "Libvirt service running"
    else
        print_error "Failed to start libvirt service."
    fi

    # Check for default network and create it if needed
    print_message "Checking for default virtual network"
    if sudo virsh net-list --all | grep -q default; then
        print_success "Default network already exists."
        
        # Check if it's active
        if ! sudo virsh net-list | grep -q default; then
            print_message "Starting default network"
            sudo virsh net-start default
            sudo virsh net-autostart default
        fi
    else
        print_message "Creating default virtual network"
        cat > /tmp/default-network.xml <<EOF
<network>
  <name>default</name>
  <forward mode="nat"/>
  <bridge name="virbr0" stp="on" delay="0"/>
  <ip address="192.168.122.1" netmask="255.255.255.0">
    <dhcp>
      <range start="192.168.122.2" end="192.168.122.254"/>
    </dhcp>
  </ip>
</network>
EOF
        sudo virsh net-define /tmp/default-network.xml
        sudo virsh net-start default
        sudo virsh net-autostart default
        rm /tmp/default-network.xml
        
        if sudo virsh net-list | grep -q default; then
            print_success "Default network created and started."
        else
            print_error "Failed to create default network."
        fi
    fi

    # did it install ok?
    print_message "Verifying KVM installation"
    
    if systemctl is-active --quiet libvirtd && groups $USER | grep -qE '(libvirt|kvm)'; then
        print_success "KVM installation completed successfully."
        print_message "You can now use virt-manager to create and manage VMs."
        return 0
    else
        print_warning "KVM seems to be installed but there might be issues with the setup."
        return 1
    fi
}

# display the main menu
display_menu() {
    
    display_banner

    echo -e "${blue}==== Post-Installation Menu ====${nc}"
    echo "1) Install and Configure Basic Packages"
    echo "2) Install and Configure KVM Hypervisor"
    echo "3) Work in progress"
    echo "4) also a WIP"
    echo "0) Exit"
    echo
    echo -n "Enter your choice: "
    read -r choice
    
    return $choice
}

# wait for user input before returning to menu
wait_for_key() {
    echo
    print_message "Hit any key to return to the menu.."
    read -n 1
}

# main function with brand new menu system
main() {
    print_message "Starting post-install script"

    # detect system information first to know which package manager we're using
    detect_system_info
    
    # check for sudo
    check_sudo || exit 1

    # menu loop
    while true; do
        display_menu
        choice=$?
        
        case $choice in
            1)
                # install and Configure Basic Packages
                install_packages
                wait_for_key
                ;;
            2)
                # install and Configure KVM
                install_kvm
                wait_for_key
                ;;
            3)
                print_message "placeholder for Environment Config (work in progress)"
                wait_for_key
                ;;
            4)
                print_message "placeholder for system config (work in progress)"
                wait_for_key
                ;;
            0)
                print_message "Exiting script, logs saved to $log_file"
                if [ "$groups_modified" = true ]; then
                    print_message "You've been added to new user groups, you'll need to relog."
                    if [ "$pkg_manager" = "zypper" ]; then
                        print_message "You may need to run 'newgrp wheel' or 'newgrp docker' to apply group changes."
                    else
                        print_message "You may need to run 'newgrp sudo' or 'newgrp docker' to apply group changes."
                    fi
                fi
                exit 0
                ;;
            *)
                print_error "Try again!?"
                wait_for_key
                ;;
        esac
    done
}

# RUN IT!!
main