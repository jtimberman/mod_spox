class RegexTracker < ModSpox::Plugin

    include Models
    def initialize(pipeline)
        super
        track = Group.find_or_create(:name => 'track')
        add_sig(:sig => 'track info (\d+)', :method => :score, :desc => 'Show info on regex tracking',
                :params => [:id])
        add_sig(:sig => 'track list(\s\S+)?', :method => :list, :desc => 'List currently tracked regex', :params => [:channel])
        add_sig(:sig => 'track add (.+)', :method => :add, :desc => 'Add new regex for tracking',
                :params => [:regex], :group => track)
        add_sig(:sig => 'track remove (\d+)', :method => :remove, :desc => 'Remove regex from tracking',
                :params => [:id], :group => track)
        add_sig(:sig => 'track modify (\d+) (.+)', :method => :modify, :desc => 'Modify regex',
                :params => [:id, :regex], :group => track)
        Helpers.load_message(:incoming, :Privmsg)
        @pipeline.hook(self, :check, ModSpox::Messages::Incoming::Privmsg)
        TrackInfo.create_table unless TrackInfo.table_exists?
        @cache = {}
        build_cache
    end
    
    def check(message)
        return unless @cache.has_key?(message.target.pk.to_i)
        time = Time.now
        @cache[message.target.pk.to_i].each do |t|
            if(message.message =~ /#{t[:regex]}/)
                ti = TrackInfo[t[:id]]
                if(ti.last_score.year != time.year || ti.last_score.yday != time.yday)
                    ti.score_today = 0
                end
                ti.last_score = Time.now
                ti.score_today += 1
                ti.score_total += 1
                ti.save
            end
        end
    end
    
    def list(message, params)
        output = ''
        begin
            raise 'No channel given for list' if message.is_private? && !params[:channel]
            channel = params[:channel] ? Helpers.find_model(params[:channel].strip, false) : message.target
            if(TrackInfo.filter(:channel_id => channel.pk).count > 0)
                output = []
                output << "\2Currently tracked regexs in #{channel.name}"
                TrackInfo.filter(:channel_id => channel.pk).each do |t|
                    output << "\2ID:\2 #{t.pk} --- \2REGEX:\2 #{t.regex}"
                end
            else
                output = 'Error: Nothing is currently being tracked'
            end
        rescue Object => boom
            output = "Error: #{boom}"
        ensure
            reply message.replyto, output
        end
    end
    
    def add(message, params)
        output = ''
        begin
            r = Regexp.new(params[:regex])
            t = TrackInfo.new
            t.regex = params[:regex]
            t.channel = message.target
            t.last_score = Time.now
            t.save
            build_cache
            output = "New regex has been added for tracking (ID: #{t.pk})"
        rescue Object => boom
            output = "Failed to save regex: #{boom}"
        ensure
            reply message.replyto, output
        end
    end
    
    def remove(message, params)
        id = params[:id].to_i
        tis = TrackInfo.filter(:id => id)
        if(tis.count > 0)
            tis.destroy
            build_cache
            reply message.replyto, "Regex has been removed (ID: #{id})"
        else
            reply message.replyto, "Failed to find regex being tracked with ID: #{id}"
        end
    end
    
    def modify(message, params)
        id = params[:id].to_i
        tis = TrackInfo.filter(:id => id)
        output = ''
        begin
            r = Regexp.new(params[:regex])
            if(tis.count > 0)
                t = tis.first
                t.regex = params[:regex]
                t.save
                build_cache
                output = "Regex has been update (ID: #{t.pk})"
            else
                output = "Failed to locate tracking regex (ID: #{id})"
            end
        rescue Object => boom
            output = "Failed to save regex. #{boom}"
        ensure
            reply message.replyto, output
        end
    end
    
    def score(message, params)
        id = params[:id].to_i
        t = TrackInfo.filter(:id => id).first
        if(t)
            reply message.replyto, "\2(#{id})\2: Regex: #{t.regex}, Today: #{t.score_today}, Total: #{t.score_total}, Last occurance: #{t.last_score}"
        else
            reply message.replyto, "Failed to find tracking regex with ID: #{id}"
        end
    end
    
    def build_cache
        @cache = {}
        TrackInfo.all.each do |t|
            @cache[t.channel_id.to_i] = [] unless @cache.has_key?(t.channel_id.to_i)
            @cache[t.channel_id.to_i] << {:id => t.pk, :regex => t.regex}
        end
    end
    
    class TrackInfo < Sequel::Model
        many_to_one :channel, :class => ModSpox::Models::Channel
        
        def channel=(chan)
            raise Exceptions::InvalidType.new('Channel model was expected') unless chan.is_a?(Models::Channel)
            values[:channel_id] = chan.pk
        end
        
        def regex=(r)
            r = [Marshal.dump(r)].pack('m')
            super(r)
        end
        
        def regex
            values[:regex] ? Marshal.load(values[:regex].unpack('m')[0]) : nil
        end
    end

end