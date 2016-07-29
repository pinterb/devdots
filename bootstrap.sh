#!/bin/bash

# vim: filetype=sh:tabstop=2:shiftwidth=2:expandtab

# http://www.kfirlavi.com/blog/2012/11/14/defensive-bash-programming/

readonly PROGNAME=$(basename $0)
readonly PROGDIR="$( cd "$(dirname "$0")" ; pwd -P )"
readonly ARGS="$@"
readonly TODAY=$(date +%Y%m%d%H%M%S)

# pull in utils
source "${PROGDIR}/utils.sh"

case "$DISTRO_ID" in
  Ubuntu)
    inf "Configuring $DISTRO_ID $DISTRO_VER..."
    inf ""
    sleep 4
  ;;

  Debian)
    warn "Configuring $DISTRO_ID $DISTRO_VER..."
    warn "Support for this distro is spotty.  Your mileage will vary."
    warn ""
    warn "You may press Ctrl+C now to abort this script."
    sleep 10
  ;;

  RHEL)
    error "Configuring $DISTRO_ID $DISTRO_VER..."
    error "Unfortunately, this is an unsupported distro"
    error ""
    sleep 4
    exit 1
  ;;

  *)
    error "Configuring $DISTRO_ID $DISTRO_VER..."
    error "Unfortunately, this is an unsupported distro"
    error ""
    sleep 4
    exit 1
  ;;

esac


# based on user, determine how commands will be executed
SH_C='sh -c'
if [ "$DEFAULT_USER" != 'root' ]; then
  if command_exists sudo; then
    SH_C='sudo -E sh -c'
  elif command_exists su; then
    SH_C='su -c'
  else
    cat >&2 <<-'EOF'
    Error: this installer needs the ability to run commands as root.
    We are unable to find either "sudo" or "su" available to make this happen.
EOF
    exit 1
  fi
fi

# cli arguments
DEV_USER=
ENABLE_ANSIBLE=
ENABLE_AWS=
ENABLE_DOCKER=
ENABLE_GOLANG=
ENABLE_GCLOUD=
ENABLE_TERRAFORM=
ENABLE_VIM=

# misc. flags
SHOULD_WARM=0
LOGOFF_REQ=0

usage() {
  cat <<- EOF
  usage: $PROGNAME options

  $PROGNAME bootstraps all or some of a development environment for a new, non-privileged user.
  It downloads install scripts under the new user's home directory and enables .profile or .bash_profile
  to install specified development tools.

  OPTIONS:
    -u --user                non-privileged user account to be bootstrapped (NOTE: invalid option when running as non-privileged user)
    -a --ansible             enable ansible
    -d --docker              enable docker
    -g --golang              enable golang (incl. third-party utilities)
    -y --gcloud              enable gcloud cli
    -t --terraform           enable terraform
    -y --gcloud              enable gcloud cli
    -v --vim                 enable vim-plug & choice plugins (e.g. vim-go)
    -z --aws                 enable aws cli
    -h --help                show this help


  Examples:
    $PROGNAME --user pinterb --golang
EOF
}


cmdline() {
  # got this idea from here:
  # http://kirk.webfinish.com/2009/10/bash-shell-script-to-use-getopts-with-gnu-style-long-positional-parameters/
  local arg=
  local args=
  for arg
  do
    local delim=""
    case "$arg" in
      #translate --gnu-long-options to -g (short options)
      --user)           args="${args}-u ";;
      --ansible)        args="${args}-a ";;
      --aws)            args="${args}-z ";;
      --docker)         args="${args}-d ";;
      --golang)         args="${args}-g ";;
      --gcloud)         args="${args}-y ";;
      --terraform)      args="${args}-t ";;
      --vim)            args="${args}-v ";;
      --help)           args="${args}-h ";;
      #pass through anything else
      *) [[ "${arg:0:1}" == "-" ]] || delim="\""
          args="${args}${delim}${arg}${delim} ";;
    esac
  done

  #Reset the positional parameters to the short options
  eval set -- $args

  while getopts ":u:adgytvzh" OPTION
  do
     case $OPTION in
     u)
         DEV_USER=$OPTARG
         ;;
     a)
         readonly ENABLE_ANSIBLE=1
         ;;
     d)
         readonly ENABLE_DOCKER=1
         ;;
     g)
         readonly ENABLE_GOLANG=1
         ;;
     y)
         readonly ENABLE_GCLOUD=1
         ;;
     t)
         readonly ENABLE_TERRAFORM=1
         ;;
     v)
         readonly ENABLE_VIM=1
         ;;
     z)
         readonly ENABLE_AWS=1
         ;;
     h)
         usage
         exit 0
         ;;
     \:)
         echo "  argument missing from -$OPTARG option"
         echo ""
         usage
         exit 1
         ;;
     \?)
         echo "  unknown option: -$OPTARG"
         echo ""
         usage
         exit 1
         ;;
    esac
  done

  return 0
}


valid_args()
{
  if [ "$DEFAULT_USER" != 'root' ]; then
    if [[ -z "$DEV_USER" ]]; then
      warn "Defaulting non-privileged user to $DEFAULT_USER"
      DEV_USER=$DEFAULT_USER
    elif [ "$DEFAULT_USER" != "$DEV_USER" ]; then
      error "When executing as a non-privileged user, --user option is not permitted"
      echo ""
      usage
      exit 1
    fi
  elif [[ -z "$DEV_USER" ]]; then
    error "a non-privileged user is required"
    echo  ""
    usage
    exit 1
  fi
}


# Make sure we have all the right stuff
prerequisites() {
  local git_cmd=$(which git)

  if [ -z "$git_cmd" ]; then
    error "git does not appear to be installed. Please install and re-run this script."
    exit 1
  fi

  # we want to be root to bootstrap
#  if [ "$EUID" -ne 0 ]; then
#    error "Please run as root"
#    exit 1
#  fi

  # for now, let's assume someone else has already created our non-privileged user.
  ret=false
  getent passwd "$DEV_USER" >/dev/null 2>&1 && ret=true

  if ! $ret; then
    error "$DEV_USER user does not exist"
  fi

  if [ ! -d "/home/$DEV_USER" ]; then
    error "By convention, expecting /home/$DEV_USER to exist. Please create a user with /home directory."
  fi
}


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
  if [ "$DISTRO_ID" == "Ubuntu" ]; then
    $SH_C 'apt-add-repository -y ppa:zanchey/asciinema'
  fi

  $SH_C 'apt-get -y update'
  $SH_C 'apt-get install -yq git mercurial subversion wget curl jq unzip vim gnupg2 \
  build-essential cmake make ssh gcc openssh-client python-dev python3-dev libssl-dev libffi-dev asciinema tree'

  if ! command_exists pip; then
    $SH_C 'apt-get remove -y python-pip'
    $SH_C 'apt-get install -y python-setuptools'
    $SH_C 'easy_install pip'
  fi

  $SH_C 'apt-get -y autoremove'
}


dotfiles()
{
  echo ""
  inf "Copying dotfiles..."
  echo ""

  # handle .bashrc
  if [ -f "/home/$DEV_USER/.bashrc" ]; then
    inf "Backing up .bashrc file"
    cp "/home/$DEV_USER/.bashrc" "/home/$DEV_USER/.bashrc-$TODAY"
  fi

  if [ -f "$PROGDIR/dotfiles/bashrc" ]; then
    inf "Copying new Debian-based .bashrc file"
    cp "$PROGDIR/dotfiles/bashrc" "/home/$DEV_USER/.bashrc"
  fi

  # handle .profile
  if [ -f "/home/$DEV_USER/.profile" ]; then
    inf "Backing up .profile file"
    cp "/home/$DEV_USER/.profile" "/home/$DEV_USER/.profile-$TODAY"
  fi

  if [ -f "$PROGDIR/dotfiles/profile" ]; then
    inf "Copying new .profile file"
    cp "$PROGDIR/dotfiles/profile" "/home/$DEV_USER/.profile"
  fi

  if [ "$DEFAULT_USER" == 'root' ]; then
    chown -R "$DEV_USER:$DEV_USER" "/home/$DEV_USER"
  fi
}


enable_vim()
{
  echo ""
  inf "Enabling vim & pathogen..."
  echo ""

  local inst_dir="/home/$DEV_USER/.vim"
  mkdir -p "$inst_dir/autoload" "$inst_dir/colors"

  ## not quite sure yet which vim plugin manager to use
#  $SH_C "curl -fLo $inst_dir/autoload/plug.vim --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim"
  curl -LSso "$inst_dir/autoload/pathogen.vim" https://tpo.pe/pathogen.vim

  # some vim colors
  if [ -d "/home/$DEV_USER/projects/vim-colors-molokai" ]; then
    cd /home/$DEV_USER/projects/vim-colors-molokai; git pull
  else
    git clone https://github.com/fatih/molokai "/home/$DEV_USER/projects/vim-colors-molokai"
  fi

  if [ -f "/home/$DEV_USER/projects/vim-colors-molokai/colors/molokai.vim" ]; then
    cp "/home/$DEV_USER/projects/vim-colors-molokai/colors/molokai.vim" "$inst_dir/colors/molokai.vim"
  fi

  # some dot files
#  if [ -d "/home/$DEV_USER/projects/dotfiles" ]; then
#    $SH_C "cd /home/$DEV_USER/projects/dotfiles; git pull"
#  else
#    $SH_C "git clone https://github.com/fatih/dotfiles /home/$DEV_USER/projects/dotfiles"
#  fi

  if [ "$DEFAULT_USER" == 'root' ]; then
    chown -R "$DEV_USER:$DEV_USER" "/home/$DEV_USER"
#    chown -R "$DEV_USER:$DEV_USER" "$inst_dir"
  fi
}


enable_pathogen_bundles()
{
  echo ""
  inf "Enabling vim & pathogen bundles..."
  echo ""

  local inst_dir="/home/$DEV_USER/.vim/bundle"
  rm -rf "$inst_dir"; mkdir -p "$inst_dir"
  cd "$inst_dir"

  inf "Re-populating pathogen bundles..."

  ## colors
  git clone git://github.com/altercation/vim-colors-solarized.git

  ## golang
  git clone https://github.com/fatih/vim-go.git

  ## json
  git clone https://github.com/elzr/vim-json.git

  ## yaml
  git clone https://github.com/avakhov/vim-yaml

  ## Ansible
  git clone https://github.com/pearofducks/ansible-vim

  ## Dockerfile
  git clone https://github.com/ekalinin/Dockerfile.vim.git \
  "$inst_dir/Dockerfile"

  ## Nerdtree
  git clone https://github.com/scrooloose/nerdtree.git

  ## Ruby
  git clone git://github.com/vim-ruby/vim-ruby.git

  ## Python
  git clone https://github.com/klen/python-mode.git

  ## Whitespace (hint: to see whitespace just :ToggleWhitespace)
  git clone git://github.com/ntpeters/vim-better-whitespace.git

  if [ $MEM_TOTAL_KB -ge 1500000 ]; then
    enable_vim_ycm
    cd "$inst_dir"
  else
    warn "Your system requires at least 1.5 GB of memory to "
    warn "install the YouCompleteMe vim plugin. Skipping... "
  fi

  # handle .vimrc
  if [ -f "/home/$DEV_USER/.vimrc" ]; then
    inf "Backing up .vimrc file"
    cp "/home/$DEV_USER/.vimrc" "/home/$DEV_USER/.vimrc-$TODAY"
  fi

  if [ -f "$PROGDIR/dotfiles/vimrc" ]; then
    inf "Copying new .vimrc file"
    cp "$PROGDIR/dotfiles/vimrc" "/home/$DEV_USER/.vimrc"
  fi

  if [ "$DEFAULT_USER" == 'root' ]; then
    chown -R "$DEV_USER:$DEV_USER" "/home/$DEV_USER"
    chown -R "$DEV_USER:$DEV_USER" "$inst_dir"
  fi
}


enable_vim_ycm()
{
  echo ""
  inf "Installing the YouCompleteMe vim plugin..."
  echo ""

  local inst_dir="/home/$DEV_USER/.vim/bundle"

  ## YouCompleteMe
  git clone https://github.com/valloric/youcompleteme
  cd "$inst_dir/youcompleteme"
  git submodule update --init --recursive
  local ycm_opts=

  if command_exists go; then
    ycm_opts="--gocode-completer"
  fi

  sh -c "$inst_dir/youcompleteme/install.py $ycm_opts"
}


enable_golang()
{
  echo ""
  inf "Enabling Golang..."
  echo ""

  local inst_dir="/home/$DEV_USER/.bootstrap/golang"

  rm -rf "$inst_dir"
  cp -R "$PROGDIR/golang" "$inst_dir"

  cp "$inst_dir/golang_profile" "/home/$DEV_USER/.golang_profile"
  cp "$inst_dir/golang_verify" "/home/$DEV_USER/.golang_verify"
  sed -i -e "s@###MY_PROJECT_DIR###@/home/${DEV_USER}/.bootstrap/golang@" /home/$DEV_USER/.golang_verify

  if [ -f "/home/$DEV_USER/.bash_profile" ]; then
    inf "Setting up .bash_profile"
    grep -q -F 'source "$HOME/.golang_profile"' "/home/$DEV_USER/.bash_profile" || echo 'source "$HOME/.golang_profile"' >> "/home/$DEV_USER/.bash_profile"
    grep -q -F 'source "$HOME/.golang_verify"' "/home/$DEV_USER/.bash_profile" || echo 'source "$HOME/.golang_verify"' >> "/home/$DEV_USER/.bash_profile"
  else
    inf "Setting up .profile"
    grep -q -F 'source "$HOME/.golang_profile"' "/home/$DEV_USER/.profile" || echo 'source "$HOME/.golang_profile"' >> "/home/$DEV_USER/.profile"
    grep -q -F 'source "$HOME/.golang_verify"' "/home/$DEV_USER/.profile" || echo 'source "$HOME/.golang_verify"' >> "/home/$DEV_USER/.profile"
  fi

  if [ "$DEFAULT_USER" == 'root' ]; then
    chown -R "$DEV_USER:$DEV_USER" "$inst_dir"
    chown "$DEV_USER:$DEV_USER" "/home/$DEV_USER/.golang_profile"
    chown "$DEV_USER:$DEV_USER" "/home/$DEV_USER/.golang_verify"
  else
    echo ""
    inf "Okay...Verifying Golang..."
    echo ""
    sh "$HOME/.golang_verify"
  fi

  # User must log off for these changes to take effect
  LOGOFF_REQ=1
}


enable_terraform()
{
  echo ""
  inf "Enabling Terraform..."
  echo ""

  local inst_dir="/home/$DEV_USER/.bootstrap/terraform"

  rm -rf "$inst_dir"
  cp -R "$PROGDIR/terraform" "$inst_dir"
  chown -R "$DEV_USER:$DEV_USER" "$inst_dir"

  cp "$inst_dir/terraform_verify" "/home/$DEV_USER/.terraform_verify"
  sed -i -e "s@###MY_PROJECT_DIR###@/home/${DEV_USER}/.bootstrap/terraform@" /home/$DEV_USER/.terraform_verify

  if [ -f "/home/$DEV_USER/.bash_profile" ]; then
    inf "Setting up .bash_profile"
    grep -q -F 'source "$HOME/.terraform_verify"' "/home/$DEV_USER/.bash_profile" || echo 'source "$HOME/.terraform_verify"' >> "/home/$DEV_USER/.bash_profile"
  else
    inf "Setting up .profile"
    grep -q -F 'source "$HOME/.terraform_verify"' "/home/$DEV_USER/.profile" || echo 'source "$HOME/.terraform_verify"' >> "/home/$DEV_USER/.profile"
  fi

  if [ "$DEFAULT_USER" == 'root' ]; then
    chown -R "$DEV_USER:$DEV_USER" "$inst_dir"
    chown "$DEV_USER:$DEV_USER" "/home/$DEV_USER/.terraform_verify"
  else
    echo ""
    inf "Okay...Verifying Terraform..."
    echo ""
    sh "$HOME/.terraform_verify"
  fi

  # User must log off for these changes to take effect
  LOGOFF_REQ=1
}


### google cloud platform cli
# https://cloud.google.com/sdk/docs/quickstart-debian-ubuntu
###
enable_gcloud()
{
  echo ""
  inf "Enabling Google Cloud SDK..."
  echo ""

  local inst_dir="/home/$DEV_USER/.bootstrap/gcloud"

  rm -rf "$inst_dir"
  cp -R "$PROGDIR/gcloud" "$inst_dir"

  cp "$inst_dir/gcloud_profile" "/home/$DEV_USER/.gcloud_profile"
  cp "$inst_dir/gcloud_verify" "/home/$DEV_USER/.gcloud_verify"
  sed -i -e "s@###MY_PROJECT_DIR###@/home/${DEV_USER}/.bootstrap/gcloud@" /home/$DEV_USER/.gcloud_verify
  sed -i -e "s@###MY_BIN_DIR###@/home/${DEV_USER}/bin@" /home/$DEV_USER/.gcloud_verify

  if [ -f "/home/$DEV_USER/.bash_profile" ]; then
    inf "Setting up .bash_profile"
    grep -q -F 'source "$HOME/.gcloud_profile"' "/home/$DEV_USER/.bash_profile" || echo 'source "$HOME/.gcloud_profile"' >> "/home/$DEV_USER/.bash_profile"
    grep -q -F 'source "$HOME/.gcloud_verify"' "/home/$DEV_USER/.bash_profile" || echo 'source "$HOME/.gcloud_verify"' >> "/home/$DEV_USER/.bash_profile"
  else
    inf "Setting up .profile"
    grep -q -F 'source "$HOME/.gcloud_profile"' "/home/$DEV_USER/.profile" || echo 'source "$HOME/.gcloud_profile"' >> "/home/$DEV_USER/.profile"
    grep -q -F 'source "$HOME/.gcloud_verify"' "/home/$DEV_USER/.profile" || echo 'source "$HOME/.gcloud_verify"' >> "/home/$DEV_USER/.profile"
  fi

  if [ "$DEFAULT_USER" == 'root' ]; then
    chown -R "$DEV_USER:$DEV_USER" "$inst_dir"
    chown "$DEV_USER:$DEV_USER" "/home/$DEV_USER/.gcloud_profile"
    chown "$DEV_USER:$DEV_USER" "/home/$DEV_USER/.gcloud_verify"
  else
    echo ""
    inf "Okay...Verifying Google Cloud SDK..."
    echo ""
    sh "$HOME/.gcloud_verify"
  fi
}


### ansible
# http://docs.ansible.com/ansible/intro_installation.html#latest-releases-via-pip
###
install_ansible()
{
  echo ""
  inf "Installing Ansible..."
  echo ""

 if command_exists ansible; then
    local version="$(ansible --version | awk '{ print $2; exit }')"
    semverParse $version
    warn "Ansible $version is already installed...skipping installation"
    return 0
  fi

  $SH_C 'pip install git+git://github.com/ansible/ansible.git@devel'
  $SH_C 'pip install ansible-lint'
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
    if [ "$DISTRO_ID" == "Debian" ]; then
      if [ "$DISTRO_VER" == "8.5" ]; then
        echo "deb https://apt.dockerproject.org/repo debian-jessie main" > /etc/apt/sources.list.d/docker.list
      else
        echo "deb http://http.debian.net/debian wheezy-backports main" > /etc/apt/sources.list.d/backports.list
        echo "deb https://apt.dockerproject.org/repo debian-wheezy main" > /etc/apt/sources.list.d/docker.list
      fi
    elif [ "$DISTRO_ID" == "Ubuntu" ]; then
      $SH_C 'apt-get install -y "linux-image-extra-$(uname -r)"'
      if [ "$DISTRO_VER" == "16.04" ]; then
        $SH_C 'echo "deb https://apt.dockerproject.org/repo ubuntu-xenial main" > /etc/apt/sources.list.d/docker.list'
      elif [ "$DISTRO_VER" == "15.10" ]; then
        $SH_C 'echo "deb https://apt.dockerproject.org/repo ubuntu-wily main" > /etc/apt/sources.list.d/docker.list'
      elif [ "$DISTRO_VER" == "14.04" ]; then
        $SH_C 'echo "deb https://apt.dockerproject.org/repo ubuntu-trusty main" > /etc/apt/sources.list.d/docker.list'
      fi
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


### ssh key generation for gce
# https://cloud.google.com/compute/docs/instances/adding-removing-ssh-keys#project-wide
###
#create_gcloud_creds()
#{
#  local expir_date=$(date -d "+30 days" --utc --iso-8601='seconds')
#  su -c "ssh-keygen -b 2048 -t rsa -f ~/.ssh/google_compute_engine -C $DEV_USER -q -N \"\"" $DEV_USER
#  sed -i -e 's@pinterb@google-ssh {"userName":"pinterb","expireOn":"###EXPIRDT###"}@' ~/.ssh/google_compute_engine.pub
#  sed -i -e "s@###EXPIRDT###@${EXPIR_DT}@"  ~/.ssh/google_compute_engine.pub
#  sed -i -e "s@ssh-rsa@pinterb:ssh-rsa@" ~/.ssh/google_compute_engine.pub
#  su -c "chmod 400 ~/.ssh/google_compute_engine" pinterb
#}


main() {
  # Be unforgiving about errors
  set -euo pipefail
  readonly SELF="$(absolute_path $0)"
  cmdline $ARGS
  valid_args
  prerequisites
  base_setup
  dotfiles

  # golang handler
  if [ -n "$ENABLE_GOLANG" ]; then
    enable_golang
  fi

  # terraform handler
  if [ -n "$ENABLE_TERRAFORM" ]; then
    enable_terraform
  fi

  # gcloud handler
  if [ -n "$ENABLE_GCLOUD" ]; then
    enable_gcloud
  fi

  # vim handler
  if [ -n "$ENABLE_VIM" ]; then
    enable_vim
    enable_pathogen_bundles
  fi

  # ansible handler
  if [ -n "$ENABLE_ANSIBLE" ]; then
    install_ansible
  fi

  # docker handler
  if [ -n "$ENABLE_DOCKER" ]; then
    install_docker
  fi

  # always the last step, notify use to logoff for changes to take affect
  if [ $LOGOFF_REQ -eq 1 ]; then
    echo ""
    echo ""
    warn "*******************************"
    warn "* For changes to take effect, *"
    warn "* you must first log off!     *"
    warn "*******************************"
    echo ""
  fi

}

[[ "$0" == "$BASH_SOURCE" ]] && main
