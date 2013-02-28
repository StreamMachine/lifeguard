forever = require "forever-monitor"
campfire = (require "campfire").Campfire
fs = require "fs"
path = require "path"
exec = require('child_process').exec

module.exports = class Lifeguard
  constructor: (@dir,@cmd,@name) ->
    @instance = null
    
    @name = @cmd if !@name
        
    # start our new process
    @_restartInstance()
    
    # set a friendly title
    process.title = "lifeguard for #{@dir} : #{@name}"
    
    @campfire = false
    @campfire_room = false
    @campfire_queue = []
    
    if process.env.CAMPFIRE_ACCOUNT && process.env.CAMPFIRE_TOKEN && process.env.CAMPFIRE_ROOM
      @campfire = new campfire 
        account:  process.env.CAMPFIRE_ACCOUNT
        token:    process.env.CAMPFIRE_TOKEN
        ssl:      true

      @campfire.join process.env.CAMPFIRE_ROOM, (err,room) =>
        @campfire_room = room
        
        for msg in @campfire_queue
          @campfire_room.speak msg
          
        @campfire_queue = []
        
    # if we get a HUP, pass it through to our instance
    process.on "SIGHUP", => process.kill @instance.child.pid, "SIGHUP"
        
    process.on "SIGTERM", =>
        # need to shut down instance, but do it gracefully
        process.kill @instance.child.pid, "SIGINT"
            
    # set up watcher on tmp/restart.txt
    # it needs to exist for us to watch it...
        
    @watcher = fs.watchFile "#{@dir}/tmp/restart.txt", => 
      # only restart on a touch, not on a deletion (such as when current/ is unlinked)
      @_restartInstance() if fs.existsSync("#{@dir}/tmp/restart.txt")

  #----------
  
  _restartInstance: ->
    if @instance
      # INT will gracefully shut down workers and immediately kill the manager
      process.kill @instance.child.pid, "SIGINT"
      @instance.forceStop = true
      @_ensureDeathOf @instance.child.pid
    
    rdir = path.resolve @dir  
    @instance = new (forever.Monitor) @cmd.split(" "), cwd: @dir
    @instance.start()  
    
    @instance.on "start", => @_notifyRestart()
    @instance.on "restart", => @_notifyRestart()
  
  #----------
  
  _notify: (msg) ->
    msg = "Lifeguard: #{@name} @ #{@dir} — #{msg}"
    
    if @campfire
      if @campfire_room
        @campfire_room.speak msg
      else
        @campfire_queue.push msg
        
    else
      console.log msg
    
  _notifyRestart: ->
    @_notify "Restarted at #{new Date}"
  
  #----------
        
  _ensureDeathOf: (pid,wait = 3) ->
    # every so often, this pid may not want to die. We want 
    # it to die.
    
    setTimeout =>
      # is it still alive?
      cmd = "kill -0 #{pid}"
      
      child = exec cmd, (err,stdout,stderr) =>
        if err
          # PID can't be signalled.  should mean it is stopped
          
        else
          # PID is running.
          if wait > 0
            # circle again...
            @_notify "Old process #{pid} still alive... "
            @_ensureDeathOf pid, wait - 1
          else
            # we're done waiting... kill -9
            process.kill pid, "SIGKILL"
            
            # we'll give it one more check
            setTimeout =>
              exec cmd, (err,stdout,stderr) =>
                if err
                  # we're good
                  @_notify "Old process #{pid} successfully killed via -9."
                  
                else
                  # need to notify that it wouldn't die...
                  @_notify "PID #{pid} refuses to die."
                  
            , 5000
      
    , 5000
    