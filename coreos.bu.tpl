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
        - docker


storage:
  disks:
    - device: $inject_drive0
      wipe_table: false
      partitions:
        - label: root
          number: 4
          size_mib: 32768
          resize: true

        - label: swap
          number: 5
          size_mib: 32768

        - label: config
          number: 6
          size_mib: 32768

        - label: backup
          number: 7
          size_mib: 65536

        - label: log
          number: 8

    - device: $inject_drive1
      partitions:
        - label: data-1
          number: 1

    - device: $inject_drive2
      partitions:
        - label: data-2
          number: 1


  raid:
    - name: md-data
      level: raid1
      devices:
        - /dev/disk/by-partlabel/data-1
        - /dev/disk/by-partlabel/data-2


  filesystems:
    - device: /dev/md/md-data
      path: /var/data
      label: data
      format: xfs
      with_mount_unit: true

    - device: /dev/disk/by-partlabel/swap
      format: swap
      wipe_filesystem: true
      with_mount_unit: true

    - device: /dev/disk/by-partlabel/config
      path: /etc/config
      format: xfs
      label: config
      wipe_filesystem: true
      with_mount_unit: true

    - device: /dev/disk/by-partlabel/backup
      path: /var/backup
      format: xfs
      label: backup
      with_mount_unit: true

    - device: /dev/disk/by-partlabel/log
      path: /var/log
      label: log
      format: xfs
      with_mount_unit: true


  directories:
    - path: /etc/sysupdate.d
    - path: /var/lib/extensions
    - path: /var/lib/extensions.d


  files:
    - path: /etc/hostname
      mode: 0644
      contents:
        inline: helium

    - path: /etc/hosts
      append:
        - inline: {{ op://homelab/nfs/IP }} {{ op://homelab/nfs/URL }}

    - path: /etc/profile.d/zz-default-editor.sh
      overwrite: true
      contents:
        inline: |
          export EDITOR=vim

    - path: /var/lib/extensions/tailscale.raw
      contents:
        source: https://extensions.fcos.fr/extensions/tailscale/tailscale-$tailscale_version-x86-64.raw
        verification:
          hash: sha256-$tailscale_verification_hash

    - path: /etc/tailscale.authkey
      mode: 0400
      contents:
        inline: "{{ op://homelab/tailscale ephemeral authkey/credential }}?preauthorized=true"


systemd:
  units:
    - name: serial-getty@ttyS0.service
      dropins:
      - name: autologin-core.conf
        contents: |
          [Service]
          ExecStart=
          ExecStart=-/usr/sbin/agetty --autologin core --noclear %I $TERM

    - name: rpm-ostree-install-vim.service
      enabled: true
      contents: |
        [Unit]
        Description=Layer vim with rpm-ostree
        Wants=network-online.target
        After=network-online.target
        Before=zincati.service
        ConditionPathExists=!/var/lib/%N.stamp

        [Service]
        Type=oneshot
        RemainAfterExit=yes
        ExecStart=/usr/bin/rpm-ostree install -y --allow-inactive vim
        ExecStart=/bin/touch /var/lib/%N.stamp
        ExecStart=/bin/systemctl --no-block reboot

        [Install]
        WantedBy=multi-user.target

    - name: systemd-sysext.service
      enabled: true

    - name: tailscaled.service
      enabled: true
      dropins:
      - name: 20-ephemeral.conf
        contents: |
          [Service]
          EnvironmentFile=
          ExecStart=
          ExecStart=/usr/bin/tailscaled --state=mem: --socket=/run/tailscale/tailscaled.sock --port='41641'

    # TODO: use systemd credentials instead of emplacing authkey directly
    - name: tailscale-up.service
      enabled: false
      contents: |
        [Unit]
        Description=Perform headless login to tailscale
        After=tailscaled.service
        
        [Service]
        Type=oneshot
        ExecStart=-/usr/bin/tailscale up --authkey='file:/etc/tailscale.authkey' --advertise-tags='tag:{{ op://homelab/tailscale ephemeral authkey/advertise-tag }}'
        User=root
        RemainAfterExit=yes

    - name: tailscale-up.path
      enabled: true
      contents: |
        [Unit]
        Description=Watch tailscaled socket to trigger tailscale login
        After=tailscaled.service
        
        [Path]
        PathExists=/run/tailscale/tailscaled.sock
        Unit=tailscale-up.service
        
        [Install]
        WantedBy=multi-user.target

    - name: var-nfs.mount
      enabled: true
      contents: |
        [Unit]
        Before=remote-fs.target
        [Mount]
        What={{ op://homelab/nfs/URL }}:{{ op://homelab/nfs/path }}
        Where=/var/nfs
        Type=nfs
        [Install]
        WantedBy=remote-fs.target
