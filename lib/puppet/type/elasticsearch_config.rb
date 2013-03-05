require 'puppet/type/file'
require 'puppet/type/file/owner'
require 'puppet/type/file/group'
require 'puppet/type/file/mode'
require 'puppet/util/checksums'

Puppet::Type.newtype(:elasticsearch_config) do
  @doc = "Collects any elasticsearch nodes for unicast and merges that with the hash config given in 'config_hash'
  This is created to allow auto collecting of all unicast nodes without having to work with file concat
  "

  ensurable

  # the file/posix provider will check for the :links property
  # which does not exist
  def [](value)
    if value == :links
      return false
    end

    super
  end

  newparam(:name, :namevar => true) do
    desc "Resource name"
  end

  newparam(:cluster) do
    desc "Cluster name"
  end

  newparam(:path) do
    desc "The output file"
    defaultto do
      resource.value(:name)
    end
  end

  newproperty(:owner, :parent => Puppet::Type::File::Owner) do
    desc "Desired file owner."
    defaultto 'root'
  end

  newproperty(:group, :parent => Puppet::Type::File::Group) do
    desc "Desired file group."
    defaultto 'root'
  end

  newproperty(:mode, :parent => Puppet::Type::File::Mode) do
    desc "Desired file mode."
    defaultto '0644'
  end

  newparam(:config_hash) do
    desc "config hash"
  end

  newproperty(:content) do
    desc "Read only attribute. Represents the content."

    include Puppet::Util::Diff
    include Puppet::Util::Checksums

    defaultto do
      # only be executed if no :content is set
      @content_default = true
      @resource.no_content
    end

    validate do |val|
      fail "read-only attribute" if !@content_default
      self.fail Puppet::ParseError, "Required setting 'cluster' missing" if self[:cluster].nil?
      self.fail Puppet::ParseError, "Required setting 'config_hash' missing" if self[:config_hash].nil?
    end

    def insync?(is)
      result = super

      if ! result
        string_file_diff(@resource[:path], @resource.should_content)
      end

      result
    end

    def is_to_s(value)
      md5(value)
    end

    def should_to_s(value)
      md5(value)
    end
  end

  def no_content
    "\0## GENERATED BY PUPPET ##\0"
  end

  def should_content
    fragment_content = []
    count=0

    # Collect all unicast nodes
    catalog.resources.select do |r|
      r.is_a?(Puppet::Type.type(:elasticsearch_unicast_node)) && r[:cluster] == self[:cluster]
    end.each do |r|
       address = r[:ipaddress]
       fragment_content << address
       count += 1
    end

    # initial string
    @yml_string = "## GENERATED BY PUPPET ##\n---\n"

    ## Transform shorted keys into full write up
    transformed_config = transform(self[:config_hash])

    # Merge it back into a hash
    tmphash = {}
    transformed_config.each do |subhash|
      tmphash = tmphash.deep_merge_with_array_values_concatenated(subhash)
    end
    
    # Merge unicast hosts if we have any
    if count > 0
      unicast_hash = { 'discovery' => { 'zen' => { 'ping' => { 'unicast' => { 'hosts' => fragment_content } } } } }
      tmphash = tmphash.deep_merge_with_array_values_concatenated(unicast_hash)
    end

    # Transform it into yaml
    recursive_hash_to_yml_string(tmphash)
    @yml_string
  end

  # Function to make a structured and sorted yaml representation out of a hash
  def recursive_hash_to_yml_string(hash, depth=0)
    spacer = ""
    depth.times { spacer += "  "}
    hash.keys.sort.each do |sorted_key|
      @yml_string += spacer + sorted_key + ": "
      if hash[sorted_key].is_a?(Array)
         keyspacer = ""
         sorted_key.length.times { keyspacer += " " }
         @yml_string += "\n"
         hash[sorted_key].each do |item|
           @yml_string += spacer + keyspacer + "- " + item +"\n"
         end
      elsif hash[sorted_key].is_a?(Hash)
        @yml_string += "\n"
        recursive_hash_to_yml_string(hash[sorted_key], depth+1)
      else
        @yml_string += "#{hash[sorted_key].to_s}\n"
      end
    end
  end

  # Function to transform shorted write up of the keys into full hash representation
  def transform(hash)
  return_vals = []
 
  hash.each do |key,val|
    if m = /^([^.]+)\.(.*)$/.match(key)
      temp = { m[1] => { m[2] => val } }
      transform(temp).each do |stuff|
        return_vals << stuff
      end 
    else
      if val.is_a?(Hash)
        transform(val).each do |stuff|
          return_vals << { key => stuff }
        end 
      else
        return_vals << { key => val }
      end
    end
  end 
 
  return_vals
  end

  # Function to deep merge hashes with same keys
  class Hash
    def deep_merge_with_array_values_concatenated(hash)
    target = dup
 
    hash.keys.each do |key|
      if hash[key].is_a? Hash and self[key].is_a? Hash
        target[key] = target[key].deep_merge_with_array_values_concatenated(hash[key])
        next
      end
 
      if hash[key].is_a?(Array) && target[key].is_a?(Array)
        target[key] = target[key] + hash[key]
      else
        target[key] = hash[key]
      end
    end
 
    target
    end
  end

  def stat(dummy_arg = nil)
    return @stat if @stat and not @stat == :needs_stat
    @stat = begin
      ::File.stat(self[:path])
    rescue Errno::ENOENT => error
      nil
    rescue Errno::EACCES => error
      warning "Could not stat; permission denied"
      nil
    end
  end

  ### took from original type/file
  # There are some cases where all of the work does not get done on
  # file creation/modification, so we have to do some extra checking.
  def property_fix
    properties.each do |thing|
      next unless [:mode, :owner, :group].include?(thing.name)

      # Make sure we get a new stat object
      @stat = :needs_stat
      currentvalue = thing.retrieve
      thing.sync unless thing.safe_insync?(currentvalue)
    end
  end
end