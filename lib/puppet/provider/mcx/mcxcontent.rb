#--
# Copyright (C) 2008 Jeffrey J McCune.

# This program and entire repository is free software; you can
# redistribute it and/or modify it under the terms of the GNU
# General Public License as published by the Free Software
# Foundation; either version 2 of the License, or any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA

# Author: Jeff McCune <mccune.jeff@gmail.com>

require 'tempfile'

Puppet::Type.type(:mcx).provide :mcxcontent, :parent => Puppet::Provider do

  desc "MCX Settings management using DirectoryService on OS X.

  This provider manages the entire MCXSettings attribute available
  to some directory services nodes.  This management is 'all or nothing'
  in that discrete application domain key value pairs are not managed
  by this provider.

  It is recommended to use WorkGroup Manager to configure Users, Groups,
  Computers, or ComputerLists, then use 'ralsh mcx' to generate a puppet
  manifest from the resulting configuration.

  Original Author: Jeff McCune (mccune.jeff@gmail.com)

"

  # This provides a mapping of puppet types to DirectoryService
  # type strings.
  TypeMap = {
    :user => "Users",
    :group => "Groups",
    :computer => "Computers",
    :computerlist => "ComputerLists",
  }

  commands :dscl => "/usr/bin/dscl"
  confine :operatingsystem => :darwin
  defaultfor :operatingsystem => :darwin
  
  # FIXME: dslocal name is fixed. The default should be "Default" if we do not 
  # want to break existing installations.
  DSLOCAL_DIR = "Default"
  
  class << self
    # It returns an array of instances of this class.
    def instances
      mcx_list = []
      TypeMap.keys.each do |ds_type|
        ds_path = "/Local/#{DSLOCAL_DIR}/#{TypeMap[ds_type]}"
        output = dscl 'localhost', '-list', ds_path
        member_list = output.split
        member_list.each do |ds_name|
          content = mcxexport(ds_type, ds_name)
          if content.empty?
            Puppet.debug "/#{TypeMap[ds_type]}/#{ds_name} has no MCX data."
          else
            # This node has MCX data.
            mcx_list << self.new(
              :name => "/#{TypeMap[ds_type]}/#{ds_name}",
              :ds_type => ds_type,
              :ds_name => ds_name,
              :content => content)
          end
        end
      end
      mcx_list
    end

    def mcxexport(ds_type, ds_name)
      ds_t = TypeMap[ds_type]
      ds_n = ds_name.to_s
      ds_path = "/Local/#{DSLOCAL_DIR}/#{ds_t}/#{ds_n}"
      dscl 'localhost', '-mcxexport', ds_path
    end
  end
  
  public

  def create
    self.content=(resource[:content])
  end

  def destroy
    ds_parms = get_dsparams
    ds_t = TypeMap[ds_parms[:ds_type]]
    ds_n = ds_parms[:ds_name].to_s
    ds_path = "/Local/#{DSLOCAL_DIR}/#{ds_t}/#{ds_n}"

    dscl 'localhost', '-mcxdelete', ds_path
  end

  def exists?
    begin
      has_mcx?
    rescue Puppet::ExecutionFailure => e
      return false
    end
  end

  def content
    ds_parms = get_dsparams

    self.class.mcxexport(ds_parms[:ds_type], ds_parms[:ds_name])
  end

  def content=(value)
    # dscl localhost -mcximport
    ds_parms = get_dsparams

    mcximport(ds_parms[:ds_type], ds_parms[:ds_name], resource[:content])
  end
  
  private
  
  def has_mcx?
    !content.empty?
  end
  
  def mcximport(ds_type, ds_name, val)
    ds_t = TypeMap[ds_type]
    ds_path = "/Local/#{DSLOCAL_DIR}/#{ds_t}/#{ds_name}"

    tmp = Tempfile.new('puppet_mcx')
    begin
      tmp << val
      tmp.flush
      dscl 'localhost', '-mcximport', ds_path, tmp.path
    ensure
      tmp.close
      tmp.unlink
    end
  end

  # Given the resource name string, parse ds_type out.
  def parse_type(name)
    ds_type = name.split('/')[1]
    unless ds_type
      error("Could not parse ds_type from resource name '#{name}'. Specify with ds_type parameter.")
    end
    # De-pluralize and downcase.
    ds_type = ds_type.chop.downcase.to_sym
    unless TypeMap.key? ds_type
      error("Could not parse ds_type from resource name '#{name}'. Specify with ds_type parameter.")
    end
    ds_type
  end

  # Given the resource name string, parse ds_name out.
  def parse_name(name)
    ds_name = name.split('/')[2]
    unless ds_name
      error("Could not parse ds_name from resource name '#{name}'. Specify with ds_name parameter.")
    end
    ds_name
  end

  # Gather ds_type and ds_name from resource or parse it out of the name.
  def get_dsparams
    ds_type = resource[:ds_type]
    ds_type ||= parse_type(resource[:name])
    unless TypeMap.key? ds_type.to_sym
      raise Puppet::Error.new("#{ds_type} is not a key in TypeMap") 
    end

    ds_name = resource[:ds_name]
    ds_name ||= parse_name(resource[:name])

    {
      :ds_type => ds_type.to_sym,
      :ds_name => ds_name,
    }
  end
  
  def error(msg)
    raise Puppet::Error.new(msg)
  end
end
