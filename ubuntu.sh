#!/bin/bash

# vim: filetype=sh:tabstop=2:shiftwidth=2:expandtab

# http://www.kfirlavi.com/blog/2012/11/14/defensive-bash-programming/

base_setup()
{
  echo ""
  inf "Performing base setup..."
  echo ""

  if [ "$DEFAULT_USER" == 'root' ]; then
    su -c "mkdir -p /home/$DEV_USER/.bootstrap" "$DEV_USER"
    su -c "mkdir -p /home/$DEV_USER/bin" "$DEV_USER"
  else
    mkdir -p "/home/$DEV_USER/.bootstrap"
    mkdir -p "/home/$DEV_USER/bin"
  fi

  # in case a previous update failed
  if [ -d "/var/lib/dpkg/updates" ]; then
    $SH_C 'cd /var/lib/dpkg/updates; rm -f *'
  fi

  # for asciinema support
  $SH_C 'apt-add-repository -y ppa:zanchey/asciinema'

  $SH_C 'apt-get install -yq git mercurial subversion letsencrypt wget curl jq unzip vim gnupg2 \
  build-essential autoconf automake libtool make g++ cmake make ssh gcc openssh-client python-dev python3-dev libssl-dev libffi-dev asciinema tree'
  $SH_C 'apt-get -y update'

  if ! command_exists pip; then
    $SH_C 'apt-get remove -y python-pip'
    $SH_C 'apt-get install -y python-setuptools'
    $SH_C 'easy_install pip'
  fi

  $SH_C 'pip install --upgrade pyyaml'
  $SH_C 'pip install --upgrade cookiecutter'

  $SH_C 'apt-get -y autoremove'
}


### node.js
# http://tecadmin.net/install-latest-nodejs-npm-on-ubuntu/#
###
install_node()
{
  echo ""
  inf "Installing Node.js..."
  echo ""

  $SH_C 'apt-get install -y python-software-properties'
  curl -sL https://deb.nodesource.com/setup_6.x | sudo -E bash -
  $SH_C 'apt-get install -y nodejs'

  if command_exists yarn; then
    echo "yarn (nodejs package mgr) is already installed. Will attempt to upgrade..."
    $SH_C 'npm upgrade --global yarn'
  else
    $SH_C 'npm install -g yarn'
  fi
}


### serverless
#
###
install_serverless()
{
  echo ""
  inf "Installing serverless utilities..."
  echo ""

  if command_exists serverless; then
    echo "serverless client is already installed. Will attempt to upgrade..."
    $SH_C 'yarn global upgrade serverless'
    ##$SH_C 'yarn global add serverless'
  else
    ##$SH_C 'yarn global upgrade serverless'
    $SH_C 'yarn global add serverless'
  fi

  if command_exists apex; then
    echo "apex client is already installed. Will attempt to upgrade..."
    $SH_C 'apex upgrade'
  else
    rm -rf /tmp/apex-install.sh
    wget -O /tmp/apex-install.sh \
      https://raw.githubusercontent.com/apex/apex/master/install.sh
    chmod +x /tmp/apex-install.sh
    $SH_C '/tmp/apex-install.sh'
  fi

  if [ "$DEFAULT_USER" == 'root' ]; then
    chown "$DEV_USER":"$DEV_USER" -R "/home/$DEV_USER/.config/yarn/global/"
    chown "$DEV_USER":"$DEV_USER" -R "/home/$DEV_USER/.cache"
  else
    sudo chown "$DEFAULT_USER":"$DEFAULT_USER" -R "/home/$DEFAULT_USER/.config/yarn/global/"
    sudo chown "$DEFAULT_USER":"$DEFAULT_USER" -R "/home/$DEFAULT_USER/.cache"
  fi

  if command_exists functions; then
    echo "google cloud functions emulator is already installed. Will attempt to upgrade..."
    $SH_C 'npm update -g @google-cloud/functions-emulator'
  else
    $SH_C 'npm install -g @google-cloud/functions-emulator'
  fi
}


### docker
# https://docs.docker.com/engine/installation/linux/
###
install_docker()
{
  echo ""
  inf "Installing Docker..."
  echo ""

  if command_exists docker; then
    local version="$(docker -v | awk -F '[ ,]+' '{ print $3 }')"
    local MAJOR_W=1
    local MINOR_W=10
    semverParse $version
    warn "Docker $version is already installed...skipping installation"
  else
    $SH_C 'apt-get install -y apt-transport-https ca-certificates'
    $SH_C 'apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 58118E89F3A912897C070ADBF76221572C52609D'
    $SH_C 'apt-get -y update'

    $SH_C 'apt-get install -y "linux-image-extra-$(uname -r)"'
    if [ "$DISTRO_VER" == "16.04" ]; then
      $SH_C 'echo "deb https://apt.dockerproject.org/repo ubuntu-xenial main" > /etc/apt/sources.list.d/docker.list'
    elif [ "$DISTRO_VER" == "15.10" ]; then
      $SH_C 'echo "deb https://apt.dockerproject.org/repo ubuntu-wily main" > /etc/apt/sources.list.d/docker.list'
    elif [ "$DISTRO_VER" == "14.04" ]; then
      $SH_C 'echo "deb https://apt.dockerproject.org/repo ubuntu-trusty main" > /etc/apt/sources.list.d/docker.list'
    fi

    $SH_C 'apt-get -y update'
    $SH_C 'apt-get install -yq docker-engine'
  fi

  $SH_C 'groupadd -f docker'
  inf "added docker group"

  echo "$DEV_USER" > /tmp/bootstrap_usermod_feh || exit 1
  $SH_C 'usermod -aG docker $(cat /tmp/bootstrap_usermod_feh)'
  rm -f /tmp/bootstrap_usermod_feh || exit 1
  inf "added $DEV_USER to group docker"

  ## Start Docker
  if command_exists systemctl; then
#    $SH_C "$PROGDIR/docker/userns.sh $DEV_USER"
    $SH_C 'systemctl daemon-reload'
    $SH_C 'systemctl enable docker'
    if [ ! -f "/var/run/docker.pid" ]; then
      $SH_C 'systemctl start docker'
    else
      inf "Docker appears to already be running"
    fi
  else
    inf "no systemctl found...assuming this OS is not using systemd (yet)"
    if [ ! -f "/var/run/docker.pid" ]; then
      $SH_C 'service docker start'
    else
      inf "Docker appears to already be running"
    fi
  fi

  # User must log off for these changes to take effect
  LOGOFF_REQ=1
}
