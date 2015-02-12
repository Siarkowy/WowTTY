#!/usr/bin/env ruby
#
# WowTTY, HellGround Core console chat client written in Ruby
# Copyright (C) 2014 Siarkowy <siarkowy@siarkowy.net>
# See LICENSE file for more information on licensing.

require 'io/console'
require 'optparse'
require 'hexdump'

require_relative 'hellground/protocol'

class HellGround::Packet
  def dump
    puts self
    data.hexdump
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
        port: 3724,
        chans: ['world'],
        verbose: false,
      }

      optparse = OptionParser.new do |opts|
        opts.banner = "Usage: WowTTY.rb [options]"

        opts.on('-H', '--host ADDR', 'Host name') do |host|
          @options[:host] = host
        end

        opts.on('-p', '--port PORT', Numeric, 'Port number') do |n|
          @options[:port] = n
        end

        opts.on('-u', '--user NAME', 'Account name') do |user|
          @options[:user] = user
        end

        opts.on('-P', '--pass PASS', 'Account password') do |pass|
          @options[:pass] = pass
        end

        opts.on('-c', '--char NAME', 'Character to use on login') do |char|
          @options[:char] = char
        end

        opts.on('-j', '--join chan1,chan2,...', Array, 'Channels to join after login') do |l|
          @options[:chans] = l
        end

        opts.on('-v', '--verbose', 'Output more information') do
          @options[:verbose] = true
        end

        opts.on_tail('-h', '--help', 'Display this screen') do
          puts opts
          exit
        end
      end

      optparse.parse!

      unless @options[:user]
        print 'Enter user: '
        @options[:user] = gets.chomp
      end

      unless @options[:pass]
        print 'Enter pass: '
        @options[:pass] = STDIN.noecho(&:gets).chomp
        puts
      end

      run!
    end

    def run!
      EM::run do
        puts "Connecting to realm server at #{@options[:host]}:#{@options[:port]}."

        @conn = EM::connect(@options[:host], @options[:port], HellGround::Auth::Connection,
          self, @options[:user], @options[:pass]) do |h|

          h.on(:packet_received, :packet_sent) do |pk|
            pk.dump if @options[:verbose]
          end

          h.on(:auth_error) do |e|
            puts "Authentication error: #{e.message}."
            exit 1
          end

          h.on(:auth_succeeded) do
            puts 'Requesting realm list from the server.'
          end

          h.on(:realmlist_discovered) do |name, addr|
            puts "Discovered realm #{name} at #{addr}."
          end

          h.on(:realmlist_selected) do |name, host, port|
            puts "Connecting to world server #{name} at #{host}:#{port}."
          end

          h.on(:reconnected) do |conn|
            @conn = conn
          end

          h.on(:world_opened) do 
            puts 'World connection opened.'
          end

          h.on(:character_enum) do |world|
            if @options[:char] && world.login(@options[:char])
              puts "Logging in as #{@options[:char]}."
              @options[:char] = nil
            else
              puts "Select character:"
              world.chars.each { |player| puts " > #{player.to_char}" }
            end
          end

          h.on(:login_succeeded) do |world|
            puts 'Login successful.'

            @options[:chans].each { |chan| world.chat.join chan }
          end

          h.on(:logout_succeeded) do
            puts 'Logout successful.'
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
            puts "World connection closed."
          end
        end

        EM::open_keyboard(KeyboardHandler, self)
      end
    end

    def timestamp
      Time.now.strftime("%H:%M")
    end
  end
end

WowTTY::App.new
