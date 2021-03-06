# == Function: ipresolve( string $name_to_resolve, bool $ipv6 = false)
#
# Copyright (c) 2015 Wikimedia Foundation Inc.
#
# Performs a name resolution (for A AND AAAA records only) and returns
# an hash of arrays.
#
# Takes one or more names to resolve, and returns an array of all the
# A or AAAA records found. The resolution is actually only done when
# the ttl has expired.
#
require 'resolv'

class DNSCacheEntry
  # Data structure for storing a DNS cached result.
  def initialize(address, ttl)
    @value = address
    @ttl = Time.now.to_i + ttl
  end

  def is_valid?(time)
    return @ttl > time
  end

  def value
    return @value.to_s
  end
end

class BasicTTLCache
  def initialize
    @cache = {}
  end

  def write(key, value, ttl)
    @cache[key] = DNSCacheEntry.new(value, ttl)
  end

  def delete(key)
    @cache.delete(key) if @cache.has_key?(key)
  end

  def is_valid?(key)
    # If the key exists, and its ttl has not expired, return true.
    # Return false (and maybe clean up the stale entry) otherwise.
    return false unless @cache.has_key?(key)
    t = Time.now.to_i
    return true if @cache[key].is_valid?t
    return false
  end

  def read(key)
    if is_valid?key
      return @cache[key].value
    end
    return nil
  end

  def read_stale(key)
    if @cache.has_key?(key)
      return @cache[key].value
    end
    return nil
  end
end

class DNSCached
  attr_accessor :dns
  def initialize(cache = nil, default_ttl = 300)
    @cache = cache || BasicTTLCache.new
    @dns = Resolv::DNS.open()
    @default_ttl = default_ttl
  end

  def get_resource(name, type)
    cache_key = "#{name}_#{type}"
    res = @cache.read(cache_key)
    if (res.nil?)
      begin
        res = @dns.getresource(name, type)
        # Ruby < 1.9 returns nil as the ttl...
        if res.ttl
          ttl = res.ttl
        else
          ttl = @default_ttl
        end
        @cache.write(cache_key, res.address, ttl)
        res.address.to_s
      rescue
      # If resolution fails and we do have a cached stale value, use it
        res = @cache.read_stale(cache_key)
        res.to_s unless res.nil?
      end
    else
      res.to_s
    end
  end
end


module Puppet::Parser::Functions
  dns = DNSCached.new
  newfunction(:ipresolve, :type => :rvalue, :arity => 2) do |args|
    name = args[0]
    type = args[1].to_i
    if type == 4
      source = Resolv::DNS::Resource::IN::A
    elsif type == 6
      source = Resolv::DNS::Resource::IN::AAAA
    else
      raise ArgumentError, 'Type must be 4 or 6'
    end
    return dns.get_resource(name, source).to_s
  end
end
