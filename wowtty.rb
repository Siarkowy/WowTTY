#!/usr/bin/env ruby
#
# WowTTY, HellGround Core console chat client written in Ruby
# Copyright (C) 2014 Siarkowy <siarkowy@siarkowy.net>
# See LICENSE file for more information on licensing.

require 'io/console'
require 'optparse'
require 'hexdump'
require 'uri'

require_relative 'hellground/protocol'

class HellGround::Packet
  # Dumps packet description and contents to specified stream (defaults to $stdout).
  # @param output [#puts] Stream to output packet to.
  def dump(output = nil)
    (output || $stdout).puts self
    data.hexdump(output: output)
  end
end

class HellGround::World::Packet
  # Dumps packet description and contents to specified stream (defaults to $stdout).
  # @param output [#puts] Stream to output packet to.
  def dump(output = nil)
    (output || $stdout).puts self
    @data[0..(hdrsize+2)].hexdump(output: output)
  end
end

module WowTTY
  require_relative 'app/slash_commands'

  class KeyboardHandler < EM::Connection
    include EM::Protocols::LineText2

    def initialize(app)
      @app = app
    end

    def receive_line(data)
      @app.receive_line(data)
    end
  end

  class App
    include SlashCommands

    def initialize
      puts %q{
 _ _ _           _____ _____ __ __
| | | |___ _ _ _|_   _|_   _|  |  |
| | | | . | | | | | |   | | |_   _|
|_____|___|_____| |_|   |_|   |_|
      }
      @options = {
        host: 'logon.hellground.net',
        dateformat: '%H:%M',
        port: 3724,
        chans: ['world'],
        verbose: false,
      }

      @opcode_verbose_flags = {}

      optparse = OptionParser.new do |opts|
        opts.banner = "Usage: WowTTY.rb [options]"

        opts.on('-H', '--host ADDR', 'Host name') do |host|
          @options[:host] = host
        end

        opts.on('-P', '--port PORT', Numeric, 'Port number') do |n|
          @options[:port] = n
        end

        opts.on('-u', '--user NAME', 'Account name') do |user|
          @options[:user] = user
        end

        opts.on('-p', '--pass PASS', 'Account password') do |pass|
          @options[:pass] = pass
        end

        opts.on('-c', '--char NAME', 'Character to use on login') do |char|
          @options[:char] = char
        end

        opts.on('-j', '--join chan1,chan2,...', Array, 'Channels to join after login') do |l|
          @options[:chans] = l
        end

        opts.on('-U', '--uri URI', 'Connection URI (user[:password][@host[:port]][/char])') do |uri|
          uri = URI.parse(uri)
          return unless uri
          @options[:host] = uri.host || @options[:host]
          @options[:port] = uri.port || @options[:port]
          @options[:user] = uri.user || @options[:user]
          @options[:pass] = uri.password || @options[:pass]
          @options[:char] = uri.path && uri.path[1..-1] || @options[:char]
        end

        opts.on('-v', '--verbose', 'Output more information') do
          @options[:verbose] = true
        end

        opts.on('-V', '--redirect-verbose DESTINATION') do |destination|
          @options[:verbose_redirect] = destination
        end

        opts.on('-d', '--date-format FORMAT', 'Date format to Time#strftime function') do |fmt|
          @options[:dateformat] = fmt
        end

        opts.on_tail('-h', '--help', 'Display this screen') do
          puts opts
          exit
        end
      end

      optparse.parse!

      unless @options[:user]
        begin
          print 'Enter user: '
          @options[:user] = gets.chomp
        rescue Interrupt
          return
        end
      end

      unless @options[:pass]
        begin
          print 'Enter pass: '
          @options[:pass] = STDIN.noecho(&:gets).chomp
          puts
        rescue Interrupt
          return
        end
      end

      return if @options[:user].empty? || @options[:pass].empty?

      run!
    end

    def run!
      EM::run do
        puts "#{timestamp} Connecting to realm server at #{@options[:host]}:#{@options[:port]}."

        @conn = EM::connect(@options[:host], @options[:port], HellGround::Auth::Connection,
                            self, @options[:user], @options[:pass]) do |h|

          h.on(:packet_received, :packet_sent) do |pk|
            next unless @options[:verbose]

            if !@opcode_verbose_flags.has_key?(pk.opcode) || @opcode_verbose_flags[pk.opcode]
              if @options[:verbose_redirect]
                open(@options[:verbose_redirect], 'a') { |pipe| pk.dump pipe }
              else
                pk.dump
              end
            end
          end

          h.on(:auth_error) do |e|
            puts "#{timestamp} Authentication error: #{e.message}."
            exit 1
          end

          h.on(:auth_succeeded) do
            puts "#{timestamp} Requesting realm list from the server."
          end

          h.on(:realmlist_discovered) do |name, addr|
            puts "#{timestamp} Discovered realm #{name} at #{addr}."
          end

          h.on(:realmlist_selected) do |name, host, port|
            puts "#{timestamp} Connecting to world server #{name} at #{host}:#{port}."
          end

          h.on(:reconnected) do |conn|
            @conn = conn
          end

          h.on(:world_opened) do
            puts "#{timestamp} World connection opened."
          end

          h.on(:character_enum) do |world|
            if @options[:char] && world.login(@options[:char])
              puts "#{timestamp} Logging in as #{@options[:char]}."
              @options[:char] = nil
            else
              puts "Select character:"
              world.chars.each { |player| puts " > #{player.to_char}" }
            end
          end

          h.on(:login_succeeded) do |world|
            puts "#{timestamp} Login successful."

            @options[:chans].each { |chan| world.chat.join chan }
          end

          h.on(:logout_succeeded) do
            puts "#{timestamp} Logout successful."
          end

          h.on(:motd_received) do |motd|
            puts "#{timestamp} <MOTD> #{motd}"
          end

          h.on(:guild_updated) do |guild|
            puts "#{timestamp} Guild roster:"
            puts guild.online.map { |guid, char| char.to_s }.join("\n")
          end

          h.on(:message_received) do |msg|
            puts "#{timestamp} #{msg}"
          end

          h.on(:server_notification_received, :channel_notification_received) do |ntfy|
            puts "#{timestamp} <Notification> #{ntfy}"
          end

          h.on(:player_not_found) do |name|
            puts "#{timestamp} Player #{name} not found."
          end

          h.on(:world_closed) do
            puts "#{timestamp} World connection closed."
          end
        end

        EM::open_keyboard(KeyboardHandler, self)
      end
    end

    def timestamp
      Time.now.strftime(@options[:dateformat])
    end
  end
end

WowTTY::App.new
