# WowTTY, HellGround Core console chat client written in Ruby
# Copyright (C) 2014 Siarkowy <siarkowy@siarkowy.net>
# See LICENSE file for more information on licensing.

# Slash command handlers.
module WowTTY::SlashCommands
  private

  SLASH_HANDLERS = {}

  public

  def self.on_slash(*args, &block)
    args.each { |slash| SLASH_HANDLERS[slash.to_sym] = block }
  end

  # Parses user input for slash commands.
  # @param line [String] User input.
  def receive_line(line)
    line.chomp.match(/^\/([a-zA-Z?]+)\s*(.*)/) do |m|
      cmd   = m[1]
      args  = m[2]

      if handler = SLASH_HANDLERS[cmd.to_sym]
        instance_exec(cmd, args, &handler)
      else
        puts "There is no such command."
      end
    end
  end

  World = HellGround::World

  # Sends channel message.
  on_slash :channel, :c do |cmd, args|
    @conn.instance_eval {
      return if @chat.nil?

      args.match(/(\S+)\s*(.+)/) do |m|
        @chat.send World::ChatMessage.new(
          World::ChatMessage::CHAT_MSG_CHANNEL,
          @player.lang,
          @player.guid,
          m[2],
          m[1]
        )
      end
    }
  end

  # Adds a friend.
  on_slash :friend do |cmd, args|
    @conn.instance_eval {
      @social.friend args unless @social.nil? || args.empty?
    }
  end

  # Displays friend list.
  on_slash :friends do |cmd, args|
    @conn.instance_eval {
      return if @social.nil?

      puts 'Friends:'
      @social.online.each { |guid, social| puts social.to_char }
    }
  end

  # Sends guild message.
  on_slash :guild, :g do |cmd, args|
    @conn.instance_eval {
      return if @chat.nil? || args.empty?

      @chat.send World::ChatMessage.new(
        World::ChatMessage::CHAT_MSG_GUILD,
        @player.lang,
        @player.guid,
        args
      )
    }
  end

  # Lists available commands.
  on_slash :help, :"?" do |cmd, args|
    puts "Available commands are:"
    SLASH_HANDLERS.each { |cmd, meth| print format '%-10s', "/#{cmd}" }
    puts
  end

  # Ignores a player.
  on_slash :ignore do |cmd, args|
    @conn.instance_eval {
      @social.ignore args unless @social.nil? || args.empty?
    }
  end

  # Displays ignore list.
  on_slash :ignores do |cmd, args|
    @conn.instance_eval {
      return if @social.nil?

      puts 'Ignores:'
      @social.ignores.each { |guid, social| puts social.to_char }
    }
  end

  # Item lookup.
  on_slash :item do |cmd, args|
    @conn.instance_eval {
      return if @player.nil? || args.empty?

      if item = World::Item.find(args.to_i)
        puts item
      else
        send_data World::Packets::ClientItemQuery.new(args.to_i)
      end
    }
  end

  # Joins a channel.
  on_slash :join do |cmd, args|
    @conn.instance_eval {
      @chat.join args unless @chat.nil? || args.empty?
    }
  end

  # Leaves a channel.
  on_slash :leave do |cmd, args|
    @conn.instance_eval {
      @chat.leave args unless @chat.nil? || args.empty?
    }
  end

  # Character selection.
  on_slash :login do |cmd, args|
    @conn.instance_eval {
      return if @chars.nil? || args.empty?

      if player = @chars.select { |player| player.to_char.name == args }.first
        @player = player

        puts "Logging in as #{player.to_char.name}."
        send_data World::Packets::ClientPlayerLogin.new(player)
      else
        puts "Character not found."
      end
    }
  end

  # Logout request.
  on_slash :logout, :camp do |cmd, args|
    @conn.instance_eval {
      send_data World::Packets::ClientLogoutRequest.new unless @player.nil?
    }
  end

  # Sends officer message.
  on_slash :officer, :o do |cmd, args|
    @conn.instance_eval {
      return if @chat.nil? || args.empty?

      @chat.send World::ChatMessage.new(
        World::ChatMessage::CHAT_MSG_OFFICER,
        @player.lang,
        @player.guid,
        args
      )
    }
  end

  # Sends party message.
  on_slash :party, :p do |cmd, args|
    @conn.instance_eval {
      return if @chat.nil? || args.empty?

      @chat.send World::ChatMessage.new(
        World::ChatMessage::CHAT_MSG_PARTY,
        @player.lang,
        @player.guid,
        args
      )
    }
  end

  # Quest lookup.
  on_slash :quest do |cmd, args|
    @conn.instance_eval {
      return if @player.nil? || args.empty?

      if quest = World::Quest.find(args.to_i)
        puts quest
      else
        send_data World::Packets::ClientQuestQuery.new(args.to_i)
      end
    }
  end

  # Quits the application.
  on_slash :quit do |cmd, args|
    @conn.stop!
  end

  # Sends raid message.
  on_slash :raid, :ra do |cmd, args|
    @conn.instance_eval {
      return if @chat.nil? || args.empty?

      @chat.send World::ChatMessage.new(
        World::ChatMessage::CHAT_MSG_RAID,
        @player.lang,
        @player.guid,
        args
      )
    }
  end

  # Replies last whisper target.
  on_slash :reply, :r do |cmd, args|
    @conn.instance_eval {
      return if @whisper_target.nil? || @chat.nil? || args.empty?

      @chat.send World::ChatMessage.new(
        World::ChatMessage::CHAT_MSG_WHISPER,
        @player.lang,
        @player.guid,
        args,
        @whisper_target
      )
    }
  end

  # Guild roster query.
  on_slash :roster do |cmd, args|
    @conn.instance_eval {
      send_data World::Packets::ClientGuildRoster.new unless @player.nil?
    }
  end

  # Says something.
  on_slash :say, :s do |cmd, args|
    @conn.instance_eval {
      return if @chat.nil? || args.empty?

      @chat.send World::ChatMessage.new(
        World::ChatMessage::CHAT_MSG_SAY,
        @player.lang,
        @player.guid,
        args
      )
    }
  end

  # Deletes a friend.
  on_slash :unfriend do |cmd, args|
    @conn.instance_eval {
      @social.unfriend args unless @social.nil? || args.empty?
    }
  end

  # Deletes an ignore.
  on_slash :unignore do |cmd, args|
    @conn.instance_eval {
      @social.unignore args unless @social.nil? || args.empty?
    }
  end

  # Whispers somebody.
  on_slash :whisper, :w do |cmd, args|
    @conn.instance_eval {
      return if @chat.nil? || args.empty?

      args.match(/(\S+)\s*(.+)/) do |m|
        @whisper_target = m[1]

        @chat.send World::ChatMessage.new(
          World::ChatMessage::CHAT_MSG_WHISPER,
          @player.lang,
          @player.guid,
          m[2],
          m[1]
        )
      end
    }
  end

  # Yells something.
  on_slash :yell, :y do |cmd, args|
    @conn.instance_eval {
      return if @chat.nil? || args.empty?

      @chat.send World::ChatMessage.new(
        World::ChatMessage::CHAT_MSG_YELL,
        @player.lang,
        @player.guid,
        args
      )
    }
  end

  # Sets verbose mode.
  on_slash :verbose do |cmd, args|
    @options[:verbose] = args.to_sym == :on
  end

  # Who query.
  on_slash :whois do |cmd, args|
    @conn.instance_eval {
      send_data World::Packets::ClientNameQuery.new(args.to_i) unless @player.nil? || args.empty?
    }
  end

  on_slash :supress do |cmd, args|
    args.split.each { |op| @opcode_verbose_flags[op.to_i(0)] = false }
  end

  on_slash :unsupress do |cmd, args|
    args.split.each { |op| @opcode_verbose_flags[op.to_i(0)] = true }
  end
end
