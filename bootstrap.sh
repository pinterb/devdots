#!/bin/bash

# vim: filetype=sh:tabstop=2:shiftwidth=2:expandtab

# http://www.kfirlavi.com/blog/2012/11/14/defensive-bash-programming/

readonly PROGNAME=$(basename $0)
readonly PROGDIR="$( cd "$(dirname "$0")" ; pwd -P )"
readonly ARGS="$@"
readonly TODAY=$(date +%Y%m%d%H%M%S)

# pull in utils
source "${PROGDIR}/utils.sh"

# pull in distro-specific functions
source "${PROGDIR}/$(echo $DISTRO_ID | tr '[:upper:]' '[:lower:]').sh"

# cli arguments
DEV_USER=
ENABLE_ANSIBLE=
ENABLE_AWS=
ENABLE_KOPS=
ENABLE_KUBE_AWS=
ENABLE_DOCKER=
ENABLE_GOLANG=
ENABLE_GCLOUD=
ENABLE_TERRAFORM=
ENABLE_VIM=
ENABLE_KUBE_UTILS=
ENABLE_PROTO_BUF=
ENABLE_NODE=
ENABLE_SERVERLESS=
ENABLE_HYPER=
ENABLE_DO=
ENABLE_HABITAT=

# misc. flags
SHOULD_WARM=0
LOGOFF_REQ=0

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


usage() {
  cat <<- EOF
  usage: $PROGNAME options

  $PROGNAME bootstraps all or some of a development environment for a new, non-privileged user.
  It downloads install scripts under the new user's home directory and enables .profile or .bash_profile
  to install specified development tools.

  OPTIONS:
    --user <userid>        non-privileged user account to be bootstrapped (NOTE: invalid option when running as non-privileged user)
    --ansible              enable ansible
    --aws                  enable aws cli
    --digitalocean         enable digitalocean cli
    --docker               enable docker
    --gcloud               enable gcloud cli
    --golang               enable golang (incl. third-party utilities)
    --habitat              enable habitat.sh (Habitat enables you to build and run your applications in a Cloud Native manner.)
    --hyper                enable hyper.sh (Hyper.sh is a hypervisor-agnostic Docker runtime)
    --kops                 enable kops (a kubernetes provisioning tool)
    --kubectl              enable kubectl and helm
    --kube-aws             enable kube-aws (a kubernetes provisioning tool)
    --node                 enable node.js and serverless
    --proto-buf            enable protocol buffers (i.e. protoc)
    --serverless           enable various serverless utilities (e.g. serverless, apex, sparta)
    --terraform            enable terraform
    --vim                  enable vim-plug & choice plugins (e.g. vim-go)
    -h --help              show this help


  Examples:
    $PROGNAME --user pinterb --golang
EOF
}

###
# http://mywiki.wooledge.org/ComplexOptionParsing
###
cmdline() {
  i=$(($# + 1)) # index of the first non-existing argument
  declare -A longoptspec
  # Use associative array to declare how many arguments a long option
  # expects. In this case we declare that loglevel expects/has one
  # argument and range has two. Long options that aren't listed in this
  # way will have zero arguments by default.
  longoptspec=( [user]=1 )
  optspec=":h-:"
  while getopts "$optspec" opt; do
  while true; do
    case "${opt}" in
      -) #OPTARG is name-of-long-option or name-of-long-option=value
        if [[ ${OPTARG} =~ .*=.* ]] # with this --key=value format only one argument is possible
        then
          opt=${OPTARG/=*/}
          ((${#opt} <= 1)) && {
            error "Syntax error: Invalid long option '$opt'" >&2
            exit 2
          }
          if (($((longoptspec[$opt])) != 1))
          then
            error "Syntax error: Option '$opt' does not support this syntax." >&2
            exit 2
          fi
          OPTARG=${OPTARG#*=}
        else #with this --key value1 value2 format multiple arguments are possible
          opt="$OPTARG"
          ((${#opt} <= 1)) && {
            error "Syntax error: Invalid long option '$opt'" >&2
            exit 2
          }
          OPTARG=(${@:OPTIND:$((longoptspec[$opt]))})
          ((OPTIND+=longoptspec[$opt]))
          #echo $OPTIND
          ((OPTIND > i)) && {
          error "Syntax error: Not all required arguments for option '$opt' are given." >&2
          exit 3
          }
        fi

        continue #now that opt/OPTARG are set we can process them as
        # if getopts would've given us long options
        ;;
      user)
        DEV_USER=$OPTARG
        ;;
      ansible)
        readonly ENABLE_ANSIBLE=1
        ;;
      docker)
        readonly ENABLE_DOCKER=1
        ;;
      golang)
        readonly ENABLE_GOLANG=1
        ;;
      digitalocean)
        readonly ENABLE_DO=1
        ;;
      aws)
        readonly ENABLE_AWS=1
        ;;
      gcloud)
        readonly ENABLE_GCLOUD=1
        ;;
      habitat)
        readonly ENABLE_HABITAT=1
        ;;
      hyper)
        readonly ENABLE_HYPER=1
        ;;
      kops)
        readonly ENABLE_KOPS=1
        ;;
      kubectl)
        readonly ENABLE_KUBE_UTILS=1
        ;;
      kube-aws)
        readonly ENABLE_KUBE_AWS=1
        ;;
      node)
        readonly ENABLE_NODE=1
        ;;
      proto-buf)
        readonly ENABLE_PROTO_BUF=1
        ;;
      serverless)
        readonly ENABLE_SERVERLESS=1
        ;;
      terraform)
        readonly ENABLE_TERRAFORM=1
        ;;
      vim)
        readonly ENABLE_VIM=1
        ;;
      h|help)
        usage
        exit 0
        ;;
      ?)
        error "Syntax error: Unknown short option '$OPTARG'" >&2
        exit 1
        ;;
      *)
        error "Syntax error: Unknown long option '$opt'" >&2
        exit 2
        ;;
    esac
    break; done
  done

}


distro_check()
{
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


binfiles()
{
  echo ""
  inf "Copying binfiles..."
  echo ""
  mkdir -p "/home/$DEV_USER/bin"
  cp -R "$PROGDIR/binfiles/." "/home/$DEV_USER/bin"
}


dotfiles()
{
  echo ""
  inf "Copying dotfiles..."
  echo ""

  # handle .bashrc
  if [ -f "/home/$DEV_USER/.bashrc" ]; then
    if [ ! -f "/home/$DEV_USER/.bashrc-orig" ]; then
      inf "Backing up .bashrc file"
      cp "/home/$DEV_USER/.bashrc" "/home/$DEV_USER/.bashrc-orig"

      if [ -f "$PROGDIR/dotfiles/bashrc" ]; then
        inf "Copying new Debian-based .bashrc file"
        cp "$PROGDIR/dotfiles/bashrc" "/home/$DEV_USER/.bashrc"
      fi
    else
      cp "/home/$DEV_USER/.bashrc" "/home/$DEV_USER/.bashrc-$TODAY"
    fi
  fi

  # handle .profile
  if [ -f "/home/$DEV_USER/.profile" ]; then
    if [ ! -f "/home/$DEV_USER/.profile-orig" ]; then
      inf "Backing up .profile file"
      cp "/home/$DEV_USER/.profile" "/home/$DEV_USER/.profile-orig"

      if [ -f "$PROGDIR/dotfiles/profile" ]; then
        inf "Copying new .profile file"
        cp "$PROGDIR/dotfiles/profile" "/home/$DEV_USER/.profile"
      fi
    else
      cp "/home/$DEV_USER/.bashrc" "/home/$DEV_USER/.profile-$TODAY"
    fi
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
  cd "$inst_dir" || exit 1

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

  ## Git
  git clone http://github.com/tpope/vim-git

  ## Terraform
  git clone http://github.com/hashivim/vim-terraform

  ## gotests
  git clone https://github.com/buoto/gotests-vim

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
    ycm_opts="--gocode-completer --tern-completer"
  fi
    ycm_opts="--all"

  sh -c "$inst_dir/youcompleteme/install.py $ycm_opts"
}


install_git_subrepo()
{
  echo ""
  inf "Installing git-subrepo..."
  echo ""

  # pull down git-subrepo
  if [ -d "/home/$DEV_USER/projects/git-subrepo" ]; then
    cd /home/$DEV_USER/projects/git-subrepo; git pull
  else
    git clone https://github.com/ingydotnet/git-subrepo "/home/$DEV_USER/projects/git-subrepo"
  fi

  if [ -f "/home/$DEV_USER/.bash_profile" ]; then
    inf "Setting up .bash_profile"
    grep -q -F 'git-subrepo' "/home/$DEV_USER/.bash_profile" || echo 'source "$HOME/projects/git-subrepo/.rc"' >> "/home/$DEV_USER/.bash_profile"
  else
    inf "Setting up .profile"
    grep -q -F 'git-subrepo' "/home/$DEV_USER/.profile" || echo 'source "$HOME/projects/git-subrepo/.rc"' >> "/home/$DEV_USER/.profile"
  fi
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


### Habitat
# https://www.habitat.sh/docs/get-habitat/
###
install_habitat()
{
  echo ""
  inf "Installing Habitat..."
  echo ""

  local install=0

  if command_exists hab; then
    if [ $(hab --version | awk '{ print $2; exit }') == "${HABITAT_VER}/${HABITAT_VER_TS}" ]; then
      warn "habitat is already installed."
      install=2
    else
      inf "habitat is already installed...but versions don't match"
      $SH_C 'rm /usr/local/bin/hab'
      install=1
    fi
  fi

  if [ $install -le 1 ]; then
    wget -O /tmp/habitat.tar.gz \
      "https://bintray.com/habitat/stable/download_file?file_path=linux%2Fx86_64%2Fhab-${HABITAT_VER}-${HABITAT_VER_TS}-x86_64-linux.tar.gz"
    tar zxvf /tmp/habitat.tar.gz -C /tmp

    chmod +x "/tmp/hab-${HABITAT_VER}-${HABITAT_VER_TS}-x86_64-linux/hab"
    $SH_C "mv /tmp/hab-${HABITAT_VER}-${HABITAT_VER_TS}-x86_64-linux/hab /usr/local/bin/hab"

    rm -rf "/tmp/hab-${HABITAT_VER}-${HABITAT_VER_TS}-x86_64-linux"
    rm /tmp/habitat.tar.gz

    # set up hab group and user.
    # also add non-privileged user to hab group
    if [ $install -eq 0 ]; then
      $SH_C "groupadd hab"
      $SH_C "useradd -g hab hab"

      if [ "$DEFAULT_USER" == 'root' ]; then
        chown -R "$DEV_USER:$DEV_USER" /usr/local/bin
        usermod -a -G hab "$DEV_USER"
      else
        $SH_C "usermod -a -G hab $DEV_USER"
      fi

      # User must log off for these changes to take effect
      LOGOFF_REQ=1
    fi
  fi

  if [ "$DEFAULT_USER" == 'root' ]; then
    chown -R "$DEV_USER:$DEV_USER" /usr/local/bin
  else
    $SH_C "chown root:root /usr/local/bin/hab"
  fi
}


### Terraform
# https://www.terraform.io/intro/getting-started/install.html
###
install_terraform()
{
  echo ""
  inf "Installing Terraform..."
  echo ""

  local install=0

  if command_exists terraform; then
    if [ $(terraform version | awk '{ print $2; exit }') == "v$TERRAFORM_VER" ]; then
      warn "terraform is already installed."
      install=1
    else
      inf "terraform is already installed...but versions don't match"
      $SH_C 'rm /usr/local/bin/terraform'
    fi
  fi

  if [ $install -eq 0 ]; then
    wget -O /tmp/terraform.zip \
      "https://releases.hashicorp.com/terraform/${TERRAFORM_VER}/terraform_${TERRAFORM_VER}_linux_amd64.zip"
    $SH_C 'unzip /tmp/terraform.zip -d /usr/local/bin'

    rm /tmp/terraform.zip
  fi

  if [ "$DEFAULT_USER" == 'root' ]; then
    chown -R "$DEV_USER:$DEV_USER" /usr/local/bin
  fi
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


### aws cli
# http://docs.aws.amazon.com/cli/latest/userguide/installing.html
###
install_aws()
{
  echo ""
  inf "Installing AWS CLI..."
  echo ""

  local inst_dir="/home/$DEV_USER/.aws"

  mkdir -p "$inst_dir"
  cp "$PROGDIR/aws/config.tpl" "$inst_dir/"
  cp "$PROGDIR/aws/credentials.tpl" "$inst_dir/"

  if command_exists aws; then
    #local version="$(aws --version | awk '{ print $2; exit }')"
    local version="$(aws --version)"
    warn "aws cli is already installed...attempting upgrade"
    $SH_C 'pip install --upgrade awscli'
  else
    $SH_C 'pip install awscli'
  fi

  if [ "$DEFAULT_USER" == 'root' ]; then
    chown -R "$DEV_USER:$DEV_USER" "$inst_dir"
  fi
}


### kops
# https://github.com/kubernetes/kops#linux
###
install_kops()
{
  echo ""
  inf "Installing Kubernetes Kops..."
  echo ""

  local inst_dir="/usr/local/bin"

  if command_exists kops; then
    warn "kops is already installed...will re-install"
    $SH_C 'rm /usr/local/bin/kops'
  fi

  wget -O /tmp/kops "https://github.com/kubernetes/kops/releases/download/${KOPS_VER}/kops-linux-amd64"
  chmod +x /tmp/kops
  $SH_C 'mv /tmp/kops /usr/local/bin/kops'
}


### hyper.sh
# https://www.hyper.sh/
###
install_hyper()
{
  echo ""
  inf "Installing Hyper.sh..."
  echo ""

  local inst_dir="/usr/local/bin"

  if command_exists hyper; then
    warn "hyper is already installed...will re-install"
    $SH_C 'rm /usr/local/bin/hyper'
  fi

  wget -O /tmp/hyper-linux.tar.gz \
    "https://hyper-install.s3.amazonaws.com/hyper-linux-x86_64.tar.gz"
  tar zxvf /tmp/hyper-linux.tar.gz -C /tmp

  chmod +x /tmp/hyper
  $SH_C 'mv /tmp/hyper /usr/local/bin/hyper'
  rm /tmp/hyper-linux.tar.gz
}


### DigitalOcean doctl
# https://www.digitalocean.com/community/tutorials/how-to-use-doctl-the-official-digitalocean-command-line-client
###
install_doctl()
{
  echo ""
  inf "Installing DigitalOcean doctl..."
  echo ""

  local inst_dir="/usr/local/bin"

  if command_exists doctl; then
    warn "doctl is already installed...will re-install"
    $SH_C 'rm /usr/local/bin/doctl'
  fi

  wget -O /tmp/doctl-linux.tar.gz \
    https://github.com/digitalocean/doctl/releases/download/v${DOCTL_VER}/doctl-${DOCTL_VER}-linux-amd64.tar.gz
  tar zxvf /tmp/doctl-linux.tar.gz -C /tmp

  chmod +x /tmp/doctl
  $SH_C 'mv /tmp/doctl /usr/local/bin/doctl'
  rm /tmp/doctl-linux.tar.gz
}


### CoreOS kube-aws
# https://coreos.com/kubernetes/docs/latest/kubernetes-on-aws.html#download-kube-aws
###
install_kube_aws()
{
  echo ""
  inf "Installing CoreOS kube-aws..."
  echo ""

  local inst_dir="/usr/local/bin"

  # Import the CoreOS Application Signing Public Key
  gpg2 --keyserver pgp.mit.edu --recv-key FC8A365E

  # Validated imported key
  #gpg2 --fingerprint FC8A365E | grep -i "18AD 5014 C99E F7E3 BA5F 6CE9 50BD D3E0 FC8A 365E"

  if command_exists kube-aws; then
    warn "kube-aws is already installed...will re-install"
    $SH_C 'rm /usr/local/bin/kube-aws'
  fi

  wget -O /tmp/kube-aws.tar.gz "https://github.com/kubernetes-incubator/kube-aws/releases/download/v${KUBE_AWS_VER}/kube-aws-linux-amd64.tar.gz"
  tar zxvf /tmp/kube-aws.tar.gz -C /tmp

  chmod +x /tmp/linux-amd64/kube-aws
  $SH_C 'mv /tmp/linux-amd64/kube-aws /usr/local/bin/kube-aws'
  rm /tmp/kube-aws.tar.gz
  rm -rf /tmp/linux-amd64
}


### kubectl cli
# http://kubernetes.io/docs/user-guide/prereqs/
###
install_kubectl()
{
  echo ""
  inf "Installing kubectl CLI..."
  echo ""

  if command_exists kubectl; then
    warn "kubectl is already installed...will re-install"
    $SH_C 'rm /usr/local/bin/kubectl'
  fi

  wget -O /tmp/kubernetes.tar.gz "https://github.com/kubernetes/kubernetes/releases/download/v${KUBE_VER}/kubernetes.tar.gz"
  tar -zxvf /tmp/kubernetes.tar.gz -C /tmp
  $SH_C 'cp /tmp/kubernetes/platforms/linux/amd64/kubectl /usr/local/bin/kubectl'
  rm /tmp/kubernetes.tar.gz
  rm -rf /tmp/kubernetes
}


### helm cli
# https://github.com/kubernetes/helm
###
install_helm()
{
  echo ""
  inf "Installing helm CLI..."
  echo ""

  local inst_dir="/usr/local/bin"

  if command_exists helm; then
    warn "helm is already installed...will re-install"
    $SH_C 'rm /usr/local/bin/helm'
    $SH_C 'rm /usr/local/bin/tiller'
  fi

  wget -O /tmp/helm.tar.gz "https://github.com/kubernetes/helm/releases/download/v${HELM_VER}/helm-v${HELM_VER}-linux-amd64.tar.gz"
  tar -zxvf /tmp/helm.tar.gz -C /tmp
  $SH_C 'cp /tmp/linux-amd64/helm /usr/local/bin/'
  $SH_C 'cp /tmp/linux-amd64/tiller /usr/local/bin/'
  rm /tmp/helm.tar.gz
  rm -rf "/tmp/linux-amd64"
}


### cfssl cli
# https://cfssl.org/
###
install_cfssl()
{
  echo ""
  inf "Installing CloudFlare's PKI toolkit..."
  echo ""

  if command_exists cfssl; then
    warn "cfssl is already installed."
  else
    wget -O /tmp/cfssl_linux-amd64 "https://pkg.cfssl.org/R${CFSSL_VER}/cfssl_linux-amd64"
    chmod +x /tmp/cfssl_linux-amd64
    $SH_C 'mv /tmp/cfssl_linux-amd64 /usr/local/bin/cfssl'
  fi

  if command_exists cfssljson; then
    warn "cfssljson is already installed."
  else
    wget -O /tmp/cfssljson_linux-amd64 "https://pkg.cfssl.org/R${CFSSL_VER}/cfssljson_linux-amd64"
    chmod +x /tmp/cfssljson_linux-amd64
    $SH_C 'mv /tmp/cfssljson_linux-amd64 /usr/local/bin/cfssljson'
  fi
}


### protocol buffers
# https://developers.google.com/protocol-buffers/
###
install_protobuf()
{
  echo ""
  inf "Installing protocol buffers..."
  echo ""
  local install_proto=0

  if command_exists protoc; then
    if [ $(protoc --version | awk '{ print $2; exit }') == "$PROTOBUF_VER" ]; then
      warn "protoc is already installed."
      install_proto=1
    else
      inf "protoc is already installed...but versions don't match"
    fi
  fi

  if [ $install_proto -eq 0 ]; then
    wget -O /tmp/protoc.tar.gz "https://github.com/google/protobuf/archive/v${PROTOBUF_VER}.tar.gz"
    tar -zxvf /tmp/protoc.tar.gz -C /tmp
    rm /tmp/protoc.tar.gz
    cd "/tmp/protobuf-${PROTOBUF_VER}" || exit 1
    ./autogen.sh
    ./configure
    make
    make check

    if [ "$DEFAULT_USER" != 'root' ]; then
      sudo make install
      sudo ldconfig
    else
      make install
      ldconfig
    fi

    rm -rf "/tmp/linux-amd64"
    cd -
  fi
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
  distro_check
  valid_args
  prerequisites
  base_setup
  binfiles
  dotfiles
  install_git_subrepo
  install_cfssl

  # golang handler
  if [ -n "$ENABLE_GOLANG" ]; then
    enable_golang
  fi

  # terraform handler
  if [ -n "$ENABLE_TERRAFORM" ]; then
    install_terraform
  fi

  # gcloud handler
  if [ -n "$ENABLE_GCLOUD" ]; then
    enable_gcloud
  fi

  # aws handler
  if [ -n "$ENABLE_AWS" ]; then
    install_aws
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

  # kubectl & helm handler
  if [ -n "$ENABLE_KUBE_UTILS" ]; then
    install_kubectl
    install_helm
  fi

  # protobuf support (compile from source)
  if [ -n "$ENABLE_PROTO_BUF" ]; then
    install_protobuf
  fi

  if [ -n "$ENABLE_NODE" ]; then
    install_node
  fi

  # kops handler
  if [ -n "$ENABLE_KOPS" ]; then
    install_terraform
    install_kops
  fi

  # kube-aws handler
  if [ -n "$ENABLE_KUBE_AWS" ]; then
    install_aws
    install_kube_aws
  fi

  if [ -n "$ENABLE_SERVERLESS" ]; then
    install_node
    install_serverless
  fi

  if [ -n "$ENABLE_HYPER" ]; then
    install_hyper
  fi

  if [ -n "$ENABLE_DO" ]; then
    install_doctl
  fi

  if [ -n "$ENABLE_HABITAT" ]; then
    install_habitat
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
