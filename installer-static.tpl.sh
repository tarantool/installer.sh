#!/usr/bin/env bash

# Script to set up the `series-N` (N = 3, 4, etc.) and `modules` repositories
# for Tarantool on any distro where RPM or DEB packages are used.

function main() {
  if yum --version > /dev/null 2>&1 || dnf --version > /dev/null 2>&1; then
    setup_yum_dnf_repo
  elif apt-get --version > /dev/null 2>&1; then
    setup_apt_repo
  elif zypper --version > /dev/null 2>&1; then
    setup_zypper_repo
  else
    echo "Unknown package manager. Supported ones: apt-get, dnf, yum, zypper"
    exit 1
  fi
}

setup_apt_repo() {
  apt-get update
  apt-get -y install apt-transport-https curl gnupg

  gpg_key_url="https://download.tarantool.org/tarantool/{{ rtype }}/series-{{ tarantool_version }}/gpgkey"
  gpg_key_url_modules="https://download.tarantool.org/tarantool/release/modules/gpgkey"
  apt_source_path="/etc/apt/sources.list.d/tarantool_{{ tarantool_version }}_static.list"

  curl -L "${gpg_key_url}" | apt-key add -
  curl -L "${gpg_key_url_modules}" | apt-key add -

  echo "deb https://download.tarantool.org{% if usr_id %}/{{ usr_id }}{% endif %}/tarantool/{{ rtype }}/series-{{ tarantool_version }}/linux-deb/ static main" > ${apt_source_path}
  echo "deb https://download.tarantool.org{% if usr_id %}/{{ usr_id }}{% endif %}/tarantool/release/modules/linux-deb static main" >> ${apt_source_path}

  mkdir -p /etc/apt/preferences.d/
  echo -e "Package: tarantool\nPin: origin download.tarantool.org{% if usr_id %}/{{ usr_id }}{% endif %}\nPin-Priority: 1001" > /etc/apt/preferences.d/tarantool
  echo -e "\nPackage: tarantool-common\nPin: origin download.tarantool.org{% if usr_id %}/{{ usr_id }}{% endif %}\nPin-Priority: 1001" >> /etc/apt/preferences.d/tarantool
  echo -e "\nPackage: tarantool-dev\nPin: origin download.tarantool.org{% if usr_id %}/{{ usr_id }}{% endif %}\nPin-Priority: 1001" >> /etc/apt/preferences.d/tarantool

  apt-get update

  if [[ ${FORCE_INSTALL_TARANTOOL:-False} = "True" ]]; then
    echo "Installing Tarantool {{ tarantool_version }}"
    DEBIAN_FRONTEND=noninteractive apt-get -y install tarantool
  else
    echo "Tarantool {{ tarantool_version }} is ready to be installed by 'apt-get -y install tarantool'"
  fi
}

setup_yum_dnf_repo() {
  cat <<EOF > /etc/yum.repos.d/tarantool_{{ tarantool_version }}_static.repo
[tarantool]
name=Tarantool
baseurl=https://download.tarantool.org{% if usr_id %}/{{ usr_id }}{% endif %}/tarantool/{{ rtype }}/series-{{ tarantool_version }}/linux-rpm/static/\$basearch/
gpgkey=https://download.tarantool.org/tarantool/{{ rtype }}/series-{{ tarantool_version }}/gpgkey
repo_gpgcheck=1
gpgcheck=0
enabled=1
priority=1

[tarantool_modules]
name=Tarantool modules
baseurl=https://download.tarantool.org{% if usr_id %}/{{ usr_id }}{% endif %}/tarantool/release/modules/linux-rpm/static/\$basearch/
gpgkey=https://download.tarantool.org/tarantool/release/modules/gpgkey
repo_gpgcheck=1
gpgcheck=0
enabled=1
priority=1
EOF

  if yum --version > /dev/null 2>&1; then
    if [[ ${FORCE_INSTALL_TARANTOOL:-False} = "True" ]]; then
      echo "Installing Tarantool {{ tarantool_version }}"
      yum -y install tarantool
    else
      echo "Tarantool {{ tarantool_version }} is ready to be installed by 'yum -y install tarantool'"
    fi
  else
    if [[ ${FORCE_INSTALL_TARANTOOL:-False} = "True" ]]; then
      echo "Installing Tarantool {{ tarantool_version }}"
      dnf -y install tarantool
    else
      echo "Tarantool {{ tarantool_version }} is ready to be installed by 'dnf -y install tarantool'"
    fi
  fi
}

setup_zypper_repo() {
  rpm --import https://download.tarantool.org/tarantool/{{ rtype }}/series-{{ tarantool_version }}/gpgkey
  rpm --import https://download.tarantool.org/tarantool/release/modules/gpgkey
  cat <<EOF > /etc/zypp/repos.d/tarantool_{{ tarantool_version }}_static.repo
[tarantool]
name=Tarantool
baseurl=https://download.tarantool.org{% if usr_id %}/{{ usr_id }}{% endif %}/tarantool/{{ rtype }}/series-{{ tarantool_version }}/linux-rpm/static/\$basearch/
gpgkey=https://download.tarantool.org/tarantool/{{ rtype }}/series-{{ tarantool_version }}/gpgkey
repo_gpgcheck=1
gpgcheck=0
enabled=1
priority=1

[tarantool_modules]
name=Tarantool modules
baseurl=https://download.tarantool.org{% if usr_id %}/{{ usr_id }}{% endif %}/tarantool/release/modules/linux-rpm/static/\$basearch/
gpgkey=https://download.tarantool.org/tarantool/release/modules/gpgkey
repo_gpgcheck=1
gpgcheck=0
enabled=1
priority=1
EOF

  if [[ ${FORCE_INSTALL_TARANTOOL:-False} = "True" ]]; then
    echo "Installing Tarantool {{ tarantool_version }}"
    zypper install -y tarantool
  else
    echo "Tarantool {{ tarantool_version }} is ready to be installed by 'zypper install -y tarantool'"
  fi
}

echo "Setting up the repository for Tarantool {{ tarantool_version }}"

main
