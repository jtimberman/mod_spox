require 'mod_spox/plugin'
require 'mod_spox/bot'
require 'splib'

Splib.load :code_reloader, :constants, :monitor


module ModSpox
  # Manages plugins for mod_spox
  class PluginManager

    # Hash of plugin instances and modules
    attr_reader :plugins

    # Plugin specific timer
    attr_reader :timer

    # bot:: Bot instance
    # Create a new plugin manager
    # :nodoc:
    # {:PluginName => {:module => Module(containing constants), :plugin => Plugin instance}}
    def initialize(bot)
      unless(bot.is_a?(Bot))
        raise ArgumentError.new("Expecting type Bot. Received type #{bot.class}")
      end
      @bot = bot
      @plugins = {}
      @lock = Splib::Monitor.new
      @timer = ActionTimer::Timer.new(:pool => @bot.pool)
      load_builtins
    end

    # args:: Arguments for loading ({:gem => gem_name} or {:file => path})
    # Loads the plugin with the given name
    def load_plugin(args = {})
      plugs = []
      if(args[:gem])
        require args[:gem]
        plugs = create_gem_plugins
      elsif(args[:file])
        plugs = load_plugins_in(args[:file])
      else
        raise ArgumentError.new 'Only :file or :gem types allowed'
      end
      plugs
    end

    # name:: Name of plugin
    # Unloads the plugin with the given name
    def unload_plugin(name)
      name = name.to_sym
      if(@plugins[name])
        @plugins[name][:plugin].destroy
        @bot.pipeline.unhook(@plugins[name][:plugin])
        @plugins.delete(name)
      else
        raise NameError.new "No plugin found with name: #{name}"
      end
      true
    end

    # name:: Name of plugin (or :all to reload all plugins)
    # Reloads single or all plugins
    def reload_plugin(name = :all)
      name = name.to_sym
      plugs = []
      Logger.debug "Requested reload of: #{name}"
      if(name == :all)
        pls = []
        Logger.debug 'Reloading all plugins'
        @plugins.keys.each do |name|
          path = @plugins[name][:module] ? @plugins[name][:module].path : nil
          unload_plugin(name)
          plugs = path ? load_plugin(:file => path) : load_plugin(:gem => name)
        end
      else
        raise NameError.new "No plugin found with name: #{name}" unless @plugins[name]
        Logger.debug "Reloading plugin: #{name}"
        path = @plugins[name][:module] ? @plugins[name][:module].path : nil
        unload_plugin(name)
        plugs = path ? load_plugin(:file => path) : load_plugin(:gem => name)
      end
      @bot.pipeline << Messages::PluginReload
      plugs
    end

    # Returns listing of all available plugins
    def find_plugins
      {:files => find_local_plugins,
        :gems => find_gem_plugins}
    end

    private

    # Loads all builtin plugins
    def load_builtins
      Dir.glob(File.dirname(__FILE__)+'/plugins/*.rb').each do |file|
        load_plugin(:file => file)
      end
      create_non_module_plugins
    end

    # Instantiates any plugins found in the ModSpox::Plugins namespace
    # that do not already exist. Returns array of plugin constants
    # created.
    def create_non_module_plugins
      plugs = []
      if(defined?(ModSpox::Plugins))
        @lock.synchronize do
          plugs = ModSpox::Plugins.constants.map{|x|
            ModSpox::Plugins.const_get(x)}.find_all{|x|
              x < ModSpox::Plugin && !@plugins.has_key?(x)}
          plugs.each do |pl|
            @plugins[pl.to_s.split('::').last.to_sym] = {:module => nil, :plugin => pl.new(@bot, @timer, self)}
            Logger.debug("Intialized new plugin: #{pl}")
          end
        end
      end
      plugs
    end

    # file:: Path to file
    # Load all plugins within given file
    def load_plugins_in(file)
      Logger.debug "Requested plugin load at: #{file}"
      plugs = []
      @lock.synchronize do
        if(File.exists?(file))
          mod = Splib.load_code(file)
          con = mod.const_get(:ModSpox)
          con = con.const_get(:Plugins) if con
          if(con)
            plugs = con.constants.map{|x|con.const_get(x)}.find_all{|x|x < ModSpox::Plugin}
            plugs.each do |pl|
              @plugins[pl.to_s.split('::').last.to_sym] = {:module => mod, :plugin => pl.new(@bot, @timer, self)}
              Logger.info "New plugin loaded: #{pl}"
            end
          end
        else
          raise ArgumentError.new 'File does not exist'
        end
      end
      plugs
    end

    # Returns a list of all plugins found in local gem list
    def find_gem_plugins
      gems = []
      begin
        require 'rubygems'
        dep = Gem::Dependency.new /^mod_spox_plugin/, nil
        gems = Gem.source_index.search(dep)
      rescue LoadError
        # ignore
      end
      gems
    end

    # Find all local plugins in config directory
    def find_local_plugins
      files = []
      if(File.exists?("#{ModSpox.config_dir}/plugins") && File.directory?("#{ModSpox.config_dir}/plugins"))
        Dir.glob("#{ModSpox.config_dir}/plugins/*.rb"){|x| files << x}
      end
      files
    end
  end
end