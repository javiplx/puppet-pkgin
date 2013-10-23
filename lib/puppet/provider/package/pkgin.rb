require "puppet/provider/package"

Puppet::Type.type(:package).provide :pkgin, :parent => Puppet::Provider::Package do
  desc "Package management using pkgin, a binary package manager for pkgsrc."

  commands :pkgin => "pkgin"

  defaultfor :operatingsystem => :dragonfly

  has_feature :installable, :uninstallable, :upgradeable

  defaultfor :solarisflavour => :smartos

  def self.parse_pkgin_line(package, force_status=nil)

    # e.g.
    #   vim-7.2.446 =        Vim editor (vi clone) without GUI
    match, name, version, status = *package.match(/(\S+)-(\S+)(?: (=|>|<))?\s+.+$/)
    if match
      ensure_status = if force_status
        force_status
      elsif status
        :present
      else
        :absent
      end

      {
        :name     => name,
        :ensure   => ensure_status,
        :status   => status,
        :version  => version,
        :provider => :pkgin
      }
    end
  end

  # packages : list of packages for the current provider declared on manifest
  def self.prefetch(packages)
    # it is unclear if we should call the parent method here. The work done
    #    there seems redundant, at least if pkgin is default provider.
    super
    pkgin("-yf", :update)
  end

  # called in every run to collect packages present in the system
  # under 'apply', it is actually called from within the parent prefetch
  def self.instances
    pkgin(:list).split("\n").map do |package|
      new(parse_pkgin_line(package, :present))
    end
  end

  # called for every resource in manifest not present in instances
  # it is not defined wether this should query local or remote packages
  # returned hash is stored on @property_hash, or '{:ensure=>:absent}' if nil
  # or false is returnedm, but in any case install/update is executed depending
  # on the value of the initial ensure attribute
  def query
    packages = pkgin(:search, resource[:name]).split("\n")

    # Remove the last three lines of help text.
    packages.slice!(-4, 4)

    pkglist = packages.map{ |line| self.class.parse_pkgin_line(line) }
    pkglist.detect{ |package| resource[:name] == package[:name] and [ '<' , nil ].index( package[:status] ) } if pkglist
  end

  def install
    pkgin("-y", :install, resource[:name])
  end

  def uninstall
    pkgin("-y", :remove, resource[:name])
  end

  # latest seems to be invoked only when the resource is on instances
  #    and ensure is set to latest
  # if nil/false is returned, latest is called again, but in neither
  #    case update is automatically invoked
  def latest
    package = self.query
    return nil if not package
    notice  "Upgrading #{package[:name]} to #{package[:version]}"
    pkgin("-y", :install, package[:name])
    package.update( { :ensure => :present } )
  end

end
