# IMPORTANT NOTE: This plugin will only function if the PHP executable can be located
class PhpCli < ModSpox::Plugin

    def initialize(pipeline)
        super(pipeline)
        @path = Models::Config.val(:plugin_directory) + '/phpcli'
        unless(File.directory?(@path))
            FileUtils.mkdir_p(@path)
        end
        @exec = Models::Config.val(:phpexec)
        if(@exec.nil?)
            result = Helpers.safe_exec('which php')
            raise NoInterpreter.new if result.empty?
            @exec = 'php'
        end
        ['bot.ini', 'setup.php'].each do |name|
            unless(File.exists?("#{@path}/#{name}"))
                file = File.new("#{@path}/#{name}", 'w')
                name =~ /ini/ ? file.write(ini) : file.write(setup)
                file.close
            end
        end
        php = Models::Group.find_or_create(:name => 'php')
        phpfunc = Models::Group.find_or_create(:name => 'phpfunc')
        admin = Models::Group.filter(:name => 'admin').first
        add_sig(:sig => 'php (on|off)', :method => :set_channel, :group => admin, :desc => 'Add or remove channel from allowing PHP command', :params => [:action])
        add_sig(:sig => 'php (?!on|off)(.+)', :method => :execute_php, :group => php, :desc => 'Execute PHP code', :params => [:code])
        add_sig(:sig => 'phpq (?!on|off)(.+)', :method => :quiet_php, :group => php, :params => [:code], :desc => 'Execute PHP quietly')
        add_sig(:sig => 'pf add (.+)', :method => :add, :params => [:function], :group => phpfunc, :desc => 'Add a custom PHP function')
        add_sig(:sig => 'pf remove (\S+)', :method => :remove, :params => [:name], :group => phpfunc, :desc => 'Remove a custom PHP function')
        add_sig(:sig => 'pf list', :method => :list, :desc => 'List custom PHP functions')
        add_sig(:sig => 'pf edit (.+)', :method => :edit, :params => [:function], :group => phpfunc, :desc => 'Overwrite existing custom PHP function')
        add_sig(:sig => 'pf show (\S+)', :method => :show, :params => [:name], :group => phpfunc, :desc => 'Show given PHP function source')
        add_sig(:sig => 'phpexec( (\S+))?', :method => :set_exec, :params => [:exec], :group => admin, :desc => 'Set custom PHP executable')
        @phpfuncs = nil
        @customfuncs = []
        populate_customs
        @channels = Models::Setting.filter(:name => 'phpcli').first
        @channels = @channels.nil? ? [] : @channels.value
    end

    def set_exec(m, params)
        if(params[:exec])
            path = params[:exec].strip
            unless(path == 'none')
                if(File.executable?(path))
                    Models::Config.set(:phpexec, path)
                    @exec = path
                    information m.replyto, "PHP executable path has been updated: #{@exec}"
                else
                    error m.replyto, 'Path given is not a valid executable path'
                end
            else
                Models::Config.filter(:name => 'phpexec').destroy
                @exec = 'php'
                information m.replyto, 'Bot is now using default php executable'
            end
        else
            information m.replyto, "Executable path is: #{@exec}"
        end
    end

    def set_channel(message, params)
        return unless message.is_public?
        if(params[:action] == 'on')
            unless(@channels.include?(message.target.pk))
                @channels << message.target.pk
                tmp = Models::Setting.find_or_create(:name => 'phpcli')
                tmp.value = @channels
                tmp.save
            end
            reply message.replyto, 'PHP command now active'
        else
            unless(@channels.include?(message.target.pk))
                reply message.replyto, 'PHP command is not currently active in this channel'
            else
                @channels.delete(message.target.pk)
                tmp = Models::Setting.find_or_create(:name => 'phpcli')
                tmp.value = @channels
                tmp.save
                reply message.replyto, 'PHP command is now disabled'
            end
        end
    end

    def quiet_php(message, params)
        execute_php(message, params, true)
    end

    def execute_php(message, params, shh=false)
        return unless @channels.include?(message.target.pk)
        filepath = @path + "/#{rand(99999)}.bot.php"
        file = File.open(filepath, 'w')
        file.write("<? #{@customfuncs.join(' ')} #{params[:code]} ?>")
        file.close
        begin
            output = Helpers.safe_exec("#{@exec} -c #{@path}/bot.ini -d max_execution_time=10 #{filepath} 2>&1 | head -n 4")
            if(output =~ /^sh: line [0-9]+:(.*)$/)
                output = $1
            end
            if(output =~ /^(Fatal error|Warning|Parse error): (.+?) in .*? on line [0-9]+[\n|\r]*(.*)$/)
                warning = $2
                type = $1
                output = $3
            end
            if(output.length > 300)
                reply message.replyto, "#{message.source.nick}: Your result has been truncated. Don't print so much."
                output = output.slice(0, 300)
            end
            if(!warning.nil?)
                reply message.replyto, "PHP #{type}: "+warning
            end
            if(warning.nil? || type !~ /(Fatal|Parse)/)
                reply message.replyto, "#{shh ? '' : 'Result: '}"+output
            end
            File.delete(filepath)
        rescue Timeout::Error => boom
            reply message.replyto, "\2Error:\2 Timeout reached: #{boom}"
        rescue Object => boom
            reply message.replyto, "\2Error:\2 Script execution terminated. (#{boom})"
            File.delete(filepath)
        end
    end
    
    def add(m, params)
        if(params[:function].scan(/function\s+([^\(]+)\(/).size > 1)
            error m.replyto, 'Only one function can be added at a time'
            return
        end
        if(params[:function] =~ /^function\s+([^\(]+)\(/)
            name = $1.downcase
            unless(@phpfuncs.has_key?(name))
                begin
                    parse(params[:function])
                    save(params[:function], name, m.source)
                    populate_customs
                    information m.replyto, "New function \2#{name}\2 added to custom PHP functions"
                rescue Object => boom
                    error m.replyto, "Failed to add function #{name}. Error: #{boom}"
                end
            else
                error m.replyto, "Function with name: #{name} already exists"
            end
        else
            error m.replyto, "Function is not in proper format"
        end
    end
    
    def remove(m, params)
        if(@phpfuncs.has_key?(params[:name]))
            @phpfuncs.delete(params[:name])
            save_funcs
            populate_customs
            information m.replyto, "Function \2#{name}\2 has been removed"
        else
            error m.replyto, "Failed to locate function named: #{params[:name]}"
        end
    end
    
    def list(m, params)
        if(@phpfuncs.empty?)
            output = 'No custom functions currenty registered'
        else
            output = ["\2Custom PHP functions:\2"]
            listing = []
            @phpfuncs.each_pair do |name, data|
                listing << "\2Name:\2 #{name} \2Author:\2 #{data[:nick]} \2Added:\2 #{data[:added].strftime("%Y/%m/%d-%H:%M:%S")}"
            end
            output << "[#{listing.join('] [')}]"
        end
        reply m.replyto, output
    end
    
    def edit(m, params)
        if(params[:function] =~ /^function\s+([^\(]+)\(/)
            name = $1.downcase
            begin
                parse(params[:function])
                save(params[:function], name, m.source)
                information m.replyto, "New function \2#{name}\2 added to custom PHP functions"
                populate_customs
            rescue Object => boom
                error m.replyto, "Failed to add function #{name}. Error: #{boom}"
            end
        else
            error m.replyto, "Function is not in proper format"
        end
    end
    
    def show(m, params)
        if(@phpfuncs.has_key?(params[:name]))
            reply m.replyto, ["Source for function \2#{params[:name]}\2:", @phpfuncs[params[:name]][:function]]
        else
            error m.replyto, "Failed to find custom PHP function with name: #{params[:name]}"
        end
    end
    
    def parse(func)
        filepath = @path + "/#{rand(99999)}.bot.php"
        file = File.open(filepath, 'w')
        file.write("<? #{func} ?>")
        file.close
        output = Helpers.safe_exec("php -l #{filepath} 2>&1 | head -n 4").strip.gsub(/\s{2,}/, ' ').gsub(/[\r\n]+/, ' ')
        File.delete(filepath)
        if(output =~ /(Parse error.+) in/)
            raise "#{$1}"
        end
    end
    
    def save(func, name, nick)
        raise "Function with given name already exists: #{name}" if @phpfuncs.has_key?(name)
        x = Models::Setting.find_or_create(:name => 'phpfuncs')
        @phpfuncs[name] = {:function => func, :added => Time.now, :nick => nick.nick}
        x.value = @phpfuncs
        x.save
    end

    def save_funcs
        x = Models::Setting.find_or_create(:name => 'phpfuncs')
        x.value = @phpfuncs
        x.save
    end

    def get_funcs
        x = Models::Setting.find_or_create(:name => 'phpfuncs')
        @phpfuncs = x.value
        if(@phpfuncs.nil?)
            @phpfuncs = {}
            save_funcs
        end
    end
    
    def populate_customs
        get_funcs if @phpfuncs.nil?
        @customfuncs = []
        @phpfuncs.each_pair do |name, data|
            @customfuncs << data[:function]
        end
    end

    class NoInterpreter < Exception
    end

    def setup
setup_file <<EOF
<?php
defined(E_DEPRECATED) ? error_reporting(E_ALL & ~E_DEPRECATED) : error_reporting(E_ALL);
ini_set('safe_mode', 'On');
ini_set('register_long_arrays', 'On');
ini_set('magic_quotes_gpc', 'On');
ini_set('date.timezone', 'America/Los_Angeles');
$_SERVER = $_ENV = $GLOBALS = array();
?>
EOF
        return setup_file
    end

    def ini
ini_file = <<EOF
[PHP]
engine = On
zend.ze1_compatibility_mode = Off
short_open_tag = On
asp_tags = Off
precision    =  12
y2k_compliance = On
output_buffering = Off
zlib.output_compression = Off
implicit_flush = Off
serialize_precision = 100
allow_call_time_pass_reference = On
safe_mode_gid = On
safe_mode_include_dir = #{@path}
safe_mode_exec_dir = #{@path}
safe_mode_allowed_env_vars = PHP_
safe_mode_protected_env_vars = LD_LIBRARY_PATH
open_basedir = #{@path}
disable_classes = dir
disable_functions = fscanf fputs chown chmod copy delete fflush file flock ftell glob link fseek lstat move_uploaded_file rename realpath set_file_buffer touch fprintf chgrp fgetss readfile dio_close dio_fnctl dio_open dio_read dio_seek dio_stat dio_tcsetattr dio_truncate dio_write chdir chroot dir closedir getcwd opendir readdir rewinddir scandir posix_kill posix_access posix_ctermid posix_get_last_error posix_getcwd posix_getegid posix_geteuid posix_getgid posix_getgrgid posix_getgrnam posix_getgroups posix_getlogin posix_getpgid posix_getpgrp posix_getpid posix_getppid posix_getpwnam posix_getpwuid posix_getwuid posix_getrlimit posix_getsid posix_getuid posix_isatty posix_mkfifo posix_mknod posix_setegid posix_setgid posix_setpgid posix_setsid posix_setuid posix_strerror posix_times posix_ttyname posix_uname expect_expectl expect_popen sleep time_sleep_until usleep pfsockopen fsockopen openlog debugger_on proc_open pclose popen fsockopen fread set_time_limit ini_alter ini_restore exec system passthru proc_close proc_nice proc_open proc_terminiate shell_exec sleep usleep pcntl_fork pcntl_exec pcntl_alarm pcntl_getpriority pcntl_setpriority pcntl_waitpid pcntl_wexitstatus pcntl_wifexited pcntl_wifsignaled pcntl_wifstopped pcntl_wstopsig pcntl_wtermsig readline_add_history readline_callback_handler_install readline_callback_handler_remove readline_callback_read_char readline_clear_history readline_completion_function readline_info readline_list_history readline_on_new_line readline_read_history readline_redisplay readline_write_history readline dl set_include_path set_magic_quotes_runtime file_put_contents fwrite fputs copy fputcsv tmpfile symlink tempnam mysql_connect unlink putenv ftp_connect socket_create socket_create socket_close socket_accept socket_bind socket_close socket_connect socket_create_listen socket_create_pair socket_get_option socket_listen socket_read socket_recv socket_select socket_send socket_sendto shmop_close shmop_open shmop_delete shmop_read shmop_size shmop_write msg_get_queue msg_receive msg_remove_queue msg_send msg_set_queue msg_stat_queue msg_acquire sem_aquire sem_release sem_get sem_remove mail time_nanosleep usleep include include_once require require_once ftp_alloc ftp_cdup ftp_chdir ftp_chmod ftp_close ftp_connect ftp_delete ftp_exec ftp_fget ftp_fput ftp_get ftp_get_option ftp_login ftp_mdtm ftp_mkdir ftp_nb_continue ftp_nb_fget ftp_nb_fput ftp_nb_get ftp_nb_put
expose_php = On
max_execution_time = 10
max_input_time = 20
memory_limit = 4M
error_reporting = E_ALL
display_errors = On
display_startup_errors = Off
log_errors = Off
log_errors_max_len = 1024
ignore_repeated_errors = Off
ignore_repeated_source = Off
report_memleaks = On
track_errors = Off
variables_order = "EGPCS"
register_globals = Off
register_argc_argv = On
post_max_size = 8M
magic_quotes_runtime = Off
magic_quotes_sybase = Off
default_mimetype = "text/html"
include_path = ".:/usr/share/php"
doc_root = #{@path}
user_dir = #{@path}
auto_prepend_file = #{@path}/setup.php
enable_dl = On
file_uploads = Off
allow_url_fopen = Off
default_socket_timeout = 10
define_syslog_variables  = Off
sendmail_path = /dev/null
[Sockets]
sockets.use_system_read = On
EOF
        return ini_file
    end

end
