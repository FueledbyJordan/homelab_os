variant: fcos
version: 1.6.0

passwd:
  users:
    - name: {{ op://homelab/server/username }}
      password_hash: "{{ op://homelab/server/password_hash }}"
      ssh_authorized_keys:
        - "{{ op://Private/SSH Key/public key }} {{ op://Private/SSH Key/email }}"
      groups:
        - sudo
        - wheel

storage:
  files:
    - path: /etc/coreos/installer.d/custom.yaml
      contents:
        inline: |
          ignition-url: $inject_file_server/coreos.ign
          insecure-ignition: true
          dest-device: $inject_drive0
