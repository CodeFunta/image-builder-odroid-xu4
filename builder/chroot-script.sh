#!/bin/bash
set -ex

KEYSERVER="ha.pool.sks-keyservers.net"

function clean_print(){
  local fingerprint="${2}"
  local func="${1}"

  nospaces=${fingerprint//[:space:]/}
  tolowercase=${nospaces,,}
  KEYID_long=${tolowercase:(-16)}
  KEYID_short=${tolowercase:(-8)}
  if [[ "${func}" == "fpr" ]]; then
    echo "${tolowercase}"
  elif [[ "${func}" == "long" ]]; then
    echo "${KEYID_long}"
  elif [[ "${func}" == "short" ]]; then
    echo "${KEYID_short}"
  elif [[ "${func}" == "print" ]]; then
    if [[ "${fingerprint}" != "${nospaces}" ]]; then
      printf "%-10s %50s\n" fpr: "${fingerprint}"
    fi
    # if [[ "${nospaces}" != "${tolowercase}" ]]; then
    #   printf "%-10s %50s\n" nospaces: $nospaces
    # fi
    if [[ "${tolowercase}" != "${KEYID_long}" ]]; then
      printf "%-10s %50s\n" lower: "${tolowercase}"
    fi
    printf "%-10s %50s\n" long: "${KEYID_long}"
    printf "%-10s %50s\n" short: "${KEYID_short}"
    echo ""
  else
    echo "usage: function {print|fpr|long|short} GPGKEY"
  fi
}


function get_gpg(){
  GPG_KEY="${1}"
  KEY_URL="${2}"

  clean_print print "${GPG_KEY}"
  GPG_KEY=$(clean_print fpr "${GPG_KEY}")

  if [[ "${KEY_URL}" =~ ^https?://* ]]; then
    echo "loading key from url"
    KEY_FILE=temp.gpg.key
    wget -q -O "${KEY_FILE}" "${KEY_URL}"
  elif [[ -z "${KEY_URL}" ]]; then
    echo "no source given try to load from key server"
#    gpg --keyserver "${KEYSERVER}" --recv-keys "${GPG_KEY}"
    apt-key adv --keyserver "${KEYSERVER}" --recv-keys "${GPG_KEY}"
    return $?
  else
    echo "keyfile given"
    KEY_FILE="${KEY_URL}"
  fi

  FINGERPRINT_OF_FILE=$(gpg --with-fingerprint --with-colons "${KEY_FILE}" | grep fpr | rev |cut -d: -f2 | rev)

  if [[ ${#GPG_KEY} -eq 16 ]]; then
    echo "compare long keyid"
    CHECK=$(clean_print long "${FINGERPRINT_OF_FILE}")
  elif [[ ${#GPG_KEY} -eq 8 ]]; then
    echo "compare short keyid"
    CHECK=$(clean_print short "${FINGERPRINT_OF_FILE}")
  else
    echo "compare fingerprint"
    CHECK=$(clean_print fpr "${FINGERPRINT_OF_FILE}")
  fi

  if [[ "${GPG_KEY}" == "${CHECK}" ]]; then
    echo "key OK add to apt"
    apt-key add "${KEY_FILE}"
    rm -f "${KEY_FILE}"
    return 0
  else
    echo "key invalid"
    exit 1
  fi
}

## examples:
# clean_print {print|fpr|long|short} {GPGKEYID|FINGERPRINT}
# get_gpg {GPGKEYID|FINGERPRINT} [URL|FILE]

# device specific settings
HYPRIOT_DEVICE="ODROID XU3/XU4"

# set up /etc/resolv.conf
DEST=$(readlink -m /etc/resolv.conf)
export DEST
mkdir -p "$(dirname "${DEST}")"
echo "nameserver 8.8.8.8" > "${DEST}"





# set up hypriot rpi repository for rpi specific kernel- and firmware-packages
PACKAGECLOUD_FPR=418A7F2FB0E1E6E7EABF6FE8C2E73424D59097AB
PACKAGECLOUD_KEY_URL=https://packagecloud.io/gpg.key
get_gpg "${PACKAGECLOUD_FPR}" "${PACKAGECLOUD_KEY_URL}"


# set up hypriot schatzkiste repository for generic packages
echo 'deb https://packagecloud.io/Hypriot/Schatzkiste/debian/ jessie main' >> /etc/apt/sources.list.d/hypriot.list

# update all apt repository lists
export DEBIAN_FRONTEND=noninteractive


# set up Docker CE repository
# # DOCKERREPO_FPR=9DC858229FC7DD38854AE2D88D81803C0EBFCD88
# # DOCKERREPO_KEY_URL=https://download.docker.com/linux/debian/gpg
# # get_gpg "${DOCKERREPO_FPR}" "${DOCKERREPO_KEY_URL}"

# # CHANNEL=edge # stable, test or edge
# # echo "deb [arch=armhf] https://download.docker.com/linux/debian jessie $CHANNEL" > /etc/apt/sources.list.d/docker.list

# reload package sources
apt-get update
apt-get upgrade -y

# install ODROID kernel
#apt-get install -y uboot u-boot-tools initramfs-tools
#touch /boot/uImage
apt-get install -y \
    --no-install-recommends \
    dirmngr \
    u-boot \
    u-boot-tools \
    initramfs-tools #\
    #libssl1.0.0
    #build-essential \
    #bc


mkdir -p /media/boot

# set up ODROID repository
#apt-key adv --keyserver keyserver.ubuntu.com --recv-keys AB19BAC9
apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 2DD567ECD986B59D
echo "deb [arch=armhf] http://deb.odroid.in/5422-s/ xenial main" > /etc/apt/sources.list.d/odroid.list


apt-get update 
apt-get upgrade -y
apt-get dist-upgrade

apt-get install linux-image-xu3 -y #=120-1



#ensure compatibility with Docker install.sh, so `raspbian` will be detected correctly
apt-get install -y \
  --no-install-recommends \
  lsb-release

# install cloud-init
apt-get install -y \
  cloud-init

mkdir -p /var/lib/cloud/seed/nocloud-net
ln -s /boot/user-data /var/lib/cloud/seed/nocloud-net/user-data
ln -s /boot/meta-data /var/lib/cloud/seed/nocloud-net/meta-data


# # install docker-machine
# curl -sSL -o /usr/local/bin/docker-machine "https://github.com/docker/machine/releases/download/v${DOCKER_MACHINE_VERSION}/docker-machine-Linux-armhf"
# chmod +x /usr/local/bin/docker-machine

# # install bash completion for Docker Machine
# curl -sSL "https://raw.githubusercontent.com/docker/machine/v${DOCKER_MACHINE_VERSION}/contrib/completion/bash/docker-machine.bash" -o /etc/bash_completion.d/docker-machine

# # install docker-compose
# apt-get install -y \
#   --no-install-recommends \
#   python-pip
# pip install wheel
# pip install -U pip setuptools 
# pip install "docker-compose==${DOCKER_COMPOSE_VERSION}"

# # install bash completion for Docker Compose
# curl -sSL "https://raw.githubusercontent.com/docker/compose/${DOCKER_COMPOSE_VERSION}/contrib/completion/bash/docker-compose" -o /etc/bash_completion.d/docker-compose

# # install docker-ce (w/ install-recommends)
# apt-get install -y --force-yes \
#   "docker-ce=${DOCKER_CE_VERSION}"

PASS=hypriot
useradd -p $(openssl passwd -1 $PASS) pirate -m -s /bin/bash
chown -R pirate:pirate /home/pirate
usermod -a -G sudo pirate

# cleanup APT cache and lists
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# set device label and version number
echo "HYPRIOT_DEVICE=\"$HYPRIOT_DEVICE\"" >> /etc/os-release
echo "HYPRIOT_IMAGE_VERSION=\"$HYPRIOT_IMAGE_VERSION\"" >> /etc/os-release
cp /etc/os-release /boot/os-release


