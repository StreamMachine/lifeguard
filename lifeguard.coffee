forever = require "forever-monitor"
campfire = (require "campfire").Campfire
fs = require "fs"

module.exports = class Lifeguard
  constructor: (@dir,@cmd) ->
    @instance = null
        
    # start our new process
    @_restartInstance()
    
    # set a friendly title
    process.title = "resque-lifeguard for #{@dir}"
    
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
        
    @watcher = fs.watchFile "#{@dir}/tmp/restart.txt", => @_restartInstance()

  #----------
  
  _restartInstance: ->
    if @instance
      # INT will gracefully shut down workers and immediately kill the manager
      process.kill @instance.child.pid, "SIGINT"
      @instance.forceStop = true
      
    @instance = new (forever.Monitor) @cmd.split(" "), cwd: @dir
    @instance.start()  
    
    @instance.on "start", => @_notifyRestart()
    @instance.on "restart", => @_notifyRestart()
    
  _notifyRestart: ->
    if @campfire
      msg = "Lifeguard: restarted resque-pool in #{@dir} at #{new Date}"
      
      if @campfire_room
        # send directly
        @campfire_room.speak msg
      else
        @campfire_queue.push msg
    