forever = require "forever-monitor"
fs      = require "fs"
path    = require "path"
exec    = require('child_process').exec

module.exports = class Lifeguard extends require("events").EventEmitter
  constructor: () ->
    @argv = require("optimist")
        .usage("Usage: $0 --dir [dir] --cmd [cmd]")
        .alias
          t:  "title"
          d:  "dir"
          c:  "cmd"
        .boolean("handoff")
        .demand('cmd')
        .describe
          dir:      "Directory to watch for tmp/restart.txt"
          cmd:      "Command to run"
          title:    "Title for the process if monitoring to Campfire"
          handoff:  "Process should use managed handoff when restarting (node scripts only)?"
        .argv
        
    @cmd = @argv.cmd
    @name = @argv.title
      
    @instance = null
    
    # keep track of how many times we've started
    @startCount = 0
    
    @name = @cmd if !@name
    
    # -- Validate arguments -- #

    if @argv.dir
      @dir = @argv.dir
      @dir = path.resolve(@dir)
    
    # create a debounced function for calling restart, so that we don't 
    # trigger multiple times in a row.  This would just be _.debounce, 
    # but bringing underscore in for one thing seemed silly
    
    @debounceRestart = do =>
      _timeout = null
      _ts = 1000
      
      =>
        clearTimeout(_timeout)
        _timeout = setTimeout =>
          _timeout = null
          @_restartInstance()
        , _ts
    
    # -- Startup -- #
        
    # set a friendly title
    process.title = "lifeguard:#{@name}"
    
    if process.env.CAMPFIRE_ACCOUNT && process.env.CAMPFIRE_TOKEN && process.env.CAMPFIRE_ROOM
      @campfire = new Lifeguard.Campfire @,
        account:  process.env.CAMPFIRE_ACCOUNT
        token:    process.env.CAMPFIRE_TOKEN
        room:     process.env.CAMPFIRE_ROOM
        
    # if we get a HUP, pass it through to our instance
    process.on "SIGHUP", => 
      process.kill @instance.child.pid, "SIGHUP" if @instance
    
    # SIGUSR2 triggers a restart (mostly for development)
    process.on "SIGUSR2", => @_restartInstance()
        
    process.on "SIGTERM", => @_shutDown()
          
    #process.on "uncaughtException", (err) => @_shutDown(err)
    #process.on "uncaughtException", (err) =>
    #  console.error "Error is ", err
    #  process.exit()
              
    if @dir
      # start our new process, if the app directory exists.  if it doesn't, just 
      # watch and wait
      @_watchForDir path.resolve(@dir,"tmp/restart.txt"), => @_startUp()
    else
      # just start up
      @_restartInstance()

  #----------
  
  _shutDown: ->
    @_notify "Lifeguard got TERM signal. Shutting down."
    
    # need to shut down instance, but do it gracefully
    @instance.forceStop = true
    process.kill @instance.child.pid, "SIGINT"
    
    @instance.on "exit", =>
        @_notify "Child process has exited."
        process.exit() 
  
  # If our entire path doesn't yet exist, walk backward until we find the 
  # longest part that does. watch that directory for the next step in the 
  # tree to appear
  
  _watchForDir: (target,cb) ->
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
            
    lFunc target, (existing) =>
      if existing == target
        console.log "Starting up!"
        cb?()
        
      else
        @_pollForDir target, existing, cb
  
  #----------
  
  _pollForDir: (target,existing,cb) ->
    # we got here because not all of our target path exists.  Sometimes that's 
    # accurate -- the app is still deploying, etc. Sometimes, though, it 
    # actually snapped into place in between the point where we checked and 
    # the point where we start watching for changes.  We'll watch what we 
    # found (existing), but also set up an interval to poll for the full path.
    
    # -- Watch existing -- #
    
    @dwatcher = fs.watch existing, (type,filename) =>
      # on any change, just stop our watcher and try again
      @dwatcher.close()
      clearInterval _pInt if _pInt
      @_watchForDir target, cb
    
    # -- Poll the full target -- #
    
    _pInt = setInterval =>
      fs.exists target, (exists) =>
        if exists
          # target acquired...
          @dwatcher.close()
          clearInterval _pInt if _pInt
          cb?()
    , 1000
          
  #----------
  
  _startUp: ->
    # there are two things we need to be watching for:
    # 1) a change event on tmp/restart.txt
    # 2) a change to the symlinked current that is @dir
    
    # close any existing watchers that got left around
    @r_watcher?.close()
    @d_watcher?.close()
    
    # set up a watcher on tmp/restart.txt
    @r_watcher = fs.watch path.resolve(@dir,"tmp/restart.txt"), (type,filename) => 
      # only restart on a touch, not on a deletion (such as when current/ is unlinked)
      @debounceRestart() if fs.existsSync("#{@dir}/tmp/restart.txt")
      
    # watch for our directory to change out from under us
    d_base = path.basename(@dir)
    @d_watcher = fs.watch path.resolve(@dir,".."), (type,filename) =>
      if filename == d_base
        # we need to start over.  the directory is changing.
        @r_watcher.close()
        @d_watcher.close()
        
        @_watchForDir path.resolve(@dir,"tmp/restart.txt"), => @_startUp()
  
    @debounceRestart()
    
  #----------
  
  _restartInstance: ->
    @_handleOldInstance(@instance) if @instance
    
    args = {}
    start_cmd = @cmd.split(" ")
    
    if @dir
      rdir = path.resolve @dir
      args.cwd = rdir
    
    if @argv.handoff
      # for handoffs, we need to start using child_process.fork to get IPC
      
      if @startCount > 0
        # we need to add the handoff flag
        start_cmd.push "--handoff"
      
      else
        # first start... no handoff flag
          
      args.fork = true
          
    console.log "Running #{start_cmd} with ", args
    @instance = new (forever.Monitor) start_cmd, args
    @instance.start()
      
    @instance.once "start", => @emit "instance", @instance
    
    # increment our start count
    @startCount += 1
    
    @instance.on "start", => @_notifyRestart()
    @instance.on "restart", => @_notifyRestart()
  
  #----------
  
  _handleOldInstance: (old_instance) ->
    if @argv.handoff
      # We're in handoff mode, which means we're brokering a shutdown / startup 
      # for the old and new processes.
      
      # Old process gets a SIGUSR2 to put it into handoff mode.  
      # New process gets a --handoff argument
            
      # tell forever not to restart the old instance when it stops
      old_instance.forceStop = true
      
      # watch for the new instance
      @once "instance", (new_instance) =>
        # send SIGUSR2 to start the process
        process.kill old_instance.child.pid, "SIGUSR2"
        
        handles = []
        
        # proxy messages between old and new
        oToN = (msg,handle) =>
          console.log "LIFEGUARD: oToN ", msg, handle?
          
          if handle && handle.destroyed
            # lost a handle mid-flight...
            new_instance.child.send msg
          else
            new_instance.child.send msg, handle
            handles.push handle if handle?
          
        nToO = (msg,handle) =>
          console.log "LIFEGUARD: nToO ", msg, handle?
          
          if handle && handle.destroyed
            # lost a handle mid-flight...
            old_instance.child.send msg
          else
            old_instance.child.send msg, handle
            handles.push handle if handle?
          
        old_instance.child.on "message", oToN
        new_instance.child.on "message", nToO
        
        # watch for the old instance to die
        old_instance.child.on "exit", =>
          # detach our proxies
          new_instance.child.removeListener "message", nToO
          console.log "Handoff done."
          
          for h in handles
            h.close?()
      
    else
      # INT will gracefully shut down workers and immediately kill the manager
      process.kill old_instance.child.pid, "SIGINT"
      old_instance.forceStop = true
      @_ensureDeathOf old_instance.child.pid
  
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
        console.error "Campfire error: ", err
        
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
            @campfire_room.speak msg, (err) =>
              # ok
          
          @campfire_queue = []
        
        # -- monitor for notifies -- #
      
        @lifeguard.on "notify", (msg) =>
          if @campfire_room
            @campfire_room.speak msg, (err) =>
              # ok
          else
            @campfire_queue.push msg
      
      
    