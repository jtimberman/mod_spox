module ModSpox
    module Messages
        module Outgoing
            class Privmsg
                # target for the message
                attr_reader :target
                # the message
                attr_reader :message
                # target:: target for the message
                # message:: message to be sent
                # Send a message to user or channel
                def initialize(target, message)
                    @target = target
                    @message = message
                end
            end
        end
    end
end