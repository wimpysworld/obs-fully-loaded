#!/usr/bin/env bash
LC_ALL=C

function fancy_message() {
    if [ -z "${1}" ] || [ -z "${2}" ]; then
      return
    fi

    local RED="\e[31m"
    local GREEN="\e[32m"
    local YELLOW="\e[33m"
    local RESET="\e[0m"
    local MESSAGE_TYPE=""
    local MESSAGE=""
    MESSAGE_TYPE="${1}"
    MESSAGE="${2}"

    case ${MESSAGE_TYPE} in
      info) echo -e "  [${GREEN}+${RESET}] ${MESSAGE}";;
      warn) echo -e "  [${YELLOW}*${RESET}] WARNING! ${MESSAGE}";;
      error) echo -e "  [${RED}!${RESET}] ERROR! ${MESSAGE}"
             exit 1;;
      *) echo -e "  [?] UNKNOWN: ${MESSAGE}";;
    esac
}

function web_get() {
    local FILE="${2}"
    local URL="${1}"
    if ! wget --quiet --continue "${URL}" -O "${CACHE_DIR}/${FILE}"; then
        fancy_message error "Failed to download ${URL}."
    fi
}

function apt_download() {
    local PACKAGE="${1}"
    local DEB=""
    fancy_message info "Downloading: ${PACKAGE} (apt)"
    cd "${CACHE_DIR}"
    apt-get -q=2 -y download "${PACKAGE}" >/dev/null 2>&1
    cd - >/dev/null 2>&1
    DEB=$(ls -1t "${CACHE_DIR}/${PACKAGE}"*.deb | grep -v fullyloaded | head -n1)
    apt_install "${DEB}"
}

function apt_install() {
    fancy_message info "Installing: ${1} (apt)"
    apt-get -q=2 -y install "${1}" >/dev/null 2>&1
}

function install_deb() {
    local URL="${1}"
    local FILE="${URL##*/}"
    fancy_message info "Installing: ${FILE} (deb)"
    web_get "${URL}" "${FILE}"
    apt-get -q=2 -y install "${CACHE_DIR}/${FILE}" >/dev/null 2>&1
}

# https://github.com/wimpysworld/deb-get/issues/126
## BEGIN package_is_installed {
# Summary  : package_is_installed <package-name>;
# Purpose  : Quickly check if a package is installed
# Example  : package_is_installed kfocus-nvidia;
# Returns  : 0 = package installed; 1 = not installed
# Throws   : none
#
package_is_installed() {
  declare _pkg_name _status_str;
  _pkg_name="${1:-}";
  _status_str="$( 2>&1 \
    dpkg-query -f '${db:Status-abbrev}' -W "${_pkg_name}"
  )";
  if grep -qE '^.i ' <<< "${_status_str}"; then
    return 0;
  fi
  return 1;
}
## . END package_is_installed }

function remove_deb() {
    local APP="${1}"
    local REMOVE="${2:-remove}"
    local STATUS=""

    if package_is_installed "${APP}"; then
        fancy_message info "Removing: ${APP} (deb)"
        STATUS="$(dpkg -s "${APP}" | grep ^Status: | cut -d" " -f2-)"
        if [ "${STATUS}" == "deinstall ok config-files" ]; then
            REMOVE="purge"
        fi
        apt-get -q=2 -y --autoremove ${REMOVE} "${APP}" >/dev/null 2>&1
    fi
}

function symlink_deb() {
    local PLUGIN=${1}
    mkdir -p "${PLUGIN_DIR}/${PLUGIN}/bin/64bit"
    ln -s "/usr/lib/obs-plugins/${PLUGIN}.so" "${PLUGIN_DIR}/${PLUGIN}/bin/64bit/${PLUGIN}.so"
}

function install_exeldro_plugin() {
    local URL="${1}"
    local FILE=""
    if [ -n "${2}" ]; then
        FILE="${2}"
    else
        FILE="${URL##*/}"
    fi
    fancy_message info "Installing: ${FILE//.zip/} (plugin)"
    web_get "${URL}" "${FILE}"
    unzip -p -qq "${CACHE_DIR}/${FILE}" | tar zxf - -C "${PLUGIN_DIR}"
}

function install_tarball_plugin() {
    local URL="${1}"
    local FILE=""
    if [ -n "${2}" ]; then
        FILE="${2}"
    else
        FILE="${URL##*/}"
    fi
    fancy_message info "Installing: ${FILE} (plugin)"
    web_get "${URL}" "${FILE}"
    tar xf "${CACHE_DIR}/${FILE}" -C "${PLUGIN_DIR}"
    if [[ "${FILE}" == *"text-pango-linux"* ]]; then
        apt_install "libpango-1.0-0 libpangocairo-1.0-0 libpangoft2-1.0-0"
    fi
}

function install_7zip_plugin() {
    local URL="${1}"
    local FILE=""
    if [ -n "${2}" ]; then
        FILE="${2}"
    else
        FILE="${URL##*/}"
    fi
    fancy_message info "Installing: ${FILE} (plugin)"
    web_get "${URL}" "${FILE}"

    if [[ "${FILE}" == *"streamfx"* ]]; then
        7z x -y -o"${OBS_CONFIG}" "${CACHE_DIR}/${FILE}" > /dev/null 2>&1
    else
        7z x -y -o"${PLUGIN_DIR}" "${CACHE_DIR}/${FILE}" > /dev/null 2>&1
    fi
}

function install_zip_plugin() {
    local URL="${1}"
    local FILE=""
    if [ -n "${2}" ]; then
        FILE="${2}"
    else
        FILE="${URL##*/}"
    fi
    fancy_message info "Installing: ${FILE} (plugin)"
    web_get "${URL}" "${FILE}"

    # Are we extracting a specific folder from the zip?
    if [ -n "${3}" ]; then
        unzip -o -qq "${CACHE_DIR}/${FILE}" "${3}" -d "${PLUGIN_DIR}"
    else
        unzip -o -qq "${CACHE_DIR}/${FILE}" -d "${PLUGIN_DIR}"
    fi

    if [[ "${FILE}" == *"obs-gstreamer"* ]]; then
        mkdir -p "${PLUGIN_DIR}/obs-gstreamer/bin/64bit"
        mv "${PLUGIN_DIR}/linux/obs-gstreamer.so" "${PLUGIN_DIR}/obs-gstreamer/bin/64bit/"
        rm -rf "${PLUGIN_DIR}/linux"
        for PKG in gstreamer1.0-plugins-good libgstreamer-plugins-base1.0-0; do
            apt_install "${PKG}"
        done
    elif [[ "${FILE}" == *"obs-nvfbc"* ]]; then
        mkdir -p "${PLUGIN_DIR}/nvfbc/bin/64bit"
        mv "${PLUGIN_DIR}/build/nvfbc.so" "${PLUGIN_DIR}/nvfbc/bin/64bit/"
        rm -rf "${PLUGIN_DIR}/build"
    elif [[ "${FILE}" == *"rgb-levels"* ]]; then
        mkdir -p "${PLUGIN_DIR}/obs-rgb-levels-filter/bin/64bit"
        mkdir -p "${PLUGIN_DIR}/obs-rgb-levels-filter/data"
        mv "${PLUGIN_DIR}/usr/lib/obs-plugins/obs-rgb-levels-filter.so" "${PLUGIN_DIR}/obs-rgb-levels-filter/bin/64bit/"
        mv "${PLUGIN_DIR}/usr/share/obs/obs-plugins/obs-rgb-levels-filter/rgb_levels.effect" "${PLUGIN_DIR}/obs-rgb-levels-filter/data/"
        rm -rf "${PLUGIN_DIR:?}/usr"
    elif [[ "${FILE}" == *"obs-teleport"* ]]; then
        mkdir -p "${PLUGIN_DIR}/obs-teleport/bin/64bit"
        mv "${PLUGIN_DIR}/linux-x86_64/obs-teleport.so" "${PLUGIN_DIR}/obs-teleport/bin/64bit/"
        rm -rf "${PLUGIN_DIR}/linux-x86_64"
    elif [[ "${FILE}" == *"spectralizer"* ]]; then
        apt_install libfftw3-3
    elif [[ "${FILE}" == *"SceneSwitcher-linux-x86_64"* ]]; then
        #echo "Unzipping payload"
        #unzip -o -qq "${PLUGIN_DIR}/advanced-scene-switcher-linux-x86_64.zip" -d "${PLUGIN_DIR}/advanced-scene-switcher"
        #rm "${PLUGIN_DIR}/advanced-scene-switcher-linux-x86_64.zip"

        mkdir -p "${PLUGIN_DIR}/advanced-scene-switcher/data/"
        mv "${PLUGIN_DIR}/data/obs-plugins/advanced-scene-switcher/locale" "${PLUGIN_DIR}/advanced-scene-switcher/data/"
        mv "${PLUGIN_DIR}/data/obs-plugins/advanced-scene-switcher/res" "${PLUGIN_DIR}/advanced-scene-switcher/data/"
        mkdir -p "${PLUGIN_DIR}/advanced-scene-switcher/bin/"
        mv "${PLUGIN_DIR}/obs-plugins/64bit" "${PLUGIN_DIR}/advanced-scene-switcher/bin/"
        # Patch advanced-scene-switcher.so so it can find advanced-scene-switcher-lib.so
        patchelf --replace-needed advanced-scene-switcher-lib.so "${PLUGIN_DIR}/advanced-scene-switcher/bin/64bit/advanced-scene-switcher-lib.so" "${PLUGIN_DIR}/advanced-scene-switcher/bin/64bit/advanced-scene-switcher.so"

        rm -rf "${PLUGIN_DIR}/data/"
        rm -rf "${PLUGIN_DIR}/obs-plugins"
        for PKG in libxss1 libxtst6 libcurl4; do
            apt_install "${PKG}"
        done

        case "${UBUNTU_CODENAME}" in
            jammy)
                for CV_LIB in core imgproc objdetect; do
                    apt_install "libopencv-${CV_LIB}4.5d"
                done
                ;;
        esac
    elif [[ "${FILE}" == *"SceneSwitcher"* ]]; then
        rm -rf "${PLUGIN_DIR}/advanced-scene-switcher"
        mv "${PLUGIN_DIR}/SceneSwitcher/Linux/advanced-scene-switcher" "${PLUGIN_DIR}/advanced-scene-switcher"
        rm -rf "${PLUGIN_DIR}/SceneSwitcher"
        for PKG in libxss1 libxtst6 libcurl4; do
            apt_install "${PKG}"
        done
        #libopencv-imgproc4.5 libopencv-objdetect4.5
    elif [[ "${FILE}" == *"LiveVisionKit"* ]]; then
        mv "${PLUGIN_DIR}/obs-studio/plugins/LiveVisionKit" "${PLUGIN_DIR}/LiveVisionKit"
        rm -rf "${PLUGIN_DIR}/obs-studio"

        case "${UBUNTU_CODENAME}" in
            kinetic)
                for CV_LIB in imgproc calib3d features2d core video; do
                    apt_install "libopencv-${CV_LIB}406"
                done
                ;;
        esac
    fi
}

function install_theme() {
    local URL="${1}"
    local FILE=""
    if [ -n "${2}" ]; then
        FILE="${2}"
    else
        FILE="${URL##*/}"
    fi
    fancy_message info "Installing: ${FILE} (theme)"
    web_get "${URL}" "${FILE}"
    unzip -o -qq "${CACHE_DIR}/${FILE}" -d "${THEME_DIR}"

    if [[ "${FILE}" == *"cgc_theme"* ]]; then
        mv "${THEME_DIR}/cgc_theme_obs/obs_theme/"* "${THEME_DIR}/"
        rm -rf "${THEME_DIR}/cgc_theme_obs"
    elif [[ "${FILE}" == *"Twitchy"* ]]; then
        mv "${THEME_DIR}/Twitchy (without font)/"* "${THEME_DIR}/"
        rm -rf "${THEME_DIR}/Twitchy (with"*
        rm "${THEME_DIR}/README.md"
    elif [[ "${FILE}" == *"YouTubey"* ]]; then
        mv "${THEME_DIR}/YouTubey (without font)/"* "${THEME_DIR}/"
        rm -rf "${THEME_DIR}/YouTubey (with"*
        rm "${THEME_DIR}/README.md"
    fi
}

echo "Open Broadcaster Software - Installer for Ubuntu & derivatives"

if [ "$(id -u)" -ne 0 ]; then
  fancy_message error "You must use sudo to run this script."
else
  fancy_message info "Running as root."
fi

if [ -z "${SUDO_USER}" ]; then
  fancy_message error "You must use sudo to run this script"
else
  fancy_message info "Called via sudo."
  SUDO_HOME=$(getent passwd "${SUDO_USER}" | cut -d: -f6)
fi

if command -v lsb_release 1>/dev/null; then
  fancy_message info "Detected lsb_release."
else
  fancy_message error "lsb_release not detected. Quitting."
fi

OS_ID=$(lsb_release --id --short)
case "${OS_ID}" in
  Elementary) fancy_message info "elementary OS detected.";;
  Linuxmint) fancy_message info "Linux Mint detected.";;
  Neon) fancy_message info "KDE Neon detected.";;
  Pop) fancy_message info "Pop!_OS detected.";;
  Ubuntu) fancy_message info "Ubuntu detected.";;
  Zorin) fancy_message info "Zorin OS detected.";;
  *) fancy_message error "${OS_ID} is not supported.";;
esac

OS_CODENAME=$(lsb_release --codename --short)
if [ -e /etc/os-release ]; then
    UBUNTU_CODENAME=$(grep UBUNTU_CODENAME /etc/os-release | cut -d'=' -f2)
else
    fancy_message error "/etc/os-release not found."
fi

if pidof -q obs; then
    fancy_message error "OBS Studio is currently running."
fi

CACHE_DIR="${SUDO_HOME}/.cache/obs-install"
OBS_CONFIG="${SUDO_HOME}/.config/obs-studio"
PLUGIN_DIR="${OBS_CONFIG}/plugins"
THEME_DIR="${OBS_CONFIG}/themes"
UBUNTU_VER=""
QT_VER=""

case "${UBUNTU_CODENAME}" in
    focal)
        QT_VER="5"
        UBUNTU_VER="20"
        ;;
    jammy|kinetic)
        QT_VER="6"
        UBUNTU_VER="22"
        ;;
    *) fancy_message error "${OS_ID_PRETTY} ${OS_CODENAME^} is not supported.";;
esac

fancy_message info "Updating apt."
add-apt-repository -y --no-update ppa:obsproject/obs-studio >/dev/null 2>&1
apt-get -q=2 -y update
apt-get -q=2 -y install patchelf 7zip unzip

rm -rf "${PLUGIN_DIR}"
rm -rf "${THEME_DIR}"
mkdir -p "${CACHE_DIR}"
mkdir -p "${PLUGIN_DIR}"
mkdir -p "${THEME_DIR}"

# Cache a copy of the OBS Studio .debs before installing them.
apt_download "obs-studio"

# Remove any common .debs that are no longer supported by OBS Fully Loaded.
remove_deb obs-pulseaudio-app-capture

# Plugins that work with Qt 5 or Qt 6

## Installs .deb plugins to /usr/lib/obs-plugins

install_deb "https://github.com/norihiro/obs-audio-pan-filter/releases/download/0.2.2/obs-audio-pan-filter-0.2.2-obs27-ubuntu-20.04-x86_64.deb"
symlink_deb "obs-audio-pan-filter"

install_deb "https://github.com/norihiro/obs-command-source/releases/download/0.3.0/obs-command-source-0.3.0-obs27-ubuntu-20.04-x86_64.deb"
symlink_deb "obs-command-source"

install_deb "https://github.com/norihiro/obs-mute-filter/releases/download/0.2.1/obs-mute-filter-0.2.1-obs27-ubuntu-20.04-x86_64.deb"
symlink_deb "obs-mute-filter"

install_deb "https://github.com/norihiro/obs-face-tracker/releases/download/0.6.4/obs-face-tracker-0.6.4-obs28-ubuntu-${UBUNTU_VER}.04-x86_64.deb"
install_deb "https://github.com/norihiro/obs-multisource-effect/releases/download/0.2.1/obs-multisource-effect-0.2.1-obs28-ubuntu-20.04-x86_64.deb"
install_deb "https://github.com/norihiro/obs-text-pthread/releases/download/2.0.2/obs-text-pthread-2.0.2-obs28-ubuntu-20.04-x86_64.deb"
install_deb "https://github.com/phandasm/waveform/releases/download/v1.5.0/Waveform_v1.5.0_Ubuntu_x86_64.deb"

## Install Exeldro's plugins to ~/.config/obs-studio/plugins
install_exeldro_plugin "https://obsproject.com/forum/resources/directory-watch-media.801/version/4096/download?file=81705" "dir-watch-media-0.6.0-linux64.tar.gz.zip"
install_exeldro_plugin "https://obsproject.com/forum/resources/dynamic-delay.1035/version/4069/download?file=80953" "dynamic-delay-0.1.3-linux64.tar.gz.zip"
install_exeldro_plugin "https://obsproject.com/forum/resources/freeze-filter.950/version/3026/download?file=65909" "freeze-filter-0.3.2-linux64.tar.gz.zip"
install_exeldro_plugin "https://obsproject.com/forum/resources/gradient-source.1172/version/3926/download?file=78596" "gradient-source-0.3.0-linux64.tar.gz.zip"
install_exeldro_plugin "https://obsproject.com/forum/resources/move-transition.913/version/4297/download?file=84808" "move-transition-2.6.1-linux64.tar.gz.zip"
install_exeldro_plugin "https://obsproject.com/forum/resources/recursion-effect.1008/version/3928/download?file=78616" "recursion-effect-0.0.4-linux64.tar.gz.zip"
install_exeldro_plugin "https://obsproject.com/forum/resources/source-record.1285/version/4081/download?file=81309" "source-record-0.3.0-linux64.tar.gz.zip"
install_exeldro_plugin "https://obsproject.com/forum/resources/source-switcher.941/version/4046/download?file=80410" "source-switcher-0.4.0-linux64.tar.gz.zip"
install_exeldro_plugin "https://obsproject.com/forum/resources/time-warp-scan.1167/version/3475/download?file=72760" "time-warp-scan-0.1.6-linux64.tar.gz.zip"
install_exeldro_plugin "https://obsproject.com/forum/resources/virtual-cam-filter.1142/version/4031/download?file=80127" "virtual-cam-filter-0.0.5-linux64.tar.gz.zip"
install_exeldro_plugin "https://nightly.link/exeldro/obs-downstream-keyer/actions/runs/2957744843/downstream-keyer-2022-08-30-e7bcbe2ef16dfa997662935de32015873a86b47e-ubuntu-${UBUNTU_VER}.04.tar.gz.zip"
install_exeldro_plugin "https://nightly.link/exeldro/obs-media-controls/actions/runs/2957756881/media-controls-2022-08-30-b37f7ab24dcf40701e1f538c14f608a5a0db868b-ubuntu-${UBUNTU_VER}.04.tar.gz.zip"
install_exeldro_plugin "https://nightly.link/exeldro/obs-replay-source/actions/runs/3054879761/replay-source-2022-09-14-5c3866fcd3ae3834c75715e52239d531d445fd65-ubuntu-${UBUNTU_VER}.04.tar.gz.zip"
install_exeldro_plugin "https://nightly.link/exeldro/obs-scene-collection-manager/actions/runs/2957768377/scene-collection-manager-2022-08-30-95001a892b3d2fe137be0e2091e687cbe5491b59-ubuntu-${UBUNTU_VER}.04.tar.gz.zip"
install_exeldro_plugin "https://nightly.link/exeldro/obs-scene-notes-dock/actions/runs/2957781272/scene-notes-dock-2022-08-30-f63f31bc1fad6012950e679a2808bdc8b2b6d706-ubuntu-${UBUNTU_VER}.04.tar.gz.zip"
install_exeldro_plugin "https://nightly.link/exeldro/obs-source-dock/actions/runs/2957914011/source-dock-2022-08-30-7b31f0e6c4a5737b832953e127134c3708168548-ubuntu-${UBUNTU_VER}.04.tar.gz.zip"
install_exeldro_plugin "https://nightly.link/exeldro/obs-source-copy/actions/runs/2957791532/source-copy-2022-08-30-c88b3c997439247749a5bffc70a69eee8929742a-ubuntu-${UBUNTU_VER}.04.tar.gz.zip"
install_exeldro_plugin "https://nightly.link/exeldro/obs-transition-table/actions/runs/2938509069/transition-table-2022-08-27-f8a28150e54d4494a8a12cb2e2726433e095be24-ubuntu-${UBUNTU_VER}.04.tar.gz.zip"

install_7zip_plugin "https://github.com/Xaymar/obs-StreamFX/releases/download/0.12.0a134/streamfx-ubuntu-${UBUNTU_VER}-0.12.0a134-g6853cc6a.7z"

## Install Zipped plugins to ~/.config/obs-studio/plugins
install_zip_plugin "https://github.com/univrsal/dvds3/releases/download/v1.1/dvd-screensaver.v1.1.linux.x64.zip"
install_zip_plugin "https://github.com/fzwoch/obs-gstreamer/releases/download/v0.3.5/obs-gstreamer.zip" "obs-gstreamer-v0.3.5.zip" "linux/*"
install_zip_plugin "https://github.com/fzwoch/obs-teleport/releases/download/0.5.0/obs-teleport.zip" "obs-teleport-0.5.0.zip" "linux-x86_64/*"
install_zip_plugin "https://obsproject.com/forum/resources/rgb-levels.967/download" "rgb-levels-linux.zip"
install_zip_plugin "https://github.com/univrsal/spectralizer/releases/download/v1.3.4/spectralizer.v1.3.4.bin.linux.x64.zip"
# Requires GLX which was removed from OBS Studio 28
#  - https://gitlab.com/fzwoch/obs-nvfbc/-/issues/6
#install_zip_plugin "https://obsproject.com/forum/resources/obs-nvfbc.796/download" "obs-nvfbc-0.0.7.zip"

# Install Tarball plugins to ~/.config/obs-studio/plugins
install_tarball_plugin "https://github.com/dimtpap/obs-pipewire-audio-capture/releases/download/1.0.5/linux-pipewire-audio-1.0.5.tar.gz"
install_tarball_plugin "https://github.com/dimtpap/obs-scale-to-sound/releases/download/1.2.2/obs-scale-to-sound-1.2.2-linux64.tar.gz"
install_tarball_plugin "https://github.com/kkartaltepe/obs-text-pango/releases/download/v1.0/text-pango-linux.tar.gz"

# LiveVisionKit requires specific versions of OpenCL
 case "${UBUNTU_CODENAME}" in
    kinetic)    install_zip_plugin "https://github.com/Crowsinc/LiveVisionKit/releases/download/v1.2.0/LiveVisionKit-1.2.0-Linux.zip";;
esac

case "${QT_VER}" in
    5)
        install_deb "https://github.com/norihiro/obs-vnc/releases/download/0.4.0/obs-vnc_1-0.4.0-1_amd64.deb"
        install_deb "https://github.com/Palakis/obs-ndi/releases/download/4.9.1/libndi4_4.5.1-1_amd64.deb"
        install_deb "https://github.com/Palakis/obs-ndi/releases/download/4.9.1/obs-ndi_4.9.1-1_amd64.deb"
        install_deb "https://github.com/iamscottxu/obs-rtspserver/releases/download/v2.2.1/obs-rtspserver-v2.2.1-linux.deb"
        install_deb "https://github.com/cg2121/obs-soundboard/releases/download/1.0.3/obs-soundboard_1.0.3-1_amd64.deb"
        install_deb "https://github.com/obsproject/obs-websocket/releases/download/5.0.1/obs-websocket-4.9.1-compat-Ubuntu64.deb"
        install_zip_plugin "https://github.com/WarmUpTill/SceneSwitcher/releases/download/1.17.7/SceneSwitcher.zip" "SceneSwitcher-1.17.7.zip" "SceneSwitcher/Linux/advanced-scene-switcher/*"
        ;;
    6)
        remove_deb "obs-vnc"
        remove_deb "libndi4"
        remove_deb "obs-ndi"
        remove_deb "obs-rtspserver"
        install_deb "https://github.com/cg2121/obs-soundboard/releases/download/1.1.1/obs-soundboard-1.1.0-linux-x86_64.deb"
        remove_deb "obs-websocket"
        install_deb "https://github.com/obsproject/obs-websocket/releases/download/4.9.1-compat/obs-websocket-4.9.1-compat-Qt6-Ubuntu64.deb"
        # Work around https://github.com/obsproject/obs-websocket/issues/995
        if [ -e /usr/obs-plugins/64bit/obs-websocket-compat.so ]; then
          mkdir -p "${PLUGIN_DIR}/obs-websocket-compat/bin"
          ln -s /usr/obs-plugins/64bit "${PLUGIN_DIR}/obs-websocket-compat/bin/"
          mkdir -p "${PLUGIN_DIR}/obs-websocket-compat/data"
          ln -s /usr/data/obs-plugins/obs-websocket-compat/locale "${PLUGIN_DIR}/obs-websocket-compat/data/"
        fi
        install_zip_plugin "https://github.com/WarmUpTill/SceneSwitcher/releases/download/1.18.0/advanced-scene-switcher-1.0.0-linux-x86_64.zip" "SceneSwitcher-linux-x86_64-1.18.0.zip"
        ;;
    *) fancy_message error "Qt version not set.";;
esac

# Install Zipped theme to ~/.config/obs-studio/themes
install_theme "https://github.com/cssmfc/camgirl-obs/releases/download/1.1.OBS.CGC/cgc_theme_obs.zip"
install_theme "https://github.com/WyzzyMoon/Moonlight/releases/download/v1.0/moonlight.zip"
install_theme "https://github.com/Xaymar/obs-oceanblue/releases/download/0.1/OceanBlue-0.1.zip"
install_theme "https://obsproject.com/forum/resources/twitchy.813/download" "Twitchy.zip"
install_theme "https://obsproject.com/forum/resources/youtubey-wip.817/download" "YouTubey.zip"

# Correct permissions and ownership
find "${OBS_CONFIG}" -type d -exec chmod 755 {} \;
find "${OBS_CONFIG}" -type f -exec chmod 644 {} \;
chown -R "${SUDO_USER}":"${SUDO_USER}" "${OBS_CONFIG}"
chown -R "${SUDO_USER}":"${SUDO_USER}" "${CACHE_DIR}"
