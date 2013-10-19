===
    ,-.    ,-.,---.,---.   ,--,   .-. .-.  .--.  ,---.   ,'|"\   
    | |    |(|| .-'| .-' .' .'    | | | | / /\ \ | .-.\  | |\ \  
    | |    (_)| `-.| `-. |  |  __ | | | |/ /__\ \| `-'/  | | \ \ 
    | |    | || .-'| .-' \  \ ( _)| | | ||  __  ||   (   | |  \ \
    | `--. | || |  |  `--.\  `-) )| `-')|| |  |)|| |\ \  /(|`-' /
    |( __.'`-')\|  /( __.')\____/ `---(_)|_|  (_)|_| \)\(__)`--' 
    (_)      (__) (__)   (__)                        (__)            
===

lifeguard is yet-another-process-launcher, but with a few extra tricks up its 
sleeve.  It was designed to run processes that accompany apps that are deployed 
via [Capistrano](http://www.capistranorb.com/), so it supports watching for 
changes to `tmp/restart.txt`.  It also supports being started up before the 
process it is configured to run has been deployed, allowing it to be provisioned 
as a service before the app deployment.

Optionally, lifeguard can also connect to a campfire room and mention restarts there.

## Usage

If you want to use the campfire integration, you need to define these environment 
variables:

* `CAMPFIRE_ACCOUNT`
* `CAMPFIRE_TOKEN`
* `CAMPFIRE_ROOM`

To run lifeguard:

    lifeguard --dir /app/dir/current --cmd "bundle exec resque-pool -E production" --title "ResquePool-production"
	
Arguments:

* `--dir`: Tells lifeguard what directory to watch for a tmp/restart.txt 
    file.  If specified, lifeguard will not run the command until 
	{dir}/tmp/restart.txt exists. 
	
* `--cmd`: The command lifeguard should run. If `--dir` was specified, working 
	directory will be changed before starting.
	
* `--title`: Lifeguard will use title in Campfire notifications and will set 
	the process title to "lifeguard:{title}"
	
* `--handoff`: For Node.js apps, lifeguard can run in a special mode that allows 
	live handoffs between old and new instances, allowing them to transfer state 
	and listening sockets.  For more, see the 
	[StreamMachine](http://github.com/StreamMachine/StreamMachine) project.
    
## Installing

You can install lifeguard globally via npm:

	npm install -g lifeguard
    
## Handoffs

Lifeguard can coordinate with a compatible Node.js application to allow 
seamless restarts that pass existing connections over to the new process.

_More documentation to come._
    
## Who?

lifeguard is written by Eric Richardson <erichardson@emcien.com> for [Emcien](http://emcien.com).