# Enable this class to run a weekly cron job to fsck your cache.
class cvmfs::fsck (
  $cvmfs_cache_base = $cvmfs::cvmfs_cache_base,
  $options = '',
  $onreboot = false,
  Optional[Boolean] $usesystemd = undef,
) inherits cvmfs {
  if ($facts['os']['family'] == 'RedHat' and (versioncmp($facts['os']['release']['major'],'7') <= 0))
  or ($facts['os']['name'] == 'Debian' and (versioncmp($facts['os']['release']['major'],'9') <= 0))
  or ($facts['os']['name'] == 'Ubuntu' and (versioncmp($facts['os']['release']['major'],'16') <= 0)) {
    $_usesystemd = false
  } else {
    $_usesystemd = true
  }

  if $_usesystemd {
    systemd::unit_file { 'cvmfs-fsck.timer':
      ensure  => present,
      content => epp('cvmfs/fsck/cvmfs-fsck.timer.epp',
        {
          'onreboot' => $onreboot,
        }
      ),
      enable  => true,
      active  => true,
    }
    systemd::unit_file { 'cvmfs-fsck.service':
      ensure  => present,
      content => epp('cvmfs/fsck/cvmfs-fsck.service.epp',
        {
          'cache_base' => $cvmfs_cache_base,
          'options'    => $options,
        }
      ),
    }
    systemd::tmpfile { 'cvmfs-quarantaine.conf':
      content => epp('cvmfs/fsck/cvmfs-quarantaine.conf.epp',
        {
          'cache_base' => $cvmfs_cache_base,
        }
      ),
    }
  } else {
    file { '/usr/local/sbin/cvmfs_fsck_cron.sh':
      ensure  => file,
      mode    => '0744',
      owner   => root,
      group   => root,
      content => template('cvmfs/cvmfs_fsck_cron.sh.erb'),
    }
    # -i <value> flag to script says cron job will exit early if uptime is less than this value.

    $tmpcleaning_cmd = $::osfamily ? {
      'RedHat' => '/usr/sbin/tmpwatch -umc -f 30d',
      'Debian' => '/usr/sbin/tmpreaper -m -f 30d',
      default  => '/usr/sbin/tmpwatch -umc -f 30d',
    }

    $tmpcleaning_pkg = $::osfamily ? {
      'RedHat' => 'tmpwatch',
      'Debian' => 'tmpreaper',
      default  => 'tmpwatch',
    }
    # Provides ionice.
    $util_linux_pkg = 'util-linux'

    cron { 'clean_quarantaine':
      hour    => fqdn_rand(24,'cvmfs_purge'),
      minute  => fqdn_rand(60,'cvmfs_purge'),
      weekday => fqdn_rand(7,'cvmfs_purge'),
      command => "/usr/bin/test -d ${cvmfs_cache_base}/shared/quarantaine && ${tmpcleaning_cmd} ${cvmfs_cache_base}/shared/quarantaine",
    }

    # lint:ignore:140chars
    cron { 'cvmfs_fsck':
      hour    => fqdn_rand(24,'cvmfs'),
      minute  => fqdn_rand(60,'cvmfs'),
      weekday => fqdn_rand(7,'cvmfs'),
      command => '/usr/local/sbin/cvmfs_fsck_cron.sh -i 86400  2>&1 | /usr/bin/awk \'{ print strftime("\%Y-\%m-\%d \%H:\%M:\%S"), $0; }\'  >> /var/log/cvmfs_fsck.log',
      require => [File['/usr/local/sbin/cvmfs_fsck_cron.sh'],Package[$tmpcleaning_pkg],Package[$util_linux_pkg]],
    }
    # lint:endignore
    if $onreboot {
      # lint:ignore:140chars
      cron { 'cvmfs_fsck_on_reboot':
        command => '/usr/local/sbin/cvmfs_fsck_cron.sh -i 0 2>&1 | /usr/bin/awk \'{ print strftime("\%Y-\%m-\%d \%H:\%M:\%S"), $0; }\'  >> /var/log/cvmfs_fsck.log',
        special => 'reboot',
        require => [File['/usr/local/sbin/cvmfs_fsck_cron.sh'],Package[$tmpcleaning_pkg],Package[$util_linux_pkg]],
      }
      # lint:endignore
    }
    file { '/etc/logrotate.d/cvmfs_fsck':
      ensure => file,
      mode   => '0644',
      owner  => 'root',
      group  => 'root',
      source => 'puppet:///modules/cvmfs/cvmfs_fsck.logrotate',
    }
    ensure_packages([$tmpcleaning_pkg, $util_linux_pkg])
  }
}
