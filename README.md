===
    ,-.    ,-.,---.,---.   ,--,   .-. .-.  .--.  ,---.   ,'|"\   
    | |    |(|| .-'| .-' .' .'    | | | | / /\ \ | .-.\  | |\ \  
    | |    (_)| `-.| `-. |  |  __ | | | |/ /__\ \| `-'/  | | \ \ 
    | |    | || .-'| .-' \  \ ( _)| | | ||  __  ||   (   | |  \ \
    | `--. | || |  |  `--.\  `-) )| `-')|| |  |)|| |\ \  /(|`-' /
    |( __.'`-')\|  /( __.')\____/ `---(_)|_|  (_)|_| \)\(__)`--' 
    (_)      (__) (__)   (__)                        (__)            
===

lifeguard launches and monitors processes for a web app, restarting the pool when a new code version is deployed.

Optionally, lifeguard can also connect to a campfire room and mention restarts there.

## Usage

If you want to use the campfire integration, you need to define these environment 
variables:

* `CAMPFIRE_ACCOUNT`
* `CAMPFIRE_TOKEN`
* `CAMPFIRE_ROOM`

To run lifeguard:

    /path/to/lifeguard /app/dir "bundle exec resque-pool -E production" "Optional Title"
    
First argument is the app directory (which must contain `tmp/restart.txt`). Second argument is the command to run. 
Third argument is an optional title, which will be used in Campfire restart notices.  If it isn't specified, the 
command argument will be used as a title instead.

If you want to install the lifeguard script somewhere in your path, do it via a symlink:

    ln -s /path/to/lifeguard/lifeguard /usr/local/bin/lifeguard
    
You can let npm do that automatically by installing with:

    npm install -g git://github.com/emcien/lifeguard.git
    
## Who?

lifeguard is written by Eric Richardson <erichardson@emcien.com> for [Emcien](http://emcien.com).