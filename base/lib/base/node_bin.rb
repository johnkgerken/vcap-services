# Copyright (c) 2009-2011 VMware, Inc.
require 'rubygems'
require 'bundler/setup'
require 'optparse'
require 'logger'
require 'yaml'

$LOAD_PATH.unshift File.join(File.dirname(__FILE__), '..', '..', '..')
require 'vcap/common'

$LOAD_PATH.unshift File.dirname(__FILE__)
require 'abstract'

module VCAP
  module Services
    module Base
    end
  end
end


class VCAP::Services::Base::NodeBin

  abstract :default_config_file
  abstract :node_class
  abstract :additional_config

  def start
    config_file = default_config_file

    OptionParser.new do |opts|
      opts.banner = "Usage: #{$0.split(/\//)[-1]} [options]"
      opts.on("-c", "--config [ARG]", "Configuration File") do |opt|
        config_file = opt
      end
      opts.on("-h", "--help", "Help") do
        puts opts
        exit
      end
    end.parse!

    begin
      config = YAML.load_file(config_file)
    rescue => e
      puts "Could not read configuration file:  #{e}"
      exit
    end

    logger = Logger.new(parse_property(config, "log_file", String, :optional => true) || STDOUT, "daily")
    logger.level = case (parse_property(config, "log_level", String, :optional => true) || "INFO")
      when "DEBUG" then Logger::DEBUG
      when "INFO" then Logger::INFO
      when "WARN" then Logger::WARN
      when "ERROR" then Logger::ERROR
      when "FATAL" then Logger::FATAL
      else Logger::UNKNOWN
    end

    options = {
      :logger => logger,
      :index => parse_property(config, "index", Integer, :optional => true),
      :base_dir => parse_property(config, "base_dir", String),
      :ip_route => parse_property(config, "ip_route", String, :optional => true),
      :node_id => parse_property(config, "node_id", String),
      :mbus => parse_property(config, "mbus", String),
      :local_db => parse_property(config, "local_db", String),
      :migration_nfs => parse_property(config, "migration_nfs", String, :optional => true),
    }

    options = additional_config(options, config)

    EM.error_handler do |e|
      logger.fatal("#{e}\n#{e.backtrace.join("\n")}")
      exit
    end

    pid_file = parse_property(config, "pid", String)
    begin
      FileUtils.mkdir_p(File.dirname(pid_file))
    rescue => e
      logger.fatal "Can't create pid directory, exiting: #{e}"
      exit
    end
    File.open(pid_file, 'w') { |f| f.puts "#{Process.pid}" }

    EM.run do
      node = node_class.new(options)
      trap("INT") {shutdown(node)}
      trap("TERM") {shutdown(node)}
    end
  end

  def shutdown(node)
    node.shutdown
    EM.stop
  end

  def parse_property(hash, key, type, options = {})
    obj = hash[key]
    if obj.nil?
      raise "Missing required option: #{key}" unless options[:optional]
      nil
    elsif type == Range
      raise "Invalid Range object: #{obj}" unless obj.kind_of?(Hash)
      first, last = obj["first"], obj["last"]
      raise "Invalid Range object: #{obj}" unless first.kind_of?(Integer) and last.kind_of?(Integer)
      Range.new(first, last)
    else
      raise "Invalid #{type} object: #{obj}" unless obj.kind_of?(type)
      obj
    end
  end
end