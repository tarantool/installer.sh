#!/bin/bash

set -o pipefail

if [ $EUID != 0 ]; then
    sudo "$0" "$@"
    exit $?
fi

repo_type="{{ rtype }}"
repo_path=""

if [ "${repo_type}" = "release" ]; then
  repo_path="release/"
elif [ "${repo_type}" != "live" ]; then
  echo "Error during installing repository"
  exit 1
fi

unsupported_os ()
{
  echo "Unfortunately, your operating system is not supported by this script."
  exit 1
}

detect_os ()
{
  if [[ ( -z "${os}" ) && ( -z "${dist}" ) ]]; then
    if [ -e /etc/centos-release ]; then
      os="centos"
      dist=$(grep -Po "[6-9]" /etc/centos-release | head -1)
    elif [ -e /etc/os-release ]; then
      os=$(. /etc/os-release && echo $ID)
      # fix for UBUNTU like systems
      os_like=$(. /etc/os-release && echo $ID_LIKE)
      [[ $os_like = "ubuntu" ]] && os="ubuntu"

      if [ $os = "debian" ]; then
        dist=$(echo $(. /etc/os-release && echo $VERSION) | sed 's/^[[:digit:]]\+ (\(.*\))$/\1/')
        if [ -z "$dist" ]; then
          if grep -q "bullseye"* /etc/debian_version; then
            dist="bullseye"
          fi
        fi
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

detect_ver ()
{
  ver="{{ tarantool_version }}"
  ver_repo=$(echo $ver | tr . _)
}

curl_check ()
{
  echo
  echo "####################"
  echo "# Checking curl... #"
  echo "####################"
  if command -v curl > /dev/null; then
    echo "Detected curl... "
  else
    echo "Installing curl..."
    ${packet_manager} install -q -y curl
    if [ "$?" -ne "0" ]; then
      echo "Unable to install curl! Your base system has a problem; please check your default OS's package repositories because curl should work."
      echo "Repository installation aborted."
      exit 1
    fi
  fi
}

apt_update ()
{
  echo
  echo "#############################"
  echo "# Running apt-get update... #"
  echo "#############################"
  apt-get update
}

gpg_check ()
{
  echo
  echo "#######################"
  echo "# Checking for gpg... #"
  echo "#######################"
  if command -v gpg > /dev/null; then
    echo "Detected gpg..."
  else
    echo "Installing gnupg for GPG verification..."
    apt-get install -y gnupg
    if [ "$?" -ne "0" ]; then
      echo "Unable to install GPG! Your base system has a problem; please check your default OS's package repositories because GPG should work."
      echo "Repository installation aborted."
      exit 1
    fi
  fi
}

install_debian_keyring ()
{
  if [ "${os}" = "debian" ]; then
    echo
    echo "####################################################################"
    echo "# Installing debian-archive-keyring which is needed for installing #"
    echo "# apt-transport-https on many Debian systems.                      #"
    echo "####################################################################"
    apt-get install -y debian-archive-keyring
  fi
}

install_apt ()
{
  export DEBIAN_FRONTEND=noninteractive
  packet_manager="apt-get"
  apt_update
  curl_check
  gpg_check

  echo
  echo "#####################################"
  echo "# Installing apt-transport-https... #"
  echo "#####################################"
  apt-get install -y apt-transport-https

  gpg_key_url="https://download.tarantool.org/tarantool/${repo_path}${ver}/gpgkey"
  gpg_key_url_modules="https://download.tarantool.org/tarantool/modules/gpgkey"
  apt_source_path="/etc/apt/sources.list.d/tarantool_${ver_repo}.list"

  echo
  echo "##################################"
  echo "# Importing Tarantool gpg key... #"
  echo "##################################"
  curl -L "${gpg_key_url}" | apt-key add -
  curl -L "${gpg_key_url_modules}" | apt-key add -

  rm -f /etc/apt/sources.list.d/*tarantool*.list
  echo "deb https://download.tarantool.org{% if usr_id %}/{{ usr_id }}{% endif %}/tarantool/${repo_path}${ver}/${os}/ ${dist} main" > ${apt_source_path}
  echo "deb-src https://download.tarantool.org{% if usr_id %}/{{ usr_id }}{% endif %}/tarantool/${repo_path}${ver}/${os}/ ${dist} main" >> ${apt_source_path}
  echo "deb https://download.tarantool.org/tarantool/modules/${os}/ ${dist} main" >> ${apt_source_path}
  echo "deb-src https://download.tarantool.org/tarantool/modules/${os}/ ${dist} main" >> ${apt_source_path}
  mkdir -p /etc/apt/preferences.d/
  echo -e "Package: tarantool\nPin: origin download.tarantool.org\nPin-Priority: 1001" > /etc/apt/preferences.d/tarantool
  echo "The repository is setup! Tarantool can now be installed."

  apt_update

  echo
  echo "Tarantool ${ver} is ready to be installed by 'apt-get install -y tarantool'"
}

install_yum ()
{
  echo
  echo "#########################"
  echo "# Cleaning yum cache... #"
  echo "#########################"
  yum clean all

  echo
  echo "#################################"
  echo "# Installing EPEL repository... #"
  echo "#################################"

  if [ $dist = 6 ]; then
    curl https://www.getpagespeed.com/files/centos6-eol.repo --output /etc/yum.repos.d/CentOS-Base.repo
    yum install -y epel-release
  else
    yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-${dist}.noarch.rpm
  fi

  if [ $dist != 8 ]; then
    yum -y install yum-priorities
  fi

  echo
  echo "#####################################"
  echo "# Setting up tarantool EPEL repo... #"
  echo "#####################################"
  if [ -e /etc/yum.repos.d/epel.repo ]; then
    sed 's/enabled=.*/enabled=1/g' -i /etc/yum.repos.d/epel.repo
  fi
  rm -f /etc/yum.repos.d/*tarantool*.repo && \
    echo -e "[tarantool_${ver_repo}]\nname=EnterpriseLinux-${dist} - Tarantool\nbaseurl=https://download.tarantool.org{% if usr_id %}/{{ usr_id }}{% endif %}/tarantool/${repo_path}${ver}/el/${dist}/x86_64/\ngpgkey=https://download.tarantool.org/tarantool/${repo_path}${ver}/gpgkey\nrepo_gpgcheck=1\ngpgcheck=0\nenabled=1\npriority=1\n\n" > /etc/yum.repos.d/tarantool_${ver_repo}.repo
    echo -e "[tarantool_${ver_repo}-source]\nname=EnterpriseLinux-${dist} - Tarantool Sources\nbaseurl=https://download.tarantool.org{% if usr_id %}/{{ usr_id }}{% endif %}/tarantool/${repo_path}${ver}/el/${dist}/SRPMS\ngpgkey=https://download.tarantool.org/tarantool/${repo_path}${ver}/gpgkey\nrepo_gpgcheck=1\ngpgcheck=0\npriority=1\n\n" >> /etc/yum.repos.d/tarantool_${ver_repo}.repo
    echo -e "[tarantool_modules]\nname=EnterpriseLinux-${dist} - Tarantool\nbaseurl=https://download.tarantool.org/tarantool/modules/el/${dist}/x86_64/\ngpgkey=https://download.tarantool.org/tarantool/modules/gpgkey\nrepo_gpgcheck=1\ngpgcheck=0\nenabled=1\n\n" >> /etc/yum.repos.d/tarantool_${ver_repo}.repo
    echo -e "[tarantool_modules-source]\nname=EnterpriseLinux-${dist} - Tarantool Sources\nbaseurl=https://download.tarantool.org/tarantool/modules/el/${dist}/SRPMS\ngpgkey=https://download.tarantool.org/tarantool/modules/gpgkey\nrepo_gpgcheck=1\ngpgcheck=0" >> /etc/yum.repos.d/tarantool_${ver_repo}.repo

  echo
  echo "########################"
  echo "# Updating metadata... #"
  echo "########################"
  yum makecache -y --disablerepo='*' --enablerepo="tarantool_${ver_repo}" --enablerepo="tarantool_modules" --enablerepo='epel'

  echo
  echo "Tarantool ${ver} is ready to be installed by 'yum install -y tarantool'"

}

install_dnf ()
{
  dnf clean all

  rm -f /etc/yum.repos.d/*tarantool*.repo
  echo -e "[tarantool_${ver_repo}]\nname=Fedora-${dist} - Tarantool\nbaseurl=https://download.tarantool.org{% if usr_id %}/{{ usr_id }}{% endif %}/tarantool/${repo_path}${ver}/fedora/${dist}/x86_64/\ngpgkey=https://download.tarantool.org/tarantool/${repo_path}${ver}/gpgkey\nrepo_gpgcheck=1\ngpgcheck=0\nenabled=1\npriority=1\n\n" > /etc/yum.repos.d/tarantool_${ver_repo}.repo
  echo -e "[tarantool_${ver_repo}-source]\nname=Fedora-${dist} - Tarantool Sources\nbaseurl=https://download.tarantool.org{% if usr_id %}/{{ usr_id }}{% endif %}/tarantool/${repo_path}${ver}/fedora/${dist}/SRPMS\ngpgkey=https://download.tarantool.org/tarantool/${repo_path}${ver}/gpgkey\nrepo_gpgcheck=1\ngpgcheck=0\npriority=1\n\n" >> /etc/yum.repos.d/tarantool_${ver_repo}.repo
  echo -e "[tarantool_modules]\nname=Fedora-${dist} - Tarantool\nbaseurl=https://download.tarantool.org/tarantool/modules/fedora/${dist}/x86_64/\ngpgkey=https://download.tarantool.org/tarantool/modules/gpgkey\nrepo_gpgcheck=1\ngpgcheck=0\nenabled=1\n\n" >> /etc/yum.repos.d/tarantool_${ver_repo}.repo
  echo -e "[tarantool_modules-source]\nname=Fedora-${dist} - Tarantool Sources\nbaseurl=https://download.tarantool.org/tarantool/modules/fedora/${dist}/SRPMS\ngpgkey=https://download.tarantool.org/tarantool/modules/gpgkey\nrepo_gpgcheck=1\ngpgcheck=0" >> /etc/yum.repos.d/tarantool_${ver_repo}.repo

  echo
  echo "########################"
  echo "# Updating metadata... #"
  echo "########################"
  dnf -q makecache -y --disablerepo='*' --enablerepo="tarantool_${ver_repo}" --enablerepo="tarantool_modules"

  echo "Tarantool ${ver} is ready to be installed by 'dnf install -y tarantool'"

}

main ()
{
  detect_os
  detect_ver
  if [ ${os} = "centos" ] && [[ ${dist} =~ ^(6|7|8)$ ]]; then
    echo
    echo "################################"
    echo "# Setting up yum repository... #"
    echo "################################"
    install_yum
  elif [ ${os} = "amzn" ] && [[ ${dist} = 2 ]]; then
    echo "Setting up yum repository... "
    dist=7
    install_yum
  elif [ ${os} = "fedora" ] && [[ ${dist} =~ ^(28|29|30|31|32|33|34)$ ]]; then
    echo "Setting up yum repository..."
    install_dnf
  elif ( [ ${os} = "debian" ] && [[ ${dist} =~ ^(jessie|stretch|buster|bullseye)$ ]] ) ||
       ( [ ${os} = "ubuntu" ] && [[ ${dist} =~ ^(trusty|xenial|bionic|cosmic|disco|eoan|focal)$ ]] ); then

    echo
    echo "################################"
    echo "# Setting up apt repository... #"
    echo "################################"
    install_apt
  else
    unsupported_os
  fi
}

main
