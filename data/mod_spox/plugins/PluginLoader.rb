class PluginLoader < ModSpox::Plugin

    def initialize(pipeline)
        super(pipeline)
        admin = Models::Group.filter(:name => 'admin').first
        Models::Signature.find_or_create(:signature => 'plugins available', :plugin => name, :method => 'available_plugins',
            :group_id => admin.pk, :description => 'List all available plugins')
        Models::Signature.find_or_create(:signature => 'plugins loaded', :plugin => name, :method => 'loaded_plugins',
            :group_id => admin.pk, :description => 'List all plugins currently loaded')
        Models::Signature.find_or_create(:signature => 'plugins load (\S+)', :plugin => name, :method => 'load_plugin',
            :group_id => admin.pk, :description => 'Load the given plugin').params = [:plugin]
        Models::Signature.find_or_create(:signature => 'plugins unload (\S+)', :plugin => name, :method => 'unload_plugin',
            :group_id => admin.pk, :description => 'Unload given plugin').params = [:plugin]
        Models::Signature.find_or_create(:signature => 'plugins reload', :plugin => name, :method => 'reload_plugin',
            :group_id => admin.pk, :description => 'Reload plugins')
        @pipeline.hook(self, :get_module, :Internal_PluginModuleResponse)
        @plugins_mod = nil
    end
    
    # message:: ModSpox::Messages::Incoming::Privmsg
    # params:: matching signature params
    # Output currently available plugins for loading
    def available_plugins(message, params)
        @pipeline << Messages::Outgoing::Privmsg.new(message.source.nick, "\2Currently available plugins:\2")
        find_plugins.each_pair do | plugin, path |
            @pipeline << Messages::Outgoing::Privmsg.new(message.source.nick, "\2#{plugin}:\2 #{path}")
        end
    end
    
    # message:: ModSpox::Messages::Incoming::Privmsg
    # params:: matching signature params
    # Output currently loaded plugins
    def loaded_plugins(message, params)
        @pipeline << Messages::Outgoing::Privmsg.new(message.source.nick, "\2Currently loaded plugins:\2 #{plugin_list.join(', ')}")
    end
    # message:: ModSpox::Messages::Incoming::Privmsg
    # params:: matching signature params
    # Load the given plugin
    def load_plugin(message, params)
        plugins = find_plugins
        if(plugins.has_key?(params[:plugin]))
            name = plugin_discovery(BotConfig[:pluginextraspath]).keys.include?(params[:plugin]) ? nil : "#{params[:plugin]}.rb"
            @pipeline << Messages::Internal::PluginLoadRequest.new(self, plugins[params[:plugin]], name)
            @pipeline << Messages::Outgoing::Privmsg.new(message.source.nick, "Okay")
        else
            @pipeline << Messages::Outgoing::Privmsg.new(message.source.nick, "Failed to find plugin: #{params[:plugin]}")
        end
    end
    
    # message:: ModSpox::Messages::Incoming::Privmsg
    # params:: matching signature params
    # Unload the given plugin
    def unload_plugin(message, params)
        path = loaded_path(params[:plugin])
        unless(path.nil?)
            name = plugin_discovery(BotConfig[:pluginextraspath]).keys.include?(params[:plugin]) ? nil : ".#{params[:plugin]}.rb"
            @pipeline << Messages::Internal::PluginUnloadRequest.new(self, path, name)
            @pipeline << Messages::Outgoing::Privmsg.new(message.source.nick, "Okay")
        else
            @pipeline << Messages::Outgoing::Privmsg.new(message.source.nick, "Failed to find loaded plugin named: #{params[:plugin]}")
        end
    end
    
    # message:: ModSpox::Messages::Incoming::Privmsg
    # params:: matching signature params
    # Reloads plugins    
    def reload_plugin(message, params)
        @pipeline << Messages::Internal::PluginReload.new
        @pipeline << Messages::Outgoing::Privmsg.new(message.source.nick, 'Okay')
    end
    
    # message:: ModSpox::Messages::Internal::PluginModuleResponse
    # Receives the plugins module
    def get_module(message)
        @plugins_mod = message.module
    end

    private
    
    # Returns the list of currently loaded plugins
    def plugin_list
        plug = []
        @pipeline << Messages::Internal::PluginModuleRequest.new(self)
        sleep(0.01) while @plugins_mod.nil?
        @plugins_mod.constants.sort.each do |const|
            klass = @plugins_mod.const_get(const)
            if(klass < Plugin)
                plug << const
            end
        end
        @plugins_mod = nil
        return plug
    end
    
    # Finds available plugins for loading
    def find_plugins
        users = plugin_discovery(BotConfig[:userpluginpath])
        extras = plugin_discovery(BotConfig[:pluginextraspath])
        plugins = users.merge(extras)
        plugin_list.each do |name|
            plugins.delete(name) if plugins.has_key?(name)
        end
        return plugins
    end
    
    # path:: path to directory
    # Discovers any plugins within the files in the given path
    def plugin_discovery(path)
        plugins = Hash.new
        Dir.new(path).each do |file|
            next unless file =~ /\.rb$/
            sandbox = Module.new
            sandbox.module_eval(IO.readlines("#{path}/#{file}").join("\n"))
            sandbox.constants.each do |const|
                klass = sandbox.const_get(const)
                plugins[const] = "#{path}/#{file}" if klass < Plugin
            end
        end
        return plugins
    end
    
    # name:: plugin name
    # Returns the file path the given plugin originated from
    def loaded_path(name)
        Dir.new(BotConfig[:userpluginpath]).each do |file|
            next unless file =~ /\.rb$/
            sandbox = Module.new
            sandbox.module_eval(IO.readlines("#{BotConfig[:userpluginpath]}/#{file}").join("\n"))
            sandbox.constants.each do |const|
                return "#{BotConfig[:userpluginpath]}/#{file}" if const == name
            end
        end
        return nil
    end

end