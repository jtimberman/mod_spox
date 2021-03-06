require 'mod_spox/handlers/Handler'
require 'mod_spox/messages/incoming/Who'
module ModSpox
    module Handlers
        class Who < Handler
            def initialize(handlers)
                handlers[RFC[:RPL_WHOREPLY][:value]] = self
                handlers[RFC[:RPL_ENDOFWHO][:value]] = self
                @cache = Hash.new
                @raw_cache = Hash.new
            end
            # :host 352 spox #mod_spox ~pizza_ 12.229.112.195 punch.va.us.dal.net pizza_ H@ :5 pizza_
            def process(string)
                string = string.dup
                orig = string.dup
                begin
                    until(string.slice(0..RFC[:RPL_WHOREPLY][:value].size-1) == RFC[:RPL_WHOREPLY][:value] || string.slice(0..RFC[:RPL_ENDOFWHO][:value].size-1) == RFC[:RPL_ENDOFWHO][:value])
                        string.slice!(0..string.index(' '))
                    end
                    if(string.slice(0..RFC[:RPL_WHOREPLY][:value].size-1) == RFC[:RPL_WHOREPLY][:value])
                        2.times{string.slice!(0..string.index(' '))}
                        location = string.slice!(0..string.index(' ')-1)
                        string.slice!(0)
                        username = string.slice!(0..string.index(' ')-1)
                        string.slice!(0)
                        host = string.slice!(0..string.index(' ')-1)
                        string.slice!(0)
                        server = string.slice!(0..string.index(' ')-1)
                        string.slice!(0)
                        nick = find_model(string.slice!(0..string.index(' ')-1))
                        string.slice!(0)
                        info = string.slice!(0..string.index(' ')-1)
                        string.slice!(0..string.index(':'))
                        hops = string.slice!(0..string.index(' ')-1)
                        string.slice!(0)
                        realname = string
                        location = nil if location == '*'
                        nick.username = username
                        nick.address = location
                        nick.real_name = realname
                        nick.connected_to = server
                        nick.away = !info.index('G').nil?
                        nick.add_channel(find_model(location)) unless location.nil?
                        nick.save_changes
                        key = location.nil? ? nick.nick : location
                        @cache[key] = Array.new unless @cache[key]
                        @cache[key] << nick
                        @raw_cache[key] = Array.new unless @raw_cache[key]
                        @raw_cache[key] << orig
                        unless(location.nil?)
                            channel = find_model(location)
                            channel.add_nick(nick)
                            if(info.include?('+'))
                                m = Models::NickMode.find_or_create(:channel_id => channel.pk, :nick_id => nick.pk)
                                m.set_mode('v')
                            elsif(info.include?('@'))
                                m = Models::NickMode.find_or_create(:channel_id => channel.pk, :nick_id => nick.pk)
                                m.set_mode('o')
                            else
                                m = Models::NickMode.find_or_create(:channel_id => channel.pk, :nick_id => nick.pk)
                                m.clear_modes
                            end
                        end
                        return nil
                    else
                        2.times{string.slice!(0..string.index(' '))}
                        location = string.slice!(0..string.index(' ')-1)
                        loc = find_model(location)
                        @raw_cache[location] << orig
                        message = Messages::Incoming::Who.new(@raw_cache[location].join("\n"), loc, @cache[location])
                        @raw_cache.delete(location)
                        @cache.delete(location)
                        return message
                    end
                rescue Object => boom
                    Logger.error("Failed to match WHO type message: #{orig}")
                    raise Exceptions::GeneralException.new(boom)
                end
            end
            
        end
    end
end