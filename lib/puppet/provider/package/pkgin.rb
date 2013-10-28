require "puppet/provider/package"

Puppet::Type.type(:package).provide :pkgin, :parent => Puppet::Provider::Package do
  desc "Package management using pkgin, a binary package manager for pkgsrc."

  commands :pkgin => "pkgin"

  defaultfor :operatingsystem => :dragonfly
  defaultfor :solarisflavour => :smartos

  has_feature :installable, :uninstallable, :upgradeable

  def self.parse_pkgin_line(package)

    # e.g.
    #   vim-7.2.446 =        Vim editor (vi clone) without GUI
    match, name, version, status = *package.match(/(\S+)-(\S+)(?: (=|>|<))?\s+.+$/)
    if match
      {
        :name     => name,
        :version  => version,
        :status   => status
      }
    end
  end

  # packages : list of packages for the current provider declared on manifest
  def self.prefetch(packages)
    # it is unclear if we should call the parent method here. The work done
    #    there seems redundant, at least if pkgin is default provider.
    super
    packages.each do |name,pkg|
      if pkg.provider.get(:ensure) == :present and pkg.should(:ensure) == :latest
        # without this hack, latest is invoked up to two times, but no install/update comes after that
        # it also mangles the messages shown for present->latest transition
        pkg.provider.set( { :ensure => :latest } )
      end
    end
    pkgin("-y", :update)
  end

  # called in every run to collect packages present in the system
  # under 'apply', it is actually called from within the parent prefetch
  def self.instances
    pkgin(:list).split("\n").map do |package|
      new(parse_pkgin_line(package).merge(:ensure => :present))
    end
  end

  # called for every resource in manifest not present in instances
  # it is not defined wether this should query local or remote packages
  # returned hash is stored on @property_hash, or '{:ensure=>:absent}' if nil
  # or false is returnedm, but in any case install/update is executed depending
  # on the value of the initial ensure attribute
  def query
    packages = parse_pkgsearch_line

    if not packages
      if @resource[:ensure] == :absent
        notice "declared as absent but unavailable #{@resource.file}:#{resource.line}"
        return false
      else
        @resource.fail "No candidate to be installed"
      end
    end

    packages.first.merge( :ensure => :absent )
  end

  def parse_pkgsearch_line
    packages = pkgin(:search, resource[:name]).split("\n")

    return nil if packages.length == 1

    # Remove the last three lines of help text.
    packages.slice!(-4, 4)

    pkglist = packages.map{ |line| self.class.parse_pkgin_line(line) }
    pkglist.select{ |package| resource[:name] == package[:name] }
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
    package = parse_pkgsearch_line.detect{ |package| package[:status] == '<' }
    if not package
      set( { :abort => true } )
      return nil
    end
    notice  "Upgrading #{package[:name]} to #{package[:version]}"
    return package[:version]
  end

  def update
    unless @property_hash[:abort]
      install
    end
  end

end
