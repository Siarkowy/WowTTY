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
        chans: ['world'],
        host: 'logon.hellground.net',
        channel_redirects: Hash.new { |h, k| h[k] = [] },
        dateformat: '%H:%M',
        port: 3724,
        verbose: false,
      }

      @opcode_verbose_flags = {}

      optparse = OptionParser.new do |opts|
        opts.banner = "Usage: #{$0} [options]"

        opts.on('-H', '--host ADDRESS', 'Sets server host name to connect to.') do |host|
          @options[:host] = host
        end

        opts.on('-P', '--port PORT', Numeric, 'Sets port number on target host.') do |port|
          @options[:port] = port
        end

        opts.on('-u', '--user ACCOUNT', 'Specifies account name.') do |user|
          @options[:user] = user
        end

        opts.on('-p', '--pass PASSWORD', 'Specifies account password.') do |pass|
          @options[:pass] = pass
        end

        opts.on('-c', '--char CHARACTER', 'Selects character to log in to.') do |char|
          @options[:char] = char
        end

        opts.on('-j', '--join chan1,chan2,...', Array, 'Sets channels to join after login, comma separated list.') do |chans|
          @options[:chans] = chans
        end

        opts.on('-U', '--uri URI', 'Specifies shorthand connection URI: //[account[:password]@]host[:port][/character]') do |uri|
          begin
            uri = URI.parse(uri)
          rescue URI::InvalidURIError => e
            puts "Error: incorrect URI specified through -U option: #{e}"
            exit 2
          end

          @options[:host] = uri.host || @options[:host]
          @options[:port] = uri.port || @options[:port]
          @options[:user] = uri.user || @options[:user]
          @options[:pass] = uri.password || @options[:pass]
          @options[:char] = uri.path && uri.path[1..-1] || @options[:char]
        end

        opts.on('-v', '--verbose', 'Enables verbose mode to dump packets.') do |v|
          @options[:verbose] = v
        end

        opts.on('-r', '--redirect-channel CHANNEL:DESTINATION',
            'Adds output redirection for specified channel or chat type. Can be used multiple times with multiple -r switches. Destination will be appended to.') do |data|
          channel, destination = data.split ':'
          @options[:channel_redirects][channel] << destination
        end

        opts.on('-n', '--redirect-notifications DESTINATION',
            'Specifies output redirection for channel and server notifications. Destination will be appended to.') do |destination|
          @options[:notification_redirect] = destination
        end

        opts.on('-V', '--redirect-verbose DESTINATION',
            'Specifies output redirection for verbose mode. Destination will be appended to.') do |destination|
          @options[:verbose_redirect] = destination
        end

        opts.on('-d', '--date-format FORMAT', 'Sets date format for timestamps. Accepts valid Time#strftime format strings.') do |fmt|
          @options[:dateformat] = fmt
        end

        opts.on('-m', '--message-format FORMAT', 'Specifies chat message template string. May contain following elements: %{type} %{sender} %{sep} %{text} %{rawtype} %{lang} %{guid} %{rawtext} %{to}.') do |fmt|
          @options[:msgformat] = fmt
        end

        opts.on_tail('-h', '--help', 'Displays the help screen and exits successfully.') do
          puts opts
          exit 0
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

            @guild_timer = EM::PeriodicTimer.new(8) do
              @conn.instance_eval {
                send_data World::Packets::ClientGuildRoster.new unless @player.nil?
              }
            end

            @options[:chans].each { |chan| world.chat.join chan }
          end

          h.on(:logout_succeeded) do
            @guild_timer.cancel if @guild_timer
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
            if @options[:channel_redirects].include?(msg.to.to_s) ||
                @options[:channel_redirects].include?(msg.type.to_s)
              (@options[:channel_redirects][msg.to.to_s] +
                  @options[:channel_redirects][msg.type.to_s]).each do |destination|
                open(destination, 'a') do |pipe|
                  pipe.puts "#{timestamp} #{msg.to_s(@options[:msgformat])}"
                end
              end
            else
              puts "#{timestamp} #{msg}" unless msg.lang == HellGround::World::ChatMessage::LANG_ADDON
            end
          end

          h.on(:server_notification_received, :channel_notification_received) do |ntfy|
            if @options[:notification_redirect]
              open(@options[:notification_redirect], 'a') do |pipe|
                pipe.puts "#{timestamp} #{ntfy}"
              end
            else
              puts "#{timestamp} <Notification> #{ntfy}"
            end
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
