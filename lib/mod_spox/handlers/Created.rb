module ModSpox
    module Handlers
        class Created < Handler
            def initialize(handlers)
                handlers[RPL_CREATED] = self
            end
            def process(string)
                if(string =~ /#{RPL_CREATED.to_s}.+?:created\s(.+)$/)
                    return Messages::Incoming::Created(string, $1)
                else
                    Logger.log('Failed to parse RPL_CREATED message')
                end
            end
        end
    end
end