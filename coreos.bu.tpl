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

    - path: /etc/yum.repos.d/rancher-k3s-common.repo
      mode: 0644
      contents:
        inline: |
          [rancher-k3s-common-stable]
          name=Rancher K3s Common (stable)
          baseurl=https://rpm.rancher.io/k3s/stable/common/coreos/noarch
          enabled=1
          gpgcheck=1
          repo_gpgcheck=0
          gpgkey=https://rpm.rancher.io/public.key

    - path: /usr/local/bin/k3s
      overwrite: true
      mode: 0755
      contents:
        source: "https://github.com/k3s-io/k3s/releases/download/v1.33.3%2Bk3s1/k3s"
        verification:
          hash: "sha256-f03cad6610cf5b2903d8a9ac3d6716690e53dab461b09c07b0c913a262166abc"

    - path: /etc/rancher/k3s/kubelet.config
      mode: 0644
      contents:
        inline: |
          apiVersion: kubelet.config.k8s.io/v1beta1
          kind: KubeletConfiguration
          shutdownGracePeriod: 60s
          shutdownGracePeriodCriticalPods: 10s


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

    - name: rpm-ostree-install-k3s-selinux.service
      enabled: true
      contents: |
        [Unit]
        Description=Install k3s selinux
        Wants=network-online.target
        After=network-online.target
        Before=zincati.service
        ConditionPathExists=|!/usr/share/selinux/packages/k3s.pp

        [Service]
        Type=oneshot
        RemainAfterExit=yes
        ExecStart=rpm-ostree install --apply-live --allow-inactive --assumeyes k3s-selinux

        [Install]
        WantedBy=multi-user.target

    - name: rpm-ostree-install-helm.service
      enabled: true
      contents: |
        [Unit]
        Description=Install helm
        Wants=network-online.target
        After=network-online.target
        Before=zincati.service
        ConditionPathExists=|!/usr/bin/helm

        [Service]
        Type=oneshot
        RemainAfterExit=yes
        ExecStart=rpm-ostree install --apply-live --allow-inactive --assumeyes helm

        [Install]
        WantedBy=multi-user.target

    - name: k3s.service
      enabled: true
      contents: |
        [Unit]
        Description=Run K3s
        Wants=network-online.target
        After=network-online.target

        [Service]
        Type=notify
        EnvironmentFile=-/etc/default/%N
        EnvironmentFile=-/etc/sysconfig/%N
        EnvironmentFile=-/etc/systemd/system/%N.env
        KillMode=process
        Delegate=yes
        LimitNOFILE=1048576
        LimitNPROC=infinity
        LimitCORE=infinity
        TasksMax=infinity
        TimeoutStartSec=0
        Restart=always
        RestartSec=5s
        ExecStartPre=-/sbin/modprobe br_netfilter
        ExecStartPre=-/sbin/modprobe overlay
        ExecStart=/usr/local/bin/k3s server --kubelet-arg="config=/etc/rancher/k3s/kubelet.config"

        [Install]
        WantedBy=multi-user.target

    # Node shutdown leaves pods with status.phase=Failed and status.reason=Shutdown,
    # so delete them automatically on startup.
    # This may delete some pods that failed for other reasons, but --field-selector doesn't
    # currently support status.reason, so it's the best we can do.
    - name: k3s-cleanup-shutdown-pods.service
      enabled: true
      contents: |
        [Unit]
        Description=Cleanup pods terminated by node shutdown
        Wants=k3s.service

        [Service]
        Type=oneshot
        Environment=KUBECONFIG=/etc/rancher/k3s/k3s.yaml
        ExecStart=/usr/local/bin/k3s kubectl delete pods --field-selector status.phase=Failed -A --ignore-not-found=true
        Restart=on-failure
        RestartSec=30

        [Install]
        WantedBy=multi-user.target
