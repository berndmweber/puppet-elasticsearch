# == Class: elasticsearch::package
#
# This class exists to coordinate all software package management related
# actions, functionality and logical units in a central place.
#
#
# === Parameters
#
# This class does not provide any parameters.
#
#
# === Examples
#
# This class may be imported by other classes to use its functionality:
#   class { 'elasticsearch::package': }
#
# It is not intended to be used directly by external resources like node
# definitions or other modules.
#
#
# === Authors
#
# * Richard Pijnenburg <mailto:richard@ispavailability.com>
#
class elasticsearch::package {

  #### Package management

  # set params: in operation
  if $elasticsearch::ensure == 'present' {

    if $elasticsearch::version == false {

      $package_ensure = $elasticsearch::autoupgrade ? {
        true  => 'latest',
        false => 'present',
      }

    }  else {

      $package_ensure = $elasticsearch::version

    }

  # set params: removal
  } else {
    $package_ensure = 'purged'
  }

  if $elasticsearch::pkg_source {

    $filenameArray = split($elasticsearch::pkg_source, '/')
    $basefilename = $filenameArray[-1]
    $proto = $filenameArray[0]

    $extArray = split($basefilename, '\.')
    $ext = $extArray[-1]

    $tmpSource = "/tmp/${basefilename}"

    if $proto =~ /^http/ {
      exec { 'download-pkg' :
        cwd     => '/tmp',
        path    => ['/usr/bin', '/bin'],
        command => "curl -o ${basefilename} ${elasticsearch::pkg_source}",
        creates => $tmpSource,
        before  => Package [ $elasticsearch::params::package ],
      }
    } else {
      file { $tmpSource:
        source => $elasticsearch::pkg_source,
        owner  => 'root',
        group  => 'root',
        backup => false,
        before => Package [ $elasticsearch::params::package ],
      }
    }

    case $ext {
      'deb':   { $pkg_provider = 'dpkg' }
      'rpm':   { $pkg_provider = 'rpm'  }
      default: { fail("Unknown file extention \"${ext}\"") }
    }
  } else {
    $tmpSource = undef
    $pkg_provider = undef
  }

  # action
  package { $elasticsearch::params::package:
    ensure   => $package_ensure,
    source   => $tmpSource,
    provider => $pkg_provider
  }

}
