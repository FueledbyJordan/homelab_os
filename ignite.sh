#!/usr/bin/env bash

set -euo pipefail

error() {
  declare RED=$'\033[0;31m'
  declare NC=$'\033[0m'
  printf '❌ %s%s%s\n' "${RED}" "${1}" "${NC}"
}

fatal() {
  error "${1}"
  exit 1
}

warn() {
  declare YELLOW=$'\033[0;33m'
  declare NC=$'\033[0m'
  printf '⚠️ %s%s%s\n' "${YELLOW}" "${1}" "${NC}"
}

usage() {
  echo "Usage: $0 [OPTIONS]"
  echo 'Options:'
  echo '  --skip-liveboot-wipe    Skip the liveboot wipe process'
  echo '  -h, --help              Display this help message'
  exit 1
}

main() {
  declare skip_liveboot_wipe=false
  
  while [[ $# -gt 0 ]]; do
    case $1 in
      --skip-liveboot-wipe)
        skip_liveboot_wipe=true
        shift
        ;;
      -h|--help)
        usage
        ;;
      *)
        echo "Unknown option: $1"
        usage
        ;;
    esac
  done

  echo '✅ Performing runtime environment checks'
  declare -a required_tools=('op' 'docker' 'grep' 'cat' 'envsubst' 'wget' 'rm' 'curl' 'ssh')
  for tool in "${required_tools[@]}"
  do
    command -v "${tool}" &>/dev/null || fatal "${tool} is not installed"
  done

  pikvm_hostname="$(op read 'op://homelab/pikvm/hostname')"
  pikvm_api_credentials="$(op read 'op://homelab/pikvm/username'):$(op read 'op://homelab/pikvm/password')"
  user="$(op read 'op://homelab/server/username')"
  host="$(op read 'op://homelab/server/hostname')"
  
  [ ! -f .env ] && fatal '.env file does not exist!'
  
  echo '✅ Reading variables from .env file'
  # deliberate word splitting to ensure env is properly set
  # shellcheck disable=2046
  export $(grep -v '^#' .env | xargs)
  
  [[ -z ${inject_file_server+x} ]] && fatal 'inject_file_server is unset. Did you set it in .env?'
  [[ -z ${inject_drive0+x} ]] && fatal 'inject_drive0 is unset. Did you set it in .env?'
  [[ -z ${inject_drive1+x} ]] && fatal 'inject_drive1 is unset. Did you set it in .env?'
  [[ -z ${inject_drive2+x} ]] && fatal 'inject_drive2 is unset. Did you set it in .env?'

  echo '✅ Starting up local file server...'
  docker compose up -d &>/dev/null
  
  echo '✅ Generating ignition files...'
  cat bootstrap.bu.tpl | envsubst | op inject | docker run --rm -i quay.io/coreos/butane:release > files/bootstrap.ign
  cat coreos.bu.tpl | envsubst | op inject | docker run --rm -i quay.io/coreos/butane:release > files/coreos.ign
  
  [ ! -f ./files/${fcos_iso} ] && \
    echo '✅ Fetching CoreOS ISO...' && \
    wget -P ./files "${fcos_iso_url}"
  
  rm -f "./files/${embedded_fcos_iso}"
  
  # TODO: disconnect MSD in live environment following successful image
  echo '✅ Customizing CoreOS live boot environment...'
  cat files/bootstrap.ign | docker run --rm -i --user "$(id -u):$(id -g)" -v ./files:/files quay.io/coreos/coreos-installer:release iso ignition embed -o "/files/${embedded_fcos_iso}" "/files/${fcos_iso}"
  
  echo '✅ Disconnecting mass storage device...'
  
  curl -s -o /dev/null -X POST -k \
    -u "${pikvm_api_credentials}" \
    "https://${pikvm_hostname}/api/msd/set_connected?connected=0"
  
  if ! $skip_liveboot_wipe; then
    echo '✅ Cleaning up old liveboot image...'
    curl -s -o /dev/null -X POST -k \
      -u "${pikvm_api_credentials}" \
      "https://${pikvm_hostname}/api/msd/remove?image=coreos-liveboot.iso"
    
    echo '✅ Waiting for image to be cleaned...'
    sleep 3
    
    echo '✅ Writing new liveboot image...'
    pushd ./files &>/dev/null && \
      curl -s -o /dev/null --progress-bar -X POST -k \
        --progress-bar \
        -u "${pikvm_api_credentials}" \
        -H 'Accept: */*' \
        -H 'Accept-Encoding: gzip, deflate, br, zstd' \
        -H 'Connection: keep-alive' \
        -H 'Priority: u=0' \
        --data-binary @${embedded_fcos_iso} \
        "https://${pikvm_hostname}/api/msd/write?prefix=&image=coreos-liveboot.iso&remove_incomplete=1" && \
    popd &>/dev/null
    
    echo '✅ Activating new liveboot image...'
    curl -s -o /dev/null -X POST -k \
      -u "${pikvm_api_credentials}" \
      "https://${pikvm_hostname}/api/msd/set_params?image=coreos-liveboot.iso&cdrom=0"
  fi
  
  echo '✅ Connecting mass storage device...'
  curl -s -o /dev/null -X POST -k \
    -u "${pikvm_api_credentials}" \
    "https://${pikvm_hostname}/api/msd/set_connected?connected=1"
  
  echo '✅ Attempting to reboot target host...'
  # TODO: on failure of reboot, issue pikvm reboot; need to acquire a switched pdu
  ssh "${user}@${host}" "sudo reboot" &>/dev/null || \
    error "Failed to reboot ${host}, you will need to manually reboot"
  
  rm -f "./files/${embedded_fcos_iso}"
  
  # TODO: on completion of first boot, run job to do this
  warn 'ensure to clean up contents of ./files'
  warn 'remember to docker compose down'
  warn 'remember to clean up any firewall rules made'
}

fcos_version='42.20250705.3.0'
fcos_iso="fedora-coreos-${fcos_version}-live-iso.x86_64.iso"
fcos_iso_url="https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/${fcos_version}/x86_64/${fcos_iso}"
embedded_fcos_iso="embedded-${fcos_iso}"

# TODO: add this version to renovate
# Obtained from https://github.com/travier/fedora-sysexts/releases/tag/tailscale on 2025-08-08.
export tailscale_version='0-1.86.2-1-42'
export tailscale_verification_hash='652655ec2430f76b64ecb236ab6c1d603ea374c62615c5e8d15401f1c5f05c40'

main "${@}"
