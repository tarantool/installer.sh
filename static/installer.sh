#!/usr/bin/env bash

set -uxo pipefail

tarantool_default_version="2"
repo_type="live"
repo_path=""
repo_only=0
os=""
dist=""
gc64=""

print_usage ()
{
    cat <<EOF
Usage for installing latest Tarantool from live repo:
    $0
Usage for installing latest Tarantool from release repo:
    $0 --type release
Usage for installing Tarantool release repo only:
    $0 --type release --repo-only
Usage for installing Tarantool live repo only:
    $0 --repo-only

Options:
    -t|--type
        Repository type: (release|live) Default: live
    -r|--repo-only
        Use this flag to install repository only.
EOF
  exit 0
}

while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    -t|--type)
    repo_type="$2"
    shift
    shift
    ;;
    -r|--repo-only)
    repo_only=1
    shift
    ;;
    *)
    print_usage
    ;;
esac
done

unsupported_os ()
{
  echo "Unfortunately, your operating system is not supported by this script."
  exit 1
}

detect_os ()
{
  if [[ ( -z "${os}" ) && ( -z "${dist}" ) ]]; then
    if [ -e /etc/centos-release ]; then
      if [ -n "$(grep "RED OS" /etc/centos-release)" ]; then
        os="redos"
        dist=$(grep -Po "[6-9].[0-9]" /etc/centos-release)
      else
        os="centos"
        dist=$(grep -Po "[6-9]" /etc/centos-release | head -1)
      fi
    elif [ -e /etc/os-release ]; then
      os=$(. /etc/os-release && echo $ID)
      # fix for UBUNTU like systems
      os_like=$(. /etc/os-release && echo ${ID_LIKE:-""})
      [[ $os_like = "ubuntu" ]] && os="ubuntu"

      if [ $os = "debian" ]; then
        dist=$(echo $(. /etc/os-release && echo $VERSION) | sed 's/^[[:digit:]]\+ (\(.*\))$/\1/')
        if [ -z "$dist" ]; then
          if grep -q "bullseye"* /etc/debian_version; then
            dist="bullseye"
          fi
        fi
      elif [ $os = "devuan" ]; then
        # $ docker run -it dyne/devuan:chimaera grep VERSION= /etc/os-release
        # VERSION="4 (chimaera)"
        # $ docker run -it dyne/devuan:daedalus grep VERSION= /etc/os-release
        # VERSION="5 (daedalus/ceres)"
        dist=$(echo $(. /etc/os-release && echo $VERSION) | sed 's/^[[:digit:]]\+ (\([^/]*\)\(\/.*\)\?)$/\1/')
        if [ -z "$dist" ]; then
          if grep -q "bullseye"* /etc/debian_version; then
            dist="bullseye"
          fi
        else
          case ${dist} in
            ascii) ddist=stretch ;;
            beowulf) ddist=buster ;;
            chimaera) ddist=bullseye ;;
            daedalus) ddist=bookworm ;;
          esac
          dist=${ddist}
        fi
        os="debian"
      elif [ $os = "ubuntu" ]; then
        ver_id=$(. /etc/os-release && echo $VERSION_ID)

        # fix for UBUNTU like systems
        ver_codename=$(. /etc/os-release && echo $UBUNTU_CODENAME)
        if [ ! -z "$ver_codename" ]; then
          dist="$ver_codename"
        elif [ $ver_id = "14.04" ]; then
          dist="trusty"
        elif [ $ver_id = "16.04" ]; then
          dist="xenial"
        elif [ $ver_id = "18.04" ]; then
          dist="bionic"
        elif [ $ver_id = "18.10" ]; then
          dist="cosmic"
        elif [ $ver_id = "19.04" ]; then
          dist="disco"
        elif [ $ver_id = "19.10" ]; then
          dist="eoan"
        elif [ $ver_id = "20.04" ]; then
          dist="focal"
        elif [ $ver_id = "20.10" ]; then
          dist="groovy"
        elif [ $ver_id = "21.04" ]; then
          dist="hirsute"
        elif [ $ver_id = "21.10" ]; then
          dist="impish"
        elif [ $ver_id = "22.04" ]; then
          dist="jammy"
        else
          unsupported_os
        fi
      elif [ $os = "fedora" ]; then
        dist=$(. /etc/os-release && echo $VERSION_ID)
      elif [ $os = "amzn" ]; then
        dist=$(. /etc/os-release && echo $VERSION_ID)
        if [ $dist != "2" ]; then
          unsupported_os
        fi
      else
        unsupported_os
      fi
    else
      unsupported_os
    fi
  fi

  if [[ ( -z "${os}" ) || ( -z "${dist}" ) ]]; then
    unsupported_os
  fi

  os="${os// /}"
  dist="${dist// /}"

  echo "Detected operating system as ${os}/${dist}."
}

print_new_release_policy_and_exit ()
{
  echo "Check out our new release policy https://github.com/tarantool/tarantool/discussions/6182"
  exit 1
}

setup_type ()
{
  if [ "${repo_type}" = "release" ]; then
    if [ "${ver}" -ge "2" ] 2> /dev/null; then
      repo_path="release/series-"
    else
      repo_path="release/"
    fi
  elif [ "${repo_type}" = "pre-release" ]; then
    if [ "${ver}" -ge "2" ] 2> /dev/null; then
      repo_path="pre-release/series-"
    else
      echo "'pre-release' repository can be set up only with Tarantool series-N, where N = 2, 3, etc."
      print_new_release_policy_and_exit
    fi
  elif [ "${repo_type}" = "live" ]; then
    if [ "${ver}" -ge "2" ] 2> /dev/null; then
      echo "'live' repository cannot be set up with Tarantool series-${ver}"
      print_new_release_policy_and_exit
    fi
  else
    echo "Unknown repository type '${repo_type}'"
    print_new_release_policy_and_exit
  fi
}

setup_ver ()
{
  ARCH=$(uname -m)
  if [ "${ARCH}" = "x86_64" ] && [ "${GC64:-false}" = "true" ]; then
    echo "GC64 will be used"
    gc64="-gc64"
  fi
  if [ -z "${VER:-2}" ]; then
    ver=$tarantool_default_version
  else
    ver=${VER:-2}
  fi
  ver_repo=$(echo $ver | tr . _)
}

curl_check ()
{
  echo -n "Checking for curl... "
  if command -v curl > /dev/null; then
    echo
    echo -n "Detected curl... "
  else
    echo
    echo -n "Installing curl... "
    apt-get install -y curl
    if [ "$?" -ne "0" ]; then
      echo "Unable to install curl! Your base system has a problem; please check your default OS's package repositories because curl should work."
      echo "Repository installation aborted."
      exit 1
    fi
  fi
  echo "done."
}

apt_update ()
{
  echo -n "Running apt-get update... "
  apt-get update
  echo "done."
}

gpg_check ()
{
  echo -n "Checking for gpg... "
  if command -v gpg > /dev/null; then
    echo
    echo "Detected gpg..."
  else
    echo
    echo -n "Installing gnupg for GPG verification... "
    apt-get install -y gnupg
    if [ "$?" -ne "0" ]; then
      echo "Unable to install GPG! Your base system has a problem; please check your default OS's package repositories because GPG should work."
      echo "Repository installation aborted."
      exit 1
    fi
  fi
  echo "done."
}

install_debian_keyring ()
{
  if [ "${os}" = "debian" ]; then
    echo "Installing debian-archive-keyring which is needed for installing "
    echo "apt-transport-https on many Debian systems."
    apt-get install -y debian-archive-keyring
  fi
}

install_apt ()
{
  export DEBIAN_FRONTEND=noninteractive
  apt_update
  curl_check
  gpg_check

  echo -n "Installing apt-transport-https... "
  apt-get install -y apt-transport-https
  echo "done."

  gpg_key_url="https://download.tarantool.org/tarantool/${repo_path}${ver}/gpgkey"
  gpg_key_url_modules="https://download.tarantool.org/tarantool/modules/gpgkey"
  apt_source_path="/etc/apt/sources.list.d/tarantool_${ver_repo}.list"

  echo -n "Importing Tarantool gpg key... "
  curl -L "${gpg_key_url}" | apt-key add -
  curl -L "${gpg_key_url_modules}" | apt-key add -
  echo "done."

  rm -f /etc/apt/sources.list.d/*tarantool*.list

  # Since series-3 we use static builds and we can use one repository
  # for all deb-based and rpm-based systems.
  if [ "${ver}" -ge "3" ] 2> /dev/null; then
    dist_path="${repo_path}${ver}/linux-deb"
    dist_ver="static"
  else
    dist_path="${repo_path}${ver}${gc64}/${os}"
    dist_ver="${dist}"
  fi

  echo "deb https://download.tarantool.org/tarantool/${dist_path}/ ${dist_ver} main" > ${apt_source_path}
  echo "deb-src https://download.tarantool.org/tarantool/${dist_path}/ ${dist_ver} main" >> ${apt_source_path}
  echo "deb https://download.tarantool.org/tarantool/modules/${os}/ ${dist} main" >> ${apt_source_path}
  echo "deb-src https://download.tarantool.org/tarantool/modules/${os}/ ${dist} main" >> ${apt_source_path}
  mkdir -p /etc/apt/preferences.d/
  echo -e "Package: tarantool\nPin: origin download.tarantool.org\nPin-Priority: 1001" > /etc/apt/preferences.d/tarantool
  echo -e "\nPackage: tarantool-common\nPin: origin download.tarantool.org\nPin-Priority: 1001" >> /etc/apt/preferences.d/tarantool
  echo -e "\nPackage: tarantool-dev\nPin: origin download.tarantool.org\nPin-Priority: 1001" >> /etc/apt/preferences.d/tarantool
  echo "The repository is setup! Tarantool can now be installed."

  apt_update

  echo
  echo "Tarantool ${ver} is ready to be installed"
}

install_yum_repo ()
{
  if [[ "${os}" =~ ^(centos|amzn)$ ]]; then
    OS_NAME="EnterpriseLinux"
    OS_CODE="el"
    modules_enabled=1
  elif [ "${os}" = "fedora" ]; then
    OS_NAME="Fedora"
    OS_CODE="fedora"
    modules_enabled=1
  elif [ "${os}" = "redos" ]; then
    OS_NAME="RedOS"
    OS_CODE="redos"
    modules_enabled=0 # for now modules for RedOS are not available
  else
    print_usage
  fi

  # Since series-3 we use static builds and we can use one repository
  # for all deb-based and rpm-based systems.
  if [ "${ver}" -ge "3" ] 2> /dev/null; then
    repo_ver_path="${repo_path}${ver}"
    dist_code="linux-rpm"
    dist_ver="static"
    source_enabled="0" # for now source packages for series-3 are not available
  else
    repo_ver_path="${repo_path}${ver}${gc64}"
    dist_code="${OS_CODE}"
    dist_ver="${dist}"
    source_enabled="1"
  fi

  cat <<EOF > /etc/yum.repos.d/tarantool_${ver_repo}.repo
[tarantool_${ver_repo}]
name=${OS_NAME}-${dist} - Tarantool
baseurl=https://download.tarantool.org/tarantool/${repo_ver_path}/${dist_code}/${dist_ver}/${ARCH}/
gpgkey=https://download.tarantool.org/tarantool/${repo_ver_path}/gpgkey
repo_gpgcheck=1
gpgcheck=0
enabled=1
priority=1

[tarantool_${ver_repo}-source]
name=${OS_NAME}-${dist} - Tarantool Sources
baseurl=https://download.tarantool.org/tarantool/${repo_ver_path}/${dist_code}/${dist_ver}/SRPMS
gpgkey=https://download.tarantool.org/tarantool/${repo_ver_path}/gpgkey
repo_gpgcheck=1
gpgcheck=0
enabled=${source_enabled}
priority=1

[tarantool_modules]
name=${OS_NAME}-${dist} - Tarantool
baseurl=https://download.tarantool.org/tarantool/modules/${OS_CODE}/${dist}/${ARCH}/
gpgkey=https://download.tarantool.org/tarantool/modules/gpgkey
repo_gpgcheck=1
gpgcheck=0
enabled=${modules_enabled}
priority=1

[tarantool_modules-source]
name=${OS_NAME}-${dist} - Tarantool Sources
baseurl=https://download.tarantool.org/tarantool/modules/${OS_CODE}/${dist}/SRPMS
gpgkey=https://download.tarantool.org/tarantool/modules/gpgkey
repo_gpgcheck=1
enabled=${modules_enabled}
gpgcheck=0
EOF
}

install_yum ()
{

  echo -n "Cleaning yum cache... "
  yum clean all
  echo "done."

  if [ $os = "centos" ] || [ $os = "amzn" ]; then
    echo -n "Installing EPEL repository... "
    if [ $dist = 6 ]; then
      curl https://www.getpagespeed.com/files/centos6-eol.repo --output /etc/yum.repos.d/CentOS-Base.repo
      yum install -y epel-release
    else
      yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-${dist}.noarch.rpm
    fi
    if [ $dist != 8 ]; then
      yum -y install yum-priorities
    fi
    echo "done."

    echo -n "Setting up tarantool EPEL repo... "
    if [ -e /etc/yum.repos.d/epel.repo ]; then
      sed 's/enabled=.*/enabled=1/g' -i /etc/yum.repos.d/epel.repo
    fi
  fi

  rm -f /etc/yum.repos.d/*tarantool*.repo && \
    install_yum_repo
  echo "done."

  echo -n "Updating metadata... "
  if [ $os = "centos" ] || [ $os = "amzn" ]; then
    yum makecache -y --disablerepo='*' --enablerepo="tarantool_${ver_repo}" --enablerepo="tarantool_modules" --enablerepo='epel'
  elif [ $os = "redos" ]; then
    # RedOS doesn't support epel repo
    yum makecache -y --disablerepo='*' --enablerepo="tarantool_${ver_repo}"
  else
    unsupported_os
  fi
  echo "done."

  echo
  echo "Tarantool ${ver} is ready to be installed"
}

install_dnf ()
{
  dnf clean all

  rm -f /etc/yum.repos.d/*tarantool*.repo
  install_yum_repo

  echo -n "Updating metadata... "
  dnf -q makecache -y --disablerepo='*' --enablerepo="tarantool_${ver_repo}" --enablerepo="tarantool_modules"
  echo "done."

  echo
  echo "Tarantool ${ver} is ready to be installed"
}

main ()
{
  detect_os
  setup_ver
  setup_type

  if [ ${os} = "centos" ] && [[ ${dist} =~ ^(6|7|8)$ ]]; then
    echo "Setting up yum repository... "
    install_yum
  elif [ ${os} = "amzn" ] && [[ ${dist} = 2 ]]; then
    echo "Setting up yum repository... "
    dist=7
    install_yum
  elif [ ${os} = "redos" ] && [[ ${dist} = "7.3" ]]; then
    echo "Setting up yum repository... "
    install_yum
  elif [ ${os} = "fedora" ] && [[ ${dist} =~ ^(28|29|30|31|32|33|34|35|36|37|38)$ ]]; then
    echo "Setting up yum repository..."
    install_dnf
  elif ( [ ${os} = "debian" ] && [[ ${dist} =~ ^(jessie|stretch|buster|bullseye|bookworm)$ ]] ) ||
       ( [ ${os} = "ubuntu" ] && [[ ${dist} =~ ^(trusty|xenial|bionic|cosmic|disco|eoan|focal|groovy|hirsute|impish|jammy)$ ]] ); then
    echo "Setting up apt repository... "
    install_apt
  else
    unsupported_os
  fi
}

main
