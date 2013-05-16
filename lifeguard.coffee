forever = require "forever-monitor"
fs      = require "fs"
path    = require "path"
exec    = require('child_process').exec

module.exports = class Lifeguard extends require("events").EventEmitter
  constructor: (@dir,@cmd,@name) ->
    @instance = null
    
    @name = @cmd if !@name
    
    # -- Validate arguments -- #
    
    if !@dir || !@cmd
      console.error "Usage: lifeguard <dir> <command> <name (optional)>"
      process.exit()
      
    @dir = path.resolve(@dir)
    
    # -- Startup -- #
        
    # set a friendly title
    process.title = "lifeguard for #{@dir} : #{@name}"
    
    if process.env.CAMPFIRE_ACCOUNT && process.env.CAMPFIRE_TOKEN && process.env.CAMPFIRE_ROOM
      @campfire = new Lifeguard.Campfire @,
        account:  process.env.CAMPFIRE_ACCOUNT
        token:    process.env.CAMPFIRE_TOKEN
        room:     process.env.CAMPFIRE_ROOM
        
    # if we get a HUP, pass it through to our instance
    process.on "SIGHUP", => process.kill @instance.child.pid, "SIGHUP"
        
    process.on "SIGTERM", =>
      # need to shut down instance, but do it gracefully
      process.kill @instance.child.pid, "SIGINT"
            
    # start our new process, if the app directory exists.  if it doesn't, just 
    # watch and wait
    @_watchForDir path.resolve(@dir,"tmp/restart.txt"), => @_startUp()

  #----------
  
  # If our entire path doesn't yet exist, walk backward until we find the 
  # longest part that does. watch that directory for the next step in the 
  # tree to appear
  
  _watchForDir: (dir,cb) ->
    console.log "watchForDir trying #{dir}"
    # loop our way up until we find something that exists    
    lFunc = (d,lcb) =>
      # test this
      fs.exists d, (exists) =>
        if exists
          lcb?(d)
        else
          if d == "/"
            @_notify "Failed to find a directory to watch."
          else
            d = path.resolve d, ".."
            lFunc(d,lcb)
            
    lFunc dir, (existing) =>
      console.log "_watchForDir pass came out with #{existing}"
      if existing == dir
        console.log "Starting up!"
        cb?()
        
      else
        @dwatcher = fs.watch existing, (type,filename) =>
          # on any change, just stop our watcher and try again
          @dwatcher.close()
          @_watchForDir dir, cb
  
  #----------
  
  _startUp: ->
    # there are two things we need to be watching for:
    # 1) a change event on tmp/restart.txt
    # 2) a change to the symlinked current that is @dir
    
    # set up a watcher on tmp/restart.txt
    @r_watcher = fs.watch path.resolve(@dir,"tmp/restart.txt"), (type,filename) => 
      # only restart on a touch, not on a deletion (such as when current/ is unlinked)
      @_restartInstance() if fs.existsSync("#{@dir}/tmp/restart.txt")
      
    # watch for our directory to change out from under us
    d_base = path.basename(@dir)
    @d_watcher = fs.watch path.resolve(@dir,".."), (type,filename) =>
      if filename == d_base
        # we need to start over.  the directory is changing.
        @r_watcher.close()
        @d_watcher.close()
        
        @_watchForDir path.resolve(@dir,"tmp/restart.txt"), => @_startUp()
  
    @_restartInstance()
    
  #----------
  
  _restartInstance: ->
    if @instance
      # INT will gracefully shut down workers and immediately kill the manager
      process.kill @instance.child.pid, "SIGINT"
      @instance.forceStop = true
      @_ensureDeathOf @instance.child.pid
    
    rdir = path.resolve @dir  
    @instance = new (forever.Monitor) @cmd.split(" "), cwd:rdir
    @instance.start()  
    
    @instance.on "start", => @_notifyRestart()
    @instance.on "restart", => @_notifyRestart()
  
  #----------
  
  _notify: (msg) ->
    msg = "Lifeguard: #{@name} @ #{@dir} — #{msg}"
    
    @emit "notify", msg

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
  
  #----------
  
  class @Campfire
    constructor: (@lifeguard,@opts) ->
      @d = require("domain").create()
      
      @d.on "error", (err) =>
        if err.code == "ECONNRESET"
          # ignore
        else
          console.log "Campfire error: ", err
        
      @d.run =>      
        Campfire = (require "campfire").Campfire
      
        @campfire_room = false
        @campfire_queue = []
    
        @campfire = new Campfire 
          account:  @opts.account
          token:    @opts.token
          ssl:      true

        @campfire.join @opts.room, (err,room) =>
          @campfire_room = room
        
          for msg in @campfire_queue
            @campfire_room.speak msg
          
          @campfire_queue = []
        
        # -- monitor for notifies -- #
      
        @lifeguard.on "notify", (msg) =>
          if @campfire_room
            @campfire_room.speak msg
          else
            @campfire_queue.push msg
      
      
    