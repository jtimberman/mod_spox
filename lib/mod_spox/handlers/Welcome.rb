require 'mod_spox/handlers/Handler'
module ModSpox
    module Handlers
        class Welcome < Handler
            def initialize(handlers)
                handlers[RPL_WELCOME] = self
            end
            
            def process(string)
                if(string =~ /:(\S+)\s(\S+).+?(\S+)$/)
                    server = $1
                    message = $2
                    userstring = $3
                    if(userstring =~ /^(.+?)!(.+?)@(.+?)$/)
                        Models::Nick.filter(:botnick => true).each{|n| n.botnick = false; n.save}
                        nick = $1
                        username = $2
                        hostname = $3
                        nick = Models::Nick.locate(nick)
                        nick.botnick = true
                        nick.username = username
                        nick.address = hostname
                        nick.source = userstring
                        nick.save
                        return Messages::Incoming::Welcome.new(string, server, message, nick, username, hostname)
                    else
                        Logger.warn('Failed to match user string in welcome message')
                        return nil
                    end
                else
                    Logger.warn('Failed to match welcome message')
                    return nil
                end
            end
        end
    end
end