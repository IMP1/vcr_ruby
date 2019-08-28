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
  - [ ] Merge branches          merge
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
  - [X] Ignore files
  - [ ] Just store deltas

=end

module Actions

    module Frames

        CREATE = "new"
        MERGE  = "merge"
        SHOW   = "show"
        LIST   = "list"

    end

    module Tracks

        CREATE = "new"
        DELETE = "delete"
        MODIFY = "modify"
        SHOW   = "show"
        LIST   = "list"

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
require_relative 'diffy/diffy'
require_relative 'console_colours'
require_relative 'console_directions'

COMMIT_TEMPLATE = <<~END
    # This is a commit message. Make it a good one!
END

WINDOWS_PLATFORMS = ["bccwin", "cygwin", "djgpp", "mingw", "mswin"]

Diffy::Diff.default_format = :color

def existing_repo?
    return File.exists?(root)
end

def ensure_vcr
    if not existing_repo?
        puts("This isn't a vcr directory. User `vcr init` to make it one.")
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

def get_object_reference(object_name)
    if Dir.entries(vcr_path("frames")).one? { |f| f.start_with? object_name }
        frame = Dir.entries(vcr_path("frames")).find { |f| f.start_with? object_name }
        return frame

    elsif File.file?(vcr_path("tags", object_name))
        return "ref: tags/#{object_name}"

    elsif File.file?(vcr_path("tracks", object_name))
        return "ref: tracks/#{object_name}"

    else
        output("'#{object_name}' not recognised as either a track, tag, or frame.")
        exit(1)
    end
end

def get_frame(frame_reference)
    while frame_reference.start_with? "ref: "
        return nil if !File.file?(vcr_path(frame_reference[5..-1]))
        frame_reference = File.read(vcr_path(frame_reference[5..-1]))
    end
    return frame_reference
end

def get_common_ancestor(frame1, frame2)
    frame1_ancestors = [frame1]
    frame2_ancestors = [frame2]
    loop do 
        next_source_parent = File.read(vcr_path("frames", frame1_ancestors.last, "parent"))
        frame1_ancestors.push(next_source_parent) if !next_source_parent.empty?
        next_target_parent = File.read(vcr_path("frames", frame2_ancestors.last, "parent"))
        frame2_ancestors.push(next_target_parent) if !next_target_parent.empty?
        break if frame1_ancestors.any? { |ancestor| frame2_ancestors.include?(ancestor) }
    end
    merge_ancestor = frame2_ancestors.find { |ancestor| frame1_ancestors.include?(ancestor) }
    return merge_ancestor
end

def has_ancestor?(frame, ancestor)
    current_frame = frame
    loop do
        parent = File.read(vcr_path("frames", current_frame, "parent"))
        return false if parent.empty?
        return true if parent == ancestor
        current_frame = parent
    end
end

def get_setting(*keys)
    case keys[0]
    when "interface"
        case keys[1]
        when "editor"
            return "notepad"
        when "editor-args"
            return "-w"
        end
    when "user"
        case keys[1]
        when "name"
            return nil
        end
    end 
end

def current_frame
    head = File.read(vcr_path("HEAD"))
    return get_frame(head)
end

def add_to_log(message)
    # Standardise an event log.
    # datetime, author, event type, message
    File.open(vcr_path(".log"), 'a') do |f|
        f.write(message + "\n")
    end
end

def output(message)
    add_to_log(message)
    $stdout.puts(message)
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
    Dir.mkdir(File.join(dir, "tracks"))  # all track HEADs
    Dir.mkdir(File.join(dir, "roots"))   # all track origins
    Dir.mkdir(File.join(dir, "tags"))    # all tags
    Dir.mkdir(File.join(dir, "staging")) # staging directory

    File.write(File.join(dir, "config"), "") # config file
    File.write(File.join(dir, "HEAD"), "")   # current head
    File.write(File.join(dir, ".log"), "")   # log of all actions

    add_to_log(">>> init #{args[0] || Dir.pwd}")
    output("New vcr repository")
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
            output("Track #{track_name} already exists")
            exit(2)
        end

        head = current_frame
        FileUtils.mkdir_p(File.dirname(vcr_path("tracks", track_name)))
        File.write(vcr_path("tracks", track_name), head)
        FileUtils.mkdir_p(File.dirname(vcr_path("roots", track_name)))
        File.write(vcr_path("roots", track_name), current_frame)
        output("Created #{track_name} track at #{head.empty? ? "initialisation" : head}")

    when Actions::Tracks::LIST
        Dir.glob(vcr_path("tracks", "**", "*")) do |item|
            next if item == '.' or item == '..' or not File.file?(item)
            track_name = item.sub(vcr_path("tracks"), "")[1..-1]
            output(track_name)
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
            output(frame[0...8] + " : " + File.read(vcr_path("frames", frame, "message")).inspect)
        end

    when Actions::Tracks::DELETE
        track_name = args[1]
        if !File.exists?(vcr_path("tracks", track_name))
            output("Missing #{track_name} track")
            exit(2)
        end

        # TODO: Check that track has been merged in and warn if not.
        unmerged_track = true
        if unmerged_track
            prompt = "This track has not been merged yet. Are you sure? (y/n)\n"
            if not get_confirmation(prompt) { |response| ["Y", "YES"].include?(response.upcase) }
                return
            end
        end
        File.delete(vcr_path("tracks", track_name))
        File.delete(vcr_path("roots", track_name))
        output("Deleted #{track_name} track")

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
            output("Tag #{tag_name} already exists")
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
        output("Created #{tag_name} tag at #{head}")

    when Actions::Tags::LIST
        Dir.glob(vcr_path("tags", "**", "*")) do |item|
            next if item == '.' or item == '..' or not File.file?(item)
            tag_name = item.sub(vcr_path("tags"), "")[1..-1]
            output(tag_name)
        end

    when Actions::Tags::SHOW
        tag_name = args[1]


    when Actions::Tags::DELETE
        tag_name = args[1]

        if !File.exists?(vcr_path("tags", tag_name))
            output("Missing #{tag_name} tag")
            exit(2)
        end

        File.delete(vcr_path("tags", tag_name))
        output("Deleted #{tag_name} tag")

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
            output("No changes in #{filename}")
            next
        end
        FileUtils.cp(repo_path(filename), vcr_path("staging", filename))
        output("Staged #{filename}")
    end
end

def remove(args)
    ensure_vcr
    add_to_log(">>> unstage #{args.map{|a|a.inspect}.join(" ")}")

    args.each do |filename|
        FileUtils.rm(vcr_path("staging", filename))
        output("Unstaged #{filename}")
    end
end

def checkout(args)
    ensure_vcr
    add_to_log(">>> checkout #{args.map{|a|a}.join(" ")}")

    target = args[0]

    if Dir.entries(vcr_path("frames")).one? { |f| f.start_with? target }
        frame = Dir.entries(vcr_path("frames")).find { |f| f.start_with? target }
        File.write(vcr_path("HEAD"), frame)
        output("At frame #{frame}")

    elsif File.file?(vcr_path("tags", target))
        File.write(vcr_path("HEAD"), "ref: tags/#{target}")
        output("At tag #{target}")

    elsif File.file?(vcr_path("tracks", target))
        File.write(vcr_path("HEAD"), "ref: tracks/#{target}")
        output("On track #{target}")

    else
        output("'#{target}' not recognised as either a track, tag, or frame.")
        exit(2)
    end
end

def status(args)
    ensure_vcr
    add_to_log(">>> status")

    ignored_files = []
    if File.file?(repo_path(".vcr-ignore"))
        ignored_files = File.readlines(repo_path(".vcr-ignore")).map { |f| f.chomp }
    end

    if File.file?(vcr_path("tracks", current_track))
        puts("On track #{ConsoleColour.cyan(current_track)}")
        add_to_log("On track #{current_track}")
    else
        puts("At frame #{ConsoleColour.cyan(current_track)}")
        add_to_log("At frame #{current_track}")
    end

    staged_files = []
    Dir.glob(vcr_path("staging", "**", "*")) do |item|
        next if item == '.' or item == '..' or not File.file?(item)
        file_name = item.sub(vcr_path("staging"), "")[1..-1]
        staged_files.push(file_name)
    end
    puts("")
    output("Changes staged for new frame:")
    staged_files.each do |file_name| 
        puts("\t" + ConsoleColour.green(file_name))
        add_to_log("\t" + file_name)
    end

    unstaged_files = []
    Find.find(repo_path) do |item|
        next if item == '.' or item == '..'
        Find.prune if File.basename(item) == '.vcr'
        Find.prune if ignored_files.include?(File.basename(item))
        if File.file?(item)
            file_name = item.sub(repo_path, "")[1..-1]
            staged_item = vcr_path("staging", file_name)
            commited_item = vcr_path("frames", current_frame, ".frame", file_name)
            if File.file?(staged_item)
                next if FileUtils.identical?(item, staged_item)
            end
            if File.file?(commited_item)
                next if FileUtils.identical?(item, commited_item)
            end
            unstaged_files.push(file_name)
        end
    end
    puts("")
    output("Changes not staged for new frame:")
    unstaged_files.each do |file_name| 
        puts("\t" + ConsoleColour.red(file_name)) 
        add_to_log("\t" + file_name) 
    end

end

def diff(args)
    ensure_vcr
    add_to_log(">>> diff #{args.map{|a|a}.join(" ")}")

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
        output("\n" + diff_string)
    end
end

def frame(args)
    ensure_vcr
    add_to_log(">>> frame #{args.map{|a|a.inspect}.join(" ")}")

    command = args[0] # TODO: change this to `shift` to shift the array along, as this is no longer an arg, really.

    case command
        
    when "new"
        if Dir.empty?(vcr_path("staging"))
            output("Nothing to commit to new frame")
            exit(2)
        end

        message = args[1]
        if message.nil?
            editor = get_setting("interface", "editor")
            editor_args = get_setting("interface", "editor-args")
            temp_filename = vcr_path("commit-message")
            File.write(temp_filename, COMMIT_TEMPLATE)
            `start #{editor} "#{temp_filename}" #{editor_args}`
            message = File.read(temp_filename)
        end
        # TODO: only accept full messages in an editor?

        author     = get_setting("user", "name") || ENV['USER'] || ENV['USERNAME']
        now        = DateTime.now.to_s
        parent     = current_frame
        frame_name = Digest::SHA1.hexdigest(now + author + parent + message)
        
        Dir.mkdir(vcr_path("frames", frame_name))

        if !File.file?(vcr_path("tracks", current_track))
            puts "Warning: You're not at the end of a track."
            puts "Either create a new track from this frame, or go to the end of the track."
            add_to_log("Not at end of track; Cancelling new frame")
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

        staged_files = Dir.glob(vcr_path("staging", "*"), File::FNM_DOTMATCH) - %w[. ..]
        FileUtils.rm_rf(staged_files)
        output("Created frame #{frame_name}")

    when Actions::Frames::LIST

    when Actions::Frames::SHOW

    end
end

def merge(args)
    # Good description of merges: 
    # https://www.atlassian.com/git/tutorials/using-branches/git-merge
    ensure_vcr
    add_to_log(">>> merge #{args.map{|a|a.inspect}.join(" ")}")

    merge_target = get_frame(get_object_reference(args[1] || current_frame))
    merge_source = get_frame(get_object_reference(args[0]))

    add_to_log("Merge source is #{merge_source}")
    add_to_log("Merge target is #{merge_target}")

    if merge_source == merge_target
        output "No merge necessary - Same frame"
        exit(0)
    end

    # TODO: merge should keep track of branches here, because otherwise they're lost forever.
    #       if one or both frames are the current tips of branches, then record that in the frame
    #       somewhere.

    # TODO: find first common ancestor of frames
    # TODO: test this with offset ancestor lenghts (what happens if one branch runs out of ancestors?)
    # TODO: test this with fast-forwardable branches (what happens when one commit is an ancestor of the other)
    merge_ancestor = get_common_ancestor(merge_source, merge_target)
    p merge_ancestor

    # TODO: play out changes on one "branch" to other "branch"
    # TODO: create a commit with a merge file to signify it as a merge. This commit will have references to 
    #       the the source and target and the ancestor. This commit will also have any changes necessary to 
    #       resolve any merge conflicts in its .frame folder.


end

def show_tree(args)
    ensure_vcr
    track_count = Dir[vcr_path("tracks", "*")].length
    frame_count = Dir[vcr_path("frames", "*")].length

    leaf_frames = Dir[vcr_path("tracks", "*")].map do |f| 
        track_name = f.sub(vcr_path("tracks"), "")[1..-1]
        track_root = File.read(vcr_path("roots", track_name))
        track_head = File.read(f)
        [track_name, track_root, track_head]
    end
    leaf_frames.sort! { |a, b| File.read(vcr_path("frames", a[1], "timestamp")) <=> File.read(vcr_path("frames", b[1], "timestamp")) }

    all_frames = Dir[vcr_path("frames", "*")].map do |f|
        frame_name = f.sub(vcr_path("frames"), "")[1..-1]
        frame_track = leaf_frames.find { |leaf| has_ancestor?(leaf[1], frame_name) }
        frame_track = (frame_track || ["master"])[0] # TODO: delete this once repo is in consistent state (no parentless commits except initial one)
        [frame_name, frame_track]
    end
    all_frames.sort! { |a, b| File.read(vcr_path("frames", a[0], "timestamp")) <=> File.read(vcr_path("frames", b[0], "timestamp")) }
    
    all_frames.each do |frame|
        col = leaf_frames.size.times.find do |i|
            leaf_frames[i][0] == frame[1]
        end
        print "@"
        print "--"
    end

    puts "#{frame_count} frames"
    width = track_count * 2 - 1
    puts "|" + " |" * (track_count-1)
    # TODO: create a visual representation of the tracks like. vertical branches with commit references
    #       and tags, and branches
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
    when "frame"
        frame(args)
    when "merge"
        merge(args)
    when "status"
        status(args)
    when "diff"
        diff(args)
    when "checkout"
        checkout(args)
    when "history"
        show_tree(args)
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

=begin

| | | |
| | | |
|/  | |
| _/  |
|/    |
| ___/
|/
|

      @
    @ |
  @ | |
@ | | |
| | | @
|/  | |
@ __|/
|/  |
@ _/
|/
@

=end