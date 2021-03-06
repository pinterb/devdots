
# SOFTWARE VERSIONS
# (Last Checked On: 2018-02-23)
DRAFT_VER="v0.16.0"  ## Draft is in fish. Candidate for removal?
PROTOBUF_VER="3.7.1"
PROTOTOOL_VER="1.4.0"
UP_VER="v0.7.2"
GOLANG_VER="1.12.5" ## Golang is in fish. Candidate for removal?
HELM_VER="v2.12.2" ## Helm is in fish. Candidate for removal?
MINIKUBE_VER="v0.35.0" ## Minikube is in fish. Candidate for removal?
TERRAFORM_VER="v0.11.13"
TERRAGRUNT_VER="v0.18.3"
CFSSL_VER="1.3.3"
KOPS_VER="1.9.0"
KUBE_VER="v1.11.1"
DOCTL_VER="v1.14.0"
#DOCKER_VER="17.03.2" # this version is compatiable w/k8s v1.9
DOCKER_VER="18.03.1" # this version is compatiable w/k8s v1.9
HABITAT_VER="0.56.0"
HABITAT_VER_TS="20180530234036"
ANSIBLE_VER="2.4.0"
AZURE_VER="2.0.60"
NGROK_VER="2.2.6"
JFROG_VER="1.23.2"
INSPEC_VER="3.0.52"
BAZEL_VER="0.23.2"
JENKINSX_VER="v1.3.1023"
GORELEASER_VER="v0.70.0"
FISSION_VER="1.1.0"
K8S_SEALED_SECRETS_VER="v0.7.0"
KUSTOMIZE_VER="1.0.11"
RUSTUP_VER="1.14.0"
RUSTC_VER="1.29.2"
PULUMI_VER="0.16.4"
SKAFFOLD_VER="0.15.1"
TELEPRESENCE_VER="0.93"
RBENV_VER="1.1.1-39-g59785f6"
SDKMAN_VER="5.7.3+337"
KUBEBUILDER_VER="1.0.7"
KREW_VER="0.2.1"
OPA_VER="0.10.3"
TILT_VER="0.5.1"
STEP_CLI_VER="0.8.6"
STEP_CERT_VER="0.8.5"
GITCOMM_VER="0.3.4"
GO_SWAGGER_VER="0.19.0"

# https://cloud.google.com/sdk/downloads#versioned
GCLOUD_VER="219.0.1"
GCLOUD_CHECKSUM="ba914c0ab0d7196d1f5d29a99fff4c6411072609ae42790b42739109b1c73300"

# https://bosh.io/docs/cli-v2#install
BOSH_VER="2.0.48"
BOSH_CHECKSUM="c807f1938494f4280d65ebbdc863eda3f883d72e"

# Candidates for removal
KUBE_AWS_VER="0.9.7-rc.2"


# Get distro data from /etc/os-release
if [ -f /etc/lsb-release ]; then
    . /etc/lsb-release
    DISTRO_ID=$DISTRIB_ID
    DISTRO_VER=$DISTRIB_RELEASE
elif [ -f /etc/debian_version ]; then
    DISTRO_ID=Debian
    DISTRO_VER=$(cat /etc/debian_version)
elif [ -f /etc/centos-release ]; then
    DISTRO_ID=$(awk '{print $1}' /etc/centos-release)
    DISTRO_VER=$(awk '{print $4}' /etc/centos-release)
elif [ -f /etc/redhat-release ]; then
    DISTRO_ID=RHEL
    DISTRO_VER=$(awk '{print $7}' /etc/redhat-release)
elif [ -f /etc/os-release ]; then
    DISTRO_ID=$(awk -F'=' '/NAME/ {print $2; exit}' /etc/os-release)
    DISTRO_VER=$(awk -F'=' '/VERSION_ID/ {print $2}' /etc/os-release | tr -d '"')
else
    DISTRO_ID=$(uname -s)
    DISTRO_VER=$(uname -r)
fi

readonly TRUE=0
readonly FALSE=1

readonly CLOUD_PROVIDER=$([ -f /sys/class/dmi/id/bios_vendor ] && cat /sys/class/dmi/id/bios_vendor)

# physical memory
readonly MEM_TOTAL_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')

# sys_arch discovers the architecture for this system.
sys_arch() {
  ARCH=$(uname -m)
  case $ARCH in
    armv5*) ARCH="armv5";;
    armv6*) ARCH="armv6";;
    armv7*) ARCH="armv7";;
    aarch64) ARCH="arm64";;
    x86) ARCH="386";;
    x86_64) ARCH="amd64";;
    i686) ARCH="386";;
    i386) ARCH="386";;
  esac
}

# Set the host's OS. Only linux supported for now
HOSTOS=$(uname -s | tr '[:upper:]' '[:lower:]')

##
# determine if this script is running on a Microsoft WSL version of Linux
# https://stackoverflow.com/questions/38086185/how-to-check-if-a-program-is-run-in-bash-on-ubuntu-on-windows-and-not-just-plain
microsoft_wsl() {
  grep -qE "(Microsoft|WSL)" /proc/version &> /dev/null
}

# For non-privileged users, this may be our default user
DEFAULT_USER="$(id -un 2>/dev/null || true)"

MYINDENT="  "
bump_indent() {
  MYINDENT="  $MYINDENT"
}

reset_indent() {
  MYINDENT="  "
}

set_indent() {
  MYINDENT="$1"
}

warn() {
  echo -e "\033[1;33m$MYINDENT+ WARNING: $1\033[0m"
}

error() {
  echo -e "\033[0;31m$MYINDENT+ ERROR: $1\033[0m"
}

inf() {
  echo -e "\033[0;32m$MYINDENT+ $1\033[0m"
}

cmd_inf() {
  echo -e "\033[0;32m$MYINDENT  ++ $1\033[0m"
}

hdr() {
  echo -e "\033[0;32m$1\033[0m"
  reset_indent
}

follow() {
  inf "Following docker logs now. Ctrl-C to cancel."
  docker logs --follow $1
}

run_command() {
  inf "Running:\n $1"
  eval $1 &> /dev/null
}

# Given a relative path, calculate the absolute path
absolute_path() {
  pushd "$(dirname $1)" > /dev/null
  local abspath="$(pwd -P)"
  popd > /dev/null
  echo "$abspath/$(basename $1)"
}

command_exists() {
  command -v "$@" > /dev/null 2>&1
}

function_exists() {
  #type -t "$@" && type -t "$@" | grep -q '^function$' > /dev/null 2>&1
  if [[ $(type -t "$@" 2>/dev/null) == function ]]; then
    return 0
  else
    return 1
  fi
}

mark_dotprofile_as_touched() {
  if [ "$DEFAULT_USER" == 'root' ]; then
    su -c "mkdir -p /home/$DEV_USER/.bootstrap/touched-dotprofile" "$DEV_USER"
    su -c "echo 'modified by install script' > /home/$DEV_USER/.bootstrap/touched-dotprofile/$@" "$DEV_USER"
  else
    mkdir -p "/home/$DEV_USER/.bootstrap/touched-dotprofile"
    echo 'modified by install script' > "/home/$DEV_USER/.bootstrap/touched-dotprofile/$@"
  fi
}

is_backed_up() {
  local bkup="${1:-orig}"

  if [ -d "/home/$DEV_USER/.bootstrap/backup/$bkup" ]; then
    return 0
  else
    return 1
  fi
}

is_installed() {
  if [ ! -d "/home/$DEV_USER/.bootstrap/installed" ]; then
    return 1
  fi

  if [ -f "/home/$DEV_USER/.bootstrap/installed/$1" ]; then
    return 0
  else
    return 1
  fi
}

mark_as_installed() {

  if [ ! -d "/home/$DEV_USER/.bootstrap/installed" ]; then
   # if [ "$DEFAULT_USER" == 'root' ]; then
   #   su -c "mkdir -p /home/$DEV_USER/.bootstrap/installed" "$DEV_USER"
   # else
   #   bash -c "mkdir -p /home/$DEV_USER/.bootstrap/installed"
   # fi
    exec_cmd "mkdir -p /home/$DEV_USER/.bootstrap/installed"
  fi

  exec_cmd "touch /home/$DEV_USER/.bootstrap/installed/$1"
  exec_cmd "chown -R $DEV_USER:$DEV_USER /home/$DEV_USER/.bootstrap/installed/$1"

#  if [ "$DEFAULT_USER" == 'root' ]; then
#    su -c "touch /home/$DEV_USER/.bootstrap/installed/$1" "$DEV_USER"
#  else
#    bash -c "touch /home/$DEV_USER/.bootstrap/installed/$1"
#  fi
}

mark_as_uninstalled() {
  exec_cmd "rm -rf /home/$DEV_USER/.bootstrap/installed/$1"
}

semverParse() {
  major="${1%%.*}"
  minor="${1#$major.}"
  minor="${minor%%.*}"
  patch="${1#$major.$minor.}"
  patch="${patch%%[-.]*}"
}

is_minikube_stopped() {
  return $(test minikube status | awk 'FNR == 1 {print}' | awk -Fminikube: '{print $2}' | grep -q Stopped)
}

is_minikube_running() {
  return $(test minikube status | awk 'FNR == 1 {print}' | awk -Fminikube: '{print $2}' | grep -q Stopped)
}


