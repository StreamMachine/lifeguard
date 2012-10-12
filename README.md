===
    ,---.   ,---.    .---. .---..-. .-,---.       ,-.   ,-,---,---.  ,--,  .-. .-. .--. ,---.  ,'|"\   
    | .-.\  | .-'   ( .-._( .-. | | | | .-'       | |   |(| .-| .-'.' .'   | | | |/ /\ \| .-.\ | |\ \  
    | `-'/  | `-.  (_) \ (_)| | | | | | `-____.___| |   (_| `-| `-.|  |  __| | | / /__\ | `-'/ | | \ \ 
    |   (   | .-'  _  \ \ | ||\ | | | | .-`----===| |   | | .-| .-'\  \ ( _| | | |  __  |   (  | |  \ \
    | |\ \  |  `--( `-'  )\ `-\\| `-')|  `--.     | `--.| | | |  `--\  `-) | `-')| |  |)| |\ \ /(|`-' /
    |_| \)\ /( __.'`----'  `---\`---(_/( __.'     |( __.`-)\| /( __.)\____/`---(_|_|  (_|_| \)(__)`--' 
        (__(__)                      (__)         (_)    (__)(__)  (__)                     (__)       
===

resque-lifeguard launches and monitors resque-pool processes for a Rails app, 
restarting the pool when a new code version is deployed.

Optionally, resque-lifeguard can also connect to a campfire room and mention 
pool restarts there.

## Usage

If you want to use the campfire integration, you need to define these environment 
variables:

* `CAMPFIRE_ACCOUNT`
* `CAMPFIRE_TOKEN`
* `CAMPFIRE_ROOM`

To run resque-lifeguard:

    /path/to/resque-lifeguard /app/dir "bundle exec resque-pool -E production"
    
First argument is the app directory (which must contain `tmp/restart.txt`). Second argument is the command to run.

If you want to install the resque-lifeguard script somewhere in your path, do it via a symlink:

    ln -s /path/to/resque-lifeguard/resque-lifeguard /usr/local/bin/resque-lifeguard
    
## Who?

resque-lifeguard is written by Eric Richardson <erichardson@emcien.com> for [Emcien](http://emcien.com).