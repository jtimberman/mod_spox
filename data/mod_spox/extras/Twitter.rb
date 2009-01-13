class Twitter < ModSpox::Plugin

    def initialize(pipeline)
        super
        begin
            require 'twitter'
            Object::Twitter::Client.configure do |conf|
                conf.user_agent = 'mod_spox twitter for twits'
                conf.application_name = 'mod_spox IRC bot'
                conf.application_version = "#{$BOTVERSION} (#{$BOTCODENAME})"
                conf.application_url = 'http://rubyforge.org/projects/mod_spox'
            end
        rescue Object => boom
            Logger.warn("Failed to load Twitter4R. Install gem to use Twitter plugin. (#{boom})")
            raise Exceptions::BotException.new('Failed to locate required gem: Twitter4R')
        end
        twitter = Models::Group.find_or_create(:name => 'twitter')
        admin = Models::Group.find_or_create(:name => 'admin')
        add_sig(:sig => 'tweet (.+)', :method => :tweet, :group => twitter, :desc => 'Send a tweet', :params => [:message])
        add_sig(:sig => 'twitter auth( (\S+) (\S+))?', :method => :auth, :group => admin, :desc => 'Set/view authentication information',
                :params => [:info, :username, :password], :req => 'private')
        add_sig(:sig => 'twitter followers( \S+)?', :method => :followers, :desc => 'Show followers', :params => [:twit])
        add_sig(:sig => 'twitter friends( \S+)?', :method => :friends, :desc => 'Show friends', :params => [:twit])
        add_sig(:sig => 'twitter friend (\S+)', :method => :add_friend, :desc => 'Add a friend', :params => [:twit], :group => admin)
        add_sig(:sig => 'twitter unfriend (\S+)', :method => :remove_friend, :desc => 'Remove a friend', :params => [:twit], :group => admin)
        add_sig(:sig => 'twitter info', :method => :info, :desc => 'Show twitter info')
        add_sig(:sig => 'twat (\S+) (.+)', :method => :twat, :group => twitter, :desc => 'Send a direct tweet to twit', :params => [:twit, :message])
        add_sig(:sig => 'tweets( \d+)', :method => :tweets, :desc => 'Get a given message or the current message', :params => [:m_id])
        add_sig(:sig => 'autotweets ?(on|off)?', :method => :auto_tweets, :desc => 'Turn on/off auto tweet for a channel', :params => [:action],
                :group => admin, :req => 'public')
        add_sig(:sig => 'autotweets interval( \d+)?', :method => :auto_tweets_interval, :desc => 'Set/show interval for auto tweet checks',
                :group => admin, :params => [:interval])
        @auth_info = Models::Setting.find_or_create(:name => 'twitter').value
        @twitter = Object::Twitter::Client.new
        unless(@auth_info.is_a?(Hash))
            @auth_info = {:username => nil, :password => nil, :interval => 0, :channels => []}
        else
            connect if @twitter.authenticate?(@auth_info[:username], @auth_info[:password])
        end
        @last_check = Time.now
        check_timeline if @auth_info[:interval] > 0
        @running = false
    end
    
    def info(m, params)
        unless(@auth_info[:username].nil?)
            information m.replyto, "http://twitter.com/#{@auth_info[:username]}"
        else
            warning m.replyto, 'currently not configured'
        end
    end
    
    def auto_tweets_interval(m, params)
        int = params[:interval].strip.to_i
        @auth_info[:interval] = int
        save_info
        check_timeline unless @running
        information m.replyto, "auto tweet interval updated to: #{int > 0 ? int : 'stopped'}"
    end
    
    def auto_tweets(m, params)
        if(params[:active])
            on = @auth_info[:channels].include?(m.target.id)
            if(params[:active] == 'on')
                if(on)
                    warning m.replyto, 'this channel is already enabled for auto tweets'
                else
                    @auth_info[:channels] << m.target.id
                    save_info
                    check_timeline unless @running
                    information m.replyto, 'auto tweets are now enabled for this channel'
                end
            else
                if(on)
                    @auth_info[:channels].delete(m.target.id)
                    save_info
                    information m.replyto, 'auto tweets are now disabled for this channel'
                else
                    warning m.replyto, 'this channel is not currently enabled for auto tweets'
                end
            end
        else
            information m.replyto, "auto tweets currently enabled in: #{@auth_info[:channels].size > 0 ? @auth_info[:channels].map{|i| Models::Channel[i].name}.join(', ') : 'not enabled'}"
        end
    end
    
    def auth(m, params)
        if(params[:info])
            begin
                @auth_info[:username] = params[:username]
                @auth_info[:password] = params[:password]
                @twitter.authenticate?(params[:username], params[:password])
                save_info
                information m.replyto, 'Authentication information has been updated'
            rescue Object => boom
                error m.replyto, "Failed to save authentication information: #{boom}"
            end
        else
            information m.replyto, "username -> #{@auth_info[:username].nil? ? 'unset' : @auth_info[:username]} password -> #{@auth_info[:password].nil? ? 'unset' : @auth_info[:password]}"
        end
    end
    
    def tweet(m, params)
        begin
            @twitter.status(:post, params[:message])
            information m.replyto, 'tweet has been sent'
        rescue Object => boom
            error m.replyto, "failed to send tweet. (#{boom})"
        end
    end
    
    def twat(m, params)
        begin
            user = @twitter.user(params[:twit])
            @twitter.message(:post, params[:message], user)
            information m.replyto, 'tweet has been sent'
        rescue Object => boom
            error m.replyto, "failed to send tweet. (#{boom})"
        end
    end
    
    def followers(m, params)
        begin
            fs = @twitter.my(:followers)
            if(fs.size > 0)
                reply m.replyto, "\2Followers:\2 #{fs.map{|u| u.screen_name}.join(', ')}"
            else
                warning m.replyto, 'no followers found'
            end
        rescue Object => boom
            error m.replyto, "failed to locate followers list. (#{boom})"
        end
    end
    
    def friends(m, params)
        begin
            fs = @twitter.my(:friends)
            if(fs.size > 0)
                reply m.replyto, "\2Friends:\2 #{fs.map{|u| u.screen_name}.join(', ')}"
            else
                warning m.replyto, 'no friends found'
            end
        rescue Object => boom
            error m.replyto, "failed to locate friends list. (#{boom})"
        end
    end
    
    def add_friend(m, params)
        begin
            user = @twitter.user(params[:twit])
            unless(@twitter.my(:friends).include?(user))
                @twitter.friend(:add, user)
                information m.replyto, "added new friend: #{params[:twit]}"
            else
                warning m.replyto, "#{params[:twit]} is already in friend list"
            end
        rescue Object => boom
            error m.replyto, "failed to add friend #{params[:twit]}. (#{boom})"
        end
    end
    
    def remove_friend(m, params)
        begin
            user = @twitter.user(params[:twit])
            if(@twitter.my(:friends).map{|u|u.screen_name}.include?(user.screen_name))
                @twitter.friend(:remove, user)
                information m.replyto, "removed user from friend list: #{params[:twit]}"
            else
                warning m.replyto, "#{params[:twit]} is not in friend list"
            end
        rescue Object => boom
            error m.replyto, "failed to remove friend #{params[:twit]}. (#{boom})"
        end
    end
    
    private
    
    def check_timeline
        if(@auth_info[:channels].size < 1 || @auth_info[:interval].to_i < 1)
            @running = false
        else
            @running = true
            @twitter.timeline_for(:me, :since => @last_check) do |status|
                @auth_info[:channels].each{|i| reply Models::Channel[i], "\2AutoTweet:\2 #{status.user.screen_name} -> #{status.text}"}
            end
            @last_check = Time.now
            @pipeline << Messages::Internal::TimerAdd.new(self, @auth_info[:interval].to_i, nil, true){ check_timeline }
        end
    end
    
    def information(to, message)
        reply to, "\2Twitter (info):\2 #{message}"
    end
    
    def warning(to, message)
        reply to, "\2Twitter (warn):\2 #{message}"
    end
    
    def error(to, message)
        reply to, "\2Twitter (error):\2 #{message}"
    end
    
    def save_info
        i = Models::Setting.find_or_create(:name => 'twitter')
        i.value = @auth_info
        i.save
    end
    
    def connect
        @twitter.login = @auth_info[:username]
        @twitter.password = @auth_info[:password]
    end

end