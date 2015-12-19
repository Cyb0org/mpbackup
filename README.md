mpbackup
--------

MPBackup - shell script to remotely backup rsync shares on btrfs volume

Prerequisites
-------------

- a partition with btrfs file system
- rsync
- cron
- script must be run as root (creating subvolumes, snapshots etc.)
- logger (if you want to log to syslog)

Purpose
-------

- make backups easily: one shell script and one text config
- make something that can replace great BackupPC (only features that I mostly use) :P

Features
--------

Those are features of this backup script (mostly features of btrfs anyway):

- incremental backup
- compression
- checksumming
- deduplication (via external tool)
- quota for backups (script doesn't set any limits)
- blackout time (via cron)
- limiting simultaneously running scripts (globally)
- only one rsync can start per share
- only one share backup is done while running script and then script quits - helps with blackout time
- limiting count of existing backups (per share of the host)
- marking completed backups as complete - not marked are partial
- verbose echo to know what's going on
- syslog support (via logger tool)
- simulation mode - to know what can/will be done
- ISC license :)

Install
-------

- place mpbackup.sh anywhere you like (/usr/local/bin/ looks good, but it really doesn't matter)
- place mpbackup-host.conf anywhere you like and point to it in mpbackup.sh
- configure variables on top of the mpbackup.sh
- add hosts and access credentials to mpbackup-hosts.conf (make sure it has 600 permissions, so nobody can read it besides you!)
- add script to cron (without any blackout time - BEWARE!):

<pre>
* *	* * *	root /path/to/mpbackup.sh
</pre>

- live happily ever after with backups :)

Configuration
-------------

mpbackup.sh variables and contents of mpbackup-host.conf should be easy to understand.

I will explain more only date format. I'm assuming that you've set up cron to start script every minute.

- "%Y%m%d-%H" - this will give you ability to have backups created every hour (20151216-01 20151216-02 etc.)
- "%Y%m%d" - here you have daily backup
- "%Y%m%d-%H%M%S" - here you have backup (almost) every time you start script

Below is quite good configuration for standard servers with local services.

date format: "%Y%m%d"

and crontab:

<pre>
* 0-5	* * mon-fri	/path/to/mpbackup.sh
* 22-23	* * mon-fri	/path/to/mpbackup.sh
* *	* * sat-sun	/path/to/mpbackup.sh
</pre>

Remarks
-------

- rsync transmission is not encrypted - use VPN or SSH to transfer data
- tools to see space usage of backups (btrfs subvolumes): https://btrfs.wiki.kernel.org/index.php/Quota_support
- use latest stable kernel possible - for Debian Jessie use backports for Linux 4.2 or try 4.3.3 from unstable: https://packages.debian.org/sid/amd64/linux-image-4.3.0-1-amd64/download
- deduplication: https://github.com/markfasheh/duperemove
- btrfs is still in development, so it's not so stable as ext2/3/4/xfs - you've been warned
- it's NOT replacement for BackupPC :) but it's a start
