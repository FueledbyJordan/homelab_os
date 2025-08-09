# Homelab OS Install

This sets up my homelab that runs [Fedora CoreOS](https://fedoraproject.org/coreos/) on a mini pc.  The goal of this repository is to be a one stop shop for deploying my homelab operating system.

This is a fully unattended install of CoreOS that currently:
* sets up an ephemeral tailscale node.

and will:
* automatically provision k3s
* automatically set up argocd for fetching custom helm charts


## Motivation

In the past, I've ran my homelab on decommissioned enterprise class server hardware (think like a Dell R620). Until Red Hat killed CentOS, I was happily running my homelab on it.  After that, I decided to migrate to fedora.  At my `$DAY_JOB` we use Rocky Linux.  For better or worse, it's safe to say I'm committed to the RHEL ecosystem.

In the past, the workloads I've ran have been docker compose.  At the time of embarking on this project, I've invested 8 years into working with docker compose.

Nothing is inherently wrong with my previous approach, but I'd like to shake it up a bit.  The guiding principals of this approach are as follows:
1. learn something new
2. reduce operational toil
3. have fun along the way


### Learn Something New
At my `$DAY_JOB`, we are on the precipice of adopting a container orchestrator.  I would like to sharpen my skills in the lingua franca of this space, kubernetes.  I will be installing k3s on my homelab.

As part of this overhaul, I would like to try something different than the traditional configuration management approach.  In my previous homelab, I've used ansible to configure the OS as well as emplace my docker compose file that defines the services that I run.  At my `$DAY_JOB` I get to use Chef for managing the fleet of hardware.  Immutable operating systems seem like an interesting alternative to the traditional CM tools.


### Reduce Operational Toil
My needs for my homelab are pretty small.  I run something like 20 services.  At my lab's peak, I was running something on the order of 50 services.  The workload can vary based on my interests at a given time.  One of the biggest pains was keeping things up to date.

Historically, I have managed all services in docker compose.  My previous approach was to have a cronjob that runs once a week to remind me to update my containers.  About once a month, I would run a premade script to do an upgrade.  This ratio of four alerts to one action is not desirable.  In fact, it's not desirable to get a notification at all; instead it would be preferable that the services automatically upgrade, and rollback and notify on failure.  This is a perfectly kubernetes shaped problem.

For the operating system, I would upgrade once every couple of years.  I would put it off because it was painful to upgrade.  I would run some RHEL provided script, and then go modify my ansible playbooks that hardened the OS.  This caused downtime and usually occupied half of a precious weekend day.  This is where an OS such as CoreOS comes in.  The chromeOS-like approach of automatic updates on a minimal surface area is appealing to me.  I like the idea of easy rollbacks as well.  I played with the idea of using NixOS, Flatcar, and CoreOS.  I have previous experience with NixOS, and it's what I daily drive on my laptop.  I believe NixOS requires more onboarding effort than most orgs have appetite for.  For the reason of learning something useful for my `$DAY_JOB`, as well as learning something new, I decided to discard NixOS.  I played with both Flatcar and CoreOS.  Ultimately, I am indifferent between the two; if I choose wrong, I'll simply back out.  So let's try CoreOS for now!


### Have fun along the way

If I'm following the first two tenets, I will probably get this one for free!


## Hardware Profile
Computing power has come a long way since my last homelab hardware refresh.  I am swapping out my previous hardware with a mini pc that takes significantly less power, occupies less space, and packs a much larger punch.  I grabbed all of the hardware here with credit card points (that only diminish in value), but less specced gear should work just as well.

The server running CoreOS consists of:
* [Minisforum MS-A2](https://amzn.to/3HeB6LR)
* 3x [WD\_BLACK 1TB SN8100 NVMe drives](https://amzn.to/47kFRhk)
* 2x [Crucial 64GB DDR5 @5600MHz RAM](https://amzn.to/3UgDGns)

The KVM switch I am using is a [PiKVM V4 Plus](https://amzn.to/45hlejq).  This is heavily utilized by the [ignite.sh script](./ignite.sh).  The script programmatically invokes the [API](https://docs.pikvm.org/api/) to make the imaging process as seamless as possible.

In a later iteration, I intend to add a switched PDU to the mix, as the PiKVM can connect over GPIO and be invoked by an API. [This](https://amzn.to/4ljgUWS) is the one I have my eye on.  This is not strictly necessary; but it would have saved me a few trips to the basement when my machine stopped accepting input (this occurred when getting kernel panics during a live boot install initiated by initrd, and a console session was not available).


## Environment Variables

To run this project, you will need to add some environment files to a `.env` file. There is an example provided in `.env.example`.


## Prerequisites
You will have a much easier time if your recipient host has a static IP.  There are various ways to do this, I set it in my router's config.

Ensure the recipient host can reach your machine that is running the ignite script on port 8080.  You can verify this by getting into a live boot environment, and running something like:

```bash
nc -zv $your_machines_ip 8080
```

Ensure that your machine can reach your pikvm on the port that is listening.  In my case, that is port 443. You can verify this with something like:

```bash
nc -zv $your_pikvms_ip 443
```


## Usage

It's pretty simple, just:

```bash
./ignite.sh
```


## Acknowledgements

 - [Timothée Ravier's](https://github.com/travier) work on [systemd-sysext on CoreOS](https://extensions.fcos.fr)
