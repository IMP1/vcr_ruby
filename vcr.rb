#!/usr/bin/env ruby

=begin
    * http://tom.preston-werner.com/2009/05/19/the-git-parable.html
    * http://ryanheathcote.com/git/build-your-own-vcs
=end

=begin

# Available Actions

  - [X] Create VCR Repo         init
  - [X] Create branches         branch new
  - [X] List branches           branch list
  - [X] Delete branches         branch delete
  - [X] Switch branches         checkout
  - [X] Create tags             tag new
  - [X] List tags               tag list
  - [X] Delete tags             tag delete
  - [X] Go to tag               checkout
  - [X] Stage files             stage
  - [X] List staged files       ???
  - [X] Unstage files           unstage
  - [X] Commit files            commit
  - [ ] Push commits            ???
  - [ ] List commits            history
  - [ ] Fetch commits           fetch
  - [ ] Merge branches          merge
  - [X] Ignore files

=end

module Actions

    module Tracks

        CREATE = "new"
        DELETE = "delete"
        LIST   = "list"
        MERGE  = "merge"
        MODIFY = "modify"
        SHOW   = "show"

    end

    module Tags

        CREATE = "new"
        DELETE = "delete"
        LIST   = "list"
        MODIFY = "modify"
        SHOW   = "show"

    end

end

require 'date'
require 'digest'
require 'find'
require 'fileutils'
require_relative 'console_colours'
require_relative 'diffy/diffy'


WINDOWS_PLATFORMS = ["bccwin", "cygwin", "djgpp", "mingw", "mswin"]

Diffy::Diff.default_format = :color

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
    while head.start_with? "ref: "
        return head[5..-1].sub("tracks/", "")
    end
    return head
end

def current_frame
    head = File.read(vcr_path("HEAD"))
    while head.start_with? "ref: "
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

def get_confirmation(prompt, &block)
    print prompt
    response = $stdin.gets.chomp
    return block.call(response)
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
    add_to_log(">>> track #{args.map{|a|a}.join(" ")}")

    command = args[0]
    case command
    when Actions::Tracks::CREATE
        track_name = args[1]
        flags = args[2..-1].select { |a| a.start_with?('-') }
        # TODO: check if valid name

        if File.exists?(vcr_path("tracks", track_name))
            puts "track already exists."
            add_to_log("track #{track_name} already exists")
            exit(2)
        end

        head = File.read(vcr_path("HEAD"))
        while head.start_with? "ref: "
            head = File.read(vcr_path(head[5..-1]))
        end
        FileUtils.mkdir_p(File.dirname(vcr_path("tracks", track_name)))
        File.write(vcr_path("tracks", track_name), head)
        add_to_log("created #{track_name} track at #{head.empty? ? "repo creation" : head}")

    when Actions::Tracks::LIST
        Dir.glob(vcr_path("tracks", "**", "*")) do |item|
            next if item == '.' or item == '..' or not File.file?(item)
            track_name = item.sub(vcr_path("tracks"), "")[1..-1]
            puts track_name
            add_to_log(track_name)
        end

    when Actions::Tracks::SHOW
        track_name = args[1] || current_track
        head = File.read(vcr_path("tracks", track_name))
        while head.start_with? "ref: "
            head = File.read(vcr_path(head[5..-1]))
        end
        history = []
        until head.empty?
            history.push(head)
            head = File.read(vcr_path("frames", head, "parent"))
        end
        history.each do |frame| 
            puts frame 
            add_to_log(frame)
        end

    when Actions::Tracks::DELETE
        track_name = args[1]
        if !File.exists?(vcr_path("tracks", track_name))
            puts "no such track #{track_name}."
            add_to_log("missing #{track_name} track")
            exit(2)
        end

        # TODO: Check that track has been merged in and warn if not.
        unmerged_track = true
        if unmerged_track
            prompt = "This track has not been merged yet. Are you sure? (y/n)\n"
            if get_confirmation(prompt) { |response| response != "y" and response != "yes" }
                return
            end
        end
        File.delete(vcr_path("tracks", track_name))
        add_to_log("deleted #{track_name} track")

    when Actions::Tracks::MERGE

    else
        exit(2)
    end
end

def tag(args)
    ensure_vcr
    add_to_log(">>> tag #{args.map{|a|a}.join(" ")}")

    command = args[0]
    case command
    when Actions::Tags::CREATE
        tag_name = args[1]
        # TODO: check if valid name

        if File.exists?(vcr_path("tags", tag_name))
            puts "tag already exists."
            add_to_log("tag #{tag_name} already exists")
            exit(2)
        end

        head = File.read(vcr_path("HEAD"))
        while head.start_with? "ref: "
            head = File.read(vcr_path(head[5..-1]))
        end
        FileUtils.mkdir_p(File.dirname(vcr_path("tags", tag_name)))
        File.write(vcr_path("tags", tag_name), head)
        if head.empty?
            head = "repo creation"
        end
        add_to_log("created #{tag_name} tag at #{head}")

    when Actions::Tags::LIST
        Dir.glob(vcr_path("tags", "**", "*")) do |item|
            next if item == '.' or item == '..' or not File.file?(item)
            tag_name = item.sub(vcr_path("tags"), "")[1..-1]
            puts tag_name
            add_to_log(tag_name)
        end

    when Actions::Tags::SHOW
        tag_name = args[1]


    when Actions::Tags::DELETE
        tag_name = args[1]

        if !File.exists?(vcr_path("tags", tag_name))
            puts "no such tag #{tag_name}"
            add_to_log("missing #{tag_name} tag")
            exit(2)
        end

        File.delete(vcr_path("tags", tag_name))
        add_to_log("deleted #{tag_name} tag")

    else
        exit(2)
    end
end

def add(args)
    ensure_vcr
    add_to_log(">>> stage #{args.map{|a|a.inspect}.join(" ")}")

    args.each do |filename|
        if File.exists?(vcr_path("staging", filename)) and 
           FileUtils.identical?(repo_path(filename), vcr_path("staging", filename))
            puts "There have been no changes in #{filename}."
            add_to_log("no changes in #{filename}")
            next
        end
        FileUtils.cp(repo_path(filename), vcr_path("staging", filename))
        add_to_log("staged #{filename}")
    end
end

def remove(args)
    ensure_vcr
    add_to_log(">>> unstage #{args.map{|a|a.inspect}.join(" ")}")

    args.each do |filename|
        FileUtils.rm(vcr_path("staging", filename))
        add_to_log("unstaged #{filename}")
    end
end

def checkout(args)
    ensure_vcr
    add_to_log(">>> checkout #{args.map{|a|a}.join(" ")}")

    target = args[0]

    if Dir.entries(vcr_path("frames")).one? { |f| f.start_with? target }
        frame = Dir.entries(vcr_path("frames")).find { |f| f.start_with? target }
        File.write(vcr_path("HEAD"), frame)
        add_to_log(frame)

    elsif File.file?(vcr_path("tags", target))
        File.write(vcr_path("HEAD"), "ref: tags/#{target}")
        add_to_log("ref: tags/#{target}")

    elsif File.file?(vcr_path("tracks", target))
        File.write(vcr_path("HEAD"), "ref: tracks/#{target}")
        add_to_log("ref: tracks/#{target}")

    else
        add_to_log("invalid checkout target")
        puts "'#{target}' not recognised as either a track, tag, or frame."
        exit(2)
    end
end

def status(args)
    ensure_vcr

    ignored_files = []
    if File.file?(repo_path(".vcr-ignore"))
        ignored_files = File.readlines(repo_path(".vcr-ignore")).map { |f| f.chomp }
    end

    if File.file?(vcr_path("tracks", current_track))
        puts "On track #{ConsoleColour.cyan(current_track)}"
    else
        puts "At frame #{ConsoleColour.cyan(current_track)}"
    end

    staged_files = []
    Dir.glob(vcr_path("staging", "**", "*")) do |item|
        next if item == '.' or item == '..' or not File.file?(item)
        file_name = item.sub(vcr_path("staging"), "")[1..-1]
        staged_files.push(file_name)
    end
    puts "\nChanges staged for commit:"
    staged_files.each { |file_name| puts "\t" + ConsoleColour.green(file_name) }

    unstaged_files = []
    Find.find(repo_path) do |item|
        next if item == '.' or item == '..'
        Find.prune if File.basename(item) == '.vcr'
        Find.prune if ignored_files.include?(File.basename(item))
        if File.file?(item)
            file_name = item.sub(repo_path, "")[1..-1]
            staged_item = vcr_path("staging", file_name)
            if File.file?(staged_item)
                next if File.mtime(item) <= File.mtime(staged_item)
            end
            unstaged_files.push(file_name)
        end
    end
    puts "\nChanges not staged for commit:"
    unstaged_files.each { |file_name| puts "\t" + ConsoleColour.red(file_name) }

end

def diff(args)
    # TODO: get flags from args and allow for you to specify a source and target tracks
    ignore_new = false
    source = :working # this can be set to the staging area, or a specific track, or a frame, etc.
    target = :staging # this can be set to the staging area, or a specific track, or a frame, etc.

    source_path = case source
    when :working
        repo_path
    when :staging
        vcr_path("staging")
    else
    end

    target_path = case target
    when :working
        repo_path
    when :staging
        vcr_path("staging")
    else
    end
        

    ignored_files = []
    if File.file?(repo_path(".vcr-ignore"))
        ignored_files = File.readlines(repo_path(".vcr-ignore")).map { |f| f.chomp }
    end

    if args.empty?
        # Diff all in source directory.
        changed_files = []
        Find.find(source_path) do |item|
            next if item == '.' or item == '..'
            Find.prune if File.basename(item) == '.vcr'
            Find.prune if ignored_files.include?(File.basename(item))
            if File.file?(item)
                file_name = item.sub(source_path, "")[1..-1]
                staged_item = File.join(target_path, file_name)
                next if ignore_new and !File.file?(staged_item)
                if File.file?(staged_item)
                    next if FileUtils.identical?(item, staged_item)
                end
                changed_files.push(file_name)
            end
        end

    else
        # Only diff the provided files
        changed_files = args.select do |item|
            file_name = item.sub(source_path, "")[1..-1]
            staged_item = File.join(target_path, file_name)
            not File.file?(staged_item) or not FileUtils.identical?(item, staged_item)
        end
    end

    changed_files.each do |file_name|
        new_content = File.read(File.join(source_path, file_name))
        old_content = "" 
        if File.file?(File.join(target_path, file_name)) 
            old_content = File.read(File.join(target_path, file_name))
        end
        diff_string = Diffy::Diff.new(old_content, new_content, :include_diff_info => true).to_s
        diff_string.gsub!(/\-\-\-\s.+?$/) { "--- a/#{file_name}" }
        diff_string.gsub!(/\+\+\+\s.+?$/) { "+++ b/#{file_name}" }
        puts
        puts diff_string
    end
end

def commit(args)
    ensure_vcr
    add_to_log(">>> commit #{args.map{|a|a.inspect}.join(" ")}")

    if Dir.empty?(vcr_path("staging"))
        puts "There's nothing to commit. Stage some changes."
        add_to_log("nothing to commit")
        exit(2)
    end

    message = args[0]
    if message.nil?
        print("A commit message must be provided.")
        add_to_log("missing commit message")
        exit(2)
    end

    author     = ENV['USER'] || ENV['USERNAME']
    now        = DateTime.now.to_s
    parent     = current_frame
    frame_name = Digest::SHA1.hexdigest(now + author + parent + message)
    
    Dir.mkdir(vcr_path("frames", frame_name))

    if !File.file?(vcr_path("tracks", current_track))
        puts "Warning: You're not at the end of a track."
        puts "Either create a new track from this frame, or go to the end of the track."
        exit(2)
    end

    File.write(vcr_path("tracks", current_track), frame_name)

    source_path = vcr_path("staging")
    target_path = vcr_path("frames", frame_name, ".frame")
    Find.find(source_path) do |source|
        if File.directory? source
            Find.prune if File.basename(source) == '.vcr'
            FileUtils.mkdir target_path unless File.exists? target_path
        else
            FileUtils.copy source, target_path
        end
    end
    File.write(vcr_path("frames", frame_name, "timestamp"), now)
    File.write(vcr_path("frames", frame_name, "author"), author)
    File.write(vcr_path("frames", frame_name, "parent"), parent)
    File.write(vcr_path("frames", frame_name, "message"), message)
    File.write(vcr_path("frames", frame_name, "timestamp"), "now")
    File.open(vcr_path("frames", frame_name, "details"), 'w') do |file|
        file.puts(now)
        file.puts(author)
        file.puts(parent)
        file.puts(message)
    end

    FileUtils.rm_rf(Dir.glob(vcr_path("staging", "*")))
    add_to_log("created frame #{frame_name}")
end

def handle_command(command, args)
    case command
    when "help"
        help(args)
    when "init"
        init(args)
    when "stage"
        add(args)
    when "unstage"
        remove(args)
    when "track"
        track(args)
    when "tag"
        tag(args)
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
        puts "Unrecognised command #{command}."
        exit(2)
    end
end

def main
    command = ARGV[0]
    args = ARGV[1..-1]
    handle_command(command, args)
end

main