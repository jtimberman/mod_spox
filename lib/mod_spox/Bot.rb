module ModSpox

    class Bot
    
        # bot timer
        attr_reader :timer
        
        # message pipeline
        attr_reader :pipeline
        
        # plugin manager
        attr_reader :plugin_manager
        
        # message factory
        attr_reader :factory
    
        # Create a Bot
        def initialize
            Logger.severity($VERBOSITY)
            Logger.fd
            clean_models
            @start_time = Time.now
            @pipeline = Pipeline.new
            @timer = Timer.new(@pipeline)
            @config = BaseConfig.new(BotConfig[:userconfigpath])
            @factory = MessageFactory.new(@pipeline)
            @socket = nil
            @plugin_manager = PluginManager.new(@pipeline)
            @shutdown = false
            @socket = nil
            @nick = nil
            @thread = Thread.current
            hook_pipeline
        end
        
        # Run the bot
        def run
            trap('SIGTERM'){ Logger.log("Caught SIGTERM"); Thread.current.exit }
            trap('SIGKILL'){ Logger.log("Caught SIGKILL"); Thread.current.exit }
            trap('SIGINT'){ Logger.log("Caught SIGINT"); Thread.current.exit }
            trap('SIGQUIT'){ Logger.log("Caught SIGQUIT"); Thread.current.exit }
            until @shutdown do
                @timer.start
                @pipeline << Messages::Internal::BotInitialized.new
                begin
                    Thread.stop
                rescue Object => boom
                    Logger.log("Caught exception: #{boom}")
                end
                shutdown
            end
        end
        
        # Shut the bot down
        def shutdown
            @shutdown = true
            @plugin_manager.destroy_plugins
            @thread.run
            @timer.stop
            @timer.destroy
            @factory.destroy
            @pipeline << Messages::Internal::Shutdown.new
            sleep(0.1)
            @pipeline.destroy
            @socket.shutdown unless @socket.nil?
            clean_models
        end
        
        # Reload the bot (basically a restart)
        def reload
            @thread.run
        end
        
        # message:: Messages::Internal::EstablishConnection message
        # Initialize connection to IRC server
        def bot_connect(message)
            Logger.log("Received a connection command", 10)
            begin
                @socket = Socket.new(self, message.server, message.port)
                @socket.connect
                @pipeline << Messages::Internal::Connected.new(message.server, message.port)
            rescue Object => boom
                Logger.log("Failed connection to server: #{boom}")
                @pipeline << Messages::Internal::ConnectionFailed.new(message.server, message.port)
            end
        end
        
        # message:: Messages::Internal::StatusRequest message
        # Returns the current status of the bot
        def status(message)
            @pipeline << Messages::Internal::StatusResponse(message.requester, stats)
        end
        
        # Returns status of the bot in a formatted string
        def stats
            return ["Uptime: #{Helpers::format_seconds(@start_time - Time.now)}",
                    "Plugins: #{@plugins.plugins.size} loaded",
                    "Lines sent: #{@socket.sent}",
                    "Lines received: #{@socket.received}"].join(' ')
        end
        
        # Adds hooks to pipeline for processing messages
        def hook_pipeline
            {:Outgoing_Admin => :admin, :Outgoing_Away => :away,
             :Outgoing_ChannelMode => :chanmode, :Outgoing_Connect => :connect,
             :Outgoing_Die => :die, :Outgoing_Info => :info,
             :Outgoing_Invite => :invite, :Outgoing_Ison => :ison,
             :Outgoing_Join => :join, :Outgoing_Kick => :kick,
             :Outgoing_Kill => :kill, :Outgoing_Links => :links,
             :Outgoing_List => :list, :Outgoing_Lusers => :lusers,
             :Outgoing_Motd => :motd, :Outgoing_Names => :names,
             :Outgoing_Nick => :nick, :Outgoing_Notice => :notice,
             :Outgoing_Oper => :oper, :Outgoing_Part => :part,
             :Outgoing_Pass => :pass, :Outgoing_Ping => :ping,
             :Outgoing_Pong => :pong, :Outgoing_Privmsg => :privmsg,
             :Outgoing_Quit => :quit, :Outgoing_Rehash => :rehash,
             :Outgoing_ServList => :servlist, :Outgoing_Squery => :squery,
             :Outgoing_Squit => :squit, :Outgoing_Stats => :stats,
             :Outgoing_Summon => :summon, :Outgoing_Time => :time,
             :Outgoing_Topic => :topic, :Outgoing_Trace => :trace,
             :Outgoing_Unaway => :unaway, :Outgoing_User => :user,
             :Outgoing_UserHost => :userhost, :Outgoing_UserMode => :usermode,
             :Outgoing_Users => :users, :Outgoing_Version => :version,
             :Outgoing_Who => :who, :Outgoing_WhoWas => :whowas,
             :Outgoing_Whois => :whois, :Internal_EstablishConnection => :bot_connect,
             :Internal_StatusRequest => :status, :Internal_ChangeNick => :set_nick,
             :Internal_NickRequest => :get_nick, :Internal_HaltBot => :halt,
             :Internal_Disconnected => :disconnected, :Internal_TimerClear => :clear_timer
             }.each_pair{ |type,method| @pipeline.hook(self, method, type) }
        end
        
        # message:: Messages::Internal::TimerClear
        # Clear all actions from timer
        def clear_timer(message)
            @timer.clear
        end
        
        # message:: Messages::Internal::Disconnected
        # Disconnect the bot from the IRC server
        def disconnected(message)
            @socket.shutdown
            @socket = nil
        end
        
        # Stop the bot
        def halt(message)
            @shutdown = true
            @thread.run
        end
        
        # message:: Messages::Internal::ChangeNick message
        # Changes the bot's nick to the given nick
        def set_nick(message)
            @nick = message.new_nick
        end
        
        # message:: Messages::Internal::NickRequest
        # Sends the bot's nick to plugins
        def get_nick(message)
            @pipeline << Messages::Internal::NickResponse(message.requester, @nick)
        end
        
        # message:: Messages::Outgoing::Pass message
        # Sends PASS message to server
        def pass(message)
            @socket << "PASS #{message.password}"
        end
        
        # message:: Messages::Outgoing::Nick message
        # Sends NICK message to server        
        def nick(message)
            nick = message.nick.is_a?(Models::Nick) ? message.nick.nick : message.nick
            @socket << "NICK #{nick}"
        end

        # message:: Messages::Outgoing::User message
        # Sends USER message to server
        def user(message)
            @socket << "USER #{message.username} #{message.mode} * :#{message.real_name}"
        end

        # message:: Messages::Outgoing::Oper message
        # Sends Oper message to server
        def oper(message)
            @socket << "OPER #{message.name} #{message.password}"
        end

        # message:: Messages::Outgoing::UserMode message
        # Sends MODE message to server
        def user_mode(message)
            raise Exceptions::InvalidValue.new('Mode must be in the form of: [+-][a-z]+') unless message.mode =~ /^[+\-][a-z]+$/
            nick = message.nick.is_a?(Models::Nick) ? message.nick.nick : message.nick
            @socket << "MODE #{nick} #{message.mode}"
        end

        # message:: Messages::Outgoing::Quit message
        # Sends QUIT message to server
        def quit(message)
            @socket << "QUIT :#{message.message}"
        end
        
        # message:: Messages::Outgoing::Squit message
        # Sends SQUIT message to server
        def squit(message)
            @socket << "SQUIT #{message.server} :#{message.comment}"
        end

        # message:: Messages::Outgoing::Join message
        # Sends JOIN message to server
        def join(message)
            channel = message.channel.is_a?(Models::Channel) ? message.channel.name : message.channel
            @socket << "JOIN #{channel} #{message.key}"
        end

        # message:: Messages::Outgoing::Part message
        # Sends PART message to server
        def part(message)
            channel = message.channel.is_a?(Models::Channel) ? message.channel.name : message.channel
            @socket << "PART #{channel} :#{message.reason}"
        end

        # message:: Messages::Outgoing::ChannelMode message
        # Sends MODE message to server
        def channel_mode(message)
            target = message.target
            channel = message.channel
            target = target.nick if target.is_a?(Models::Nick)
            channel = channel.name if channel.is_a?(Models::Channel)
            @socket << "MODE #{channel} #{message.mode} #{target}"
        end
        
        # message:: Messages::Outgoing::Topic message
        # Sends TOPIC message to server
        def topic(message)
            channel = message.channel.is_a?(Models::Channel) ? message.channel.name : message.channel
            @socket << "TOPIC #{channel} :#{message.topic}"
        end

        # message:: Messages::Outgoing::Names message
        # Sends NAMES message to server
        def names(message)
            channel = message.channel.is_a?(Models::Channel) ? message.channel.name : message.channel
            @socket << "NAMES #{channel} #{message.target}"
        end

        # message:: Messages::Outgoing::List message
        # Sends LIST message to server
        def list(message)
            channel = message.channel.is_a?(Models::Channel) ? message.channel.name : message.channel
            @socket << "LIST #{channel}"
        end
        
        # message:: Messages::Outgoing::Invite message
        # Sends INVITE message to server
        def invite(message)
            nick = message.nick.is_a?(Models::Nick) ? message.nick.nick : message.nick
            channel = message.channel.is_a?(Models::Channel) ? message.channel.name : message.channel
            @socket << "INVITE #{nick} #{channel}"
        end
       
        # message:: Messages::Outgoing::Kick message
        # Sends KICK message to server
        def kick(message)
            nick = message.nick.is_a?(Models::Nick) ? message.nick.nick : message.nick
            channel = message.channel.is_a?(Models::Channel) ? message.channel.name : message.channel
            @socket << "KICK #{channel} #{nick} :#{message.reason}"
        end

        # message:: Messages::Outgoing::Privmsg message
        # Sends PRIVMSG message to server
        def privmsg(message)
            target = message.target.name if message.target.is_a?(Models::Channel)
            target = message.target.nick if message.target.is_a?(Models::Nick)
            target = message.target unless target
            @socket << "PRIVMSG #{target} :#{message.message}"
        end

        # message:: Messages::Outgoing::Notice message
        # Sends NOTICE message to server
        def notice(message)
            target = message.target.name if message.target.is_a?(Models::Channel)
            target = message.target.nick if message.target.is_a?(Models::Nick)
            @socket << "NOTICE #{target} :#{message}"
        end
        
        # message:: Messages::Outgoing::Motd message
        # Sends MOTD message to server
        def motd(message)
            @socket << "MOTD #{message.target}"
        end
        
        # message:: Messages::Outgoing::Lusers message
        # Sends LUSERS message to server
        def lusers(message)
            @socket << "LUSERS #{message.mask} #{message.target}"
        end

        # message:: Messages::Outgoing::Version message
        # Sends VERSION message to server
        def version(message)
            @socket << "VERSION #{message.target}"
        end
        
        # message:: Messages::Outgoing::Stats message
        # Sends STATS message to server
        def stats(message)
            raise Exceptions::InvalidValue.new('Query must be a single character') unless message.query =~ /^[a-z]$/
            @socket << "STATS #{message.query} #{message.target}"
        end
        
        # message:: Messages::Outgoing::Links message
        # Sends LINKS message to server
        def links(message)
            @socket << "LIST #{message.server} #{message.mask}"
        end
        
        # message:: Messages::Outgoing::Time message
        # Sends TIME message to server
        def time(message)
            @socket << "TIME #{message.target}"
        end

        # message:: Messages::Outgoing::Connect message
        # Sends CONNECT message to server
        def connect(message)
            @socket << "CONNECT #{message.target_server} #{message.port} #{message.remote_server}"
        end

        # message:: Messages::Outgoing::Trace message
        # Sends TRACE message to server
        def trace(message)
            @socket << "TRACE #{message.target}"
        end

        # message:: Messages::Outgoing::Admin message
        # Sends ADMIN message to server
        def admin(message)
            @socket << "ADMIN #{message.target}"
        end

        # message:: Messages::Outgoing::Info message
        # Sends INFO message to server
        def info(message)
            @socket << "INFO #{message.target}"
        end
        
        # message:: Messages::Outgoing::ServList message
        # Sends SERVLIST message to server
        def servlist(message)
            @socket << "SERVLIST #{message.mask} #{message.type}"
        end

        # message:: Messages::Outgoing::Squery message
        # Sends SQUERY message to server
        def squery(message)
            @socket << "SQUERY #{message.service_name} #{message.message}"
        end

        # message:: Messages::Outgoing::Who message
        # Sends WHO message to server
        def who(message)
            o = message.only_ops ? 'o' : ''
            @socket << "WHO #{message.mask} #{o}"
        end

        # message:: Messages::Outgoing::Whois message
        # Sends WHOIS message to server
        def whois(message)
            nick = message.nick.is_a?(Models::Nick) ? message.nick.nick : message.nick
            @socket << "WHOIS #{message.target_server} #{nick}"
        end
        
        # message:: Messages::Outgoing::WhoWas message
        # Sends WHOWAS message to server
        def whowas(message)
            nick = message.nick.is_a?(Models::Nick) ? message.nick.nick : message.nick
            @socket << "WHOWAS #{message.nick} #{message.count} #{message.target}"
        end

        # message:: Messages::Outgoing::Kill message
        # Sends KILL message to server
        def kill(message)
            nick = message.nick.is_a?(Models::Nick) ? message.nick.nick : message.nick
            @socket << "KILL #{nick} :#{message.comment}"
        end

        # message:: Messages::Outgoing::Ping message
        # Sends PING message to server
        def ping(message)
            @socket << "PING #{message.message}"
        end

        # message:: Messages::Outgoing::Pong message
        # Sends PONG message to server
        def pong(message)
            @socket << "PONG #{message.server} #{message.string.nil? ? '' : ":#{message.string}"}"
        end
        
        # message:: Messages::Outgoing::Away message
        # Sends AWAY message to server
        def away(message)
            @socket << "AWAY :#{message.message}"
        end
        
        # message:: Messages::Outgoing::Unaway message
        # Sends AWAY message to server
        def unaway(message)
            @socket << "AWAY"
        end
        
        # message:: Messages::Outgoing::Rehash message
        # Sends REHASH message to server
        def rehash(message)
            @socket << "REHASH"
        end
        
        # message:: Messages::Outgoing::Die message
        # Sends DIE message to server
        def die(message)
            @socket << "DIE"
        end

        # message:: Messages::Outgoing::Restart message
        # Sends RESTART message to server
        def restart(message)
            @socket << "RESTART"
        end

        # message:: Messages::Outgoing::Summon message
        # Sends SUMMON message to server
        def summon(message)
            nick = message.nick.is_a?(Models::Nick) ? message.nick.nick : message.nick
            channel = message.channel.is_a?(Models::Channel) ? message.channel.name : message.channel
            @socket << "SUMMON #{nick} #{message.target} #{channel}"
        end
        
        # message:: Messages::Outgoing::Users message
        # Sends USERS message to server
        def users(message)
            @socket << "USERS #{message.target}"
        end
        
        def wallops
        end

        # message:: Messages::Outgoing::UserHost message
        # Sends USERHOST message to server
        def userhost(message)
            nick = message.nick.is_a?(Models::Nick) ? message.nick.nick : message.nick
            @socket << "USERHOST #{nick}"
        end

        # message:: Messages::Outgoing::Ison message
        # Sends ISON message to server
        def ison(message)
            nick = message.nick.is_a?(Models::Nick) ? message.nick.nick : message.nick
            @socket << "ISON #{nick}"
        end 
        
        private
        
        # Cleans information from models to avoid
        # stale values
        def clean_models
            Models::Nick.clean
            Models::Channel.clean
            Models::NickChannel.destroy_all
            Models::Signature.delete_all
        end
    end

end