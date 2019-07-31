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
  - [X] Stage files
  - [X] List staged files
  - [X] Unstage files
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

WINDOWS_PLATFORMS = ["bccwin", "cygwin", "djgpp", "mingw", "mswin"]

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

def vcr_path(*args)
    return File.join(root, *args)
end

def repo_path(*args)
    return File.join(Dir.pwd, *args)
end

def current_track
    head = File.read(vcr_path("HEAD"))
    if head.start_with? "ref: "
        return head[5..-1].sub("tracks/", "")
    end
    return head
end

def current_frame
    head = File.read(vcr_path("HEAD"))
    if head.start_with? "ref: "
        head = File.read(vcr_path(head[5..-1]))
    end
    return head
end

def add_to_log(message)
    # Standardise an event log.
    # datetime, author, event type, message
    File.open(vcr_path(".log"), 'a') do |f|
        f.write(message + "\n")
    end
end

def help(args)
    if args[0].nil?
        # Print general help
        puts "VCR Help"
    else
        # Print help on command
        puts "VCR Help about #{args[0]}"
    end
end

def create_frame(frame_name)
    
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
    if WINDOWS_PLATFORMS.any? { |platform| RUBY_PLATFORM.include?(platform) }
        IO.popen(['attrib', '+H', dir])  # hide .vcr folder on windows
    end
    Dir.mkdir(File.join(dir, "frames"))  # all snapshots
    Dir.mkdir(File.join(dir, "tracks"))  # all tracks
    Dir.mkdir(File.join(dir, "tags"))    # all tags
    Dir.mkdir(File.join(dir, "staging")) # staging directory

    File.write(File.join(dir, "config"), "") # config file
    File.write(File.join(dir, "HEAD"), "")   # current head
    File.write(File.join(dir, ".log"), "")   # log of all actions

    add_to_log(">>> init #{args[0] || Dir.pwd}")
    track([Actions::Tracks::CREATE, "master"]) # create master track
    checkout(["master"])                       # checkout master track
end

def track(args)
    ensure_vcr
    add_to_log(">>> track #{args.join(" ")}")

    command = args[0]
    case command
    when Actions::Tracks::CREATE
        track_name = args[1]

        # TODO: check if valid name

        if File.exists?(vcr_path("tracks", track_name))
            puts "track already exists."
            add_to_log("track #{track_name} already exists")
            exit(1)
        end

        head = File.read(vcr_path("HEAD"))
        if head.start_with? "ref: "
            head = File.read(vcr_path(head[5..-1]))
        end
        FileUtils.mkdir_p(File.dirname(vcr_path("tracks", track_name)))
        File.write(vcr_path("tracks", track_name), head)
        add_to_log("created #{track_name} track at #{head}")

    when Actions::Tracks::LIST
        Dir.glob(vcr_path("tracks", "**", "*")) do |item|
            next if item == '.' or item == '..' or not File.file?(item)
            track_name = item.sub(vcr_path("tracks"), "")[1..-1]
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

    args.each do |filename|
        FileUtils.cp(repo_path(filename), vcr_path("staging", filename))
        add_to_log(">>> stage #{filename}")
    end
end

def remove(args)
    ensure_vcr

    args.each do |filename|
        FileUtils.rm(vcr_path("staging", filename))
        add_to_log(">>> unstage #{filename}")
    end
end

def checkout(args)
    ensure_vcr
    add_to_log(">>> checkout #{args.join(" ")}")

    target = args[0]
    # TODO: check if valid target

    if File.file?(vcr_path("tracks", target))
        File.write(vcr_path("HEAD"), "ref: tracks/#{target}")
        add_to_log("ref: tracks/#{target}")

    elsif File.file?(vcr_path("tags", target))
        File.write(vcr_path("HEAD"), "ref: tags/#{target}")
        add_to_log("ref: tags/#{target}")

    elsif Dir.entries(vcr_path("frames")).one? { |f| f.start_with? target }
        frame = Dir.entries(vcr_path("frames")).find { |f| f.start_with? target }
        File.write(vcr_path("HEAD"), frame)
        add_to_log(frame)

    else
        add_to_log("invalid checkout target")
        puts "'#{target}' not recognised as either a track, tag, or frame."
        exit(1)
    end
end

def status(args)
    ensure_vcr

    ignored_files = []
    if File.file?(repo_path(".vcr-ignore"))
        ignored_files = File.readlines(repo_path(".vcr-ignore")).map { |f| f.chomp }
    end

    puts "On track #{current_track}"
    puts

    puts "Changes staged for commit:"
    Dir.glob(vcr_path("staging", "**", "*")) do |item|
        next if item == '.' or item == '..' or not File.file?(item)
        file_name = item.sub(vcr_path("staging"), "")[1..-1]
        # TODO: add colour here (green)
        puts "\t" + file_name
    end
    puts

    puts "Changes not staged for commit:"
    Find.find(repo_path) do |item|
        next if item == '.' or item == '..'
        Find.prune if File.basename(item) == '.vcr-ignore'
        Find.prune if File.basename(item) == '.vcr'
        Find.prune if ignored_files.include?(File.basename(item))
        if File.file?(item)
            file_name = item.sub(repo_path, "")[1..-1]
            staged_item = vcr_path("staging", file_name)
            if File.file?(staged_item)
                next if File.mtime(item) <= File.mtime(staged_item)
            end
            # TODO: add colour here (red)
            puts "\t" + file_name
        end
    end

end

def diff(args)
    # Check out https://github.com/samg/diffy as a gem to just do alla this for you.
end

def commit(args)
    ensure_vcr
    message = args[0]
    if message.nil?
        print("A commit message must be provided.")
        exit(0)
    end
    author     = ENV['USER'] || ENV['USERNAME']
    now        = DateTime.now.to_s
    parent     = current_frame
    frame_name = Digest::SHA1.hexdigest(now + author + parent + message)
    
    Dir.mkdir(vcr_path("frames", frame_name))
    Dir.mkdir(vcr_path("frames", frame_name, ".frame"))

    File.write(vcr_path("HEAD"), frame_name)

    source_path = vcr_path("staging")
    target_path = vcr_path("frames", frame_name, ".frame")
    Find.find(source_path) do |source|
        target = source.sub(/^#{source_path}/, target_path)
        # TODO: ignore files in a `.vcr-ignore` file as well.
        if File.directory? source
            Find.prune if File.basename(source) == '.vcr'
            FileUtils.mkdir target unless File.exists? target
        else
            FileUtils.copy source, target
        end
    end
    FileUtils.rm_rf(Dir.glob(vcr_path("staging", "*")))
end

def handle_command(command, args)
    case command
    when "help"
        help(args)
    when "init"
        init(args)
    when "add", "stage"
        add(args)
    when "rm", "unstage"
        remove(args)
    when "track"
        track(args)
    when "commit"
        commit(args)
    when "status"
        status(args)
    when "diff"
        diff(args)
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