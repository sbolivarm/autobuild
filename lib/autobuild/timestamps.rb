module Autobuild
    STAMPFILE = "autobuild-stamp"

    class << self
        # The set of global ignores for SourceTreeTask
        #
        # Regular expressions added to this set will be used to determine if a
        # source tree has or has not changed
        attr_reader :ignored_files
    end
    @ignored_files = Array.new

    # Add a file and/or a regular expression to the ignore list
    #
    # The matching paths will not be considered when looking if a source tree
    # has been updated or not.
    def self.ignore(path)
        if path.kind_of?(Regexp)
            ignored_files << path
        else
            ignored_files << Regexp.new("^#{Regexp.quote(path)}")
        end
    end

    def self.tree_timestamp(path, *exclude)
        # Exclude autobuild timestamps
        exclude << (/#{Regexp.quote(STAMPFILE)}$/)
        exclude << (/\.autobuild-patches$/)

        Autobuild.message "getting tree timestamp for #{path}" if Autobuild.debug
        latest = Time.at(0)
        latest_file = ""

        Find.find(path) do |p|
            Find.prune if File.basename(p) =~ /^\./
            exclude.each do |pattern| 
                if pattern === p
                    Autobuild.message "  excluding #{p} because of #{pattern}" if Autobuild.debug
                    Find.prune
                end
            end
            next if !File.file?(p)

            p_time = File.mtime(p)
            if latest < p_time
                latest = p_time
                latest_file = p
            end
        end

        Autobuild.message "  newest file: #{latest_file} at #{latest}" if Autobuild.debug
        return latest_file, latest
    end

    class SourceTreeTask < Rake::Task
        attr_accessor :exclude

        attr_reader :newest_file
        attr_reader :newest_time

        def initialize(*args, &block)
            @exclude = Autobuild.ignored_files.dup
            super
        end
            
        def timestamp
            if @newest_time
                return @newest_time
            end

            @newest_file, @newest_time =
                Autobuild.tree_timestamp(name, %r#(?:^|/)(?:CVS|_darcs|\.svn)$#, *@exclude)
            @newest_time
        end
    end
    def self.source_tree(path, &block)
        task = SourceTreeTask.define_task(path)
        block.call(task) unless !block
        task
    end
            
    def self.get_stamp(stampfile)
        return Time.at(0) if !File.exist?(stampfile)
        return File.mtime(stampfile)
    end

    def self.hires_modification_time?
        if @hires_modification_time.nil?
            Tempfile.open('test') do |io|
                io.flush
                p_time = File.mtime(io.path)
                @hires_modification_time = (p_time.tv_usec != 0)
            end
        end
        @hires_modification_time
    end

    def self.touch_stamp(stampfile)
        Autobuild.message "Touching #{stampfile}" if Autobuild.debug
        dir = File.dirname(stampfile)
        if File.exist?(dir) && !File.directory?(dir)
            raise "#{dir} exists and is not a directory"
        elsif !File.exist?(dir)
            FileUtils.mkdir_p dir
        end
        FileUtils.touch(stampfile)

        if !hires_modification_time?
            # File modification times on most Unix filesystems have a granularity of
            # one second, so we (unfortunately) have to sleep 1s to make sure that
            # time comparisons will work as expected.
            sleep(1)
        end
    end
end

