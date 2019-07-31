#!/usr/bin/env ruby

=begin
    * http://tom.preston-werner.com/2009/05/19/the-git-parable.html
    * http://ryanheathcote.com/git/build-your-own-vcs
=end

=begin

# Available Actions

  - [X] Create VCR Repo
  - [X] Create branches
  - [X] List branches
  - [X] Switch branches
  - [ ] Delete branches
  - [ ] Stage files
  - [ ] List staged files
  - [ ] Unstage files
  - [ ] Commit files
  - [ ] Push commits
  - [ ] List commits
  - [ ] Fetch commits
  - [ ] Merge branches
  - [ ] Ignore files

=end

module Actions

    module Tracks

        CREATE = "new"
        DELETE = "delete"
        LIST   = "list"
        MERGE  = "merge"
        MODIFY = "modify"

    end

    module Tags

        CREATE = "new"
        DELETE = "delete"
        LIST   = "list"
        MODIFY = "modify"

    end

    module Context

        CHECKOUT = "checkout"
        STATUS   = "status"

    end

end

require 'date'
require 'digest'
require 'find'
require 'fileutils'

def existing_repo?
    return File.exists?(root)
end

def ensure_vcr
    if not existing_repo?
        print("This isn't a vcr directory. User `vcr init` to make it one.")
        exit(0)
    end
end

def root
    return File.join(Dir.pwd, ".vcr")
end

def path(*args)
    return File.join(root, *args)
end

def current_track
    head = File.read(path("HEAD"))
    if head.start_with? "ref: "
        return path(head[5..-1]).sub(path("tracks"), "")[1..-1]
    end
    return head
end

def current_frame
    head = File.read(path("HEAD"))
    if head.start_with? "ref: "
        head = File.read(path(head[5..-1]))
    end
    return head
end

def add_to_log(message)
    # Standardise an event log.
    # datetime, author, event type, message
    File.open(path(".log"), 'a') do |f|
        f.write(message + "\n")
    end
end

def help(args)
    if args[0].nil?
        # Print general help
        puts "VCR Help"
    else
        # Print help on command
        puts "VCR Help about #{arg[0]}"
    end
end

def create_frame(frame_name)
    source_path = Dir.pwd
    target_path = path("frames", frame_name, ".frame")
    Find.find(source_path) do |source|
        target = source.sub(/^#{source_path}/, target_path)
        if File.directory? source
            Find.prune if File.basename(source) == '.vcr'
            FileUtils.mkdir target unless File.exists? target
        else
            FileUtils.copy source, target
        end
    end
end

def show_log(args)
    
end

def init(args)
    if existing_repo?
        puts "Already a vcr repository."
        return
    end
    dir = File.join(args[0] || Dir.pwd, ".vcr")

    Dir.mkdir(dir)                       # vcr directory
    Dir.mkdir(File.join(dir, "frames"))  # all snapshots
    Dir.mkdir(File.join(dir, "tracks"))  # all tracks
    Dir.mkdir(File.join(dir, "tags"))    # all tags
    Dir.mkdir(File.join(dir, "staging")) # staging directory

    File.write(File.join(dir, "config"), "") # config file
    File.write(File.join(dir, "HEAD"), "")   # current head
    File.write(File.join(dir, ".log"), "")   # log of all actions

    add_to_log(">>> init #{args[0] || Dir.pwd}")
    add_to_log("VCR initialised.")
    track([Actions::Tracks::CREATE, "master"])       # create master track
    checkout([Actions::Context::CHECKOUT, "master"]) # checkout master track
end

def track(args)
    ensure_vcr
    add_to_log(">>> track #{args.join(" ")}")

    command = args[0]
    case command
    when Actions::Tracks::CREATE
        track_name = args[1]

        # TODO: check if valid name

        if File.exists?(path("tracks", track_name))
            puts "track already exists."
            add_to_log("track #{track_name} already exists")
            exit(1)
        end

        head = File.read(path("HEAD"))
        if head.start_with? "ref: "
            head = File.read(path(head[5..-1]))
        end
        FileUtils.mkdir_p(File.dirname(path("tracks", track_name)))
        File.write(path("tracks", track_name), head)
        add_to_log("created #{track_name} track at #{head}")

    when Actions::Tracks::LIST
        Dir.glob(path("tracks", "**", "*")) do |item|
            next if item == '.' or item == '..' or not File.file?(item)
            track_name = item.sub(path("tracks"), "")[1..-1]
            puts track_name
            add_to_log(track_name)
        end

    when Actions::Tracks::DELETE
        # TODO: Check that track has been merged in and warn if not.

    when Actions::Tracks::MERGE

    else
        exit(1)
    end
end

def add(args)
    ensure_vcr

end

def checkout(args)
    ensure_vcr
    add_to_log(">>> checkout #{args.join(" ")}")

    target = args[0]
    # TODO: check if valid target

    if File.file?(path("tracks", target))
        File.write(path("HEAD"), "ref: tracks/#{target}")
        add_to_log("ref: tracks/#{target}")

    elsif File.file?(path("tags", target))
        File.write(path("HEAD"), "ref: tags/#{target}")
        add_to_log("ref: tags/#{target}")

    elsif Dir.entries(path("frames")).one? { |f| f.start_with? target }
        frame = Dir.entries(path("frames")).find { |f| f.start_with? target }
        File.write(path("HEAD"), frame)
        add_to_log(frame)

    else
        add_to_log("invalid checkout target")
        puts "'#{target}' not recognised as either a track, tag, or frame."
        exit(1)
    end
end

def status(args)
    ensure_vcr
    add_to_log(">>> status #{args.join(" ")}")


    puts "On track #{current_track
    add_to_log(">>> status #{args.join(" ")}")

end

def commit(args)
    ensure_vcr
    message = args[0]
    if message.nil?
        print("A commit message must be provided.")
        exit(0)
    end
    author      = ENV['USER'] || ENV['USERNAME']
    now         = DateTime.now.to_s
    parent      = current_frame
    commit_hash = Digest::SHA1.hexdigest(now + author + parent + message)
    
    Dir.mkdir(path("frames", commit_hash))
    Dir.mkdir(path("frames", commit_hash, ".frame"))

    File.write(path("HEAD"), commit_hash)

    create_frame(commit_hash)
    # TODO: only copy staged files
end

def handle_command(command, args)
    case command
    when "help"
        help(args)
    when "init"
        init(args)
    when "add"
        add(args)
    when "track"
        track(args)
    when "commit"
        commit(args)
    when "status"
        status(args)
    when "checkout"
        checkout(args)
    when "log"
        show_log(args)
    else
        exit(1)
    end
end

def main
    command = ARGV[0]
    args = ARGV[1..-1]
    handle_command(command, args)
end

main