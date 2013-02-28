console.log "Welcome to #{ process.pid }.  I don't like dying."

timeout = null

handleSig = ->
  if timeout
    console.log "I laugh at your Signal"
  else
    console.log "In a minute..."
    timeout = setTimeout ->
      console.log "Going away."
      process.exit()
    , 60 * 1000
    
process.on 'SIGINT', handleSig
process.on 'SIGQUIT', handleSig
process.on 'SIGTERM', handleSig
    
setInterval ->
  console.log "#{process.pid} still living."
, 2000