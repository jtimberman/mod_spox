module ModSpox
    module Exceptions

        class BotException < Exception
        end

        class GeneralException < Exception
            attr_reader :original
            def initialize(o)
                @original = o
            end
            def to_s
                @original.to_s
            end
        end
        
        class NotImplemented < BotException
        end
    
        class InvalidType < BotException
        end
        
        class InvalidValue < BotException
        end
        
        class AlreadyRunning < BotException
        end
        
        class NotRunning < BotException
        end
        
        class UnknownKey < BotException
        end
        
        class InstallationError < BotException
        end
        
        class LockedObject < BotException
        end
        
        class TimerInUse < BotException
        end
        
        class EmptyQueue < BotException
        end

        class Disconnected < BotException
        end

        class HandlerNotFound < BotException
            attr_reader :message_type
            def initialize(type)
                @message_type = type
            end
        end

        class NotInChannel < BotException
            attr_reader :channel
            def initialize(channel)
                @channel = channel
            end
            def to_s
                "Bot is not currently in channel: #{@channel}"
            end
        end

        class QuietChannel < BotException
            attr_reader :channel
            def initialize(channel)
                @channel = channel
            end
            def to_s
                "Bot is not allowed to speak in channel: #{@channel}"
            end
        end

        class PluginMissing < BotException
        end

        class PluginFileNotFound < BotException
        end

    end
end